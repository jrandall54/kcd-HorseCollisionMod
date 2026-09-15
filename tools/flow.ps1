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
	[ValidateSet("test", "branch", "land", "shipping", "status", "world")]
	[string]$Verb = "status",

	[Parameter(Position = 1)]
	[string]$Argument,

	# land only: skip the push, so the result can be looked at first.
	[switch]$NoPush,

	# test only: start the game if it is not already running.
	[switch]$Launch,

	# The testing world, which sticks to the branch until `land` clears it.
	# Anything in the settings file can be changed, including a table member,
	# so no new kind of test needs a new switch here:
	#
	#   flow.ps1 test -Preset stamina
	#   flow.ps1 test -Set CollisionIsCrime=true
	#   flow.ps1 test -Set StaminaDrainByTier.Gallop=0
	#   flow.ps1 test -Unset CollisionIsCrime
	#   flow.ps1 test -Shipped
	#
	# Presets live in tools/testworlds.ini, as data.
	[string[]]$Preset = @(),
	[string[]]$Set = @(),
	[string[]]$Unset = @(),

	# Carry no overrides at all, so the install runs the shipped values.
	[switch]$Shipped
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

# ------------------------------------------------------- test world state

# The testing world lives in tools/testworld.py, which owns `.hcm_testworld`,
# the presets in tools/testworlds.ini, and writing the override file into the
# install. This script only passes requests to it.
$script:worldTool = Join-Path $PSScriptRoot "testworld.py"

