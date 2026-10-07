// Configure whether or not floorbot will fix hull breaches.
// This can be a problem if it tries to pave over space or shuttles.  That should be fixed but...
// If it can see space outside windows, it can be laggy since it keeps wondering if it should fix them.
// Therefore that functionality is disabled for now.  But it can be turned on by uncommenting this.
// # define FLOORBOT_PATCHES_HOLES 1

/mob/living/bot/floorbot
	name = "Floorbot"
	desc = "A little floor repairing robot, it looks so excited!"
	icon_state = "floorbot0"
	req_one_access = list(ACCESS_ROBOTICS, ACCESS_CONSTRUCTION)
	wait_if_pulled = 1
	min_target_dist = 0

	var/vocal = 1
	var/amount = 10 // 1 for tile, 2 for lattice
	var/maxAmount = 60
	var/tilemake = 0 // When it reaches 100, bot makes a tile
	var/improvefloors = 0
	var/eattiles = 0
	var/maketiles = 0
	var/targetdirection = null
	var/floor_build_type = /datum/decl/flooring/tiling // Basic steel floor.

/mob/living/bot/floorbot/update_icons()
	if(task_busy(src))
		icon_state = "floorbot-c"
	else if(amount > 0)
		icon_state = "floorbot[on]"
	else
		icon_state = "floorbot[on]e"

CAPABILITIES(/mob/living/bot/floorbot)
	interface("Floorbot")
	op("start", ui_act("start"), then(PROC_REF(ui_act_start)))
	op("vocal", ui_act("vocal"), then(PROC_REF(ui_act_vocal)))
	op("improve", ui_act("improve"), then(PROC_REF(ui_act_improve)))
	op("tiles", ui_act("tiles"), then(PROC_REF(ui_act_tiles)))
	op("make", ui_act("make"), then(PROC_REF(ui_act_make)))
	op("bridgemode", ui_act("bridgemode", arg("dir")), then(PROC_REF(ui_act_bridgemode)))

/// The window's data: the bot's state, and the settings for whoever may see them (a silicon, or anyone while the panel is unlocked).
/mob/living/bot/floorbot/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["on"] = on
	data["open"] = open
	data["locked"] = locked
	data["vocal"] = vocal
	data["amount"] = amount
	data["possible_bmode"] = list("NORTH", "EAST", "SOUTH", "WEST")

	data["improvefloors"] = null
	data["eattiles"] = null
	data["maketiles"] = null
	data["bmode"] = null

	if(!locked || issilicon(user))
		data["improvefloors"] = improvefloors
		data["eattiles"] = eattiles
		data["maketiles"] = maketiles
		data["bmode"] = dir2text(targetdirection)
	return data

/mob/living/bot/floorbot/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	. = ..()
	if(!emagged)
		emagged = 1
		if(user)
			to_chat(user, span_notice("The [src] buzzes and beeps."))
			play_sfx(src, SFX_MACHINES_BUZZBEEP)
		return 1

/mob/living/bot/floorbot/proc/ui_act_start(datum/act/op/A)
	if(on)
		turn_off()
	else
		turn_on()
	. = TRUE

/mob/living/bot/floorbot/proc/ui_act_vocal(datum/act/op/A)
	if(locked && !issilicon(A.actor))
		return
	vocal = !vocal
	. = TRUE

/mob/living/bot/floorbot/proc/ui_act_improve(datum/act/op/A)
	if(locked && !issilicon(A.actor))
		return
	improvefloors = !improvefloors
	. = TRUE

/mob/living/bot/floorbot/proc/ui_act_tiles(datum/act/op/A)
	if(locked && !issilicon(A.actor))
		return
	eattiles = !eattiles
	. = TRUE

/mob/living/bot/floorbot/proc/ui_act_make(datum/act/op/A)
	if(locked && !issilicon(A.actor))
		return
	maketiles = !maketiles
	. = TRUE

/mob/living/bot/floorbot/proc/ui_act_bridgemode(datum/act/op/A, dir)
	if(locked && !issilicon(A.actor))
		return
	targetdirection = text2dir(dir)
	. = TRUE

/mob/living/bot/floorbot/handleRegular()
	++tilemake
	if(tilemake >= 100)
		tilemake = 0
		addTiles(1)

	if(vocal && prob(1))
		automatic_custom_emote(AUDIBLE_MESSAGE, "makes an excited beeping sound!")
		play_sfx(src, SFX_MACHINES_TWOBEEP, vary = FALSE)

/mob/living/bot/floorbot/handleAdjacentTarget()
	if(get_turf(target) == src.loc)
		UnarmedAttack(target)

/mob/living/bot/floorbot/lookForTargets()
	if(emagged) // Time to griff
		for(var/turf/simulated/floor/D in view(src))
			if(confirmTarget(D))
				rel_set(src, nameof(target), D)
				return

	else if(amount)
		if(targetdirection) // Building a bridge
			var/turf/T = get_step(src, targetdirection)
			while(T in range(world.view, src))
				if(confirmTarget(T))
					rel_set(src, nameof(target), T)
					return
				T = get_step(T, targetdirection)
			return // In bridge mode we don't want to step off that line even to eat plates!

