-- LDoc configuration. Run `ldoc .` from the repository root.
--
-- LDoc is the standard documentation generator for Lua, and the doc comments
-- in src/HorseCollisionMod.lua are written for it. It is not needed to build
-- the mod, only to regenerate docs/api/.
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

file = "src/HorseCollisionMod.lua"
dir = "docs/api"

-- The doc comments use Markdown for emphasis, lists and fenced code.
format = "markdown"

-- Declaration order is meaningful here: the module header explains the
-- mechanism before the functions that use it.
sort = false

-- The mod is one module rather than a package, so a module index adds a click
-- without adding information.
one = true

-- Everything in the file is part of the documented surface. Nothing is marked
-- @local, and the internals are worth reading.
all = false
