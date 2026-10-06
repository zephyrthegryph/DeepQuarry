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

	// These values are passed on to all component pieces.
	armor_spec = "melee=40;bullet=5;laser=20;energy=5;bomb=35;bio=100;rad=20"
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
	EXPIRY_DECLARE(wearer_move_delay) //Used for AI moving.
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
	var/tmp/mob/living/carbon/human/wearer	// The person currently wearing the rig.
	var/image/mob_icon                                        // Holder for on-mob icon.
	var/list/installed_modules                       // Power consumption/use bookkeeping.

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

	var/datum/mini_hud/rig/minihud

	// Decomposed subsystems — see rig_power_system.dm and rig_component_registry.dm
	var/datum/rig_power_system/power_system
	var/datum/rig_component_registry/component_registry

	// Action buttons
	actions_types = list(/datum/action/item_action/hardsuit_interface, /datum/action/item_action/toggle_heatsink)

	// Protean
	var/protean = 0
	var/obj/item/storage/backpack/rig_storage
	permeability_coefficient = 0  //Protect the squishies, after all this shit should be waterproof.
	resistance_flags = FIRE_PROOF | ACID_PROOF

CAPABILITIES(/obj/item/rig)
	owns_one(nameof(boots), /obj/item/clothing/shoes)
	owns_one(nameof(chest), /obj/item/clothing/suit/space/rig)
	owns_one(nameof(gloves), /obj/item/clothing/gloves/gauntlets/rig)
	owns_one(nameof(helmet), /obj/item/clothing/head/helmet/space/rig)
	owns_one(nameof(minihud), /datum/mini_hud/rig)
	owns_one(nameof(power_system), starts = /datum/rig_power_system)
	owns_one(nameof(component_registry), starts = /datum/rig_component_registry)
	// We only care about processing when we're on a mob
	every(2 SECONDS, then(PROC_REF(rig_step)), when = nameof(carried_by_mob))
	space(SPACE_PANEL, door = nameof(open))
	wires(name = "Unknown", count = 5, randomize = TRUE, tools = FALSE)
	on_wire(WIRE_RIG_SECURITY, cut = PROC_REF(security_wire_cut), pulse = PROC_REF(security_wire_pulsed))
	on_wire(WIRE_RIG_AI_OVERRIDE, pulse = PROC_REF(ai_override_wire_pulsed))
	on_wire(WIRE_RIG_SYSTEM_CONTROL, pulse = PROC_REF(system_wire_pulsed))
	on_wire(WIRE_RIG_INTERFACE_LOCK, pulse = PROC_REF(interface_lock_wire_pulsed))
	on_wire(WIRE_RIG_INTERFACE_SHOCK, cut = PROC_REF(shock_wire_cut), pulse = PROC_REF(shock_wire_pulsed))
	interface(null, state = nameof(GLOB.tgui_inventory_state), window_var = nameof(interface_path))
	without("ui_open")
	op("toggle_seals", ui_act("toggle_seals"), then(PROC_REF(ui_act_toggle_seals)))
	op("toggle_cooling", ui_act("toggle_cooling"), then(PROC_REF(ui_act_toggle_cooling)))
	op("toggle_ai_control", ui_act("toggle_ai_control"), then(PROC_REF(ui_act_toggle_ai_control)))
	op("toggle_suit_lock", ui_act("toggle_suit_lock"), then(PROC_REF(ui_act_toggle_suit_lock)))
	op("toggle_piece", ui_act("toggle_piece", arg("piece", schema_text(4096))), then(PROC_REF(ui_act_toggle_piece)))
	op("interact_module", ui_act("interact_module", arg("charge_type", schema_text(4096)), arg("module", num()), arg("module_mode", schema_text(4096))), then(PROC_REF(ui_act_interact_module)))
	op("tank_settings", ui_act("tank_settings"), then(PROC_REF(ui_act_tank_settings)))

/obj/item/rig/Initialize(mapload)
	. = ..()

	suit_state = icon_state
	item_state = icon_state

	if(!LAZYLEN(req_access) && !LAZYLEN(req_one_access))
		locked = 0

	// Instantiate the decomposed subsystems.
	power_system.cooling_on              = cooling_on
	power_system.max_cooling             = max_cooling
	power_system.charge_consumption      = charge_consumption
	power_system.thermostat              = thermostat
	power_system.offline                 = offline
	power_system.offline_slowdown        = offline_slowdown
	power_system.offline_vision_restriction = offline_vision_restriction

	component_registry.initialize_pieces()

	mob_icon = null // rebuilt by the redraw
	update_icon()


