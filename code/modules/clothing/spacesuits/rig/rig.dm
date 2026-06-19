#define ONLY_DEPLOY 1
#define ONLY_RETRACT 2
#define SEAL_DELAY 30

/*
 * Defines the behavior of hardsuits/rigs/power armour.
 */

/obj/item/rig
	name = "hardsuit control module"
	icon = 'icons/obj/rig_modules.dmi'
	desc = "A back-mounted hardsuit deployment and control mechanism."
	flags = PHORONGUARD
	slot_flags = SLOT_BACK
	req_one_access = list()
	req_access = list()
	w_class = ITEMSIZE_HUGE
	actions_types = list(/datum/action/item_action/toggle_heatsink)

	// These values are passed on to all component pieces.
	armor = list(melee = 40, bullet = 5, laser = 20,energy = 5, bomb = 35, bio = 100, rad = 20)
	min_cold_protection_temperature = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE
	siemens_coefficient = 0.2
	permeability_coefficient = 0.1
	unacidable = TRUE
	preserve_item = 1

	var/default_mob_icon = 'icons/mob/rig_back.dmi'

	var/suit_state //The string used for the suit's icon_state.

	var/interface_path = "RIGSuit"
	var/ai_interface_path = "RIGSuit"
	var/interface_title = "Hardsuit Controller"
	var/interface_intro = "NT"
	var/wearer_move_delay //Used for AI moving.
	var/ai_controlled_move_delay = 10

	// Keeps track of what this rig should spawn with.
	var/suit_type = "hardsuit"
	var/list/initial_modules
	var/chest_type = /obj/item/clothing/suit/space/rig
	var/helm_type =  /obj/item/clothing/head/helmet/space/rig
	var/boot_type =  /obj/item/clothing/shoes/magboots/rig
	var/glove_type = /obj/item/clothing/gloves/gauntlets/rig
	var/cell_type =  /obj/item/cell/high
	var/air_type =   /obj/item/tank/oxygen


	//Component/device holders.
	var/obj/item/tank/air_supply                       // Air tank, if any.
	var/obj/item/clothing/shoes/boots = null                  // Deployable boots, if any.
	var/obj/item/clothing/suit/space/rig/chest                // Deployable chestpiece, if any.
	var/obj/item/clothing/head/helmet/space/rig/helmet = null // Deployable helmet, if any.
	var/obj/item/clothing/gloves/gauntlets/rig/gloves = null  // Deployable gauntlets, if any.
	var/obj/item/cell/cell                             // Power supply, if any.
	var/obj/item/rig_module/selected_module = null            // Primary system (used with middle-click)
	var/obj/item/rig_module/vision/visor                      // Kinda shitty to have a var for a module, but saves time.
	var/obj/item/rig_module/voice/speech                      // As above.
	var/mob/living/carbon/human/wearer                        // The person currently wearing the rig.
	var/image/mob_icon                                        // Holder for on-mob icon.
	var/list/installed_modules = list()                       // Power consumption/use bookkeeping.

	// Cooling system vars.
	var/cooling_on = 0					//is it turned on?
	var/max_cooling = 15				// in degrees per second - probably don't need to mess with heat capacity here
	var/charge_consumption = 2			// charge per second at max_cooling		//more effective on a rig, because it's all built in already
	var/thermostat = T20C

	// Rig status vars.
	var/open = 0                                              // Access panel status.
	var/locked = 1                                            // Lock status.
	var/unremovable = FALSE											//If the rig can be removed or not. Used for protean rigs.
	var/subverted = 0
	var/interface_locked = 0
	var/control_overridden = 0
	var/ai_override_enabled = 0
	var/security_check_enabled = 1
	var/malfunctioning = 0
	var/malfunction_delay = 0
	var/electrified = 0
	var/locked_down = 0

	var/seal_delay = SEAL_DELAY
	var/sealing                                               // Keeps track of seal status independantly of canremove.
	var/offline = 1                                           // Should we be applying suit maluses?
	var/offline_slowdown = 1.5                                  // If the suit is deployed and unpowered, it sets slowdown to this.
	var/vision_restriction
	var/offline_vision_restriction = 1                        // 0 - none, 1 - welder vision, 2 - blind. Maybe move this to helmets.
	var/airtight = 1 //If set, will adjust AIRTIGHT flag and pressure protections on components. Otherwise it should leave them untouched.
	var/rigsuit_max_pressure = 10 * ONE_ATMOSPHERE			  // Max pressure the rig protects against when sealed
	var/rigsuit_min_pressure = 0							  // Min pressure the rig protects against when sealed

	var/emp_protection = 0
	item_flags = PHORONGUARD // add

	var/datum/effect/effect/system/spark_spread/spark_system
	var/datum/mini_hud/rig/minihud

	// Decomposed subsystems — see rig_power_system.dm and rig_component_registry.dm
	var/datum/rig_power_system/power_system
	var/datum/rig_component_registry/component_registry

	// Action button
	actions_types = list(/datum/action/item_action/hardsuit_interface)

	// Protean
	var/protean = 0
	var/obj/item/storage/backpack/rig_storage
	permeability_coefficient = 0  //Protect the squishies, after all this shit should be waterproof.
	resistance_flags = FIRE_PROOF | ACID_PROOF

