//This is the initial set up for the new carts. Feel free to improve and/or rewrite everything here.
//I don't know what the hell I'm doing right now. Please help. Especially with the update_icons stuff. -Joan Risu

/obj/vehicle/train/rover/engine
	name = "\improper NT T-41LV Humvee"
	desc = "The corporate market model of the UF T-41LV, a SolGov reconnaissance and exploration vehicle, painted in Nanotrasen blue. Trailers can be latched for transporting heavy equipment, though its performance will noticeably degrade with more than one."
	icon = 'icons/vore/rover_vr.dmi'
	icon_state = "rover"
	light_power = 2 // 1 to 2, more light range.
	light_range = 6 // 3 to 6, more light range.
	on = 0
	powered = 1
	locked = 0
	move_delay = 0.2 // Move delay reduced from 0.5 to 0.2.
	charge_use = 2.5 // Reduced from 5 to 2.5 for more fuel efficiency, being a dedicated transport vehicle.

	//Health stuff
	max_integrity = 250 // Cars are usually just a bit tougher than humans.
	fire_dam_coeff = 0.6
	brute_dam_coeff = 0.5

	load_item_visible = 0
	load_offset_x = 0
	pixel_x = -8
	pixel_y = -8

	var/car_limit = 1	//how many cars an engine can pull before performance degrades. This should be 0 to prevent trailers from unhitching.
						// Set to 1 because the thing slows down to a crawl with even one trailer. Unhitching doesn't occur at regular movement speeds, or even at faster speeds than base.
	active_engines = 1
	var/obj/item/key/rover/key
	var/siren = 0 //This is for eventually getting the siren sprite to work.

/obj/vehicle/train/rover/engine/dunebuggy
	name = "Research Dune Buggy"
	desc = "A Dune Buggy developed for asteroid exploration and transportation. It has a sticker that says to wear EVA suits if used in space."
	icon = 'icons/vore/rover_vr.dmi'
	icon_state = "dunebug"

/obj/item/key/rover
	name = "\improper ignition key" // Name update
	desc = "A universal electronic tri-key for starting most Nanotrasen vehicles." // Desc update
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "securikey"
	w_class = ITEMSIZE_TINY

/obj/vehicle/train/rover/trolley
	name = "Train trolley"
	desc = "A trolley designed to transport security equipment to a scene."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "secitemcarrierbot"
	anchored = FALSE
	passenger_allowed = 0
	locked = 0

	load_item_visible = 0
	load_offset_x = 0
	load_offset_y = 0
	mob_offset_y = 0

//-------------------------------------------
// Standard procs
//-------------------------------------------

/obj/vehicle/train/rover/engine/Initialize(mapload)
	. = ..()
	turn_off()	//so engine verbs are correctly set

/obj/vehicle/train/rover/engine/Move(atom/newloc, direct = 0, movetime)
	if(on && cell.charge < charge_use)
		turn_off()
		update_stats()
		if(load && is_train_head())
			to_chat(load, span_notice("The drive motor briefly whines, then drones to a stop."))

	if(is_train_head() && !on)
		return FALSE

	//space check ~no flying space trains sorry
	if(on && is_vehicle_inpassable(newloc))
		return FALSE

	return ..()

CAPABILITIES(/obj/vehicle/train/rover/trolley)
	op("train_limiter_cable", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle load limiter"), then(PROC_REF(interaction_train_limiter_cable)))

CAPABILITIES(/obj/vehicle/train/rover/engine)
	op("rover_engine_key", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert key"), then(PROC_REF(interaction_rover_engine_key)))
	op("rover_engine_start_engine", menu(), label("Start engine"), needs(req_on_holder_turf(), req_capable(), req_is(nameof(on), FALSE, because = MSG(vehicle/already_running))), then(PROC_REF(rover_engine_start_engine)))
	op("rover_engine_stop_engine", menu(), label("Stop engine"), needs(req_on_holder_turf(), req_capable(), req_is(nameof(on), TRUE, because = MSG(vehicle/already_stopped))), then(PROC_REF(rover_engine_stop_engine)))
	op("rover_engine_remove_key", menu(), label("Remove key"), needs(req_on_holder_turf(), req_capable(), req(PROC_REF(pred_rover_engine_has_key_holds))), then(PROC_REF(rover_engine_remove_key)))

/// Requirement (was REQ pred_rover_engine_has_key): the legacy check answers TRUE to pass.
/obj/vehicle/train/rover/engine/proc/pred_rover_engine_has_key_holds(datum/act/op/A)
	var/answer = pred_rover_engine_has_key(A.actor, src, A.held)
	if(!istext(answer) && answer)
		return null
	return req_refusal_value(answer, /datum/msg/req_failed)

/// Why pred_rover_engine_has_key refuses: the legacy check text, else the clause reason.
/// Old attackby: the key goes in the ignition (a key is always used up here, even with one already in).
/obj/vehicle/train/rover/engine/proc/interaction_rover_engine_key(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W, /obj/item/key/rover))
		return OP_DECLINE
	if(!key)
		move_into(src, nameof(src.key), W, user)
	return OP_OK

//cargo trains are open topped, so there is a chance the projectile will hit the mob ridding the train instead
/obj/vehicle/train/rover/bullet_act(obj/item/projectile/Proj)
	if(has_buckled_mobs() && prob(70))
		var/mob/living/L = pick(src?.buckled_mob_list())
		L.bullet_act(Proj)
		return
	..()

/// The rover has no open sprite: it keeps its initial icon_state.
/// The look: the mapped sprite, none of what the types above draw.
/obj/vehicle/train/rover/draw(datum/look/look)
	..()
	// the mapped sprite, without the parent's states and layers
	look.state(null)

/obj/vehicle/train/rover/trolley/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	return

/obj/vehicle/train/rover/engine/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	..()
	update_stats()

/obj/vehicle/train/rover/engine/remove_cell(mob/living/carbon/human/H)
	..()
	update_stats()

/obj/vehicle/train/rover/engine/Bump(atom/Obstacle)
	var/obj/machinery/door/D = Obstacle
	var/mob/living/carbon/human/H = load
	if(istype(D) && istype(H))
		D.Bumped(H)		//a little hacky, but hey, it works, and respects access rights

	..()

/obj/vehicle/train/rover/trolley/Bump(atom/Obstacle)
	if(!lead())
		return //so people can't knock others over by pushing a trolley around
	..()

//-------------------------------------------
// Train procs
//-------------------------------------------
/obj/vehicle/train/rover/engine/turn_on()
	if(!key)
		return
	else
		..()
		update_stats()

/obj/vehicle/train/rover/engine/turn_off()
	..()

/obj/vehicle/train/rover/RunOver(mob/living/M)
	var/list/parts = list(BP_HEAD, BP_TORSO, BP_L_LEG, BP_R_LEG, BP_L_ARM, BP_R_ARM)

	M.apply_effects(5, 5)
	for(var/i = 0, i < rand(1,3), i++)
		M.injure(INJURY_BLUNT, rand(1,5), pick(parts), src)

/obj/vehicle/train/rover/trolley/RunOver(mob/living/M)
	..()
	attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey])")]")