// the suit pieces are torn down by its (owned) component registry.
/obj/item/rig/on_destroy(force)
	component_registry?.destroy_pieces(src)
	..()

/obj/item/rig/MouseDrop(obj/over_object)
	if(unremovable)
		return
	..()

/obj/item/rig/examine(mob/user)
	. = ..()
	if(wearer())
		for(var/obj/item/piece in list(helmet,gloves,chest,boots))
			if(!piece || piece.loc != wearer())
				continue
			. += "[icon2html(piece, user.client)] \The [piece] [piece.gender == PLURAL ? "are" : "is"] deployed."

	if(src.loc == user)
		. += "The access panel is [locked? "locked" : "unlocked"]."
		. += "The maintenance panel is [open ? "open" : "closed"]."
		. += "Hardsuit systems are [offline ? span_warning("offline") : span_notice("online")]."
		. += "The cooling system is [cooling_on ? "active" : "inactive"]."

		if(open)
			. += "It's equipped with [english_list(installed_modules)]."

/// TRUE while it is on a mob; set by Moved().
/obj/item/rig/var/carried_by_mob = FALSE
TRACKED(/obj/item/rig, carried_by_mob)

/obj/item/rig/Moved(old_loc, direction, forced)
	set_carried_by_mob(ismob(loc) ? TRUE : FALSE)
	if(!ismob(loc))
		own_clear(src, nameof(minihud), OWN_DELETE) // Just in case we get removed some other way

		// The control module has left the wearer's body — dropped, force-dropped on
		// damage, stuffed into storage, gibbed off, or a protean transforming out of
		// rig mode. Retract any still-deployed pieces so the armour can't stay locked
		// onto the (ex-)wearer. Moved() is the universal hook: unlike dropped() it also
		// fires for forceMove(), which is how the damage/protean paths remove the suit.
		for(var/obj/item/clothing/piece in list(helmet, gloves, chest, boots))
			if(piece.master_rig() == src && ismob(piece.loc))
				piece.rig_self_detach()
		// drop_from_inventory() bypasses the canremove seal gate, so a sealed suit can
		// land here still flagged sealed. Reset to a clean unsealed state, otherwise the
		// next wearer's first seal toggle inverts (seal_target = !canremove).
		if(!canremove)
			reset()
		// Off a mob the slow step no longer runs (carried_by_mob), so let go of the wearer here.
		if(wearer()?.wearing_rig == src)
			own_take(wearer(), nameof(/mob/living/carbon/human::wearing_rig))
		rel_clear(src, nameof(wearer))

	// If we've lost any parts, grab them back.
	var/mob/living/M
	for(var/obj/item/piece in list(gloves,boots,helmet,chest))
		if(piece.loc != src && !(wearer() && piece.loc == wearer()))
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
	if(!istype(wearer(), /mob/living/carbon/human) || src.loc != wearer() || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		return 0
	if(helm_type && !(helmet && wearer().get_equipped_item(SLOT_ID_HEAD) == helmet))
		return 0
	if(glove_type && !(gloves && wearer().get_equipped_item(SLOT_ID_GLOVES) == gloves))
		return 0
	if(boot_type && !(boots && wearer().get_equipped_item(SLOT_ID_SHOES) == boots))
		return 0
	if(chest_type && !(chest && wearer().get_equipped_item(SLOT_ID_SUIT) == chest))
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
	mob_icon = null // rebuilt by the redraw
	update_icon()

/obj/item/rig/proc/cut_suit()
	offline = 2
	canremove = TRUE
	toggle_piece("helmet", loc, ONLY_RETRACT, TRUE)
	toggle_piece("gauntlets", loc, ONLY_RETRACT, TRUE)
	toggle_piece("boots", loc, ONLY_RETRACT, TRUE)
	toggle_piece("chest", loc, ONLY_RETRACT, TRUE)
	mob_icon = null // rebuilt by the redraw
	update_icon()

/// Seals or unseals the suit: a sequence of timed actions (the overall check, then one per
/// piece), each continuing in seal_piece() and ending in seal_finish().
/obj/item/rig/proc/toggle_seals(mob/living/carbon/human/M, instant, destructive)

	if(sealing) return

	if(!check_power_cost(M))
		return 0

	//NOTE: DESTRUCTIVE SHOULD ONLY BE CALLED ONCE (DURING THE INITIAL DEPLOYMENT)
	//DESTRUCTIVE WILL DELETE ANY CLOTHING THAT WOULD OTHERWISE BE BLOCKING IT.
	//IF DESTRUCTIVE IS CALLED WHILE THE RIG IS ALREADY DEPLOYED, THE RIG WILL DELETE ITSELF.
	deploy(M,destructive)

	var/seal_target = !canremove

	var/atom/movable/screen/rig_booting/booting_L = new
	var/atom/movable/screen/rig_booting/booting_R = new

	if(!seal_target)
		booting_L.icon_state = "boot_left"
		booting_R.icon_state = "boot_load"
		animate(booting_L, alpha=230, time=3 SECONDS, easing=SINE_EASING)
		animate(booting_R, alpha=200, time=2 SECONDS, easing=SINE_EASING)
		M.client?.screen += booting_L
		M.client?.screen += booting_R

	canremove = FALSE // No removing the suit while unsealing.
	sealing = 1

	if(!seal_target && !suit_is_deployed())
		act_message(M, null, MSG_SELF(span_danger("Your suit flashes an error light. It can't function properly without being fully deployed.")), \
			MSG_OTHERS(span_danger("%U%'s suit flashes an error light.")))
		play_sfx(src, SFX_MACHINES_RIG_RIGERROR)
		seal_finish(M, seal_target, booting_L, booting_R, TRUE)
		return 0

	if(!instant)
		act_message(M, null, MSG_SELF(span_notice("With a quiet hum, the suit begins running checks and adjusting components.")), \
			MSG_OTHERS(span_notice("%U%'s suit emits a quiet hum as it begins to adjust its seals.")))
		if(seal_delay)
			om_task_start(/datum/om/task/timed/rig_seal, M, src, duration = seal_delay, seal_target = seal_target, booting_L = booting_L, booting_R = booting_R)
			return 1
	seal_piece(M, seal_target, instant, booting_L, booting_R, 1)
	return 1

/// One timed stage of sealing the suit: the overall check (no piece), or one piece. Each
/// continues in seal_piece() with the next piece.
/datum/om/task/timed/rig_seal
	flags = IGNORE_TARGET_LOC_CHANGE
	complete_proc = /obj/item/rig/proc/seal_stage_done
	cancel_proc = /obj/item/rig/proc/seal_interrupted
	var/seal_target
	var/atom/movable/screen/rig_booting/booting_L
	var/atom/movable/screen/rig_booting/booting_R
	/// The piece this stage seals (null: the overall check) and its place in the order.
	var/obj/item/piece
	var/msg_type
	var/index = 0

/obj/item/rig/proc/seal_interrupted(datum/om/task/timed/rig_seal/task)
	var/mob/living/carbon/human/M = task.actor
	if(M)
		to_chat(M, span_warning("You must remain still while the suit is adjusting the components."))
		play_sfx(src, SFX_MACHINES_RIG_RIGERROR)
	seal_finish(M, task.seal_target, task.booting_L, task.booting_R, TRUE)

/obj/item/rig/proc/seal_stage_done(datum/om/task/timed/rig_seal/task)
	if(task.piece)
		seal_one_piece(task.actor, task.piece, task.msg_type, task.seal_target)
	seal_piece(task.actor, task.seal_target, FALSE, task.booting_L, task.booting_R, task.index + 1)

/// Seals pieces from `index` on (boots, gloves, helmet, chest); a piece with a seal delay is a
/// timed action that comes back here for the next one.
/obj/item/rig/proc/seal_piece(mob/living/carbon/human/M, seal_target, instant, atom/movable/screen/rig_booting/booting_L, atom/movable/screen/rig_booting/booting_R, index)
	if(!M)
		seal_finish(M, seal_target, booting_L, booting_R, TRUE)
		return
	var/list/pieces = list(list(M.get_equipped_item(SLOT_ID_SHOES),boots,"boots",boot_type),list(M.get_equipped_item(SLOT_ID_GLOVES),gloves,"gloves",glove_type),list(M.get_equipped_item(SLOT_ID_HEAD),helmet,"helmet",helm_type),list(M.get_equipped_item(SLOT_ID_SUIT),chest,"chest",chest_type))
	for(var/i in index to length(pieces))
		var/list/piece_data = pieces[i]
		var/obj/item/piece = piece_data[1]
		var/obj/item/compare_piece = piece_data[2]
		var/msg_type = piece_data[3]
		var/piece_type = piece_data[4]

		if(!piece || !piece_type)
			continue

		if(!istype(M) || !istype(piece) || !istype(compare_piece) || !msg_type)
			to_chat(M, span_warning("You must remain still while the suit is adjusting the components."))
			seal_finish(M, seal_target, booting_L, booting_R, TRUE)
			return

		if(!((M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src) && piece == compare_piece))
			seal_finish(M, seal_target, booting_L, booting_R, TRUE)
			return

		if(seal_delay && !instant)
			om_task_start(/datum/om/task/timed/rig_seal, M, src, duration = seal_delay, seal_target = seal_target, booting_L = booting_L, booting_R = booting_R, piece = piece, msg_type = msg_type, index = i)
			return
		seal_one_piece(M, piece, msg_type, seal_target)

	seal_finish(M, seal_target, booting_L, booting_R, FALSE)

/obj/item/rig/proc/seal_one_piece(mob/living/carbon/human/M, obj/item/piece, msg_type, seal_target)
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
				helmet.update_light(wearer())

	//sealed pieces become airtight, protecting against diseases
	if (!seal_target)
		piece.set_armor_value("bio", 100)
	else
		piece.set_armor_value("bio", src.get_armor().value("bio"))
	piece.worn_protection_changed()
	play_sfx(src, SFX_MACHINES_RIG_RIGSERVO)

/obj/item/rig/proc/seal_finish(mob/living/carbon/human/M, seal_target, atom/movable/screen/rig_booting/booting_L, atom/movable/screen/rig_booting/booting_R, failed_to_seal)
	if(!failed_to_seal)
		if(!M || (!(istype(M) && (M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src)) && !istype(M,/mob/living/silicon)) || (!seal_target && !suit_is_deployed()))
			failed_to_seal = 1

	sealing = null

	if(failed_to_seal)
		M?.client?.screen -= booting_L
		M?.client?.screen -= booting_R
		consume(booting_L, M)
		consume(booting_R, M)
		for(var/obj/item/piece in list(helmet,boots,gloves,chest))
			if(!piece) continue
			piece.icon_state = "[suit_state][!seal_target ? "" : "_sealed"]"
		canremove = !seal_target
		if(airtight)
			update_component_sealed()
		mob_icon = null // rebuilt by the redraw
		update_icon()
		return 0

	// Success!
	canremove = seal_target
	if(M.hud_used)
		if(canremove)
			own_clear(src, nameof(minihud), OWN_DELETE)
		else
			rel_set(src, nameof(minihud), new /datum/mini_hud/rig (M.hud_used, src))
	to_chat(M, span_boldnotice("Your entire suit [canremove ? "loosens as the components relax" : "tightens around you as the components lock into place"]."))
	play_sfx(src, SFX_MACHINES_RIG_RIGSTARTED)
	M.client?.screen -= booting_L
	consume(booting_L, M)
	booting_R.icon_state = "boot_done"
	after(M, 4 SECONDS, /proc/rig_boot_hud_clear, with = list(M, booting_R))

	if(canremove)
		for(var/obj/item/rig_module/module in installed_modules)
			module.deactivate()
	if(airtight)
		update_component_sealed()
	mob_icon = null // rebuilt by the redraw
	update_icon()

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

/obj/item/rig/proc/attached_to_user(mob/M)
	if (!ishuman(M))
		return 0

	var/mob/living/carbon/human/H = M

	if (!H.get_equipped_item(SLOT_ID_SUIT) || (H.get_equipped_item(SLOT_ID_BACK) != src && H.get_equipped_item(SLOT_ID_BELT) != src))
		return 0

	return 1

// coolingProcess() delegates to power_system so the logic lives in one place.
// The cooling_on var on src is the authority; power_system.cooling_on mirrors it.
/obj/item/rig/proc/coolingProcess()
	if(!ismob(loc))
		return
	var/mob/living/carbon/human/H = loc
	power_system.run_cooling(H)

/obj/item/rig/proc/rig_step(datum/act/timer/A)
	// Run through cooling.
	coolingProcess()

	// The offline-state machine now lives in power_system.
	// We only invoke it when the original condition would have triggered
	// the cell-check path, preserving the original conditional structure.
	if(!istype(wearer(), /mob/living/carbon/human) || loc != wearer() || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src) || canremove || !cell || cell.charge <= 0)
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
		draw_power(module.periodic_step() * 10 / CELLRATE, module, partial = TRUE)

