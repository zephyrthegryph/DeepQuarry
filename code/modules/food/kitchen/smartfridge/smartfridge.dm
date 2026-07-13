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
	var/list/item_records = list()
	var/datum/stored_item/currently_vending = null	//What we're putting out of the machine.
	var/stored_datum_type = /datum/stored_item
	var/seconds_electrified = 0;
	var/shoot_inventory = 0
	var/locked = 0
	var/scan_id = 1
	var/is_secure = 0
	var/wrenchable = 0
	var/persistent = null // Path of persistence datum used to track contents
	circuit = /obj/item/circuitboard/smartfridge //This one is meant to be uncraftable, however.

	var/datum/looping_sound/fridge/soundloop
	var/playing_sound = FALSE

/obj/machinery/smartfridge/secure
	is_secure = 1

/obj/machinery/smartfridge/Initialize(mapload)
	. = ..()
	if(persistent)
		SSpersistence.track_value(src, persistent)
	if(is_secure)
		set_wires(new /datum/wires/smartfridge/secure(src))
	else
		set_wires(new /datum/wires/smartfridge(src))

	soundloop = new(list(src), FALSE)
	update_icon()
	default_apply_parts()

/obj/machinery/smartfridge/Destroy()
	qdel(wires)
	for(var/A in item_records)	//Get rid of item records.
		qdel(A)
	wires = null
	if(persistent)
		SSpersistence.forget_value(src, persistent)
	QDEL_NULL(soundloop)
	return ..()

/obj/machinery/smartfridge/proc/accept_check(obj/item/O)
	return FALSE

/obj/machinery/smartfridge/process()
	if(stat & (BROKEN|NOPOWER))
		soundloop.stop()
		playing_sound = FALSE
		return
	if(!playing_sound && !stat)
		soundloop.start()
		playing_sound = TRUE
	if(src.seconds_electrified > 0)
		src.seconds_electrified--
	if(src.shoot_inventory && prob(2))
		src.throw_item()

/obj/machinery/smartfridge/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_icon()
		if(stat & (NOPOWER | BROKEN))
			soundloop.stop()
			playing_sound = FALSE
		else
			soundloop.start()
			playing_sound = TRUE

// Number of stored products, used to pick the fill-level overlay. Counts the
// actual item_records contents rather than contents.len, because contents also
// holds the machine's component parts (circuit + motor + gears), which would
// otherwise mask the empty (-0) overlay and inflate the apparent fill level.
/obj/machinery/smartfridge/proc/stored_count()
	. = 0
	for(var/datum/stored_item/I as anything in item_records)
		. += I.get_amount()

/obj/machinery/smartfridge/update_icon()
	cut_overlays()
	if(panel_open)
		add_overlay("[icon_base]-panel")

	if(stat & (BROKEN))
		cut_overlays()
		icon_state = "[icon_base]-broken"

	if(stat & (NOPOWER))
		icon_state = "[icon_base]-off"
		switch(stored_count())
			if(0)
				add_overlay("[icon_base]-0-off")
			if(1 to 3)
				add_overlay("[icon_base]-[icon_contents]1-off")
			if(3 to 6)
				add_overlay("[icon_base]-[icon_contents]2-off")
			if(6 to INFINITY)
				add_overlay("[icon_base]-[icon_contents]3-off")
	else
		icon_state = icon_base
		switch(stored_count())
			if(0)
				add_overlay("[icon_base]-0")
			if(1 to 3)
				add_overlay("[icon_base]-[icon_contents]1")
			if(3 to 6)
				add_overlay("[icon_base]-[icon_contents]2")
			if(6 to INFINITY)
				add_overlay("[icon_base]-[icon_contents]3")

