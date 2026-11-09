# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

**Mine ShopGUI** (`mine_shop_gui`) is a Minetest (Luanti) mod that provides a shop GUI. The repo is at an early stage: it currently contains only `LICENSE` and `README.md`. Update this file as the code takes shape.

The repo lives directly in the Minetest user mods folder (`%APPDATA%\Minetest\mods\mine_shop_gui`), so the game can load it as-is.

## Layout (planned, standard Minetest mod structure)

```
mod.conf        # name = mine_shop_gui, description, depends / optional_depends
init.lua        # entry point; loads the other files via dofile(modpath .. "/x.lua")
*.lua           # feature modules (shop registry, formspec building, economy hooks, ...)
settingtypes.txt# optional: user-configurable settings
textures/       # assets, prefixed with the mod name (mine_shop_gui_*.png)
locale/         # optional: translation files
```

## Conventions

- Language is Lua 5.1 / LuaJIT as provided by the Minetest engine. Avoid 5.2+ features (`goto`, bitwise operators, `//`).
- Keep everything in the `mine_shop_gui` namespace. Use a single global table (e.g. `mine_shop_gui = {}`) and keep other state `local`. Never leak globals.
- Prefix registered names, textures, and formspec names with `mine_shop_gui:` / `mine_shop_gui_`.
- Get the mod path with `core.get_modpath(core.get_current_modname())`. Prefer `core.*` over the legacy `minetest.*` alias unless targeting old engine versions.
- Build formspecs with `formspec_version[...]` set explicitly. Never trust fields from `core.register_on_player_receive_fields`: check the formname, the player, and validate every value server-side before acting on it.
- Shop actions that move items or currency must be atomic: check inventory space and funds first, then apply both changes, and handle failure paths without losing or duplicating items.
- Use `core.get_translator` (`S("...")`) for user-facing strings.
- Declare every dependency in `mod.conf` (`depends` or `optional_depends`) and guard optional ones with `core.get_modpath("othermod")`.

## Testing and running

- There is no automated test suite yet. To test, enable the mod in a world (Mods tab, or `load_mod_mine_shop_gui = true` in `world.mt`) and launch Minetest. Check `debug.txt` and the in-game console for Lua errors.
- If linting is added, use `luacheck` with a `.luacheckrc` declaring the Minetest globals.

## Working in this repo

- Make small, focused commits. The default branch is `master`.
- After completing a piece of work, commit it without waiting to be asked.
- Always ask the user before pushing. Never push to a remote without explicit confirmation, even if earlier pushes were approved.
- Do not commit generated files, world data, or `debug.txt`.
- Keep `README.md` user-facing (features, install, configuration). Keep agent- and developer-oriented notes here.