/obj/item/rig/Initialize(mapload)
	. = ..()

	suit_state = icon_state
	item_state = icon_state
	set_wires(new /datum/wires/rig(src))

	if(!LAZYLEN(req_access) && !LAZYLEN(req_one_access))
		locked = 0

	spark_system = new()
	spark_system.set_up(5, 0, src)
	spark_system.attach(src)

	// Instantiate the decomposed subsystems.
	power_system = new /datum/rig_power_system(src)
	power_system.cooling_on              = cooling_on
	power_system.max_cooling             = max_cooling
	power_system.charge_consumption      = charge_consumption
	power_system.thermostat              = thermostat
	power_system.offline                 = offline
	power_system.offline_slowdown        = offline_slowdown
	power_system.offline_vision_restriction = offline_vision_restriction

	component_registry = new /datum/rig_component_registry(src)
	component_registry.initialize_pieces()

	update_icon(1)

/obj/item/rig/Destroy()
	// Delegate piece teardown to the component registry.
	if(component_registry)
		component_registry.destroy_pieces()
	QDEL_NULL(component_registry)
	QDEL_NULL(power_system)

	installed_modules = null
	STOP_PROCESSING(SSobj, src)
	qdel(wires)
	wires = null
	qdel(spark_system)
	spark_system = null
	return ..()

/obj/item/rig/MouseDrop(obj/over_object)
	if(unremovable)
		return
	..()

/obj/item/rig/examine(mob/user)
	. = ..()
	if(wearer)
		for(var/obj/item/piece in list(helmet,gloves,chest,boots))
			if(!piece || piece.loc != wearer)
				continue
			. += "[icon2html(piece, user.client)] \The [piece] [piece.gender == PLURAL ? "are" : "is"] deployed."

	if(src.loc == user)
		. += "The access panel is [locked? "locked" : "unlocked"]."
		. += "The maintenance panel is [open ? "open" : "closed"]."
		. += "Hardsuit systems are [offline ? span_warning("offline") : span_notice("online")]."
		. += "The cooling system is [cooling_on ? "active" : "inactive"]."

		if(open)
			. += "It's equipped with [english_list(installed_modules)]."

// We only care about processing when we're on a mob
/obj/item/rig/Moved(old_loc, direction, forced)
	if(ismob(loc))
		START_PROCESSING(SSobj, src)
	else
		STOP_PROCESSING(SSobj, src)
		QDEL_NULL(minihud) // Just in case we get removed some other way

	// If we've lost any parts, grab them back.
	var/mob/living/M
	for(var/obj/item/piece in list(gloves,boots,helmet,chest))
		if(piece.loc != src && !(wearer && piece.loc == wearer))
			if(isliving(piece.loc))
				M = piece.loc
				M.unEquip(piece)
			piece.forceMove(src)

/obj/item/rig/get_worn_icon_file(body_type,slot_name,default_icon,inhands)
	if(!inhands && (slot_name == slot_back_str || slot_name == slot_belt_str))
		if(body_type == SPECIES_TESHARI || body_type == SPECIES_WEREBEAST) //Until teshari get proper sprites for rigs, they can default to not having the sprite.
			return null //All other species are 'humanoid enough' to wear the default rig sprite.
		if(icon_override)
			return icon_override
		else if(mob_icon)
			return mob_icon

	return ..()

/obj/item/rig/proc/suit_is_deployed()
	if(!istype(wearer) || src.loc != wearer || (wearer.back != src && wearer.belt != src))
		return 0
	if(helm_type && !(helmet && wearer.head == helmet))
		return 0
	if(glove_type && !(gloves && wearer.gloves == gloves))
		return 0
	if(boot_type && !(boots && wearer.shoes == boots))
		return 0
	if(chest_type && !(chest && wearer.wear_suit == chest))
		return 0
	return 1

