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
