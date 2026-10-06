/obj/proc/cultify()
	spent(src)

/obj/effect/decal/cleanable/blood/cultify()
	return

/obj/effect/decal/remains/cultify()
	return

/obj/effect/overlay/cultify()
	return

/obj/item/flashlight/lamp/cultify()
	new /obj/structure/cult/pylon(loc)
	..()

/obj/item/stack/material/wood/cultify()
	return

/obj/item/book/cultify()
	new /obj/item/book/tome(loc)
	..()

/obj/item/material/sword/cultify()
	new /obj/item/melee/cultblade(loc)
	..()

/obj/item/storage/backpack/cultify()
	new /obj/item/storage/backpack/cultpack(loc)
	..()

/obj/item/storage/backpack/cultpack/cultify()
	return

/obj/machinery/cultify()
	// We keep the number of cultified machines down by only converting those that are dense
	// The alternative is to keep a separate file of exceptions.
	if(density)
		var/list/random_structure = list(
			/obj/structure/cult/talisman,
			/obj/structure/cult/forge,
			/obj/structure/cult/tome
			)
		var/I = pick(random_structure)
		new I(loc)
	..()

/obj/machinery/atmospherics/cultify()
	if(src.invisibility != INVISIBILITY_MAXIMUM)
		src.invisibility = INVISIBILITY_MAXIMUM
		set_density(FALSE)

/obj/machinery/appliance/cooker/cultify()
	replace_with(src, /obj/structure/cult/talisman)

/obj/machinery/computer/cultify()
	replace_with(src, /obj/structure/cult/tome)

/obj/machinery/door/airlock/external/cultify()
	new /obj/structure/simple_door/wood(loc)
	..()

/obj/machinery/door/cultify()
	if(invisibility != INVISIBILITY_MAXIMUM)
		invisibility = INVISIBILITY_MAXIMUM
		set_density(FALSE)
		anim(target = src, a_icon = 'icons/effects/effects.dmi', a_icon_state = "breakdoor", sleeptime = 10)
		destroyed(src)

/obj/machinery/door/firedoor/cultify()
	spent(src)

/obj/machinery/light/cultify()
	replace_with(src, /obj/structure/cult/pylon)

/obj/machinery/mech_sensor/cultify()
	spent(src)

/obj/machinery/power/apc/cultify()
	if(src.invisibility != INVISIBILITY_MAXIMUM)
		src.invisibility = INVISIBILITY_MAXIMUM

/obj/machinery/vending/cultify()
	replace_with(src, /obj/structure/cult/forge)

/obj/structure/bed/chair/cultify()
	var/obj/structure/bed/chair/wood/wings/I = new(loc)
	I.dir = dir
	..()

/obj/structure/bed/chair/wood/cultify()
	return

/obj/structure/bookcase/cultify()
	return

/obj/structure/grille/cultify()
	new /obj/structure/grille/cult(get_turf(src))
	..()

/obj/structure/grille/cult/cultify()
	return

/obj/structure/simple_door/cultify()
	new /obj/structure/simple_door/wood(loc)
	..()

/obj/structure/simple_door/wood
	resistance_flags = FLAMMABLE

/obj/structure/simple_door/wood/cultify()
	return

/obj/singularity/cultify()
	var/dist = max((current_size - 2), 1)
	explosion(get_turf(src), dist, dist * 2, dist * 4)
	destroyed(src, null, "explosion")

/obj/structure/shuttle/engine/heater/cultify()
	new /obj/structure/cult/pylon(loc)
	..()

/obj/structure/shuttle/engine/propulsion/cultify()
	var/turf/T = get_turf(src)
	if(T)
		T.ChangeTurf(/turf/simulated/wall/cult)
	..()

/obj/structure/table/cultify()
	// Make it a wood-reinforced wooden table.
	// There are cult materials available, but it'd make the table non-deconstructable with how holotables work.
	// Could possibly use a new material var for holographic-ness?
	set_layers(get_material_by_name(MAT_WOOD), get_material_by_name(MAT_WOOD))
	refresh_layers()
