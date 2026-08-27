<#
.SYNOPSIS
    Publishes a built release zip to the HorseCollisionMod page on Nexus Mods.

.DESCRIPTION
    Runs the Nexus Mods v3 upload flow end to end so a release does not have to
    go through the browser:

        POST /uploads                     start a session, get a presigned URL
        PUT  <presigned_url>              the zip itself
        POST /uploads/{id}/finalise       close the session
        GET  /uploads/{id}                poll until state is available
        POST /mod-files/{id}/versions     turn the upload into a published version
        POST /mods/{id}/changelogs        optional, appends changelog text

    The two identifiers in the mod's site URLs are not the ones the API wants,
    so they are resolved first:

        nexusmods.com/kingdomcomedeliverance/mods/2338
          -> GET /games/{domain}/mods/2338    -> data.id       (mod id)

        ...?tab=files&file_id=10219
          -> GET /games/{domain}/mod-file-versions/10219
                                             -> data.file.id  (mod file id)

    The site's file_id names a mod file *version*, while an upload is attached
    to the mod *file* that owns it. That second call is the bridge.

    What this deliberately does not do: create a mod page, or edit the mod
    description. Neither has an API endpoint, so the page copy is still pasted
    in by hand on each release.

    Acceptable use. Nexus Mods permit a personal API key for personal use, which
    is what this is: one author publishing to one mod page, the key read from
    the environment at the moment of use, never stored by anything and never
    used without the author starting the run. Every request identifies itself
    with Application-Name and Application-Version as the policy requires.

    If this ever became a tool other people run against their own mod pages,
    that is a public-facing application and it would have to be registered with
    Nexus Mods first, at support@nexusmods.com, rather than shipping on personal
    keys.

    https://help.nexusmods.com/article/114-api-acceptable-use-policy

.PARAMETER Version
    The version to publish, e.g. 2.1.0. Must match the version in the zip's
    mod.manifest, and must not already exist on the mod file.

.PARAMETER DryRun
    Resolve, validate and report, then stop before anything is uploaded.

.EXAMPLE
    tools\publish_nexus.ps1 -Version 2.1.0 -DryRun

.EXAMPLE
    tools\publish_nexus.ps1 -Version 2.1.0 -ChangelogFile releases\notes-2.1.0.md
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Version,

    # Defaults to releases\HorseCollisionMod_v<Version>.zip.
    [string]$Zip,

    [string]$Changelog,
    [string]$ChangelogFile,

    # Shown as the file name on the mod page. The API caps this at 50
    # characters and allows only [a-zA-Z0-9 _'().-].
    [string]$DisplayName = "HorseCollisionMod",
    [string]$Description,

    [ValidateSet("main", "optional", "miscellaneous")]
    [string]$Category = "main",

    # Read from the environment so the key never has to appear in a command
    # line, in shell history, or in a file in the repository.
    [string]$ApiKey = $env:NEXUS_API_KEY,

    # Public identifiers, straight out of the mod's own URLs.
    [string]$GameDomain = "kingdomcomedeliverance",
    [string]$ModPageId = "2338",
    [string]$FilePageId = "10219",

    # Release defaults: the new file becomes the mod manager download and the
    # mod page's version follows it. Pass -Primary $false or
    # -UpdateModVersion $false for a side upload that should not do either.
    [bool]$Primary = $true,
    [bool]$UpdateModVersion = $true,
    [bool]$AllowModManagerDownload = $true,
    [bool]$ShowRequirementsPopUp = $false,

    # Archives the previous version rather than leaving it listed.
    [switch]$ArchiveExisting,

    # An upload id from a previous run, to retry publishing without sending the
    # zip a second time. Printed by this script when a run fails after the
    # upload has already succeeded.
    [string]$ResumeUploadId,

    [switch]$DryRun,

    # Skips the confirmation prompt and the manifest and pre-release checks.
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 still negotiates TLS 1.0 by default on some machines,
# which the API rejects outright.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ApiBase = "https://api.nexusmods.com/v3"

# Nexus Mods' acceptable use policy requires every request to identify the
# client, and forbids metadata that is blank or impersonates another
# application. The name is meant to stay constant across versions of the tool,
# so only AppVersion moves.
#
# https://help.nexusmods.com/article/114-api-acceptable-use-policy
$AppName = "HorseCollisionMod-publish"
$AppVersion = "1.0.0"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

