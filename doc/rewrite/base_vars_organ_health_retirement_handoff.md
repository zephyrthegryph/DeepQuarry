# Nullable item-health retirement proposal

One base-var row removed; source-only draft, no generation/tests run. Wire dq_base_vars_organ_sale_tests.dm and run dq_base_vars_organ_sale.

The only production item-health consumer is the typed internal-organ sell_error guard. Whole-tree source search found no item health assignments or subtype defaults; organs carry real damage/status/lesions instead. Both old compared values are therefore null in actual production transactions. The two map health assignments are demonAI mobs with their own state, not items. Removing the dead comparison preserves repository behavior; it does not substitute integrity or add another placeholder.

The real regression preserves packaging refusal, freezer acceptance and declared price, then changes actual organ condition via bruise and verifies the same old acceptance. Damaged organ sale acceptance is a preexisting bug and deliberately NOT fixed by this state-retirement cohort. An admin manually assigning obsolete health through VV/SDQL is not a supported source use; the obsolete field itself retires rather than being maintained as a shadow compatibility state. No refusal string changes in ordinary behavior.
