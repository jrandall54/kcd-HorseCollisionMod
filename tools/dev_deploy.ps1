# Installs the mod straight into the game for development, skipping Vortex.
#
# Internal to tools\flow.ps1, which is the only thing that calls it. Run
# `flow.ps1 test`, `flow.ps1 shipping` or `flow.ps1 land` instead; each decides
# which of these the install's state calls for.
#
#   -Launch                  build, install, start the game with -devmode
#   -Reload                  copy the loose files that changed, reload them live
#   -ReleaseSettings         with -Reload: install the shipped world
#   -SetDevEnvironment       switch system.cfg to development values
#   -PrepareShippingTest     park every loose file, switch to shipping values
#   -RestoreDevEnvironment   put it all back
#
# With no switch it builds and installs. That refuses while the game is
# running, because the engine holds the installed pak open.
#
# The game folder is resolved by tools\game_root.ps1. The release build for
# Nexus goes through build.ps1 on its own; the folder this writes never ships.

param (
	[switch]$Launch,
	[switch]$Reload,
	[switch]$ReleaseSettings,
	[switch]$SetDevEnvironment,
	[switch]$PrepareShippingTest,
	[switch]$RestoreDevEnvironment
)

$ErrorActionPreference = "Stop"

# This script lives in tools/, so the repository root is one level up. Every
# project path below is built from it rather than from the working directory,
# so the script can be run from anywhere.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

. (Join-Path $PSScriptRoot "game_root.ps1")

$gameRoot = Resolve-GameRoot
$modsDir = Join-Path $gameRoot "Mods"
$exe = Join-Path $gameRoot "Bin\Win64\KingdomCome.exe"

# A fixed folder name, deliberately not versioned. Vortex names its folders
# after the archive it installed, so every new build lands in a new folder and
# the old one has to be removed by hand. One stable folder makes deployment a
# straight overwrite.
$devMod = "HorseCollisionMod_dev"

# Where -PrepareShippingTest moves everything the development loop installed, so
# a release zip can be tested with nothing loose left to mask a broken pak.
$parkedDir = "hcm_dev_parked"

# Vanilla animation file names this mod has claimed at some point. Everything
# else it installs carries an hcm_ prefix.
#
# Named because a file the mod no longer ships still has to be cleaned out of an
# install that has it. At sys_PakPriority = 0 a loose override wins, so a
# withdrawn file goes on overriding vanilla, and the verify pass calls the
# install correct, because it only checks files the repository still has.
$claimedVanillaAdb = @(
	"kcd_animationControlledTags.xml",
	"wh_female_fragmentids.xml",
	"kcd_horse_fragmentids.xml",
	"kcd_horse_controllerdefs.xml"
)

