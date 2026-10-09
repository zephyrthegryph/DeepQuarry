/**
 * proteans
 */
/obj/item/rig/protean
	name = "nanosuit control cluster"
	suit_type = "nanomachine"
	icon = 'icons/obj/rig_modules_vr.dmi'
	unremovable = TRUE //Can not be removed. At least, not initially.
	default_mob_icon = null	//Actually having a forced sprite for Proteans is ugly af. I'm not gonna make this a toggle
	icon_state = "nanomachine_rig"
	interface_intro = "Protean"
	armor_spec = "bio=100;rad=100"
	siemens_coefficient= 1
	slowdown = 0
	offline_slowdown = 0
	seal_delay = 0
	/// The protean character this cluster belongs to. While folded, it is inside us.
	var/mob/living/carbon/human/myprotean
	initial_modules = list(/obj/item/rig_module/protean/syphon, /obj/item/rig_module/protean/armor, /obj/item/rig_module/protean/healing)
	flags = PHORONGUARD
	item_flags = NOSTRIP

	helm_type = /obj/item/clothing/head/helmet/space/rig/protean //These are important for sprite pointers
	boot_type = /obj/item/clothing/shoes/magboots/rig/protean
	chest_type = /obj/item/clothing/suit/space/rig/protean
	glove_type = /obj/item/clothing/gloves/gauntlets/rig/protean
	protean = TRUE
	offline_vision_restriction = FALSE
	open = TRUE
	cell_type =  /obj/item/cell/protean
	var/assimilated_rig
	var/can_assimilate_rig = TRUE
	/// The protean is dormant: the cluster is a dead weight that protects nobody.
	var/inert = FALSE
	/// The wearer whose injuries this cluster soaks (not the protean itself).
	var/mob/living/carbon/human/soaking_wearer

/obj/item/rig/protean/relaymove(mob/user, direction)
	if(user != myprotean || user.stat || user.has_status(STAT_STUNNED))
		return
	forced_move(direction, user, 0)

/// The protean's core_dormancy affliction, if it is dormant.
/obj/item/rig/protean/proc/get_dormancy()
	RETURN_TYPE(/datum/affliction/core_dormancy)
	return myprotean?.body?.find_affliction(/datum/affliction/core_dormancy)

/// A click from the folded protean drives the selected module. TRUE if handled.
/obj/item/rig/protean/proc/host_click(mob/living/carbon/human/user, atom/A)
	if(offline || !selected_module || !ai_can_move_suit(user))
		return FALSE
	selected_module.engage(A, FALSE, user)
	if(ismob(A))
		user.setClickCooldown(user.get_attack_speed())
	return TRUE

/mob/living/carbon/human/ClickOn(atom/A, params)
	if(istype(loc, /obj/item/rig/protean))
		var/obj/item/rig/protean/prig = loc
		if(prig.myprotean == src && prig.host_click(src, A))
			return
	return ..()

/obj/item/rig/protean/check_suit_access(mob/living/user)
	if(user == myprotean)
		return TRUE
	return ..()

/obj/item/rig/protean/digest_act(atom/movable/item_storage = null)
	return FALSE

/// An explosion on the cluster is an explosion on the protean's mass: it goes
/// through the protean's injure(), aimed at the core, like every other hit on
/// the cluster (take_damage()). The cluster's own integrity never moves. An
/// orphaned cluster is just an object.
/obj/item/rig/protean/ex_act(severity)
	if(!myprotean || QDELETED(src))
		return ..()
	var/band = round(severity)
	var/static/list/blast_blunt = list(120, 60, 25)
	var/static/list/blast_burn = list(60, 30, 10)
	if(band < 1 || band > length(blast_blunt))
		return
	var/taken = myprotean.injure(INJURY_BLUNT, blast_blunt[band], BP_TORSO, src)
	taken += myprotean.injure(INJURY_BURN, blast_burn[band], BP_TORSO, src)
	log_attack("PROTEAN RIG: [src] caught a severity [band] explosion; [key_name(myprotean)] took [taken].")
	return taken

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The rig becomes that protean's control cluster.
/obj/item/rig/protean/proc/bind_protean(mob/living/carbon/human/P)
	if(!istype(P))
		return
	var/datum/forms/protean/F = P.get_protean_forms()
	if(!F)
		if(P.character_forms)
			log_game("FORMS: [key_name(P)] had [P.character_forms.type] replaced by protean forms for a new control cluster.")
			own_clear(P, nameof(P.character_forms), OWN_DELETE)
		F = P.add_forms(/datum/forms/protean)
	if(F.rig && F.rig != src)
		rel_clear(F.rig, nameof(/obj/item/rig/protean::myprotean))
	rel_set(F, nameof(F.rig), src)
	if(P.get_equipped_item(SLOT_ID_BACK))
		after(src, 0.3 SECONDS, PROC_REF(AssimilateBag), with = list(P, 1, P.get_equipped_item(SLOT_ID_BACK)))
	else
		to_chat(P, span_notice("You should have spawned with a backpack to assimilate into your RIG. Try clicking it with a backpack."))