/obj/machinery/smartfridge/attackby(obj/item/O, mob/user)
	if(O.has_tool_quality(TOOL_SCREWDRIVER))
		panel_open = !panel_open
		user.visible_message(span_filter_notice("[user] [panel_open ? "opens" : "closes"] the maintenance panel of \the [src]."), span_filter_notice("You [panel_open ? "open" : "close"] the maintenance panel of \the [src]."))
		playsound(src, O.usesound, 50, 1)
		update_icon()
		return

	if(wrenchable && default_unfasten_wrench(user, O, 20))
		return

	if(O.has_tool_quality(TOOL_CROWBAR))
		if(allowed(user))
			default_deconstruction_crowbar(user, O)
		else
			to_chat(user, span_warning("\The [src] smartly denies you access to deconstruct it."))
		return

	if(istype(O, /obj/item/multitool) || O.has_tool_quality(TOOL_WIRECUTTER))
		if(panel_open)
			attack_hand(user)
		return

	if(stat & NOPOWER)
		to_chat(user, span_notice("\The [src] is unpowered and useless."))
		return

	if(accept_check(O))
		user.remove_from_mob(O)
		stock(O)
		user.visible_message(span_notice("[user] has added \the [O] to \the [src]."), span_notice("You add \the [O] to \the [src]."))
		sortTim(item_records, GLOBAL_PROC_REF(cmp_stored_item_name))

	else if(istype(O, /obj/item/storage/bag))
		var/obj/item/storage/bag/P = O
		var/plants_loaded = 0
		for(var/obj/G in P.contents)
			if(accept_check(G))
				P.remove_from_storage(G) //fixes ui bug - Pull Request 5515
				stock(G)
				plants_loaded = 1
		if(plants_loaded)
			user.visible_message(span_notice("[user] loads \the [src] with \the [P]."), span_notice("You load \the [src] with \the [P]."))
			if(P.contents.len > 0)
				to_chat(user, span_notice("Some items are refused."))

	else if(istype(O, /obj/item/gripper)) // Grippers. ~Mechoid.
		var/obj/item/gripper/B = O	//B, for Borg.
		var/obj/item/wrapped = B.get_wrapped_item()
		if(!wrapped)
			to_chat(user, span_filter_notice("\The [B] is not holding anything."))
			return TRUE
		else if(accept_check(wrapped))
			stock(wrapped)
			to_chat(user, span_filter_notice("You use \the [B] to put \the [wrapped] into \the [src]."))
			sortTim(item_records, GLOBAL_PROC_REF(cmp_stored_item_name))
		else
			to_chat(user, span_filter_notice("\The [src] refuses \the [wrapped]."))
		return TRUE

	else
		to_chat(user, span_notice("\The [src] smartly refuses [O]."))
		return TRUE

/obj/machinery/smartfridge/secure/emag_act(remaining_charges, mob/user)
	if(!emagged)
		emagged = 1
		locked = -1
		to_chat(user, span_filter_notice("You short out the product lock on [src]."))
		return TRUE

/obj/machinery/smartfridge/proc/find_record(obj/item/O)
	for(var/datum/stored_item/I as anything in item_records)
		if((O.type == I.item_path) && (O.name == I.item_name))
			return I
	return null

/obj/machinery/smartfridge/proc/stock(obj/item/O)
	var/datum/stored_item/I = find_record(O)
	if(!istype(I))
		I = new stored_datum_type(src, O.type, O.name)
		item_records.Add(I)
	I.add_product(O)
	SStgui.update_uis(src)
	update_icon()

/obj/machinery/smartfridge/proc/vend(datum/stored_item/I, count)
	var/amount = I.get_amount()
	// Sanity check, there are probably ways to press the button when it shouldn't be possible.
	if(amount <= 0)
		return

	for(var/i = 1 to min(amount, count))
		I.get_product(get_turf(src))
	SStgui.update_uis(src)
	update_icon()

/obj/machinery/smartfridge/attack_ai(mob/user as mob)
	attack_hand(user)

