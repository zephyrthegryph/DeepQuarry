GLOBAL_DATUM(highlanders, /datum/antagonist/highlander)

/datum/antagonist/highlander
	role_text = "Highlander"
	role_text_plural = "Highlanders"
	welcome_text = "There can be only one."
	id = MODE_HIGHLANDER
	flags = ANTAG_SUSPICIOUS | ANTAG_IMPLANT_IMMUNE //| ANTAG_RANDSPAWN | ANTAG_VOTABLE // Someday...

	hard_cap = 5
	hard_cap_round = 7
	initial_spawn_req = 3
	initial_spawn_target = 5

	id_type = /obj/item/card/id/centcom/ert

/datum/antagonist/highlander/New()
	..()
	GLOB.highlanders = src

/datum/antagonist/highlander/create_objectives(datum/mind/player)

	var/datum/objective/steal/steal_objective = new
	rel_set(steal_objective, nameof(steal_objective.owner), player)
	steal_objective.set_target("nuclear authentication disk")
	rel_add(player, nameof(player.objectives), steal_objective)

	var/datum/objective/hijack/hijack_objective = new
	rel_set(hijack_objective, nameof(hijack_objective.owner), player)
	rel_add(player, nameof(player.objectives), hijack_objective)

/datum/antagonist/highlander/equip(mob/living/carbon/human/player)

	if(!..())
		return

	// drop original items! It used to be a loop that just Qdeled everything including your organs!
	// Dropping because of non-oxy breathers... That would suck wouldn't it?
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_ID))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_SUIT))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_UNIFORM))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_EAR_L))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_HEAD))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_HAND_L))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_SHOES))
	player.drop_from_inventory(player.get_equipped_item(SLOT_ID_POCKET_L))
	// highlanders!
	player.equip_to_slot_or_del(new /obj/item/clothing/under/kilt(player), SLOT_ID_UNIFORM)
	player.equip_to_slot_or_del(new /obj/item/clothing/head/beret(player), SLOT_ID_HEAD)
	player.equip_to_slot_or_del(new /obj/item/material/sword(player), SLOT_ID_HAND_L)
	player.equip_to_slot_or_del(new /obj/item/clothing/shoes/boots/combat(player), SLOT_ID_SHOES)
	player.equip_to_slot_or_del(new /obj/item/pinpointer(get_turf(player)), SLOT_ID_POCKET_L)

	var/obj/item/card/id/id = create_id("Highlander", player)
	if(id)
		id.access |= SSaccess.get_all_station_access()
		id.icon_state = "centcom"
	create_radio(DTH_FREQ, player)

/**
 * Gives everyone kilts, berets, claymores, and pinpointers, with the objective to hijack the emergency shuttle.
 * Uses highlander controller to do so!
 *
 * Arguments:
 * * was_delayed: boolean: whether the option to do a "delayed" highlander was pressed before this was called, changes up the logging a bit.

 */
/client/proc/only_one(was_delayed = FALSE, mob/user)
	if(!SSticker.HasRoundStarted())
		tgui_alert_async(user, "The game hasn't started yet!")
		return

	if(was_delayed) //sends more accurate logs
		message_admins(span_adminnotice("[key_name_admin(user)]'s delayed THERE CAN ONLY BE ONE started!"))
		log_admin("[key_name(user)] delayed THERE CAN ONLY BE ONE started.")
	else
		message_admins(span_adminnotice("[key_name_admin(user)] used THERE CAN BE ONLY ONE!"))
		log_admin("[key_name(user)] used THERE CAN BE ONLY ONE.")

	for(var/mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(H.stat == 2 || !(H.client)) continue
		if(is_special_character(H)) continue
		GLOB.highlanders.add_antagonist(H.mind)

/client/proc/only_one_delayed(mob/user)
	message_admins(span_adminnotice("[key_name_admin(user)] used (delayed) THERE CAN BE ONLY ONE!"))
	log_admin("[key_name(user)] used delayed THERE CAN BE ONLY ONE.")
	after(src, 42 SECONDS, PROC_REF(only_one), with = list(TRUE, user), keeps_dead = TRUE)
