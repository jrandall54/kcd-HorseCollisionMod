# The session's workflow, as commands rather than a sequence to remember.
#
# A session goes: read the handoff, decide what to do, start a branch, test a
# lot, land it, start the next one. Each of those states needs the install and
# the repository in a particular condition, and every one of them was previously
# a list of steps with two or three predictable failures in it. That is what
# this replaces.
#
#   .\tools\flow.ps1 test        get into, or back into, a testable state
#   .\tools\flow.ps1 branch NAME start a branch and get testable
#   .\tools\flow.ps1 land "msg"  finish: checks, version, build, tag, push
#   .\tools\flow.ps1 shipping    park the mod to test a release build
#   .\tools\flow.ps1 status      say where everything stands
#
# The verbs are idempotent. Running `test` when already testing re-syncs and
# says so rather than failing.
#
# What this does not do is decide anything. It does not choose a version, write
# a changelog entry, or judge whether the work is finished. Those are the parts
# that need a person.

param (
	[Parameter(Position = 0)]
	[ValidateSet("test", "branch", "land", "shipping", "status")]
	[string]$Verb = "status",

	[Parameter(Position = 1)]
	[string]$Argument,

	# land only: skip the push, so the result can be looked at first.
	[switch]$NoPush,

	# test only: start the game if it is not already running.
	[switch]$Launch,

	# Keep the shipping values for crime and the rest, for the rarer test that
	# is about the world's reaction rather than the collision.
	[switch]$Crime,
	[switch]$FreeGallop
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$deploy = Join-Path $PSScriptRoot "dev_deploy.ps1"
$gameRoot = "C:\Games\Kingdom Come - Deliverance"

# Git writes ordinary notices to stderr: the line-ending warning, "Switched to
# branch", the push summary. Windows PowerShell wraps any native stderr line in
# an ErrorRecord, and with ErrorActionPreference set to Stop that ends the
# script on a message that is not an error at all. So git is called through
# here, which judges the exit code and nothing else.
function Invoke-Git {
	$old = $ErrorActionPreference
	$ErrorActionPreference = "Continue"

	try {
		$out = & git.exe -C $repo @args 2>&1 | Out-String
		$code = $LASTEXITCODE
	}
	finally {
		$ErrorActionPreference = $old
	}

	if ($code -ne 0) {
		Write-Host $out
		Fail "git $($args -join ' ') failed."
	}

	return $out
}

function Say {
	param ([string]$Text, [string]$Color = "Gray")

	Write-Host "[FLOW] $Text" -ForegroundColor $Color
}

function Fail {
	param ([string]$Text)

	Write-Host "[FLOW] $Text" -ForegroundColor Red
	exit 1
}

function Game-Running {
	return [bool](Get-Process -Name "KingdomCome" -ErrorAction SilentlyContinue)
}

# Whether the install is configured for loose files, which is what every
# development deploy depends on. Reading it rather than assuming is the point:
# the install gets switched to shipping values to test a release and the switch
# back is easy to forget.
function Dev-Configured {
	$cfg = Join-Path $gameRoot "system.cfg"

	if (-not (Test-Path $cfg)) {
		return $false
	}

	$text = [System.IO.File]::ReadAllText($cfg)

	return ($text -match 'sys_PakPriority\s*=\s*0')
}

function Parked {
	return (Test-Path (Join-Path $gameRoot "hcm_dev_parked"))
}

function Current-Branch {
	return (Invoke-Git rev-parse --abbrev-ref HEAD).Trim()
}

function Working-Tree-Dirty {
	return -not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain))
}

# ---------------------------------------------------------------- status

function Show-Status {
	$branch = Current-Branch
	$dirty = Working-Tree-Dirty
	$running = Game-Running

	Say "branch      $branch$(if ($dirty) { '  (uncommitted changes)' } else { '  (clean)' })"

	$manifest = Join-Path $repo "src\mod.manifest"

	if (Test-Path $manifest) {
		# <version>4.21.0</version>, not the xml declaration's version attribute.
		$v = [regex]::Match([System.IO.File]::ReadAllText($manifest),
			'<version>([^<]+)</version>')

		if ($v.Success) {
			Say "version     $($v.Groups[1].Value)"
		}
	}

	if (Parked) {
		Say "install     SHIPPING (mod parked)" Yellow
		Say "            .\tools\flow.ps1 test  puts it back"
	}
	elseif (Dev-Configured) {
		Say "install     development"
	}
	else {
		Say "install     not configured for development" Yellow
	}

	Say "game        $(if ($running) { 'running' } else { 'not running' })"

	# What a test would actually be run against. Read off disk, because the
	# whole reason these live in the installed file is that they survive
	# reloads, and the whole reason they are printed is that a silent revert
	# costs a test.
	$settings = Join-Path $gameRoot "Data\Scripts\Startup\HorseCollisionMod_Settings.lua"

	if (Test-Path $settings) {
		$text = [System.IO.File]::ReadAllText($settings)
		$shown = @()

		# The keys come from dev_deploy.ps1's own table rather than from a
		# second copy of the list kept here.
		#
		# There were two lists, and adding Retaliation to the one that writes
		# the settings left the one that reports them unchanged, so the status
		# line said the testing world was one key smaller than it was. A status
		# line that under-reports is worse than no status line, because the
		# whole reason these are printed is that a silent revert costs a test.
		$deploySource = Join-Path $PSScriptRoot "dev_deploy.ps1"
		$keys = @()

		if (Test-Path $deploySource) {
			$deployText = [System.IO.File]::ReadAllText($deploySource)
			$block = [regex]::Match($deployText,
					'(?s)\$script:DevTestValues\s*=\s*\[ordered\]@\{(.*?)\n\}')

			if ($block.Success) {
				foreach ($entry in [regex]::Matches($block.Groups[1].Value,
						'(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=')) {
					$keys += $entry.Groups[1].Value
				}
			}
		}

		foreach ($key in $keys) {
			# Anchored to the start of a line so a key that is a prefix of a
			# longer one, or a mention inside a comment, cannot answer for it.
			$m = [regex]::Match($text, "(?m)^\s*$([regex]::Escape($key))\s*=\s*([^,\r\n]+)")

			if ($m.Success) {
				$shown += "$key=$($m.Groups[1].Value.Trim())"
			}
		}

		if ($shown.Count -gt 0) {
			Say "test world  $($shown -join ' ')"
		}
	}
}