/obj/machinery/smartfridge/attack_hand(mob/user as mob)
	if(stat & (NOPOWER|BROKEN))
		return
	wires.Interact(user)
	tgui_interact(user)

/obj/machinery/smartfridge/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SmartVend", name)
		ui.set_autoupdate(FALSE)
		ui.open()

/obj/machinery/smartfridge/tgui_data(mob/user)
	. = list()

	var/list/items = list()
	for(var/i=1 to length(item_records))
		var/datum/stored_item/I = item_records[i]
		var/count = I.get_amount()
		if(count > 0)
			items.Add(list(list("name" = capitalize(I.item_name), "index" = i, "amount" = count)))

	.["contents"] = items
	.["name"] = name
	.["locked"] = locked
	.["secure"] = is_secure

/obj/machinery/smartfridge/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	add_fingerprint(ui.user)
	switch(action)
		if("Release")
			var/amount = 0
			if(params["amount"])
				amount = params["amount"]
			else
				amount = tgui_input_number(ui.user, "How many items?", "How many items would you like to take out?", 1)

			if(QDELETED(src) || QDELETED(ui.user) || !ui.user.Adjacent(src))
				return FALSE

			var/index = text2num(params["index"])
			if(index < 1 || index > LAZYLEN(item_records))
				return TRUE

			vend(item_records[index], amount)
			update_icon()
			return TRUE
	return FALSE

/obj/machinery/smartfridge/proc/throw_item()
	var/obj/throw_item = null
	var/mob/living/target = locate() in view(7,src)
	if(!target)
		return FALSE

	for(var/datum/stored_item/I in item_records)
		throw_item = I.get_product(get_turf(src))
		if (!throw_item)
			continue
		break

	if(!throw_item)
		return FALSE
	spawn(0)
		throw_item.throw_at(target,16,3,src)
	src.visible_message(span_warning("[src] launches [throw_item.name] at [target.name]!"))
	SStgui.update_uis(src)
	update_icon()
	return TRUE

/*
 * Secure Smartfridges
 */
/obj/machinery/smartfridge/secure/tgui_act(action, params, datum/tgui/ui)
	if(stat & (NOPOWER|BROKEN))
		return TRUE
	if(ui.user.contents.Find(src) || (in_range(src, ui.user) && istype(loc, /turf)))
		if((!allowed(ui.user) && scan_id) && !emagged && locked != -1 && action == "Release")
			to_chat(ui.user, span_warning("Access denied."))
			return TRUE
	return ..()


// === merged from smartfridge_vr.dm during hard-fork de-suffix (verified no override-order change) ===
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
	var/obj/machinery/smartfridge/chemistry/chemvator/attached
	circuit = /obj/item/circuitboard/smartfridge/chemvator

/obj/machinery/smartfridge/chemistry/chemvator/accept_check(obj/item/O as obj)
	if(istype(O,/obj/item/storage/pill_bottle) || istype(O,/obj/item/reagent_containers) || istype(O,/obj/item/reagent_containers/glass/))
		return 1
	return 0

/obj/machinery/smartfridge/chemistry/chemvator/down/Destroy()
	if(attached)
		attached.attached = null // clear the upper unit's back-reference to us
	item_records = null // shared with the upper unit; don't let the base Destroy qdel its stored records
	attached = null
	return ..()

/obj/machinery/smartfridge/chemistry/chemvator/down
	name = "\improper Smart Chemavator - Lower"
	circuit = /obj/item/circuitboard/smartfridge/chemvator/down

/obj/machinery/smartfridge/chemistry/chemvator/down/Initialize(mapload)
	. = ..()
	var/obj/machinery/smartfridge/chemistry/chemvator/above = locate(/obj/machinery/smartfridge/chemistry/chemvator,get_zstep(src,UP))
	if(istype(above))
		above.attached = src
		attached = above
		item_records = attached.item_records
	else
		to_chat(world,span_danger("[src] at [x],[y],[z] cannot find the unit above it!"))
