/obj/vehicle/train/engine
	name = "cargo train tug"
	desc = "A ridable electric car designed for pulling cargo trolleys."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "cargo_engine"
	on = 0
	powered = 1
	locked = 0

	load_item_visible = 1
	load_offset_x = 0
	mob_offset_y = 7

	var/speed_mod = 1.1
	var/car_limit = 3		//how many cars an engine can pull before performance degrades
	active_engines = 1
	var/obj/item/key/key
	var/key_type = /obj/item/key/cargo_train

/obj/item/key/cargo_train
	name = "key"
	desc = "A keyring with a small steel key, and a yellow fob reading \"Choo Choo!\"."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "train_keys"
	w_class = ITEMSIZE_TINY

/obj/vehicle/train/trolley
	name = "cargo train trolley"
	desc = "A large, flat platform made for putting things on. Or people."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "cargo_trailer"
	anchored = FALSE
	passenger_allowed = 0
	locked = 0

	load_item_visible = 1
	load_offset_x = 0
	load_offset_y = 7
	mob_offset_y = 8

//-------------------------------------------
// Standard procs
//-------------------------------------------

/obj/vehicle/train/engine/Initialize(mapload)
	. = ..()
	var/image/I = new(icon = 'icons/obj/vehicles.dmi', icon_state = "cargo_engine_overlay", layer = src.layer + 0.2) //over mobs
	add_overlay(I)
	turn_off()	//so engine verbs are correctly set

/obj/vehicle/train/engine/Move(atom/newloc, direct = 0, movetime)
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

/obj/vehicle/train/trolley/wirecutter_act(mob/user, obj/item/tool)
	if(!open || passenger_allowed)
		return ITEM_INTERACT_BLOCKING
	passenger_allowed = TRUE
	act_message(user, src, MSG_SELF(span_notice("You cut the load limiter cable.")), MSG_OTHERS(span_notice("%U% cuts a cable in %T%.")))
	return ITEM_INTERACT_SUCCESS

EXTEND_INTERACTIONS(/obj/vehicle/train/engine, \
	INTERACT_ITEM("Insert key", PROC_REF(interaction_engine_key)), \
	INTERACT_ALT("Remove key", PROC_REF(interaction_engine_remove_key)), \
	INTERACT_VERB("Start engine", PROC_REF(engine_start_engine), REQ_REACH(0), REQ_ON(PRED_TARGET, /obj/vehicle/train/engine/proc/pred_engine_stopped, "the engine is already running")), \
	INTERACT_VERB("Stop engine", PROC_REF(engine_stop_engine), REQ_REACH(0), REQ_ON(PRED_TARGET, /obj/vehicle/train/engine/proc/pred_engine_running, "the engine is already stopped")), \
	INTERACT_VERB("Remove key", PROC_REF(engine_remove_key), REQ_REACH(0), REQ_ON(PRED_TARGET, /obj/vehicle/train/engine/proc/pred_engine_has_key, null)), \
)

/// Old attackby: the key goes in the ignition (a key is always used up here, even with one already in).
/obj/vehicle/train/engine/proc/interaction_engine_key(mob/user, obj/item/W, datum/interaction/interaction)
	if(!istype(W, key_type))
		return FALSE
	if(!key)
		move_into(src, nameof(src.key), W, user)
	return TRUE

/*
//cargo trains are open topped, so there is a chance the projectile will hit the mob ridding the train instead
/obj/vehicle/train/cargo/bullet_act(obj/item/projectile/Proj)
	if(has_buckled_mobs() && prob(70))
		var/mob/living/L = pick(buckled_mobs)
		L.bullet_act(Proj)
		return
	..()

*/

/obj/vehicle/train/trolley/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	return

/obj/vehicle/train/engine/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	..()
	update_stats()

/obj/vehicle/train/engine/remove_cell(mob/living/carbon/human/H)
	..()
	update_stats()

/obj/vehicle/train/engine/Bump(atom/Obstacle)
	var/obj/machinery/door/D = Obstacle
	var/mob/living/carbon/human/H = load
	if(istype(D) && istype(H))
		D.Bumped(H)		//a little hacky, but hey, it works, and respects access rights

	..()

/obj/vehicle/train/trolley/Bump(atom/Obstacle)
	if(!lead())
		return //so people can't knock others over by pushing a trolley around
	..()