// the protean core spills out; a dormant one repairs on the body.
/obj/item/rig/protean/on_destroy(force)
	stop_soaking()
	if(myprotean)
		var/datum/forms/protean/F = myprotean.get_protean_forms()
		if(myprotean.loc == src)
			myprotean.forceMove(drop_location())
		// A dormant core with no cluster left is repaired on the protean itself.
		if(F?.is_dormant())
			log_game("NANOFORM: [key_name(myprotean)]'s control cluster was destroyed during dormancy; repairs continue on the body at [AREACOORD(myprotean)].")
			myprotean.visible_message(span_warning("[myprotean]'s core spills out of the ruined control cluster.")) // ALLOW(decl): message from the protean, only while dormant
	..()

/obj/item/rig/proc/AssimilateBag(mob/living/carbon/human/P, spawned, obj/item/storage/backpack/B)
	if(spawned && !P)
		return
	if(istype(B,/obj/item/storage/backpack))
		if(spawned)
			B = P.get_equipped_item(SLOT_ID_BACK)
		if(QDELETED(B)) // for mannequins or such
			return
		// Off the back (spawned) or out of the hand, into the rig.
		if(!move_into(src, nameof(src.rig_storage), B, spawned ? null : P))
			return
		to_chat(P, span_notice("[B] has been integrated into the [src]."))
		if(spawned)	//This feels very dumb to have a second if but I'm lazy
			P.equip_to_slot_if_possible(src, SLOT_ID_BACK)
		src.Moved()
	else
		to_chat(P,span_warning("Your rigsuit can only assimilate a backpack into itself. If you are seeing this message, and you do not have a rigsuit, tell a coder."))

/// Old verb "Remove Stored Bag".
/obj/item/rig/protean/proc/protean_removebag_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(rig_storage)
		var/obj/item/storage/backpack/removed_bag = rel_take(src, nameof(rig_storage))
		user.put_in_hands(removed_bag)
	else
		to_chat(user, "This Rig does not have a bag installed. Use a bag on it to install one.")

CAPABILITIES(/obj/item/rig/protean)
	op("protean_rig_hand", hand(), ungated(), then(PROC_REF(protean_rig_hand)))
	op("protean_rig_item", item(/obj/item), then(PROC_REF(protean_rig_item)))
	op("protean_removebag_verb", menu(), label("Remove Stored Bag"), needs(carried()), then(PROC_REF(protean_removebag_verb)))
	op("protean_removerig_verb", menu(), label("Remove Assimilated Rig"), needs(carried()), then(PROC_REF(protean_removerig_verb)))
	interface(null, window_var = nameof(interface_path), state = nameof(GLOB.tgui_always_state))
	without("ui_open")
	ui_shape(cooling = num(), sealing = any, emagged = num(), coverlock = num(), interfacelock = num(), aicontrol = num(), aioverride = num(), securitycheck = num(), malf = num(), primarysystem = schema_text(), ai = bool(), sealed = bool(), helmet = schema_text(), gauntlets = schema_text(), boots = schema_text(), chest = schema_text(), helmetDeployed = bool(), gauntletsDeployed = bool(), bootsDeployed = bool(), chestDeployed = bool(), charge = num(), maxcharge = num(), chargestatus = num(), modules = list_of())
	drag_onto(PROC_REF(mousedrop_input))
	param(nameof(myprotean), pos = 1, apply = PROC_REF(bind_protean))

/// Old attack_hand: open the bag when worn; otherwise close it for onlookers, then the usual touch
/// (the old ..(), which used to run before the closing).
/obj/item/rig/protean/proc/protean_rig_hand(datum/act/op/A)
	var/mob/user = A.actor
	src.add_fingerprint(user)
	if (src.loc == user)
		if(rig_storage)
			src.rig_storage.open(user)
		return TRUE
	for(var/mob/M in range(1))
		if (M.s_active == src)
			src.rig_storage.close(M)
	return OP_DECLINE

