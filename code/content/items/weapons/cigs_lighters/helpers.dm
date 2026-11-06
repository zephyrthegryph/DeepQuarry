/// One puff of source's reagents: into the mouth of the human wearing it as a mask, else a little
/// burns away. Shared by smokables and the smokable capability.
/proc/smoke_reagents(obj/item/source, amount)
	if(!source.reagents || !source.reagents.total_volume) // check if it has any reagents at all
		return
	if(ishuman(source.loc))
		var/mob/living/carbon/human/C = source.loc
		if (source == C.get_equipped_item(SLOT_ID_MASK) && C.check_has_mouth()) // if it's in the human/monkey mouth, transfer reagents to the mob
			source.reagents.trans_to_mob(C, amount, CHEM_INGEST, 1.5, can_dialysis = FALSE) // I don't predict significant balance issues by letting blunts actually WORK.
	else // else just remove some of the reagents
		source.reagents.remove_any(REM)

/// Lighting source: phoron or fuel in it explodes (source is deleted, returns TRUE); otherwise its
/// reagents may react from now on. Shared by smokables and the smokable capability.
/proc/ignite_smoke_reagents(obj/item/source)
	if(source.reagents?.get_reagent_amount(REAGENT_ID_PHORON)) // the phoron explodes when exposed to fire
		var/datum/effect/effect/system/reagents_explosion/e = new()
		e.set_up(round(source.reagents.get_reagent_amount(REAGENT_ID_PHORON) / 2.5, 1), get_turf(source), 0, 0)
		e.start()
		destroyed(source)
		return TRUE
	if(source.reagents?.get_reagent_amount(REAGENT_ID_FUEL)) // the fuel explodes, too, but much less violently
		var/datum/effect/effect/system/reagents_explosion/e = new()
		e.set_up(round(source.reagents.get_reagent_amount(REAGENT_ID_FUEL) / 5, 1), get_turf(source), 0, 0)
		e.start()
		destroyed(source)
		return TRUE
	source.flags &= ~NOREACT // allowing reagents to react after being lit
	source.reagents?.handle_reactions()
	return FALSE
