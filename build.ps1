param (
    [string]$Version = "dev"
)

Write-Host "Building HorseCollisionMod version $Version..."

# Everything resolves from the repository root rather than the working
# directory, so the script behaves the same run as .\build.ps1 from the root
# or invoked by another tool from somewhere else.
$repoRoot = Split-Path -Parent $PSCommandPath
$srcDir = Join-Path $repoRoot "src"
$toolsDir = Join-Path $repoRoot "tools"
$assetsDir = Join-Path $repoRoot "mod_assets"
$modScript = Join-Path $srcDir "HorseCollisionMod.lua"
$settingsScript = Join-Path $srcDir "HorseCollisionMod_Settings.lua"

$buildDir = Join-Path $repoRoot "build_temp"
$pakDir = "$buildDir\pak\Scripts\Startup"
$modDir = "$buildDir\HorseCollisionMod"
$dataDir = "$modDir\Data"
$releasesDir = Join-Path $repoRoot "releases"

# Clean previous temp build
if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
New-Item -ItemType Directory -Force -Path $pakDir | Out-Null
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

Write-Host "Running Code Style Hooks..."
$errors = 0
$maxLineLength = 90
$luaLineCount = 0

foreach ($luaFile in @($modScript, $settingsScript)) {
$shortName = Split-Path -Leaf $luaFile
$lines = Get-Content $luaFile
$luaLineCount += $lines.Count

# Checks run per line so violations can be reported with a line number, and
# so comment lines can be excluded from the code-shape rules. A doc comment
# reading "-- if X then Y end" is prose, not a single-line if block.
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $num = $i + 1
    $isComment = $line.TrimStart().StartsWith("--")

    if ($line -match '^ ') {
        Write-Host "[LINT] ${shortName} line ${num}: space indentation, use hard tabs" -ForegroundColor Red
        $errors++
    }

    if (-not $isComment -and $line -match '\bif\b.*\bthen\b.*\bend\b') {
        Write-Host "[LINT] ${shortName} line ${num}: single-line if/then/end block" -ForegroundColor Red
        $errors++
    }

    if ($line -match '[ \t]+$') {
        Write-Host "[LINT] ${shortName} line ${num}: trailing whitespace" -ForegroundColor Red
        $errors++
    }

    # Tabs are counted as one character here, which is close enough for
    # spotting the long trailing lines the style guide warns about.
    if ($line.Length -gt $maxLineLength) {
        Write-Host "[LINT] ${shortName} line ${num}: $($line.Length) chars, over $maxLineLength" -ForegroundColor Red
        $errors++
    }

    # Smart quotes and dashes pasted from prose break the ASCII-only
    # assumption the engine's Lua and the animation data both rely on, and
    # they are invisible in most editors.
    if ($line -cmatch '[^\x00-\x7F]') {
        Write-Host "[LINT] ${shortName} line ${num}: non-ASCII character" -ForegroundColor Red
        $errors++
    }
}
}

if ($errors -gt 0) {
    Write-Host "Build failed: $errors style violation(s). Fix them before packaging." -ForegroundColor Red
    exit 1
}

# Stray control characters in any tracked text file.
#
# A scripted edit that writes a path like ".\build.ps1" through a tool that
# interprets escapes turns the \b into a literal backspace, and \v into a
# vertical tab. The result is invisible in an editor, survives review, and has
# reached this repository four times: it broke dev_deploy.ps1's build path and
# corrupted two documented commands. Cheaper to fail the build than to keep
# noticing it by hand.
$controlChars = @()

foreach ($tracked in (git ls-files)) {
    if ($tracked -notmatch '\.(md|ps1|py|lua|ld|json|manifest|css|html|xml)$') { continue }

    $full = Join-Path $repoRoot $tracked
    if (-not (Test-Path $full)) { continue }

    $hits = [regex]::Matches([System.IO.File]::ReadAllText($full),
                             '[\x00-\x08\x0B\x0C\x0E-\x1F]')
    foreach ($h in $hits) {
        $controlChars += "{0}: 0x{1:X2} at offset {2}" -f $tracked, [int][char]$h.Value, $h.Index
    }
}

if ($controlChars.Count -gt 0) {
    foreach ($c in $controlChars) {
        Write-Host "[LINT] control character - $c" -ForegroundColor Red
    }
    Write-Host "Build failed: stray control characters." -ForegroundColor Red
    exit 1
}

Write-Host "Code Style Check Passed ($luaLineCount lines, 2 files)."

