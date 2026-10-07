//This is the initial set up for the new carts. Feel free to improve and/or rewrite everything here.
//I don't know what the hell I'm doing right now. Please help. Especially with the update_icons stuff. -Joan Risu

/obj/vehicle/train/security/engine
	name = "Security Cart"
	desc = "A ridable electric car designed for pulling trolleys as well as personal transport."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "paddywagon"
	on = 0
	powered = 1
	locked = 0
	move_delay = 0.5

	//Health stuff
	max_integrity = 100
	fire_dam_coeff = 0.6
	brute_dam_coeff = 0.5

	load_item_visible = 1
	load_offset_x = 0
	mob_offset_y = 7

	var/car_limit = 0	//how many cars an engine can pull before performance degrades. This should be 0 to prevent trailers from unhitching.
	active_engines = 1
	var/obj/item/key/key
	var/key_type = /obj/item/key/security
	var/siren = 0 //This is for eventually getting the siren sprite to work.

/obj/item/key/security
	name = "The Security Cart key"
	desc = "The Security Cart Key used to start it."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "securikey"
	w_class = ITEMSIZE_TINY

/obj/vehicle/train/security/trolley
	name = "Train trolley"
	desc = "A trolly designed to transport security personnel or prisoners."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "paddy_trailer"
	anchored = FALSE
	passenger_allowed = 1
	locked = 0

	load_item_visible = 1
	load_offset_x = 0
	load_offset_y = 4
	mob_offset_y = 8

/obj/vehicle/train/security/trolley/cargo
	name = "Train trolley"
	desc = "A trolley designed to transport security equipment to a scene."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "secitemcarrierbot"
	passenger_allowed = 0 //Stick a man inside the box. :v
	load_item_visible = 0 //The load is supposed to be invisible.

//-------------------------------------------
// Standard procs
//-------------------------------------------

/obj/vehicle/train/security/engine/Initialize(mapload)
	. = ..()
	var/image/I = new(icon = 'icons/obj/vehicles.dmi', icon_state = "cargo_engine_overlay", layer = src.layer + 0.2) //over mobs
	add_overlay(I)
	turn_off()	//so engine verbs are correctly set

/obj/vehicle/train/security/engine/Move(atom/newloc, direct = 0, movetime)
	if(on && cell.charge < charge_use)
		turn_off()
		update_stats()
		if(load && is_train_head())
			to_chat(load, "The drive motor briefly whines, then drones to a stop.")

	if(is_train_head() && !on)
		return FALSE

	//space check ~no flying space trains sorry
	if(on && is_vehicle_inpassable(newloc))
		return FALSE

	return ..()

