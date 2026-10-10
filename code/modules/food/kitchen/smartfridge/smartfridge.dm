/obj/machinery/smartfridge
	name = "\improper SmartFridge"
	desc = "For storing all sorts of things! This one doesn't accept any of them!"
	icon = 'icons/obj/vending_smartfridge.dmi'
	icon_state = "smartfridge"
	var/icon_base = "smartfridge" //Iconstate to base all the broken/deny/etc on
	var/icon_contents = "food" //Overlay to put on that show contents
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 100
	flags = NOREACT
	var/max_n_of_items = 999 // Sorry but the BYOND infinite loop detector doesn't look things over 1000.
	var/list/item_records = list() // ALLOW(instance_list): d: the fridge's live stock records
	var/tmp/datum/stored_item/currently_vending	//What we're putting out of the machine.
	var/stored_datum_type = /datum/stored_item
	/// Whether inserted items with identical state fold into counts (C9).
	var/collapse_stock = TRUE
	locked = 0
	var/is_secure = 0
	var/wrenchable = 0
	var/persistent = null // Path of persistence datum used to track contents
	circuit = /obj/item/circuitboard/smartfridge //This one is meant to be uncraftable, however.
	maintenance_flags = MACHINE_MAINT_FRAME | MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 2 SECONDS

	var/datum/looping_sound/fridge/soundloop
	var/playing_sound = FALSE

/// Throws its stock: the throw wire cut, or pulsed (item_throw()).
STAT(/obj/machinery/smartfridge, shoot_inventory, ANY)
/// Checks the ID for a secure stock (the ID wire pulsed stops it; cut, it scans for good: id_scan()).
STAT(/obj/machinery/smartfridge, scan_id, TOP, base = TRUE)
/// Shocks the hand at it: the shock wire cut (until mended) or pulsed (30 s); live only while operable (shock_live()).
STAT(/obj/machinery/smartfridge, electrified, TOP, base = 0)

