// ─────────────────────────────────────────────────────────────────────────────
// APC (Area Power Controller) global defines
//
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

// EMP protection factor for "critical" APCs.
#define CRITICAL_APC_EMP_PROTECTION 10