// Updates pressure protection
// Seal = 1 sets protection
// Seal = 0 unsets protection
/obj/item/rig/proc/update_airtight(obj/item/piece, seal = 0)
	if(seal == 1)
		piece.min_pressure_protection = rigsuit_min_pressure
		piece.max_pressure_protection = rigsuit_max_pressure
		piece.item_flags |= AIRTIGHT
	else
		piece.min_pressure_protection = null
		piece.max_pressure_protection = null
		piece.item_flags &= ~AIRTIGHT
	return


/obj/item/rig/proc/reset()
	offline = 2
	canremove = TRUE
	for(var/obj/item/piece in list(helmet,boots,gloves,chest))
		if(!piece) continue
		piece.icon_state = "[suit_state]"
		if(airtight)
			update_airtight(piece, 0) // Unseal
	update_icon(1)

/obj/item/rig/proc/cut_suit()
	offline = 2
	canremove = TRUE
	toggle_piece("helmet", loc, ONLY_RETRACT, TRUE)
	toggle_piece("gauntlets", loc, ONLY_RETRACT, TRUE)
	toggle_piece("boots", loc, ONLY_RETRACT, TRUE)
	toggle_piece("chest", loc, ONLY_RETRACT, TRUE)
	update_icon(1)

/obj/item/rig/proc/toggle_seals(mob/living/carbon/human/M, instant, destructive)

	if(sealing) return

	if(!check_power_cost(M))
		return 0

	//NOTE: DESTRUCTIVE SHOULD ONLY BE CALLED ONCE (DURING THE INITIAL DEPLOYMENT)
	//DESTRUCTIVE WILL DELETE ANY CLOTHING THAT WOULD OTHERWISE BE BLOCKING IT.
	//IF DESTRUCTIVE IS CALLED WHILE THE RIG IS ALREADY DEPLOYED, THE RIG WILL DELETE ITSELF.
	deploy(M,destructive)

	var/seal_target = !canremove
	var/failed_to_seal

	var/atom/movable/screen/rig_booting/booting_L = new
	var/atom/movable/screen/rig_booting/booting_R = new

	if(!seal_target)
		booting_L.icon_state = "boot_left"
		booting_R.icon_state = "boot_load"
		animate(booting_L, alpha=230, time=30, easing=SINE_EASING)
		animate(booting_R, alpha=200, time=20, easing=SINE_EASING)
		M.client?.screen += booting_L
		M.client?.screen += booting_R

	canremove = FALSE // No removing the suit while unsealing.
	sealing = 1

	if(!seal_target && !suit_is_deployed())
		M.visible_message(span_danger("[M]'s suit flashes an error light."),span_danger("Your suit flashes an error light. It can't function properly without being fully deployed."))
		playsound(src, 'sound/machines/rig/rigerror.ogg', 20, FALSE)
		failed_to_seal = 1

	if(!failed_to_seal)

		if(!instant)
			M.visible_message(span_notice("[M]'s suit emits a quiet hum as it begins to adjust its seals."),span_notice("With a quiet hum, the suit begins running checks and adjusting components."))
			if(seal_delay && !do_after(M, seal_delay, target = src))
				if(M)
					to_chat(M, span_warning("You must remain still while the suit is adjusting the components."))
					playsound(src, 'sound/machines/rig/rigerror.ogg', 20, FALSE)
				failed_to_seal = 1
		if(!M)
			failed_to_seal = 1
		else
			for(var/list/piece_data in list(list(M.shoes,boots,"boots",boot_type),list(M.gloves,gloves,"gloves",glove_type),list(M.head,helmet,"helmet",helm_type),list(M.wear_suit,chest,"chest",chest_type)))

				var/obj/item/piece = piece_data[1]
				var/obj/item/compare_piece = piece_data[2]
				var/msg_type = piece_data[3]
				var/piece_type = piece_data[4]

				if(!piece || !piece_type)
					continue

				if(!istype(M) || !istype(piece) || !istype(compare_piece) || !msg_type)
					if(M)
						to_chat(M, span_warning("You must remain still while the suit is adjusting the components."))
					failed_to_seal = 1
					break

				if(!failed_to_seal && (M.back == src || M.belt == src) && piece == compare_piece)

					if(seal_delay && !instant && !do_after(M, seal_delay, target = src))
						failed_to_seal = 1

					piece.icon_state = "[suit_state][!seal_target ? "_sealed" : ""]"
					switch(msg_type)
						if("boots")
							to_chat(M, span_notice("\The [piece] [!seal_target ? "seal around your feet" : "relax their grip on your legs"]."))
							M.update_inv_shoes()
						if("gloves")
							to_chat(M, span_notice("\The [piece] [!seal_target ? "tighten around your fingers and wrists" : "become loose around your fingers"]."))
							M.update_inv_gloves()
						if("chest")
							to_chat(M, span_notice("\The [piece] [!seal_target ? "cinches tight again your chest" : "releases your chest"]."))
							M.update_inv_wear_suit()
						if("helmet")
							to_chat(M, span_notice("\The [piece] hisses [!seal_target ? "closed" : "open"]."))
							M.update_inv_head()
							if(helmet?.light_system == STATIC_LIGHT)
								helmet.update_light(wearer)

					//sealed pieces become airtight, protecting against diseases
					if (!seal_target)
						piece.armor["bio"] = 100
					else
						piece.armor["bio"] = src.armor["bio"]
					playsound(src,'sound/machines/rig/rigservo.ogg', 10, FALSE)

				else
					failed_to_seal = 1

		if((M && !(istype(M) && (M.back == src || M.belt == src)) && !istype(M,/mob/living/silicon)) || (!seal_target && !suit_is_deployed()))
			failed_to_seal = 1

	sealing = null

	if(failed_to_seal)
		M.client?.screen -= booting_L
		M.client?.screen -= booting_R
		qdel(booting_L)
		qdel(booting_R)
		for(var/obj/item/piece in list(helmet,boots,gloves,chest))
			if(!piece) continue
			piece.icon_state = "[suit_state][!seal_target ? "" : "_sealed"]"
		canremove = !seal_target
		if(airtight)
			update_component_sealed()
		update_icon(1)
		return 0

	// Success!
	canremove = seal_target
	if(M.hud_used)
		if(canremove)
			QDEL_NULL(minihud)
		else
			minihud = new (M.hud_used, src)
	to_chat(M, span_boldnotice("Your entire suit [canremove ? "loosens as the components relax" : "tightens around you as the components lock into place"]."))
	playsound(src, 'sound/machines/rig/rigstarted.ogg', 10, FALSE)
	M.client?.screen -= booting_L
	qdel(booting_L)
	booting_R.icon_state = "boot_done"
	spawn(40)
		M.client?.screen -= booting_R
		qdel(booting_R)

	if(canremove)
		for(var/obj/item/rig_module/module in installed_modules)
			module.deactivate()
	if(airtight)
		update_component_sealed()
	update_icon(1)