# ------------------------------------------------------------------ test

function Enter-Test {
	# Order matters. The pak cannot be moved while the game holds it, and
	# sys_PakPriority is read at startup, so an install that needs restoring
	# needs the game closed and then restarted.
	if (Parked) {
		if (Game-Running) {
			Fail "the mod is parked for a shipping test and the game is running. Quit it, then run this again."
		}

		Say "restoring the development environment"
		& $deploy -RestoreDevEnvironment | Out-Null
	}

	if (-not (Dev-Configured)) {
		Say "switching the install to development values"
		& $deploy -SetDevEnvironment | Out-Null
	}

	# A hashtable, not an array, and not $args.
	#
	# Two separate defects lived here. $args is a PowerShell automatic variable
	# holding a function's own unbound arguments, so reassigning it inside a
	# function and splatting it dropped the switches. And splatting an **array**
	# passes its elements positionally rather than by name, so "-Crime" arrived
	# as the value of -GameRoot and the deploy exited with "-GameRoot points at
	# -Crime" -- having installed nothing, while the caller reported success.
	#
	# A hashtable splats by parameter name, which is the only form that works
	# for switches.
	$deployArgs = @{}

	if ($Crime) {
		$deployArgs.Crime = $true
	}

	# Long tests are slowed by stopping to rest, so this zeroes what a collision
	# costs the horse. Opt in rather than default: the drain is part of what an
	# impact does and hiding it would falsify a test that is measuring it.
	if ($FreeGallop) {
		$deployArgs.FreeGallop = $true
	}

	if (Game-Running) {
		# A running game holds the pak, so only the loose halves can be
		# replaced. Both, always: a script-only deploy leaving the animation
		# databases stale is silent, survives a reload, and has cost rides.
		Say "game is running, syncing loose files"
		& $deploy -ScriptOnly @deployArgs
		& $deploy -AnimOnly @deployArgs
	}
	else {
		& $deploy @deployArgs

		if ($Launch) {
			& $deploy -NoBuild -Launch @deployArgs
		}
	}

	Say "ready to test" Green
	Show-Status
}

# ---------------------------------------------------------------- branch

function Start-Branch {
	if ([string]::IsNullOrWhiteSpace($Argument)) {
		Fail "name the branch: .\tools\flow.ps1 branch fix/the-thing"
	}

	if (Working-Tree-Dirty) {
		Fail "the working tree has uncommitted changes. Land or stash them first."
	}

	$branch = Current-Branch

	if ($branch -ne "main") {
		Fail "already on $branch. One branch at a time; land it before starting another."
	}

	Invoke-Git checkout -b $Argument | Out-Null
	Say "on $Argument" Green
	Enter-Test
}

# ------------------------------------------------------------------ land