CAPABILITIES(/obj/vehicle/train/security/trolley)
	op("train_limiter_cable", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle load limiter"), then(PROC_REF(interaction_train_limiter_cable)))

CAPABILITIES(/obj/vehicle/train/security/engine)
	op("security_engine_key", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert key"), then(PROC_REF(interaction_security_engine_key)))
	op("security_engine_start_engine", menu(), label("Start engine"), needs(req_on_holder_turf(), req_capable(), req_is(nameof(on), FALSE, because = MSG(vehicle/already_running))), then(PROC_REF(security_engine_start_engine)))
	op("security_engine_stop_engine", menu(), label("Stop engine"), needs(req_on_holder_turf(), req_capable(), req_is(nameof(on), TRUE, because = MSG(vehicle/already_stopped))), then(PROC_REF(security_engine_stop_engine)))
	op("security_engine_remove_key", menu(), label("Remove key"), needs(req_on_holder_turf(), req_capable(), req(PROC_REF(pred_security_engine_has_key_holds), because = PROC_REF(pred_security_engine_has_key_refusal))), then(PROC_REF(security_engine_remove_key)))

/// Requirement (was REQ pred_security_engine_has_key): the legacy check answers TRUE to pass.
/obj/vehicle/train/security/engine/proc/pred_security_engine_has_key_holds(datum/act/op/A)
	var/answer = pred_security_engine_has_key(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why pred_security_engine_has_key refuses: the legacy check text, else the clause reason.
/obj/vehicle/train/security/engine/proc/pred_security_engine_has_key_refusal(datum/act/op/A)
	var/answer = pred_security_engine_has_key(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Old attackby: the key goes in the ignition (a key is always used up here, even with one already in).
/obj/vehicle/train/security/engine/proc/interaction_security_engine_key(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W, key_type))
		return OP_DECLINE
	if(!key)
		move_into(src, nameof(src.key), W, user)
	return OP_OK



/obj/vehicle/train/security/trolley/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	return

/obj/vehicle/train/security/engine/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	..()
	update_stats()

/obj/vehicle/train/security/engine/remove_cell(mob/living/carbon/human/H)
	..()
	update_stats()

/obj/vehicle/train/security/engine/Bump(atom/Obstacle)
	var/obj/machinery/door/D = Obstacle
	var/mob/living/carbon/human/H = load
	if(istype(D) && istype(H))
		D.Bumped(H)		//a little hacky, but hey, it works, and respects access rights

	..()

/obj/vehicle/train/security/trolley/Bump(atom/Obstacle)
	if(!lead())
		return //so people can't knock others over by pushing a trolley around
	..()

//-------------------------------------------
// Train procs
//-------------------------------------------
/obj/vehicle/train/security/engine/turn_on()
	if(!key)
		return
	else
		..()
		update_stats()

/obj/vehicle/train/security/engine/turn_off()
	..()

/obj/vehicle/train/security/RunOver(mob/living/M)
	var/list/parts = list(BP_HEAD, BP_TORSO, BP_L_LEG, BP_R_LEG, BP_L_ARM, BP_R_ARM)

	M.apply_effects(5, 5)
	for(var/i = 0, i < rand(1,3), i++)
		M.injure(INJURY_BLUNT, rand(1,5), pick(parts), src)

/obj/vehicle/train/security/trolley/RunOver(mob/living/M)
	..()
	attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey])")]")

/obj/vehicle/train/security/engine/RunOver(mob/living/M)
	..()

	if(is_train_head() && ishuman(load))
		var/mob/living/carbon/human/D = load
		to_chat(D, span_danger("You ran over \the [M]!"))
		visible_message(span_danger("\The [src] ran over \the [M]!"))
		add_attack_logs(D,M,"Ran over with [src.name]")
		attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey]), driven by [D.name] ([D.ckey])")]")
	else
		attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey])")]")


//-------------------------------------------
// Interaction procs
//-------------------------------------------
/obj/vehicle/train/security/engine/relaymove(mob/user, direction)
	if(user != load)
		return 0

	if(is_train_head())
		if(direction == reverse_direction(dir) && tow())
			return 0
		if(Move(get_step(src, direction)))
			return 1
		return 0
	else
		return ..()

/obj/vehicle/train/security/engine/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The power light is [on ? "on" : "off"]."
		. += "There are[key ? "" : " no"] keys in the ignition."
		. += "The charge meter reads [cell? round(cell.percent(), 0.01) : 0]%"

/// Old verb "Start engine".
/obj/vehicle/train/security/engine/proc/security_engine_start_engine(datum/act/op/A)
	var/mob/user = A.actor
	if(!ishuman(user))
		return

	turn_on()
	if (on)
		to_chat(user, "You start [src]'s engine.")
	else
		if(cell && cell.charge < charge_use)
			to_chat(user, "[src] is out of power.")
		else
			to_chat(user, "[src]'s engine won't start.")

/// Old verb "Stop engine".
/obj/vehicle/train/security/engine/proc/security_engine_stop_engine(datum/act/op/A)
	var/mob/user = A.actor
	if(!ishuman(user))
		return

	turn_off()
	if (!on)
		to_chat(user, "You stop [src]'s engine.")

/// Old verb "Remove key".
/obj/vehicle/train/security/engine/proc/security_engine_remove_key(datum/act/op/A)
	var/mob/user = A.actor
	if(!ishuman(user))
		return

	if(!key || (load && load != user))
		return

	if(on)
		turn_off()

	key.forceMove(user.loc)
	if(!user.get_active_hand())
		user.put_in_hands(key)
	rel_take(src, nameof(key))

