/datum/power/changeling/changeling_revive
	name = "Revive"
	desc = "We revive from our death-like state."
	helptext = "Regeneration must first be started via Regenerative Stasis."
	ability_icon_state = "ling_revive"
	genomecost = 0
	allowduringlesserform = TRUE
	verbpath = /mob/proc/changeling_revive

//Revive from revival stasis
/mob/proc/changeling_revive()
	set category = "Changeling"
	set name = "Revive"
	set desc = "We are ready to revive ourselves on command."

	var/datum/component/antag/changeling/changeling = changeling_power(0,0,100,DEAD)
	if(!changeling)
		return FALSE

	if(stat != DEAD)
		to_chat(src, span_danger("We are not dead."))
		return FALSE
	if(!changeling.is_reviving)
		to_chat(src, span_danger("We have not begun the regeneration process yet.."))
		return FALSE
	if(changeling.is_on_cooldown(FAKE_DEATH))
		to_chat(src, span_danger("We are still recovering. We will be able to revive again in [(changeling.get_cooldown(FAKE_DEATH) - world.time)/10] seconds."))
		return FALSE

	if(changeling.max_geneticpoints < 0) //Absorbed by another ling
		to_chat(src, span_danger("You have no genomes, not even your own, and cannot revive."))
		return FALSE

	if(src.stat == DEAD)
		GLOB.dead_mob_list -= src
		GLOB.living_mob_list += src
	var/mob/living/carbon/C = src

	C.tod = null
	C.fully_heal()
	C.SetParalysis(0)
	C.SetStunned(0)
	C.SetWeakened(0)
	C.radiation = 0
	C.reagents.clear_reagents()
	if(ishuman(C))
		var/mob/living/carbon/human/H = src
		H.species.create_organs(H)
		H.restore_all_organs(ignore_prosthetic_prefs=1) //Covers things like fractures and other things not covered by the above.
		H.restore_blood()
		H.mutations.Remove(HUSK)
		H.status_flags &= ~DISFIGURED
		H.update_icons_body()
		for(var/limb in H.organs_by_name)
			var/obj/item/organ/external/current_limb = H.organs_by_name[limb]
			if(current_limb)
				current_limb.relocate()
				current_limb.open = 0

		BITSET(H.hud_updateflag, HEALTH_HUD)
		BITSET(H.hud_updateflag, STATUS_HUD)
		BITSET(H.hud_updateflag, LIFE_HUD)

		if(H.get_equipped_item(SLOT_ID_HANDCUFFED))
			H.drop_from_inventory(H.get_equipped_item(SLOT_ID_HANDCUFFED), H.loc)
		if(H.get_equipped_item(SLOT_ID_LEGCUFFED))
			H.drop_from_inventory(H.get_equipped_item(SLOT_ID_LEGCUFFED), H.loc)
		if(istype(H.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/straight_jacket))
			H.drop_from_inventory(H.get_equipped_item(SLOT_ID_SUIT), H.loc)
		H.UpdateAppearance()

	C.shock_stage = 0 //Pain
	to_chat(C, span_notice("We have regenerated."))
	C.update_canmove()
	feedback_add_details("changeling_powers","CR")
	C.set_stat(CONSCIOUS)
	C.forbid_seeing_deadchat = FALSE
	C.timeofdeath = null
	changeling.is_reviving = FALSE

	return TRUE