# Syntax check. KCD runs Lua 5.1, and LuaJIT shares its syntax, so it can
# parse the script without the game being involved. A syntax error otherwise
# only shows up as the mod silently not loading, which costs a whole test
# cycle to notice. Skipped with a warning when LuaJIT is not installed, since
# the toolchain is optional.
$luajit = Get-Command luajit -ErrorAction SilentlyContinue

if ($luajit) {
    # Lua treats a backslash in a quoted string as an escape, so the path
    # handed to loadfile is converted to forward slashes.
    foreach ($script in @($modScript, $settingsScript)) {
        $luaPath = $script.Replace([char]92, [char]47)
        & $luajit.Source -e "assert(loadfile('$luaPath'))"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[SYNTAX ERROR] $(Split-Path -Leaf $script) does not parse." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "Lua Syntax Check Passed."
}
else {
    Write-Host "Lua Syntax Check Skipped (luajit not installed)." -ForegroundColor Yellow
}

# 1. Structure the PAK contents
Copy-Item $modScript -Destination "$pakDir\"
Copy-Item $settingsScript -Destination "$pakDir\"

# Data overrides live under mod_assets/ mirroring the game's own layout and
# are copied in wholesale. They are derived from the game's paks, so they are
# not committed; regenerate them from a local install instead. A fresh clone
# therefore has no mod_assets/ and would silently build a Lua-only mod, so
# generate it here rather than leaving that trap for the next person.
# Tests for the generated file rather than the directory, because a failed or
# interrupted run can leave mod_assets/ present but empty, which would
# otherwise skip generation and fail later with a less obvious message.
if (-not (Test-Path (Join-Path $assetsDir "Animations\Mannequin\ADB\hcm_male_database.adb"))) {
    Write-Host "Animation data missing - generating..."
    python (Join-Path $toolsDir "build_adb.py")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[BUILD ERROR] build_adb.py failed. Check the game path at the top of it." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Including data overrides from mod_assets ..."
Copy-Item "$assetsDir\*" -Destination "$buildDir\pak\" -Recurse -Force

# The animation chain needs every one of these present or the stagger silently
# no-ops in game, which is expensive to diagnose. Fail the build instead.
#
# These are the additive layout, which claims no vanilla filename: a parent
# database per gender referencing the untouched vanilla file in its own pak,
# the mod's own fragments, and the declarations those fragments need.
# Any file under a vanilla name is a bug, not an alternative layout: it would
# override the file the parent database references, silently defeating the
# whole arrangement without changing anything this build prints.
$adb = "$buildDir\pak\Animations\Mannequin\ADB"

# The exact file set the mod ships. Two of these carry vanilla names on
# purpose: they are small declaration files, and owning them is far cheaper
# than the alternative of restating 123 KB of fragment and controller
# definitions under mod names, which put this mod in the resolution path of
# every human animation and broke unrelated ones. See TECHNICAL_DETAILS.md.
$required = @(
    "$adb\hcm_male_database.adb",
    "$adb\hcm_female_database.adb",
    "$adb\kcd_animationControlledTags.xml",
    "$adb\wh_female_fragmentids.xml"
)

# Nothing beyond that set may ship. A leftover from an earlier layout would
# still be an override and would quietly change which chain entities resolve
# through, without altering a single line this build prints.
$allowed = $required | ForEach-Object { Split-Path -Leaf $_ }
$unexpected = Get-ChildItem $adb -File -ErrorAction SilentlyContinue |
    Where-Object { $allowed -notcontains $_.Name }

if ($unexpected) {
    foreach ($f in $unexpected) {
        Write-Host "[BUILD ERROR] unexpected animation file: $($f.Name)" -ForegroundColor Red
    }
    Write-Host "Delete mod_assets\ and rebuild." -ForegroundColor Red
    exit 1
}

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
Copy-Item (Join-Path $srcDir "mod.manifest") -Destination "$modDir\"
$readme = Join-Path $repoRoot "README.md"
if (Test-Path $readme) { Copy-Item $readme -Destination "$modDir\" }

# 4. Create the final Release ZIP
if (-not (Test-Path $releasesDir)) { New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null }
$outZip = "$releasesDir\HorseCollisionMod_v$Version.zip"
if (Test-Path $outZip) { Remove-Item -Force $outZip }
Compress-Archive -Path "$modDir\*" -DestinationPath $outZip -Force

# Cleanup
Remove-Item -Recurse -Force $buildDir

Write-Host "Successfully built $outZip"


