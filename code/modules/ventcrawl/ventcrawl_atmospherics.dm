/obj/machinery/atmospherics/var/image/pipe_image

// ventcrawlers inside are put out; its pipe image comes off players' clients.
/obj/machinery/atmospherics/on_destroy(force)
	for(var/mob/living/M in contents_of(src)) //ventcrawling is serious business // ALLOW(latent): mobs are never latent
		M.remove_ventcrawl()
		M.forceMove(get_turf(src))
	..()

/// LC-refs: the pipe image leaves every ventcrawler's screen before phase 4 drops it (DECLARE_REF(..., OWNED)).
/obj/machinery/atmospherics/lifecycle_dematerialize()
	if(pipe_image)
		for(var/mob/living/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
			if(M.client)
				M.client.images -= pipe_image
				M.pipes_shown -= pipe_image
	return ..()

/obj/machinery/atmospherics/explosion_contents_severity(severity)
	return severity

/obj/machinery/atmospherics/Entered(atom/movable/Obj)
	if(isliving(Obj))
		var/mob/living/L = Obj
		L.ventcrawl_layer = layer
	. = ..()

/obj/machinery/atmospherics/relaymove(mob/living/user, direction)
	if(user.loc != src || !(direction & initialize_directions) || !IS_CARDINAL(direction)) //can't go in a way we aren't connecting to
		return
	ventcrawl_to(user,findConnecting(direction, user.ventcrawl_layer),direction)

/obj/machinery/atmospherics/proc/ventcrawl_to(mob/living/user, obj/machinery/atmospherics/target_move, direction)
	if(target_move)
		if(is_type_in_list(target_move, GLOB.ventcrawl_machinery) && target_move.can_crawl_through())
			user.remove_ventcrawl()
			user.forceMove(target_move.loc) //handles entering and so on
			user.visible_message("You hear something squeezing through the ducts.", "You climb out the ventilation system.")
		else if(target_move.can_crawl_through())
			if(target_move.return_network(target_move) != return_network(src))
				user.remove_ventcrawl()
				user.add_ventcrawl(target_move)
			user.forceMove(target_move)
			user.reset_perspective(target_move) //if we don't do this, Byond only updates the eye every tick - required for smooth movement
			if(COOLDOWN_FINISHED(user, next_play_vent))
				COOLDOWN_START(user, next_play_vent, 30)
				var/turf/T = get_turf(src)
				GLOB.motiontracker_service.ping(T,40) // Teshari rattler
				playsound(T, 'sound/machines/ventcrawl.ogg', 50, 1, -3)
				var/message = pick(
					prob(90);"* clunk *",
					prob(90);"* thud *",
					prob(90);"* clatter *",
					prob(1);"* " + span_giganteus("ඞ") + " *"
				)
				T.runechat_message(message)

	else
		if((direction & initialize_directions) || is_type_in_list(src, GLOB.ventcrawl_machinery) && src.can_crawl_through()) //if we move in a way the pipe can connect, but doesn't - or we're in a vent
			user.remove_ventcrawl()
			user.forceMove(src.loc)
			user.visible_message("You hear something squeezing through the pipes.", "You climb out the ventilation system.")
	user.setMoveCooldown(1)

/obj/machinery/atmospherics/proc/can_crawl_through()
	return 1

/obj/machinery/atmospherics/unary/can_crawl_through()
	if(welded)
		return 0

	. = ..()

/obj/machinery/atmospherics/proc/findConnecting(direction)
	for(var/obj/machinery/atmospherics/target in get_step(src,direction))
		if(target.initialize_directions & get_dir(target,src))
			if(isConnectable(target) && target.isConnectable(src))
				return target

/obj/machinery/atmospherics/proc/isConnectable(obj/machinery/atmospherics/target)
	return (target == node1 || target == node2)

/obj/machinery/atmospherics/pipe/manifold/isConnectable(obj/machinery/atmospherics/target)
	return (target == node3 || ..())

/obj/machinery/atmospherics/trinary/isConnectable(obj/machinery/atmospherics/target)
	return (target == node3 || ..())

/obj/machinery/atmospherics/pipe/manifold4w/isConnectable(obj/machinery/atmospherics/target)
	return (target == node3 || target == node4 || ..())

/obj/machinery/atmospherics/tvalve/isConnectable(obj/machinery/atmospherics/target)
	return (target == node3 || ..())

/obj/machinery/atmospherics/pipe/cap/isConnectable(obj/machinery/atmospherics/target)
	return (target == node || ..())

/obj/machinery/atmospherics/portables_connector/isConnectable(obj/machinery/atmospherics/target)
	return (target == node || ..())

/obj/machinery/atmospherics/unary/isConnectable(obj/machinery/atmospherics/target)
	return (target == node || ..())

DECLARE_REF(/obj/machinery/atmospherics, "pipe_image", OWNED, null)
