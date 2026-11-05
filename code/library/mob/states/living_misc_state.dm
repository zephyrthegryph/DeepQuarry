// living_misc: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, living_misc, field), write with living_misc_of(M).set_field(value), end it with living_misc_clear(M).

/datum/living_misc_state
	/// /mob/living
	var/adminbus_eat_minerals = FALSE
	/// / The selection marker a mob shows the admins who picked it in buildmode, made the first time one does.
	var/image/buildmode_selected_image
	var/churn_count = 0
	var/composition_reagent_quantity
	var/custom_link
	var/holder_default
	/// / The z-level whose presence lists this low-priority mob (sparse slot life_z; unset: none).
	var/life_z = 0
	var/mute_entry = FALSE
	var/photosynthesis_boost = 0
	var/pickup_active = TRUE
	var/revival_in_progress = FALSE
	var/skin_reagent
	var/summoned
	var/tf_form_holds_key = FALSE
	var/tod
	var/touch_reaction_flags
	var/trash_catching = FALSE
	var/updating_cult_vision = 0

/mob/living
	var/datum/living_misc_state/living_misc
