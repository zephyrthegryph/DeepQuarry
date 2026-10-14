# E3 menu-order profiling

Baseline focused profile on master1828a63c82 passed, 32.9seconds. Profile: data/logs/run1/profile/dx_menu_order.json. op_resolution_sort had1,002calls/15.15seconds total; op_cand_precedes8.04seconds self across8,526,393calls. Allocations622calls/6.28seconds total were secondary.

The pass path skips the unasserted diagnostic all-order sort. Capture and mismatch paths still sort the same full candidates for identical DXORDER/DXDIFF details. All334scenarios, production resolver/menu calls, fresh fixtures, teardown, click/menu assertions, nonempty-row count and golden rows are preserved. Repeated held/mode lists are hoisted. No gameplay/resolver changes or pin blessing.

Expected pass-path sorts1,002 ->668. Post-change focused profile and final lane gate pending. No full suite, merge or push.