/obj/item/clothing/head/helmet/space/rig/protean
	name = "mass"
	desc = "A helmet-shaped clump of nanomachines."
	light_overlay = "should not use a light overlay"
	sprite_sheets = list(
		SPECIES_PROTEAN			 = 'icons/mob/head.dmi',
		SPECIES_HUMAN			 = 'icons/mob/head.dmi',
		SPECIES_TAJARAN 		 = 'icons/mob/species/tajaran/helmet.dmi',
		SPECIES_SKRELL 			 = 'icons/mob/species/skrell/helmet.dmi',
		SPECIES_UNATHI 			 = 'icons/mob/species/unathi/helmet.dmi',
		SPECIES_XENOHYBRID		 = 'icons/mob/species/unathi/helmet.dmi',
		SPECIES_AKULA 			 = 'icons/mob/species/akula/helmet.dmi',
		SPECIES_SERGAL			 = 'icons/mob/species/sergal/helmet.dmi',
		SPECIES_NEVREAN			 = 'icons/mob/species/sergal/helmet.dmi',
		SPECIES_VULPKANIN 		 = 'icons/mob/species/vulpkanin/helmet.dmi',
		SPECIES_ZORREN_HIGH 	 = 'icons/mob/species/fox/helmet.dmi',
		SPECIES_FENNEC 			 = 'icons/mob/species/vulpkanin/helmet.dmi',
		SPECIES_PROMETHEAN		 = 'icons/mob/species/skrell/helmet.dmi',
		SPECIES_TESHARI 		 = 'icons/mob/species/teshari/helmet.dmi',
		SPECIES_VASILISSAN		 = 'icons/mob/species/skrell/helmet.dmi',
		SPECIES_VOX				 = 'icons/mob/species/vox/head.dmi',
		SPECIES_XENOMORPH_HYBRID = 'icons/mob/species/xenomorph_hybrid/helmet.dmi',
		SPECIES_SHADEKIN		 = 'icons/mob/head.dmi',
		)

	sprite_sheets_obj = list(
		SPECIES_PROTEAN			 = 'icons/mob/head.dmi',
		SPECIES_HUMAN			 = 'icons/mob/head.dmi',
		SPECIES_TAJARAN 		 = 'icons/mob/head.dmi',
		SPECIES_SKRELL 			 = 'icons/mob/head.dmi',
		SPECIES_UNATHI 			 = 'icons/mob/head.dmi',
		SPECIES_XENOHYBRID		 = 'icons/mob/head.dmi',
		SPECIES_AKULA 			 = 'icons/mob/head.dmi',
		SPECIES_SERGAL			 = 'icons/mob/head.dmi',
		SPECIES_NEVREAN			 = 'icons/mob/head.dmi',
		SPECIES_VULPKANIN 		 = 'icons/mob/head.dmi',
		SPECIES_ZORREN_HIGH 	 = 'icons/mob/head.dmi',
		SPECIES_FENNEC 			 = 'icons/mob/head.dmi',
		SPECIES_PROMETHEAN		 = 'icons/mob/head.dmi',
		SPECIES_TESHARI 		 = 'icons/mob/head.dmi',
		SPECIES_VASILISSAN		 = 'icons/mob/head.dmi',
		SPECIES_VOX				 = 'icons/mob/head.dmi',
		SPECIES_XENOMORPH_HYBRID = 'icons/mob/head.dmi',
		SPECIES_SHADEKIN		 = 'icons/mob/head.dmi',
		)
	icon = 'icons/inventory/head/item.dmi'
	default_worn_icon = 'icons/mob/head.dmi'
	icon_state = "nanomachine_rig"

TYPE_TABLE(/obj/item/clothing/head/helmet/space/rig/protean, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_PROTEAN, SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_XENOMORPH_HYBRID, SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW))))

