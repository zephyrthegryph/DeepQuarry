#!/usr/bin/env bash
# Check selector filtering without starting a compiler or a test world.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. tools/dq_proof_cache.sh
export DQ_NO_PINS=1
for selector in dq_conversion_pin dq_requirement_protocol_pin dq_look_state_pin dq_timed_pin/last_occupant/cryo_yes /datum/unit_test/dq_pin_constructor_repairs/* dx_menu_order dq_constraint_parity/holster /datum/unit_test/dq_constraint_parity/equip/representative; do
	if proof_test_enabled "$selector"; then echo "FAIL: enabled snapshot $selector" >&2; exit 1; fi
done
for selector in dq_boot_gate dq_native_property_dependencies dq_containment_sharp_old; do
	proof_test_enabled "$selector" || { echo "FAIL: excluded behavior $selector" >&2; exit 1; }
done
while IFS= read -r selector; do
	proof_test_enabled "$selector" || { echo "FAIL: smoke retained $selector" >&2; exit 1; }
done < <(proof_smoke_tests)
unset DQ_NO_PINS
proof_test_enabled dq_conversion_pin
echo 'PASS: no-pins filters explicit and inherited snapshot selectors'
