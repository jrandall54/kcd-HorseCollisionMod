# Engine script binds

Every Lua function the game exposes on the objects this mod touches, extracted from the engine's own script-bind registration.

This is a catalog of what exists, not of what works. A name here has not been called unless it is marked, and several documented binds accept a call and then do nothing: `human:PlayAnim` is the standing example, and the whole `Can`/`Request` family answers `Undefined` under conditions that are not yet identified. Signatures come from the registration, so an argument count can differ from what the engine accepts in practice; `actor:Fall` is registered with one argument and takes two.

Entries this mod calls are marked with a dagger. See `docs/kcd_api.lua` for annotated definitions of those, and `docs/TESTING_DIARY.md` for what was learned about the ones that misbehave.

## Actor

Reached through `npc.actor`. Body, health, animation state and the full-body actions. The surface this mod depends on most.

113 functions.

| Function | Arguments |
| --- | --- |
| `AcceptStealthActionByVictim` | none |
| `AddBlood` | string, number |
| `AddDirt` | number |
| `AddFrost` | number |
| `AttachTo` | Actor |
| `AttachVulnerabilityEffect` | number, number, vector, number, string, string |
| `CameraShake` | number, number, number, vector |
| `CanDoMercyKill` | id |
| `CanGrabCorpse` | id |
| `CanHorsePullDown` &dagger; | id |
| `CanHuntAttack` &dagger; | id |
| `CanInteractWith` | id |
| `CanKnockOut` | id |
| `CanLoot` | id |
| `CanPutCorpse` | none |
| `CanStealthKill` &dagger; | id |
| `CanStealthKnockout` &dagger; | id |
| `CanTalk` | none |
| `ChangeAnimGraph` | string, number |
| `CheckInventoryRestrictions` | string |
| `CheckVirtualInventoryRestrictions` | table, string |
| `CleanDirt` | number |
| `ClearForcedLookDir` | none |
| `ClearForcedLookObjectId` | none |
| `CreateCodeEvent` | table |
| `CreateIKLimb` | number, string, string, string, string, number |
| `DumpActorInfo` | none |
| `EnableAspect` | string, boolean |
| `EquipClothingPreset` | string |
| `EquipInventoryItem` | id |
| `EquipWeaponPreset` | string |
| `Fall` &dagger; | vector |
| `GetActor` | none |
| `GetActorId` | none |
| `GetAngles` | none |
| `GetArmor` | none |
| `GetChannel` | none |
| `GetCloseColliderParts` | number, vector, number |
| `GetClosestAttachment` | number, vector, number, string |
| `GetCurrentAnimationState` | none |
| `GetExtensionParams` | string, table |
| `GetFrozenAmount` | none |
| `GetHeadDir` | none |
| `GetHeadPos` | none |
| `GetHealth` | none |
| `GetInitialClothingPreset` | none |
| `GetInitialWeaponPreset` | none |
| `GetLinkedEntity` | none |
| `GetMaxArmor` | none |
| `GetMaxHealth` | none |
| `GetPhysicalizationProfile` | none |
| `GetSpectatorMode` | none |
| `GoLimp` | none |
| `IsCarryingCorpse` | none |
| `IsFlying` | none |
| `IsGhostPit` | none |
| `IsLocalClient` | none |
| `IsMoreDirty` | number |
| `IsPlayer` | none |
| `IsUnconscious` | none |
| `LinkToEntity` | none |
| `MakeLookAsActor` | id, boolean |
| `MakeLookAsSoul` | string |
| `OpenInventory` | id, number, framework__T_WUIDScriptType, string |
| `PlayerSetViewAngles` | angles |
| `PostPhysicalize` | none |
| `QueueAnimationState` | string |
| `RagDollize` | none |
| `RenderScore` | id, number, number, number |
| `RequestDialog` | none |
| `RequestGrabCorpse` | id |
| `RequestHorsePullDown` | id |
| `RequestHuntAttack` | id |
| `RequestItemExchange` | none |
| `RequestKnockOut` | id |
| `RequestMercyKill` | id |
| `RequestPutCorpse` | none |
| `RequestStealthKill` | id |
| `ResetScores` | none |
| `ResetVulnerabilityEffects` | number |
| `Revive` | boolean |
| `ReviveToDefaults` | none |
| `SetAngles` | angles |
| `SetAnimationInput` | string, string |
| `SetClothingDirtLevel` | number |
| `SetDialogAnimationState` | boolean |
| `SetExtensionActivation` | string, boolean |
| `SetExtensionParams` | string, table |
| `SetForcedLookDir` | vector |
| `SetForcedLookObjectId` | id |
| `SetHealth` | number |
| `SetLookIK` | boolean |
| `SetMaxHealth` | number |
| `SetMovementControlledByAnimation` &dagger; | boolean |
| `SetMovementRestriction` | boolean, boolean |
| `SetPhysicalizationProfile` | string |
| `SetSearchBeam` | vector |
| `SetSpectatorMode` | number, id |
| `SetSpeedMultiplier` | number |
| `SetStats` | none |
| `SetVariationInput` | string, string |
| `SetViewLimits` | vector, number, number |
| `SetViewShake` | angles, vector, number, number, number |
| `SimulateOnAction` | string, number, number |
| `StandUp` | none |
| `StartInteractiveActionByName` &dagger; | string, id, boolean, number |
| `StopTimeWarp` | none |
| `TrackViewControlled` | number |
| `UnequipInventoryItem` | id |
| `VectorToLocal` | none |
| `WarpTime` | number, number |
| `WashDirtAndBlood` | number |
| `WashItems` | number |

