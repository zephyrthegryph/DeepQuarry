// Rust world subscriptions on the scheduler (code/engine/time/world_watches.dm,
// doc/rewrite/archive/object_model_core.md §4.8). The numeric registry (WORLD_REASON_*,
// WORLD_WAKE_STRIDE) is generated from the Rust sources into verdigris/_bindings.dm.

// --- Comparisons for conditions and rate watches.
#define WORLD_CMP_ABOVE 0
#define WORLD_CMP_BELOW 1
/// Enters only past the limit (`value > limit`), leaves at `value <= limit - hysteresis`.
#define WORLD_CMP_ABOVE_STRICT 2
/// Enters only past the limit (`value < limit`), leaves at `value >= limit + hysteresis`.
#define WORLD_CMP_BELOW_STRICT 3

// --- Probe channels (the test Probe component, verdigris/ffi/src/sched.rs). A channel's
// reason bit is (1 << id).
#define CH_PROBE_PRESSURE 0
#define CH_PROBE_TEMPERATURE 1
#define CH_BIT(ch) (1 << (ch))

// --- Gas domain channels (verdigris/domains/gas/src/cell.rs, the same for turf gas and
// main-owned mixtures).
#define CH_GAS_PRESSURE 0
#define CH_GAS_TEMPERATURE 1
#define CH_GAS_MOLES 2
#define CH_GAS_OXYGEN 3
#define CH_GAS_PLASMA 4
#define CH_GAS_CARBON_DIOXIDE 5
#define CH_GAS_COMPOSITION 6
// Partial pressures (kPa) a breather's air watch follows (code/modules/mob/living/life/air_watch.dm).
#define CH_GAS_O2_KPA 7
#define CH_GAS_N2_KPA 8
#define CH_GAS_CO2_KPA 9
#define CH_GAS_PLASMA_KPA 10
#define CH_GAS_N2O_KPA 11
#define CH_GAS_CH4_KPA 12
#define CH_GAS_FUEL_KPA 13
// Moles, for a simple mob's environment limits.
#define CH_GAS_NITROGEN 14
#define CH_GAS_METHANE 15
// Oxygen and CO2 partial pressures summed (kPa): a skin breather (alraune) lives on either.
#define CH_GAS_O2_CO2_KPA 16
// Nitrous oxide and volatile fuel partial pressures summed (kPa): an air alarm's trace-gas limit.
#define CH_GAS_TRACE_KPA 17

// --- Watch handles: what a watch names, as list(code, cell). `code` is a component kind
// (VG_KIND_*, cells are vg_entity values) or VG_GAS_HANDLES (cells are gas arena ids).
#define WORLD_HANDLE(code, cell) list(code, cell)
/// The watch handle of a gas mixture (a turf's air, a tank, a canister).
#define WORLD_GAS_HANDLE(mixture) list(VG_GAS_HANDLES, (mixture).arena_id())

// --- DM-owned facts are not published into Rust. Game facts (areas, doors, powernets, chunks, ...) are tracked state and published keys.
