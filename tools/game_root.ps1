# Resolves the game install for the PowerShell tools. Dot-source it and call
# Resolve-GameRoot.
#
# Order: the KCD_PATH environment variable, then the usual install locations,
# then every Steam library listed in libraryfolders.vdf, since a Steam install
# can sit on any drive. tools/build_adb.py resolves in the same order.

function Resolve-GameRoot {
	# A path given in KCD_PATH is authoritative. Falling through to a different
	# install when it is wrong would write somewhere the caller did not mean.
	if ($env:KCD_PATH) {
		if (Test-Path (Join-Path $env:KCD_PATH "Bin\Win64\KingdomCome.exe")) {
			return $env:KCD_PATH
		}

		Write-Host "KCD_PATH points at $env:KCD_PATH" -ForegroundColor Red
		Write-Host "but Bin\Win64\KingdomCome.exe is not there."
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
			$library = $match.Groups[1].Value -replace '\\\\', '\'
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

	Write-Host "No Kingdom Come: Deliverance install found." -ForegroundColor Red
	Write-Host "Looked for Bin\Win64\KingdomCome.exe under:"

	foreach ($candidate in $candidates) {
		Write-Host "  $candidate"
	}

	Write-Host ""
	Write-Host 'Point at it with: $env:KCD_PATH = "D:\path\to\game"'
	exit 1
}
