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

# The entry point names its parts with Script.ReloadScript and they ship
# alongside it under Scripts/HorseCollisionMod/. The directory is walked rather
# than listed file by file, so moving another section into its own part file
# needs no change here. Sorted so the build log and the pak read the same way
# on every machine.
$partsSrcDir = Join-Path $srcDir "HorseCollisionMod"
$partScripts = @()
if (Test-Path $partsSrcDir) {
    $partScripts = @(Get-ChildItem -Path $partsSrcDir -Filter *.lua -File |
        Sort-Object Name | ForEach-Object { $_.FullName })
}

# Every Lua file the mod ships. The style, scope and syntax checks below all
# run over this set, so a part file is held to the same standard as the entry
# point instead of being packaged unchecked.
$luaScripts = @($modScript, $settingsScript) + $partScripts

$buildDir = Join-Path $repoRoot "build_temp"
$pakDir = "$buildDir\pak\Scripts\Startup"
$modDir = "$buildDir\HorseCollisionMod"
$dataDir = "$modDir\Data"
$releasesDir = Join-Path $repoRoot "releases"

# The version the repository is currently on, regardless of what is being
# built. A prerelease build carries a different -Version, and the release
# checks below read the manifest again for their own comparison; this copy
# exists so the archive step at the end knows which released zip to leave in
# place.
$manifestCurrent = ([xml](Get-Content (Join-Path $srcDir "mod.manifest"))).kcd_mod.info.version

# Clean previous temp build
if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
New-Item -ItemType Directory -Force -Path $pakDir | Out-Null
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

Write-Host "Running Code Style Hooks..."
$errors = 0
$maxLineLength = 90
$luaLineCount = 0

