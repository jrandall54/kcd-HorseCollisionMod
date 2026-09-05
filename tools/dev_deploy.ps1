# Builds the mod and installs it straight into the game, skipping Vortex.
#
# Vortex's deploy step does one thing that matters here: it copies a pak and a
# manifest into Mods\<name>\ and lists that folder in Mods\mod_order.txt. None
# of that needs a mod manager, and doing it directly removes four manual steps
# from every test cycle.
#
#   .\tools\dev_deploy.ps1                      build, deploy
#   .\tools\dev_deploy.ps1 -Reload              push what changed into the running game
#   .\tools\dev_deploy.ps1 -Launch              build, deploy, start the game
#   .\tools\dev_deploy.ps1 -NoBuild -Launch     deploy what was built last, start the game
#   .\tools\dev_deploy.ps1 -Crime               keep riding people down a crime
#   .\tools\dev_deploy.ps1 -ParkVortexMod       move the Vortex-installed copy aside first
#   .\tools\dev_deploy.ps1 -GameRoot "D:\..."   use an install somewhere else
#   .\tools\dev_deploy.ps1 -SetDevEnvironment    switch system.cfg to development values
#   .\tools\dev_deploy.ps1 -SetPlayEnvironment   switch it back to shipping values
#   .\tools\dev_deploy.ps1 -PrepareShippingTest  park every loose file and switch to
#                                               shipping values, to test a release zip
#   .\tools\dev_deploy.ps1 -RestoreDevEnvironment   put it all back
#
# The game folder is found automatically: -GameRoot, then the KCD_PATH
# environment variable, then the usual Steam and GOG install locations.
#
# The release build for Nexus still goes through build.ps1 on its own. This is
# a development path only, and the folder it writes is never what ships.

param (
	[string]$GameRoot = "",
	[string]$Version = "",
	[switch]$NoBuild,
	[switch]$Launch,
	[switch]$ParkVortexMod,
	[switch]$NoDevMode,
	[switch]$NoLooseScript,
	[switch]$Reload,
	[switch]$ScriptOnly,
	[switch]$AnimOnly,
	[switch]$Crime,
	[switch]$SetDevEnvironment,
	[switch]$SetPlayEnvironment,
	[switch]$PrepareShippingTest,
	[switch]$RestoreDevEnvironment,
	[switch]$Force
)

$ErrorActionPreference = "Stop"