# Turns a thrown message into a plain line instead of PowerShell's error record
# with its source extent and CategoryInfo block, which buries the sentence that
# actually says what to do.
trap {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

# Errors come back as RFC 9457 problem+json, but Invoke-RestMethod throws on a
# non-2xx and the useful part is in the response stream rather than the
# exception message. Without this a 422 reads as "The remote server returned an
# error: (422) Unprocessable Entity." and says nothing about which field failed.
function Read-ProblemDetails {
    param ($ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    if (-not $response) { return $ErrorRecord.Exception.Message }

    try {
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $body = $reader.ReadToEnd()
        $reader.Close()
    }
    catch {
        return $ErrorRecord.Exception.Message
    }

    if (-not $body) { return $ErrorRecord.Exception.Message }

    try {
        $problem = $body | ConvertFrom-Json
        $text = "$($problem.status) $($problem.title): $($problem.detail)"
        if ($problem.errors) {
            foreach ($field in $problem.errors.PSObject.Properties) {
                $text += "`n    $($field.Name): $($field.Value -join '; ')"
            }
        }
        return $text
    }
    catch {
        return $body
    }
}

function Invoke-NexusApi {
    param (
        [string]$Method,
        [string]$Path,
        $Body
    )

    $params = @{
        Method  = $Method
        Uri     = "$ApiBase$Path"
        Headers = @{
            "apikey"              = $ApiKey
            "Accept"              = "application/json"
            "Application-Name"    = $AppName
            "Application-Version" = $AppVersion
        }
    }

    if ($null -ne $Body) {
        # Encoded explicitly: 5.1 sends a -Body string as ISO-8859-1 unless the
        # charset is spelled out, which mangles anything non-ASCII in a
        # changelog.
        $json = $Body | ConvertTo-Json -Depth 6 -Compress
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params.ContentType = "application/json; charset=utf-8"
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        throw "$Method $Path failed.`n  $(Read-ProblemDetails $_)"
    }
}

# ---------------------------------------------------------------------------
# Local checks, before anything leaves the machine
# ---------------------------------------------------------------------------

# The API's own constraint. Checked here so a typo fails in a second rather
# than after the upload.
if ($Version -notmatch '^[a-zA-Z0-9.-]+$') {
    throw "Version '$Version' has characters the API rejects. Allowed: letters, digits, dot, hyphen."
}
if ($Version.Length -gt 50) {
    throw "Version '$Version' is longer than the 50 character limit."
}

if (-not $Zip) {
    $Zip = Join-Path $repoRoot "releases\HorseCollisionMod_v$Version.zip"
}
if (-not (Test-Path $Zip)) {
    throw "No release zip at $Zip. Build it first: .\build.ps1 -Version $Version"
}
$zipItem = Get-Item $Zip
$zipBytes = $zipItem.Length

if ($ChangelogFile) {
    if (-not (Test-Path $ChangelogFile)) { throw "No changelog file at $ChangelogFile." }
    $Changelog = Get-Content $ChangelogFile -Raw
}

# A dev build reaching the mod page is the expensive mistake this script could
# otherwise make faster than the browser did.
if (-not $Force -and $Version -match 'dev|alpha|beta|rc') {
    throw "Version '$Version' looks like a pre-release. Pass -Force if that is deliberate."
}

# build.ps1 copies src\mod.manifest verbatim, so its <version> is maintained by
# hand and can drift from the -Version the zip was built with. The manifest is
# what the game reads, so a mismatch ships a mod that reports the wrong version
# to anyone debugging it.
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipItem.FullName)
try {
    # Compress-Archive stores Windows separators, so the release zip really
    # does hold "Data\HorseCollisionMod.pak". Harmless for the outer zip, which
    # is unpacked by Vortex or by hand rather than looked up by path, and the
    # pak inside it is built entry by entry to get forward slashes. Worth
    # knowing that Python's zipfile quietly normalizes these on read while .NET
    # reports them as stored, so the two disagree about the same file.
    $names = $archive.Entries | ForEach-Object { $_.FullName.Replace([char]92, [char]47) }

    foreach ($required in @("mod.manifest", "Data/HorseCollisionMod.pak")) {
        if ($names -notcontains $required) {
            throw "$($zipItem.Name) has no $required. It is not a HorseCollisionMod release zip."
        }
    }

    $entry = $archive.GetEntry("mod.manifest")
    $reader = New-Object System.IO.StreamReader($entry.Open())
    $manifest = $reader.ReadToEnd()
    $reader.Close()
}
finally {
    $archive.Dispose()
}

$manifestVersion = $null
if ($manifest -match '<version>\s*(.+?)\s*</version>') { $manifestVersion = $Matches[1] }

if ($manifestVersion -ne $Version) {
    $message = "mod.manifest says version $manifestVersion but you are publishing $Version." +
               "`n  Update <version> in src\mod.manifest and rebuild, or pass -Force."
    if (-not $Force) { throw $message }
    Write-Host "[WARN] $message" -ForegroundColor Yellow
}

if (-not $ApiKey) {
    throw ("No API key. Get one from https://www.nexusmods.com/settings/api-keys, then:" +
           "`n    " + '$env:NEXUS_API_KEY' + " = '<key>'" +
           "`n  Set it in the session rather than committing it anywhere.")
}

# ---------------------------------------------------------------------------
# Resolve the site's identifiers into the API's
# ---------------------------------------------------------------------------

Write-Host "Resolving mod $ModPageId on $GameDomain ..."

$mod = (Invoke-NexusApi GET "/games/$GameDomain/mods/$ModPageId").data
$modId = $mod.id

$fileVersion = (Invoke-NexusApi GET "/games/$GameDomain/mod-file-versions/$FilePageId").data
$modFileId = $fileVersion.file.id

Write-Host "  mod:      $($mod.name) [$modId]"
Write-Host "  mod file: $($fileVersion.file.name) [$modFileId]"

# Confirms the file belongs to this mod. Publishing a version onto a mod file
# from someone else's page is exactly the sort of thing a wrong id would do
# quietly.
$modFiles = (Invoke-NexusApi GET "/mods/$modId/files").data.mod_files
$owned = $modFiles | Where-Object { $_.id -eq $modFileId }
if (-not $owned) {
    throw ("Mod file $modFileId is not on mod $ModPageId. Check -FilePageId." +
           "`n  Files on this mod: " + (($modFiles | ForEach-Object { "$($_.name) [$($_.id)]" }) -join ", "))
}
Write-Host "  versions: $($owned.versions_count) ($($owned.archived_count) archived)"

$existing = (Invoke-NexusApi GET "/mod-files/$modFileId/versions").data.versions
$clash = $existing | Where-Object { $_.version -eq $Version }
if ($clash) {
    # Not a failure so much as nothing to do, and re-running a publish is a
    # normal thing to do after a partial one. Given its own exit code so a
    # wrapper can tell "already there" from "went wrong".
    Write-Host ""
    Write-Host "Version $Version is already on the page, uploaded $($clash[0].uploaded_at)." -ForegroundColor Yellow
    Write-Host "Nothing to do. Bump the version if this was meant to be a new release."
    exit 2
}

# ---------------------------------------------------------------------------
# Report and confirm
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "About to publish:" -ForegroundColor Cyan
Write-Host "  file          $($zipItem.Name) ($([math]::Round($zipBytes / 1KB, 1)) KB)"
Write-Host "  version       $Version"
Write-Host "  display name  $DisplayName"
Write-Host "  category      $Category"
Write-Host "  primary       $Primary"
Write-Host "  bump page     $UpdateModVersion"
Write-Host "  archive prev  $($ArchiveExisting.IsPresent)"
if ($Changelog) {
    $firstLine = ($Changelog -split "`n")[0]
    Write-Host "  changelog     $($Changelog.Length) chars, starting '$firstLine'"
}
else {
    Write-Host "  changelog     none"
}
Write-Host ""

if ($DryRun) {
    Write-Host "Dry run, stopping before upload." -ForegroundColor Yellow
    exit 0
}

if (-not $Force) {
    $answer = Read-Host "This publishes to the live mod page. Type the version to confirm"
    if ($answer -ne $Version) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

$uploadId = $ResumeUploadId

if ($uploadId) {
    Write-Host "Resuming upload $uploadId ..."
}
else {
    # Files over 100 MiB need the S3 multipart flow instead. This mod's release
    # zip is around 190 KB, so the single PUT path is the only one implemented;
    # fail clearly rather than silently truncating if that ever changes.
    if ($zipBytes -gt 100MB) {
        throw ("$($zipItem.Name) is $([math]::Round($zipBytes / 1MB, 1)) MB, over the 100 MiB single-part limit." +
               "`n  POST /uploads/multipart is needed for this and is not implemented here.")
    }

    Write-Host "Creating upload session ..."
    $upload = (Invoke-NexusApi POST "/uploads" @{
        size_bytes = $zipBytes
        filename   = $zipItem.Name
    }).data

    $uploadId = $upload.id
    Write-Host "  upload $uploadId"

    # The filename is part of the presigned URL's signature, so S3 rejects the
    # PUT outright if this header is missing or does not match the filename
    # sent above.
    $disposition = 'attachment; filename="' + $zipItem.Name + '"'

    # 5.1 renders a progress bar per chunk, which dominates the runtime of an
    # Invoke-WebRequest upload.
    $previousProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Write-Host "Uploading $([math]::Round($zipBytes / 1KB, 1)) KB ..."
        Invoke-WebRequest -Uri $upload.presigned_url -Method Put `
            -InFile $zipItem.FullName `
            -Headers @{ "Content-Disposition" = $disposition } `
            -ContentType "application/octet-stream" | Out-Null
    }
    catch {
        throw "Upload to the presigned URL failed.`n  $(Read-ProblemDetails $_)"
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    Write-Host "Finalising ..."
    Invoke-NexusApi POST "/uploads/$uploadId/finalise" | Out-Null
}

# The upload is processed asynchronously, and claiming it before it is ready
# fails with a 422 that reads like a bad request.
Write-Host "Waiting for the upload to become available ..."
$state = $null
for ($attempt = 1; $attempt -le 40; $attempt++) {
    $state = (Invoke-NexusApi GET "/uploads/$uploadId").data.state
    if ($state -eq "available") { break }

    # Backs off rather than hammering a fixed interval. Excessive consumption
    # is what the acceptable use policy rate limits for, and a poll loop is the
    # easiest place in this script to be a bad citizen by accident. Reaches
    # roughly three minutes of waiting in 40 requests instead of 90.
    Start-Sleep -Seconds ([Math]::Min(5, 1 + [Math]::Floor($attempt / 3)))
}

if ($state -ne "available") {
    throw ("Upload $uploadId is still '$state' after about three minutes." +
           "`n  The data is uploaded. Retry the publish without re-sending it:" +
           "`n    tools\publish_nexus.ps1 -Version $Version -ResumeUploadId $uploadId")
}

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------

$request = @{
    upload_id                    = $uploadId
    name                         = $DisplayName
    version                      = $Version
    file_category                = $Category
    primary_mod_manager_download = $Primary
    allow_mod_manager_download   = $AllowModManagerDownload
    show_requirements_pop_up     = $ShowRequirementsPopUp
    update_mod_version           = $UpdateModVersion
    archive_existing_file        = $ArchiveExisting.IsPresent
}
if ($Description) { $request.description = $Description }

Write-Host "Publishing version $Version ..."
try {
    $published = (Invoke-NexusApi POST "/mod-files/$modFileId/versions" $request).data
}
catch {
    Write-Host ("The upload succeeded but publishing did not. Retry without re-uploading:" +
                "`n    tools\publish_nexus.ps1 -Version $Version -ResumeUploadId $uploadId") -ForegroundColor Yellow
    throw
}

Write-Host "  version id $($published.id)" -ForegroundColor Green

# Last, and separately, because it is additive: a failed publish should not
# leave changelog text on the page for a version that does not exist, and a
# repeated call appends rather than replaces.
if ($Changelog) {
    Write-Host "Adding changelog ..."
    Invoke-NexusApi POST "/mods/$modId/changelogs" @{
        version   = $Version
        changelog = $Changelog
    } | Out-Null
}

Write-Host ""
Write-Host "Published $Version." -ForegroundColor Green
Write-Host "  https://www.nexusmods.com/$GameDomain/mods/$ModPageId`?tab=files"
Write-Host ""
Write-Host "Still manual: the mod page description has no API endpoint." -ForegroundColor Yellow