/obj/item/rig/proc/check_power_cost(mob/living/user, cost, use_unconcious, obj/item/rig_module/mod, user_is_ai)

	if(!istype(user))
		return 0

	var/fail_msg

	if(!user_is_ai)
		var/mob/living/carbon/human/H = user
		if(istype(H) && (H.get_equipped_item(SLOT_ID_BACK) != src && H.get_equipped_item(SLOT_ID_BELT) != src))
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
		play_sfx(src, SFX_MACHINES_RIG_RIGERROR)
		return 0

	// This is largely for cancelling stealth and whatever.
	if(mod && mod.disruptive)
		for(var/obj/item/rig_module/module in (installed_modules - mod))
			if(module.active && module.disruptable)
				module.deactivate(FALSE, user)

	draw_power(cost * 10 / CELLRATE, mod || user, partial = TRUE)
	return 1

// --- Power ledger ------------------------------------------------------------------------
// draw_power() and add_power() are the only writers of a rig's cell (module
// upkeep, seals and activation, cooling, suit movement, power sinks, the
// protean cluster's recharge), as for robots (robot.dm). Amounts are joules; the cell stores joules * CELLRATE.

/// Take `joules` from the cell, all or nothing. `reserve` joules must remain
/// afterwards. `partial` takes whatever is there instead. Returns TRUE if
/// anything was drawn.
/obj/item/rig/proc/draw_power(joules, datum/source, reserve = 0, partial = FALSE)
	if(joules <= 0)
		return TRUE
	if(!cell)
		return FALSE
	var/units = joules * CELLRATE
	if(partial)
		return cell.use(units, FALSE) > 0
	if(!cell.check_charge(units + max(reserve, 0) * CELLRATE))
		return FALSE
	return cell.use(units, FALSE) >= units