/obj/item/rig/proc/update_component_sealed()
	for(var/obj/item/piece in list(helmet,boots,gloves,chest))
		if(canremove)
			update_airtight(piece, 0) // Unseal
		else
			update_airtight(piece, 1) // Seal

/obj/item/rig/proc/toggle_cooling(mob/user)
	if(cooling_on)
		turn_cooling_off(user)
	else
		turn_cooling_on(user)

/obj/item/rig/proc/turn_cooling_on(mob/user)
	if(!cell)
		return
	if(cell.charge <= 0)
		to_chat(user, span_notice("\The [src] has no power!"))
		return
	if(!suit_is_deployed())
		to_chat(user, span_notice("The hardsuit needs to be deployed first!"))
		return

	cooling_on = 1
	power_system.cooling_on = 1
	to_chat(user, span_notice("You switch \the [src]'s cooling system on."))


/obj/item/rig/proc/turn_cooling_off(mob/user, failed)
	if(failed)
		visible_message("\The [src]'s cooling system clicks and whines as it powers down.")
	else
		to_chat(user, span_notice("You switch \the [src]'s cooling system off."))
	cooling_on = 0
	power_system.cooling_on = 0

// Thin wrapper — environment-temperature logic now lives in power_system.
// Kept here so legacy callers (and subtypes) continue to work unchanged.
/obj/item/rig/proc/get_environment_temperature()
	return power_system.get_environment_temperature()

/obj/item/rig/proc/attached_to_user(mob/M)
	if (!ishuman(M))
		return 0

	var/mob/living/carbon/human/H = M

	if (!H.wear_suit || (H.back != src && H.belt != src))
		return 0

	return 1

// coolingProcess() delegates to power_system so the logic lives in one place.
// The cooling_on var on src is the authority; power_system.cooling_on mirrors it.
/obj/item/rig/proc/coolingProcess()
	if(!ismob(loc))
		return
	var/mob/living/carbon/human/H = loc
	power_system.run_cooling(H)

