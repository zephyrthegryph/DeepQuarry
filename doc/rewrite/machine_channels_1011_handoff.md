# Machinery channels — 2026-10-11

Stamped source: feac9cbd88ed, merged with master 1903f01e16.

Converted 93 channel bridges plus 16 settings bridges to native tracked state; updated 20 scheduler field descriptors. Vehicle condition state now uses native keys. Removed and hard-banned CHANGE_MACHINE_POWER, PANEL, BROKEN, ANCHORED, OCCUPANT, MODE and CHANGE_POWER_GRID_RATE, STATE, TOPOLOGY. The grid dependency and atomic-publication branch is included.

Against master 5d39966ad3, exact authored DM token matches for CHANGE_MACHINE_SETTINGS fell from 122 to 5; CHANGE_EXPLICIT from 53 to 51. These counts include defines, comments and the hit producer mask. The sole remaining actual settings publication is disposal: its delegated UI reads mode and continuous reservoir pressure, whose dependencies must be declared before removing the blanket wake. EXPLICIT still includes framework wake paths and eleven caches across six families; these need semantic migration, not renaming.

Fixed disposal flush_complete() assigning a shadowing local rather than the holder flag. A real timed flush regression asserts handle reset, custody and reservoir behavior. Removed an obsolete vehicle appearance watch after proving native providers do not read its legacy stat field.

Master fa9f430b95 moved light fields into light_glow traits. Repaired the hit producer to observe glow_of() and exclude opaque trait allocation only after capturing the actual light values. Added a falsifiable setter/observation regression. Existing hit goldens were preserved.

Verification: normal lane-ready, 29 passed / 0 failed; production compile and DreamChecker clean; analyzer and ratchets passed. Both dq_requirement_protocol_pin and dq_conversion_pin passed, as did dq_hit_pin and dq_hit_public_glow. The earlier 31/32 run passed the vehicle/disposal/edge repairs; its sole hit-producer failure was repaired before this successful gate. No full suite run.
## Master merge verification (2026-10-12)

Merged master 17f0997c4d, preserving both analyzer changes. Fixed draw_untracked without baseline changes: public emag observation reads native state directly, and the reconstitutor template is tracked. Added public emag-state and real reconstitutor setter/redraw coverage.

Fresh lane-ready stamp: 59b04b9b57. 34 tests passed, zero failed; production compile, DreamChecker (zero diagnostics), analyzer and ratchets passed. No full suite. Both mandatory requirement and conversion pins passed.