/obj/item/clothing/gloves/gauntlets/rig/protean
	name = "mass"
	desc = "Glove-shaped clusters of nanomachines."
	siemens_coefficient= 0
	sprite_sheets = list(
		SPECIES_PROTEAN			 = 'icons/mob/hands.dmi',
		SPECIES_HUMAN			 = 'icons/mob/hands.dmi',
		SPECIES_TAJARAN 		 = 'icons/mob/hands.dmi',
		SPECIES_SKRELL 			 = 'icons/mob/hands.dmi',
		SPECIES_UNATHI 			 = 'icons/mob/hands.dmi',
		SPECIES_XENOHYBRID		 = 'icons/mob/hands.dmi',
		SPECIES_AKULA 			 = 'icons/mob/hands.dmi',
		SPECIES_SERGAL			 = 'icons/mob/hands.dmi',
		SPECIES_NEVREAN			 = 'icons/mob/hands.dmi',
		SPECIES_VULPKANIN		 = 'icons/mob/hands.dmi',
		SPECIES_ZORREN_HIGH 	 = 'icons/mob/hands.dmi',
		SPECIES_FENNEC			 = 'icons/mob/hands.dmi',
		SPECIES_PROMETHEAN		 = 'icons/mob/hands.dmi',
		SPECIES_TESHARI 		 = 'icons/mob/species/teshari/hands.dmi',
		SPECIES_VASILISSAN		 = 'icons/mob/hands.dmi',
		SPECIES_VOX				 = 'icons/mob/species/vox/gloves.dmi',
		SPECIES_XENOMORPH_HYBRID = 'icons/mob/species/xenomorph_hybrid/gloves.dmi',
		SPECIES_SHADEKIN		 = 'icons/mob/hands.dmi'
		)

	sprite_sheets_obj = list(
		SPECIES_HUMAN			 = 'icons/mob/hands.dmi',
		SPECIES_TAJARAN 		 = 'icons/mob/hands.dmi',
		SPECIES_SKRELL 			 = 'icons/mob/hands.dmi',
		SPECIES_UNATHI 			 = 'icons/mob/hands.dmi',
		SPECIES_XENOHYBRID		 = 'icons/mob/hands.dmi',
		SPECIES_AKULA 			 = 'icons/mob/hands.dmi',
		SPECIES_SERGAL			 = 'icons/mob/hands.dmi',
		SPECIES_NEVREAN			 = 'icons/mob/hands.dmi',
		SPECIES_VULPKANIN 		 = 'icons/mob/hands.dmi',
		SPECIES_ZORREN_HIGH 	 = 'icons/mob/hands.dmi',
		SPECIES_FENNEC 			 = 'icons/mob/hands.dmi',
		SPECIES_PROMETHEAN		 = 'icons/mob/hands.dmi',
		SPECIES_TESHARI 		 = 'icons/mob/hands.dmi',
		SPECIES_VASILISSAN		 = 'icons/mob/hands.dmi',
		SPECIES_VOX				 = 'icons/mob/hands.dmi',
		SPECIES_XENOMORPH_HYBRID = 'icons/mob/hands.dmi',
		SPECIES_SHADEKIN		 = 'icons/mob/hands.dmi'
		)
	icon = 'icons/inventory/hands/item.dmi'
	default_worn_icon = 'icons/mob/hands.dmi'
	icon_state = "nanomachine_rig"

TYPE_TABLE(/obj/item/clothing/gloves/gauntlets/rig/protean, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_PROTEAN, SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_XENOMORPH_HYBRID, SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW))))

/obj/item/clothing/shoes/magboots/rig/protean
	name = "mass"
	desc = "Boot-shaped clusters of nanomachines."
	sprite_sheets = list(
		SPECIES_TESHARI 		 = 'icons/mob/species/teshari/feet.dmi',
		SPECIES_VOX				 = 'icons/mob/species/vox/shoes.dmi',
		SPECIES_XENOMORPH_HYBRID = 'icons/mob/species/xenomorph_hybrid/shoes.dmi'
		)
	sprite_sheets_obj = list()
	icon = 'icons/inventory/feet/item.dmi'
	default_worn_icon = 'icons/mob/feet.dmi'
	icon_state = "nanomachine_rig"

TYPE_TABLE(/obj/item/clothing/shoes/magboots/rig/protean, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_PROTEAN, SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_XENOMORPH_HYBRID, SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW))))

/obj/item/clothing/suit/space/rig/protean
	name = "mass"
	desc = "A body-hugging mass of nanomachines."
	can_breach = 0
	sprite_sheets = list(
		SPECIES_TESHARI 		 = 'icons/mob/species/teshari/suit.dmi',
		SPECIES_VOX				 = 'icons/mob/species/vox/suit.dmi',
		SPECIES_XENOMORPH_HYBRID = 'icons/mob/species/xenomorph_hybrid/suit.dmi'
		)

	sprite_sheets_obj = list()
	icon = 'icons/inventory/suit/item.dmi'
	default_worn_icon = 'icons/mob/spacesuit.dmi'
	icon_state = "nanomachine_rig"

//Copy pasted most of this proc from base because I don't feel like rewriting the base proc with a shit load of exceptions

TYPE_TABLE(/obj/item/clothing/suit/space/rig/protean, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_PROTEAN, SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_XENOHYBRID, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_XENOMORPH_HYBRID, SPECIES_SHADEKIN, SPECIES_SHADEKIN_CREW))))