/obj/item/rig/process()
	// Not on a mob...?
	if(!ismob(loc))
		if(wearer?.wearing_rig == src)
			wearer.wearing_rig = null
		wearer = null
		return PROCESS_KILL

	// Run through cooling.
	coolingProcess()

	// The offline-state machine now lives in power_system.
	// We only invoke it when the original condition would have triggered
	// the cell-check path, preserving the original conditional structure.
	if(!istype(wearer) || loc != wearer || (wearer.back != src && wearer.belt != src) || canremove || !cell || cell.charge <= 0)
		if(power_system.process_offline_state())
			offline = power_system.offline
			return
		offline = power_system.offline

	// If we are still offline (came online this tick but skipped the block above),
	// sync and bail so we don't run module processing while unpowered.
	if(offline)
		offline = power_system.offline
		return

	if(cell && cell.charge > 0 && electrified > 0)
		electrified--

	if(malfunction_delay > 0)
		malfunction_delay--
	else if(malfunctioning)
		malfunctioning--
		malfunction()

	for(var/obj/item/rig_module/module in installed_modules)
		cell.use(module.process()*10)

/obj/item/rig/proc/check_power_cost(mob/living/user, cost, use_unconcious, obj/item/rig_module/mod, user_is_ai)

	if(!istype(user))
		return 0

	var/fail_msg

	if(!user_is_ai)
		var/mob/living/carbon/human/H = user
		if(istype(H) && (H.back != src && H.belt != src))
			fail_msg = span_warning("You must be wearing \the [src] to do this.")
		else if(user.is_incorporeal())
			fail_msg = span_warning("You must be solid to do this.")
	if(sealing)
		fail_msg = span_warning("The hardsuit is in the process of adjusting seals and cannot be activated.")
	else if(!fail_msg && ((use_unconcious && user.stat > 1) || (!use_unconcious && user.stat)))
		fail_msg = span_warning("You are in no fit state to do that.")
	else if(!cell)
		fail_msg = span_warning("There is no cell installed in the suit.")
	else if(cost && cell.charge < cost * 10) //TODO: Cellrate?
		fail_msg = span_warning("Not enough stored power.")

	if(fail_msg)
		to_chat(user, fail_msg)
		playsound(src, 'sound/machines/rig/rigerror.ogg', 20, FALSE)
		return 0

	// This is largely for cancelling stealth and whatever.
	if(mod && mod.disruptive)
		for(var/obj/item/rig_module/module in (installed_modules - mod))
			if(module.active && module.disruptable)
				module.deactivate()

	cell.use(cost*10)
	return 1

/obj/item/rig/update_icon(update_mob_icon)

	cut_overlays()
	if(!mob_icon || update_mob_icon)
		var/species_icon = default_mob_icon
		// Since setting mob_icon will override the species checks in
		// update_inv_wear_suit(), handle species checks here.
		if(wearer && LAZYACCESS(sprite_sheets, wearer.species.get_bodytype(wearer)))
			species_icon = sprite_sheets[wearer.species.get_bodytype(wearer)]
		mob_icon = icon(icon = species_icon, icon_state = "[icon_state]")

	chest.cut_overlays()
	if(installed_modules.len)
		for(var/obj/item/rig_module/module in installed_modules)
			if(module.suit_overlay)
				chest.add_overlay(image(module.suit_overlay_icon, icon_state = "[module.suit_overlay]", dir = SOUTH))

	if(wearer)
		wearer.update_inv_shoes()
		wearer.update_inv_gloves()
		wearer.update_inv_head()
		wearer.update_inv_wear_suit()
		wearer.update_inv_back()
	return

/obj/item/rig/proc/check_suit_access(mob/living/carbon/human/user, do_message = TRUE)

	if(!security_check_enabled)
		return 1

	if(istype(user))
		if(!canremove)
			return 1
		if(malfunction_check(user))
			return 0
		if(user.back != src && user.belt != src)
			return 0
		else if(!src.allowed(user))
			if(do_message)
				to_chat(user, span_danger("Unauthorized user. Access denied."))
			return 0

	else if(!ai_override_enabled)
		if(do_message)
			to_chat(user, span_danger("Synthetic access disabled. Please consult hardware provider."))
		return 0

	return 1

/obj/item/rig/proc/notify_ai(message)
	for(var/obj/item/rig_module/ai_container/module in installed_modules)
		if(module.integrated_ai && module.integrated_ai.client && !module.integrated_ai.stat)
			to_chat(module.integrated_ai, "[message]")
			. = 1

