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
$lines = Get-Content "HorseCollisionMod.lua"
$errors = 0
$maxLineLength = 90

# Checks run per line so violations can be reported with a line number, and
# so comment lines can be excluded from the code-shape rules. A doc comment
# reading "-- if X then Y end" is prose, not a single-line if block.
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $num = $i + 1
    $isComment = $line.TrimStart().StartsWith("--")

    if ($line -match '^ ') {
        Write-Host "[LINT] line ${num}: space indentation, use hard tabs" -ForegroundColor Red
        $errors++
    }

    if (-not $isComment -and $line -match '\bif\b.*\bthen\b.*\bend\b') {
        Write-Host "[LINT] line ${num}: single-line if/then/end block" -ForegroundColor Red
        $errors++
    }

    if ($line -match '[ \t]+$') {
        Write-Host "[LINT] line ${num}: trailing whitespace" -ForegroundColor Red
        $errors++
    }

    # Tabs are counted as one character here, which is close enough for
    # spotting the long trailing lines the style guide warns about.
    if ($line.Length -gt $maxLineLength) {
        Write-Host "[LINT] line ${num}: $($line.Length) chars, over $maxLineLength" -ForegroundColor Red
        $errors++
    }

    # Smart quotes and dashes pasted from prose break the ASCII-only
    # assumption the engine's Lua and the animation data both rely on, and
    # they are invisible in most editors.
    if ($line -cmatch '[^\x00-\x7F]') {
        Write-Host "[LINT] line ${num}: non-ASCII character" -ForegroundColor Red
        $errors++
    }
}

if ($errors -gt 0) {
    Write-Host "Build failed: $errors style violation(s). Fix them before packaging." -ForegroundColor Red
    exit 1
}
Write-Host "Code Style Check Passed ($($lines.Count) lines)."

# Syntax check. KCD runs Lua 5.1, and LuaJIT shares its syntax, so it can
# parse the script without the game being involved. A syntax error otherwise
# only shows up as the mod silently not loading, which costs a whole test
# cycle to notice. Skipped with a warning when LuaJIT is not installed, since
# the toolchain is optional.
$luajit = Get-Command luajit -ErrorAction SilentlyContinue

if ($luajit) {
    & $luajit.Source -e "assert(loadfile('HorseCollisionMod.lua'))"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[SYNTAX ERROR] HorseCollisionMod.lua does not parse." -ForegroundColor Red
        exit 1
    }
    Write-Host "Lua Syntax Check Passed."
}
else {
    Write-Host "Lua Syntax Check Skipped (luajit not installed)." -ForegroundColor Yellow
}

# 1. Structure the PAK contents
Copy-Item "HorseCollisionMod.lua" -Destination "$pakDir\"

# Data overrides live under mod_assets/ mirroring the game's own layout and
# are copied in wholesale. They are derived from the game's paks, so they are
# not committed; regenerate them from a local install instead. A fresh clone
# therefore has no mod_assets/ and would silently build a Lua-only mod, so
# generate it here rather than leaving that trap for the next person.
# Tests for the generated file rather than the directory, because a failed or
# interrupted run can leave mod_assets/ present but empty, which would
# otherwise skip generation and fail later with a less obvious message.
if (-not (Test-Path "mod_assets\Animations\Mannequin\ADB\kcd_male_database.adb")) {
    Write-Host "Animation data missing - generating..."
    python build_adb.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[BUILD ERROR] build_adb.py failed. Check the game path at the top of it." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Including data overrides from mod_assets ..."
Copy-Item "mod_assets\*" -Destination "$buildDir\pak\" -Recurse -Force

# The animation chain needs all three files present or the stagger silently
# no-ops in game, which is expensive to diagnose. Fail the build instead.
$required = @(
    "$buildDir\pak\Animations\Mannequin\ADB\kcd_male_database.adb",
    "$buildDir\pak\Animations\Mannequin\ADB\kcd_animationControlledTags.xml",
    "$buildDir\pak\Animations\Mannequin\ADB\wh_female_database.adb",
    "$buildDir\pak\Animations\Mannequin\ADB\wh_female_fragmentids.xml"
)
foreach ($f in $required) {
    if (-not (Test-Path $f)) {
        Write-Host "[BUILD ERROR] missing required asset: $f" -ForegroundColor Red
        exit 1
    }
}

# 2. Create the PAK (zip file)
# Compress-Archive writes Windows path separators into the zip entry names
# (Libs\AI\final\x.xml). CryEngine looks pak entries up by exact path with
# forward slashes, so a backslash pak silently fails to override anything.
# Startup Lua still works because that folder is enumerated rather than looked
# up by path, which is what made this bug so slow to spot. Build the pak entry
# by entry so the names match the vanilla paks (Libs/AI/final/x.xml).
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$pakPath = Join-Path (Resolve-Path $dataDir) "HorseCollisionMod.pak"
if (Test-Path $pakPath) { Remove-Item -Force $pakPath }

$pakRoot = (Resolve-Path "$buildDir\pak").Path
$zip = [System.IO.Compression.ZipFile]::Open($pakPath, "Create")
try {
    Get-ChildItem -Path $pakRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($pakRoot.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $_.FullName, $rel) | Out-Null
        Write-Host "  + $rel"
    }
}
finally {
    $zip.Dispose()
}

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


