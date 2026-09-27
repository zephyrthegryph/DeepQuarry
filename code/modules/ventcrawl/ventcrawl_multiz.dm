/// A ventcrawler inside a z-pipe climbs it with the ordinary Move Upwards /
/// Move Down verbs (mob/zMove() hands them here). Up pipes go up, down pipes down.
/obj/machinery/atmospherics/pipe/zpipe/proc/ventcrawl_z(mob/living/user, direction)
	return FALSE

/obj/machinery/atmospherics/pipe/zpipe/up/ventcrawl_z(mob/living/user, direction)
	if(direction != UP || user.loc != src)
		return FALSE
	var/obj/machinery/atmospherics/target = check_ventcrawl(GetAbove(loc))
	if(!target)
		return FALSE
	ventcrawl_to(user, target, UP)
	return TRUE

/obj/machinery/atmospherics/pipe/zpipe/down/ventcrawl_z(mob/living/user, direction)
	if(direction != DOWN || user.loc != src)
		return FALSE
	var/obj/machinery/atmospherics/target = check_ventcrawl(GetBelow(loc))
	if(!target)
		return FALSE
	ventcrawl_to(user, target, DOWN)
	return TRUE

/obj/machinery/atmospherics/pipe/zpipe/proc/check_ventcrawl(turf/target)
	if(!istype(target))
		return
	if(node1 in target)
		return node1
	if(node2 in target)
		return node2
	return
