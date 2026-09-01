-- LDoc configuration. Run `ldoc .` from the repository root.
--
-- LDoc is the standard documentation generator for Lua, and the doc comments
-- in src/ are written for it. It is not needed to build the mod, only to
-- regenerate docs/api/.
--
-- Installing it needs a C compiler, because LDoc depends on penlight which
-- depends on luafilesystem, which is a C module. On Windows without one:
--
--     winget install BrechtSanders.WinLibs.POSIX.UCRT --scope user
--     luarocks install ldoc
--
-- The compiler is only needed for that install. Afterwards `ldoc .` runs on
-- its own.

project = "HorseCollisionMod"
title = "HorseCollisionMod API reference"
description = "Speed-tiered horse collision reactions for Kingdom Come: Deliverance."

-- The entry point first, then the part files it pulls in with
-- Script.ReloadScript. Listed rather than pointed at the directory so the
-- reference reads in the order the mod loads, which `sort = false` preserves.
file = {
	"src/HorseCollisionMod.lua",
	"src/HorseCollisionMod/Enums.lua",
	"src/HorseCollisionMod/Log.lua",
	"src/HorseCollisionMod/Armor.lua",
	"src/HorseCollisionMod/Detection.lua",
	"src/HorseCollisionMod/Health.lua",
	"src/HorseCollisionMod/Reaction.lua",
	"src/HorseCollisionMod/Recovery.lua"
}
dir = "docs/api"

-- The doc comments use Markdown for emphasis, lists and fenced code.
format = "markdown"

-- Declaration order is meaningful here: the module header explains the
-- mechanism before the functions that use it.
sort = false

-- Once there is more than one module a package index carries information: it
-- is the list of the parts the mod is built from.
one = false

-- Everything in the file is part of the documented surface. Nothing is marked
-- @local, and the internals are worth reading.
all = false