TYPE_TABLE(/obj/item/clothing/suit/space/rig/protean, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS, POCKET_EXPLO, /obj/item/storage/backpack))))
/// Old attackby. It never fell through to the rig's own.
/obj/item/rig/protean/proc/protean_rig_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(!istype(user))
		return OP_PASS
	var/datum/affliction/core_dormancy/dormancy = get_dormancy()
	if(dormancy)
		dormancy.repair_with(W, user, src)
		return OP_PASS
	if(istype(W,/obj/item/rig))
		if(!assimilated_rig)
			AssimilateRig(user,W)
	if(istype(W,/obj/item/tank)) //Todo, some kind of check for suits without integrated air supplies.
		if(air_supply)
			to_chat(user, "\The [src] already has a tank installed.")
			return OP_PASS


		if(!move_into(src, nameof(src.air_supply), W, user))
			return OP_PASS
		to_chat(user, "You slot [W] into [src] and tighten the connecting valve.")
		return OP_PASS

		// Check if this is a hardsuit upgrade or a modification.
	else if(istype(W,/obj/item/rig_module))
		if(length(installed_modules))
			for(var/obj/item/rig_module/installed_mod in installed_modules)
				if(!installed_mod.redundant && istype(installed_mod,W))
					to_chat(user, "The hardsuit already has a module of that class installed.")
					return TRUE

		var/obj/item/rig_module/mod = W
		to_chat(user, "You begin installing \the [mod] into \the [src].")
		task_start(/datum/task/timed/protean_attackby_protean, user, src, receiver = src, W = W, mod = mod)
		return TRUE
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.accepts_item(W,user)) //Item is handled in this proc
			return OP_PASS
	if(rig_storage)
		var/obj/item/storage/backpack = rig_storage
		backpack.insert_item(W, user)
	else
		if(istype(W,/obj/item/storage/backpack))
			AssimilateBag(user,0,W)
	return OP_PASS

/datum/task/timed/protean_attackby_protean
	duration = 4 SECONDS
	complete_proc = /obj/item/rig/protean/proc/attackby_protean_done
	var/obj/item/W
	var/obj/item/rig_module/mod

/obj/item/rig/protean/proc/attackby_protean_done(datum/task/timed/protean_attackby_protean/task)
	var/obj/item/W = task.W
	var/mob/living/user = task.actor
	var/obj/item/rig_module/mod = task.mod
	if(!user || !W)
		return
	if(!user.unEquip(mod))
		return
	to_chat(user, "You install \the [mod] into \the [src].")
	mod.forceMove(src)
	mod.installed(src) // pair: installed_modules gains mod
	update_icon()
	return 1

/obj/item/rig/protean/wrench_act(mob/living/user, obj/item/tool)
	if(get_dormancy())
		return ITEM_INTERACT_BLOCKING
	if(!air_supply)
		to_chat(user, "There is no tank to remove.")
		return ITEM_INTERACT_BLOCKING
	var/obj/item/tank/removed_tank = rel_take(src, nameof(air_supply))
	if(user.get_equipped_item(SLOT_ID_HAND_R) && user.get_equipped_item(SLOT_ID_HAND_L))
		removed_tank.forceMove(get_turf(user))
	else
		user.put_in_hands(removed_tank)
	to_chat(user, "You detach and remove \the [removed_tank].")
	return ITEM_INTERACT_SUCCESS

/obj/item/rig/protean/screwdriver_act(mob/living/user, obj/item/tool)
	var/datum/affliction/core_dormancy/dormancy = get_dormancy()
	if(dormancy)
		if(dormancy.revival_step != DORMANCY_SEALED)
			return ITEM_INTERACT_BLOCKING
		dormancy.repair_with(tool, user, src)
		return ITEM_INTERACT_SUCCESS
	else
		var/list/possible_removals = list()
		for(var/obj/item/rig_module/module in installed_modules)
			if(module.permanent)
				continue
			possible_removals[module.name] = module

		if(!possible_removals.len)
			to_chat(user, "There are no installed modules to remove.")
			return ITEM_INTERACT_BLOCKING

		open_request(src, /datum/prompt/choice/protean_rig_module, PROC_REF(module_removal_chosen), answerer = user, choices = possible_removals)
		return ITEM_INTERACT_SUCCESS

/// Re-checked on the answer: next to the rig, able to act, and the module is still installed.
/datum/prompt/choice/protean_rig_module
	title = "Removal Choice"
	question = "Which module would you like to remove?"
	timeout = 0
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/prompt/choice/protean_rig_module/recheck_extra()
	if(isnull(value))
		return
	var/obj/item/rig/protean/rig = owner
	return (choices[value] in rig.installed_modules) ? null : "not installed"

/obj/item/rig/protean/proc/module_removal_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return module_removal_apply(A)

/obj/item/rig/protean/proc/module_removal_apply(datum/act/request/A)
	var/datum/prompt/choice/protean_rig_module/ask = A.answer
	var/mob/living/user = ask.answerer
	var/obj/item/rig_module/removed = ask.choices[ask.value]
	to_chat(user, "You detach \the [removed] from \the [src].")
	removed.forceMove(get_turf(src))
	removed.removed() // pair: installed_modules loses it
	update_icon()

/// Revival of a dormant core, one step per tool. Each step is a treatment
/// mechanism the core_dormancy affliction answers to.
/// The cluster has no module damage pool of its own: see take_damage() and
/// soak_wearer_injury(), which put every hit on the protean's body.
/obj/item/rig/protean/take_hit(damage, source, is_emp=0)
	return