//-------------------------------------------
// Train procs
//-------------------------------------------
/obj/vehicle/train/engine/turn_on()
	if(!key)
		return
	if(!cell)
		return
	else
		..()
		update_stats()

/obj/vehicle/train/engine/turn_off()
	..()

/obj/vehicle/train/RunOver(mob/living/M)
	if(src?.pulled_by_mob() == M) // Don't destroy people pulling vehicles up stairs
		return

	var/list/parts = list(BP_HEAD, BP_TORSO, BP_L_LEG, BP_R_LEG, BP_L_ARM, BP_R_ARM)

	M.apply_effects(5, 5)
	for(var/i = 0, i < rand(1,3), i++)
		M.injure(INJURY_BLUNT, rand(1,5), pick(parts), src)

/obj/vehicle/train/trolley/RunOver(mob/living/M)
	..()
	attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey])")]")

/obj/vehicle/train/engine/RunOver(mob/living/M)
	..()

	if(is_train_head() && ishuman(load))
		var/mob/living/carbon/human/D = load
		to_chat(D, span_bolddanger("You ran over [M]!"))
		visible_message(span_bolddanger("\The [src] ran over [M]!"))
		add_attack_logs(D,M,"Ran over with [src.name]")
		attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey]), driven by [D.name] ([D.ckey])")]")
	else
		attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey])")]")


//-------------------------------------------
// Interaction procs
//-------------------------------------------
/obj/vehicle/train/engine/relaymove(mob/user, direction)
	if(user != load)
		return 0
	// Start
	if(user.has_status(STAT_PARALYZED) || user.has_status(STAT_SLEEPING))
		return 0
	// End
	if(is_train_head())
		if(direction == reverse_direction(dir) && tow())
			return 0
		if(Move(get_step(src, direction)))
			return 1
		return 0
	else
		return ..()

/obj/vehicle/train/engine/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The power light is [on ? "on" : "off"].\nThere are[key ? "" : " no"] keys in the ignition."
		. += "The charge meter reads [cell? round(cell.percent(), 0.01) : 0]%"


/obj/vehicle/train/engine/click_ctrl(mob/user)
	if(Adjacent(user))
		if(on)
			engine_stop_engine(user)
			return CLICK_ACTION_SUCCESS

		engine_start_engine(user)
		return CLICK_ACTION_SUCCESS

	return ..()

/// Old click_alt: pull the key when adjacent.
/obj/vehicle/train/engine/proc/interaction_engine_remove_key(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return FALSE
	engine_remove_key(user)
	return TRUE

/// Old verb "Start engine".
/obj/vehicle/train/engine/proc/engine_start_engine(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user))
		return

	turn_on()
	if (on)
		to_chat(user, "You start [src]'s engine.")
	else
		if(!cell)
			to_chat(user, "[src] doesn't appear to have a power cell!")
		else if(cell.charge < charge_use)
			to_chat(user, "[src] is out of power.")
		else
			to_chat(user, "[src]'s engine won't start.")

/// Old verb "Stop engine".
/obj/vehicle/train/engine/proc/engine_stop_engine(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user))
		return

	turn_off()
	if (!on)
		to_chat(user, "You stop [src]'s engine.")

/// Old verb "Remove key".
/obj/vehicle/train/engine/proc/engine_remove_key(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user))
		return

	if(!key || (load && load != user))
		return

	if(on)
		turn_off()

	key.forceMove(user.loc)
	if(!user.get_active_hand())
		user.put_in_hands(key)
	own_take(src, nameof(key))

//-------------------------------------------
// Loading/unloading procs
//-------------------------------------------
/obj/vehicle/train/trolley/load(atom/movable/C, mob/user)
	if(ismob(C) && !passenger_allowed)
		return 0
	if(!istype(C,/obj/machinery) && !istype(C,/obj/structure/closet) && !istype(C,/obj/structure/largecrate) && !istype(C,/obj/structure/reagent_dispensers) && !istype(C,/obj/structure/ore_box) && !ishuman(C))
		return 0

	//if there are any items you don't want to be able to interact with, add them to this check
	// ~no more shielded, emitter armed death trains
	if(istype(C, /obj/machinery))
		load_object(C)
	else
		..(C, user)

	if(load)
		return 1

/obj/vehicle/train/engine/load(atom/movable/C, mob/user)
	if(!ishuman(C))
		return 0

	return ..()

