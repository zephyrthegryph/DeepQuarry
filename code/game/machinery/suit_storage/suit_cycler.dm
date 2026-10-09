GLOBAL_LIST_EMPTY(suit_cycler_typecache)

/// If this is > 0, the cycler is decontaminating whatever is inside it (steps left).
/obj/machinery/suit_cycler/var/irradiating = 0
TRACKED_BRIDGED(/obj/machinery/suit_cycler, irradiating, CHANGE_MACHINE_SETTINGS)
/datum/scheduler_field_definition/obj/machinery/suit_cycler/irradiating
	of = /obj/machinery/suit_cycler
	field = "irradiating"
	channel = CHANGE_MACHINE_SETTINGS
/// Shocks the hand at it: the shock wire cut (until mended) or pulsed (30 s); live only while operable (shock_live()).
STAT(/obj/machinery/suit_cycler, electrified, TOP, base = 0)
/// Derived field: a UV cycle is running.
/obj/machinery/suit_cycler/proc/cycler_has_work()
	return active && irradiating > 0

/obj/machinery/suit_cycler
	name = "suit cycler"
	desc = "An industrial machine for painting and refitting voidsuits."
	anchored = TRUE
	density = TRUE

	icon = 'icons/obj/suit_cycler.dmi'
	icon_state = "suit_cycler"

	req_access = list(ACCESS_CAPTAIN,ACCESS_HEADS)

	active = 0          // PLEASE HOLD.
	var/radiation_level = 2 // 1 is removing germs, 2 is removing blood, 3 is removing phoron.
	var/model_text = ""     // Some flavour text for the topic box.
	locked = 1          // If locked, nothing can be taken from or added to the cycler.
	var/can_repair          // If set, the cycler can repair voidsuits.

	/// Departments that the cycler can paint suits to look like. Null assumes all except specially excluded ones.
	/// No idea why these particular suits are the default cycler's options.
	var/list/limit_departments = list( // ALLOW(instance_list): d: replaced per instance at runtime (1 assignments)
		/datum/suit_cycler_choice/department/eng/standard,
		/datum/suit_cycler_choice/department/crg/mining,
		/datum/suit_cycler_choice/department/med/standard,
		/datum/suit_cycler_choice/department/sec/standard,
		/datum/suit_cycler_choice/department/eng/atmospherics,
		/datum/suit_cycler_choice/department/eng/hazmat,
		/datum/suit_cycler_choice/department/eng/construction,
		/datum/suit_cycler_choice/department/med/biohazard,
		/datum/suit_cycler_choice/department/med/emt,
		/datum/suit_cycler_choice/department/sec/riot,
		/datum/suit_cycler_choice/department/sec/eva
	)

	/// Species that the cycler can refit suits for. Null assumes all except specially excluded ones.
	var/list/limit_species

	var/list/departments
	var/list/species
	var/list/emagged_departments

	var/datum/suit_cycler_choice/department/target_department_static
	var/datum/suit_cycler_choice/species/target_species_static

	var/obj/item/clothing/suit/space/void/suit = null
	var/obj/item/clothing/head/helmet/space/helmet = null

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3). The
/// suit and helmet stay their own typed vars in raw contents, same as the
/// suit storage unit -- only the person inside is a slot.
/datum/om/relation/slot/occupant/suit_cycler
	holder = /obj/machinery/suit_cycler
	slot_id = OCCUPANT_SLOT_SUIT_CYCLER
	name = "suit cycler"

/obj/machinery/suit_cycler/Initialize(mapload)
	. = ..()

	departments = load_departments()
	species = load_species()
	emagged_departments = load_emagged()
	limit_departments = null // just for mem

	target_department_static = departments["No Change"]
	target_species_static = species["No Change"]

	if(!target_department() || !target_species())
		atom_break()