/// A hit on the cluster itself is a hit on the protean: its mass is the
/// protean's body, so the damage goes through the protean's injure(), aimed at
/// the core (the torso), and the cluster's own integrity never moves. An
/// orphaned cluster is just an object.
/obj/item/rig/protean/take_damage(damage_amount, damage_type = BRUTE, damage_flag = "", sound_effect = TRUE, attack_dir, armour_penetration = 0)
	if(!myprotean || QDELETED(src))
		return ..()
	if(sound_effect)
		play_attack_sound(damage_amount, damage_type, damage_flag)
	var/kind
	switch(damage_type)
		if(BRUTE)
			kind = (damage_flag == BULLET) ? INJURY_PIERCE : INJURY_BLUNT
		if(BURN)
			kind = INJURY_BURN
	if(!kind)
		return 0
	. = myprotean.injure(kind, damage_amount, BP_TORSO, src, armour_penetration)
	log_attack("PROTEAN RIG: [src] took [damage_amount] [damage_type] ([damage_flag]); [key_name(myprotean)] took [.].")

/// Worn by someone else, the cluster's armour is the protean's own mass: what
/// it stops, the protean takes. The wearer's own armour stage still applies.
/obj/item/rig/protean/proc/start_soaking(mob/living/carbon/human/M)
	if(soaking_wearer == M)
		return
	stop_soaking()
	if(!istype(M) || M == myprotean)
		return
	rel_set(src, nameof(soaking_wearer), M)
	observe(M, /datum/act/injure, src, adjusts_with(PROC_REF(soak_wearer_injury)))

/obj/item/rig/protean/proc/stop_soaking()
	if(!soaking_wearer)
		return
	unobserve(soaking_wearer, /datum/act/injure, src)
	rel_clear(src, nameof(soaking_wearer))

/obj/item/rig/protean/proc/soak_wearer_injury(datum/act/injure/hit)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/carbon/human/source = hit.target
	var/kind = hit.kind
	var/zone = hit.zone
	var/atom/hit_source = hit.cause
	var/flags = hit.flags
	if(!myprotean || inert || !(flags & INJURE_ARMORED))
		return
	var/armor_key = injury_armor_key(kind)
	if(!armor_key)
		return
	var/obj/item/organ/external/E = istext(zone) ? source.get_organ(check_zone(zone)) : null
	var/obj/item/clothing/piece = covering_piece(source, E)
	var/armor_value = piece ? piece.get_armor().value(armor_key) : 0
	if(!armor_value)
		return
	var/soaked = hit.amount * clamp(armor_value, 0, 100) / 100
	if(soaked <= 0)
		return
	myprotean.injure(kind, soaked, E?.organ_tag, hit_source, 0, null, INJURE_SILENT)
	log_attack("PROTEAN RIG: [key_name(myprotean)] soaked [soaked] [injury_kind_name(kind)] for [key_name(source)].")

/// The deployed piece of this cluster covering `E` on `M` (the chest piece
/// for untargeted hits), or null.
/obj/item/rig/protean/proc/covering_piece(mob/living/carbon/human/M, obj/item/organ/external/E)
	for(var/obj/item/clothing/piece in list(chest, helmet, gloves, boots))
		if(piece.loc != M)
			continue
		if(!E || (piece.body_parts_covered & E.body_part))
			return piece
	return null

/obj/item/rig/protean/dropped(mob/user, equipping, slot)
	stop_soaking()
	return ..()


/// The swarm feeds its cluster's cell from its own nutrition.
/obj/item/rig/protean/proc/recharge_from(mob/living/P)
	if(!cell || inert || cell.charge >= cell.maxcharge || P.nutrition <= PROTEAN_RIG_RECHARGE_NUTRITION_FLOOR)
		return 0
	var/stored = add_power(ROBOT_CELL_JOULES(PROTEAN_RIG_RECHARGE_UNITS), P)
	if(stored > 0)
		P.adjust_nutrition(-stored * CELLRATE * PROTEAN_RIG_NUTRITION_PER_UNIT)
	return stored

// --- Dormancy -------------------------------------------------------------------------------

/// The protean has gone dormant: the cluster is inert. It protects nobody,
/// unseals, drops every module and weighs its wearer down.
/obj/item/rig/protean/proc/go_inert()
	if(inert)
		return
	inert = TRUE
	for(var/obj/item/rig_module/module in installed_modules)
		if(!module.active)
			continue
		module.deactivate()
		// Unworn modules refuse a polite shutdown; an inert cluster cuts them anyway.
		module.active = FALSE
	reset()
	set_armor(dq_armor_none())
	for(var/obj/item/piece in list(gloves, helmet, boots, chest))
		piece.set_armor(dq_armor_none())
	slowdown = PROTEAN_RIG_INERT_SLOWDOWN
	offline_slowdown = PROTEAN_RIG_INERT_SLOWDOWN
	wearer()?.update_inv_back()
	wearer()?.worn_protection_changed()
	log_game("PROTEAN RIG: [src] of [key_name(myprotean)] went inert at [AREACOORD(src)].")