## Human

Reached through `npc.human`. Everything specific to a person rather than to an actor: hands, weapons, mounts and perception.

62 functions.

| Function | Arguments |
| --- | --- |
| `AttachEntityToHand` | id, number |
| `AttachTo` | Human |
| `AverageActorSuperFraction` | none |
| `CanBeRobbed` | none |
| `CanInteractWith` | id |
| `CanTalk` | none |
| `CanUseLadder` | id, number, boolean |
| `CookFood` | framework__T_WUIDScriptType |
| `CycleWeapon` | none |
| `DetachFromHand` | number |
| `Dismount` | none |
| `DoStepOnGrindstone` | none |
| `DrawFromInventory` | id, number, boolean |
| `DrawWeapon` | none |
| `ForceDismount` | none |
| `ForceMount` | id |
| `GetDialogRequestSourceName` | none |
| `GetHorse` | none |
| `GetHorseMountPoint` | id |
| `GetHuman` | none |
| `GetItemInHand` | number |
| `GetTotalQuality` | none |
| `GetWheelSpeed` | none |
| `GrabOnLadder` | id |
| `HolsterToInventory` | number, boolean |
| `HolsterWeapon` | none |
| `InterruptDialog` | none |
| `IsInDialog` | none |
| `IsMounted` &dagger; | none |
| `IsOnLadder` | none |
| `IsPickpocketing` | none |
| `IsSharpeningActive` | none |
| `IsWeaponDrawn` | none |
| `Mount` | id |
| `MoveToWorstZone` | none |
| `PickUpItem` | id, boolean |
| `PlaceItem` | id, id, boolean |
| `PlayAnim` | string, string |
| `PrepareFood` | framework__T_WUIDScriptType, number |
| `PrepareForDialog` | none |
| `ReadyForDialog` | boolean |
| `ReadyForDialogWithRoles` | boolean, string |
| `ReadyForDialogWithTwins` | boolean |
| `RequestDialog` | none |
| `RequestItemExchange` | none |
| `RequestPickpocketing` | id, number |
| `SetAnimMotionParam` | number, number |
| `SetGrindstone` | id |
| `SetOptimalRotation` | none |
| `SetSharpeningPosition` | number |
| `SetSharpeningPressure` | number |
| `SetSharpeningRotation` | number |
| `SetWheelSpeed` | number |
| `StartBookTranscription` | id |
| `StartBuilding` | id |
| `StartReading` | id |
| `StartSharpening` | id |
| `StartSharpeningWeapon` | id, number |
| `StopAnim` | none |
| `StopSharpening` | none |
| `ToggleWeapon` | none |
| `ToggleWeaponSet` | number |

## Soul

Reached through `npc.soul`. Stats, skills, buffs and identity.

70 functions.