# This script lives in tools/, so the repository root is one level up. Every
# project path below is built from it rather than from the working directory,
# so the script can be run from anywhere.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Where the game is installed. Resolved rather than hardcoded, because a clone
# only works when this matches, and it matches on exactly one machine.
#
# Order: -GameRoot, then KCD_PATH in the environment, then the usual install
# locations, then every Steam library listed in libraryfolders.vdf, since a
# Steam install can sit on any drive.
function Resolve-GameRoot {
	param ([string]$Explicit)

	# An explicitly given path is authoritative. Falling through to a different
	# install when it is wrong would deploy somewhere the caller did not mean,
	# which is a far worse failure than stopping here and saying so.
	foreach ($source in @(, @("-GameRoot", $Explicit)) + @(, @("KCD_PATH", $env:KCD_PATH))) {
		$label = $source[0]
		$given = $source[1]

		if (-not $given) {
			continue
		}

		if (Test-Path (Join-Path $given "Bin\Win64\KingdomCome.exe")) {
			return $given
		}

		Write-Host "[DEPLOY] $label points at $given" -ForegroundColor Red
		Write-Host "         but Bin\Win64\KingdomCome.exe is not there."
		exit 1
	}

	$candidates = New-Object System.Collections.Generic.List[string]

	$candidates.Add("C:\Games\Kingdom Come - Deliverance")
	$candidates.Add("C:\Program Files (x86)\Steam\steamapps\common\KingdomComeDeliverance")
	$candidates.Add("C:\Program Files\Steam\steamapps\common\KingdomComeDeliverance")
	$candidates.Add("C:\GOG Games\Kingdom Come Deliverance")
	$candidates.Add("C:\Program Files (x86)\GOG Galaxy\Games\Kingdom Come Deliverance")

	foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
			"HKCU:\SOFTWARE\Valve\Steam")) {
		$install = (Get-ItemProperty -Path $key -Name InstallPath `
			-ErrorAction SilentlyContinue).InstallPath

		if (-not $install) {
			continue
		}

		$vdf = Join-Path $install "steamapps\libraryfolders.vdf"

		if (-not (Test-Path $vdf)) {
			continue
		}

		# Valve's key/value text format. Only the "path" entries matter, and
		# they carry doubled backslashes.
		$body = Get-Content -Raw $vdf

		foreach ($match in [regex]::Matches($body, '"path"\s+"([^"]+)"')) {
			$library = $match.Groups[1].Value -replace '\\', '\'
			$candidates.Add((Join-Path $library "steamapps\common\KingdomComeDeliverance"))
		}

		break
	}

	# The executable is what identifies a directory as the game, rather than a
	# folder that merely exists.
	foreach ($candidate in $candidates) {
		if ($candidate -and (Test-Path (Join-Path $candidate "Bin\Win64\KingdomCome.exe"))) {
			return $candidate
		}
	}

	Write-Host "[DEPLOY] no Kingdom Come: Deliverance install found." -ForegroundColor Red
	Write-Host "         Looked for Bin\Win64\KingdomCome.exe under:"

	foreach ($candidate in $candidates) {
		Write-Host "           $candidate"
	}

	Write-Host ""
	Write-Host "         Point at it with either of:"
	Write-Host '           .\tools\dev_deploy.ps1 -GameRoot "D:\path\to\game"'
	Write-Host '           $env:KCD_PATH = "D:\path\to\game"'
	exit 1
}

$gameRoot = Resolve-GameRoot -Explicit $GameRoot
$modsDir = Join-Path $gameRoot "Mods"
$parkDir = Join-Path $gameRoot "mods_old"
$exe = Join-Path $gameRoot "Bin\Win64\KingdomCome.exe"

# A fixed folder name, deliberately not versioned. Vortex names its folders
# after the archive it installed, so every new build lands in a new folder and
# the old one has to be removed by hand. One stable folder makes deployment a
# straight overwrite.
$devMod = "HorseCollisionMod_dev"

# Where -PrepareShippingTest moves everything the development loop installed, so
# a release zip can be tested with nothing loose left to mask a broken pak.
$parkedDir = "hcm_dev_parked"

# ---------------------------------------------------------------------------
# Which configuration the install is in
# ---------------------------------------------------------------------------

# Verifying a release switches this install to shipping values, and nothing
# switches it back, so an install left over from a release is configured for
# play rather than for development.
#
# That failure is invisible. At sys_PakPriority = 2 the engine ignores loose
# files completely and logs nothing about it, so a deploy, a reload and a
# console command all report success while the game keeps running the packed
# build. A warning is not enough, because the deploy that follows it looks like
# it worked.
$DevEnvironment = @(
	@{ Name = "sys_PakPriority"; Dev = "0"; Play = "2"
	   Why = "loose files under Data\ are ignored at any other value" },
	@{ Name = "mn_allowEditableDatabasesInPureGame"; Dev = "1"; Play = "0"
	   Why = "Mannequin refuses to reload its animation databases" },
	@{ Name = "log_EnableRemoteConsole"; Dev = "1"; Play = "1"
	   Why = "dev_console.py has no port to connect to" },
	# Warhorse's own backend cannot be reached and retries about twice a
	# second, which was half of every line written to kcd.log and made the
	# in-game console unreadable. The delay collapses repeats of an identical
	# line; the mod's own telemetry carries changing numbers on every line and
	# is not affected.
	@{ Name = "log_SpamDelay"; Dev = "30"; Play = "30"
	   Why = "the PROS backend fills the console and the log with retries" }
)

function Get-CfgValue {
	param ([string]$Text, [string]$Name)

	# Last assignment wins, the way the engine reads the file.
	$found = [regex]::Matches($Text, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*(\S+)")

	if ($found.Count -eq 0) { return $null }

	return $found[$found.Count - 1].Groups[1].Value
}

function Set-CfgValues {
	param ([string]$Root, [string]$Which)

	$cfg = Join-Path $Root "system.cfg"

	if (-not (Test-Path $cfg)) {
		Write-Host "[DEPLOY] no system.cfg at $cfg" -ForegroundColor Red
		exit 1
	}

	$text = Get-Content $cfg -Raw

	foreach ($rule in $DevEnvironment) {
		$want = $rule[$Which]
		$pattern = "(?m)^(\s*$([regex]::Escape($rule.Name))\s*=\s*)\S+"

		if ([regex]::IsMatch($text, $pattern)) {
			$text = [regex]::Replace($text, $pattern, "`${1}$want")
		}
		else {
			$text = $text.TrimEnd() + "`r`n$($rule.Name) = $want`r`n"
		}

		Write-Host "  $($rule.Name) = $want"
	}

	Set-Content -Path $cfg -Value $text -Encoding UTF8 -NoNewline
	Write-Host "[DEPLOY] system.cfg switched to $Which values." -ForegroundColor Green
	Write-Host "         sys_PakPriority is read at startup, so restart the game."
}