/// The protean has reconstituted: the cluster is its own again.
/obj/item/rig/protean/proc/wake()
	if(!inert)
		return
	inert = FALSE
	var/obj/item/rig/R = assimilated_rig
	var/datum/armor/restored = istype(R) ? R.get_armor() : initial_armor()
	set_armor(restored)
	for(var/obj/item/piece in list(gloves, helmet, boots, chest))
		piece.set_armor(restored)
	wearer()?.worn_protection_changed()
	if(istype(R))
		slowdown = initial(R.slowdown) * 0.5
	else
		slowdown = initial(slowdown)
	offline_slowdown = slowdown
	log_game("PROTEAN RIG: [src] of [key_name(myprotean)] woke at [AREACOORD(src)].")

/// The unconfigured cluster's armour.
/obj/item/rig/protean/proc/initial_armor()
	return dq_armor(list(BIO = 100, ARMOR_RAD = 100))

/// An inert cluster runs nothing: no seals, no modules.
/obj/item/rig/protean/check_power_cost(mob/living/user, cost, use_unconcious, obj/item/rig_module/mod, user_is_ai)
	if(inert)
		if(user)
			to_chat(user, span_warning("\The [src] is inert and unresponsive."))
		return 0
	return ..()

/obj/item/rig/protean/cut_suit()
	return	//nope

/obj/item/rig/protean/force_rest(mob/user)
	wearer().lay_down()
	to_chat(user, span_notice("\The [wearer()] is now [wearer().resting ? "resting" : "getting up"]."))

/// The cluster's cell. It starts full and is recharged only through the
/// cluster's power ledger (recharge_from()).
/obj/item/cell/protean
	name = "Protean power cell"
	desc = "Something terrible must have happened if you're managing to see this."
	maxcharge = 10000
	charge_amount = 100

/obj/item/cell/protean/Initialize(mapload)
	. = ..()
	set_charge(maxcharge)

/obj/item/rig/protean/equipped(mob/living/carbon/human/M)
	..()
	if(get_dormancy())
		unremovable = FALSE
	else
		unremovable = TRUE //It's like glue! If you put them on your back, YOU can't take them off!
	if(istype(M) && (M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src))
		start_soaking(M)