| Function | Arguments |
| --- | --- |
| `AddBuff` | string |
| `AddInjury` | number, string |
| `AddMetaRole` | MetaRoleId |
| `AddMetaRoleByName` | string |
| `AddPerk` | string |
| `AddSkillXP` | string, unsigned |
| `AddStatXP` | string, unsigned |
| `AddXP` | string, XP_T, boolean |
| `AdvanceToSkillLevel` | string, SoulLvlValue |
| `AdvanceToStatLevel` | string, SoulLvlValue |
| `AttachTo` | IEntity, Soul |
| `CalculateBarterDominance` | framework__T_WUIDScriptType |
| `DealDamage` | number, number |
| `DetachFrom` | IEntity |
| `GenerateCompanionEventDebug` | none |
| `GetArchetype` | none |
| `GetAverageSuperFaction` | none |
| `GetDerivedStat` | string |
| `GetFactionID` | none |
| `GetGatherMult` | none |
| `GetGender` &dagger; | none |
| `GetHobbies` | none |
| `GetId` | none |
| `GetMemoryUsage` | ICrySizer |
| `GetMetaRoles` | none |
| `GetNameStringId` | none |
| `GetNextLevelSkillXP` | string, unsigned |
| `GetNextLevelStatXP` | string, unsigned |
| `GetPerceivedSuperfaction` | none |
| `GetReadCaptionObjectText` | none |
| `GetRelationship` | framework__T_WUIDScriptType |
| `GetRoles` | none |
| `GetSchedule` | none |
| `GetSkillLevel` | string |
| `GetSkillProgress` | string |
| `GetSocialClass` | none |
| `GetSoul` | table |
| `GetSoulValue` | string |
| `GetStatLevel` | string |
| `GetStatProgress` | string |
| `GetState` &dagger; | string |
| `GetSuperfaction` | none |
| `HasAbility` | string |
| `HasBuffDebug` | string |
| `HasMetaRoleByName` | string |
| `HasRoleByName` | string |
| `HaveSkill` | string |
| `HealBleeding` | number, number |
| `IsDialogRestricted` | none |
| `IsInCombatDanger` &dagger; | none |
| `IsPublicEnemy` | none |
| `ModifyMoraleDebug` | number |
| `ModifyPlayerReputation` | string, boolean |
| `OnCompanionEvent` | framework__T_WUIDScriptType, string |
| `OnPerkUsed` | string |
| `OverrideCharacterElement` | string, entitymodule__T_CharacterElementId_S_CharacterBodyDescription |
| `OverrideHair` | string |
| `OverrideHead` | string |
| `RemoveAllBuffsByGuid` | string |
| `RemoveBuff` | framework__T_WUIDScriptType |
| `RemoveMetaRole` | MetaRoleId |
| `RemoveMetaRoleByName` | string |
| `RemovePerk` | string |
| `RestrictDialog` | boolean |
| `SetPlayerReputationDebug` | number, number, boolean |
| `SetSkillLevel` | string, SoulLvlValue |
| `SetSkillLevelDebug` | string, SoulLvlValue |
| `SetStatLevel` | string, SoulLvlValue |
| `SetStatLevelDebug` | string, SoulLvlValue |
| `SetState` &dagger; | string, number |

## Inventory

Reached through `npc.inventory`. Carried items, as WUIDs.

21 functions.

| Function | Arguments |
| --- | --- |
| `AddItem` | id |
| `AttachTo` | IEntity, Inventory |
| `CreateItem` | string, number, number |
| `DeleteItem` | framework__T_WUIDScriptType, number |
| `DeleteItemOfClass` | string, number |
| `DetachFrom` | IEntity |
| `Dump` | none |
| `FindItem` | string |
| `GetCount` | none |
| `GetCountOfCategory` | string |
| `GetCountOfClass` | string |
| `GetId` | none |
| `GetInventoryTable` &dagger; | none |
| `GetMemoryUsage` | ICrySizer |
| `GetMoney` | none |
| `HasItem` | id |
| `MoveItemOfClass` | framework__T_WUIDScriptType, string, number, boolean |
| `RemoveAllItems` | none |
| `RemoveItem` | id, number |
| `RemoveMoney` | number |
| `Validate` | none |

## ItemManager

Reached through `ItemManager`. Global. Resolves an item WUID to its class. Carries no weight or name-to-weight lookup, so any weight has to come from the game's own item tables.

11 functions.

| Function | Arguments |
| --- | --- |
| `AddOnEquipBuff` | framework__T_WUIDScriptType, string, boolean |
| `CombineItems` | framework__T_WUIDScriptType, framework__T_WUIDScriptType |
| `CreateItem` | string, number, number |
| `GetItem` &dagger; | id |
| `GetItemName` | string |
| `GetItemOwner` | framework__T_WUIDScriptType |
| `GetItemUIName` | string |
| `IsItemOversized` | framework__T_WUIDScriptType |
| `RemoveItem` | id |
| `SetItemOwner` | framework__T_WUIDScriptType, framework__T_WUIDScriptType, boolean |
| `ValidateId` | id |

## RPGModule

Reached through `RPGModule`. Global. RPG parameters and derived values.

17 functions.

