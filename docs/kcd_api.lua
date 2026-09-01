--- Type definitions for the Kingdom Come: Deliverance Lua API.
--
-- This file is never loaded by the game and is never packed into the mod. It
-- exists so a language server can offer autocomplete, catch typos, and flag
-- wrong argument counts while editing.
--
-- Everything below was verified against this project: either observed working
-- in game, read out of the decompiled binary's script-bind registration, or
-- taken from vanilla scripts unpacked from Scripts.pak. Where a signature is
-- known to be misleading, the annotation says so - those notes are the whole
-- reason this file is worth keeping.
--
-- Point a language server at it with the .luarc.json in the project root.
--
-- @module kcd_api

---@meta

--------------------------------------------------------------------------
-- Globals the engine injects
--------------------------------------------------------------------------

--- The player entity. Present only once a save is loaded.
---@class Player : Entity
---@field human Human
---@field player PlayerExtension
---@field actor Actor
---@field soul Soul
player = {}

--------------------------------------------------------------------------
-- System
--------------------------------------------------------------------------

---@class System
System = {}

--- Writes a line to kcd.log. The one logging call proven to reach the file;
--- the behavior-tree LogToConsole node does not.
---@param message string
function System.LogAlways(message) end

--- Seconds since the session started, as a float.
---@return number
function System.GetCurrTime() end

--- Every entity whose origin lies inside the sphere. Returns everything,
--- including items and props, so callers must filter.
---@param position table @{x,y,z}
---@param radius number @meters
---@return table[]
function System.GetEntitiesInSphere(position, radius) end

---@param name string
---@return table|nil
function System.GetEntityByName(name) end

---@param name string
---@param value number|string
function System.SetCVar(name, value) end

--------------------------------------------------------------------------
-- Script
--------------------------------------------------------------------------

---@class Script
Script = {}

--- Runs a function once after a delay. There is no repeating timer, so a
--- loop is built by having the callback reschedule itself.
---@param milliseconds number
---@param callback fun()
function Script.SetTimer(milliseconds, callback) end

--- Executes another Lua file, synchronously, resolving the path through the
--- merged pak filesystem. This is how the base game composes its own scripts:
--- it is the first line of nearly every vanilla entity script and is what
--- `Scripts/common.lua` uses to pull in its utility files. Re-running a file
--- redefines what it declares, which is why a mod can hot-reload with it.
---@param path string forward-slash path inside Data, e.g. "Scripts/x.lua"
function Script.ReloadScript(path) end

--------------------------------------------------------------------------
-- XGenAIModule - Warhorse's AI and entity layer
--------------------------------------------------------------------------

---@class XGenAIModule
XGenAIModule = {}

--- Resolves a WUID to a live entity, or nil if it is not streamed in.
---@param wuid userdata
---@return table|nil
function XGenAIModule.GetEntityByWUID(wuid) end

---@param entity table
---@return userdata
function XGenAIModule.GetMyWUID(entity) end

--- Posts a message to an entity's brain.
---
--- `values` is a flat string of `key(value), key(value)` pairs, not a table.
--- Message type names and their fields are defined in
--- Libs/AI/TypeDefinitions.xml.
---
--- Delivery is NOT guaranteed and there is no return value to check. Handlers
--- declared `Atomic="true"` drop messages while busy; measured delivery was
--- roughly 3 in 19 under load. Never build behavior that depends on one
--- message arriving.
---@param entityId number
---@param messageType string @e.g. "hitReaction", "combat:hit"
---@param values string
function XGenAIModule.SendMessageToEntity(entityId, messageType, values) end

---@param entityId number
---@param messageType string
---@param data table
function XGenAIModule.SendMessageToEntityData(entityId, messageType, data) end

--------------------------------------------------------------------------
-- Framework
--------------------------------------------------------------------------

---@class Framework
Framework = {}

--- Encodes a WUID for use inside a brain message `values` string.
---@param wuid userdata
---@return string
function Framework.WUIDToMsg(wuid) end

--------------------------------------------------------------------------
-- UIAction
--------------------------------------------------------------------------

---@class UIAction
UIAction = {}

--- Subscribes a table to UI events. Empty strings match all elements.
---
--- A Scripts/Startup script has no "game loaded" hook, so the usual entry
--- point is listening for actionName "sys_loadingimagescreen" with eventName
--- "OnEnd".
---@param listener table
---@param elementName string
---@param instanceName string
---@param callbackName string @method name on listener
function UIAction.RegisterActionListener(listener, elementName, instanceName, callbackName) end

--------------------------------------------------------------------------
-- Entity - the base every world object shares
--------------------------------------------------------------------------

---@class Entity
---@field id number
---@field class string @"NPC", "Player", "Horse", ...
---@field Properties table
local Entity = {}

---@return table @{x,y,z}
function Entity:GetPos() end

---@return string
function Entity:GetName() end

---@return table @{x,y,z} meters per second
function Entity:GetVelocity() end

