/obj/structure/meteorite
	resistance_flags = BOMB_PROOF
	name = "meteorite"
	desc = "A big hunk of star-stuff."
	icon = 'icons/obj/meteor.dmi'
	icon_state = "large"
	density = TRUE

CAPABILITIES(/obj/structure/meteorite)
	setup(PROC_REF(rotate_initial_meteorite))
	initial_contents(PROC_REF(roll_contents))
	climb()
	op("item", item(/obj/item/pickaxe), label("Use"), begins(PROC_REF(break_apart_text)), wait(PROC_REF(break_apart_time)), then(PROC_REF(break_apart_done)))

/obj/structure/meteorite/proc/rotate_initial_meteorite()
	set_icon(turn(icon, 90))

/// What it holds: mostly iron ore, sometimes a mix of precious ores, now and then an artifact.
/obj/structure/meteorite/proc/roll_contents(datum/roller/R)
	var/roll = R.number(1, 100)
	if(roll <= 60)
		return list(/obj/item/ore/iron = R.number(12, 36))
	if(roll <= 90)
		var/n = R.number(8, 24)
		return list(/obj/item/ore/silver = n, /obj/item/ore/gold = n, /obj/item/ore/osmium = n, /obj/item/ore/diamond = n)
	return /obj/machinery/artifact

/obj/structure/meteorite/proc/break_apart_done(datum/act/op/A)
	var/mob/M = A.actor
	act_message(M, src, MSG_SELF(span_warning("You break apart %T%.")), MSG_OTHERS(span_warning("%U% breaks apart %T%.")))
	for(var/obj/O in contents_of(src))
		O.forceMove(get_turf(src))
	destroyed(src, M, BRUTE)

/// The lines of the start name what the pickaxe does.
/obj/structure/meteorite/proc/break_apart_text(datum/act/op/A)
	var/obj/item/pickaxe/P = A.held
	return msg_text(span_warning("You start [P.drill_verb] %T%."), span_warning("%U% starts [P.drill_verb] %T%."))

/// Three times the pickaxe's dig time.
/obj/structure/meteorite/proc/break_apart_time(datum/act/op/A)
	var/obj/item/pickaxe/P = A.held
	return P.digspeed * 3
