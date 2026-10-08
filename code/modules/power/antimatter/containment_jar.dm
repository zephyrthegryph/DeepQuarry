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


CAPABILITIES(/obj/item/am_containment)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(jar_blast))))

/// A devastating blast, or a lucky one against an unstable jar, sets off the fuel; any other blast only destabilises it.
/obj/item/am_containment/proc/jar_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(packet.severity <= 1 || (packet.severity == 2 && prob((fuel/10)-stability)))
		explosion(get_turf(src), 1, 2, 3, 5)
		destroyed(src)
		return OP_OK
	stability -= 40 / (packet.severity - 1)
	return OP_OK

/obj/item/am_containment/proc/usefuel(wanted)
	if(fuel < wanted)
		wanted = fuel
	fuel -= wanted
	return wanted