//Load the object "inside" the trolley and add an overlay of it.
//This prevents the object from being interacted with until it has
// been unloaded. A dummy object is loaded instead so the loading
// code knows to handle it correctly.
/obj/vehicle/train/trolley/proc/load_object(atom/movable/C)
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

/obj/vehicle/train/trolley/unload(mob/user, direction)
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

/obj/vehicle/train/engine/latch(obj/vehicle/train/T, mob/user)
	if(!istype(T) || !Adjacent(T))
		return 0

	//if we are attaching a trolley to an engine we don't care what direction
	// it is in and it should probably be attached with the engine in the lead
	if(istype(T, /obj/vehicle/train/trolley) || istype(T, /obj/vehicle/train/trolley_tank))
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
/obj/vehicle/train/engine/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	//Update move delay
	if(!is_train_head() || !on)
		move_delay = initial(move_delay)		//so that engines that have been turned off don't lag behind
	else
		move_delay = max(0, (-car_limit * active_engines) + train_length - active_engines)	//limits base overweight so you cant overspeed trains
		move_delay *= (1 / max(1, active_engines)) * 2 										//overweight penalty (scaled by the number of engines)
		move_delay += CONFIG_GET(number/run_speed) 											//base reference speed
		move_delay *= speed_mod																//makes cargo trains 10% slower than running when not overweight

/obj/vehicle/train/trolley/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	if(!lead() && !tow())
		set_anchored(FALSE)
	else
		set_anchored(TRUE)

/obj/vehicle/train/engine/draw(datum/look/look)
	..()
	var/image/O = image(icon = 'icons/obj/vehicles.dmi', icon_state = "cargo_engine_overlay", dir = src.dir)
	O.layer = FLY_LAYER
	O.plane = MOB_PLANE
	look.overlay(O)

/obj/vehicle/train/engine/set_dir()
	..()
	changed(src)

//-------------------------------------------------------
// Cargo tugs for reagent transport from chemical refinery
//-------------------------------------------------------
/obj/vehicle/train/trolley_tank
	name = "cargo train tanker"
	/// Refinery hubs wait TROLLEY_TANK_SETTLE_TIME after the tank last moved before transferring.
	COOLDOWN_DECLARE(settle_cooldown)
	desc = "A large, tank made for transporting liquids."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "cargo_tank"
	anchored = FALSE
	flags = OPENCONTAINER
	paint_color = "#efdd16"


