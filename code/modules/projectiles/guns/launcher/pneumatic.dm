// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/obj/item/gun/launcher/pneumatic
	name = "pneumatic cannon"
	desc = "A large gas-powered cannon."
	icon_state = "pneumatic"
	item_state = "pneumatic"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_HUGE
	fire_sound_text = "a loud whoosh of moving air"
	fire_delay = 50
	fire_sound = SFX_WEAPONS_GRENADE_LAUNCHER // Formerly tablehit1.ogg but I like this better -Ace

	var/fire_pressure									// Used in fire checks/pressure checks.
	var/hopper_size = ITEMSIZE_NORMAL					// Hopper intake size.
	var/max_storage_space = ITEMSIZE_COST_NORMAL * 5	// Total internal storage size.
	var/tmp/obj/item/tank/tank	// Tank of gas for use in firing the cannon.

	var/obj/item/storage/item_storage
	var/pressure_setting = 10							// Percentage of the gas in the tank used to fire the projectile.
	var/possible_pressure_amounts = list(5,10,20,25,50) // Possible pressure settings.
	var/force_divisor = 400								// Force equates to speed. Speed/5 equates to a damage multiplier for whoever you hit.
														// For reference, a fully pressurized oxy tank at 50% gas release firing a health
														// analyzer with a force_divisor of 10 hit with a damage multiplier of 3000+.
	special_handling = TRUE

CAPABILITIES(/obj/item/gun/launcher/pneumatic)
	owns_one(nameof(item_storage), starts = /obj/item/storage)
	op("pneumatic_hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("pneumatic_verb_set_pressure", menu(), label("Set Valve Pressure"), needs(carried()),
		asks(/datum/prompt/choice, fields = list("question" = "Percentage of tank used per shot:", "title" = computed(PROC_REF(pressure_title)), "choices" = nameof(possible_pressure_amounts), "timeout" = 0), step = "pressure"),
		then(PROC_REF(pneumatic_verb_set_pressure)))

/obj/item/gun/launcher/pneumatic/Initialize(mapload)
	. = ..()
	item_storage.name = "hopper"
	item_storage.restrict_hold(null, hopper_size)
	item_storage.max_storage_space = max_storage_space
	item_storage.use_sound = null

/// The pressure question's title.
/obj/item/gun/launcher/pneumatic/proc/pressure_title(datum/act/op/A)
	return "[src]"

/// Old Set Valve Pressure verb.
/obj/item/gun/launcher/pneumatic/proc/pneumatic_verb_set_pressure(datum/act/op/A)
	var/mob/user = A.actor
	var/N = A.step_value("pressure")
	if(N)
		pressure_setting = N
		to_chat(user, "You dial the pressure valve to [pressure_setting]%.")
	return OP_OK

/obj/item/gun/launcher/pneumatic/proc/eject_tank(mob/user) //Remove the tank.
	if(!tank())
		to_chat(user, "There's no tank in [src].")
		return

	to_chat(user, "You twist the valve and pop the tank out of [src].")
	user.put_in_hands(tank())
	rel_clear(src, nameof(tank))
	changed(src)

/obj/item/gun/launcher/pneumatic/proc/unload_hopper(mob/user)
	if(contents_count(item_storage) > 0)
		var/obj/item/removing = item_storage.contents[contents_count(item_storage)]
		item_storage.remove_from_storage(removing, src.loc, user)
		user.put_in_hands(removing)
		to_chat(user, "You remove [removing] from the hopper.")
		play_sfx(src, SFX_WEAPONS_EMPTY)
	else
		to_chat(user, "There is nothing to remove in \the [src].")

/// Old attack_hand.
/obj/item/gun/launcher/pneumatic/proc/interaction_hand(datum/act/op/A)
	if(A.actor.get_inactive_hand() == src)
		unload_hopper(A.actor)
	else
		return OP_DECLINE
	return OP_OK

/// Old attackby. It never called ..(): any item stops here, but afterattack still follows.
/obj/item/gun/launcher/pneumatic/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	. = OP_PASS
	if(!tank() && istype(W,/obj/item/tank))
		if(!own_bring_in(src, nameof(tank), W, null, user, TRUE, null, FALSE))
			return OP_PASS
		rel_set(src, nameof(tank), W)
		act_message(user, src, MSG_SELF("You jam [W] into %T%'s valve and twist it closed."), MSG_OTHERS("%U% jams [W] into %T%'s valve and twists it closed."))
		changed(src)
	else if(istype(W))
		item_storage.try_insert(W, user)

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/launcher/pneumatic/gun_operate(datum/act/op/A, callback)
	var/mob/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	eject_tank(user)

