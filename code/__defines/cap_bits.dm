// The ONLY place cap_state bits are allocated (doc/rewrite/dx_conventions.md §2, review L1 / review 2 C2).
// Capability runtime state holds one bit per boolean capability state. DM bitwise math is safe to 24 bits.
// tools/ci/cap_bits_lint.py fails CI if a CAP_* bit is defined anywhere else, two share a value, or one
// reaches 1<<24. Take the next free bit here; never reuse a retired one in the same release.

/// cover(): the cover is open.
#define CAP_COVER_OPEN (1<<0)
/// panel(): the maintenance panel is open.
#define CAP_PANEL_OPEN (1<<1)
/// access_lock(): the access lock is engaged.
#define CAP_LOCKED (1<<2)
/// breakable(): broken (every entry refuses unless works_broken).
#define CAP_BROKEN (1<<3)
/// emag(): emagged.
#define CAP_EMAGGED (1<<4)
// (1<<5): retired (the legacy wires capability's CAP_WIRES_EXPOSED).
/// Door weld_shut(): welded shut.
#define CAP_WELDED (1<<6)
/// smokable(): lit.
#define CAP_LIT (1<<9)
/// two_handed(): wielded.
#define CAP_WIELDED (1<<10)
/// toggle_state(): the first, second and third toggles of a holder (a hood, buttons, sensors).
#define CAP_TOGGLE_1 (1<<11)
#define CAP_TOGGLE_2 (1<<12)
#define CAP_TOGGLE_3 (1<<13)
/// cover(removable = TRUE): the cover is knocked off (APC).
#define CAP_COVER_REMOVED (1<<14)
/// Door emergency_access(): emergency access on.
// Free: 16 .. 23.