function Land {
	if ([string]::IsNullOrWhiteSpace($Argument)) {
		Fail "give a commit subject: .\tools\flow.ps1 land ""fix: the thing"""
	}

	# Documentation style first, because it is the check that fails at the
	# very end otherwise, after a version has been set and a build made. The
	# hook that enforces it runs on push; running it here turns a late refusal
	# into an early list.
	Say "checking documentation style"
	$style = python (Join-Path $repo ".claude\lint_docs.py") 2>&1 | Out-String

	if ($LASTEXITCODE -ne 0) {
		Write-Host $style
		Fail "documentation style failed. Fix the errors above, then run land again."
	}

	# The repository's claims about itself. This regenerates the API reference
	# as a side effect when it is out of date, which is why it runs before the
	# version is chosen and why anything it changes is staged below.
	Say "checking the repository against itself"
	python (Join-Path $repo "tools\pre_release_check.py") --merge | Out-String | Write-Host

	if ($LASTEXITCODE -ne 0) {
		if (Working-Tree-Dirty) {
			Say "regenerated files staged; re-running"
			Invoke-Git add -A | Out-Null
			python (Join-Path $repo "tools\pre_release_check.py") --merge | Out-String | Write-Host

			if ($LASTEXITCODE -ne 0) {
				Fail "the repository still describes a build it is not. Fix the claims above."
			}
		}
		else {
			Fail "the repository describes a build it is not. Fix the claims above."
		}
	}

	# The version follows the changelog rather than being chosen here.
	$derived = python (Join-Path $repo "tools\version_check.py") 2>&1 | Out-String
	$next = [regex]::Match($derived, '->\s*([0-9]+\.[0-9]+\.[0-9]+)')

	if (-not $next.Success) {
		Write-Host $derived
		Fail "no version could be derived. Is there an entry under ## [Unreleased] in CHANGELOG.md?"
	}

	$version = $next.Groups[1].Value
	Say "version $version, from the changelog"

	python (Join-Path $repo "tools\set_version.py") $version | Out-String | Write-Host

	Say "building"
	& (Join-Path $repo "build.ps1") -Version $version | Out-String | Write-Host

	# One retry, for the staleness the version bump itself creates.
	#
	# Setting the version rewrites the `@release` line in every source file,
	# which makes the generated API reference stale a second time, after the
	# check above has already passed. The build regenerates it and refuses, and
	# the only thing needed is to stage what it wrote and build again. Failing
	# here and handing that back is the tool creating work rather than doing it.
	if ($LASTEXITCODE -ne 0) {
		Say "build refused, staging what it regenerated and retrying"
		Invoke-Git add -A | Out-Null

		& (Join-Path $repo "build.ps1") -Version $version | Out-String | Write-Host

		if ($LASTEXITCODE -ne 0) {
			Fail "the build failed. Nothing has been committed."
		}
	}

	Invoke-Git add -A | Out-Null
	Invoke-Git commit -q -m $Argument | Out-Null
	Say "committed"

	$branch = Current-Branch

	if ($branch -ne "main") {
		Invoke-Git checkout main -q | Out-Null
		Invoke-Git merge --no-ff $branch -m "Merge $branch" -q | Out-Null
		Say "merged $branch into main"
	}

	Invoke-Git tag -a "v$version" -m "v$version" | Out-Null
	Say "tagged v$version"

	if ($NoPush) {
		Say "not pushing, as asked. Push with: git push origin main --follow-tags" Yellow
		return
	}

	$ErrorActionPreference = "Continue"
	$pushed = & git.exe -C $repo push origin main --follow-tags 2>&1 | Out-String
	$pushCode = $LASTEXITCODE
	$ErrorActionPreference = "Stop"

	Write-Host $pushed

	if ($pushCode -ne 0) {
		Fail "the push was refused. The commit, merge and tag are local; fix the report above, then push with: git push origin main --follow-tags"
	}

	if ($branch -ne "main") {
		Invoke-Git branch -d $branch | Out-Null
	}

	Say "landed v$version" Green

	# Back to a testable state, because the next thing after landing is almost
	# always testing the next thing.
	Enter-Test
}

# -------------------------------------------------------------- shipping

function Enter-Shipping {
	if (Game-Running) {
		Fail "the game is running and the pak cannot be moved. Quit it, then run this again."
	}

	& $deploy -PrepareShippingTest | Out-Null

	# The park leaves the mod's line in the load order and an empty directory
	# behind, both of which make it ambiguous whether the mod is really gone.
	$order = Join-Path $gameRoot "Mods\mod_order.txt"

	if (Test-Path $order) {
		$kept = @(Get-Content $order | Where-Object {
			$_.Trim() -ne "" -and $_ -notmatch "HorseCollisionMod"
		})

		$noBom = New-Object System.Text.UTF8Encoding($false)
		[System.IO.File]::WriteAllLines($order, [string[]]$kept, $noBom)
	}

	$stray = Join-Path $gameRoot "Data\Scripts\HorseCollisionMod"

	if ((Test-Path $stray) -and
			-not (Get-ChildItem $stray -Force -ErrorAction SilentlyContinue)) {
		Remove-Item $stray -Force
	}

	$left = @(Get-ChildItem (Join-Path $gameRoot "Data") -Recurse -Force `
		-Include "*HorseCollisionMod*", "hcm_*" -ErrorAction SilentlyContinue)

	if ($left.Count -gt 0) {
		Write-Host "[FLOW] still present under Data:" -ForegroundColor Red
		$left | ForEach-Object { Write-Host "       $($_.FullName)" }
		Fail "the mod is not fully parked, so a shipping test would not be clean."
	}

	Say "mod fully parked, install in shipping values" Green
	Say "launch the game normally. .\tools\flow.ps1 test puts it all back."
}

switch ($Verb) {
	"status"   { Show-Status }
	"test"     { Enter-Test }
	"branch"   { Start-Branch }
	"land"     { Land }
	"shipping" { Enter-Shipping }
}
