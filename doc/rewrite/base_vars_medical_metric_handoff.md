# Medical metric cursor cohort (source only)

Owner directory `code/modules/medical/`: three human base fields move to the actual body domain owner. The cursor compares the same neural load/radiation/temperature values and invalidates the same BODY_DIRTY_METRICS bit. A bodyless caller has no domain to invalidate and now returns before cache work; a new body starts its own unobserved cursor instead of inheriting another body's cache. No duplicate human state or base-type field is added. The existing medical dirty-domain test now writes the cursor on its real owner.

`dq_medical_metric_home` asserts real-body values, unchanged-state non-wakeup, changed-state invalidation and independent bodies. Also select existing `dq_medical_dirty_domains_wake_exactly`. No generation, compilation, tests, baseline update or stamp has run.