| Function | Arguments |
| --- | --- |
| `AddStatXP` | id, framework__T_WUIDScriptType, string, number, number, number |
| `CaptionObjectUsed` | id, boolean |
| `GetFactionById` | number |
| `GetFactions` | none |
| `GetHerbCollectingEfficiency` | id |
| `GetHobbies` | none |
| `GetLocationById` | string |
| `GetLocationByName` | string |
| `GetLocations` | none |
| `GetMemoryUsage` | ICrySizer |
| `Help` | none |
| `IsPublicEnemy` | framework__T_WUIDScriptType |
| `NotifyLevelXpGain` | string |
| `UnlockAllRecipes` | id, boolean |
| `UnlockRecipe` | id, number, number |
| `_GetConstant` | table, string |
| `_SetConstant` | table, string, number |

## XGenAIModule

Reached through `XGenAIModule`. Global. WUIDs, brain variables, daycycle patches and messages to an NPC's behavior tree.

34 functions.

| Function | Arguments |
| --- | --- |
| `AddRecordedIntellectForFaderProfiling` | framework__T_WUIDScriptType |
| `BindToModule` | XGenAIModule |
| `DespawnPerceptibleVolume` | framework__T_WUIDScriptType |
| `ForceSyncFromLua` | framework__T_WUIDScriptType |
| `GetBrainVariable` | framework__T_WUIDScriptType, string |
| `GetCombatSimulatorHumanExperimentParams` | none |
| `GetEntityByWUID` &dagger; | framework__T_WUIDScriptType |
| `GetEntityIdByWUID` | framework__T_WUIDScriptType |
| `GetMyWUID` &dagger; | table |
| `GetWuidDebugString` | framework__T_WUIDScriptType |
| `IsPointInAreaWithLabel` | vector, string |
| `IsPointInAreaWithLabelWUID` | framework__T_WUIDScriptType, string |
| `LootBegin` | framework__T_WUIDScriptType |
| `LootEnd` | framework__T_WUIDScriptType |
| `LootInventoryBegin` | framework__T_WUIDScriptType |
| `OnDestroy` | number |
| `OnPropertyChange` | id |
| `OnSpawn` | id, string |
| `OnStart` | boolean |
| `PlaceToSlotFromInventory` | framework__T_WUIDScriptType, id |
| `ProduceSound` | number, vector, number |
| `ProduceSoundWUID` | number, framework__T_WUIDScriptType, number |
| `RemoveDaycyclePatch` &dagger; | framework__T_WUIDScriptType, string |
| `SaveCombatSimulatorHumanExperimentResult` | number, number |
| `SendMessageToEntity` &dagger; | table, string, string |
| `SendMessageToEntityData` | table, string, table |
| `SetBrainVariable` | framework__T_WUIDScriptType, string, table |
| `SetModuleLink` | XGenAIModule |
| `SetPlayerDogMode` | string |
| `SpawnPerceptibleVolume` | vector, number, number, number, number, string, string, boolean, boolean |
| `SpawnPerceptibleVolumeOnWUID` | framework__T_WUIDScriptType, number, number, number, number, string, string, boolean, boolean |
| `TryEndCombat` | framework__T_WUIDScriptType |
| `_GetDataVariable` | string |
| `_SetDataVariable` | string |

## Player

Reached through `player.player`. The player extension.

45 functions.

| Function | Arguments |
| --- | --- |
| `AddActions` | none |
| `AddLuaActions` | none |
| `AddSoAction` | framework__T_WUIDScriptType, string, string, number |
| `AttachTo` | Player |
| `CanMountHorse` | id |
| `CanSleepAndReportProblem` | none |
| `CancelDogObjective` | none |
| `ChangePlayerHeadLight` | string |
| `ClearPlayerHorse` | none |
| `DebugDisableInteractionFilter` | string |
| `DebugEnableInteractionFilter` | string |
| `DebugStopMinigame` | none |
| `EnableFastTravel` | boolean |
| `EnablePlayerHorseInventory` | boolean |
| `FeedDog` | none |
| `GetHorseId` | none |
| `GetPlayer` | none |
| `GetPlayerHorse` &dagger; | none |
| `HasRunningDogObjective` | none |
| `HorseInspect` | id |
| `InterruptSitting` | none |
| `IsLaying` | none |
| `IsSitting` | none |
| `OnBedInterrupt` | none |
| `OnBedPrepareForDialog` | none |
| `OnBedStop` | none |
| `OnEndInteractive` | none |
| `OnEndItemInteraction` | none |
| `OnEndSleepState` | none |
| `OnEnterInteractive` | none |
| `OnHold` | boolean |
| `OnSleepFadeIn` | none |
| `OnSleepFadeOut` | none |
| `OnSleeping` | number, framework__T_WUIDScriptType |
| `OnUsableMessage` | framework__T_WUIDScriptType, string, string |
| `OpenInventory` | number, framework__T_WUIDScriptType |
| `PlayerForceSit` | none |
| `PushBack` | number |
| `RequestDogObjective` | id |
| `SetPlayerDog` | id |
| `SetPlayerHorse` | id |
| `SetWhistling` | boolean |
| `Sleep` | id |
| `ToggleWeaponSet` | number |
| `TryDrawTorch` | none |