/// Put up to `joules` into the cell. Returns the joules actually stored.
/obj/item/rig/proc/add_power(joules, datum/source)
	if(joules <= 0 || !cell)
		return 0
	return cell.give(joules * CELLRATE, FALSE) / CELLRATE

DECLARE_APPEARANCE_PROC(/obj/item/rig, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/rig/appearance_overlays()
	. = list()

	if(!mob_icon)
		var/species_icon = default_mob_icon
		// Since setting mob_icon will override the species checks in
		// update_inv_wear_suit(), handle species checks here.
		if(wearer() && LAZYACCESS(sprite_sheets, wearer().species.get_bodytype(wearer())))
			species_icon = sprite_sheets[wearer().species.get_bodytype(wearer())]
		mob_icon = icon(icon = species_icon, icon_state = "[icon_state]")

	if(chest)
		chest.cut_overlays()
		if(length(installed_modules))
			for(var/obj/item/rig_module/module in installed_modules)
				if(module.suit_overlay)
					chest.add_overlay(image(module.suit_overlay_icon, icon_state = "[module.suit_overlay]", dir = SOUTH))

	if(wearer())
		wearer().update_inv_shoes()
		wearer().update_inv_gloves()
		wearer().update_inv_head()
		wearer().update_inv_wear_suit()
		wearer().update_inv_back()
	return .

/obj/item/rig/proc/check_suit_access(mob/living/carbon/human/user, do_message = TRUE)

	if(!security_check_enabled)
		return 1

	if(istype(user))
		if(!canremove)
			return 1
		if(malfunction_check(user))
			return 0
		if(user.get_equipped_item(SLOT_ID_BACK) != src && user.get_equipped_item(SLOT_ID_BELT) != src)
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
		if(module.integrated_ai() && module.integrated_ai().client && !module.integrated_ai().stat)
			to_chat(module.integrated_ai(), "[message]")
			. = 1

/obj/item/rig/equipped(mob/living/carbon/human/M)
	..()

	if(istype(M.get_equipped_item(SLOT_ID_BACK), /obj/item/rig) && istype(M.get_equipped_item(SLOT_ID_BELT), /obj/item/rig))
		to_chat(M, span_notice("You try to put on the [src], but it won't fit."))
		if(M && (M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src))
			if(!M.unEquip(src))
				return
		src.forceMove(get_turf(src))
		return

	if(seal_delay > 0 && istype(M) && (M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src))
		act_message(M, src, MSG_SELF(span_notice("You start putting on %T%...")), MSG_OTHERS(span_notice("%U% starts putting on %T%...")))
		om_task_timed(M, seal_delay, src, src, PROC_REF(put_on_done), list(M), IGNORE_TARGET_LOC_CHANGE, PROC_REF(put_on_failed), list(M))
		return
	put_on_done(M)

/obj/item/rig/proc/put_on_failed(mob/living/carbon/human/M)
	if(M && (M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src))
		if(!M.unEquip(src))
			return
	src.forceMove(get_turf(src))

/obj/item/rig/proc/put_on_done(mob/living/carbon/human/M)
	if(istype(M) && (M.get_equipped_item(SLOT_ID_BACK) == src || M.get_equipped_item(SLOT_ID_BELT) == src))
		act_message(M, src, MSG_SELF(span_boldnotice("You struggle into %T%.")), MSG_OTHERS(span_boldnotice("%U% struggles into %T%.")))
		rel_set(src, nameof(wearer), M)
		rel_set(wearer(), nameof(/mob/living/carbon/human::wearing_rig), src)
		update_icon()

/obj/item/rig/proc/toggle_piece(piece, mob/living/carbon/human/H, deploy_mode, forced = FALSE)

	if((sealing || !cell || !cell.charge) && !forced)
		return

	if((!istype(wearer(), /mob/living/carbon/human) || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src)) && !forced)
		return

	if(!H)
		return

	if((H == wearer() && (H.stat||H.has_status(STAT_PARALYZED)||H.has_status(STAT_STUNNED))) && !forced) // If the user isn't wearing the suit it's probably an AI.
		return

	var/obj/item/check_slot
	var/equip_to
	var/obj/item/clothing/use_obj

	switch(piece)
		if("helmet")
			equip_to = SLOT_ID_HEAD
			use_obj = helmet
			check_slot = H.get_equipped_item(SLOT_ID_HEAD)
		if("gauntlets")
			equip_to = SLOT_ID_GLOVES
			use_obj = gloves
			check_slot = H.get_equipped_item(SLOT_ID_GLOVES)
		if("boots")
			equip_to = SLOT_ID_SHOES
			use_obj = boots
			check_slot = H.get_equipped_item(SLOT_ID_SHOES)
		if("chest")
			equip_to = SLOT_ID_SUIT
			use_obj = chest
			check_slot = H.get_equipped_item(SLOT_ID_SUIT)

	if(use_obj)
		if(check_slot == use_obj && deploy_mode != ONLY_DEPLOY)

			var/mob/living/carbon/human/holder

			if(use_obj)
				holder = use_obj.loc
				if(istype(holder))
					if(use_obj && check_slot == use_obj)
						balloon_alert(H, "your [use_obj.name] [use_obj.gender == PLURAL ? "retract" : "retracts"] swiftly.")
						play_sfx(src, SFX_MACHINES_RIG_RIGSERVO)
						rel_clear(use_obj, nameof(use_obj.master_rig))   // intentional retract: silence the dropped() safety net
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
				rel_set(use_obj, nameof(use_obj.master_rig), src)   // the piece now knows its controller, so it can free itself
				balloon_alert(H, "your [use_obj.name] [use_obj.gender == PLURAL ? "deploy" : "deploys"] swiftly.")
				play_sfx(src, SFX_MACHINES_RIG_RIGSERVO)

	if(piece == "helmet" && helmet?.light_system == STATIC_LIGHT)
		helmet.update_light()