/obj/vehicle/train/rover/engine/RunOver(mob/living/M)
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
/obj/vehicle/train/rover/engine/relaymove(mob/user, direction)
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

/obj/vehicle/train/rover/engine/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The power light is [on ? "on" : "off"]."
		. += "There are[key ? "" : " no"] keys in the ignition."
		. += "The charge meter reads [cell? round(cell.percent(), 0.01) : 0]%"

/// Old verb "Start engine".
/obj/vehicle/train/rover/engine/proc/rover_engine_start_engine(datum/act/op/A)
	var/mob/user = A.actor
	if(!ishuman(user))
		return

	turn_on()
	if (on)
		to_chat(user, "You start [src]'s engine.")
	else
		if(cell.charge < charge_use)
			to_chat(user, "[src] is out of power.")
		else
			to_chat(user, "[src]'s engine won't start.")

/// Old verb "Stop engine".
/obj/vehicle/train/rover/engine/proc/rover_engine_stop_engine(datum/act/op/A)
	var/mob/user = A.actor
	if(!ishuman(user))
		return

	turn_off()
	if (!on)
		to_chat(user, "You stop [src]'s engine.")

/// Old verb "Remove key".
/obj/vehicle/train/rover/engine/proc/rover_engine_remove_key(datum/act/op/A)
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
/obj/vehicle/train/rover/trolley/load(atom/movable/C)
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

/obj/vehicle/train/rover/engine/load(atom/movable/C)
	if(!ishuman(C))
		return 0

	. = ..(C)

	if(!.)
		return

	if(ismob(C))
		buckle_mob(C)
		C.alpha = 0

/obj/vehicle/train/rover/engine/unload(mob/user, direction)
	var/mob/living/carbon/human/C = load


	if(ismob(load))
		unbuckle_mob(load)
		C.alpha = 255

	rel_clear(src, nameof(load))


//Load the object "inside" the trolley and add an overlay of it.
//This prevents the object from being interacted with until it has
// been unloaded. A dummy object is loaded instead so the loading
// code knows to handle it correctly.
/obj/vehicle/train/rover/trolley/proc/load_object(atom/movable/C)
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

/obj/vehicle/train/rover/trolley/unload(mob/user, direction)
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

/obj/vehicle/train/rover/engine/latch(obj/vehicle/train/T, mob/user)
	if(!istype(T) || !Adjacent(T))
		return 0

	//if we are attaching a trolley to an engine we don't care what direction
	// it is in and it should probably be attached with the engine in the lead
	if(istype(T, /obj/vehicle/train/rover/trolley))
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
/obj/vehicle/train/rover/engine/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	//Update move delay
	if(!is_train_head() || !on)
		move_delay = initial(move_delay)		//so that engines that have been turned off don't lag behind
	else
		move_delay = max(0, (-car_limit * active_engines) + train_length - active_engines)	//limits base overweight so you cant overspeed trains
		move_delay *= (1 / max(1, active_engines)) * 2 										//overweight penalty (scaled by the number of engines)
		move_delay += 1 // base reference speed // Move-delay from server config (2) to 1.
		move_delay *= 1.1																	//makes cargo trains 10% slower than running when not overweight

/obj/vehicle/train/rover/trolley/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	if(!lead() && !tow())
		set_anchored(FALSE)
	else
		set_anchored(TRUE)

/obj/vehicle/train/rover/engine/ownership()
	. = ..()
	. += owns(nameof(key), policy = OWN_CONTAINED, starts = /obj/item/key/rover)
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell/high)

/// Engine Menu requirements (old start/stop/remove_key verb toggling in turn_on/turn_off/key insert).
/obj/vehicle/train/rover/engine/proc/pred_rover_engine_has_key(mob/actor, atom/target, obj/item/held)
	return !!key