## SmartObject

Reached through `SmartObject`. Global. Smart object slots and interactions.

7 functions.

| Function | Arguments |
| --- | --- |
| `AttachTo` | SmartObject |
| `BindToModule` | XGenAIModule |
| `GetHelperLinkTarget` | string, string |
| `GetHelperLinks` | string |
| `GetHelperUserData` | string, string |
| `GetHelpers` | none |
| `GetHelpersCategory` | string |

## PickableItem

Reached through item entity. An item lying in the world.

39 functions.

| Function | Arguments |
| --- | --- |
| `AttachTo` | PickableItem |
| `BelongsToDeadBody` | none |
| `CanPickUp` | id |
| `CanSteal` | id |
| `CanUse` | id |
| `GetExtensionParams` | string, table |
| `GetHealth` | none |
| `GetId` | none |
| `GetLinkedOwner` | none |
| `GetMaxHealth` | none |
| `GetMountedAngleLimits` | none |
| `GetMountedDir` | none |
| `GetOwnerId` | none |
| `GetParams` | none |
| `GetPhase` | none |
| `GetPhaseById` | none |
| `GetStats` | none |
| `GetUIName` | none |
| `IsDestroyed` | none |
| `IsFromShop` | none |
| `IsMounted` &dagger; | none |
| `IsOversized` | none |
| `IsUsed` | none |
| `OnHit` | table |
| `OnSteal` | id |
| `OnUsed` | id |
| `PlayAnimation` | string |
| `Quiet` | none |
| `Reset` | none |
| `Select` | boolean |
| `SetExtensionActivation` | string, boolean |
| `SetExtensionParams` | string, table |
| `SetIgnoreSaveFlag` | boolean |
| `SetMountedAngleLimits` | number, number, number |
| `SetPhase` | number |
| `SetPhaseById` | number |
| `StartUse` | id |
| `StopUse` | id |
| `Use` | id |

## Contexts

Reached through `Contexts`. Global, from `Scripts/Script/Context.lua`. Per-NPC
behavior switches, and the API vanilla quests use to change how an NPC
behaves.

    Contexts.SetPersistentOption(entity, option, handle, params)
    Contexts.SetNonpersistentOption(entity, option, handle, params)
    Contexts.ClearOption(entity, option, handle, params)
    Contexts.CheckOption(entity, option)
    Contexts.SetNonpersistentPreset(entity, preset, handle, params)
    Contexts.SetPersistentPreset(entity, preset, handle, params)
    Contexts.ClearPreset(entity, preset, handle, params)

Every option is carried on a named **handle**, so several systems can request
the same option and clearing one does not disturb another. `ClearOption`
throws when the handle was never set, which is a useful way to tell "cleared"
from "was never held". `Contexts.RestoreEntity`, `ResetEntity` and
`EnsureEntityIsRestored` concern restoring context data after a load, not
relocating an NPC.

`Scripts/Script/ContextData.lua` catalogs **89 options and 14 presets**.
Vanilla drives NPC behavior with them directly: `q_ledecko` sets
`fightAllHostilePerceptibles` on four bandits, `q_huntPtacek` on two Cumans,
`q_hareHunt` applies the `berserk` preset.

The ones that bear on collisions and fights:

| Option | Effect |
| --- | --- |
| `alwaysFightWhenHit` | answers a hit with a fight rather than the usual response |
| `fightAllHostilePerceptibles` | fights anything perceived hostile |
| `suppressFightMoraleChecks` | removes the morale gate that makes civilians flee |
| `disableChangeHostilityOnHit` | a hit does not change hostility |
| `neverAcceptSurrender` | refuses a yield |
| `suppressDudeHostilePerceptionStimuli` | ignores the player being perceived as hostile |
| `suppressReputationHitOnDudeHit` | being hit by the player costs no reputation |
| `suppressCollisionsBark` | silences the collision bark |
| `suppressHitReactions` | no hit reaction at all |
| `suppressAutoCure` | exempt from the auto-cure daycycle |