function Assert-DevEnvironment {
	param ([string]$Root)

	$cfg = Join-Path $Root "system.cfg"

	if (-not (Test-Path $cfg)) {
		Write-Host "[DEPLOY] no system.cfg at $cfg" -ForegroundColor Red
		exit 1
	}

	$text = Get-Content $cfg -Raw
	$wrong = @()

	foreach ($rule in $DevEnvironment) {
		$have = Get-CfgValue -Text $text -Name $rule.Name

		if ($null -eq $have) { $have = "unset" }

		if ($have -ne $rule.Dev) {
			$wrong += "         $($rule.Name) is $have, needs $($rule.Dev), or $($rule.Why)"
		}
	}

	if ($wrong.Count -eq 0) { return }

	Write-Host "[DEPLOY] this install is not configured for development." -ForegroundColor Red
	$wrong | ForEach-Object { Write-Host $_ }
	Write-Host ""
	Write-Host "         Switch it:  .\tools\dev_deploy.ps1 -SetDevEnvironment"
	Write-Host "         then restart the game."
	Write-Host "         -Force deploys anyway, into an install that will ignore it."
	exit 1
}

if ($SetDevEnvironment -and $SetPlayEnvironment) {
	Write-Host "[DEPLOY] pick one of -SetDevEnvironment and -SetPlayEnvironment." -ForegroundColor Red
	exit 1
}

if ($SetDevEnvironment) {
	Set-CfgValues -Root $gameRoot -Which "Dev"
	exit 0
}

if ($SetPlayEnvironment) {
	Set-CfgValues -Root $gameRoot -Which "Play"
	exit 0
}