/obj/item/rig/equipped(mob/living/carbon/human/M)
	..()

	if(istype(M.back, /obj/item/rig) && istype(M.belt, /obj/item/rig))
		to_chat(M, span_notice("You try to put on the [src], but it won't fit."))
		if(M && (M.back == src || M.belt == src))
			if(!M.unEquip(src))
				return
		src.forceMove(get_turf(src))
		return

	if(seal_delay > 0 && istype(M) && (M.back == src || M.belt == src))
		M.visible_message(span_notice("[M] starts putting on \the [src]..."), span_notice("You start putting on \the [src]..."))
		if(!do_after(M, seal_delay, target = src))
			if(M && (M.back == src || M.belt == src))
				if(!M.unEquip(src))
					return
			src.forceMove(get_turf(src))
			return

	if(istype(M) && (M.back == src || M.belt == src))
		M.visible_message(span_boldnotice("[M] struggles into \the [src]."), span_boldnotice("You struggle into \the [src]."))
		wearer = M
		wearer.wearing_rig = src
		update_icon()

/obj/item/rig/proc/toggle_piece(piece, mob/living/carbon/human/H, deploy_mode, forced = FALSE)

	if((sealing || !cell || !cell.charge) && !forced)
		return

	if((!istype(wearer) || (!wearer.back == src && !wearer.belt == src)) && !forced)
		return

	if(!H)
		return

	if((H == wearer && (H.stat||H.paralysis||H.stunned)) && !forced) // If the user isn't wearing the suit it's probably an AI.
		return

	var/obj/item/check_slot
	var/equip_to
	var/obj/item/use_obj

	switch(piece)
		if("helmet")
			equip_to = slot_head
			use_obj = helmet
			check_slot = H.head
		if("gauntlets")
			equip_to = slot_gloves
			use_obj = gloves
			check_slot = H.gloves
		if("boots")
			equip_to = slot_shoes
			use_obj = boots
			check_slot = H.shoes
		if("chest")
			equip_to = slot_wear_suit
			use_obj = chest
			check_slot = H.wear_suit

	if(use_obj)
		if(check_slot == use_obj && deploy_mode != ONLY_DEPLOY)

			var/mob/living/carbon/human/holder

			if(use_obj)
				holder = use_obj.loc
				if(istype(holder))
					if(use_obj && check_slot == use_obj)
						balloon_alert(H, "your [use_obj.name] [use_obj.gender == PLURAL ? "retract" : "retracts"] swiftly.")
						playsound(src, 'sound/machines/rig/rigservo.ogg', 10, FALSE)
						use_obj.canremove = TRUE
						holder.drop_from_inventory(use_obj)
						use_obj.forceMove(get_turf(src))
						use_obj.dropped(holder)
						use_obj.canremove = FALSE
						use_obj.forceMove(src)

		else if (deploy_mode != ONLY_RETRACT)
			if(check_slot && check_slot == use_obj)
				return
			use_obj.forceMove(H)
			if(!H.equip_to_slot_if_possible(use_obj, equip_to, 0, 1))
				use_obj.forceMove(src)
				if(check_slot)
					to_chat(H, span_danger("You are unable to deploy \the [piece] as \the [check_slot] [check_slot.gender == PLURAL ? "are" : "is"] in the way."))
					return
			else
				balloon_alert(H, "your [use_obj.name] [use_obj.gender == PLURAL ? "deploy" : "deploys"] swiftly.")
				playsound(src, 'sound/machines/rig/rigservo.ogg', 10, FALSE)

	if(piece == "helmet" && helmet?.light_system == STATIC_LIGHT)
		helmet.update_light()

/obj/item/rig/proc/deploy(mob/M,destructive)

	var/mob/living/carbon/human/H = M

	if(!H || !istype(H)) return

	if(H.back != src && H.belt != src)
		return

	if(destructive)
		if(H.head)
			var/obj/item/garbage = H.head
			H.drop_from_inventory(garbage)
			H.head = null
			qdel(garbage)

		if(H.gloves)
			var/obj/item/garbage = H.gloves
			H.drop_from_inventory(garbage)
			H.gloves = null
			qdel(garbage)

		if(H.shoes)
			var/obj/item/garbage = H.shoes
			H.drop_from_inventory(garbage)
			H.shoes = null
			qdel(garbage)

		if(H.wear_suit)
			var/obj/item/garbage = H.wear_suit
			H.drop_from_inventory(garbage)
			H.wear_suit = null
			qdel(garbage)

	for(var/piece in list("helmet","gauntlets","chest","boots"))
		toggle_piece(piece, H, ONLY_DEPLOY)