//-------------------------------------------
// Loading/unloading procs
//-------------------------------------------
/obj/vehicle/train/security/trolley/load(atom/movable/C)
	if(ismob(C) && !passenger_allowed)
		return 0
	if(!istype(C,/obj/machinery) && !istype(C,/obj/structure/closet) && !istype(C,/obj/structure/largecrate) && !istype(C,/obj/structure/reagent_dispensers) && !istype(C,/obj/structure/ore_box) && !ishuman(C))
		return 0

	//if there are any items you don't want to be able to interact with, add them to this check
	// ~no more shielded, emitter armed death trains
	if(istype(C, /obj/machinery))
		load_object(C)
	else
		..()

	if(load)
		return 1

/obj/vehicle/train/security/engine/load(atom/movable/C)
	if(!ishuman(C))
		return 0

	return ..()

//Load the object "inside" the trolley and add an overlay of it.
//This prevents the object from being interacted with until it has
// been unloaded. A dummy object is loaded instead so the loading
// code knows to handle it correctly.
/obj/vehicle/train/security/trolley/proc/load_object(atom/movable/C)
	if(!isturf(C.loc)) //To prevent loading things from someone's inventory, which wouldn't get handled properly.
		return 0
	if(load || C.anchored)
		return 0

	var/datum/vehicle_dummy_load/dummy_load = new()
	rel_set(src, nameof(load), dummy_load)

	if(!load)
		return
	dummy_load.actual_load = C
	C.forceMove(src)

	if(load_item_visible)
		C.pixel_x += load_offset_x
		C.pixel_y += load_offset_y
		C.layer = layer

		add_overlay(C)

		//we can set these back now since we have already cloned the icon into the overlay
		C.pixel_x = initial(C.pixel_x)
		C.pixel_y = initial(C.pixel_y)
		C.layer = initial(C.layer)

/obj/vehicle/train/security/trolley/unload(mob/user, direction)
	if(istype(load, /datum/vehicle_dummy_load))
		var/datum/vehicle_dummy_load/dummy_load = load
		rel_set(src, nameof(load), dummy_load.actual_load)
		dummy_load.actual_load = null
		spent(dummy_load, src)
		cut_overlays()
	..()

//-------------------------------------------
// Latching/unlatching procs
//-------------------------------------------

/obj/vehicle/train/security/engine/latch(obj/vehicle/train/T, mob/user)
	if(!istype(T) || !Adjacent(T))
		return 0

	//if we are attaching a trolley to an engine we don't care what direction
	// it is in and it should probably be attached with the engine in the lead
	if(istype(T, /obj/vehicle/train/security/trolley))
		T.attach_to(src, user)
	else
		var/T_dir = get_dir(src, T)	//figure out where T is wrt src

		if(dir == T_dir) 	//if car is ahead
			src.attach_to(T, user)
		else if(reverse_direction(dir) == T_dir)	//else if car is behind
			T.attach_to(src, user)

//-------------------------------------------------------
// Stat update procs
//
// Update the trains stats for speed calculations.
// The longer the train, the slower it will go. car_limit
// sets the max number of cars one engine can pull at
// full speed. Adding more cars beyond this will slow the
// train proportionate to the length of the train. Adding
// more engines increases this limit by car_limit per
// engine.
//-------------------------------------------------------
/obj/vehicle/train/security/engine/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	//Update move delay
	if(!is_train_head() || !on)
		move_delay = initial(move_delay)		//so that engines that have been turned off don't lag behind
	else
		move_delay = max(0, (-car_limit * active_engines) + train_length - active_engines)	//limits base overweight so you cant overspeed trains
		move_delay *= (1 / max(1, active_engines)) * 2 										//overweight penalty (scaled by the number of engines)
		move_delay += CONFIG_GET(number/run_speed) // base reference speed //
		move_delay *= 1.1																	//makes cargo trains 10% slower than running when not overweight

/obj/vehicle/train/security/trolley/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	if(!lead() && !tow())
		set_anchored(FALSE)
	else
		set_anchored(TRUE)

/obj/vehicle/train/security/engine/ownership()
	. = ..()
	. += owns(nameof(key), policy = OWN_CONTAINED, starts = nameof(key_type))
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell/high)

/// Engine Menu requirements (old start/stop/remove_key verb toggling in turn_on/turn_off/key insert).
/obj/vehicle/train/security/engine/proc/pred_security_engine_has_key(mob/actor, atom/target, obj/item/held)
	return !!key
