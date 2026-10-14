# Ordinary tracked test writes

The ten ordinary tracked-test writes now use the real setters. The smartfridge fixture asserts its actual initial stat instead of writing a composed stat. The life-state fixture uses the real revival path and asserts consciousness plus its living look. Sequence tests independently assert explicit publication before changing heat, and rely on setters for setter-wake/parking checks.

The tracked_tests baseline shrinks from 11 to 1. The remaining kernel_sequence_audit heat write is the deliberate missed-publication fault; converting it to a setter would invalidate the test. Its approved validated fault-injection form still needs the owner-controlled tracked-lint contract, so this branch does not hide or reclassify the fault.

Minimal approved master typed-link repairs and their real tests are carried for mandatory conversion-pin coverage; their constructor goldens remain unchanged. The two retired mecha key tokens have cause f13b84652d in intended_changes.md.

Verification pending: dq_requirement_protocol_pin, dq_conversion_pin, dq_blocked_airlock_wakes_from_blocker_movement, dq_idle_auxiliary_machines_hibernate, dq_pipe_device_law_push_is_generated, dq_draw_life_state_follows_stat, kernel_sequence_sleep_wake, kernel_sequence_precheck, kernel_sequence_parking, and the two typed-link regressions. No full suite.