/obj/item/rig/dropped(mob/user, equipping, slot)
	. = ..(user)
	// So the next user will see the boot animation
	tgui_shared_states?.Cut()
	for(var/piece in list("helmet","gauntlets","chest","boots"))
		toggle_piece(piece, user, ONLY_RETRACT)
	if(wearer && wearer.wearing_rig == src)
		wearer.wearing_rig = null
	wearer = null

//Todo
/obj/item/rig/proc/malfunction()
	return 0

/obj/item/rig/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	//set malfunctioning
	if(emp_protection < 30) //for ninjas, really.
		malfunctioning += 10
		if(malfunction_delay <= 0)
			malfunction_delay = max(malfunction_delay, round(30/severity))

	//drain some charge
	if(cell) cell.emp_act(severity + 15)

	//possibly damage some modules
	take_hit((100/severity), "electrical pulse", 1)

/obj/item/rig/proc/shock(mob/user)
	if (electrocute_mob(user, cell, src)) //electrocute_mob() handles removing charge from the cell, no need to do that here.
		spark_system.start()
		if(user.stunned)
			return 1
	return 0

/obj/item/rig/proc/take_hit(damage, source, is_emp=0)

	if(!installed_modules.len)
		return

	var/chance
	if(!is_emp)
		chance = 2*max(0, damage - (chest? chest.breach_threshold : 0))
	else
		//Want this to be roughly independant of the number of modules, meaning that X emp hits will disable Y% of the suit's modules on average.
		//that way people designing hardsuits don't have to worry (as much) about how adding that extra module will affect emp resiliance by 'soaking' hits for other modules
		chance = 2*max(0, damage - emp_protection)*min(installed_modules.len/15, 1)

	if(!prob(chance))
		return

	//deal addition damage to already damaged module first.
	//This way the chances of a module being disabled aren't so remote.
	var/list/valid_modules = list()
	var/list/damaged_modules = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.damage < 2)
			valid_modules |= module
			if(module.damage > 0)
				damaged_modules |= module

	var/obj/item/rig_module/dam_module = null
	if(damaged_modules.len)
		dam_module = pick(damaged_modules)
	else if(valid_modules.len)
		dam_module = pick(valid_modules)

	if(!dam_module) return

	dam_module.damage++

	if(!source)
		source = "hit"

	if(wearer)
		if(dam_module.damage >= 2)
			to_chat(wearer, span_danger("The [source] has disabled your [dam_module.interface_name]!"))
		else
			to_chat(wearer, span_warning("The [source] has damaged your [dam_module.interface_name]!"))
	dam_module.deactivate()

/obj/item/rig/proc/malfunction_check(mob/living/carbon/human/user)
	if(malfunction_delay)
		if(offline)
			to_chat(user, span_danger("The suit is completely unresponsive."))
		else
			to_chat(user, span_danger("ERROR: Hardware fault. Rebooting interface..."))
		return 1
	return 0

/obj/item/rig/proc/ai_can_move_suit(mob/user, check_user_module = 0, check_for_ai = 0)

	if(check_for_ai)
		if(!(locate(/obj/item/rig_module/ai_container) in contents))
			return 0
		var/found_ai
		for(var/obj/item/rig_module/ai_container/module in contents)
			if(module.damage >= 2)
				continue
			if(module.integrated_ai && module.integrated_ai.client && !module.integrated_ai.stat)
				found_ai = 1
				break
		if(!found_ai)
			return 0

	if(check_user_module)
		if(!user || !user.loc || !user.loc.loc)
			return 0
		var/obj/item/rig_module/ai_container/module = user.loc.loc
		if(!istype(module) || module.damage >= 2)
			to_chat(user, span_warning("Your host module is unable to interface with the suit."))
			return 0

	if(offline || !cell || !cell.charge || locked_down)
		if(user)
			to_chat(user, span_warning("Your host rig is unpowered and unresponsive."))
		return 0
	if(!wearer || (wearer.back != src && wearer.belt != src))
		if(user)
			to_chat(user, span_warning("Your host rig is not being worn."))
		return 0
	if(!wearer.stat && !control_overridden && !ai_override_enabled)
		if(user)
			to_chat(user, span_warning("You are locked out of the suit servo controller."))
		return 0
	return 1

/obj/item/rig/proc/force_rest(mob/user)
	if(!ai_can_move_suit(user, check_user_module = 1))
		return
	wearer.lay_down()
	to_chat(user, span_notice("\The [wearer] is now [wearer.resting ? "resting" : "getting up"]."))