# Puts the install in the state a player is in, so a packaged build can be
# tested the way it will actually be loaded. The development loop deploys loose
# files and runs at sys_PakPriority 0, and a pak with wrong entry names or
# reference paths overrides nothing and logs nothing, so a broken release looks
# identical to a working one until every loose file is gone.
#
# Everything is moved rather than deleted, and -RestoreDevEnvironment puts it
# all back.
if ($PrepareShippingTest) {
	# Nothing is moved while the game holds a file open.
	#
	# The pak is the one that matters: parking it fails with "the process
	# cannot access the file", after the loose files have already moved and
	# before the manifest line that would let the restore find it again. The
	# result is a half-parked install whose restore cannot put the mod back,
	# and that is how a mod folder was lost rather than parked.
	#
	# Checked before anything moves, so the install is either untouched or
	# fully parked.
	if (Get-Process -Name "KingdomCome" -ErrorAction SilentlyContinue) {
		Write-Host "[DEPLOY] the game is running, so its pak cannot be parked." -ForegroundColor Red
		Write-Host "         Quit the game and run this again. Nothing was moved."
		exit 1
	}

	$park = Join-Path $gameRoot $parkedDir
	New-Item -ItemType Directory -Force $park | Out-Null

	# Where each item came from, so the restore does not have to infer it.
	$manifest = Join-Path $park "parked.txt"
	Set-Content $manifest "" -Encoding utf8

	$moved = 0

	# What gets parked is discovered in the game folder, not listed here.
	#
	# A list of names only covers what this script currently deploys, and the
	# set of files the mod ships changes: the ten part files were added when
	# the Lua was split, and HorseCollisionMod_ItemData.lua was deployed by an
	# earlier version of this script and left behind by every list written
	# since. A single survivor invalidates the whole test, and it does so by
	# making it pass: at sys_PakPriority 2 the engine ignores loose files, but
	# the moment the priority is wrong the stale file is read instead of the
	# pak's copy, and nothing says so.
	#
	# So this matches on where the mod puts things rather than on what it is
	# expected to have put there. Two vanilla file names are listed explicitly
	# because the mod claims them and they carry no hcm_ prefix.
	$patterns = @(
		@{ Dir = "Data\Scripts\Startup"; Filter = "HorseCollisionMod*" },
		@{ Dir = "Data\Scripts\HorseCollisionMod"; Filter = "*" },
		@{ Dir = "Data\Animations\Mannequin\ADB"; Filter = "hcm_*" },
		@{ Dir = "Data\Animations\Mannequin\ADB"
		   Names = @("kcd_animationControlledTags.xml", "wh_female_fragmentids.xml") }
	)

	$found = @()

	foreach ($rule in $patterns) {
		$dir = Join-Path $gameRoot $rule.Dir

		if (-not (Test-Path $dir)) { continue }

		if ($rule.Names) {
			foreach ($n in $rule.Names) {
				$p = Join-Path $dir $n
				if (Test-Path $p) { $found += "$($rule.Dir)\$n" }
			}

			continue
		}

		foreach ($f in (Get-ChildItem -Path $dir -Filter $rule.Filter -File | Sort-Object Name)) {
			$found += "$($rule.Dir)\$($f.Name)"
		}
	}

	# Two directories can hold the same leaf name, and the manifest keys on the
	# leaf, so a collision would restore one file over the other.
	$used = @{}

	foreach ($rel in ($found | Select-Object -Unique)) {
		$p = Join-Path $gameRoot $rel
		$leaf = Split-Path $rel -Leaf
		$name = $leaf
		$n = 1

		while ($used.ContainsKey($name)) {
			$n++
			$name = "$n-$leaf"
		}

		$used[$name] = $rel
		Move-Item $p (Join-Path $park $name) -Force
		Add-Content $manifest "$name|$rel" -Encoding utf8
		Write-Host "[DEPLOY] parked $rel"
		$moved++
	}

	$dev = Join-Path $modsDir $devMod

	if (Test-Path $dev) {
		Move-Item $dev (Join-Path $park $devMod) -Force
		Add-Content $manifest "$devMod|Mods\$devMod" -Encoding utf8
		Write-Host "[DEPLOY] parked Mods\$devMod"
		$moved++
	}

	Set-CfgValues -Root $gameRoot -Which "Play"

	Write-Host "[DEPLOY] $moved item(s) parked in $parkedDir."
	Write-Host "[DEPLOY] install the release zip through Vortex, then launch"
	Write-Host "         the game normally. No -devmode."
	Write-Host "[DEPLOY] undo with: .\tools\dev_deploy.ps1 -RestoreDevEnvironment"
	exit 0
}

if ($RestoreDevEnvironment) {
	# Same reason as the park above: the pak cannot be moved back into place
	# while the game holds the copy it is running from.
	if (Get-Process -Name "KingdomCome" -ErrorAction SilentlyContinue) {
		Write-Host "[DEPLOY] the game is running, so the pak cannot be restored." -ForegroundColor Red
		Write-Host "         Quit the game and run this again. Nothing was moved."
		exit 1
	}

	$park = Join-Path $gameRoot $parkedDir

	if (-not (Test-Path $park)) {
		Write-Host "[DEPLOY] nothing parked in $parkedDir." -ForegroundColor Yellow
		Set-CfgValues -Root $gameRoot -Which "Dev"
		exit 0
	}

	# Restored to where each item actually came from, read back from the
	# manifest written when it was parked. Inferring the destination from the
	# file name puts anything unexpected in Scripts\Startup, and a script that
	# lands there is executed at startup rather than sitting inert.
	$manifest = Join-Path $park "parked.txt"

	if (-not (Test-Path $manifest)) {
		Write-Host "[DEPLOY] $parkedDir has no manifest; restore by hand." -ForegroundColor Red
		Write-Host "         Items are in $park"
		exit 1
	}

	foreach ($line in Get-Content $manifest) {
		if (-not $line.Trim()) { continue }

		$name, $rel = $line -split "\|", 2
		$src = Join-Path $park $name

		if (-not (Test-Path $src)) { continue }

		$dest = Join-Path $gameRoot $rel
		New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
		Move-Item $src $dest -Force
		Write-Host "[DEPLOY] restored $rel"
	}

	Remove-Item $park -Recurse -Force -ErrorAction SilentlyContinue
	Set-CfgValues -Root $gameRoot -Which "Dev"
	Write-Host "[DEPLOY] development environment restored. Restart the game."
	exit 0
}