/obj/machinery/suit_cycler/proc/load_departments()
	var/list/typecache = GLOB.suit_cycler_typecache[type]
	// First of our type
	if(!typecache)
		typecache = list()
		GLOB.suit_cycler_typecache[type] = typecache
	var/list/loaded = typecache["departments"]
	// No departments loaded
	if(!loaded)
		loaded = list()
		typecache["departments"] = loaded
		for(var/datum/suit_cycler_choice/department/thing as anything in GLOB.suit_cycler_departments)
			if(istype(thing, /datum/suit_cycler_choice/department/noop))
				loaded[thing.name] = thing
				continue
			if(limit_departments && !is_type_in_list(thing, limit_departments))
				continue
			loaded[thing.name] = thing

	return loaded

/obj/machinery/suit_cycler/proc/load_species()
	var/list/typecache = GLOB.suit_cycler_typecache[type]
	// First of our type
	if(!typecache)
		typecache = list()
		GLOB.suit_cycler_typecache[type] = typecache
	var/list/loaded = typecache["species"]
	// No species loaded
	if(!loaded)
		loaded = list()
		typecache["species"] = loaded
		for(var/datum/suit_cycler_choice/species/thing as anything in GLOB.suit_cycler_species)
			if(istype(thing, /datum/suit_cycler_choice/species/noop))
				loaded[thing.name] = thing
				continue
			if(limit_species && !is_type_in_list(thing, limit_species))
				continue
			loaded[thing.name] = thing

	return loaded

/obj/machinery/suit_cycler/proc/load_emagged()
	var/list/typecache = GLOB.suit_cycler_typecache[type]
	// First of our type
	if(!typecache)
		typecache = list()
		GLOB.suit_cycler_typecache[type] = typecache
	var/list/loaded = typecache["emagged"]
	// No emagged loaded
	if(!loaded)
		loaded = list()
		typecache["emagged"] = loaded
		for(var/datum/suit_cycler_choice/department/thing as anything in GLOB.suit_cycler_emagged)
			loaded[thing.name] = thing

	return loaded



/// Requirement for putting a grabbed mob in: null, or why not.
/obj/machinery/suit_cycler/proc/can_insert_grabbed(datum/act/op/A)
	var/obj/item/grab/G = A.held
	var/mob/grabbed = G?.grab_target()
	if(!ismob(grabbed))
		return null // the effect declines silently
	if(locked)
		return "the suit cycler is locked"
	if(contents_count(src) > 0 || has_latent()) // ALLOW(latent): latent entries checked
		return "there is no room inside the cycler for [grabbed.name]"
	return null

/// Requirement shared by the helmet and suit slots: null, or why `item` can't be fitted.
/obj/machinery/suit_cycler/proc/can_fit_part(obj/item/clothing/item, occupied, part_name, no_cycle)
	if(locked)
		return "the suit cycler is locked"
	if(occupied)
		return "the cycler already contains a [part_name]"
	if(no_cycle)
		return "that item is not compatible with the cycler's protocols"
	// Refitting is immediate; sample the item's current custom appearance.
	if(read_once(item.icon_override) == CUSTOM_ITEM_MOB)
		return "you cannot refit a customised voidsuit"
	return null

/// Requirement for fitting a helmet.
/obj/machinery/suit_cycler/proc/can_insert_helmet(datum/act/op/A)
	var/obj/item/clothing/head/helmet/space/void/IH = A.held
	if(!istype(IH))
		return null
	var/reason = can_fit_part(IH, helmet, "helmet", IH.no_cycle)
	if(reason)
		return reason
	//Make it so autolok suits can't be refitted in a cycler
	if(istype(IH, /obj/item/clothing/head/helmet/space/void/autolok))
		return "you cannot refit an autolok helmet (you shouldn't even be able to remove it in the first place, inform an admin)"
	//Ditto the Mk7
	if(istype(IH, /obj/item/clothing/head/helmet/space/void/responseteam))
		return "the Mark VII Emergency Response Helmet is not compatible with the refitting system (inform an admin)"
	return null