/obj/item/rig/proc/deploy(mob/M,destructive)

	var/mob/living/carbon/human/H = M

	if(!H || !istype(H)) return

	if(H.get_equipped_item(SLOT_ID_BACK) != src && H.get_equipped_item(SLOT_ID_BELT) != src)
		return

	if(destructive)
		if(H.get_equipped_item(SLOT_ID_HEAD))
			var/obj/item/garbage = H.get_equipped_item(SLOT_ID_HEAD)
			consume(garbage, H)

		if(H.get_equipped_item(SLOT_ID_GLOVES))
			var/obj/item/garbage = H.get_equipped_item(SLOT_ID_GLOVES)
			consume(garbage, H)

		if(H.get_equipped_item(SLOT_ID_SHOES))
			var/obj/item/garbage = H.get_equipped_item(SLOT_ID_SHOES)
			consume(garbage, H)

		if(H.get_equipped_item(SLOT_ID_SUIT))
			var/obj/item/garbage = H.get_equipped_item(SLOT_ID_SUIT)
			consume(garbage, H)

	for(var/piece in list("helmet","gauntlets","chest","boots"))
		toggle_piece(piece, H, ONLY_DEPLOY)

/obj/item/rig/dropped(mob/user, equipping, slot)
	. = ..(user)
	// So the next user will see the boot animation
	tgui_shared_states?.Cut()
	// Piece retraction and seal-state reset are handled in Moved() (the universal hook
	// that also catches forceMove); here we just drop the wearer back-references.
	if(wearer() && wearer().wearing_rig == src)
		own_take(wearer(), nameof(/mob/living/carbon/human::wearing_rig))
	rel_clear(src, nameof(wearer))