function Invoke-World {
	param ([string[]]$WorldArgs)

	& python $script:worldTool @WorldArgs 2>&1 | Out-String
}


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

	# What a test would actually be run against. Asked of the tool that writes
	# it, rather than read back out of the installed file: the world is its own
	# file now, and one source for it is the whole point.
	#
	# Printed every time because a value left on silently is what corrupts the
	# next comparison, and the rider has paid for that more than once.
	$world = (Invoke-World @("--list")).TrimEnd()

	if ($world) {
		Say "test world"

		foreach ($line in ($world -split "`r?`n")) {
			if ($line.Trim()) {
				Say "  $($line.Trim())"
			}
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

	# Anything asked for on this invocation is added to the branch's world and
	# stays there until `land` clears it. A switch given once should not
	# evaporate on the next deploy: a rider mid-test suddenly has a horse that
	# tires, and no reason to connect that to a deploy they did not run.
	$worldArgs = @()

	if ($Shipped) {
		$worldArgs += "--clear"
	}

	foreach ($name in $Preset) {
		$worldArgs += @("--preset", $name)
	}

	foreach ($pair in $Set) {
		$worldArgs += @("--set", $pair)
	}

	foreach ($key in $Unset) {
		$worldArgs += @("--unset", $key)
	}

	if ($worldArgs.Count -gt 0) {
		Write-Host (Invoke-World $worldArgs) -NoNewline
	}

	# The deploy carries no world switches any more. It writes whatever
	# `.hcm_testworld` holds, so there is nothing to splat and nothing that can
	# be dropped between here and there.
	$deployArgs = @{}

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
			# -Launch goes in the hashtable rather than beside it. Passed as a
			# bare switch in front of a splat it was accepted and did nothing:
			# the deploy ran, installed and never launched, while this script
			# said "ready to test" and the status line said the game was not
			# running. Same family as the splatting defect above, same rule.
			$launchArgs = $deployArgs.Clone()
			$launchArgs.NoBuild = $true
			$launchArgs.Launch = $true

			& $deploy @launchArgs
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

	# The world a branch starts in: the default, which is everything that can
	# interrupt a test switched off. Anything else is asked for per branch,
	# and `land` clears it again.
	Write-Host (Invoke-World @("--reset")) -NoNewline

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

	# A clean tree is a normal way to arrive here, not a failure. The work may
	# already be committed, by hand or by an earlier run that got as far as the
	# commit and no further, and in that case landing still has a merge, a tag
	# and a push to do. `git commit` exits non-zero on an empty commit, so
	# asking first is what keeps that from aborting the whole landing.
	$ErrorActionPreference = "Continue"
	& git.exe -C $repo diff --cached --quiet
	$staged = $LASTEXITCODE
	$ErrorActionPreference = "Stop"

	if ($staged -ne 0) {
		Invoke-Git commit -q -m $Argument | Out-Null
		Say "committed"
	} else {
		Say "nothing to commit, the tree is already clean"
	}

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

	Prune-Merged

	Say "landed v$version" Green

	# The branch is over, so its testing world goes with it. Without this the
	# install keeps whatever the branch was riding with and the next branch
	# inherits a world nobody chose, which is the drift that had a rider
	# wondering why their horse never tired.
	Write-Host (Invoke-World @("--reset")) -NoNewline
	Say "testing world cleared, install back to shipped values"
	& $deploy -ScriptOnly -ReleaseSettings | Out-Null

	# Deliberately not re-entering the testing world. Landing returns to main,
	# and main is the shipped world: the next branch seeds its own. Re-entering
	# here is what left main carrying a branch's test values.
	Show-Status
}

# Deletes every local branch already merged into main. This is part of landing
# rather than a separate chore: a merged branch carries no work, and leaving it
# behind turns repository tidiness into something a person has to notice and
# decide about. The rider had to ask for this three times before it was
# automated, which is the argument for automating it.
#
# `git branch --merged main` is the safe list by construction: a branch appears
# only when main already contains every one of its commits, so nothing can be
# lost. `-d` rather than `-D` keeps that guarantee even if the list is wrong.
function Prune-Merged {
	$ErrorActionPreference = "Continue"
	$merged = & git.exe -C $repo branch --merged main --format="%(refname:short)" 2>&1
	$ErrorActionPreference = "Stop"

	$gone = @($merged | Where-Object { $_ -and $_.Trim() -ne "" -and $_.Trim() -ne "main" })

	if ($gone.Count -eq 0) {
		return
	}

	foreach ($name in $gone) {
		Invoke-Git branch -d $name.Trim() | Out-Null
	}

	Say "pruned $($gone.Count) merged branch(es)"
}

# -------------------------------------------------------------- shipping

function Enter-Shipping {
	if (Game-Running) {
		Fail "the game is running and the pak cannot be moved. Quit it, then run this again."
	}

	# The testing world goes first. A shipping test carrying a branch's
	# overrides is not a shipping test, and the stray-file check below would
	# otherwise refuse the park because of a file this script wrote.
	Write-Host (Invoke-World @("--clear")) -NoNewline
	& python $script:worldTool --write $gameRoot | Out-String | Write-Host -NoNewline

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

# ----------------------------------------------------------------- world

# Change the testing world without deploying, or ask what it is.
#
# Separate from `test` because reading it should cost nothing, and because a
# world can be built up across several calls before anything is installed.
# Nothing is live until the next `test`, and this says so.
function Show-World {
	$worldArgs = @()

	if ($Shipped) {
		$worldArgs += "--clear"
	}

	foreach ($name in $Preset) {
		$worldArgs += @("--preset", $name)
	}

	foreach ($pair in $Set) {
		$worldArgs += @("--set", $pair)
	}

	foreach ($key in $Unset) {
		$worldArgs += @("--unset", $key)
	}

	if ($worldArgs.Count -eq 0) {
		$worldArgs += "--list"
	}

	Write-Host (Invoke-World $worldArgs) -NoNewline

	if ($worldArgs[0] -ne "--list") {
		Say "not installed yet. flow.ps1 test applies it."
	}

	$presetFile = Join-Path $PSScriptRoot "testworlds.ini"

	if (Test-Path $presetFile) {
		$names = @(Get-Content $presetFile |
			Select-String '^\[(\w+)\]' |
			ForEach-Object { $_.Matches[0].Groups[1].Value })

		Say "presets: $($names -join ', ')"
	}
}

switch ($Verb) {
	"status"   { Show-Status }
	"test"     { Enter-Test }
	"branch"   { Start-Branch }
	"land"     { Land }
	"shipping" { Enter-Shipping }
	"world"    { Show-World }
}