# Every deploy path runs this, including -ScriptOnly and -AnimOnly, which are
# the ones most likely to be aimed at an install left in shipping values.
if (-not $Force) {
	Assert-DevEnvironment -Root $gameRoot
}
$devDir = Join-Path $modsDir $devMod

Write-Host "[DEPLOY] game: $gameRoot"

# Copies the parts of the mod that can be replaced under a running game.
#
# Both live under Data, because sys_game_folder is "Data" and that is where
# the engine's file system is rooted. One level higher is never found, and the
# failure is quiet: "Loading and executing script file" is logged before the
# read is attempted and a miss logs nothing.
#
# Neither is what ships. The packed copies inside the pak stay exactly as they
# are; these are only what a running game reads first, and only while
# sys_PakPriority is 0.
#
# Returns which halves were written, as @{ Script = $bool; Anim = $bool }, so
# the caller reloads only the subsystem that needs it.
function Sync-LooseFiles {
	param (
		[string]$Root,
		[switch]$Script,
		[switch]$Anim,
		[switch]$ChangedOnly
	)

	$changed = @{ Script = $false; Anim = $false }
	$files = @()

	# The settings file belongs here as much as the mod script does. It is a
	# separate Startup script, so a settings edit that is not copied leaves the
	# running game reading the packed values while the edited file sits on disk
	# looking applied.
	if ($Script) {
		$startup = Join-Path $Root "Data\Scripts\Startup"

		foreach ($name in @("HorseCollisionMod.lua", "HorseCollisionMod_Settings.lua")) {
			$files += @{
				Half = "Script"
				From = Join-Path $repoRoot "src\$name"
				To   = Join-Path $startup $name
			}
		}

		# The part files the entry point pulls in with Script.ReloadScript.
		# They sit beside Scripts\Startup rather than in it, because that
		# folder is enumerated and executed by the engine. Walked rather than
		# named, so a later slice needs no change here. A missing part does not
		# fail loudly: the entry point loads, the methods it expected are nil,
		# and the mod silently does less.
		$partsSrc = Join-Path $repoRoot "src\HorseCollisionMod"

		if (Test-Path $partsSrc) {
			$partsDest = Join-Path $Root "Data\Scripts\HorseCollisionMod"

			foreach ($part in (Get-ChildItem -Path $partsSrc -Filter *.lua -File | Sort-Object Name)) {
				$files += @{
					Half = "Script"
					From = $part.FullName
					To   = Join-Path $partsDest $part.Name
				}
			}
		}
	}

	if ($Anim) {
		$source = Join-Path $repoRoot "mod_assets\Animations\Mannequin\ADB"

		if (-not (Test-Path $source)) {
			Write-Host "[DEPLOY] no mod_assets yet. Run build.ps1 first." -ForegroundColor Yellow
		}
		else {
			$adbDir = Join-Path $Root "Data\Animations\Mannequin\ADB"

			foreach ($file in Get-ChildItem -Path $source -File) {
				$files += @{
					Half = "Anim"
					From = $file.FullName
					To   = Join-Path $adbDir $file.Name
				}
			}
		}
	}

	foreach ($file in $files) {
		if (-not (Test-Path $file.From)) {
			continue
		}

		# Compared by content rather than by timestamp. build.ps1 regenerates
		# every animation database on each run whether or not the bytes moved,
		# and a Mannequin reload is a visible hitch in the running game, so a
		# rebuild that changed nothing should not cause one.
		if ($ChangedOnly -and (Test-Path $file.To)) {
			$from = (Get-FileHash $file.From -Algorithm SHA256).Hash
			$to = (Get-FileHash $file.To -Algorithm SHA256).Hash

			if ($from -eq $to) {
				continue
			}
		}

		$dir = Split-Path -Parent $file.To

		if (-not (Test-Path $dir)) {
			New-Item -ItemType Directory -Force -Path $dir | Out-Null
		}

		Copy-Item $file.From -Destination $file.To -Force
		Write-Host "[DEPLOY] updated $(Split-Path -Leaf $file.To)"
		$changed[$file.Half] = $true
	}

	# A development deploy leaves riding someone down legal, because almost
	# every collision test is about the collision and not about the crime, and
	# guards arriving mid-test end the test. -Crime keeps the shipping value.
	#
	# This has to happen here, between the copy and the reload the caller runs
	# next. src\HorseCollisionMod_Settings.lua cannot carry the change, because
	# build.ps1 rejects a release that ships CollisionIsCrime = false, and
	# patching the installed file after the reload is too late: the value the
	# engine already read is the one a later save load keeps.
	if ($changed.Script) {
		Set-DeployedCrime -Root $Root -Enabled:$Crime
	}

	return $changed
}