Presets compose them. `berserk` is `fightAllHostilePerceptibles` plus
`suppressFightMoraleChecks`. `eventEnemyWithFriendlySuperfaction`, an enemy
who fights the player without the world turning on them, is
`suppressDudeProxBark`, `suppressPickNoticedItems` and
`suppressReputationPreventForDudeHits`.

## Combat subbrain messages

Sent with `XGenAIModule.SendMessageToEntityData(wuid, type, table)`, where the
table is built by `Utils.makeTable(type, {...})` and validated against
`Libs/AI/TypeDefinitions.xml`. **The target is `npc.this.id`, the WUID, not
`npc.id`**: sent to the entity id a message is accepted and discarded in
silence.

Thirty-seven `combat:` types appear across the vanilla behavior XML.
`MessageTypes.xml` registers which are addressable. The ones used or
evaluated here:

| Message | Payload | Effect |
| --- | --- | --- |
| `combat:hit` | attacker, strength, hitType, real | a hit through `sb_switch_hitreactions.xml`, which both scores reputation and broadcasts an assault volume |
| `combat:stimulus:hit` | attacker, kind, real | the same decision without the broadcast, straight to the combat subbrain |
| `combat:stimulus:hostilePerception` | perceptible | fight, flee or report, chosen by `crimeSystemRole` and morale |
| `combat:stimulus:standDownRequest` | *empty* | ends the combat state. The declared member `_` is a placeholder and passing it is rejected |
| `combat:stimulus:customBehaviorRequest` | behaviorName or includeXml/includeTree, suppressStimuli, entity | runs a behavior with other stimuli suppressed |
| `daycycle:restartRequest` | reason, speed | sends an NPC back to their activity |

`sb_combat.xml` rejects any stimulus arriving while the receiver is already in
`fight` or `flee`, **except** `standDownRequest` and `customBehaviorRequest`,
which are named exemptions. That is the only way to reach someone mid-flight.

## Faction

Returned by `RPG.GetFactionById(id)` and `RPG.GetFactions()`, which answers 98.
The methods are reached through a metatable rather than listed by `pairs`,
which shows only `__FactionId`.

| Method | Notes |
| --- | --- |
| `GetId` | |
| `GetName` | e.g. `ui_fac_rataje_out_villagers` |
| `GetLocationId` | |
| `GetReputation`, `GetBaseReputation` | 0 to 1, 0.5 typical |
| `AddReputation(sEnumName)` | takes an enum name, not a number |
| `GetAngriness`, `SetAngriness(float)`, `AddAngriness(float)` | clamped to 1.0 |

**Angriness is not a hostility switch.** Every faction in the game set to
maximum produced no hostility whatsoever. `wh_rpg_angriness [-f ID [-a N]] [-p]`
dumps the same data from the console.

`soul:GetRelationship(playerWuid)` is the individual counterpart, and is what
a beating lowers. It moves globally for everyone as town standing changes, so
compare a victim against an untouched neighbor rather than against an
absolute.

## Globals that are not script binds

The sections above are `C_ScriptBind*` classes. Several of the most useful Lua
globals are not among them, which is why a survey of those headers cannot
answer "what can Lua call". Everything below was verified present in this
build by probing the running game, 43 entry points out of 43 tried.

The source is spraguep's Cheat mod, `references/kcd1tools/cheat-106-*.zip`,
which is pure Lua in a pak and therefore demonstrates working calls rather
than declarations.

### Calendar

World time, readable and settable, without the in-game wait dialog.

| Function | Notes |
| --- | --- |
| `Calendar.GetWorldTime()` | seconds; 3,319,760 read at day 38 |
| `Calendar.SetWorldTime(seconds)` | absolute; add `hours * 3600` to skip |
| `Calendar.GetWorldTimeRatio()` | **15** by default |
| `Calendar.SetWorldTimeRatio(n)` | higher is faster, 0 pauses |
| `Calendar.IsWorldTimePaused()`, `SetWorldTimePaused(bool)` | |
| `Calendar.GetWorldHourOfDay()` | |
| `Calendar.SetFakeTimeOfDay(h)`, `UnfakeTimeOfDay()`, `IsFakedTimeOfDay()` | |

Vanilla follows a time jump with
`XGenAIModule.SendMessageToEntity(player.this.id, "timekeeper:recalculate", "")`
so the world catches up.

