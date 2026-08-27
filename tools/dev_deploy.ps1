# Builds the mod and installs it straight into the game, skipping Vortex.
#
# Vortex's deploy step does one thing that matters here: it copies a pak and a
# manifest into Mods\<name>\ and lists that folder in Mods\mod_order.txt. None
# of that needs a mod manager, and doing it directly removes four manual steps
# from every test cycle.
#
#   .\tools\dev_deploy.ps1                      build, deploy
#   .\tools\dev_deploy.ps1 -Launch              build, deploy, start the game
#   .\tools\dev_deploy.ps1 -NoBuild -Launch     deploy what was built last, start the game
#   .\tools\dev_deploy.ps1 -ParkVortexMod       move the Vortex-installed copy aside first
#   .\tools\dev_deploy.ps1 -GameRoot "D:\..."   use an install somewhere else
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
	[switch]$ScriptOnly,
	[switch]$AnimOnly
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
# after the archive it installed, which is why the game currently holds
# HorseCollisionMod_v200; that means every new build lands in a new folder and
# the old one has to be removed by hand. One stable folder makes deployment a
# straight overwrite.
$devMod = "HorseCollisionMod_dev"
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
function Copy-LooseFiles {
	param (
		[string]$Root,
		[switch]$Script,
		[switch]$Anim
	)

	if ($Script) {
		$looseDir = Join-Path $Root "Data\Scripts\Startup"

		New-Item -ItemType Directory -Force -Path $looseDir | Out-Null
		Copy-Item (Join-Path $repoRoot "src\HorseCollisionMod.lua") `
			-Destination (Join-Path $looseDir "HorseCollisionMod.lua") -Force

		Write-Host "[DEPLOY] loose script updated"
	}

	if ($Anim) {
		$source = Join-Path $repoRoot "mod_assets\Animations\Mannequin\ADB"

		if (-not (Test-Path $source)) {
			Write-Host "[DEPLOY] no mod_assets yet. Run build.ps1 first." -ForegroundColor Yellow
			return
		}

		$looseDir = Join-Path $Root "Data\Animations\Mannequin\ADB"

		New-Item -ItemType Directory -Force -Path $looseDir | Out-Null
		Copy-Item "$source\*" -Destination $looseDir -Force

		Write-Host "[DEPLOY] loose animation databases updated"
	}
}

# The inner loops: push what changed, then reload it from the console. Both
# deliberately skip the running-game guard below, because that guard is about
# the pak, which the engine holds open. A loose file is not locked and can be
# replaced underneath a running game.
if ($ScriptOnly -or $AnimOnly) {
	Copy-LooseFiles -Root $gameRoot -Script:$ScriptOnly -Anim:$AnimOnly

	Write-Host "[DEPLOY] reload it with:" -ForegroundColor Green

	if ($ScriptOnly) {
		Write-Host "         python tools\dev_console.py --reload"
	}

	if ($AnimOnly) {
		Write-Host "         python tools\dev_console.py --anim-reload"
	}

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
	Copy-LooseFiles -Root $gameRoot -Script -Anim

	$cfg = Join-Path $gameRoot "system.cfg"
	$priority = $null

	if (Test-Path $cfg) {
		$match = Select-String -Path $cfg -Pattern '^\s*sys_PakPriority\s*=\s*(\d)' |
			Select-Object -Last 1

		if ($match) {
			$priority = $match.Matches[0].Groups[1].Value
		}
	}

	if ($priority -ne "0") {
		Write-Host "[DEPLOY] warning: sys_PakPriority is '$priority', not 0." -ForegroundColor Yellow
		Write-Host "         Loose files are ignored, so --reload will re-read the packed copy."
	}
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