/obj/item/rig/protean/ai_can_move_suit(mob/user, check_user_module = 0, check_for_ai = 0)
	if(check_for_ai)
		return 0	//We don't do that here.
	if(offline || !cell || !cell.charge || locked_down)
		if(user)
			to_chat(user, span_warning("Your host rig is unpowered and unresponsive."))
		return 0
	if(!wearer() || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		if(user)
			to_chat(user, span_warning("Your host rig is not being worn."))
		return 0
	return 1

/obj/item/rig/protean/toggle_seals(mob/living/carbon/human/M, instant = TRUE)
	M = src.wearer()
	..()

/obj/item/rig/protean/toggle_cooling(mob/user)
	user = src.wearer()
	..()

/obj/item/rig/protean/toggle_piece(piece, mob/living/carbon/human/H, deploy_mode, forced)
	H = src.wearer()
	..()

/obj/item/rig/protean/get_description_interaction()
	var/list/results = list()
	var/datum/affliction/core_dormancy/dormancy = get_dormancy()
	if(dormancy)
		results += dormancy.revival_instructions()
	return results

//Effectively a round about way of letting a Protean wear other rigs.
/obj/item/rig/protean/proc/AssimilateRig(mob/user, obj/item/rig/R)
	if(!can_assimilate_rig)
		to_chat(user, span_warning("You can not place a rig into \the [src]"))
		return
	if(!R || assimilated_rig)
		return
	if(istype(R, /obj/item/rig/protean))
		to_chat(user, span_warning("The world is not ready for such a technological singularity."))
		return
	to_chat(user, span_notice("You assimilate the [R] into the [src]. Mimicking its stats and appearance."))

	rigsuit_max_pressure = R.rigsuit_max_pressure
	for(var/obj/item/piece in list(gloves,helmet,boots,chest))
		piece.set_armor(R.get_armor())
		piece.max_pressure_protection = R.rigsuit_max_pressure
		piece.max_heat_protection_temperature = R.max_heat_protection_temperature
	wearer()?.worn_protection_changed()
	//I dislike this piece of code, but not every rig has the full set of parts
	if(R.gloves)
		gloves.sprite_sheets = R.gloves.sprite_sheets.Copy()
		gloves.sprite_sheets_obj = R.gloves.sprite_sheets_obj.Copy()
		gloves.icon = R.gloves.icon
		gloves.icon_state = R.gloves.icon_state
		gloves.default_worn_icon = R.gloves.default_worn_icon
	if(R.helmet)
		helmet.sprite_sheets = R.helmet.sprite_sheets.Copy()
		helmet.sprite_sheets_obj = R.helmet.sprite_sheets_obj.Copy()
		helmet.icon = R.helmet.icon
		helmet.icon_state = R.helmet.icon_state
		helmet.default_worn_icon = R.helmet.default_worn_icon
	if(R.boots)
		boots.sprite_sheets = R.boots.sprite_sheets.Copy()
		boots.sprite_sheets_obj = R.boots.sprite_sheets_obj.Copy()
		boots.icon = R.boots.icon
		boots.icon_state = R.boots.icon_state
		boots.default_worn_icon = R.boots.default_worn_icon
	if(R.chest)
		chest.sprite_sheets = R.chest.sprite_sheets.Copy()
		chest.sprite_sheets_obj = R.chest.sprite_sheets_obj.Copy()
		chest.icon = R.chest.icon
		chest.icon_state = R.chest.icon_state
		chest.default_worn_icon = R.chest.default_worn_icon

	suit_state = R.suit_state
	name = R.name
	icon = R.icon
	icon_state = R.icon_state
	user.drop_item(R)
	R.forceMove(src)
	assimilated_rig = R
	slowdown = (initial(R.slowdown) *0.5)
	offline_slowdown = slowdown

/// Old verb "Remove Assimilated Rig".
/obj/item/rig/protean/proc/protean_removerig_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(assimilated_rig)
		rigsuit_max_pressure = initial(rigsuit_max_pressure)
		for(var/obj/item/piece in list(gloves,helmet,boots,chest))
			piece.set_armor(get_armor())
			piece.max_pressure_protection = rigsuit_max_pressure
			piece.max_heat_protection_temperature = max_heat_protection_temperature
			piece.icon_state = src.icon_state
			piece.icon = initial(piece.icon)
			piece.default_worn_icon = initial(piece.default_worn_icon)

		//Byond at this time does not support initial() on lists
		//So we have to create a new rig, just so we can copy the lists we're after
		//If someone figures out a smarter way to do this, please tell me
		var/obj/item/rig/tempRig = new /obj/item/rig/protean()
		gloves.sprite_sheets = tempRig.gloves.sprite_sheets.Copy()
		gloves.sprite_sheets_obj = tempRig.gloves.sprite_sheets.Copy()
		helmet.sprite_sheets = tempRig.helmet.sprite_sheets.Copy()
		helmet.sprite_sheets_obj = tempRig.helmet.sprite_sheets.Copy()
		boots.sprite_sheets = tempRig.boots.sprite_sheets.Copy()
		boots.sprite_sheets_obj = tempRig.boots.sprite_sheets.Copy()
		chest.sprite_sheets = tempRig.chest.sprite_sheets.Copy()
		chest.sprite_sheets_obj = tempRig.chest.sprite_sheets.Copy()
		slowdown = initial(slowdown)
		name = tempRig.name
		icon = tempRig.icon // Reset the icon back to its original
		icon_state = tempRig.icon_state
		suit_state = icon_state
		offline_slowdown = initial(offline_slowdown)
		wearer()?.worn_protection_changed()
		user.put_in_hands(assimilated_rig)
		assimilated_rig = null
		spent(tempRig)
	else
		to_chat(user, "[src] has not assimilated a RIG. Use one on it to assimilate.")

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/rig/protean/proc/mousedrop_input(datum/act/input/A)
	if(!handle_inventory_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/rig/protean/proc/handle_inventory_drop(mob/user, obj/over_object)
	if(get_dormancy()) //We adjust our unremovable upon being attempted to be moved via checking if we are dead or not.
		unremovable = FALSE
	else
		unremovable = TRUE

	if(unremovable)
		return TRUE

	if (isliving(user) || isobserver(user))

		if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech. why?
			return TRUE

		if (!( istype(over_object, /atom/movable/screen) ))
			return FALSE

		if (!(src.loc == user) || (src.loc && src.loc.loc == user))
			return TRUE

		if (( user.restrained() ) || ( user.stat ))
			return TRUE

		if ((src.loc == user) && !(istype(over_object, /atom/movable/screen)) && !user.unEquip(src))
			return TRUE

		switch(over_object.name)
			if("r_hand")
				user.unEquip(src)
				user.put_in_r_hand(src)
			if("l_hand")
				user.unEquip(src)
				user.put_in_l_hand(src)
		src.add_fingerprint(user)
	return TRUE

// Teardown reads both before letting go (the core spills out, soaking stops).
