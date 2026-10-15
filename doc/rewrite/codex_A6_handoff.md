# A6 power initializer sweep

Before:191 init_lines,0 world_reads. Analyzer-confirmed after:105 init_lines,0 world_reads;86 removed (global baseline4115→4029,decl unchanged47).

24 declared setup jobs across18 production files: rack look/starting cells; fusion monitor tags; fuel base and both blitz overrides; station gravity parts; sensor identity/history; field proximity; emitter initial state; particle first move/control power/recipes; POI charge; solar integrity/direction; broken-shard admin announcement; energy-ball glow; compressor/turbine pairing; both broken-light subtype jobs.

No TRACKED lines, existing setter calls, ownership/relation/reference declarations changed. Original random draws, constructor interleaving and debug/admin logging preserved. No added base vars/shadow state, baseline edits or ALLOWs.

Fuel inheritance trap: parent blitz currently defaults fuel_type to five spaces. The old parent fills that key and each child adds blitz/blitzu. All three jobs move together and that dual-entry behavior stays; child fuel_type cannot move to a type default without changing the parent input and fuel contents. Child name/color/glow overrides likewise happen after the parent material job. Their constants are therefore part of the ordered override job, not independent defaults.

Broken-light trap: small/broken formerly calls broken() twice through its parent chain. Two distinct named setup hooks preserve both calls; a direct repeated PROC_REF(broken) would deduplicate and change side effects.

New test include code/modules/unit_tests/dq_a6_power_init.dm; seven leaf selectors under dq_a6_power_init/* (fuel inheritance including actual nullspace unshielded pulse, actual starting monitor tags/range, sensor histories, mapped rack cells/final overlay state, field direction, both broken light types, native POI charge/caps). Existing useful tests: dq_pp/turbine_output_curve, dq_pp/solar_output, dq_pp/emitter_controls, dq_pp/fusion_injector_fuel_use, dq_look_pin. Root chooses one focused batch. No builds/tests/cargo/gen/baseline/commits run by this agent.

## Residuals
- `apc.dm` (10): building/build_dir constructor inputs suppress initial cell before parent and choose built-frame state afterward. These include transient constructor arguments, area binding and construction stages reserved from this sweep.
- `cable.dm` (18): Actual mapped icon state determines endpoints, floor placement determines hiding/network joining. Coil material/blueprint state and alien embed normalization are consumed by subtype initializers; keep parent prerequisites and map/constructor data.
- `cell.dm` (3): Blueprint/material-service setup and unique UID precede emergency-light and external stand-in subtype checks. Moving parent setup after a rejecting subtype skips its old side effects/UID allocation; preserve parent timing.
- `cells/power_cells.dm` (3): Emergency cell starts empty based on its actual constructor area lightswitch/glow; genuine per-instance placement, following the cell parent prerequisite.
- `generator.dm` (1): Rated description is prepared before machinery parent initialization from actual mapper max_power; no supported early setup contract preserves that phase.
- `light_construct.dm` (7): Reads transient fixture_at_make, copying fingerprints, actual facing and graph stage before params are dropped at setup. No shadow constructor state or stages changes allowed.
- `lighting.dm` (37): Bulbs and fixtures copy transient fixture_at_make/construct_at_make data, apply mapper emergency-cell options, choose latent bulb state and power/area/layer before subtype init. floor lamp observes the construction input after parent. Preserve these parent/constructor dependencies; only broken subtype post-parent jobs are converted.
- `lightswitch.dm` (5): Generic construction parent computes actual mapper-facing offsets and graph-stage look before subtype constructors in machinery; preserve map state and shared prerequisite phase.
- `privacy_switch.dm` (3): Area ghost-sight flag sets its initial state before parent; moving to phase3 changes phase and mapper overwrite contract.
- `singularity/singularity.dm` (5): Admin-investigation setup/logging occurs before parent, then beacon targeting before energy-ball subtype init. Preserve early tracing and shared parent ordering.
- `smes.dm` (5): Terminal discovery and connect_to_network(!mapload) require the actual mapload flag; setup has no equivalent mapload input. Network phase also has to remain aligned with materialization binding.
- `smes_construction.dm` (3): placed_by_map is set before parent creates initial coils; actual parts then determine charge/caps. Preserve parent creation and mapper flag; POI charge/output/input post-parent job is converted.
- `supermatter/supermatter.dm` (3): UID and using_map.station_levels classification occur before parent; preserve counter/order and mapped-level setup. Broken-shard admin announcement post-parent job is converted.
- `terminal.dm` (2): Actual floor/level determines under-floor hiding; genuine per-instance map placement state.

Exact remaining fingerprints and expected removed identities are in the corresponding text files beside this report.

## Static review and possible gate repair
All selected jobs checked for source definitions and inheritance. Monitor children exist via unchanged starts declarations. Battery-rack parent and mapped child setup order retained. Fuel constants are not moved ahead of parent normalization. Shared root/cell/light prerequisites and transient inputs remain. Tests scope coalesce; light-template caches/dview/status policies warm in New; unshielded radiation uses a real nullspace constructor to avoid irradiating neighboring fixtures. No new getter API invented; POI charge uses actual stored_charge().
Possible newly exposed tracked site: solar max_integrity *=2 moves from Initialize to setup. Existing update_integrity call unchanged; parent was notified to review any required existing setter substitution. No raw assignment or setter declaration has been altered preemptively.

Moved raw fuel_colour, rod_glows and reinforced max_integrity writes now use existing registered setters. No pre-existing setter call or declaration changed. Tracked check passes after generation.


Read-tracking preflight on master 4ab2e15fe1 requires the three newly moved fuel_type writes to use their existing generated set_fuel_type setter. Those calls now publish in the exact previous positions, without editing any protected declaration or preexisting setter line. The now-unused particle initializer annotation was removed from above Bump. All other preflight checks passed; a repaired preflight and lane-ready proof remain pending. No compilation or runtime test has yet been run on this branch.
