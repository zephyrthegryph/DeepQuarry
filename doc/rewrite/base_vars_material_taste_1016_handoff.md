# Material emission and taste samples

Source-only cohort, verification pending: four base-var declarations removed. Three item emission magnitudes use native numeric sparse slots; carbon's last taste text uses a native text sparse slot with the original empty-string default. Existing zero defaults, retained values, grant/revoke behavior, glow updates, fixed toxin dose and taste suppression clocks are unchanged.

Consumer audit: emission magnitudes are read only by configure_material_behaviors() and the periodic material_emission_step(); taste text is read only by ingest(). These are imperative effects, with no cached draw, stat, menu or requirement reads. No dependency/publication contract is added. The existing material replacement regression uses the native magnitude accessors.

Production files: code/modules/materials/material_behaviors.dm; code/modules/mob/living/carbon/carbon_defines.dm; code/modules/mob/living/carbon/taste.dm. Existing test: dq_material_science_tests.dm. New include: dq_base_vars_material_taste_tests.dm, with /datum/unit_test/dq_base_vars_material_taste/emissions and /ingestion. These exercise real glow/capability grant, actual held-human toxin injury, inert replacement, real reagent transfer, retained taste text and repeat cooldown. Also retain dq_material_refit_clears_old_behaviors in focused verification.

No generation, analyzer, compile or runtime test has run for this cohort; no baselines edited.