CAPABILITIES(/obj/machinery/smartfridge)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition), gate = PROC_REF(step_gate), wakes_on = list(STAT_OPERABLE), unpowered = TRUE)
	owns_one(nameof(soundloop), /datum/looping_sound/fridge, starts = /datum/looping_sound/fridge)
	owns_many(nameof(item_records))
	interface("SmartVend")
	extend("ui_open", priority(OP_PRIORITY_DEFAULT - 3))
	// Release takes `amount` out of record `index`; with no amount it asks how many (the old act_ask re-run).
	op("release", ui_act("Release", arg("amount", num(default = 0)), arg("index", num())),
		asks(/datum/prompt/number, fields = list("question" = "How many items?", "title" = "How many items would you like to take out?", "default" = 1, "timeout" = 0), step = "amount", when = PROC_REF(release_asks_amount)),
		then(PROC_REF(ui_act_release)))
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Smartfridge", count = 3, tools = FALSE, status_lines = PROC_REF(wire_lights))
	extend(/datum/act/touch_wires, instead(then(PROC_REF(wire_touch_shocks))))
	shock_wire(stat = STAT_ELECTRIFIED)
	id_scan(stat = STAT_SCAN_ID, pulse_value = FALSE)
	item_throw(stat = STAT_SHOOT_INVENTORY)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(throw_frame)), when = cond_all(STAT_OPERABLE, STAT_SHOOT_INVENTORY))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("smartfridge_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(is_powered_for_stocking_holds))), then(PROC_REF(smartfridge_interaction_item)))
	op("smartfridge_interaction_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), then(PROC_REF(smartfridge_interaction_hand)))
	op("use_wire_tools", any_of_tools(TOOL_WIRECUTTER, TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Wires"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)), then(PROC_REF(wire_tool_used)))

/obj/machinery/smartfridge/proc/wire_lights()
	return list(
		"The orange light is [shock_live(src) ? "off" : "on"].",
		"The red light is [shoot_inventory ? "off" : "blinking"].",
		"A [scan_id ? "purple" : "yellow"] light is on.")

/// Reaching into a live fridge's wires shocks a carbon at it instead.
/obj/machinery/smartfridge/proc/wire_touch_shocks(datum/act/A)
	var/datum/act/touch_wires/T = A
	if(iscarbon(T.user) && Adjacent(T.user) && shock_live(src) && shock(T.user, 100))
		return OP_REFUSED
	return HOOK_DECLINE

/obj/machinery/smartfridge/secure
	is_secure = 1

/obj/machinery/smartfridge/Initialize(mapload)
	. = ..()
	if(persistent)
		SSpersistence.track_value(src, persistent)

	default_apply_parts()

// Stock is a stock slot (roadmap C9, code/datums/containment/stock.dm).
// Inserted items whose state serializes and matches the record's fold into
// its count; items with state of their own stay real in the stock slot.
// Deconstruction spills everything, latent copies made real.
/obj/machinery/smartfridge/stock_records()
	return item_records

/obj/machinery/smartfridge/on_slot_changed(slot_id, atom/movable/thing, inserted)
	if(!inserted && slot_id == CONTAINER_SLOT_STOCK)
		for(var/datum/stored_item/I as anything in item_records)
			I.forget(thing)

// a persistent fridge is forgotten by persistence.
/obj/machinery/smartfridge/lifecycle_dematerialize()
	if(persistent)
		SSpersistence.forget_value(src, persistent)
	..()

/obj/machinery/smartfridge/proc/accept_check(obj/item/O)
	return FALSE

/// Whether a step may run now (a drying rack works only powered and whole).
/obj/machinery/smartfridge/proc/step_gate(datum/act/A)
	return TRUE

/obj/machinery/smartfridge/proc/work_step(datum/act/timer/A)
	if(!operable())
		soundloop.stop()
		playing_sound = FALSE
		return PROCESS_KILL
	if(!playing_sound && !has_condition())
		soundloop.start()
		playing_sound = TRUE
	return PROCESS_KILL // its only timed work, throwing its stock, is an every() on STAT_SHOOT_INVENTORY

/// One frame of a fridge that throws its stock (every() runs it only while it is operable and throwing).
/obj/machinery/smartfridge/proc/throw_frame(datum/act/timer/A)
	if(prob(2))
		throw_item()

/obj/machinery/smartfridge/power_change()
	. = ..()
	if(.)
		if(!operable())
			soundloop?.stop()
			playing_sound = FALSE
		else
			soundloop?.start()
			playing_sound = TRUE
			// work_step(null) sleeps on NOPOWER; resume pending work on restore.
			if(has_pending_work())
				work_start(src)

/// TRUE when process() still has time-dependent work to do once powered.
/obj/machinery/smartfridge/proc/has_pending_work()
	return FALSE // the throwing is an every() on STAT_SHOOT_INVENTORY; a subtype with work of its own says so

// Number of stored products, used to pick the fill-level overlay. Counts the
// actual item_records contents rather than contents.len, because contents also
// holds the machine's component parts (circuit + motor + gears), which would
// otherwise mask the empty (-0) overlay and inflate the apparent fill level.
/obj/machinery/smartfridge/proc/stored_count()
	. = 0
	for(var/datum/stored_item/I as anything in item_records)
		. += I.get_amount()

/obj/machinery/smartfridge/draw(datum/look/look)
	..()
	for(var/datum/stored_item/record as anything in item_records)
		look.watch(record) // the stock count: a record's amount and what it keeps are tracked on it
	look_parts(look)

/// What this chain's providers drew: each type's own part of the look, a subtype replacing or extending it (..()).
/obj/machinery/smartfridge/proc/look_parts(datum/look/look)
	if(panel_open)
		look.overlay("[icon_base]-panel")

	if(broken_now())
		look.state("[icon_base]-broken")

	if(power_lost())
		look.state("[icon_base]-off")
		switch(stored_count())
			if(0)
				look.overlay("[icon_base]-0-off")
			if(1 to 3)
				look.overlay("[icon_base]-[icon_contents]1-off")
			if(3 to 6)
				look.overlay("[icon_base]-[icon_contents]2-off")
			if(6 to INFINITY)
				look.overlay("[icon_base]-[icon_contents]3-off")
	else
		look.state(icon_base)
		switch(stored_count())
			if(0)
				look.overlay("[icon_base]-0")
			if(1 to 3)
				look.overlay("[icon_base]-[icon_contents]1")
			if(3 to 6)
				look.overlay("[icon_base]-[icon_contents]2")
			if(6 to INFINITY)
				look.overlay("[icon_base]-[icon_contents]3")

/// Requirement: is_powered_for_stocking returns null to allow, or a refusal reason.
/obj/machinery/smartfridge/proc/is_powered_for_stocking_holds(datum/act/op/A)
	return is_powered_for_stocking(A.actor, src, A.held)

/// Requirement: the fridge has power.
/obj/machinery/smartfridge/proc/is_powered_for_stocking(mob/user, atom/target, obj/item/held)
	return !power_lost() ? null : "it is unpowered and useless"

/// Old attackby.
/obj/machinery/smartfridge/proc/smartfridge_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(accept_check(O))
		user.remove_from_mob(O)
		stock(O)
		act_message(user, src, MSG_SELF(span_notice("You add %I% to %T%.")), MSG_OTHERS(span_notice("%U% has added %I% to %T%.")), item = O)
		sortTim(item_records, GLOBAL_PROC_REF(cmp_stored_item_name))

	else if(istype(O, /obj/item/storage/bag))
		var/obj/item/storage/bag/P = O
		var/plants_loaded = 0
		P.latent_materialize_all() // a walk needs real things (C5)
		for(var/obj/G in contents_of(P)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
			if(accept_check(G))
				P.remove_from_storage(G) //fixes ui bug - Pull Request 5515
				stock(G)
				plants_loaded = 1
		if(plants_loaded)
			act_message(user, src, MSG_SELF(span_notice("You load %T% with %I%.")), MSG_OTHERS(span_notice("%U% loads %T% with %I%.")), item = P)
			if(contents_count(P) > 0) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
				to_chat(user, span_notice("Some items are refused."))

	else if(istype(O, /obj/item/gripper)) // Grippers. ~Mechoid.
		var/obj/item/gripper/B = O	//B, for Borg.
		var/obj/item/wrapped = B.get_wrapped_item()
		if(!wrapped)
			to_chat(user, span_filter_notice("\The [B] is not holding anything."))
			return OP_OK
		else if(accept_check(wrapped))
			stock(wrapped)
			to_chat(user, span_filter_notice("You use \the [B] to put \the [wrapped] into \the [src]."))
			sortTim(item_records, GLOBAL_PROC_REF(cmp_stored_item_name))
		else
			to_chat(user, span_filter_notice("\The [src] refuses \the [wrapped]."))
		return OP_OK

	else
		to_chat(user, span_notice("\The [src] smartly refuses [O]."))
		return OP_OK
	return OP_PASS

/obj/machinery/smartfridge/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	set_panel_open(!panel_open)
	act_message(user, src, MSG_SELF(span_notice("You [panel_open ? "open" : "close"] the maintenance panel of %T%.")), \
		MSG_OTHERS(span_filter_notice("%U% [panel_open ? "opens" : "closes"] the maintenance panel of %T%.")))
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK

/obj/machinery/smartfridge/proc/wrench_used(datum/act/op/A)
	if(!wrenchable)
		return OP_DECLINE
	return OP_DECLINE

/obj/machinery/smartfridge/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!allowed(user))
		to_chat(user, span_warning("\The [src] smartly denies you access to deconstruct it."))
		return OP_OK
	return OP_DECLINE

/// The wirecutters or a multitool behind the open panel: the fridge's window, where its wires are.
/obj/machinery/smartfridge/proc/wire_tool_used(datum/act/op/A)
	attack_hand(A.actor)
	return OP_OK

/obj/machinery/smartfridge/secure/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	set_emagged(1)
	set_locked(-1)
	to_chat(user, span_filter_notice("You short out the product lock on [src]."))
	return OP_OK

/obj/machinery/smartfridge/proc/find_record(obj/item/O)
	for(var/datum/stored_item/I as anything in item_records)
		if((O.type == I.item_path) && (O.name == I.item_name))
			return I
	return null

/obj/machinery/smartfridge/proc/stock(obj/item/O)
	work_start(src)
	var/datum/stored_item/I = find_record(O)
	if(!istype(I))
		I = new stored_datum_type(src, O.type, O.name)
		I.collapsible = collapse_stock
		rel_add(src, nameof(item_records), I)
	I.add_product(O)
	SStgui.update_uis(src)

/obj/machinery/smartfridge/proc/vend(datum/stored_item/I, count)
	var/amount = I.get_amount()
	// Sanity check, there are probably ways to press the button when it shouldn't be possible.
	if(amount <= 0)
		return

	for(var/i = 1 to min(amount, count))
		I.get_product(get_turf(src))
	SStgui.update_uis(src)

/// Old attack_hand.
/obj/machinery/smartfridge/proc/smartfridge_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return OP_OK
	wires_open(src, user)
	tgui_interact(user)
	return OP_OK

/// The window's data.
/obj/machinery/smartfridge/ui_data(datum/act/eval/A)
	. = list()
	.["name"] = name
	.["secure"] = is_secure
	var/list/part = ui_data_part_smartfridge(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/smartfridge/proc/ui_data_part_smartfridge(datum/act/eval/A)
	. = list()

	var/list/items = list()
	for(var/i=1 to length(item_records))
		var/datum/stored_item/I = item_records[i]
		var/count = I.get_amount()
		if(count > 0)
			items.Add(list(list("name" = capitalize(I.item_name), "index" = i, "amount" = count)))

	.["contents"] = items
	.["locked"] = locked

/// Release asks how many only when the button did not say.
/obj/machinery/smartfridge/proc/release_asks_amount(datum/act/op/A)
	return !A.args["amount"]

/// Release: `amount` (or the answered number) out of record `index`.
/obj/machinery/smartfridge/proc/ui_act_release(datum/act/op/A, amount, index)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!amount)
		amount = A.step_value("amount")
	if(QDELETED(src) || QDELETED(user) || !user.Adjacent(src))
		return FALSE

	if(index < 1 || index > LAZYLEN(item_records))
		return TRUE

	vend(item_records[index], amount)
	return TRUE

/obj/machinery/smartfridge/proc/throw_item()
	var/obj/throw_item = null
	var/mob/living/target = locate_in_list(view(7,src), /mob/living)
	if(!target)
		return FALSE

	for(var/datum/stored_item/I in item_records)
		throw_item = I.get_product(get_turf(src))
		if (!throw_item)
			continue
		break

	if(!throw_item)
		return FALSE
	throw_item.throw_at(target,16,3,src)
	src.visible_message(span_warning("[src] launches [throw_item.name] at [target.name]!"))
	SStgui.update_uis(src)
	return TRUE

/*
 * Secure Smartfridges
 */
// A secure fridge's buttons do nothing while it does not work (the old ui_act_allowed()).
CAPABILITIES(/obj/machinery/smartfridge/secure)
	configure(wires(count = 4, randomize = TRUE)) // a dud beside the three, and each fridge its own colours
	extend("release", needs(req(PROC_REF(ui_gate), silent = TRUE)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)

/obj/machinery/smartfridge/secure/proc/ui_gate(datum/act/op/A)
	return (operable()) ? null : /datum/msg/req_silent

/// Release behind the ID scan.
/obj/machinery/smartfridge/secure/ui_act_release(datum/act/op/A, amount, index)
	var/mob/user = A.actor
	if(user.contents.Find(src) || (in_range(src, user) && istype(loc, /turf)))
		if((!allowed(user) && scan_id) && !emagged() && locked != -1)
			to_chat(user, span_warning("Access denied."))
			return TRUE
	return ..()

/*
 * Expert Jobs
 */
/obj/machinery/smartfridge
	var/expert_job = JOB_CHEF
/obj/machinery/smartfridge/seeds
	expert_job = JOB_BOTANIST
/obj/machinery/smartfridge/secure/extract
	expert_job = JOB_XENOBIOLOGIST
/obj/machinery/smartfridge/secure/medbay
	expert_job = JOB_CHEMIST
/obj/machinery/smartfridge/secure/chemistry
	expert_job = JOB_CHEMIST
/obj/machinery/smartfridge/secure/virology
	expert_job = JOB_MEDICAL_DOCTOR //Virologist is an alt-title unfortunately
/obj/machinery/smartfridge/drinks
	expert_job = JOB_BARTENDER

/*
 * Allow thrown items into smartfridges
 */
/obj/machinery/smartfridge/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	. = ..()
	var/mob/thrower = throwingdatum?.get_thrower()
	if(accept_check(source) && thrower)
		//Try to find what job they are via ID
		var/obj/item/card/id/thrower_id
		if(ismob(thrower))
			var/mob/T = thrower
			thrower_id = T.GetIdCard()

		//98% chance the expert makes it
		if(expert_job && thrower_id && thrower_id.rank == expert_job && prob(98))
			stock(source)

		//20% chance a non-expert makes it
		else if(prob(20))
			stock(source)

/*
 * Chemistry 'chemavator' (multi-z chem storage)
 */
/obj/machinery/smartfridge/chemistry/chemvator
	name = "\improper Smart Chemavator - Upper"
	desc = "A refrigerated storage unit for medicine and chemical storage. Now sporting a fancy system of pulleys to lift bottles up and down."
	expert_job = JOB_CHEMIST
	var/tmp/obj/machinery/smartfridge/chemistry/chemvator/attached
	circuit = /obj/item/circuitboard/smartfridge/chemvator

/obj/machinery/smartfridge/chemistry/chemvator/accept_check(obj/item/O as obj)
	if(istype(O,/obj/item/storage/pill_bottle) || istype(O,/obj/item/reagent_containers) || istype(O,/obj/item/reagent_containers/glass/))
		return 1
	return 0

// The lower unit keeps no stock of its own: it stocks into the upper unit, and its
// item_records is a read-only view of the upper unit's owned list. Drop the alias
// (never take or dispose of it: the records belong to the upper unit).
/obj/machinery/smartfridge/chemistry/chemvator/down/on_destroy(force)
	item_records = null // ALLOW(ownership): alias of the upper unit's owned list, never owned here
	..()

/obj/machinery/smartfridge/chemistry/chemvator/down/stock(obj/item/O)
	var/obj/machinery/smartfridge/chemistry/chemvator/above = attached()
	if(istype(above))
		above.stock(O)
		SStgui.update_uis(src)
		return
	return ..()

/obj/machinery/smartfridge/chemistry/chemvator/down
	name = "\improper Smart Chemavator - Lower"
	circuit = /obj/item/circuitboard/smartfridge/chemvator/down

/obj/machinery/smartfridge/chemistry/chemvator/down/Initialize(mapload)
	. = ..()
	var/obj/machinery/smartfridge/chemistry/chemvator/above = locate(/obj/machinery/smartfridge/chemistry/chemvator,get_zstep(src,UP))
	if(istype(above))
		rel_set(above, nameof(above.attached), src)
		rel_set(src, nameof(attached), above)
		item_records = attached().item_records // ALLOW(ownership): read-only alias of the upper unit's owned list; stock() forwards writes there
	else
		to_chat(world,span_danger("[src] at [x],[y],[z] cannot find the unit above it!"))

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/smartfridge/step_start_condition()
	return operable() // its hum

/// What we're putting out of the machine. (a relation view: null once it is deleted).
/obj/machinery/smartfridge/proc/currently_vending() as /datum/stored_item
	return currently_vending

/// the attached this refers to (a relation view: null once it is deleted).
/obj/machinery/smartfridge/chemistry/chemvator/proc/attached() as /obj/machinery/smartfridge/chemistry/chemvator
	return attached
