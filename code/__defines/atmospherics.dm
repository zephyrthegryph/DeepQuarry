// DeepQuarry atmospherics defines.
//
// LINDA atmospherics (vendored from /tg/, backed by auxmos in Rust) is the
// only atmos engine in DQ. ZAS and XGM are no longer compiled into the build.
// See doc/atmos_migration.md.

// XGM call-site rewrite helpers. CHOMP consumers that haven't been per-site
// rewritten use these macros to bridge to LINDA's gas_mixture shape.
//   LINDA_GAS_AMT(mix, gas_id_str)        → moles of `gas_id_str` in `mix`, 0 if absent.
//   LINDA_GAS_ADJUST(mix, gas_id_str, d)  → add `d` moles of `gas_id_str` to `mix`.
//
// `get_xgm_id_for_gas` lives in code/atmospherics/xgm_compat_shim.dm
// — it maps CHOMP's string gas-id ("oxygen", "phoron") to /datum/gas type path.
//
// AMT keeps outer parens because the ternary needs grouping. ADJUST omits
// outer parens so callers can chain. LINDA_GAS_LIST does NOT exist — DM's
// preprocessor doesn't handle `MACRO(x).member` cleanly; whole-list `.gas`
// references must be per-site rewritten to get_gases().
//
// Under auxmos the per-mixture `gases` list is gone; moles route through the
// arena-backed get_moles() getter (returns 0 for absent gases, so no presence
// guard is needed). gas_id_str is a CHOMP string id mapped to a /datum/gas
// type path by get_xgm_id_for_gas().

#define LINDA_GAS_AMT(mix, gas_id_str) \
	( mix ? mix.get_moles(mix.get_xgm_id_for_gas(gas_id_str)) : 0 )
#define LINDA_GAS_ADJUST(mix, gas_id_str, delta) mix.adjust_gas(gas_id_str, delta)

// /tg/ helpers/plane defines/wet-floor constants are below in the consolidated block.

// SSair subtask constants — vendored from /tg/'s code/__DEFINES/subsystems.dm.
// SSair's `fire()` uses these to checkpoint where it was when MC tick budget runs
// out, so it resumes from the same subtask on the next fire().
#define SSAIR_PIPENETS 1
// SSAIR_ATMOSMACHINERY (2) deleted with the atmos_machinery process
// queue; devices run via SSmachines. Don't reuse value 2 — leaving the gap
// keeps the fire() switch identifiers stable if a future merge re-introduces it.
// SSAIR_ACTIVETURFS (3) deleted — the DM active-turf loop is gone; turf sharing
// is the auxmos Rust FDM (SSAIR_TURFS below). Value kept vacant.
#define SSAIR_HOTSPOTS 4
#define SSAIR_EXCITEDGROUPS 5
#define SSAIR_HIGHPRESSURE 6
#define SSAIR_SUPERCONDUCTIVITY 7 // process_turf_heat (Rust auxmos heat conduction)
// SSAIR_PROCESS_ATOMS (8) deleted alongside atom_process / process_exposure.
// auxmos turf-processing steps. These run in a fixed order each fire(); the
// fire() switch checkpoints on them so a mid-tick MC pause resumes correctly.
#define SSAIR_TURFS 9              // process_turfs_auxtools (Rust FDM sharing)
#define SSAIR_EQUALIZE 10         // process_turf_equalize_auxtools (katmos)
#define SSAIR_FINALIZE_TURFS 11   // drain Rust->DM callbacks (react/set_visuals/pressure)

// Milliseconds of tick budget still available to hand an auxmos turf-processing
// bind. TICK_USAGE and Master.current_ticklimit are both percentages of a tick
// (0-100); TICK_DELTA_TO_MS converts a percentage to milliseconds using
// world.tick_lag. Clamped to a small positive floor so we never hand the Rust
// side a zero/negative budget (it would parse as 50ms via unwrap_or, over-running
// the tick). The Rust binds internally checkpoint against this and return
// "overtimed" so SSair pauses/resumes cleanly.
#define SSAIR_REMAINING_MS (max(TICK_DELTA_TO_MS(Master.current_ticklimit - TICK_USAGE), 1))

// Pipeline rebuild helper subtasks.
#define SSAIR_REBUILD_PIPELINE 1
#define SSAIR_REBUILD_QUEUE 2

// /tg/'s init-state flag — set on atom.flags_1 after Initialize completes.
// CHOMP uses atom_init/SS_INITIALIZED elsewhere; LINDA atom-aware atmos code
// checks this flag to skip pre-init atoms. Defined here so vendored atmos files
// compile; the flag bit value matches /tg/'s code/__DEFINES/_flags.dm:33.
#define INITIALIZED_1 (1<<5)

// /tg/'s "iterate every turf in the world" macro. Variadic to match the /tg/
// signature exactly; uses BYOND's block(x1, y1, z1, x2, y2, z2) form.
#define ALL_TURFS(...) block(1, 1, 1, world.maxx, world.maxy, world.maxz)

// /tg/ multi-z direction constants — CHOMP uses UP/DOWN; alias here.
#define Z_LEVEL_UP UP
#define Z_LEVEL_DOWN DOWN

// TURF_WET_PERMAFROST removed; the only reference was the deleted
// VOLATILE_REACTION branch in gasmixtures/reactions.dm (water_vapor reaction).

// /tg/'s LINDA plane defines — alias to CHOMP's nearest equivalents.
// Defined early so vendored atmos files (gas_types.dm, LINDA_fire.dm) see them.
#define ABOVE_GAME_PLANE (OBJ_PLANE + 1)
#define OVERLAY_LIGHT 0
#define HIGH_GAME_PLANE OBJ_PLANE
// Param name MUST NOT be `plane` — DM's preprocessor substitutes inside member
// access, so `target.plane = plane` would rewrite to `target.<expansion> = ...`.
// Rename to `_p`; this is /tg/'s convention.
#define SET_PLANE_W_SCALAR(target, _p, scalar) target.plane = _p
#define IS_FINITE(X) (isnum(X) && (X != INFINITY) && (X != -INFINITY) && (X == X))
#define GET_TURF_PLANE_OFFSET(T) 0

// /tg/'s REVERSE_DIR macro. CHOMP has /proc/turn() but no inline macro. Provide one.
#define REVERSE_DIR(dir) ( ((dir & (NORTH|SOUTH)) << 2) | ((dir & (EAST|WEST)) >> 2) | (dir & (UP|DOWN)) )

// xgm_total_moles helper proc. CHOMP consumers that read `mix.total_moles` as
// a var were hand-rewritten to call this proc, which forwards to LINDA's
// total_moles() — the var/proc name collision is why a direct shim isn't possible.
/proc/xgm_total_moles(datum/gas_mixture/mix)
	return mix ? mix.total_moles() : 0

// FUSION_HEAT_CAP is #define'd in code/modules/power/fusion/_setup.dm
// then #undef'd in core_field.dm. fusion_reactions.dm (which loads after
// core_field.dm) still references it. Redeclare globally so the macro is in
// scope at fusion_reactions.dm:149+.
#define FUSION_HEAT_CAP 1.57e7