//Todo
/obj/item/rig/proc/malfunction()
	return 0

DAMAGE_REACTION(/obj/item/rig, DAMAGE_EMP, PROC_REF(rig_emp_malfunction))

/// A pulse makes the suit malfunction, drains its cell and can damage modules.
/obj/item/rig/proc/rig_emp_malfunction(datum/damage_packet/packet)
	//set malfunctioning
	if(emp_protection < 30) //for ninjas, really.
		malfunctioning += 10
		if(malfunction_delay <= 0)
			malfunction_delay = max(malfunction_delay, round(30/packet.severity))

	//drain some charge
	if(cell) cell.emp_act(packet.severity + 15)

	//possibly damage some modules
	take_hit((100/packet.severity), "electrical pulse", 1)

/obj/item/rig/proc/shock(mob/user)
	if (electrocute_mob(user, cell, src)) //electrocute_mob() handles removing charge from the cell, no need to do that here.
		fx_sparks(src, 5, FALSE)
		if(user.has_status(STAT_STUNNED))
			return 1
	return 0

/obj/item/rig/proc/take_hit(damage, source, is_emp=0)

	if(!length(installed_modules))
		return

	var/chance
	if(!is_emp)
		chance = 2*max(0, damage - (chest? chest.breach_threshold : 0))
	else
		//Want this to be roughly independant of the number of modules, meaning that X emp hits will disable Y% of the suit's modules on average.
		//that way people designing hardsuits don't have to worry (as much) about how adding that extra module will affect emp resiliance by 'soaking' hits for other modules
		chance = 2*max(0, damage - emp_protection)*min(length(installed_modules)/15, 1)

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

	if(wearer())
		if(dam_module.damage >= 2)
			to_chat(wearer(), span_danger("The [source] has disabled your [dam_module.interface_name]!"))
		else
			to_chat(wearer(), span_warning("The [source] has damaged your [dam_module.interface_name]!"))
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
		if(!(locate_within(src, /obj/item/rig_module/ai_container)))
			return 0
		var/found_ai
		for(var/obj/item/rig_module/ai_container/module in contents)
			if(module.damage >= 2)
				continue
			if(module.integrated_ai() && module.integrated_ai().client && !module.integrated_ai().stat)
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
	if(!wearer() || (wearer().get_equipped_item(SLOT_ID_BACK) != src && wearer().get_equipped_item(SLOT_ID_BELT) != src))
		if(user)
			to_chat(user, span_warning("Your host rig is not being worn."))
		return 0
	if(!wearer().stat && !control_overridden && !ai_override_enabled)
		if(user)
			to_chat(user, span_warning("You are locked out of the suit servo controller."))
		return 0
	return 1