function Game-Running {
	return [bool](Get-Process -Name "KingdomCome" -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------------------
# Which configuration the install is in
# ---------------------------------------------------------------------------

# Testing a release switches this install to shipping values, and an install in
# that state is configured for play rather than for development.
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
	# Development keeps every repeat. The animation queue overflow message is
	# byte identical for a given character apart from a pointer, so a delay
	# collapses exactly the evidence a hunt needs.
	@{ Name = "log_SpamDelay"; Dev = "0"; Play = "30"
	   Why = "repeats of an identical engine warning are collapsed" },
	# The file and the console have separate verbosities, and the file ships at
	# 0. Every engine warning and error therefore renders on the in-game console
	# and is never written to kcd.log, which is the only thing this project can
	# read after the fact.
	@{ Name = "log_WriteToFileVerbosity"; Dev = "3"; Play = "0"
	   Why = "engine warnings and errors never reach kcd.log" },
	# Gates the animation warnings, including the queue filling up before it
	# overflows. At the shipped 0 only the hard failure can ever print.
	@{ Name = "ca_AnimWarningLevel"; Dev = "2"; Play = "0"
	   Why = "animation warnings are off, including the queue filling" }
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
	Write-Host "         .\tools\flow.ps1 test switches it; then restart the game."
	exit 1
}

if ($SetDevEnvironment) {
	Set-CfgValues -Root $gameRoot -Which "Dev"
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
	# result is a half-parked install whose restore cannot put the mod back.
	#
	# Checked before anything moves, so the install is either untouched or
	# fully parked.
	if (Game-Running) {
		Write-Host "[DEPLOY] the game is running, so its pak cannot be parked." -ForegroundColor Red
		Write-Host "         Quit the game and run this again. Nothing was moved."
		exit 1
	}

	$park = Join-Path $gameRoot $parkedDir
	New-Item -ItemType Directory -Force $park | Out-Null

	# Where each item came from, so the restore does not have to infer it.
	# Appended rather than rewritten, because the park is rerun after a
	# refusal and the first run's entries must survive it.
	$manifest = Join-Path $park "parked.txt"

	if (-not (Test-Path $manifest)) {
		Set-Content $manifest "" -Encoding utf8
	}

	$moved = 0

	# Matched by location, not by a list of names, because one surviving loose
	# file masks the pak: the moment sys_PakPriority is wrong, the stale file
	# is read instead of the pak's copy, and nothing says so. The claimed
	# vanilla names are listed because they carry no hcm_ prefix.
	$patterns = @(
		@{ Dir = "Data\Scripts\Startup"; Filter = "HorseCollisionMod*" },
		@{ Dir = "Data\Scripts\HorseCollisionMod"; Filter = "*" },
		@{ Dir = "Data\Animations\Mannequin\ADB"; Filter = "hcm_*" },
		@{ Dir = "Data\Animations\Mannequin\ADB"; Names = $claimedVanillaAdb },
		@{ Dir = "Data\Libs\Config"; Filter = "hcm_*" },
		@{ Dir = "Data\Libs\Tables\rpg"; Filter = "*__horsecollision*" },
		@{ Dir = "Data\Libs\Tables\text"; Filter = "*__horsecollision*" }
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
	exit 0
}

if ($RestoreDevEnvironment) {
	# Same reason as the park above: the pak cannot be moved back into place
	# while the game holds the copy it is running from.
	if (Game-Running) {
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

	# Only the manifest and what it listed may be deleted. The park is a
	# plain folder inside the game install, and things get put there by hand.
	Remove-Item $manifest -Force -ErrorAction SilentlyContinue

	$leftovers = @(Get-ChildItem $park -Force -ErrorAction SilentlyContinue)

	if ($leftovers.Count -eq 0) {
		Remove-Item $park -Recurse -Force -ErrorAction SilentlyContinue
	} else {
		Write-Host "[DEPLOY] $parkedDir kept; it holds $($leftovers.Count) item(s) no manifest listed:" -ForegroundColor Yellow

		foreach ($item in $leftovers) {
			Write-Host "         $($item.Name)" -ForegroundColor Yellow
		}
	}

	Set-CfgValues -Root $gameRoot -Which "Dev"
	Write-Host "[DEPLOY] development environment restored. Restart the game."
	exit 0
}

# Every deploy path runs this, -Reload included, since that is the one most
# likely to be aimed at an install left in shipping values.
Assert-DevEnvironment -Root $gameRoot

$devDir = Join-Path $modsDir $devMod

Write-Host "[DEPLOY] game: $gameRoot"

# The animation files the mod ships: generated ones from mod_assets and
# hand-authored ones from src, the same two sources build.ps1 packs.
function Get-ShippedAdbFiles {
	foreach ($base in @("mod_assets", "src")) {
		$dir = Join-Path $repoRoot "$base\Animations\Mannequin\ADB"

		if (Test-Path $dir) {
			Get-ChildItem -Path $dir -File
		}
	}
}

# The data overrides the mod ships under Libs, as relative path to source file:
# mod_assets\Libs, then src\Libs, the order build.ps1 packs them in, so a
# file in src\Libs wins over a copy of the same path in mod_assets.
#
# Tables are read once at startup, so a file that lands here still needs the
# game restarted before it means anything.
function Get-ShippedLibsFiles {
	$map = [ordered]@{}

	foreach ($base in @("mod_assets", "src")) {
		$dir = Join-Path $repoRoot "$base\Libs"

		if (-not (Test-Path $dir)) {
			continue
		}

		$prefix = (Resolve-Path $dir).Path

		foreach ($file in Get-ChildItem -Path $dir -File -Recurse) {
			$map[$file.FullName.Substring($prefix.Length).TrimStart('\')] = $file.FullName
		}
	}

	return $map
}

# Every loose file the mod owns, as repo source paired with installed target.
#
# Split out of Sync-LooseFiles so the verification below checks every file
# whatever a given deploy copied.
function Get-LooseFileMap {
	param ([string]$Root)

	$files = @()

	# The settings file belongs here as much as the mod script does. It is a
	# separate Startup script, so a settings edit that is not copied leaves the
	# running game reading the packed values while the edited file sits on disk
	# looking applied.
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
	# named, so a new part needs no change here. A missing part does not
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

	if (-not (Test-Path (Join-Path $repoRoot "mod_assets\Animations\Mannequin\ADB"))) {
		Write-Host "[DEPLOY] no mod_assets yet. Run build.ps1 first." -ForegroundColor Yellow
	}

	$adbDir = Join-Path $Root "Data\Animations\Mannequin\ADB"

	foreach ($file in Get-ShippedAdbFiles) {
		$files += @{
			Half = "Anim"
			From = $file.FullName
			To   = Join-Path $adbDir $file.Name
		}
	}

	$libs = Get-ShippedLibsFiles

	foreach ($relative in $libs.Keys) {
		$files += @{
			Half = "Anim"
			From = $libs[$relative]
			To   = Join-Path $Root (Join-Path "Data\Libs" $relative)
		}
	}

	return $files
}

function Test-SameBytes {
	param ([string]$A, [string]$B)

	if (-not (Test-Path $B)) {
		return $false
	}

	return (Get-FileHash $A -Algorithm SHA256).Hash -eq (Get-FileHash $B -Algorithm SHA256).Hash
}

# Reports any installed loose file whose bytes differ from the repository, so a
# deploy that reports success cannot leave the running game executing
# something the repository no longer contains.
#
# Hashes rather than timestamps, because a copy can be newer and still be the
# wrong bytes.
#
# @return the number of files that do not match
function Test-InstalledFiles {
	param ([string]$Root)

	$bad = 0

	foreach ($file in (Get-LooseFileMap -Root $Root)) {
		if (-not (Test-Path $file.From)) {
			continue
		}

		if (-not (Test-Path $file.To)) {
			Write-Host "[VERIFY] missing  $(Split-Path -Leaf $file.To)" -ForegroundColor Red
			$bad++
			continue
		}

		if (-not (Test-SameBytes $file.From $file.To)) {
			Write-Host "[VERIFY] STALE    $(Split-Path -Leaf $file.To)" -ForegroundColor Red
			Write-Host "         installed does not match $($file.From)" -ForegroundColor Red
			$bad++
		}
	}

	if ($bad -eq 0) {
		Write-Host "[VERIFY] installed files match the repository."
	}
	else {
		Write-Host "[VERIFY] $bad file(s) do not match. The running game is not" -ForegroundColor Red
		Write-Host "         what the repository says." -ForegroundColor Red
	}

	return $bad
}

# Deletes loose animation overrides the mod installed once and no longer ships.
#
# A deploy only ever writes, so withdrawing a file from the shipped set leaves the
# installed copy behind, still overriding vanilla at sys_PakPriority = 0, and
# every check downstream passes: the pak is right, the build is right, and the
# verify pass compares only files the repository still has.
#
# Scoped to names this mod is known to own, so nothing of the game's or of
# another mod's is ever a candidate.
function Remove-WithdrawnAnimOverrides {
	param ([string]$Root)

	$installed = Join-Path $Root "Data\Animations\Mannequin\ADB"

	if (-not (Test-Path (Join-Path $repoRoot "mod_assets\Animations\Mannequin\ADB")) -or
	    -not (Test-Path $installed)) {
		return
	}

	$shipped = @(Get-ShippedAdbFiles | ForEach-Object { $_.Name })

	foreach ($file in (Get-ChildItem -Path $installed -File | Sort-Object Name)) {
		if ($shipped -contains $file.Name) {
			continue
		}

		$ours = $file.Name -like "hcm_*" -or $claimedVanillaAdb -contains $file.Name

		if (-not $ours) {
			continue
		}

		Remove-Item $file.FullName -Force
		Write-Host "[DEPLOY] removed withdrawn override $($file.Name)" -ForegroundColor Yellow
	}
}

# Copies the loose files whose bytes differ from the installed copy.
#
# They live under Data, because sys_game_folder is "Data" and that is where
# the engine's file system is rooted. One level higher is never found, and the
# failure is quiet: "Loading and executing script file" is logged before the
# read is attempted and a miss logs nothing.
#
# None of them is what ships. The packed copies inside the pak stay exactly as
# they are; these are only what a running game reads first, and only while
# sys_PakPriority is 0.
#
# Compared by content rather than by timestamp: a regeneration rewrites every
# database whether or not the bytes moved, and a Mannequin reload is a visible
# hitch in the running game.
#
# Returns which halves changed, as @{ Script = $bool; Anim = $bool }, so the
# caller reloads only the subsystem that needs it.
# Deletes loose table overrides the mod installed once and no longer ships, for
# the same reason as the animation overrides above. The engine loads every
# `<table>__<suffix>.xml` it finds, so a withdrawn one goes on adding its rows.
# Scoped to the mod's own `__horsecollision` suffix.
function Remove-WithdrawnTableOverrides {
	param ([string]$Root)

	$shipped = @((Get-ShippedLibsFiles).Keys | ForEach-Object { Split-Path $_ -Leaf })

	foreach ($sub in @("rpg", "text")) {
		$dir = Join-Path $Root "Data\Libs\Tables\$sub"

		if (-not (Test-Path $dir)) {
			continue
		}

		foreach ($file in (Get-ChildItem -Path $dir -Filter "*__horsecollision*" -File)) {
			if ($shipped -contains $file.Name) {
				continue
			}

			Remove-Item $file.FullName -Force
			Write-Host "[DEPLOY] removed withdrawn override $($file.Name)" -ForegroundColor Yellow
		}
	}
}

function Sync-LooseFiles {
	param ([string]$Root)

	$changed = @{ Script = $false; Anim = $false }

	Remove-WithdrawnAnimOverrides -Root $Root
	Remove-WithdrawnTableOverrides -Root $Root

	foreach ($file in (Get-LooseFileMap -Root $Root)) {
		if (-not (Test-Path $file.From)) {
			continue
		}

		if (Test-SameBytes $file.From $file.To) {
			continue
		}

		$dir = Split-Path -Parent $file.To

		if (-not (Test-Path $dir)) {
			New-Item -ItemType Directory -Force -Path $dir | Out-Null
		}

		Copy-Item $file.From -Destination $file.To -Force
		Write-Host "[DEPLOY] updated $(Split-Path -Leaf $file.To)"
		$changed[$file.Half] = $true

		# The action map is read once, at startup. Rear.lua loads it behind a
		# flag, because loading a registered map again registers every action a
		# second time, so a script reload cannot pick up a new key.
		if ((Split-Path -Leaf $file.To) -eq "hcm_actionmaps.xml" -and (Game-Running)) {
			Write-Host "[DEPLOY] hcm_actionmaps.xml changed while the game is running." -ForegroundColor Yellow
			Write-Host "[DEPLOY] Action maps are read once at startup, so any new key is" -ForegroundColor Yellow
			Write-Host "[DEPLOY] dead until the game is restarted." -ForegroundColor Yellow
		}
	}

	# The testing world, written beside the settings rather than into them.
	#
	# `HorseCollisionMod_TestWorld.lua` loads after the settings file because
	# startup scripts run in name order, and assigns into the same global, so
	# the mod applies it through ApplySettings with the same type checking and
	# without knowing it exists. The build packs from src\, which never holds
	# it, so it cannot ship; the repository's settings file cannot carry a
	# testing value, because it does ship.
	#
	# Written before the caller's reload: a value written after it is not the
	# one the engine read, and not the one a later save load keeps. A changed
	# world counts as a changed script, so a world switch alone still reloads.
	#
	# -ReleaseSettings asks for the shipped world, which is the world with no
	# overrides in it, and is what a branch wants once it stops being tested.
	$worldTool = Join-Path $PSScriptRoot "testworld.py"
	$worldFile = Join-Path $Root "Data\Scripts\Startup\HorseCollisionMod_TestWorld.lua"

	$before = $null

	if (Test-Path $worldFile) {
		$before = (Get-FileHash $worldFile -Algorithm SHA256).Hash
	}

	if ($ReleaseSettings) {
		Write-Host "[DEPLOY] release settings: the installed world is the shipped one"
		& python $worldTool --clear --write $Root | Out-String | Write-Host -NoNewline
	}
	else {
		& python $worldTool --write $Root | Out-String | Write-Host -NoNewline
	}

	$after = $null

	if (Test-Path $worldFile) {
		$after = (Get-FileHash $worldFile -Algorithm SHA256).Hash
	}

	if ($before -ne $after) {
		$changed.Script = $true
	}

	return $changed
}

# Reloads the halves that were written, through the remote console.
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
	if (-not (Game-Running)) {
		Write-Host "[DEPLOY] the game is not running. The files are in place for the next start."
		return
	}

	Write-Host "[DEPLOY] reloading in the running game..." -ForegroundColor Green
	& python (Join-Path $repoRoot "tools\dev_console.py") @flags
}

# The inner loop: copy what changed, then reload it from the console. A loose
# file is not locked, so it can be replaced underneath a running game.
if ($Reload) {
	$changed = Sync-LooseFiles -Root $gameRoot

	# Verified before the reload, not after, so a stale file is named while
	# there is still a chance to act on it.
	$bad = Test-InstalledFiles -Root $gameRoot

	if (-not ($changed.Script -or $changed.Anim)) {
		Write-Host "[DEPLOY] nothing changed since the last deploy."
		exit ($(if ($bad -gt 0) { 1 } else { 0 }))
	}

	Invoke-LiveReload -Changed $changed

	if ($bad -gt 0) {
		exit 1
	}

	exit 0
}

# A full deploy replaces Mods\HorseCollisionMod_dev, whose pak the engine holds
# open while the game runs. Refused before anything is built or touched; flow.ps1
# uses -Reload for a running game.
if (Game-Running) {
	Write-Host "[DEPLOY] the game is running, so its pak cannot be replaced." -ForegroundColor Red
	Write-Host "         .\tools\flow.ps1 test reloads the loose files instead. Nothing was changed."
	exit 1
}

# Built as a prerelease of the manifest's version, so the deploy never
# overwrites releases\HorseCollisionMod_v<version>.zip, which is the released
# artifact once that version is tagged.
$manifest = [xml](Get-Content (Join-Path $repoRoot "src\mod.manifest"))
$Version = "$($manifest.kcd_mod.info.version)-dev"

# -Development, because this installs and never ships. Without it the build
# applies the release gate (version against changelog and manifest,
# documentation staleness) and refuses to deploy over work that has been
# written into [Unreleased] but not yet versioned, which is the normal state of
# a branch being tested.
& powershell.exe -ExecutionPolicy Bypass `
	-File (Join-Path $repoRoot "build.ps1") -Version $Version -Development

if ($LASTEXITCODE -ne 0) {
	Write-Host "[DEPLOY] build failed, nothing deployed" -ForegroundColor Red
	exit 1
}

$zip = Join-Path $repoRoot "releases\HorseCollisionMod_v$Version.zip"

if (-not (Test-Path $zip)) {
	Write-Host "[DEPLOY] no build at $zip" -ForegroundColor Red
	exit 1
}

# Vortex installed its own copy under a versioned folder name. Two folders both
# providing Scripts/Startup/HorseCollisionMod.lua is decided by mod_order, which
# is a confusing way to find out which build is actually being tested.
$others = Get-ChildItem -Path $modsDir -Directory -ErrorAction SilentlyContinue |
	Where-Object { $_.Name -like "HorseCollisionMod*" -and $_.Name -ne $devMod }

foreach ($other in $others) {
	Write-Host "[DEPLOY] warning: $($other.Name) is also installed. Remove it in Vortex." -ForegroundColor Yellow
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
if (Test-Path (Join-Path $staging "Localization")) {
	Copy-Item (Join-Path $staging "Localization") -Destination $devDir -Recurse -Force
}
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

# The scripts and animation data also go down loose, next to the game's own
# trees, so an edit on disk can be reloaded without a restart. The packed copy
# inside the pak stays where it is and remains what ships; this is only what the
# running game reads first, and only at sys_PakPriority = 0, which
# Assert-DevEnvironment has already checked.
Sync-LooseFiles -Root $gameRoot | Out-Null

if ((Test-InstalledFiles -Root $gameRoot) -gt 0) {
	exit 1
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

	# Without -devmode the console refuses VF_CHEAT commands,
	# lua_reload_script among them.
	#
	# Started with the executable's own folder as the working directory, which
	# is what a double-click does. The engine resolves user.cfg relative to the
	# working directory, so the graphics settings depend on it.
	Write-Host "[DEPLOY] launching -devmode..."

	Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
		CommandLine = "`"$exe`" -devmode"
		CurrentDirectory = (Split-Path $exe -Parent)
	} | Out-Null
}