/obj/item/rig/proc/forced_move(direction, mob/user, ai_moving = TRUE)

	// Why is all this shit in client/Move()? Who knows?
	if(world.time < wearer_move_delay)
		return

	if(!wearer || !wearer.loc) // Removed some stuff for protean living hardsuit
		return

// Added this for protean living hardsuit
	wearer_move_delay = world.time + 2
	if(ai_moving)
		if(!ai_can_move_suit(user, check_user_module = 1))
			return
		// AIs are a bit slower than regular and ignore move intent.
		// Moved this to where it's relevant
		wearer_move_delay = world.time + ai_controlled_move_delay

	//This is sota the goto stop mobs from moving var
	if(wearer.transforming || !wearer.canmove)
		return

	if((istype(wearer.loc, /turf/space)) || (wearer.lastarea.get_gravity() == 0))
		if(!wearer.Process_Spacemove(0))
			return 0

	if(malfunctioning)
		direction = pick(GLOB.cardinal)

	// Inside an object, tell it we moved.
	if(isobj(wearer.loc) || ismob(wearer.loc))
		var/atom/O = wearer.loc
		return O.relaymove(wearer, direction)

	if(isturf(wearer.loc))
		if(wearer.restrained())//Why being pulled while cuffed prevents you from moving
			for(var/mob/M in range(wearer, 1))
				if(M.pulling == wearer)
					if(!M.restrained() && M.stat == 0 && M.canmove && wearer.Adjacent(M))
						to_chat(user, span_notice("Your host is restrained! They can't move!"))
						return 0
					else
						M.stop_pulling()

	if(LAZYLEN(wearer.pinned))
		to_chat(src, span_notice("Your host is pinned to a wall by [wearer.pinned[1]]!"))
		return 0

	if(istype(wearer.buckled, /obj/vehicle))
		//manually set move_delay for vehicles so we don't inherit any mob movement penalties
		//specific vehicle move delays are set in code\modules\vehicles\vehicle.dm
		wearer_move_delay = world.time
		return wearer.buckled.relaymove(wearer, direction)

	if(istype(wearer.get_current_machine(), /obj/machinery))
		if(wearer.get_current_machine().relaymove(wearer, direction))
			return

	if(wearer.pulledby || wearer.buckled) // Wheelchair driving!
		if(istype(wearer.loc, /turf/space))
			return // No wheelchair driving in space
		if(istype(wearer.pulledby, /obj/structure/bed/chair/wheelchair))
			return wearer.pulledby.relaymove(wearer, direction)
		else if(istype(wearer.buckled, /obj/structure/bed/chair/wheelchair))
			if(ishuman(wearer.buckled))
				var/obj/item/organ/external/l_hand = wearer.get_organ(BP_L_HAND)
				var/obj/item/organ/external/r_hand = wearer.get_organ(BP_R_HAND)
				if((!l_hand || (l_hand.status & ORGAN_DESTROYED)) && (!r_hand || (r_hand.status & ORGAN_DESTROYED)))
					return // No hands to drive your chair? Tough luck!
			wearer_move_delay += 2
			return wearer.buckled.relaymove(wearer,direction)

	var/power_cost = 50
	if(!ai_moving)
		power_cost = 20
	cell.use(power_cost) //Arbitrary, TODO
	wearer.Move(get_step(get_turf(wearer),direction),direction)

// This returns the rig if you are contained inside one, but not if you are wearing it
/atom/proc/get_rig()
	if(loc)
		return loc.get_rig()
	return null

/obj/item/rig/get_rig()
	return src

/mob/living/carbon/human/get_rig()
	if(istype(back, /obj/item/rig))
		return back
	else if(istype(belt, /obj/item/rig))
		return belt
	else
		return null

/atom/proc/get_voidsuit()
	return null

/mob/living/carbon/human/get_voidsuit()
	if(istype(wear_suit, /obj/item/clothing/suit/space/void))
		return wear_suit
	else
		return null

//Boot animation screen objects
/atom/movable/screen/rig_booting
	screen_loc = "1,1"
	icon = 'icons/obj/rig_boot.dmi'
	icon_state = ""
	layer = SCREEN_LAYER
	plane = PLANE_FULLSCREEN
	mouse_opacity = 0
	alpha = 20 //Animated up when loading

#undef ONLY_DEPLOY
#undef ONLY_RETRACT
#undef SEAL_DELAY