/obj/item/rig/proc/force_rest(mob/user)
	if(!ai_can_move_suit(user, check_user_module = 1))
		return
	wearer().lay_down()
	to_chat(user, span_notice("\The [wearer()] is now [wearer().resting ? "resting" : "getting up"]."))

/obj/item/rig/proc/forced_move(direction, mob/user, ai_moving = TRUE)

	// Why is all this shit in client/Move()? Who knows?
	if(!COOLDOWN_FINISHED(src, wearer_move_delay))
		return

	if(!wearer() || !wearer().loc) // Removed some stuff for protean living hardsuit
		return

// Added this for protean living hardsuit
	COOLDOWN_START(src, wearer_move_delay, 0.2 SECONDS)
	if(ai_moving)
		if(!ai_can_move_suit(user, check_user_module = 1))
			return
		// AIs are a bit slower than regular and ignore move intent.
		// Moved this to where it's relevant
		COOLDOWN_START(src, wearer_move_delay, ai_controlled_move_delay)

	//This is sota the goto stop mobs from moving var
	if(wearer().transforming || !wearer().canmove)
		return

	if((istype(wearer().loc, /turf/space)) || (wearer().lastarea.get_gravity() == 0))
		if(!wearer().Process_Spacemove(0))
			return 0

	if(malfunctioning)
		direction = pick(GLOB.cardinal)

	// Inside an object, tell it we moved.
	if(isobj(wearer().loc) || ismob(wearer().loc))
		var/atom/O = wearer().loc
		return O.relaymove(wearer(), direction)

	if(isturf(wearer().loc))
		if(wearer().restrained())//Why being pulled while cuffed prevents you from moving
			for(var/mob/M in range(wearer(), 1))
				if(M?.pulling_target() == wearer())
					if(!M.restrained() && M.stat == 0 && M.canmove && wearer().Adjacent(M))
						to_chat(user, span_notice("Your host is restrained! They can't move!"))
						return 0
					else
						M.stop_pulling()

	if(LAZYLEN(wearer().pinned))
		to_chat(src, span_notice("Your host is pinned to a wall by [wearer().pinned[1]]!"))
		return 0

	if(istype(wearer()?.buckled_to(), /obj/vehicle))
		//manually set move_delay for vehicles so we don't inherit any mob movement penalties
		//specific vehicle move delays are set in code\modules\vehicles\vehicle.dm
		EXPIRY_STAMP(src, wearer_move_delay, CLOCK_WORLD)
		var/atom/movable/_tmp_buck_13 = wearer()?.buckled_to()
		return _tmp_buck_13.relaymove(wearer(), direction)

	if(istype(wearer().get_current_machine(), /obj/machinery))
		if(wearer().get_current_machine().relaymove(wearer(), direction))
			return

	var/mob/wearer_puller = wearer()?.pulled_by_mob()
	if(wearer_puller || wearer()?.buckled_to()) // Wheelchair driving!
		if(istype(wearer().loc, /turf/space))
			return // No wheelchair driving in space
		if(istype(wearer_puller, /obj/structure/bed/chair/wheelchair))
			return wearer_puller.relaymove(wearer(), direction)
		else if(istype(wearer()?.buckled_to(), /obj/structure/bed/chair/wheelchair))
			if(ishuman(wearer()?.buckled_to()))
				var/obj/item/organ/external/l_hand = wearer().get_organ(BP_L_HAND)
				var/obj/item/organ/external/r_hand = wearer().get_organ(BP_R_HAND)
				if((!l_hand || (l_hand.status & ORGAN_DESTROYED)) && (!r_hand || (r_hand.status & ORGAN_DESTROYED)))
					return // No hands to drive your chair? Tough luck!
			wearer_move_delay += 2
			var/atom/movable/_tmp_buck_14 = wearer()?.buckled_to()
			return _tmp_buck_14.relaymove(wearer(),direction)

	var/power_cost = 50
	if(!ai_moving)
		power_cost = 20
	draw_power(power_cost / CELLRATE, wearer(), partial = TRUE)
	wearer().Move(get_step(get_turf(wearer()),direction),direction)