# Rewrites CollisionIsCrime in the installed settings file, and reports what it
# left behind rather than assuming the edit took. The value is written as bytes
# with no byte order mark: Set-Content -Encoding utf8 on Windows PowerShell
# writes one, and a BOM on the first line makes Lua reject the entire settings
# file, at which point the mod silently keeps every compiled-in default and the
# setting appears not to work at all.
function Set-DeployedCrime {
	param (
		[string]$Root,
		[switch]$Enabled
	)

	$path = Join-Path $Root "Data\Scripts\Startup\HorseCollisionMod_Settings.lua"

	if (-not (Test-Path $path)) {
		return
	}

	$want = if ($Enabled) { "true" } else { "false" }
	$text = [System.IO.File]::ReadAllText($path)
	$patched = [regex]::Replace($text,
		'(CollisionIsCrime\s*=\s*)(true|false)', "`${1}$want")

	if ($patched -ne $text) {
		$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
		[System.IO.File]::WriteAllText($path, $patched, $utf8NoBom)
	}

	# Read it back off disk. A regex that matched nothing looks exactly like a
	# successful patch from here, and the cost of the difference is the rider
	# fending off guards through a test that then has to be run again.
	$now = [regex]::Match([System.IO.File]::ReadAllText($path),
		'CollisionIsCrime\s*=\s*(true|false)')

	if (-not $now.Success) {
		Write-Host "[DEPLOY] CollisionIsCrime not found in the installed settings." -ForegroundColor Yellow
	}
	elseif ($now.Groups[1].Value -ne $want) {
		Write-Host "[DEPLOY] CollisionIsCrime is $($now.Groups[1].Value), wanted $want." -ForegroundColor Red
	}
	else {
		Write-Host "[DEPLOY] CollisionIsCrime = $want (installed settings)"
	}
}

# Reloads the halves that were written. The console commands are known here, so
# printing them to be pasted into a second shell would put a manual step in the
# middle of a loop that is run many times in a testing session.
function Invoke-LiveReload {
	param ([hashtable]$Changed)

	$flags = @()

	if ($Changed.Anim) {
		$flags += "--anim-reload"
	}

	if ($Changed.Script) {
		$flags += "--reload"
	}

	if ($flags.Count -eq 0) {
		return
	}

	# Nothing to reload into. The files are in place and the engine reads them
	# at startup, so this is a note rather than a failure.
	if (-not (Get-Process -Name "KingdomCome" -ErrorAction SilentlyContinue)) {
		Write-Host "[DEPLOY] the game is not running. The files are in place for the next start."
		return
	}

	Write-Host "[DEPLOY] reloading in the running game..." -ForegroundColor Green
	& python (Join-Path $repoRoot "tools\dev_console.py") @flags
}