#ifdef FLOORBOT_PATCHES_HOLES
		for(var/turf/space/T in view(src)) // Breaches are of higher priority
			if(confirmTarget(T))
				target = T
				return

		for(var/turf/simulated/mineral/floor/T in view(src)) // Asteroids are of smaller priority
			if(confirmTarget(T))
				target = T
				return
#endif
		// Look for broken floors even if we aren't improvefloors
		for(var/turf/simulated/floor/T in view(src))
			if(confirmTarget(T))
				target = T
				return

	if(amount < maxAmount && (eattiles || maketiles))
		for(var/obj/item/stack/S in view(src))
			if(confirmTarget(S))
				target = S
				return

/mob/living/bot/floorbot/confirmTarget(atom/A) // The fact that we do some checks twice may seem confusing but remember that the bot's settings may be toggled while it's moving and we want them to stop in that case
	if(!..())
		return 0

	if(istype(A, /obj/item/stack/tile/floor))
		return (amount < maxAmount && eattiles)
	if(istype(A, /obj/item/stack/material/steel))
		return (amount < maxAmount && maketiles)

	// Don't pave over all of space, build there only if in bridge mode
	if(!targetdirection && istype(A.loc, /area/space)) // Note name == "Space" does not work!
		return 0

	if(istype(A.loc, /area/shuttle)) // Do NOT mess with shuttle drop zones
		return 0

	if(emagged)
		return (istype(A, /turf/simulated/floor))

	if(!amount)
		return 0

#ifdef FLOORBOT_PATCHES_HOLES
	if(istype(A, /turf/space))
		return 1

	if(istype(A, /turf/simulated/mineral/floor))
		return 1
#endif

	var/turf/simulated/floor/T = A
	return (istype(T) && (T.broken || T.burnt || (improvefloors && !T.flooring)) && (get_turf(T) == loc || prob(40)))

/mob/living/bot/floorbot/UnarmedAttack(atom/A, proximity)
	if(!..())
		return

	if(task_busy(src))
		return

	if(get_turf(A) != loc)
		return

	if(emagged && istype(A, /turf/simulated/floor))
		var/turf/simulated/floor/F = A
		if(F.flooring)
			act_message(src, null, others = span_warning("%U% begins to tear the floor tile from the floor!"))
			bot_work(5 SECONDS, A, PROC_REF(UnarmedAttack_floorbot_done), list(F))
		else
			act_message(src, null, others = span_danger("%U% begins to tear through the floor!"))
			bot_work(15 SECONDS, A, PROC_REF(UnarmedAttack_floorbot_done2), list(F))
		rel_clear(src, nameof(target))
	else if(isopenturf(A) || istype(A, /turf/simulated/mineral/floor))
		var/building = 2
		if(locate(/obj/structure/lattice, A))
			building = 1
		if(amount < building)
			return
		act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to repair the hole."))
		bot_work(5 SECONDS, A, PROC_REF(UnarmedAttack_floorbot_done3), list(A, building))
		rel_clear(src, nameof(target))
	else if(istype(A, /turf/simulated/floor))
		var/turf/simulated/floor/F = A
		if(F.broken || F.burnt)
			act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to remove the broken floor."))
			bot_work(5 SECONDS, F, PROC_REF(UnarmedAttack_floorbot_done4), list(F))
			rel_clear(src, nameof(target))
		else if(!F.flooring && amount)
			act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to improve the floor."))
			bot_work(5 SECONDS, F, PROC_REF(UnarmedAttack_floorbot_done5), list(F))
			rel_clear(src, nameof(target))
	else if(istype(A, /obj/item/stack/tile/floor) && amount < maxAmount)
		var/obj/item/stack/tile/floor/T = A
		act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to collect tiles."))
		bot_work(2 SECONDS, T, PROC_REF(UnarmedAttack_floorbot_done6), list(T))
		rel_clear(src, nameof(target))
	else if(istype(A, /obj/item/stack/material) && amount + 4 <= maxAmount)
		var/obj/item/stack/material/M = A
		if(M.get_material_name() == MAT_STEEL)
			act_message(src, null, others = span_infoplain(span_bold("%U%") + " begins to make tiles."))
			bot_work(5 SECONDS, A, PROC_REF(UnarmedAttack_floorbot_done7), list(M))

/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done(turf/simulated/floor/F)
	F.break_tile_to_plating()
	addTiles(1)
/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done2(turf/simulated/floor/F)
	F.ReplaceWithLattice()
	addTiles(1)
/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done3(atom/A, building)
	if(A && (locate(/obj/structure/lattice, A) && building == 1 || !locate(/obj/structure/lattice, A) && building == 2)) // Make sure that it still needs repairs
		var/obj/item/I
		if(building == 1)
			I = new /obj/item/stack/tile/floor(src)
		else
			I = new /obj/item/stack/rods(src)
		A.attackby(I, src)
