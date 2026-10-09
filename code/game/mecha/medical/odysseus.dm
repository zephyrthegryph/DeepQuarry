/obj/mecha/medical/odysseus
	desc = "These exosuits are developed and produced by Vey-Med. (&copy; All rights reserved)."
	name = "Odysseus"
	catalogue_data = list(
		/datum/category_item/catalogue/technology/odysseus,
		/datum/category_item/catalogue/information/organization/vey_med
		)
	icon_state = "odysseus"
	initial_icon = "odysseus"
	step_in = 2
	max_temperature = 15000
	max_integrity = 70
	wreckage = /obj/effect/decal/mecha_wreckage/odysseus
	internal_damage_threshold = 35
	step_energy_drain = 6
	var/obj/item/clothing/glasses/hud/health/mech/hud

	icon_scale_x = 1.2
	icon_scale_y = 1.2

CAPABILITIES(/obj/mecha/medical/odysseus)
	owns_one(nameof(hud), starts = /obj/item/clothing/glasses/hud/health/mech)

/obj/mecha/medical/odysseus/moved_inside(mob/living/carbon/human/H as mob)
	if(..())
		if(H.get_equipped_item(SLOT_ID_EYES))
			occupant_message(span_red("[H.get_equipped_item(SLOT_ID_EYES)] prevent you from using [src] [hud]!"))
		else if(move_into(H, SLOT_ID_EYES, hud, H))
			H.recalculate_vis()
		return 1
	else
		return 0

/obj/mecha/medical/odysseus/go_out()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant
		if(H.get_equipped_item(SLOT_ID_EYES) == hud)
			H.slot_remove(hud, src, H)
			H.recalculate_vis()
	..()
	return

/obj/item/clothing/glasses/hud/health/mech
	name = "Integrated Medical Hud"


//	process_hud(var/mob/M) //TODO VIS
/*
		to_world("view(M)")
		for(var/mob/mob in view(M))
			to_world("[mob]")
		to_world("view(M.client)")
		for(var/mob/mob in view(M.client))
			to_world("[mob]")
		to_world("view(M.loc)")
		for(var/mob/mob in view(M.loc))
			to_world("[mob]")


		if(!M || M.stat || !(M in view(M)))	return
		if(!M.client)	return
		var/client/C = M.client
		var/image/holder
		for(var/mob/living/carbon/human/patient in view(M.loc))
			if(M.see_invisible < patient.invisibility)
				continue
			var/foundVirus = 0

			for (var/ID in patient.virus2)
				if (ID in virusDB)
					foundVirus = 1
					break

			holder = patient.hud_list[HEALTH_HUD]
			if(patient.stat == DEAD)
				holder.icon_state = "hudhealth-100"
				C.images += holder
			else
				holder.icon_state = vitality_hud_state(patient)
				C.images += holder

			holder = patient.hud_list[STATUS_HUD]
			if(HAS_SYNTHETIC_BIOLOGY(patient))
				holder.icon_state = "hudrobo"
			else if(patient.stat == DEAD)
				holder.icon_state = "huddead"
			else if(foundVirus)
				holder.icon_state = "hudill"
			else if(patient.has_brain_worms())
				var/mob/living/simple_mob/animal/borer/B = patient.has_brain_worms()
				if(B.controlling)
					holder.icon_state = "hudbrainworm"
				else
					holder.icon_state = "hudhealthy"
			else
				holder.icon_state = "hudhealthy"

			C.images += holder
*/
TYPE_TABLE(/obj/mecha/medical/odysseus/loaded, mecha_starting_equipment, list( \
		/obj/item/mecha_parts/mecha_equipment/tool/sleeper, \
		/obj/item/mecha_parts/mecha_equipment/tool/sleeper, \
		/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun \
		))

//Meant for random spawns.
/obj/mecha/medical/odysseus/old
	desc = "An aging combat exosuit utilized by many corporations. Originally developed to combat hostile alien lifeforms. This one is particularly worn looking and likely isn't as sturdy."

// ALLOW(init/INSTANCE_STATE): an old exosuit starts worn, damaged and with a random charge
/obj/mecha/medical/odysseus/old/Initialize(mapload)
	. = ..()
	max_integrity = 50	//Just slightly worse.
	update_integrity(25)
	cell.set_charge(rand(0, (cell.charge/2)))


// === merged from odysseus_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/mecha/medical/odysseus/
	minimum_penetration = 0

/obj/mecha/medical/odysseus/ownership()
	. = ..()
	. += owns(nameof(hud), policy = OWN_CONTAINED)
