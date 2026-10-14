# Phase D power support files

Four fully migrated leaf files move from `code/modules/power/` into `code/domains/power/content/`, preserving their relative paths:

- `antimatter/containment_jar.dm`
- `cells/esoteric_cells.dm`
- `debug_items.dm`
- `sensors/sensor_monitoring.dm`

Commit d566edcb04 contains only four exact renames and their four include-path replacements. Include order is unchanged. The moved blobs match master 86ad72702e byte for byte; the most recent source edits predate October 13, so the move does not overlap that day's source work.

The focused gate includes `dq_requirement_protocol_pin`, `dq_conversion_pin`, `dq_hc_struct/power_hit_declarations`, `dq_hc_tgui/power_monitor_buttons` and `dq_power_monitor_reading`. The containment test exercises the jar's real explosion/stability behavior; the monitor tests cover neighboring sensor/module behavior. There are no dedicated esoteric-cell or debug-item behavior tests in the current suite.

Verification is pending. No snapshot rows have been blessed for the move.

Completed lane-ready on edd8d9295a7c against master 23b388bc70: 54 passed, zero failed; production DreamMaker errors and DreamChecker diagnostics zero; analyzer and ratchets passed. The unchanged nonempty look-key record matched all 21,045 current plan rows, so incremental appearance probes were correctly empty. No golden changes or pin re-blesses were needed. The stamp is on the tested parent; this handoff is a documentation-only child.