# The inner loops: push what changed, then reload it from the console. Both
# deliberately skip the running-game guard below, because that guard is about
# the pak, which the engine holds open. A loose file is not locked and can be
# replaced underneath a running game.
if ($Reload -or $ScriptOnly -or $AnimOnly) {
	# -Reload is the everyday form: it works out which halves moved and reloads
	# those. -ScriptOnly and -AnimOnly name one half and skip the comparison,
	# which is what is wanted when a file has been reverted to a state matching
	# the copy already installed, or when only one subsystem should be
	# disturbed.
	$named = $ScriptOnly -or $AnimOnly

	$changed = Sync-LooseFiles -Root $gameRoot `
		-Script:($ScriptOnly -or -not $named) `
		-Anim:($AnimOnly -or -not $named) `
		-ChangedOnly:(-not $named)

	if (-not ($changed.Script -or $changed.Anim)) {
		Write-Host "[DEPLOY] nothing changed since the last deploy."
		exit 0
	}

	Invoke-LiveReload -Changed $changed
	exit 0
}

# Read the version from the manifest when none is given, so the two cannot
# drift apart and deploy a build that is not the one just made.
if ($Version -eq "") {
	$manifest = [xml](Get-Content (Join-Path $repoRoot "src\mod.manifest"))
	$Version = $manifest.kcd_mod.info.version
	Write-Host "[DEPLOY] version from mod.manifest: $Version"
}

if (-not $NoBuild) {
	& powershell.exe -ExecutionPolicy Bypass `
		-File (Join-Path $repoRoot "build.ps1") -Version $Version
	if ($LASTEXITCODE -ne 0) {
		Write-Host "[DEPLOY] build failed, nothing deployed" -ForegroundColor Red
		exit 1
	}
}

$zip = Join-Path $repoRoot "releases\HorseCollisionMod_v$Version.zip"

if (-not (Test-Path $zip)) {
	Write-Host "[DEPLOY] no build at $zip" -ForegroundColor Red
	Write-Host "         run without -NoBuild, or pass the -Version that was built."
	exit 1
}

# Refuse to write into the running game. The engine holds its paks open, so a
# deploy would either fail on a locked file or, worse, half succeed.
$running = Get-Process -Name "KingdomCome" -ErrorAction SilentlyContinue

if ($running) {
	Write-Host "[DEPLOY] the game is running. Close it, or use the console reload path." -ForegroundColor Red
	exit 1
}

# Vortex installed its own copy under a versioned folder name. Two folders both
# providing Scripts/Startup/HorseCollisionMod.lua is decided by mod_order, which
# is a confusing way to find out which build is actually being tested.
$stale = Get-ChildItem -Path $modsDir -Directory -ErrorAction SilentlyContinue |
	Where-Object { $_.Name -like "HorseCollisionMod*" -and $_.Name -ne $devMod }

if ($stale) {
	foreach ($s in $stale) {
		if ($ParkVortexMod) {
			if (-not (Test-Path $parkDir)) {
				New-Item -ItemType Directory -Force -Path $parkDir | Out-Null
			}

			$dest = Join-Path $parkDir $s.Name

			if (Test-Path $dest) {
				Remove-Item -Recurse -Force $dest
			}

			Move-Item -Path $s.FullName -Destination $dest
			Write-Host "[DEPLOY] moved $($s.Name) to mods_old\" -ForegroundColor Yellow
		}
		else {
			Write-Host "[DEPLOY] warning: $($s.Name) is also installed." -ForegroundColor Yellow
			Write-Host "         Pass -ParkVortexMod to move it to mods_old\, or remove it in Vortex."
		}
	}
}

if (Test-Path $devDir) {
	Remove-Item -Recurse -Force $devDir
}

New-Item -ItemType Directory -Force -Path (Join-Path $devDir "Data") | Out-Null

$staging = Join-Path $env:TEMP "hcm_deploy"

if (Test-Path $staging) {
	Remove-Item -Recurse -Force $staging
}

Expand-Archive -Path $zip -DestinationPath $staging -Force

