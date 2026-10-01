# OpenDream-to-DMB translation fixtures

Each `.dme` is independent. Compile it with Dream Maker and OpenDream, then
compare DreamDaemon's startup log for a translated DMB with the reference below.
Source files and selected OpenDream `.json` output are fixtures. Compiled
`.dmb` and `.rsc` files are local test artifacts.

| Fixture | Translation feature | Expected DreamDaemon log line |
| --- | --- | --- |
| `variables.dme` | global, instance, and proc static variables | `VARIABLES 2 4 5` |
| `lists.dme` | list allocation, append, indexed and associative lookup | `LISTS 4 5 42` |
| `control_flow.dme` | loop, `continue`, branch, and ternary | `CONTROL 8 yes` |
| `calls.dme` | global proc and member proc calls with arguments | `CALLS 8 8` |
| `inheritance.dme` | subclass default override and parent proc call | `INHERITANCE 10` |
| `maps.dme` | `.dmm` cell, turf, area, map object override, and dimensions | `MAPS 1 1 1 fixture floor 12` |
| `assets.dme` | bundled file resource and `isfile()` | `ASSETS 1` |

These were compiled with Dream Maker 516.1687 and OpenDream DMCompiler
516.1655 on 2026-09-26. The Dream Maker DMBs were booted with DreamDaemon
516.1687 to establish the expected log lines.

Additional paired static fixtures cover `multi_maps` (disjoint z-levels),
`skin_simple` (DMF resource), `resource_kinds` (nine common asset extensions),
`map_list` and `map_assoc` (list override bytecode), `map_proc` (proc-reference
override), `map_mixed` (positional and associative list keys), `infinity`
(numeric infinity constants), `static_const` (static declaration flags), and
`proc_constant`/`proc_inherited` (class proc-reference defaults).
`dynamic_initializer_fields` checks native value tag 62 for one list
declaration, two repeated list overrides, object creation, and a particle
generator; null and scalar overrides stay unmarked. Its JSON requires the
pinned exporter annotation patch.
Their DMB records were compared statically; no DreamDaemon run is claimed for
these additional fixtures.

`builtin_global_shadow` is a compile-only native fixture for `#undef` followed
by class and procedure statics named `NORTH` or `TRUE`. Native root constants
and independently mutable same-name statics must keep separate binding IDs.
Eight authored bodies are checked in both debug modes, with immutable constant
reads separately checked against their exact native default and declaration
flags. The test explicitly rejects aliasing across six mutable bindings.
