param (
    [string]$Version = "dev"
)

Write-Host "Building HorseCollisionMod version $Version..."

$buildDir = "build_temp"
$pakDir = "$buildDir\pak\Scripts\Startup"
$modDir = "$buildDir\HorseCollisionMod"
$dataDir = "$modDir\Data"
$releasesDir = "releases"

# Clean previous temp build
if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
New-Item -ItemType Directory -Force -Path $pakDir | Out-Null
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

Write-Host "Running Code Style Hooks..."
$code = Get-Content "HorseCollisionMod.lua" -Raw
$errors = 0

if ($code -match '(?m)^ +') {
    Write-Host "[LINT ERROR] Spaces detected for indentation instead of tabs!" -ForegroundColor Red
    $errors++
}

if ($code -match 'if.*?then.*?end') {
    Write-Host "[LINT ERROR] Single-line if/then block detected!" -ForegroundColor Red
    $errors++
}

if ($errors -gt 0) {
    Write-Host "Build failed due to style violations. Fix them before packaging." -ForegroundColor Red
    exit 1
}
Write-Host "Code Style Check Passed."

# 1. Structure the PAK contents
Copy-Item "HorseCollisionMod.lua" -Destination "$pakDir\"

if (Test-Path "mod_xmls\Libs\AI\final\sb_switch_hitreactions.xml") {
    New-Item -ItemType Directory -Force -Path "$buildDir\pak\Libs\AI\final" | Out-Null
    Copy-Item "mod_xmls\Libs\AI\final\sb_switch_hitreactions.xml" -Destination "$buildDir\pak\Libs\AI\final\"
}

# 2. Create the PAK (zip file)
Compress-Archive -Path "$buildDir\pak\*" -DestinationPath "$dataDir\HorseCollisionMod.zip" -Force
Rename-Item "$dataDir\HorseCollisionMod.zip" "HorseCollisionMod.pak"

# 3. Structure the Mod contents
Copy-Item "mod.manifest" -Destination "$modDir\"
if (Test-Path "README.md") { Copy-Item "README.md" -Destination "$modDir\" }

# 4. Create the final Release ZIP
if (-not (Test-Path $releasesDir)) { New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null }
$outZip = "$releasesDir\HorseCollisionMod_v$Version.zip"
if (Test-Path $outZip) { Remove-Item -Force $outZip }
Compress-Archive -Path "$modDir\*" -DestinationPath $outZip -Force

# Cleanup
Remove-Item -Recurse -Force $buildDir

Write-Host "Successfully built $outZip"


