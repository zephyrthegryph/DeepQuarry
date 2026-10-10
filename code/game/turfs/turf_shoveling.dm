/turf/proc/handle_turf_dig(mob/user, obj/item/shovel/our_shovel)
	SHOULD_NOT_OVERRIDE(TRUE)

	// Grave digging
	if(our_shovel.grave_mode)
		shovel_dig_grave(user, our_shovel)
		return

	// Loot and garden digging
	use_tool(user, our_shovel, src, delay = 3 SECONDS, volume = 0, start_self = "\The [user] begins digging into \the [src] with \the [our_shovel].", receiver = src, on_done = PROC_REF(handle_turf_dig_tool_done), done_args = list(user, our_shovel))

/turf/proc/handle_turf_dig_tool_done(mob/user, obj/item/shovel/our_shovel)
	if(shovel_can_cultivate() && !(locate_within(src, /obj/machinery/portable_atmospherics/hydroponics/soil)) && !(locate_within(src, /obj/structure/closet/grave/dirthole)))
		var/obj/machinery/portable_atmospherics/hydroponics/soil/soil = new(src)
		user.visible_message(span_notice("\The [src] digs \a [soil] into \the [src]."))
		return

	// Spawn loot
	if(dig_exhaustion_chance >= TURF_DIG_LOOT_EXHAUSTED)
		to_chat(user, span_warning("There is nothing more to be found in \the [src]."))
		return
	var/loot_type = get_dig_loot_type(user, our_shovel)
	if(!loot_type)
		to_chat(user, span_notice("You didn't find anything of note in \the [src]."))
		return
	var/obj/item/loot = new loot_type(src)
	to_chat(user, span_notice("You dug up \a [loot]!"))

	// Check if we should be exhausted of loot
	if(dig_exhaustion_chance && prob(dig_exhaustion_chance))
		dig_exhaustion_chance = TURF_DIG_LOOT_EXHAUSTED

/turf/proc/shovel_dig_grave(mob/user, obj/item/shovel/our_shovel)
	if(contents_count(src))
		to_chat(user, span_warning("You can't dig here!"))
		return
	// Make a grave
	to_chat(user, span_notice("\The [user] begins digging into \the [src] with \the [our_shovel]."))
	var/delay = (5 SECONDS * our_shovel.toolspeed)
	user.setClickCooldown(delay)
	perform_op(user, src, "dig_grave", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("delay" = delay))

/turf/proc/grave_time(datum/act/op/A)
	return A.arg("delay")

/turf/proc/grave_dug(datum/act/op/A)
	if(!(locate_within(src, /obj/structure/closet/grave/dirthole)))
		new /obj/structure/closet/grave/dirthole(src)
	to_chat(A.actor, span_notice("You dug up a hole!"))
	return OP_OK

/// If a turf has any loot when dug with a shovel
/turf/proc/get_dig_loot_type(mob/user, obj/item/W)
	return null

/// If a turf supports making growbeds
/turf/proc/shovel_can_cultivate()
	return FALSE
