
ADMIN_VERB(Debug2, R_DEBUG, "Debug-Game", "Toggles debug level 2, might be quite spammy.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	if(GLOB.Debug2)
		GLOB.Debug2 = FALSE
		message_admins("[key_name(user)] toggled debugging off.")
		log_admin("[key_name(user)] toggled debugging off.")
	else
		GLOB.Debug2 = TRUE
		message_admins("[key_name(user)] toggled debugging on.")
		log_admin("[key_name(user)] toggled debugging on.")

	feedback_add_details("admin_verb","DG2") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

// callproc moved to code/modules/admin/callproc

ADMIN_VERB(simple_DPS, R_DEBUG, "Simple DPS", "Gives a really basic idea of how much hurt something in-hand does.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/obj/item/I = null
	var/mob/living/user_mob = user.mob
	if(!istype(user_mob))
		to_chat(user, span_warning("You need to be a living mob, with hands, and for an object to be in your active hand, to use this verb."))
		return

	I = user_mob.get_active_hand()
	if(!I || !istype(I))
		to_chat(user, span_warning("You need to have something in your active hand, to use this verb."))
		return
	var/weapon_attack_speed = user_mob.get_attack_speed(I) / 10
	var/modified_damage_percent = user_mob.factor(BF_MELEE_DAMAGE)
	var/weapon_damage = I.force * modified_damage_percent

	if(istype(I, /obj/item/gun))
		var/obj/item/gun/G = I
		var/obj/item/projectile/P

		if(istype(I, /obj/item/gun/energy))
			var/obj/item/gun/energy/energy_gun = G
			P = new energy_gun.projectile_type()

		else if(istype(I, /obj/item/gun/projectile))
			var/obj/item/gun/projectile/projectile_gun = G
			var/obj/item/ammo_casing/ammo = projectile_gun.chambered
			P = ammo.BB

		else
			to_chat(user, span_warning("DPS calculation by this verb is not supported for \the [G]'s type. Energy or Ballistic only, sorry."))

		weapon_damage = P.damage
		weapon_attack_speed = G.fire_delay / 10
		spent(P)

	var/DPS = weapon_damage / weapon_attack_speed
	to_chat(user, span_notice("Damage: [weapon_damage][modified_damage_percent != 1 ? " (Modified by [modified_damage_percent*100]%)":""]"))
	to_chat(user, span_notice("Attack Speed: [weapon_attack_speed]/s"))
	to_chat(user, span_notice("\The [I] does <b>[DPS]</b> damage per second."))
	if(DPS > 0)
		// There is no single health number any more: crit and death come from the body's
		// afflictions. Endurance is the closest toughness scale.
		var/endurance = user_mob.get_endurance()
		to_chat(user, span_notice("At your endurance ([endurance]), it would take approximately;"))
		to_chat(user, span_notice("[endurance / DPS] seconds to deal damage equal to your endurance."))
		to_chat(user, span_notice("[(endurance * 2) / DPS] seconds to deal twice your endurance (lethal for machines)."))


ADMIN_VERB(Cell, R_DEBUG, "Cell", "Display the atmos information of the current cell.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/turf/T = get_turf(user.mob)

	if (!(isturf(T)))
		return

	var/datum/gas_mixture/env = T.return_air()

	var/env_temperature = env.return_temperature()
	var/env_volume = env.return_volume()
	var/t = span_blue("Coordinates: [T.x],[T.y],[T.z]\n")
	t += span_red("Temperature: [env_temperature]\n")
	t += span_red("Pressure: [env.return_pressure()]kPa\n")
	// was env.gas[g] (XGM); under LINDA/auxmos, iterate get_gases() (id -> moles).
	for(var/datum/gas/g as anything in env.get_gases())
		var/moles = env.get_moles(g)
		t += span_blue("[g]: [moles] / [moles * R_IDEAL_GAS_EQUATION * env_temperature / env_volume]kPa\n")

	user.mob.show_message(t, 1)
	feedback_add_details("admin_verb","ASL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(debug_atmospherics, R_DEBUG, "Debug Atmospherics", "Opens the SSair debug panel (excited groups, active turfs, fire count, freeze).", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	SSair.tgui_interact(user.mob)
	feedback_add_details("admin_verb","DBGATMOS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(trace_injury_mitigation, R_DEBUG, "Trace Injury Mitigation", "Toggle a per-hit breakdown of a mob's injury mitigation (armour, shields, factors, species) in your chat and the debug log.", ADMIN_CATEGORY_DEBUG_INVESTIGATE, mob/living/target in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!istype(target))
		return
	if(user in target.injury_trace)
		LAZYREMOVE(target.injury_trace, user)
		to_chat(user, span_notice("No longer tracing injury mitigation on [target]."))
	else
		LAZYADD(target.injury_trace, user)
		to_chat(user, span_notice("Tracing injury mitigation on [target]: every injure() call reports each stage."))
	log_admin("[key_name(user)] toggled injury mitigation tracing on [key_name(target)].")
	feedback_add_details("admin_verb","TRACEINJ") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_robotize, R_ADMIN|R_EVENT|R_DEBUG, "Make Robot", "Turns the target into a robot.", ADMIN_CATEGORY_FUN_EVENT_KIT, mob/living/carbon/human/target_human in REGISTRY_MEMBERS(REGISTRY_HUMANS))
	if(!SSticker)
		tgui_alert_async(user, "Wait until the game starts")
		return
	if(!ishuman(target_human))
		tgui_alert_async(user, "Invalid mob")
		return

	log_admin("[key_name(user)] has robotized [target_human.key].")
	after(target_human, 1 SECOND, TYPE_PROC_REF(/mob/living/carbon/human, Robotize))

ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_animalize, R_ADMIN|R_EVENT|R_DEBUG, "Make Simple Animal", "Spawns a new player directly as animal.", ADMIN_CATEGORY_FUN_EVENT_KIT, mob/target_mob in REGISTRY_MEMBERS(REGISTRY_MOBS))
	if(!SSticker)
		tgui_alert_async(user, "Wait until the game starts")
		return

	if(!target_mob)
		tgui_alert_async(user, "That mob doesn't seem to exist, close the panel and try again.")
		return

	if(isnewplayer(target_mob))
		tgui_alert_async(user, "The mob must not be a new_player.")
		return

	log_admin("[key_name(user)] has animalized [target_mob.key].")
	after(target_mob, 1 SECOND, TYPE_PROC_REF(/mob, Animalize))

ADMIN_VERB(makepAI, R_ADMIN|R_EVENT|R_DEBUG, "Make pAI", "Spawn someone in as a pAI!", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/list/available = list()
	for(var/mob/current_client in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(current_client.key && isobserver(current_client))
			available += current_client
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_pai_player, PROC_REF(pai_player_chosen), answerer = answerer, choices = available)

/datum/admin_verb/makepAI/proc/pai_player_chosen(datum/act/request/A)
	if(!A.answer)
		return
	make_chosen_pai(A)

/datum/admin_verb/makepAI/proc/make_chosen_pai(datum/act/request/A)
	var/mob/choice = A.request.value
	var/client/user = A.request.answerer.client
	var/turf/target_turf = get_turf(user.mob)
	var/obj/item/paicard/typeb/card = new(target_turf)
	var/mob/living/silicon/pai/pai = new(card)
	pai.real_name = pai.name
	pai.key = choice.key
	card.setPersonality(pai)
	// The new pAI answers these in its own time.
	pai.offer_admin_spawn_load()
	log_admin("made a pAI with key=[pai.key] at ([target_turf.x],[target_turf.y],[target_turf.z])")
	feedback_add_details("admin_verb","MPAI") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/// An admin-spawned pAI loads its saved data, or else names itself.
/mob/living/silicon/pai/proc/offer_admin_spawn_load()
	open_request(src, /datum/prompt/yes_no, PROC_REF(admin_spawn_load_chosen), answerer = src, title = "Load", question = "Do you want to load your pAI data?", timeout = 0)

/mob/living/silicon/pai/proc/admin_spawn_load_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		apply_preferences(client)
		return
	open_request(src, /datum/prompt/text, PROC_REF(admin_spawn_name_entered), answerer = src, title = "pAI Name", question = "Enter your pAI name:", default = "Personal AI", encode = FALSE, timeout = 0)

/mob/living/silicon/pai/proc/admin_spawn_name_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_name = sanitizeName(A.answer.value, allow_numbers = TRUE)
	if(new_name)
		name = new_name

ADMIN_VERB_AND_CONTEXT_MENU(cmd_admin_alienize, R_ADMIN|R_EVENT|R_DEBUG, "Make Alien", "Turns the target into an alien.", ADMIN_CATEGORY_FUN_EVENT_KIT, mob/living/carbon/human/target_human in REGISTRY_MEMBERS(REGISTRY_HUMANS))
	if(!SSticker)
		tgui_alert_async(user, "Wait until the game starts")
		return
	if(!ishuman(target_human))
		tgui_alert_async(user, "Invalid mob")
		return

	log_admin("[key_name(user)] has alienized [target_human.key].")
	after(target_human, 1 SECOND, TYPE_PROC_REF(/mob/living/carbon/human, Alienize))
	feedback_add_details("admin_verb","MKAL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(user)] made [key_name(target_human)] into an alien.")
	message_admins(span_notice("[key_name_admin(user)] made [key_name(target_human)] into an alien."))

//TODO: merge the vievars version into this or something maybe mayhaps
ADMIN_VERB(cmd_debug_del_all, R_SERVER, "Del-All", "DANGER: Deletes all instances of a type.", ADMIN_CATEGORY_DEBUG_DANGEROUS)
	// to prevent REALLY stupid deletions
	var/blocked = list(/obj, /mob, /mob/living, /mob/living/carbon, /mob/living/carbon/human, /mob/observer/dead, /mob/living/silicon, /mob/living/silicon/robot, /mob/living/silicon/ai)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_delete_type, PROC_REF(delete_type_chosen), answerer = answerer, choices = typesof(/obj) + typesof(/mob) - blocked)

/datum/admin_verb/cmd_debug_del_all/proc/delete_type_chosen(datum/act/request/A)
	if(!A.answer)
		return
	delete_type_answered(A)

/datum/admin_verb/cmd_debug_del_all/proc/delete_type_answered(datum/act/request/A)
	var/hsbitem = A.request.value
	var/client/user = A.request.answerer.client
	if(hsbitem)
		for(var/atom/O in world)
			if(istype(O, hsbitem))
				spent(O)
		log_admin("[key_name(user)] has deleted all instances of [hsbitem].")
		message_admins("[key_name_admin(user)] has deleted all instances of [hsbitem].", 0)
	feedback_add_details("admin_verb","DELA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_debug_make_powernets, R_DEBUG, "Make Powernets", "Send every cable and power machine to the power network again.", ADMIN_CATEGORY_DEBUG_DANGEROUS)
	SSmachines.power_reregister_all()
	log_admin("[key_name(user)] has remade the power network.")
	message_admins("[key_name_admin(user)] has remade the power network.")
	feedback_add_details("admin_verb","MPWN") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_debug_tog_aliens, R_DEBUG, "Toggle Aliens", "Toggle if aliens are allowed.", ADMIN_CATEGORY_SERVER_GAME)
	CONFIG_SET(flag/aliens_allowed, !CONFIG_GET(flag/aliens_allowed))
	log_admin("[key_name(user)] has turned aliens [CONFIG_GET(flag/aliens_allowed) ? "on" : "off"].")
	message_admins("[key_name_admin(user)] has turned aliens [CONFIG_GET(flag/aliens_allowed) ? "on" : "off"].")
	feedback_add_details("admin_verb","TAL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(cmd_display_del_log, R_DEBUG, "Display del() Log", "Display del's log of everything that's passed through it.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/list/dellog = list(span_bold("List of things that have gone through qdel this round") + "<BR><BR><ol>")
	sortTim(SSgarbage.items, cmp=/proc/cmp_qdel_item_time, associative = TRUE)
	for(var/path in SSgarbage.items)
		var/datum/qdel_item/I = SSgarbage.items[path]
		dellog += "<li><u>[path]</u><ul>"
		if (I.failures)
			dellog += "<li>Failures: [I.failures]</li>"
		dellog += "<li>qdel() Count: [I.qdels]</li>"
		dellog += "<li>Destroy() Cost: [I.destroy_time]ms</li>"
		if (I.hard_deletes)
			dellog += "<li>Total Hard Deletes [I.hard_deletes]</li>"
			dellog += "<li>Time Spent Hard Deleting: [I.hard_delete_time]ms</li>"
		if (I.slept_destroy)
			dellog += "<li>Sleeps: [I.slept_destroy]</li>"
		if (I.no_respect_force)
			dellog += "<li>Ignored force: [I.no_respect_force]</li>"
		if (I.no_hint)
			dellog += "<li>No hint: [I.no_hint]</li>"
		dellog += "</ul></li>"

	dellog += "</ol>"

	// structured TGUI AdminReport.
	dq_admin_report_html(user, "qdel() Log", dellog.Join())

ADMIN_VERB(cmd_display_init_log, R_DEBUG, "Display Initialize() Log", "Displays a list of things that didn't handle Initialize() properly.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	// structured TGUI AdminReport.
	dq_admin_report_html(user, "Initialize() Log", replacetext(SSatoms.InitLog(), "\n", "<br>"))

ADMIN_VERB(cmd_display_overlay_log, R_DEBUG, "Display overlay Log", "Display SSoverlays log of everything that's passed through it.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	render_stats(SSoverlays.stats, user)

// Render stats list for round-end statistics.
/proc/render_stats(list/stats, user, sort = /proc/cmp_generic_stat_item_time)
	sortTim(stats, sort, TRUE)

	var/list/lines = list()
	for (var/entry in stats)
		var/list/data = stats[entry]
		lines += "[entry] => [num2text(data[STAT_ENTRY_TIME], 10)]ms ([data[STAT_ENTRY_COUNT]]) (avg:[num2text(data[STAT_ENTRY_TIME]/(data[STAT_ENTRY_COUNT] || 1), 99)])"

	if (user)
		// structured TGUI AdminReport.
		dq_admin_report_lines(user, "Stats", lines)
	else
		. = lines.Join("\n")

ADMIN_VERB(cmd_admin_grantfullaccess, (R_ADMIN|R_EVENT), "Grant Full Access", "Grants full access to a human.", ADMIN_CATEGORY_EVENTS, mob/living/carbon/human/H in REGISTRY_MEMBERS(REGISTRY_HUMANS))
	if (!SSticker)
		tgui_alert_async(user, "Wait until the game starts")
		return
	if (H.get_equipped_item(SLOT_ID_ID))
		var/obj/item/card/id/id = H.get_equipped_item(SLOT_ID_ID)
		if(istype(H.get_equipped_item(SLOT_ID_ID), /obj/item/pda))
			var/obj/item/pda/pda = H.get_equipped_item(SLOT_ID_ID)
			id = pda.id
		id.icon_state = "gold"
		id.access = SSaccess.get_all_accesses().Copy()
	else
		var/obj/item/card/id/id = new/obj/item/card/id(H);
		id.icon_state = "gold"
		id.access = SSaccess.get_all_accesses().Copy()
		id.registered_name = H.real_name
		id.assignment = JOB_SITE_MANAGER
		id.name = "[id.registered_name]'s ID Card ([id.assignment])"
		H.equip_to_slot_or_del(id, SLOT_ID_ID)
		H.update_inv_wear_id()
	feedback_add_details("admin_verb","GFA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	log_admin("[key_name(user)] has granted [H.key] full access.")
	message_admins(span_blue("[key_name_admin(user)] has granted [H.key] full access."))

ADMIN_VERB(cmd_assume_direct_control, (R_DEBUG|R_ADMIN|R_EVENT), "Assume Direct Control", "Assume direct control of a mob.", ADMIN_CATEGORY_GAME, mob/M)
	if(M.ckey)
		var/mob/answerer = user.mob
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/admin_control_target, PROC_REF(control_confirmed), answerer = answerer, controlled_mob = M, question = "This mob is being controlled by [M.ckey]. Are you sure you wish to assume control of it? [M.ckey] will be made a ghost.")
		return
	apply_control(user, M)

/datum/admin_verb/cmd_assume_direct_control/proc/control_confirmed(datum/act/request/context)
	if(!context.answer)
		return
	finish_control(context)

/datum/admin_verb/cmd_assume_direct_control/proc/finish_control(datum/act/request/context)
	var/datum/prompt/choice/admin_control_target/request = context.request
	var/mob/M = request.controlled_mob
	if(M.ckey && request.value != "Yes")
		return
	apply_control(request.answerer.client, M)

/datum/admin_verb/cmd_assume_direct_control/proc/apply_control(client/user, mob/M)
	if(!M || QDELETED(M))
		to_chat(user, span_warning("The target mob no longer exists."))
		return

	var/mob/observer/dead/ghost = new/mob/observer/dead(M,1)
	ghost.ckey = M.ckey

	message_admins(span_blue("[key_name_admin(user)] assumed direct control of [M]."))
	log_admin("[key_name(user)] assumed direct control of [M].")
	var/mob/adminmob = user.mob
	M.ckey = user.ckey
	if( isobserver(adminmob) )
		replaced_by(adminmob, M)
	feedback_add_details("admin_verb","ADC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(take_picture, R_DEBUG, "Save PNG", "Opens a dialog to save a PNG of any object in the game.", ADMIN_CATEGORY_DEBUG_MISC, atom/selected_atom in world)
	downloadImage(selected_atom, null, user)

ADMIN_VERB_VISIBILITY(cmd_admin_areatest, ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST)
ADMIN_VERB(cmd_admin_areatest, R_DEBUG, "Test areas", "Manually tests all areas and prints to world (Only use on a test server).", ADMIN_CATEGORY_MAPPING_TESTS)
	var/list/areas_all = list()
	var/list/areas_with_APC = list()
	var/list/areas_with_air_alarm = list()
	var/list/areas_with_RC = list()
	var/list/areas_with_light = list()
	var/list/areas_with_LS = list()
	var/list/areas_with_intercom = list()
	var/list/areas_with_camera = list()

	for(var/area/A in world)
		if(!(A.type in areas_all))
			areas_all.Add(A.type)

	for(var/obj/machinery/power/apc/APC in REGISTRY_MEMBERS(REGISTRY_APCS))
		var/area/A = get_area(APC)
		if(A && !(A.type in areas_with_APC))
			areas_with_APC.Add(A.type)

	for(var/obj/machinery/alarm/alarm in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		var/area/A = get_area(alarm)
		if(A && !(A.type in areas_with_air_alarm))
			areas_with_air_alarm.Add(A.type)

	for(var/obj/machinery/requests_console/RC in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		var/area/A = get_area(RC)
		if(A && !(A.type in areas_with_RC))
			areas_with_RC.Add(A.type)

	for(var/obj/machinery/light/L in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		var/area/A = get_area(L)
		if(A && !(A.type in areas_with_light))
			areas_with_light.Add(A.type)

	for(var/obj/machinery/light_switch/LS in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		var/area/A = get_area(LS)
		if(A && !(A.type in areas_with_LS))
			areas_with_LS.Add(A.type)

	for(var/obj/item/radio/intercom/I in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		var/area/A = get_area(I)
		if(A && !(A.type in areas_with_intercom))
			areas_with_intercom.Add(A.type)

	for(var/obj/machinery/camera/C in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		var/area/A = get_area(C)
		if(A && !(A.type in areas_with_camera))
			areas_with_camera.Add(A.type)

	var/list/areas_without_APC = areas_all - areas_with_APC
	var/list/areas_without_air_alarm = areas_all - areas_with_air_alarm
	var/list/areas_without_RC = areas_all - areas_with_RC
	var/list/areas_without_light = areas_all - areas_with_light
	var/list/areas_without_LS = areas_all - areas_with_LS
	var/list/areas_without_intercom = areas_all - areas_with_intercom
	var/list/areas_without_camera = areas_all - areas_with_camera

	to_chat(world, span_bold("AREAS WITHOUT AN APC:"))
	for(var/areatype in areas_without_APC)
		to_chat(world, "* [areatype]")

	to_chat(world, span_bold("AREAS WITHOUT AN AIR ALARM:"))
	for(var/areatype in areas_without_air_alarm)
		to_chat(world, "* [areatype]")

	to_chat(world, span_bold("AREAS WITHOUT A REQUEST CONSOLE:"))
	for(var/areatype in areas_without_RC)
		to_chat(world, "* [areatype]")

	to_chat(world, span_bold("AREAS WITHOUT ANY LIGHTS:"))
	for(var/areatype in areas_without_light)
		to_chat(world, "* [areatype]")

	to_chat(world, span_bold("AREAS WITHOUT A LIGHT SWITCH:"))
	for(var/areatype in areas_without_LS)
		to_chat(world, "* [areatype]")

	to_chat(world, span_bold("AREAS WITHOUT ANY INTERCOMS:"))
	for(var/areatype in areas_without_intercom)
		to_chat(world, "* [areatype]")

	to_chat(world, span_bold("AREAS WITHOUT ANY CAMERAS:"))
	for(var/areatype in areas_without_camera)
		to_chat(world, "* [areatype]")

ADMIN_VERB(cmd_admin_dress, R_FUN, "elect equipment", "Select equipment for a mob.", ADMIN_CATEGORY_FUN_EVENT_KIT, input)
	if(!input)
		var/mob/answerer = user.mob
		if(QDELETED(answerer))
			return
		open_request(src, /datum/prompt/choice/admin_dress_target, PROC_REF(dress_target_selected), answerer = answerer, choices = getmobs())
		return
	ask_outfit(user, input)

/datum/admin_verb/cmd_admin_dress/proc/dress_target_selected(datum/act/request/context)
	if(!context.answer)
		return
	open_selected_outfit(context)

/datum/admin_verb/cmd_admin_dress/proc/open_selected_outfit(datum/act/request/context)
	var/input = context.request.value
	if(!input)
		return
	ask_outfit(context.request.answerer.client, input)

/datum/admin_verb/cmd_admin_dress/proc/ask_outfit(client/user, input)
	var/target = getmobs()[input]
	if(!ishuman(target))
		return
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_dress_outfit, PROC_REF(outfit_selected), answerer = answerer, choices = GLOB.outfits_decls, target_label = input)

/datum/admin_verb/cmd_admin_dress/proc/outfit_selected(datum/act/request/context)
	if(!context.answer)
		return
	dress_selected_outfit(context)

/datum/admin_verb/cmd_admin_dress/proc/dress_selected_outfit(datum/act/request/context)
	var/datum/prompt/choice/admin_dress_outfit/request = context.request
	var/target = getmobs()[request.target_label]
	if(!ishuman(target))
		return
	var/mob/living/carbon/human/target_human = target
	var/datum/decl/hierarchy/outfit/outfit = request.value
	if(!outfit)
		return
	feedback_add_details("admin_verb","SEQ")
	dressup_human(target_human, outfit, request.answerer)

/proc/dressup_human(mob/living/carbon/human/H, datum/decl/hierarchy/outfit/outfit, mob/user)
	if(!H || !outfit)
		return
	if(outfit.undress)
		H.delete_inventory()
	outfit.equip(H)
	log_and_message_admins("changed the equipment of [key_name(H)] to [outfit.name].", user)

/// "Setup supermatter" brings the crystal up to a working power shortly after the rest of the engine room is set.
/proc/admin_boost_supermatter(obj/machinery/power/supermatter/SM)
	if(SM)
		SM.power = 320

ADMIN_VERB(startSinglo, R_DEBUG|R_ADMIN, "Start Singularity", "Sets up the singularity and all machines to get power flowing through the station.", ADMIN_CATEGORY_DEBUG_GAME)
	// Only this verb's actual ended native request supplies replay answers.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if((istype(resumed, /datum/prompt/choice/admin_singularity_replay)) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(startSinglo_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!("a5" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_singularity_replay, PROC_REF(startSinglo_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a5", buttons = TRUE, question = "Are you sure? This will start up the engine. Should only be used during debug!", title = "Start Singularity", choices = list("Yes","No"))
		return
	var/_answer_a5 = replay_answers["a5"]
	if(isnull(_answer_a5))
		return
	if(_answer_a5 != "Yes")
		return

	for(var/obj/machinery/power/emitter/E in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(istype(get_area(E), /area/space))
			E.anchored = TRUE
			E.state = 2
			E.connect_to_network()
			E.set_active(TRUE)
	for(var/obj/machinery/field_generator/F in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(istype(get_area(F), /area/space))
			F.set_Varedit_start(TRUE)
	for(var/obj/machinery/power/grounding_rod/GR in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		GR.set_anchored(TRUE)
	for(var/obj/machinery/power/tesla_coil/TC in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		TC.set_anchored(TRUE)
	for(var/obj/structure/particle_accelerator/PA in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		PA.anchored = TRUE
		graph_place(PA, STAGE_PA_CLOSED)
	for(var/obj/machinery/particle_accelerator/PA in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		PA.anchored = TRUE
		graph_place(PA, STAGE_PA_CLOSED)

	// /obj/machinery/power/rad_collector was deleted with the ZAS power
	// machinery; this loop is a no-op until LINDA's equivalent is wired.
	log_admin("[key_name(user)] setup the singulo engine")
	message_admins(span_blue("[key_name_admin(user)] setup the singulo engine"))

ADMIN_VERB(setup_supermatter_engine, R_DEBUG|R_ADMIN, "Setup supermatter", "Sets up the supermatter engine.", ADMIN_CATEGORY_DEBUG_GAME)
	var/mob/answerer = user.mob
	if(!answerer || QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_supermatter_setup, PROC_REF(supermatter_setup_answered), answerer = answerer)

/datum/admin_verb/setup_supermatter_engine/proc/supermatter_setup_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/client/user = context.request.answerer?.client
	if(!user)
		return
	if(supermatter_setup_advanced_call(context.request.answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(!admin_can(user, permissions))
		admin_log_denial(user, "verb:[src.type]", permissions)
		to_chat(user, span_adminnotice("You lack the permissions to do this."))
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	var/response = context.answer.value
	if(isnull(response))
		return

	if(!response || response == "No")
		return

	var/found_the_pump = 0
	var/obj/machinery/power/supermatter/SM

	for(var/obj/machinery/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(!M)
			continue
		if(!M.loc)
			continue
		if(!M.loc.loc)
			continue

		if(istype(M.loc.loc,/area/engineering/engine_room))
			// rad_collector and ZAS binary/pump removed; supermatter only.
			if(istype(M,/obj/machinery/power/supermatter))
				SM = M
				after(SM, 5 SECONDS, GLOBAL_PROC_REF(admin_boost_supermatter), with = list(SM))

			else if(istype(M,/obj/machinery/power/smes))	//This is the SMES inside the engine room.  We don't need much power.
				var/obj/machinery/power/smes/SMES = M
				SMES.set_input_attempt(1)
				SMES.set_input_level(200000)
				SMES.set_output_level(75000)

		else if(istype(M.loc.loc,/area/engineering/engine_smes))	//Set every SMES to charge and spit out 300,000 power between the 4 of them.
			if(istype(M,/obj/machinery/power/smes))
				var/obj/machinery/power/smes/SMES = M
				SMES.set_input_attempt(1)
				SMES.set_input_level(200000)
				SMES.set_output_level(75000)

	if(!found_the_pump && response == "Setup Completely")
		to_chat(src, span_red("Unable to locate air supply to fill up with coolant, adding some coolant around the supermatter"))
		var/turf/simulated/T = SM.loc
		// was XGM `T.zone.air`; LINDA stores gases on the turf itself.
		// Use the turf's own air mixture via return_air().
		var/datum/gas_mixture/_air = T.return_air()
		if(_air)
			LINDA_GAS_ADJUST(_air, GAS_N2, 450)
			heat_set(_air, 50)


	log_admin("[key_name(user)] setup the supermatter engine [response == "Setup except coolant" ? "without coolant" : ""]")
	message_admins(span_blue("[key_name_admin(user)] setup the supermatter engine  [response == "Setup except coolant" ? "without coolant": ""]"))


ADMIN_VERB(cmd_debug_mob_lists, R_DEBUG, "Debug Mob Lists", "For when you just gotta know.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_mob_list, PROC_REF(list_chosen), answerer = answerer)

/datum/admin_verb/cmd_debug_mob_lists/proc/list_chosen(datum/act/request/A)
	if(!A.answer)
		return
	show_chosen_list(A)

/datum/admin_verb/cmd_debug_mob_lists/proc/show_chosen_list(datum/act/request/A)
	var/client/user = A.request.answerer.client
	var/_answer_a7 = A.request.value
	switch(_answer_a7)
		if("Players")
			to_chat(user, span_filter_debuglogs(jointext(REGISTRY_MEMBERS(REGISTRY_PLAYERS),",")))
		if("Admins")
			to_chat(user, span_filter_debuglogs(jointext(GLOB.admins,",")))
		if("Mobs")
			to_chat(user, span_filter_debuglogs(jointext(REGISTRY_MEMBERS(REGISTRY_MOBS),",")))
		if("Living Mobs")
			to_chat(user, span_filter_debuglogs(jointext(REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS),",")))
		if("Dead Mobs")
			to_chat(user, span_filter_debuglogs(jointext(REGISTRY_MEMBERS(REGISTRY_DEAD_MOBS),",")))
		if("Clients")
			to_chat(user, span_filter_debuglogs(jointext(GLOB.clients,",")))

ADMIN_VERB(cmd_debug_using_map, R_DEBUG, "Debug Map Datum", "Debug the map metadata about the currently compiled in map.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	user.debug_variables(using_map)

// DNA2 - Admin Hax
/client/proc/cmd_admin_toggle_block(mob/M,block)
	if(!SSticker)
		tgui_alert_async(src, "Wait until the game starts")
		return
	if(istype(M, /mob/living/carbon))
		M.dna.SetSEState(block,!M.dna.GetSEState(block))
		domutcheck(M,null,MUTCHK_FORCED)
		M.UpdateAppearance()
		var/state="[M.dna.GetSEState(block)?"on":"off"]"
		var/blockname = GLOB.assigned_blocks[block]
		message_admins("[key_name_admin(src)] has toggled [M.key]'s [blockname] block [state]!")
		log_admin("[key_name(src)] has toggled [M.key]'s [blockname] block [state]!")
	else
		tgui_alert_async(src, "Invalid mob")

ADMIN_VERB(view_runtimes, R_DEBUG, "View Runtimes", "Opens the runtime viewer.", ADMIN_CATEGORY_DEBUG_INVESTIGATE)
	GLOB.error_cache.show_to(user)

	// The runtime viewer has the potential to crash the server if there's a LOT of runtimes
	// this has happened before, multiple times, so we'll just leave an alert on it
	if(GLOB.total_runtimes >= 50000) // arbitrary number, I don't know when exactly it happens
		var/warning = "There are a lot of runtimes, clicking any button (especially \"linear\") can have the potential to lag or crash the server"
		if(GLOB.total_runtimes >= 100000)
			warning = "There are a TON of runtimes, clicking any button (especially \"linear\") WILL LIKELY crash the server"
		// Not using TGUI alert, because it's view runtimes, stuff is probably broken
		if(user.mob?.client)
			open_request(user.mob, /datum/prompt/choice, null, answerer = user.mob, question = "[warning]. Proceed with caution. If you really need to see the runtimes, download the runtime log and view it in a text editor.", title = "HEED THIS WARNING CAREFULLY MORTAL", choices = list("Ok"), buttons = TRUE, timeout = 0)

ADMIN_VERB(change_weather, R_DEBUG|R_EVENT, "Change Weather", "Changes the current weather.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/datum/planet/planet = verb_ask(user, "a8", args, /datum/prompt/choice, question = "Which planet do you want to modify the weather on?", title = "Change Weather", choices = SSplanets.planets)
	if(isnull(planet))
		return
	if(!istype(planet))
		return
	var/datum/weather/new_weather = verb_ask(user, "a9", args, /datum/prompt/choice, question = "What weather do you want to change to?", title = "Change Weather", choices = planet.weather_holder.allowed_weather_types)
	if(isnull(new_weather))
		return
	if(!new_weather)
		return
	planet.weather_holder.change_weather(new_weather)
	planet.weather_holder.rebuild_forecast()
	var/log = "[key_name(user)] changed [planet.name]'s weather to [new_weather]."
	message_admins(log)
	log_admin(log)

ADMIN_VERB(toggle_firework_override, R_DEBUG|R_EVENT, "Toggle Weather Firework Override", "Toggles ability for weather fireworks to affect weather on planet of choice.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/datum/planet/planet
	var/datum/request/resumed = length(args) > 1 ? args[2] : null
	if(istype(resumed, /datum/prompt/choice/admin_firework_override) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(firework_override_answered))
		planet = resumed.value
	else
		open_request(src, /datum/prompt/choice/admin_firework_override, PROC_REF(firework_override_answered), answerer = user.mob, question = "Which planet do you want to toggle firework effects on?", title = "Change Weather", choices = SSplanets.planets)
		return
	if(isnull(planet))
		return
	if(istype(planet) && planet.weather_holder)
		planet.weather_holder.firework_override = !(planet.weather_holder.firework_override)
		var/log = "[key_name(user)] toggled [planet.name]'s firework override to [planet.weather_holder.firework_override ? "on" : "off"]."
		message_admins(log)
		log_admin(log)

ADMIN_VERB(change_time, R_DEBUG|R_EVENT, "Change Planet Time", "Changes the time of a planet.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/datum/planet/planet = verb_ask(user, "a11", args, /datum/prompt/choice, question = "Which planet do you want to modify time on?", title = "Change Time", choices = SSplanets.planets)
	if(isnull(planet))
		return
	if(!istype(planet))
		return
	var/datum/time/current_time_datum = planet.current_time
	var/planet_hours = max(round(current_time_datum.seconds_in_day / 36000) - 1, 0)
	var/new_hour = verb_ask(user, "a12", args, /datum/prompt/number, question = "What hour do you want to change to?", title = "Change Time", default = text2num(current_time_datum.show_time("hh")), max_value = planet_hours)
	if(isnull(new_hour))
		return
	if(isnull(new_hour))
		return
	var/planet_minutes = max(round(current_time_datum.seconds_in_hour / 600) - 1, 0)
	var/new_minute = verb_ask(user, "a13", args, /datum/prompt/number, question = "What minute do you want to change to?", title = "Change Time", default = text2num(current_time_datum.show_time("mm")), max_value = planet_minutes)
	if(isnull(new_minute))
		return
	if(isnull(new_minute))
		return
	var/type_needed = current_time_datum.type
	var/datum/time/new_time = new type_needed()
	new_time = new_time.add_hours(new_hour)
	new_time = new_time.add_minutes(new_minute)
	planet.current_time = new_time
	planet.update_sun()

	var/log = "[key_name(user)] changed [planet.name]'s time to [planet.current_time.show_time("hh:mm")]."
	message_admins(log)
	log_admin(log)

ADMIN_VERB(cmd_regenerate_asset_cache, R_DEBUG|R_SERVER, "Regenerate Asset Cache", "Clears the asset cache and regenerates it immediately.", ADMIN_CATEGORY_DEBUG_ASSETS)
	if(!CONFIG_GET(flag/cache_assets))
		to_chat(user, span_warning("Asset caching is disabled in the config!"))
		return
	var/regenerated = 0
	for(var/datum/asset/current_asset as anything in subtypesof(/datum/asset))
		if(!initial(current_asset.cross_round_cachable))
			continue
		if(current_asset == initial(current_asset._abstract))
			continue
		var/datum/asset/asset_datum = GLOB.asset_datums[current_asset]
		asset_datum.regenerate()
		regenerated++
	to_chat(user, span_notice("Regenerated [regenerated] asset\s."))

ADMIN_VERB(cmd_clear_smart_asset_cache, R_DEBUG|R_SERVER, "Clear Smart Asset Cache", "Clears the smart asset cache.", ADMIN_CATEGORY_DEBUG_ASSETS)
	if(!CONFIG_GET(flag/smart_cache_assets))
		to_chat(user, span_warning("Smart asset caching is disabled in the config!"))
		return
	var/cleared = 0
	for(var/datum/asset/spritesheet_batched/current_asset as anything in subtypesof(/datum/asset/spritesheet_batched))
		if(current_asset == initial(current_asset._abstract))
			continue
		fdel("[ASSET_CROSS_ROUND_SMART_CACHE_DIRECTORY]/spritesheet_cache.[initial(current_asset.name)].json")
		cleared++
	to_chat(user, span_notice("Cleared [cleared] asset\s."))

// For spriters with long world loads, allows to reload test robot sprites
ADMIN_VERB(cmd_reload_robot_sprite_test, R_DEBUG|R_SERVER, "Reload Robot Test Sprites", "Reloads the dmis from the test folder and creates the test datums.", ADMIN_CATEGORY_DEBUG_SPRITES)
	SSrobot_sprites.reload_test_sprites()

ADMIN_VERB(quick_nif, R_ADMIN, "Quick NIF", "Spawns a NIF into someone in quick-implant mode.", ADMIN_CATEGORY_FUN_ADD_NIF)
	var/input_NIF
	var/mob/living/carbon/human/H = verb_ask(user, "a14", args, /datum/prompt/choice, question = "Pick a mob with a player", title = "Quick NIF", choices = REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	if(isnull(H))
		return

	if(!H)
		return

	if(!istype(H))
		to_chat(user, span_warning("That mob type ([H.type]) doesn't support NIFs, sorry."))
		return

	if(!H.get_organ(BP_HEAD))
		to_chat(user, span_warning("Target is unsuitable."))
		return

	if(H.nif)
		to_chat(user, span_warning("Target already has a NIF."))
		return

	if(H.species.flags & NO_DNA)
		var/obj/item/nif/S = /obj/item/nif/bioadap
		input_NIF = initial(S.name)
		new /obj/item/nif/bioadap(H)
	else
		var/list/NIF_types = typesof(/obj/item/nif)
		var/list/NIFs = list()

		for(var/NIF_type in NIF_types)
			var/obj/item/nif/S = NIF_type
			NIFs[capitalize(initial(S.name))] = NIF_type

		var/list/show_NIFs = sortList(NIFs) // the list that will be shown to the user to pick from

		var/_answer_a15 = verb_ask(user, "a15", args, /datum/prompt/choice, question = "Pick the NIF type", title = "Quick NIF", choices = show_NIFs)
		if(isnull(_answer_a15))
			return
		input_NIF = _answer_a15
		var/chosen_NIF = NIFs[capitalize(input_NIF)]

		if(chosen_NIF)
			new chosen_NIF(H)
		else
			new /obj/item/nif(H)

	log_and_message_admins("Quick NIF'd [H.real_name] with a [input_NIF].", user)
	feedback_add_details("admin_verb","QNIF") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(reload_configuration, R_DEBUG, "Reload Configuration", "Reloads the configuration from the default path on the disk, wiping any in-round modifications.", ADMIN_CATEGORY_DEBUG_SERVER)
	// Replay input is only a synchronous answered request from this verb.
	var/list/replay_answers = list()
	if(length(args) > 1)
		var/datum/request/resumed = args[2]
		if(istype(resumed, /datum/prompt/choice/admin_reload_configuration_replay) && resumed.owner == src && resumed.answerer == user.mob && resumed.outcome == REQ_ANSWERED && !resumed.is_open() && !QDELETED(resumed) && resumed.handler == PROC_REF(reload_configuration_replay_answered))
			replay_answers = resumed.captured.Copy()
			replay_answers[resumed.step_name] = resumed.value
	if(!("a16" in replay_answers))
		open_request(src, /datum/prompt/choice/admin_reload_configuration_replay, PROC_REF(reload_configuration_replay_answered), answerer = user.mob, captured = replay_answers.Copy(), step_name = "a16", buttons = TRUE, question = "Are you absolutely sure you want to reload the configuration from the default path on the disk, wiping any in-round modifications?", title = "Really reset?", choices = list("No", "Yes"))
		return
	var/_answer_a16 = replay_answers["a16"]
	if(isnull(_answer_a16))
		return
	if(_answer_a16 != "Yes")
		return
	config.admin_reload(user)


/datum/admins/proc/quick_authentic_nif()
	set category = VERB_CAT_FUN_ADD_NIF
	set name = "Quick Auth NIF"
	set desc = "Spawns an authentic NIF into someone in quick-implant mode."

	if(!admin_require(owner(), R_ADMIN|R_EVENT|R_DEBUG, "quick_authentic_nif", TRUE)) // TFF 24/4/19: Allow Devs to use Quick-NIF verb.
		return

	open_request(src, /datum/prompt/choice, PROC_REF(quick_authentic_nif_chosen), answerer = usr, title = "Quick Authentic NIF", question = "Pick a mob with a player", choices = REGISTRY_MEMBERS(REGISTRY_PLAYERS), rights = R_ADMIN|R_EVENT|R_DEBUG, timeout = 0)

/datum/admins/proc/quick_authentic_nif_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/admin = A.request.answerer
	var/mob/living/carbon/human/H = A.answer.value
	if(!istype(H))
		to_chat(admin,span_warning("That mob type ([H.type]) doesn't support NIFs, sorry."))
		return

	if(!H.get_organ(BP_HEAD))
		to_chat(admin,span_warning("Target is unsuitable."))
		return

	if(H.nif)
		to_chat(admin,span_warning("Target already has a NIF."))
		return

	if(H.species.flags & NO_DNA)
		new /obj/item/nif/authenticbio(H)
	else
		new /obj/item/nif/authentic(H)

	log_and_message_admins("[key_name(src)] Quick Authentic NIF'd [H.real_name].")
	feedback_add_details("admin_verb","QANIF") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/prompt/choice/admin_delete_type
	rights = R_SERVER
	timeout = 0
	question = "Choose an object to delete."
	title = "Delete:"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_mob_list
	rights = R_DEBUG
	timeout = 0
	question = "Which list?"
	title = "List Choice"
	choices = list("Players", "Admins", "Mobs", "Living Mobs", "Dead Mobs", "Clients")
	recheck_on_open = TRUE

/datum/prompt/choice/admin_pai_player
	rights = R_ADMIN|R_EVENT|R_DEBUG
	timeout = 0
	question = "Choose a player to play the pAI"
	title = "Spawn pAI"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_pai_player/recheck_extra()
	. = ..()
	if(.)
		return
	if(!isnull(value))
		var/mob/picked = value
		if(QDELETED(picked) || !picked.key)
			return "chosen player is gone"

/datum/prompt/choice/admin_control_target
	rights = R_DEBUG|R_ADMIN|R_EVENT
	timeout = 0
	title = "Confirmation"
	choices = list("Yes", "No")
	buttons = TRUE
	var/mob/controlled_mob
	recheck_on_open = TRUE

CAPABILITIES(/datum/prompt/choice/admin_control_target)
	ref_one(nameof(controlled_mob), /mob)

/datum/prompt/choice/admin_control_target/prepare(datum/act/context)
	. = ..()
	var/mob/captured = controlled_mob
	rel_clear(src, nameof(controlled_mob))
	rel_set(src, nameof(controlled_mob), captured)

/datum/prompt/choice/admin_control_target/recheck_extra()
	. = ..()
	if(.)
		return
	return QDELETED(controlled_mob) ? "target is gone" : null

/datum/prompt/choice/admin_dress_target
	rights = R_FUN
	timeout = 0
	title = "Select the target to dress."
	question = "Pick Target"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_dress_outfit
	rights = R_FUN
	timeout = 0
	title = "Select equipment."
	question = "Select outfit."
	var/target_label
	recheck_on_open = TRUE

/datum/prompt/choice/admin_dress_outfit/recheck_extra()
	. = ..()
	if(.)
		return
	if(!isnull(value))
		var/datum/decl/hierarchy/outfit/picked = value
		return QDELETED(picked) ? "outfit is gone" : null


/datum/prompt/choice/admin_supermatter_setup
	timeout = 0
	recheck_on_open = TRUE
	rights = R_DEBUG|R_ADMIN
	buttons = TRUE
	question = "Are you sure? This will start up the engine. Should only be used during debug!"
	title = "Setup Supermatter"
	choices = list("Setup Completely", "Setup except coolant", "No")

/datum/prompt/choice/admin_supermatter_setup/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/proc/supermatter_setup_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/prompt/choice/admin_reload_configuration_replay
	timeout = 0
	rights = R_DEBUG
	recheck_on_open = TRUE

/datum/prompt/choice/admin_reload_configuration_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_reload_configuration_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_reload_configuration_replay/refusal(given)
	return null

/datum/admin_verb/reload_configuration/proc/reload_configuration_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/admin_singularity_replay
	timeout = 0
	rights = R_DEBUG|R_ADMIN
	recheck_on_open = TRUE

/datum/prompt/choice/admin_singularity_replay/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/prompt/choice/admin_singularity_replay/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/admin_singularity_replay/refusal(given)
	return null

/datum/admin_verb/startSinglo/proc/startSinglo_replay_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)

/datum/prompt/choice/admin_firework_override
	timeout = 0
	rights = R_DEBUG|R_EVENT
	recheck_on_open = TRUE

/datum/prompt/choice/admin_firework_override/normalize(given)
	if(isdatum(given))
		var/datum/selected = given
		if(QDELETED(selected))
			return null
	return given

/datum/prompt/choice/admin_firework_override/refusal(given)
	return null

/datum/prompt/choice/admin_firework_override/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return admin_can(answerer.client, 0) ? null : "no admin rights"

/datum/admin_verb/toggle_firework_override/proc/firework_override_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/actor = A.request.answerer
	var/client/user = actor?.client
	if(!user)
		return
	world.push_usr(actor, new /datum/callback(SSadmin_verbs, TYPE_PROC_REF(/datum/system/admin_verbs, dynamic_invoke_verb)), user, src.type, A.answer)