/// Requirement for fitting a voidsuit.
/obj/machinery/suit_cycler/proc/can_insert_suit(datum/act/op/A)
	var/obj/item/clothing/suit/space/void/IS = A.held
	if(!istype(IS))
		return null
	var/reason = can_fit_part(IS, suit, "voidsuit", IS.no_cycle)
	if(reason)
		return reason
	//Make it so autolok suits can't be refitted in a cycler
	if(istype(IS, /obj/item/clothing/suit/space/void/autolok))
		return "you cannot refit an autolok suit"
	//Ditto the Mk7
	if(istype(IS, /obj/item/clothing/suit/space/void/responseteam))
		return "the Mark VII Emergency Response Suit is not compatible with the refitting system"
	return null

/obj/machinery/suit_cycler/proc/interaction_insert_grab(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/G = A.held
	if(shock_live(src))
		if(shock(user, 100))
			return OP_OK

	var/mob/grabbed = G?.grab_target()
	if(!(ismob(grabbed)))
		return OP_OK

	act_message(user, null, others = span_notice("%U% starts putting [grabbed.name] into the suit cycler."))

	task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(interaction_insert_grab_timed_done), done_args = list(user, G))

	return OP_OK

/obj/machinery/suit_cycler/proc/interaction_insert_grab_timed_done(mob/user, obj/item/grab/G)
	if(!G || !G?.grab_target())
		return TRUE
	var/mob/M = G?.grab_target()
	if(!move_into(src, OCCUPANT_SLOT_SUIT_CYCLER, M))
		return TRUE

	add_fingerprint(user)
	consume(G, user)

