// Organ lifecycle hooks for medical conditions.
//
// Conditions are stored on the organ object (`organ.medical_issues`).
// When the organ leaves a body — limb severed, internal organ extracted —
// the upstream `removed()` proc nulls each condition's `owner` so the
// patient stops processing it. The condition object lives on with the
// organ. The organ's own `process()` loop continues to tick the
// conditions via `handle_offline()` so severity keeps drifting.
//
// When the organ is re-implanted — limb reattach surgery,
// internal-organ implantation — the upstream `replaced()` proc calls
// `dq_reseat_owner()` here to hook everything back up so the patient
// resumes feeling the symptoms.

/// Re-anchor every medical condition attached to this organ to the new
/// owner. Idempotent — safe to call even if the organ is already attached.
/// Forces a symptom reroll so the new patient gets a fresh symptom set
/// instead of stale data from the previous owner.
/obj/item/organ/proc/dq_reseat_owner(mob/living/carbon/human/new_owner)
	if(!medical_issues)
		return
	for(var/datum/medical_issue/condition/C in medical_issues)
		C.owner = new_owner
		// Reset the band tracker so the next tick re-rolls symptoms
		// against the patient currently hosting the condition. Without
		// this a transplant patient would keep seeing the donor's last
		// rolled symptom set until severity crossed a band boundary.
		C.last_reroll_band = -1