--- Basis vector in world space: 0 is right, 1 is forward, 2 is up.
---@param axis number
---@return table @{x,y,z}
function Entity:GetDirectionVector(axis) end

---@return table @{x,y,z} radians
function Entity:GetAngles() end

--- Applies a physics impulse.
---
--- Ignored on an upright actor: NPCs and horses are animation-driven, not
--- physics-driven. Only works once the target is a ragdoll, and even then the
--- ragdoll needs a tick to physicalise first.
---@param partId number @-1 for the whole entity
---@param position table @{x,y,z} world-space application point
---@param direction table @{x,y,z} unit vector
---@param impulse number @magnitude
---@param scale number
function Entity:AddImpulse(partId, position, direction, impulse, scale) end

---@return boolean
function Entity:IsDead() end

--------------------------------------------------------------------------
-- Actor
--------------------------------------------------------------------------

---@class Actor
local Actor = {}

--- Ragdolls the actor.
---@param position table @{x,y,z}
---@param force boolean
function Actor:Fall(position, force) end

--- Takes over the actor's body and plays a whole animation, then returns
--- control. The only reliable way to animate an NPC from Lua.
---
--- `actionName` is matched against the FragTags of the `AnimationControlled`
--- Mannequin fragment ONLY - not fragment IDs, and not other fragments' tags.
--- Vanilla ships only object interactions there (cabinet_o, alarmBell,
--- door_*), so new names must be added to both the animation database and its
--- subTagDef file. A name that does not resolve is accepted silently and
--- aborts after one frame.
---@param actionName string
---@param objectId number @entity interacted with; the actor itself works when there is none
---@param updateVisibility boolean
---@param animSpeed number
function Actor:StartInteractiveActionByName(actionName, objectId, updateVisibility, animSpeed) end

---@return string
function Actor:GetCurrentAnimationState() end

---@return number
function Actor:GetHealth() end

---@param health number
function Actor:SetHealth(health) end

---@return boolean
function Actor:IsPlayer() end

--------------------------------------------------------------------------
-- Human
--------------------------------------------------------------------------

---@class Human
local Human = {}

---@return boolean
function Human:IsMounted() end

---@return table|nil
function Human:GetHorse() end

---@param horseId number
function Human:Mount(horseId) end

function Human:Dismount() end

function Human:ForceDismount() end

--- Requests a Mannequin fragment.
---
--- Accepted on NPCs and silently inert: the call returns without error and no
--- animation ever renders, under every combination of fragment, Tags and
--- FragTags tried. Use Actor:StartInteractiveActionByName instead.
---@param fragment string
---@param tag string
function Human:PlayAnim(fragment, tag) end

function Human:StopAnim() end

---@return boolean
function Human:IsWeaponDrawn() end

function Human:DrawWeapon() end

--------------------------------------------------------------------------
-- Soul - the RPG layer
--------------------------------------------------------------------------

---@class Soul
local Soul = {}

--- Reads a stat. Known keys: "health", "stamina".
---
--- Values are absolute, not normalized: a horse's stamina pool measured 210.
---@param state string
---@return number|nil
function Soul:GetState(state) end

---@param state string
---@param value number
function Soul:SetState(state, value) end

--- Applies damage.
---
--- **The first argument is stamina and the second is health**, per the
--- registered binding. Vanilla's own debug helper Quick.lua names them
--- health-first, which is wrong and has cost this project real time. Prefer
--- SetState when adjusting a specific stat.
---
--- This is an RPG-layer stat change only. It does NOT generate a combat hit
--- event, so it produces no recoil animation and no hostility.
---@param stamina number
---@param health number
---@param attacker userdata|nil
---@param flag boolean
function Soul:DealDamage(stamina, health, attacker, flag) end

--- 0 undefined, 1 male, 2 female.
---@return number
function Soul:GetGender() end

---@param buffGuid string
function Soul:AddBuff(buffGuid) end

---@param skillName string
---@return number
function Soul:GetSkillLevel(skillName) end

--------------------------------------------------------------------------
-- Horse extension
--
-- Present on horse entities as `entity.horse`, not on the entity itself and
-- not on `actor` or `human`. Found by enumerating a live horse's fields.
--------------------------------------------------------------------------

---@class HorseExtension
local HorseExtension = {}

--- Rears the horse and throws its rider to the ground.
---
--- The natural animation for an unseating. Ragdolling the player instead
--- reads as them collapsing rather than being thrown.
function HorseExtension:RearAndThrowDown() end

---@return boolean
function HorseExtension:HasRider() end

---@return boolean
function HorseExtension:IsMountable() end

--------------------------------------------------------------------------
-- Player extension
--------------------------------------------------------------------------

---@class PlayerExtension
local PlayerExtension = {}

---@return userdata|nil @WUID of the player's horse
function PlayerExtension:GetPlayerHorse() end

--- Pushes the PLAYER back. Registered on the player bind, so it is nil on
--- NPCs; it cannot be used to shove someone else.
---@param distance number
function PlayerExtension:PushBack(distance) end

return nil