`GetWorldTimeRatio` at 15 is the ordinary ratio and is a different quantity
from the CVar `wh_pl_SkipTimeMaxWorldTimeRatio` at 360, which governs the skip
dialog only.

### Database

| Function | Notes |
| --- | --- |
| `Database.LoadTable(name)` | **required first**, or the table reads as empty |
| `Database.GetTableInfo(name)` | `.LineCount` is the row count, **not** `.RowCount` |
| `Database.GetColumnInfo(name, i)` | `.Name` |
| `Database.GetTableLine(name, row)` | a row keyed by column name |
| `Database.GetTableColumnData(name, col)` | returns nothing for some tables |

`GetTableColumnData` returning nothing does not mean a table is empty.
`reputation_change` and `angriness_enum` both read as empty through it and
both read correctly through `LoadTable` plus `GetTableLine`.

### Game

| Function | Notes |
| --- | --- |
| `Game.SetWantedLevel(0..3)` | the player's wanted level, settable |
| `Game.SaveGameViaResting()` | |
| `Game.RemoveSaveLock()` | |
| `Game.IsLoadingEngineSaveGame()` | |
| `Game.ShowItemsTransfer()` | |

### Entity

Methods on the entity class table, so any entity carries them.

| Function | Notes |
| --- | --- |
| `CreateLink(name, targetId)` | targetId optional |
| `GetLink`, `RemoveLink`, `CountLinks` | |
| `AddImpulse(-1, pos, dir, force)` | vanilla scales force by the target's mass |
| `GetPhysicalStats()` | `.mass`, `.gravity`, `.flags`; the player is mass 80 |
| `SetPhysicParams(group, table)` | `PHYSICPARAM_PLAYERDYN` carries gravity, zeroG, air_control |
| `AwakePhysics(1)` | |

Whether `CreateLink` reaches the behavior tree's **tagged** links, which
`checkAssaultSuppression` walks looking for a `suppressAssaultReactions` tag
between two entities, is unestablished. The entity link API takes a name and
a target; the behavior tree's takes From, To, Tag and Data.

### System, beyond the familiar

| Function | Notes |
| --- | --- |
| `System.AddCCommand(name, "tbl:method(%line)", help)` | registers a console command backed by Lua |
| `System.ExecuteCommand("...")` | runs a console command from Lua |
| `System.SetCVar(name, value)`, `System.GetCVar(name)` | observed setting a `VF_CHEAT` variable, though under `-devmode` |
| `System.SpawnEntity(table)` | |
| `System.GetEntitiesByClass(class)` | |

### Others confirmed present

`Physics.RayWorldIntersection`, `Framework.IsValidWUID`,
`EnvironmentModule.BlendTimeOfDay`, `EnvironmentModule.ForceImmediateWeatherUpdate`,
`EntityModule.GetInventoryOwner`, `Shops.IsLinkedWithShop`,
`CryAction.LoadXML`, `Minigame.StartLockPicking`, `QuestSystem.*`,
`ItemManager.*`, and `actor:ReviveToDefaults()`.

## The reputation change table

`reputation_change` has 71 lines. `soul:ModifyPlayerReputation(name, propagate)`
and `faction:AddReputation(...)` select from it by name. Each row carries a
`change` and a **`can_change_hostility`** flag, and the flag is what decides
whether an NPC stops treating the player as hostile.

| name | change | can_change_hostility |
| --- | --- | --- |
| `hit_melee_weak` | -0.2 | **true** |
| `hit_melee_medium` | -0.4 | true |
| `hit_melee_strong` | -0.7 | true |
| `hit_melee_brutal` | -1.25 | true |
| `hit_melee_*_noChangeHostility` | the same numbers | false |
| `surrender_step` | **+0.25** | **true** |
| `payToTalk` | +0.25 | **false** |
| `best_friend` | +2 | true |
| `sworn_enemy` | -2 | true |
| `death` | -0.6 | true |
| `crime_assault_individual`, `_reported` | -0.3 each | false |
| `crime_murder_individual` | -0.6 | false |
| `crime_murder_reported` | -1.5 | false |
| `crime_theft_individual` | -0.25 | false |
| `haggle_tip` | +0.1 | false |
| `shop_transaction` | +0.02 | false |
| `impress_success` | +0.05 | false |
| `quest_reward_1_micro` .. `_7_max` | +0.05 to +1.5 | true at 6 and 7 |

The practical consequence: **punching someone sets a hostility flag, and only
a change with `can_change_hostility` can clear it.** `payToTalk` raises the
number and cannot clear the flag, which is why paying a fine never repairs a
victim while surrendering to him does.