/obj/item/gun/launcher/pneumatic/consume_next_projectile(mob/user=null)
	if(!contents_count(item_storage))
		return null
	if (!tank())
		to_chat(user, "There is no gas tank in [src]!")
		return null

	var/environment_pressure = 10
	var/turf/T = get_turf(src)
	if(T)
		var/datum/gas_mixture/environment = T.return_air()
		if(environment)
			environment_pressure = environment.return_pressure()

	fire_pressure = (tank().air_contents.return_pressure() - environment_pressure)*pressure_setting/100
	if(fire_pressure < 10)
		to_chat(user, "There isn't enough gas in the tank to fire [src].")
		return null

	var/obj/item/launched = item_storage.contents[1]
	item_storage.remove_from_storage(launched, src)
	return launched

/obj/item/gun/launcher/pneumatic/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += "The valve is dialed to [pressure_setting]%."
		if(tank())
			. += "The tank dial reads [tank().air_contents.return_pressure()] kPa."
		else
			. += "Nothing is attached to the tank valve!"

/obj/item/gun/launcher/pneumatic/update_release_force(obj/item/projectile)
	if(tank())
		release_force = ((fire_pressure*tank().volume)/projectile.w_class)/force_divisor //projectile speed.
		if(release_force > 80) release_force = 80 //damage cap.
	else
		release_force = 0

/obj/item/gun/launcher/pneumatic/handle_post_fire()
	if(tank())
		var/lost_gas_amount = tank().air_contents.total_moles()*(pressure_setting/100)
		var/datum/gas_mixture/removed = tank().air_contents.remove(lost_gas_amount)

		var/turf/T = get_turf(src.loc)
		if(T)
			T.assume_air(removed)
		spent(removed)
	..()

/// The look: with or without the tank (the hands redraw with it).
/obj/item/gun/launcher/pneumatic/draw(datum/look/look)
	..()
	if(tank())
		look.state("pneumatic-tank")
		look.held_state("pneumatic-tank")
	else
		look.state("pneumatic")
		look.held_state("pneumatic")

//Constructable pneumatic cannon.

/obj/item/cannonframe
	name = "pneumatic cannon frame"
	desc = "A half-finished pneumatic cannon."
	icon_state = "pneumatic0"
	item_state = "pneumatic"

	var/buildstate = 0

/// The look (the draw sweep: from its template).
/obj/item/cannonframe/draw(datum/look/look)
	..()
	look.state("pneumatic[buildstate]")

/obj/item/cannonframe/examine(mob/user)
	. = ..()
	switch(buildstate)
		if(1)
			. += "It has a pipe segment installed."
		if(2)
			. += "It has a pipe segment welded in place."
		if(3)
			. += "It has an outer chassis installed."
		if(4)
			. += "It has an outer chassis welded in place."
		if(5)
			. += "It has a transfer valve installed."

/obj/item/cannonframe/welder_act(mob/user, obj/item/tool)
	var/obj/item/weldingtool/T = tool.get_welder()
	if(buildstate == 1)
		if(T.remove_fuel(0,user))
			if(!src || !T.isOn()) return ITEM_INTERACT_SUCCESS
			playsound(src, tool.usesound, 100, 1)
			to_chat(user, span_notice("You weld the pipe into place."))
			buildstate++
			changed(src)
	if(buildstate == 3)
		if(T.remove_fuel(0,user))
			if(!src || !T.isOn()) return ITEM_INTERACT_SUCCESS
			playsound(src, tool.usesound, 100, 1)
			to_chat(user, span_notice("You weld the metal chassis together."))
			buildstate++
			changed(src)
	if(buildstate == 5)
		if(T.remove_fuel(0,user))
			if(!src || !T.isOn()) return ITEM_INTERACT_SUCCESS
			playsound(src, tool.usesound, 100, 1)
			to_chat(user, span_notice("You weld the valve into place."))
			replace_with(src, /obj/item/gun/launcher/pneumatic)
	return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/cannonframe)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/cannonframe/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/pipe))
		if(buildstate == 0)
			consume(W, user)
			to_chat(user, span_notice("You secure the piping inside the frame."))
			buildstate++
			changed(src)
			return OP_PASS
	else if(istype(W,/obj/item/stack/material) && W.get_material_name() == MAT_STEEL)
		if(buildstate == 2)
			var/obj/item/stack/material/M = W
			if(M.use(5))
				to_chat(user, span_notice("You assemble a chassis around the cannon frame."))
				buildstate++
				changed(src)
			else
				to_chat(user, span_notice("You need at least five metal sheets to complete this task."))
			return OP_PASS
	else if(istype(W,/obj/item/transfer_valve))
		if(buildstate == 4)
			consume(W, user)
			to_chat(user, span_notice("You install the transfer valve and connect it to the piping."))
			buildstate++
			changed(src)
			return OP_PASS
	else
		return OP_DECLINE
	return OP_PASS

/// Tank of gas for use in firing the cannon. (a relation view: null once it is deleted).
/obj/item/gun/launcher/pneumatic/proc/tank() as /obj/item/tank
	return tank
