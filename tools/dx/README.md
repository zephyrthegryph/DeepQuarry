# tools/dx — one-time DX capability migration tools

Both tools are for the machine migration waves (framework_review2.md §4 item 10). They are
table-driven, have a `--selftest` with inline fixtures, and default to nothing clever: anything
they can't prove safe they list instead of changing. Run them with the repo's Python 3.11+.

## convert_map_capabilities.py — map varedits -> `cap_state`

Rewrites instance varedits of removed base state vars (`locked`, `welded`, `p_open`,
`panel_open`, `emagged`, APC `opened`/`wiresexposed`, ...) into one `cap_state = CAP_X|CAP_Y`
varedit, using the bit values parsed from `code/__defines/cap_bits.dm`.

Table: `tools/dx/capability_varmap.json`, keyed by type path prefix (longest match on a path
segment boundary wins). Per var:

| spec | meaning |
|---|---|
| `"CAP_X"` | truthy value sets the bit, falsy (`0`, `null`, `FALSE`, `""`) clears it |
| `{"0": null, "1": "CAP_A", "2": "CAP_B"}` | value-mapped (APC `opened`); unmapped values are warned and left |
| `"drop"` | delete the varedit (transient state such as `operating`) |
| `"keep"` / absent | untouched — per-instance config (`req_access`, `id_tag`, ...) stays, rule H1 |
| `_default_bits` | bits the TYPE sets by default, so `locked = 0` on an APC clears `CAP_LOCKED`, and a result equal to the default emits no `cap_state` at all |

An existing `cap_state` varedit is parsed (names or integers) and merged into; output is
canonical (bits in value order, varedits sorted), so a second run is a no-op. Only the
dictionary section of the .dmm is touched; the grid is byte-identical. Handles TGM and
single-line `{a = 1; b = 2}` blocks, quoted `;`/`}` and `list(...)` values.

```
python tools/dx/convert_map_capabilities.py --selftest
python tools/dx/convert_map_capabilities.py --dry-run maps/southern_cross/*.dmm   # per-map summary
python tools/dx/convert_map_capabilities.py --report                              # tree-wide counts
python tools/dx/convert_map_capabilities.py maps/southern_cross/*.dmm             # rewrite (waves only)
```

`--numeric` writes `cap_state = 192` instead of `CAP_WELDED|CAP_BOLTED`: use it for maps loaded
at runtime by the map loader (submaps, templates), which does not see preprocessor defines.
Convert a type's maps in the same commit that removes its old vars.

## rename_icon_states.py — readable capability layer names

Renames icon states in the icon pipeline SOURCES (`icons/**/*.dmi.toml`; the .png sheet is
positional, so only `name = "..."` changes; `icons/gen/` is never touched — the build repacks
it). Table: `tools/dx/icon_state_renames.json`, `{"icons/x.dmi": {"old": "new"}}`. Refuses
(before writing anything) unknown states and renames that collide with a kept state.

References it rewrites:
- **code**: an exact `"old"` literal in a .dm file that references `'icons/x.dmi'`, on a line
  with icon context, when no other dmi the file references has a different fate for `"old"`;
- **maps**: `icon_state = "old"` varedits on instances whose icon is that dmi (an `icon =`
  varedit, else the type's declared `icon`, resolved up the type tree parsed from `code/`).

References it only LISTS (`AMBIG`): interpolated strings that could build a renamed state
(`"[initial(icon_state)]-panel"`, collapsed to one line per site), literals without icon
context, literals in files that reference another dmi with the same state, and literals of
states unique to renamed dmis in files that draw through a var icon (`apc.icon`). Migrate
those by hand in the same wave.

```
python tools/dx/rename_icon_states.py --selftest
python tools/dx/rename_icon_states.py --dry-run          # WOULD / AMBIG / ERROR lines + summary
python tools/dx/rename_icon_states.py                    # apply (waves only), then rebuild icons
python tools/dx/rename_icon_states.py --renames my.json --maps "maps/southern_cross/*.dmm"
```

The shipped `icon_state_renames.json` is a starter PROPOSAL (not applied): APC states in
`power.dmi` and `wall_machines_angled.dmi` (`apc-spark`->`sparks`, `apcewires`->`wires`,
`apc-b`->`broken`, `apcmaint`->`cover_open`, `apcox-1/0`->`locked`/`unlocked`), airlock
`door_locked`->`locked`, `sparks_damaged`->`sparks`, `sparks_broken`->`broken` in every
`icons/obj/doors/*` that has them, and vending `<base>-panel`->`<base>-panel_open`,
`<base>-off`->`<base>-dark` (generated from the toml state lists). Trim it per wave: a wave
should pass only the dmis it migrates.