/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done4(turf/simulated/floor/F)
	if(F.broken || F.burnt)
		F.make_plating()
/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done5(turf/simulated/floor/F)
	if(!F.flooring)
		F.set_flooring(get_flooring_data(floor_build_type))
		addTiles(-1)
/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done6(obj/item/stack/tile/floor/T)
	if(T)
		var/eaten = min(maxAmount - amount, T.get_amount())
		T.use(eaten)
		addTiles(eaten)
/mob/living/bot/floorbot/proc/UnarmedAttack_floorbot_done7(obj/item/stack/material/M)
	if(M)
		M.use(1)
		addTiles(4)

/mob/living/bot/floorbot/explode()
	turn_off()
	act_message(src, null, others = span_danger("%U% blows apart!"))
	play_sfx(src, SFX_SPARKS)
	var/turf/Tsec = get_turf(src)

	var/obj/item/storage/toolbox/mechanical/N = new /obj/item/storage/toolbox/mechanical(Tsec)
	N.latent_discard()
	QDEL_LIST(N.contents) // ALLOW(latent): the contents are being thrown away, so a latent entry that never materializes does not matter
	new /obj/item/assembly/prox_sensor(Tsec)
	if(prob(50))
		new /obj/item/robot_parts/l_arm(Tsec)
	new /obj/item/stack/tile/floor(Tsec, amount)
	fx_sparks(src, 3)
	return ..()

/mob/living/bot/floorbot/proc/addTiles(am)
	amount += am
	if(amount < 0)
		amount = 0
	else if(amount > maxAmount)
		amount = maxAmount

/mob/living/bot/floorbot/handlePanic()	// Speed modification based on alert level.
	. = 0
	switch(get_security_level())
		if("green")
			. = 0

		if("yellow")
			. = 0

		if("violet")
			. = 0

		if("orange")
			. = 1

		if("blue")
			. = 1

		if("red")
			. = 2

		if("delta")
			. = 2

	return .

/* Assembly */

// Ten floor tiles on an empty toolbox start a floorbot; a toolbox with something in it takes them like any storage.
CAPABILITIES(/obj/item/storage/toolbox/mechanical)
	op("add_tiles", item(/obj/item/stack/tile/floor), when(req_storage_empty()), label("Add tiles"), then(PROC_REF(add_floorbot_tiles)))

/obj/item/storage/toolbox/mechanical/proc/add_floorbot_tiles(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/stack/tile/floor/T = A.held
	if(user.s_active)
		user.s_active.close(user)
	if(T.use(10))
		var/obj/item/toolbox_tiles/B = new /obj/item/toolbox_tiles
		user.put_in_hands(B)
		to_chat(user, span_notice("You add the tiles into the empty toolbox. They protrude from the top."))
		consume(src, user)
	else
		to_chat(user, span_warning("You need 10 floor tiles for a floorbot."))
	return OP_OK

/obj/item/toolbox_tiles
	desc = "It's a toolbox with tiles sticking out the top"
	name = "tiles and toolbox"
	icon = 'icons/obj/aibots.dmi'
	icon_state = "toolbox_tiles"
	force = 3.0
	throwforce = 10.0
	throw_speed = 2
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	var/created_name = "Floorbot"

CAPABILITIES(/obj/item/toolbox_tiles)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/toolbox_tiles/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(isprox(W))
		consume(W, user)
		var/obj/item/toolbox_tiles_sensor/B = new /obj/item/toolbox_tiles_sensor()
		B.created_name = created_name
		user.put_in_hands(B)
		to_chat(user, span_notice("You add the sensor to the toolbox and tiles!"))
		consume(src, user)
	else if (istype(W, /obj/item/pen))
		ask_name_var(user)
	return OP_PASS

/obj/item/toolbox_tiles_sensor
	desc = "It's a toolbox with tiles sticking out the top and a sensor attached"
	name = "tiles, toolbox and sensor arrangement"
	icon = 'icons/obj/aibots.dmi'
	icon_state = "toolbox_tiles_sensor"
	force = 3.0
	throwforce = 10.0
	throw_speed = 2
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	var/created_name = "Floorbot"

CAPABILITIES(/obj/item/toolbox_tiles_sensor)
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/toolbox_tiles_sensor/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/robot_parts/l_arm) || istype(W, /obj/item/robot_parts/r_arm) || (istype(W, /obj/item/organ/external/arm) && ((W.name == "robotic right arm") || (W.name == "robotic left arm"))))
		consume(W, user)
		var/turf/T = get_turf(user.loc)
		var/mob/living/bot/floorbot/new_bot = new /mob/living/bot/floorbot(T)
		new_bot.name = created_name
		to_chat(user, span_notice("You add the robot arm to the odd looking toolbox assembly! Boop beep!"))
		consume(src, user)
	else if(istype(W, /obj/item/pen))
		ask_name_var(user)
	return OP_PASS
