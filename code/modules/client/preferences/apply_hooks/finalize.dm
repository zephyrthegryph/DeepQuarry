// DQAdd — Post-everything cleanup. Runs last to:
//   - rewalk worn clothing and re-apply digitigrade transforms
//   - reset the DNA UI from the now-final body state
//   - force a limbs / icon refresh so all the changes above become visible at once

/datum/preference_apply_hook/finalize
	priority = APPLY_HOOK_PRIORITY_LATE + 50

/datum/preference_apply_hook/finalize/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target))
		return
	for(var/obj/item/clothing/O in target.contents)
		O.handle_digitigrade(target)
	if(target.dna)
		target.dna.ResetUIFrom(target)
	target.force_update_limbs()
	target.regenerate_icons()