foreach ($luaFile in $luaScripts) {
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

# A local helper used before it is declared.
#
# `local function f` is visible only from its declaration onward. A function
# written above it that calls `f` resolves the name as a global instead, which
# is nil, and the call throws at runtime. It is valid syntax, so the LuaJIT
# parse below accepts it, and the mod loads and then errors on every tick.
$scopeErrors = @()

foreach ($luaFile in $luaScripts) {
    $text = Get-Content $luaFile
    $shortName = Split-Path -Leaf $luaFile

    for ($i = 0; $i -lt $text.Count; $i++) {
        if ($text[$i] -notmatch '^local function (\w+)') { continue }

        $name = $Matches[1]

        for ($j = 0; $j -lt $i; $j++) {
            if ($text[$j] -match '^\s*(--|local function)') { continue }
            if ($text[$j] -match ("\b" + $name + "\s*\(")) {
                $scopeErrors += "{0} line {1}: {2} used before its declaration on line {3}" -f `
                        $shortName, ($j + 1), $name, ($i + 1)
            }
        }
    }
}

if ($scopeErrors.Count -gt 0) {
    foreach ($e in $scopeErrors) {
        Write-Host "[LINT] $e" -ForegroundColor Red
    }
    Write-Host "Build failed: a local helper is used above where it is declared." -ForegroundColor Red
    exit 1
}

# The part file layout, enforced rather than remembered.
#
# The mod's Lua was one 2,558-line file and was split across ten part files by
# concern. Nothing stops the next change putting a new method back in the entry
# point, and that is how the split would be undone: not in one commit anybody
# would question, but a method at a time, each one defensible on its own.
#
# The entry point owns the table, Config, the state tables, the timing
# constants, the settings merge, the animation database redirect, the load
# screen listener and the bootstrap. Behavior belongs in a part file. This list
# is deliberately short and deliberately awkward to extend: adding a name here
# should feel like a decision, because it is one.
$entryPointMethods = @(
    "ApplySettings",
    "RedirectAnimationDatabases",
    "uiActionListener"
)

$layoutErrors = @()
$entryText = Get-Content $modScript

for ($i = 0; $i -lt $entryText.Count; $i++) {
    if ($entryText[$i] -notmatch '^function HorseCollisionMod:(\w+)') { continue }

    $method = $Matches[1]

    if ($entryPointMethods -notcontains $method) {
        $layoutErrors += "HorseCollisionMod.lua line $($i + 1): $method belongs in a part file under src\HorseCollisionMod\, not in the entry point"
    }
}

# Only the entry point creates the table. A part file that rebuilt it would
# discard every method loaded before it, and the order they load in is the only
# thing that would decide what survived.
foreach ($part in $partScripts) {
    $shortName = Split-Path -Leaf $part
    $text = Get-Content $part
    $hasModule = $false

    for ($i = 0; $i -lt $text.Count; $i++) {
        if ($text[$i] -match '^\s*HorseCollisionMod\s*=\s*\{') {
            $layoutErrors += "${shortName} line $($i + 1): only the entry point may create the HorseCollisionMod table"
        }

        if ($text[$i] -match '^--\s*@module\s') { $hasModule = $true }
    }

    # Without one, ldoc drops the file from the reference silently.
    if (-not $hasModule) {
        $layoutErrors += "${shortName}: no LDoc @module header, so it is missing from docs\api"
    }
}

# A part file that exists but is never loaded is the quietest failure the mod
# has. The entry point loads, the methods it expected are nil, and the log says
# nothing. verify_additive.py checks this against a packaged release, which is
# too late to be useful while writing one.
$namedByEntry = @([regex]::Matches((Get-Content $modScript -Raw),
    'Script\.ReloadScript\s*\(\s*"Scripts/HorseCollisionMod/([^"]+)"\s*\)') |
    ForEach-Object { $_.Groups[1].Value })

# Missing from config.ld is quieter still: the file works, and only its
# documentation disappears.
$ldocText = if (Test-Path (Join-Path $repoRoot "config.ld")) {
    Get-Content (Join-Path $repoRoot "config.ld") -Raw
} else { "" }

foreach ($part in $partScripts) {
    $leaf = Split-Path -Leaf $part

    if ($namedByEntry -notcontains $leaf) {
        $layoutErrors += "${leaf}: no Script.ReloadScript line in the entry point, so it never loads"
    }

    if ($ldocText -notmatch [regex]::Escape("src/HorseCollisionMod/$leaf")) {
        $layoutErrors += "${leaf}: not listed in config.ld, so it is missing from the reference"
    }
}

foreach ($named in $namedByEntry) {
    if (-not (Test-Path (Join-Path $partsSrcDir $named))) {
        $layoutErrors += "HorseCollisionMod.lua: loads Scripts/HorseCollisionMod/$named, which does not exist in src"
    }
}

if ($layoutErrors.Count -gt 0) {
    foreach ($e in $layoutErrors) {
        Write-Host "[LAYOUT] $e" -ForegroundColor Red
    }
    Write-Host "Build failed: the part file layout was not respected." -ForegroundColor Red
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

Write-Host "Code Style Check Passed ($luaLineCount lines, $($luaScripts.Count) files)."

# Release gate. A release version is anything without a prerelease suffix, so
# -dev and -diag builds skip every check below and stay free to carry
# diagnostics and a mismatched version.
$isRelease = $Version -match '^\d+\.\d+\.\d+$'

if ($isRelease) {
    # The version lives in three places and a release needs all three to agree.
    # publish_nexus.ps1 catches a manifest mismatch, but only once the zip is
    # already built and only for the manifest.
    $manifestVersion = ([xml](Get-Content (Join-Path $srcDir "mod.manifest"))).kcd_mod.info.version
    $luaVersion = $null

    if ((Get-Content $modScript -Raw) -match 'HorseCollisionMod\.Version\s*=\s*"([^"]+)"') {
        $luaVersion = $Matches[1]
    }

    if ($manifestVersion -ne $Version) {
        Write-Host "Build failed: mod.manifest says $manifestVersion, building $Version." -ForegroundColor Red
        exit 1
    }

    if ($luaVersion -ne $Version) {
        Write-Host "Build failed: HorseCollisionMod.Version is $luaVersion, building $Version." -ForegroundColor Red
        exit 1
    }

    # The LDoc header carries the version too, and it is the one that goes
    # stale unnoticed because nothing reads it back. Checked in every part
    # file that declares one, not just the entry point, since a part header is
    # read even less often than the entry point's.
    # Every mismatch is collected and reported together. Failing on the first
    # one turns a version bump into a build, fix, build cycle repeated once per
    # file, which is how twelve files were bumped one at a time. The remedy is
    # named in the message, because `set_version.py` does all of them at once.
    $staleReleases = @()

    foreach ($script in (@($modScript) + $partScripts)) {
        $raw = Get-Content $script -Raw
        if ($raw -notmatch '@release\s+([^\s]+)') { continue }

        if ($Matches[1] -ne $Version) {
            $staleReleases += "  $(Split-Path -Leaf $script) says $($Matches[1])"
        }
    }

    if ($staleReleases.Count -gt 0) {
        Write-Host "Build failed: $($staleReleases.Count) @release tag(s) do not say $Version." -ForegroundColor Red
        $staleReleases | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "         Fix them all at once:  python tools\set_version.py $Version"
        exit 1
    }

    # A diagnostic left on writes thousands of lines to a player's kcd.log.
    # The settings file ships and overrides the default, so the default being
    # correct is not enough.
    if ((Get-Content $settingsScript -Raw) -match 'DiagnoseMisses\s*=\s*true') {
        Write-Host "Build failed: DiagnoseMisses is on in the shipped settings." -ForegroundColor Red
        exit 1
    }

    Write-Host "Release Checks Passed (version $Version, diagnostics off)."

    # The number has to follow from what changed, not from a guess made at
    # release time.
    python (Join-Path $toolsDir "version_check.py") --release $Version

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed: version and changelog disagree." -ForegroundColor Red
        exit 1
    }

    # Documentation that describes a build the project has moved past is what
    # a reader meets first, and nothing else checks it.
    #
    # Repository scope only. Every merge to main takes a plain version and
    # builds at it, and almost none of those are published, so the mod page is
    # checked by publish_nexus.ps1 where it belongs rather than blocking a
    # routine build on copy nobody is about to read.
    python (Join-Path $toolsDir "pre_release_check.py") --merge

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed: stale references to an older build." -ForegroundColor Red
        exit 1
    }
} else {
    # Advisory on every development build, so player-visible work that has not
    # been written down is noticed while it is still fresh.
    python (Join-Path $toolsDir "version_check.py")
}

# Syntax check. KCD runs Lua 5.1, and LuaJIT shares its syntax, so it can
# parse the script without the game being involved. A syntax error otherwise
# only shows up as the mod silently not loading, which costs a whole test
# cycle to notice. Skipped with a warning when LuaJIT is not installed, since
# the toolchain is optional.
$luajit = Get-Command luajit -ErrorAction SilentlyContinue

if ($luajit) {
    # Lua treats a backslash in a quoted string as an escape, so the path
    # handed to loadfile is converted to forward slashes.
    foreach ($script in $luaScripts) {
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

# The parts go beside Scripts/Startup/, not inside it. The engine enumerates
# Startup and executes what it finds, in no guaranteed order and without the
# entry point's knowledge; a part file there would run before the mod's table
# exists and then run again when the entry point named it. Here they are only
# ever reached by the Script.ReloadScript calls at the foot of the entry point.
if ($partScripts.Count -gt 0) {
    $pakPartsDir = "$buildDir\pak\Scripts\HorseCollisionMod"
    New-Item -ItemType Directory -Force -Path $pakPartsDir | Out-Null

    foreach ($part in $partScripts) {
        Copy-Item $part -Destination "$pakPartsDir\"
    }
}

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

# A stale armor table from before the mod read the game's tables directly. It
# is a Startup script, so leaving one in mod_assets would ship it and define a
# global nothing reads. Removed rather than ignored, because mod_assets is
# generated and not committed, so a working copy can still be carrying one.
$staleItemData = Join-Path $assetsDir "Scripts\Startup\HorseCollisionMod_ItemData.lua"

if (Test-Path $staleItemData) {
    Remove-Item -Force $staleItemData
    Write-Host "Removed the superseded armor table from mod_assets."
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

# Nothing beyond that set may ship. A stale file left in mod_assets is still an
# override, and would quietly change which chain entities resolve through
# without altering a single line this build prints.
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

# Same defect as the pak above, and it reached players. Compress-Archive writes
# Windows separators into the entry names, so the archive carries one entry
# literally named "Data\HorseCollisionMod.pak" rather than a Data folder holding
# the pak. File Explorer hides it by treating the backslash as a separator, which
# is why manual testing never caught it, but the ZIP specification requires
# forward slashes and every tool that follows it, 7-Zip and Vortex included,
# extracts a single oddly named file into the mod root. The mod then does not
# load at all. Build the archive entry by entry, as the pak is built.
$modRoot = (Resolve-Path $modDir).Path
$outArchive = [System.IO.Compression.ZipFile]::Open($outZip, "Create")
try {
    Get-ChildItem -Path $modRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($modRoot.Length + 1).Replace("\", "/")
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $outArchive, $_.FullName, $rel) | Out-Null
    }
}
finally {
    $outArchive.Dispose()
}

# A backslash here ships a broken install, and it did once. The archive is read
# back and refused rather than trusted, because the failure is invisible in File
# Explorer and only appears on a player's machine.
$verify = [System.IO.Compression.ZipFile]::OpenRead($outZip)
try {
    $bad = @($verify.Entries | Where-Object { $_.FullName.Contains("\") })
}
finally {
    $verify.Dispose()
}
if ($bad.Count -gt 0) {
    Write-Host "[BUILD ERROR] archive entries use backslash separators:" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Red }
    Remove-Item -Force $outZip
    exit 1
}

# Cleanup
Remove-Item -Recurse -Force $buildDir

# Superseded builds move into releases\archive.
#
# Every build of every branch lands here, and a session of small slices leaves
# dozens. That is not merely untidy: publish_nexus.ps1 and pre_release_check.py
# resolve a zip by name, and the one thing worse than a full directory is
# picking the wrong file out of it.
#
# Nothing is deleted, only moved, which matters more than it first appears: a
# tagged release cannot be rebuilt. Asked for its own version number this
# script refuses twice, once because the manifest has moved on and once because
# version_check.py sees that version already tagged and demands the next one.
# The zip in this directory is therefore the only copy of what was released,
# and archiving is the whole safety net rather than a convenience.
#
# So two names stay at the top level. The build just made, and the version the
# manifest currently names, so that a prerelease built while testing does not
# push the release it is testing out of reach of the publishing tools.
$archiveDir = Join-Path $releasesDir "archive"

$keep = @("HorseCollisionMod_v$Version.zip",
          "HorseCollisionMod_v$manifestCurrent.zip")

$stale = @(Get-ChildItem -Path $releasesDir -Filter "HorseCollisionMod_v*.zip" -File |
    Where-Object { $keep -notcontains $_.Name })

if ($stale.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null

    foreach ($old in $stale) {
        Move-Item $old.FullName (Join-Path $archiveDir $old.Name) -Force
    }

    Write-Host "Archived $($stale.Count) superseded build(s) to releases\archive."
}

Write-Host "Successfully built $outZip"


