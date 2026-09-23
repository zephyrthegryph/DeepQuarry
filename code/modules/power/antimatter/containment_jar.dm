/obj/item/am_containment
	name = "antimatter containment jar"
	desc = "Holds antimatter."
	icon = 'icons/obj/machines/antimatter.dmi'
	icon_state = "jar"
	density = FALSE
	anchored = FALSE
	force = 8
	throwforce = 10
	throw_speed = 1
	throw_range = 2

	var/fuel = 10000
	var/fuel_max = 10000//Lets try this for now
	var/stability = 100//TODO: add all the stability things to this so its not very safe if you keep hitting in on things


/obj/item/am_containment/ex_act(severity)
	// A devastating blast, or a lucky one against an unstable jar, sets off the fuel.
	if(severity <= 1 || (severity == 2 && prob((fuel/10)-stability)))
		explosion(get_turf(src), 1, 2, 3, 5)
		qdel(src)
		return
	stability -= 40 / (severity - 1)

/obj/item/am_containment/proc/usefuel(wanted)
	if(fuel < wanted)
		wanted = fuel
	fuel -= wanted
	return wanted
