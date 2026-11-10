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
- Price files live in `prices/games/<game_id>.lua` and `prices/mods/<mod_id>.lua`. Name a mod's file after the `name` in its `mod.conf`, never after its folder (folder names are deprecated). Every item named in a price file must exist; check against a world that has the mod loaded.
- A price in a price file is a ceiling: a recipe that makes the item for less lowers it. Write `{ price = n, fixed = true }` only for a true anchor that must never be lowered. When you add a loop anchor (an item only made by uncrafting slabs, stairs or blocks), set it to the cost of its ingredients, or the ceiling rule will lower it and the report will show it.
- Declare every dependency in `mod.conf` (`depends` or `optional_depends`) and guard optional ones with `core.get_modpath("othermod")`.

## Testing and running

- Tests use the `mtt` mod and run inside the real Luanti engine. Do not write your own test harness, mock the Minetest API, or run the code under a standalone Lua interpreter.
- Tests live in `mtt.lua` (loaded from `init.lua` only when `mtt.enabled`). Register them with `mtt.register(name, function(callback) ... callback() end)`. Use `fakelib` players, not `mtt.join_player` (it fires every mod's join callbacks, and `credits` crashes on fake players).
- Engine: `C:\Users\Apollo\AppData\Local\luanti\5.18.0\bin\luanti.exe`. Its user folder is `C:\Users\Apollo\AppData\Roaming\Minetest`. Never kill an existing `luanti.exe` process; it is the user's game client.
- Run in a throwaway world in the scratchpad (never inside the repo). `world.mt` needs `gameid = minetest` and `load_mod_<name> = mods/<name>` entries (paths must be relative to the user folder, not absolute) for: `mine_shop_gui`, `mtt`, `fakelib`, `currency`, `credits`, `unified_money/um_core`, `unified_money/um_backend_plain`. Config file:
  ```
  mtt_enable = true
  mtt_filter = mine_shop_gui
  mg_name = singlenode
  mine_shop_gui_item_currency = default:goldblock=9, default:gold_ingot=1
  ```
  Command (exit code 0 means every test passed; always use a timeout):
  ```
  luanti.exe --server --world <world> --gameid minetest --config <conf> --logfile <log>
  ```
- Run the tests in two worlds. The small one (Minetest Game plus the mods listed above) skips the Technic tests. The Technic ones need a second world with `technic`, `ethereal`, `everness`, `3d_armor`, `pipeworks`, `techage_modpack`, `xcompat`, `unified_inventory`, `currency`, `credits`, `mtt`, `mine_shop_gui`, plus `unified_money/um_core` and `unified_money/um_backend_plain` only, plus `formspec_ast` (it checks the shop window's syntax; the small world needs it too). Modpacks cannot be enabled as one entry: list every mod inside them by its own path (`mods/technic/technic`, ...) and skip duplicates (`techage_modpack` ships its own `unified_inventory`). Both worlds must pass.
- Account balances persist in the world between runs. Tests that touch a balance (`unified_money`, `credits`) must reset it at the start (see `reset_credits` in `mtt.lua`), so runs never depend on a clean world.
- Only one version of `credits` can be present in a world, so the V1.2.3 code path (`credits_old`) is not covered by the automated tests.

## Working in this repo

- `AGENTS.md` holds rules for AI agents only. Record design decisions, findings, and agreed approaches in `PLAN.md`. Record open questions and pending tasks in `TODO.md`. Do not put either in this file.
- Make small, focused commits. The default branch is `master`.
- After completing a piece of work, commit it without waiting to be asked.
- Always ask the user before pushing. Never push to a remote without explicit confirmation, even if earlier pushes were approved.
- Do not commit generated files, world data, or `debug.txt`.
- Keep `README.md` user-facing (features, install, configuration). Keep agent- and developer-oriented notes here.
