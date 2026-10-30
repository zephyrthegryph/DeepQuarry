// Boot work a focused unit-test world may skip (doc/testing.md "Boot work a focused run defers").
//
// A test declares `boot_needs = list(...)` (code/modules/unit_tests/unit_test.dm) naming the BOOT_NEED_* work it relies on;
// a test that declares nothing (null) is assumed to need all of it. A focused world (tools/dq_focused_test.sh) skips one piece
// of work only when EVERY selected test declared a list that leaves it out. The full suite, the merge gates and production never skip.

/// own_validate_boot(): validates the ownership table of every mapped type at boot instead of on first use.
#define BOOT_NEED_OWN_VALIDATE "own_validate"
/// The early asset datums (preference menus): built at boot instead of on first get_asset_datum().
#define BOOT_NEED_EARLY_ASSETS "early_assets"
/// create_all_lighting_objects(): lighting objects on every turf.
#define BOOT_NEED_LIGHTING "lighting"
/// GLOB.autospeaker, the global announcer radio.
#define BOOT_NEED_RADIO "radio"
/// The holo minimaps of every level.
#define BOOT_NEED_HOLOMAPS "holomaps"