// This returns the rig if you are contained inside one, but not if you are wearing it
/atom/proc/get_rig()
	if(loc)
		return loc.get_rig()
	return null

/obj/item/rig/get_rig()
	return src

/mob/living/carbon/human/get_rig()
	if(istype(get_equipped_item(SLOT_ID_BACK), /obj/item/rig))
		return get_equipped_item(SLOT_ID_BACK)
	else if(istype(get_equipped_item(SLOT_ID_BELT), /obj/item/rig))
		return get_equipped_item(SLOT_ID_BELT)
	else
		return null

/atom/proc/get_voidsuit()
	return null

/mob/living/carbon/human/get_voidsuit()
	if(istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space/void))
		return get_equipped_item(SLOT_ID_SUIT)
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

/// The boot-up HUD's last piece leaves the screen once the seals finish.
/proc/rig_boot_hud_clear(mob/M, atom/movable/screen/booting_R)
	M.client?.screen -= booting_R
	consume(booting_R, M)

/obj/item/rig/ownership()
	. = ..()
	. += owns(nameof(air_supply), policy = OWN_CONTAINED)
	. += owns(nameof(cell), policy = OWN_CONTAINED)
	. += owns(nameof(installed_modules), policy = OWN_CONTAINED, is_list = TRUE)
	. += owns(nameof(rig_storage), policy = OWN_CONTAINED)

/// The person currently wearing the rig. (a relation view: null once it is deleted).
/obj/item/rig/proc/wearer() as /mob/living/carbon/human
	return wearer
