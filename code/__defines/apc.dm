// ─────────────────────────────────────────────────────────────────────────────
// APC (Area Power Controller) global defines
//
// Pulled out of apc.dm so that the delegate datums (apc_power_distributor,
// apc_icon_renderer) can reference them without depending on include order.
// ─────────────────────────────────────────────────────────────────────────────

// Power channel states (lighting / equipment / environ vars)
#define POWERCHAN_OFF      0  // Channel is off; stays off until manually changed.
#define POWERCHAN_OFF_AUTO 1  // Channel is off; turns on automatically when power recovers.
#define POWERCHAN_ON       2  // Channel is on; stays on until manually changed.
#define POWERCHAN_ON_AUTO  3  // Channel is on; turns off automatically on low power.

// main_status values
#define APC_EXTERNAL_POWER_NOTCONNECTED 0
#define APC_EXTERNAL_POWER_NOENERGY     1
#define APC_EXTERNAL_POWER_GOOD         2

// has_electronics states
#define APC_HAS_ELECTRONICS_NONE    0
#define APC_HAS_ELECTRONICS_WIRED   1
#define APC_HAS_ELECTRONICS_SECURED 2

// Nightshift lighting modes
#define NIGHTSHIFT_AUTO   1
#define NIGHTSHIFT_NEVER  2
#define NIGHTSHIFT_ALWAYS 3

// update_state bitflags (used by check_updates() and apc_icon_renderer)
#define UPDATE_CELL_IN    1
#define UPDATE_OPENED1    2
#define UPDATE_OPENED2    4
#define UPDATE_MAINT      8
#define UPDATE_BROKE     16
#define UPDATE_BLUESCREEN 32
#define UPDATE_WIREEXP   64
#define UPDATE_ALLGOOD  128

// update_overlay bitflags (used by apc_icon_renderer)
#define APC_UPOVERLAY_CHARGEING0  1
#define APC_UPOVERLAY_CHARGEING1  2
#define APC_UPOVERLAY_CHARGEING2  4
#define APC_UPOVERLAY_EQUIPMENT0  8
#define APC_UPOVERLAY_EQUIPMENT1 16
#define APC_UPOVERLAY_EQUIPMENT2 32
#define APC_UPOVERLAY_LIGHTING0  64
#define APC_UPOVERLAY_LIGHTING1  128
#define APC_UPOVERLAY_LIGHTING2  256
#define APC_UPOVERLAY_ENVIRON0   512
#define APC_UPOVERLAY_ENVIRON1   1024
#define APC_UPOVERLAY_ENVIRON2   2048
#define APC_UPOVERLAY_LOCKED     4096
#define APC_UPOVERLAY_OPERATING  8192

// Icon update cooldown — delay between consecutive icon refreshes (deciseconds).
#define APC_UPDATE_ICON_COOLDOWN 100

// EMP protection factor for "critical" APCs.
#define CRITICAL_APC_EMP_PROTECTION 10

// Return bitfield from /datum/apc_power_distributor/proc/process().
// Used by apc.dm to decide whether to queue icon / area updates.
#define ADIST_CHANGED_CHANNELS 1
#define ADIST_CHANGED_CHARGING 2