`angriness_enum` has nine lines: `min_angriness` 0, `max_angriness` 1, `death`
0.55, `event_roadsideCorpse_unsolvedMurder` 0.2, `unatributedStealthKill` 0.15,
`theft_large` 0.125, `theft_medium` 0.025, `theft_small` 0.01.

## Actor and human methods vanilla uses

Gathered from `vanilla_scripts/`, and listed because several bear directly on
this mod and were not known to it. Presence in vanilla means the method exists;
none of the ones marked untried has been called here.

### Actor, reached as `ent.actor`

Already used by this mod: `Fall`, `GetCurrentAnimationState`,
`GetPhysicalizationProfile`, `SetPhysicalizationProfile`,
`StartInteractiveActionByName`, `SetMovementRestriction`, `SetHealth`.

Untried and relevant:

| Method | Why it matters here |
| --- | --- |
| `StandUp()` | stands an actor up, which is what several improvised repairs were reaching for |
| `IsUnconscious()` | the state read that `IsDead` failed to provide |
| `RequestKnockOut()` | a knockout, which is how a brawl can end without a death |
| `SetMovementTarget(...)` | send an actor somewhere, rather than asking the daycycle to replan |
| `HolsterItem(...)` | put a weapon away |
| `UnequipInventoryItem(item)` | vanilla's `Crime.lua` holsters the **player's** weapon with this during a confrontation |
| `EquipWeaponPreset`, `EquipClothingPreset` | wholesale loadout changes |
| `AddBlood(str, n)`, `AddDirt(n)`, `AddFrost`, `CleanDirt`, `WashDirtAndBlood` | the cosmetic roadmap item |
| `CameraShake(...)`, `SetViewShake(...)` | impact feedback for the rider, never considered |
| `SetForcedLookDir`, `SetForcedLookObjectId` | make a victim look at the rider |
| `Revive()`, `ReviveToDefaults()` | reset an actor |
| `GetArmor()` | armor, read directly rather than summed from the item tables |
| `CanHorsePullDown(id)`, `RequestHorsePullDown(id)` | see below |
| `CanStealthKnockout`, `RequestStealthKill`, `RequestMercyKill` | |
| `CanHuntAttack`, `RequestHuntAttack` | |

### Human, reached as `ent.human`

Already used: `IsMounted`, `GetItemInHand`, `ForceDismount`.

Untried: `DrawWeapon`, `DrawPrimaryWeapon`, `IsWeaponDrawn`, `CycleWeapon`,
`EquipItemInSlot`, `CanBeRobbed`, `RequestDialog`, `RequestPickpocketing`,
`Mount`, `GrabOnLadder`, `StartBuilding`, `StartBookTranscription`.

`IsWeaponDrawn` is the read that the polearm get-up investigation inferred
from item names.

## Horse pull-down is a vanilla interaction

`BasicAIActions.lua` offers it as an interactor action beside knockout and
hunt attack:

    local canPullDown = user.actor:CanHorsePullDown(self.id)
    ...
    user.actor:RequestHorsePullDown(self.id)

with the hint `@ui_hud_horse_pulldown` and the interaction `inr_pullDown`. The
binary carries `wh_cs_HorsePullDownAngle`, `wh_cs_HorsePullDownZAngle` and
`wh_cs_HorsePullDownZeroAngle`, so the geometry that permits it is tunable.

In vanilla the `user` is the player and the target is a mounted NPC. **Whether
an NPC can be the `user` and the player the target is untested**, and if it
can, an NPC pulling the rider off the horse is a native mechanic rather than
something this mod would have to build. That is the roadmap's braced-polearm
dismount and a large part of what victims fighting back should look like.

## The engine names rider-specific combat behaviours

A combat action type group in the binary carries, among forty-six entries:

`freeRiderAttack`, `freeRiderAttackStatic`, `groupRiderAttack`,
`groupRiderMovement`, `riderGuardIdle`, `riderGuardIdle2Move`,
`riderGuardMove2Idle`, `riderGuardMovement`, `riderGuardFastStop`,
`riderGuardJump`, `riderGuardJumpStart`, `riderGuardJumpEnd`,
**`riderGuardRear`**, `horsePullDownAttackSuccess`, `horsePullDownHitSuccess`.

These are behaviour and animation identifiers rather than Lua entry points, so
they are not callable as they stand. What they establish is that the AI has
combat behaviour written specifically for fighting a mounted target and for
mounted guards, including a rear. The roadmap item about striking a heavy
target rearing the horse has a named behaviour behind it.