/obj/machinery/suit_cycler/proc/interaction_insert_helmet(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/clothing/head/helmet/space/void/IH = A.held
	if(shock_live(src))
		if(shock(user, 100))
			return OP_OK

	to_chat(user, "You fit \the [IH] into the suit cycler.")
	if(!move_into(src, nameof(src.helmet), IH, user))
		return OP_OK

	return OP_OK

/obj/machinery/suit_cycler/proc/interaction_insert_suit(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/clothing/suit/space/void/IS = A.held
	if(shock_live(src))
		if(shock(user, 100))
			return OP_OK

	to_chat(user, "You fit \the [IS] into the suit cycler.")
	if(!move_into(src, nameof(src.suit), IS, user))
		return OP_OK

	return OP_OK

/// The multitool or wirecutters: a live cycler shocks; behind the open panel its window opens.
/obj/machinery/suit_cycler/proc/hacking_tool_used(datum/act/op/A)
	if(shock_live(src) && shock(A.actor, 100))
		return OP_OK
	if(panel_open)
		attack_hand(A.actor)
	return OP_OK

/obj/machinery/suit_cycler/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(shock_live(src) && shock(user, 100))
		return OP_OK
	set_panel_open(!panel_open)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, "You [panel_open ? "open" : "close"] the maintenance panel.")
	return OP_OK

/obj/machinery/suit_cycler/proc/on_emag(datum/act/op/A)
	//Clear the access reqs, disable the safeties, and open up all paintjobs.
	to_chat(A.actor, span_danger("You run the sequencer across the interface, corrupting the operating protocols."))

	set_emagged(1)
	hold(src, STAT_SAFETIES, null, src) // the corrupted protocols keep the safeties off for good
	req_access = list()
	return OP_OK

/obj/machinery/suit_cycler/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return OP_OK

	if(!user.IsAdvancedToolUser())
		return OP_OK

	if(shock_live(src))
		if(shock(user, 100))
			return OP_OK

	tgui_interact(user)
	return OP_OK

/// The cycler won't start with a living thing inside it unless the safeties are off: the safety wire cut or pulsed, or an emag (safety_wire()).
STAT(/obj/machinery/suit_cycler, safeties, ALL)

MSG_DEF_SELF(suit_cycler/cannot_leave, "you can't do that right now")
MSG_DEF_SELF(suit_cycler/needs_grab, "needs a grab")
MSG_DEF_SELF(suit_cycler/needs_helmet, "needs a void helmet")
MSG_DEF_SELF(suit_cycler/needs_suit, "needs a voidsuit")

CAPABILITIES(/obj/machinery/suit_cycler)
	op("cycler_insert_grab", inputs(item(/obj/item/grab), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Put in cycler"), needs(req(/obj/item/grab, because = MSG(suit_cycler/needs_grab)), req_adjacent(), req_capable(), req(PROC_REF(can_insert_grabbed))), then(PROC_REF(interaction_insert_grab)))
	op("cycler_insert_helmet", inputs(item(/obj/item/clothing/head/helmet/space/void), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Fit helmet"), when(PROC_REF(cycler_helmet_offered)), needs(req(/obj/item/clothing/head/helmet/space/void, because = MSG(suit_cycler/needs_helmet)), req_adjacent(), req_capable(), req(PROC_REF(can_insert_helmet))), then(PROC_REF(interaction_insert_helmet)))
	op("cycler_insert_suit", inputs(item(/obj/item/clothing/suit/space/void), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Fit voidsuit"), needs(req(/obj/item/clothing/suit/space/void, because = MSG(suit_cycler/needs_suit)), req_adjacent(), req_capable(), req(PROC_REF(can_insert_suit))), then(PROC_REF(interaction_insert_suit)))
	op("cycler_use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	op("cycler_leave", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject Cycler"), needs(req_adjacent(), req_capable(), req(PROC_REF(cycler_actor_can_act), because = MSG(suit_cycler/cannot_leave))), then(PROC_REF(interaction_leave)))
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(cycler_has_work), wakes_on = list(nameof(active), nameof(irradiating)))
	interface("SuitCycler", state = nameof(GLOB.tgui_notcontained_state))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Suit storage unit", count = 3, tools = FALSE, status_lines = PROC_REF(wire_lights))
	extend(/datum/act/touch_wires, instead(then(PROC_REF(wire_touch_shocks))))
	safety_wire(stat = STAT_SAFETIES)
	shock_wire(stat = STAT_ELECTRIFIED)
	on_wire(WIRE_IDSCAN, cut = PROC_REF(idscan_wire_cut), pulse = PROC_REF(idscan_wire_pulsed)) // the cycler's own lock: cut opens it, mended it locks
	op("dispense", ui_act("dispense", arg("item", schema_text(4096))), then(PROC_REF(ui_act_dispense)))
	op("department", ui_act("department", arg("department")), then(PROC_REF(ui_act_department)))
	op("species", ui_act("species", arg("species")), then(PROC_REF(ui_act_species)))
	op("radlevel", ui_act("radlevel", arg("radlevel", num())), then(PROC_REF(ui_act_radlevel)))
	op("repair_suit", ui_act("repair_suit"), then(PROC_REF(ui_act_repair_suit)))
	op("apply_paintjob", ui_act("apply_paintjob"), then(PROC_REF(ui_act_apply_paintjob)))
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
	op("eject_guy", ui_act("eject_guy"), then(PROC_REF(ui_act_eject_guy)))
	op("uv", ui_act("uv"), then(PROC_REF(ui_act_uv)))
	emag(then(PROC_REF(on_emag)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("use_hacking_tools", any_of_tools(TOOL_MULTITOOL, TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), label("Wires"), then(PROC_REF(hacking_tool_used)))

/obj/machinery/suit_cycler/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/occupant = slot_item_real(OCCUPANT_SLOT_SUIT_CYCLER)
	var/list/data = list()

	data["userHasAccess"] = allowed(user)

	data["locked"] = locked
	data["active"] = active
	data["uv_active"] = (active && irradiating > 0)
	data["max_uv_level"] = emagged() ? 5 : 3
	if(helmet)
		data["helmet"] = helmet.name
	else
		data["helmet"] = null
	if(suit)
		data["suit"] = suit.name
		if(istype(suit) && can_repair)
			data["damage"] = suit.damage
	else
		data["suit"] = null
		data["damage"] = null
	if(occupant)
		data["occupied"] = TRUE
	else
		data["occupied"] = FALSE

	data["model_text"] = model_text
	data["can_repair"] = can_repair
	data["safeties"] = safeties
	data["uv_level"] = radiation_level
	return data

/obj/machinery/suit_cycler/tgui_static_data(mob/user)
	var/list/data = list()

	// tgui gets angy if you pass values too
	var/list/department_keys = list()
	for(var/key in departments)
		department_keys += key

	// emagged at the bottom
	if(emagged())
		for(var/key in emagged_departments)
			department_keys += key

	var/list/species_keys = list()
	for(var/key in species)
		species_keys += key

	data["departments"] = department_keys
	data["species"] = species_keys

	return data

/obj/machinery/suit_cycler/proc/ui_act_dispense(datum/act/op/A, raw_item)
	switch(raw_item)
		if("helmet")
			if(helmet)
				helmet.forceMove(get_turf(src))
				rel_take(src, nameof(helmet))
		if("suit")
			if(suit)
				suit.forceMove(get_turf(src))
				rel_take(src, nameof(/obj/machinery/suit_cycler::suit))
	. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_department(datum/act/op/A, department)
	var/choice = department
	if(choice in departments)
		target_department_static = departments[choice]
	else if(emagged() && (choice in emagged_departments))
		target_department_static = emagged_departments[choice]
		. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_species(datum/act/op/A, raw_species)
	var/choice = raw_species
	if(choice in species)
		target_species_static = species[choice]
		. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_radlevel(datum/act/op/A, radlevel)
	radiation_level = clamp(radlevel, 1, emagged() ? 5 : 3)
	. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_repair_suit(datum/act/op/A)
	var/mob/user = A.actor
	if(!suit || !can_repair)
		return
	set_active(1)
	after(src, 10 SECONDS, PROC_REF(finish_repair), with = list(user))
	. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_apply_paintjob(datum/act/op/A)
	var/mob/user = A.actor
	if(!suit && !helmet)
		return
	set_active(1)
	after(src, 10 SECONDS, PROC_REF(finish_paintjob), with = list(user))
	. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_lock(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		set_locked(!locked)
		to_chat(user, "You [locked ? "" : "un"]lock \the [src].")
	else
		to_chat(user, span_danger("Access denied."))
	. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_eject_guy(datum/act/op/A)
	var/mob/user = A.actor
	eject_occupant(user)
	. = TRUE

/obj/machinery/suit_cycler/proc/ui_act_uv(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SUIT_CYCLER)
	if(safeties && occupant)
		to_chat(user, span_danger("The cycler has detected an occupant. Please remove the occupant before commencing the decontamination cycle."))
		return

	set_active(1)
	set_irradiating(10)
	after(src, 1 SECOND, PROC_REF(uv_wash))
	. = TRUE

/obj/machinery/suit_cycler/proc/uv_wash()
	if(helmet)
		if(radiation_level > 2)
			helmet.wash(CLEAN_TYPE_RADIATION)
		if(radiation_level > 1)
			helmet.wash(CLEAN_SCRUB)

	if(suit)
		if(radiation_level > 2)
			suit.wash(CLEAN_TYPE_RADIATION)
		if(radiation_level > 1)
			suit.wash(CLEAN_SCRUB)

/obj/machinery/suit_cycler/proc/work_step(datum/act/timer/A)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SUIT_CYCLER)

	if(!active)
		return

	if(!operable())
		set_active(0)
		set_irradiating(0)
		return

	// Repair and repaint jobs complete through their existing delayed callbacks;
	// only UV treatment needs a per-cycle machinery callback.
	if(irradiating <= 0)
		return

	if(irradiating == 1)
		add_overlay("decon")
		finished_job()
		set_irradiating(0)
		cut_overlays()
		return

	set_irradiating(irradiating - 1)

	if(occupant)
		if(prob(radiation_level*2)) occupant.emote("scream")
		if(radiation_level > 2)
			occupant.injure(INJURY_BURN, radiation_level*2 + rand(1,3), null, src)
		if(radiation_level > 1)
			occupant.injure(INJURY_BURN, radiation_level + rand(1,3), null, src)
		occupant.apply_effect(radiation_level*10, IRRADIATE)

/obj/machinery/suit_cycler/proc/finished_job(mob/user)
	var/turf/T = get_turf(src)
	T.visible_message("[icon2html(src,viewers(src))]" + span_notice("The [src] beeps several times."))
	icon_state = initial(icon_state)
	set_active(0)
	play_sfx(src, SFX_MACHINES_BOOBEEBEEP)

/obj/machinery/suit_cycler/proc/repair_suit()
	if(!suit || !suit.damage || !suit.can_breach)
		return

	own_clear(suit, nameof(suit.breaches), OWN_DELETE)
	suit.calc_breach_damage()

	return

/obj/machinery/suit_cycler/proc/interaction_leave(datum/act/op/A)
	var/mob/user = A.actor
	eject_occupant(user)
	return OP_OK

/obj/machinery/suit_cycler/proc/eject_occupant(mob/user)
	var/mob/living/carbon/human/occupant = src?.slot_item(OCCUPANT_SLOT_SUIT_CYCLER)

	if(locked || active)
		to_chat(user, span_warning("The cycler is locked."))
		return

	if(!occupant)
		return

	slot_remove(occupant, get_turf(src))

	add_fingerprint(user)

	return

// "Streamlined" before? Ok. -Aro
/obj/machinery/suit_cycler/proc/apply_paintjob()
	if(!target_species() || !target_department())
		return

	// Helmet to new paint
	if(target_department().can_refit_helmet(helmet))
		target_department().do_refit_helmet(helmet)
	// Suit to new paint
	if(target_department().can_refit_suit(suit))
		target_department().do_refit_suit(suit)
	// Attached voidsuit helmet to new paint
	if(target_department().can_refit_helmet(suit?.hood))
		target_department().do_refit_helmet(suit?.hood)

	// Species fitting for all 3 potential changes
	if(target_species().can_refit_to(helmet, suit, suit?.hood))
		target_species().do_refit_to(helmet, suit, suit?.hood)
	else
		visible_message("[icon2html(src,viewers(src))]" + span_warning("Unable to apply specified cosmetics with specified species. Please try again with a different species or cosmetic option selected."))
		return

/obj/machinery/suit_cycler/proc/finish_repair(mob/user)
	repair_suit()
	finished_job(user)

/obj/machinery/suit_cycler/proc/finish_paintjob(mob/user)
	apply_paintjob()
	finished_job(user)

/obj/machinery/suit_cycler/ownership()
	. = ..()
	. += owns(nameof(suit), policy = OWN_CONTAINED)
	. += owns(nameof(helmet), policy = OWN_CONTAINED)

/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/obj/machinery/suit_cycler/proc/target_department() as /datum/suit_cycler_choice/department
	return target_department_static

/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/obj/machinery/suit_cycler/proc/target_species() as /datum/suit_cycler_choice/species
	return target_species_static

// ---- the wires ----

/obj/machinery/suit_cycler/proc/wire_lights()
	return list(
		"The orange light is [shock_live(src) ? "off" : "on"].",
		"The red light is [safeties ? "off" : "blinking"].",
		"The yellow light is [locked ? "on" : "off"].")

/// Reaching into a live cycler's wires shocks a carbon at it instead (a shock that misses lets them through).
/obj/machinery/suit_cycler/proc/wire_touch_shocks(datum/act/A)
	var/datum/act/touch_wires/T = A
	if(iscarbon(T.user) && Adjacent(T.user) && shock_live(src) && shock(T.user, 100))
		return OP_REFUSED
	return HOOK_DECLINE

/obj/machinery/suit_cycler/proc/idscan_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_locked(N.mended)

/obj/machinery/suit_cycler/proc/idscan_wire_pulsed(datum/act/A)
	set_locked(!locked)


/obj/machinery/suit_cycler/proc/cycler_helmet_offered(datum/act/op/A)
	return !istype(A.held, /obj/item/clothing/head/helmet/space/rig)


/obj/machinery/suit_cycler/proc/cycler_actor_can_act(datum/act/op/A)
	var/mob/actor = A.actor
	READS_FROM(actor)
	if(!isliving(actor) || actor.incapacitated())
		return "you can't do that right now"
	return null
