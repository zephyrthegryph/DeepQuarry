/obj/machinery/atmospherics/pipe/zpipe/up/declare_interactions(list/into)
	into += /datum/interaction/machine_verb/ventcrawl_up
	..()

/obj/machinery/atmospherics/pipe/zpipe/down/declare_interactions(list/into)
	into += /datum/interaction/machine_verb/ventcrawl_down
	..()

/datum/interaction/machine_verb/ventcrawl_up
	id = "ventcrawl_up"
	name = "Ventcrawl Upwards"
	requires = list(REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/pipe/zpipe/proc/actor_inside_pipe, "enter the pipe first"))
	effect = /obj/machinery/atmospherics/pipe/zpipe/proc/interaction_ventcrawl_up

/datum/interaction/machine_verb/ventcrawl_down
	id = "ventcrawl_down"
	name = "Ventcrawl Downwards"
	requires = list(REQ_ON(PRED_TARGET, /obj/machinery/atmospherics/pipe/zpipe/proc/actor_inside_pipe, "enter the pipe first"))
	effect = /obj/machinery/atmospherics/pipe/zpipe/proc/interaction_ventcrawl_down

/obj/machinery/atmospherics/pipe/zpipe/proc/actor_inside_pipe(mob/actor, atom/target, obj/item/held)
	return actor?.loc == src

/obj/machinery/atmospherics/pipe/zpipe/proc/interaction_ventcrawl_up(mob/living/user, obj/item/held, datum/interaction/interaction)
	var/obj/machinery/atmospherics/target = check_ventcrawl(GetAbove(loc))
	if(target)
		ventcrawl_to(user, target, UP)
	return TRUE

/obj/machinery/atmospherics/pipe/zpipe/proc/interaction_ventcrawl_down(mob/living/user, obj/item/held, datum/interaction/interaction)
	var/obj/machinery/atmospherics/target = check_ventcrawl(GetBelow(loc))
	if(target)
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
