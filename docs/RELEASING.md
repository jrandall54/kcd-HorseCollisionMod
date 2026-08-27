# Releasing

Building the mod, regenerating its API reference, and publishing it to Nexus Mods.
None of this is needed to play or to change settings; see `README.md` for that.

## Build

Requires PowerShell and Python 3. LuaJIT is optional and adds a syntax check.

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "2.1.0"
```

Animation data is generated from your own game install rather than committed, so the
first build runs `tools/build_adb.py` for you. It finds the game automatically:
`--game-root`, then the `KCD_PATH` environment variable, then the usual Steam and GOG
locations, then every Steam library listed in `libraryfolders.vdf`. If none of those
find it, it says so and lists everywhere it looked.

Output goes to `releases\`.

The build produces the additive layout by default: every file is named `hcm_*` and no
vanilla filename is claimed. `tools/build_adb.py --replace` builds the pre-2.1.0 layout
that replaced whole databases, and `build.ps1` will refuse it, since mixing the two
silently defeats the additive one.

`build.ps1` copies `src/mod.manifest` verbatim, so bump its `<version>` before
building. The publish step refuses to upload a zip whose manifest disagrees with the
version being published.

## Publish

`tools/publish_nexus.ps1` uploads a built zip to the mod page through the Nexus Mods
v3 API, so a release does not have to go through the browser.

Once, to store your API key:

```
.\tools\publish_nexus.ps1 -SaveApiKey
```

Then per release:

```
.\tools\publish_nexus.ps1 -Version 2.1.0 -DryRun
.\tools\publish_nexus.ps1 -Version 2.1.0 -ChangelogFile releases\notes-2.1.0.md
```

This is a release step, run by hand on a tagged version. It is not wired into anything
that runs on a push.

`-DryRun` resolves and validates everything, then stops before uploading. Without it
the script prints what it is about to publish and asks you to type the version back
before anything reaches the live page.

Before uploading it checks that the version string is one the API accepts, that the
zip really is a mod release, that the version in the zip's `mod.manifest` matches the
one being published, and that the version is not already on the page. `-Force` skips
those and the confirmation prompt.

If a run fails after the upload succeeded it prints the upload id, and
`-ResumeUploadId` retries the publish without sending the file again.

Two things the API cannot do, so they stay manual: creating a mod page, and editing
the mod description.

## The API key

`-SaveApiKey` prompts for the key and writes it to
`%LOCALAPPDATA%\HorseCollisionMod\nexus.cred`, encrypted with DPAPI under your Windows
account. That file is unreadable to other users on the machine and useless if copied to
another one, which covers how a key realistically leaks: a synced folder, a backup, a
shared machine, a stray `git add`. It lives outside the repository so it cannot be
committed at all.

What DPAPI does not defend against is code already running as you, which decrypts it
exactly as the script does. That is a reasonable trade for a mod upload key, but it is
a trade rather than the key being safe from everything.

`-ForgetApiKey` deletes it. Key resolution is `-ApiKey`, then `$env:NEXUS_API_KEY`, then
the stored file, so a single session can override without touching what is saved. Prefer
the stored key to `setx`, which puts it in the registry as plaintext, and to passing
`-ApiKey`, which puts it in shell history.

## Why this is not a GitHub Action

Nexus Mods publish an upload action and a sample workflow that checks out a repository,
zips its source, and uploads the result. That shape does not fit this mod.

`build.ps1` reads the game's own `Animations-part1.pak` to generate `mod_assets/`, which
is gitignored. A hosted runner has no game install, and shipping Warhorse's paks to CI
is both a licensing problem and a gigabyte-scale one. Building locally and feeding the
artifact to a workflow would still build by hand, and add a round trip through GitHub in
order to run six HTTP calls.

Keeping it manual is also what keeps a personal API key inside their
[acceptable use policy](https://help.nexusmods.com/article/114-api-acceptable-use-policy),
which permits personal keys only when the action is initiated by the user. Every request
identifies itself with `Application-Name` and `Application-Version`, as the policy
requires.

Turning this into a tool other people point at their own mod pages would make it a
public-facing application, which has to be registered with Nexus Mods first.

Worth revisiting only if the additive ADB deployment in `ROADMAP.md` ever lands, since a
repository that commits a small delta instead of regenerating whole databases would be
buildable anywhere.

## API reference

The doc comments in `src/HorseCollisionMod.lua` are standard LDoc, and `config.ld`
configures the project. Regenerate `docs/api/` with:

```
ldoc .
```

LDoc needs a C compiler to install, because it depends on penlight which depends on
luafilesystem. On Windows without one:

```
winget install BrechtSanders.WinLibs.POSIX.UCRT --scope user
luarocks install ldoc
```

The compiler is only needed for that install; `ldoc .` runs on its own afterwards.
