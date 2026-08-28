# Releasing

The steps to publish a version, in order. Every one is run by hand on a version
chosen for release; nothing here is wired to a push or a schedule.

Requires PowerShell and Python 3. LuaJIT is optional and adds a syntax check.

## 1. Bump the version

`src/mod.manifest` and `HorseCollisionMod.Version` in `src/HorseCollisionMod.lua`.
`build.ps1` copies the manifest verbatim, and step 5 refuses a zip whose manifest
disagrees with the version being published.

## 2. Build

```
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version "2.1.0"
```

Animation data is generated from a local game install rather than committed, so a
first build runs `tools/build_adb.py`, which resolves the game folder itself:
`--game-root`, then `KCD_PATH`, then the usual Steam and GOG locations, then every
Steam library in `libraryfolders.vdf`.

Output lands in `releases\`.

## 3. Verify

```
python tools\verify_additive.py
```

Thirty-one checks against the game's own paks and the packaged zip:

- only the two intended declaration files carry vanilla names
- nothing is lost from the fragment the mod takes authority over
- every reference in the chain resolves
- pak entries use forward slashes
- the Lua redirects the classes the engine spawns, read out of `Scripts.pak`
  rather than taken on trust

All must pass.

## 4. Test the packaged build

The dev loop deploys loose files at `sys_PakPriority = 0`, which is not how a
player runs the mod. A pak whose entry names or reference paths are wrong
overrides nothing and logs nothing, and loose files hide that completely.

So before publishing, test the zip the way it will be installed:

- `sys_PakPriority = 2` and `mn_allowEditableDatabasesInPureGame = 0` in
  `system.cfg`, both shipping defaults
- no loose files under `Data\Animations\` or `Data\Scripts\Startup\`
- installed through Vortex, from the zip
- launched without `-devmode`

## 5. Publish

```
.\tools\publish_nexus.ps1 -Version 2.1.0 -DryRun
.\tools\publish_nexus.ps1 -Version 2.1.0 -ChangelogFile releases\notes-2.1.0.md
```

`-DryRun` resolves and validates, then stops before uploading. Without it the
script prints what it is about to publish and asks for the version to be typed
back.

It checks the version string against the API's own pattern, the zip against the
expected release layout, the manifest version against the one being published,
and the mod page for an existing version of that name. `-Force` skips those and
the prompt. If a run fails after the upload succeeded it prints the upload id,
and `-ResumeUploadId` retries without sending the file again.

## 6. Update the mod page

The API has no endpoint for a mod's description, so page copy is edited in the
browser. The local draft is kept outside the repository.

---

## The API key

`.\tools\publish_nexus.ps1 -SaveApiKey` prompts once and writes the key to
`%LOCALAPPDATA%\HorseCollisionMod\nexus.cred`, encrypted with DPAPI under the
current Windows account. The file is unreadable to other users on the machine,
useless if copied to another one, and outside the repository so it cannot be
committed. `-ForgetApiKey` deletes it.

DPAPI does not defend against code already running as that user. It defends
against how a key leaks in practice: a synced folder, a backup, a shared machine,
an accidental commit.

Resolution order is `-ApiKey`, then `$env:NEXUS_API_KEY`, then the stored file.
Prefer the stored key to `setx`, which writes plaintext to the registry, and to
`-ApiKey`, which lands in shell history.

## Why publishing stays manual

Nexus Mods permit a personal API key only when the action is initiated by the
user. Every request identifies itself with `Application-Name` and
`Application-Version`, as their
[acceptable use policy](https://help.nexusmods.com/article/114-api-acceptable-use-policy)
requires. A tool other people pointed at their own mod pages would be a
public-facing application and would have to be registered with Nexus Mods first.

Automation is also impractical: `build.ps1` reads the game's own
`Animations-part1.pak` and `mod_assets/` is not committed, so a hosted runner has
no game install. Shipping Warhorse's paks to CI is both a licensing and a size
problem, and building locally to feed a workflow would still build by hand.