CAPABILITIES(/obj/vehicle/train/trolley_tank)
	reagents(CARGOTANKER_VOLUME)
	climb()
	// the tank's own uses answer before the vehicle's generic item use (a hit), one tier above it
	op("fill_container", item(/obj/item/reagent_containers/glass), priority(OP_PRIORITY_PART + 1), then(PROC_REF(fill_container)))
	op("repaint", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_PART + 1), wait(0),
		asks(/datum/prompt/color, fields = list("question" = "Please select paint color.", "title" = "Paint Color", "default" = nameof(paint_color), "timeout" = 0), step = "paint"),
		then(PROC_REF(repainted)))
	op("relabel", item(/obj/item/pen), priority(OP_PRIORITY_PART + 1),
		asks(/datum/prompt/text, fields = list("question" = "What would you like the label to be?", "title" = computed(PROC_REF(label_title)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "k491"),
		then(PROC_REF(relabelled)))

/obj/vehicle/train/trolley_tank/Initialize(mapload)
	. = ..()
	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/output)
	make_sellable(/datum/sellable/trolley_tank)

/obj/vehicle/train/trolley_tank/insert_cell(obj/item/cell/C, mob/living/carbon/human/H)
	return

/obj/vehicle/train/trolley_tank/Bump(atom/Obstacle)
	if(!lead())
		return //so people can't knock others over by pushing a trolley around
	..()

EXTEND_INTERACTIONS(/obj/vehicle/train/trolley_tank, \
	INTERACT_DRAG(null, PROC_REF(interaction_trolley_tank_drag)))

/// Old MouseDrop_T: climb, empty a beaker in, or latch another car (the only train drag it allows).
/obj/vehicle/train/trolley_tank/proc/interaction_trolley_tank_drag(mob/user, atom/movable/C, datum/interaction/interaction)
	if(C == user) // climbing is the climb capability's own drag
		return FALSE

	if(istype(C,/obj/item/reagent_containers/glass))
		var/obj/item/reagent_containers/glass/G = C
		G.reagents.trans_to(src,G.reagents.total_volume)
		to_chat(user,"You empty \the [G] into the \the [src].")
		return TRUE

	if(istype(C,/obj/vehicle/train)) // Only allow latching
		return FALSE
	return TRUE

/obj/vehicle/train/trolley_tank/load(atom/movable/C, mob/living/user)
	return FALSE // Cannot load anything onto this

/obj/vehicle/train/trolley_tank/RunOver(mob/living/M)
	..()
	attack_log += text("\[[time_stamp()]\] [span_red("ran over [M.name] ([M.ckey])")]")

/// Old attackby: a beaker is filled from the tank.
/obj/vehicle/train/trolley_tank/proc/fill_container(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/G = A.held
	if(reagents.total_volume <= 0)
		to_chat(user,"\The [src] is empty.")
		return TRUE
	if(G.reagents.total_volume >= G.reagents.maximum_volume)
		to_chat(user,"\The [G] is full.")
		return TRUE
	play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
	to_chat(user,"You drain \the [src] into the \the [G].")
	reagents.trans_to_holder( G.reagents, G.reagents.maximum_volume)
	return TRUE

/// Old attackby: a multitool repaints it the answered colour.
/obj/vehicle/train/trolley_tank/proc/repainted(datum/act/op/A)
	var/new_paint = A.step_value("paint")
	if(new_paint)
		paint_color = new_paint
	return TRUE

/obj/vehicle/train/trolley_tank/proc/label_title(datum/act/op/A)
	return "[src.name]"

/// Old attackby: a pen relabels it (an empty answer clears the label).
/obj/vehicle/train/trolley_tank/proc/relabelled(datum/act/op/A)
	var/mob/user = A.actor
	if (user.get_active_hand() != A.held)
		return TRUE
	if((!in_range(src, user) && src.loc != user))
		return TRUE
	var/t = sanitizeSafe(A.step_value("k491"), MAX_NAME_LEN)
	if(t)
		src.name = "[initial(name)] - '[t]'"
	else
		src.name = initial(name)
	return TRUE

/obj/vehicle/train/trolley_tank/update_car(train_length, active_engines)
	src.train_length = train_length
	src.active_engines = active_engines

	if(!lead() && !tow())
		set_anchored(FALSE)
	else
		set_anchored(TRUE)

/obj/vehicle/train/trolley_tank/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u."

/obj/vehicle/train/trolley_tank/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(reagents && reagents.total_volume > 0)
		var/percent = (reagents.total_volume / reagents.maximum_volume) * 100
		switch(percent)
			if(5 to 10) percent = 10
			if(10 to 20) percent = 20
			if(20 to 30) percent = 30
			if(30 to 40) percent = 40
			if(40 to 50) percent = 50
			if(50 to 60) percent = 60
			if(60 to 70) percent = 70
			if(70 to 80) percent = 80
			if(80 to 90) percent = 90
			if(90 to INFINITY) percent = 100
		var/image/chems = image(icon, icon_state = "[drawn_state]_r_[percent]", dir = NORTH)
		chems.color = reagents.get_color()
		look.overlay(chems)
	var/image/Bodypaint = image(icon, icon_state = "[drawn_state]_c", dir = NORTH)
	Bodypaint.color = paint_color
	look.overlay(Bodypaint)

/obj/vehicle/train/trolley_tank/on_reagent_change(changetype)
	changed(src)

/obj/vehicle/train/engine/ownership()
	. = ..()
	. += owns(nameof(key), policy = OWN_CONTAINED, starts = nameof(key_type))
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell/high)

/// Engine Menu requirements (old start/stop/remove_key verb toggling in turn_on/turn_off/key insert).
/obj/vehicle/train/engine/proc/pred_engine_running(mob/actor, atom/target, obj/item/held)
	return on

/obj/vehicle/train/engine/proc/pred_engine_stopped(mob/actor, atom/target, obj/item/held)
	return !on

/obj/vehicle/train/engine/proc/pred_engine_has_key(mob/actor, atom/target, obj/item/held)
	return !!key

/obj/vehicle/train/trolley_tank/Move(atom/newloc, direct = 0, movetime)
	. = ..()
	if(.)
		COOLDOWN_START(src, settle_cooldown, TROLLEY_TANK_SETTLE_TIME)