Copy-Item (Join-Path $staging "Data\HorseCollisionMod.pak") -Destination (Join-Path $devDir "Data\")
Copy-Item (Join-Path $staging "mod.manifest") -Destination $devDir
Remove-Item -Recurse -Force $staging

# mod_order.txt is one folder name per line. Later lines win a conflict, so the
# dev build goes last.
$orderPath = Join-Path $modsDir "mod_order.txt"
$order = @()

if (Test-Path $orderPath) {
	$order = @(Get-Content $orderPath | Where-Object { $_.Trim() -ne "" })
}

$order = @($order | Where-Object { $_.Trim() -ne $devMod })

# Drop entries whose folder is gone. Parking a mod, or removing one in
# Vortex, leaves its line behind, and a load order listing folders that do
# not exist is a confusing thing to read when working out which build is
# actually being tested. The game skips them, so this is tidying rather
# than a fix.
$order = @($order | Where-Object {
	$keep = Test-Path (Join-Path $modsDir $_.Trim())

	if (-not $keep) {
		Write-Host "[DEPLOY] dropping stale load order entry: $($_.Trim())" -ForegroundColor Yellow
	}

	$keep
})

$order = $order + $devMod

# Written through .NET rather than Set-Content because PowerShell 5.1's
# "-Encoding utf8" emits a byte order mark, and the BOM ends up glued to the
# front of the first mod's folder name where the game cannot match it.
$noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($orderPath, [string[]]$order, $noBom)

Write-Host "[DEPLOY] $Version installed to Mods\$devMod" -ForegroundColor Green
Write-Host "[DEPLOY] load order: $($order -join ' -> ')"

# The script also goes down loose, next to the game's own Scripts tree, so an
# edit on disk can be picked up by `dev_console.py --reload` without a restart.
# The packed copy inside the pak stays where it is and remains what ships; this
# is only what the running game reads first.
#
# It only works with sys_PakPriority = 0 in system.cfg. The stock value is 2,
# pak-only, under which loose files are ignored entirely and a reload re-reads
# the same packed bytes. The check below says so rather than leaving a silent
# no-op to be discovered later.
if (-not $NoLooseScript) {
	Sync-LooseFiles -Root $gameRoot -Script -Anim | Out-Null
}

if ($Launch) {
	# The UAC prompt on every launch is not Windows being cautious about an
	# unknown publisher on its own account. It is the RUNASADMIN compatibility
	# layer, set per user for this executable, forcing elevation. The game does
	# not ask for it: its own manifest requests asInvoker, and the whole game
	# folder is user writable. Vortex and various setup guides set this flag, so
	# it can come back; the check is here rather than being a one-time fix.
	$layerKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
	$layers = $null

	if (Test-Path $layerKey) {
		$layers = (Get-ItemProperty -Path $layerKey -Name $exe -ErrorAction SilentlyContinue).$exe
	}

	if ($layers -and $layers -match "RUNASADMIN") {
		Write-Host "[DEPLOY] note: RUNASADMIN is set for the game, so Windows will" -ForegroundColor Yellow
		Write-Host "         ask for elevation on every launch. To clear just this app:"
		Write-Host "         Properties > Compatibility > untick 'Run this program as an administrator'"
	}

	if (-not (Test-Path $exe)) {
		Write-Host "[DEPLOY] game executable not found at $exe" -ForegroundColor Red
		exit 1
	}

	# Dev mode comes from the command line, not from a config file. The
	# "sys_DevMode = 1" line in system.cfg does nothing: querying it over the
	# remote console answers "Unknown command: sys_DevMode". Without -devmode the
	# console refuses anything marked VF_CHEAT, which includes lua_reload_script.
	$launchArgs = @()

	if (-not $NoDevMode) {
		$launchArgs = $launchArgs + "-devmode"
	}

	# Started with the executable's own folder as the working directory, which is
	# what a double-click does. Note there are two user.cfg files in this install,
	# one in the game root and one next to the executable, and which of them the
	# engine picks up depends on this. Do not change it without checking that the
	# graphics settings in Bin\Win64\user.cfg still apply.
	Write-Host "[DEPLOY] launching $(if ($launchArgs) { $launchArgs -join ' ' } else { '(no flags)' })..."

	if ($launchArgs) {
		Start-Process -FilePath $exe -ArgumentList $launchArgs -WorkingDirectory (Split-Path $exe -Parent)
	}
	else {
		Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe -Parent)
	}
}
