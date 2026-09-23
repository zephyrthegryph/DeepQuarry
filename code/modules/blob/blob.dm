//I will need to recode parts of this but I am way too tired atm
/obj/effect/blob
	name = "blob"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blob"
	light_range = 2
	light_color = "#b5ff5b"
	desc = "Some blob creature thingy"
	density = TRUE
	opacity = 0
	anchored = TRUE
	mouse_opacity = 2

	uses_integrity = TRUE
	max_integrity = 30
	var/brute_resist = 4
	var/fire_resist = 1
	var/expandType = /obj/effect/blob

/obj/effect/blob/Initialize(mapload)
	. = ..()
	update_icon()

/obj/effect/blob/CanPass(atom/movable/mover, turf/target)
	return FALSE

/obj/effect/blob/ex_act(severity)
	switch(severity)
		if(1)
			take_damage(rand(100, 120) / brute_resist)
		if(2)
			take_damage(rand(60, 100) / brute_resist)
		if(3)
			take_damage(rand(20, 60) / brute_resist)

/obj/effect/blob/update_icon()
	if(get_integrity() > max_integrity / 2)
		icon_state = "blob"
	else
		icon_state = "blob_damaged"

/obj/effect/blob/on_update_integrity(old_value, new_value)
	. = ..()
	update_icon()

/obj/effect/blob/atom_destruction(damage_flag)
	playsound(src, 'sound/effects/splat.ogg', 50, 1)
	return ..()

/// Blob damage is already divided by the blob's resistances, so it skips armour.
/obj/effect/blob/proc/blob_damage(amount, damage_type = BRUTE)
	var/resist = damage_type == BURN ? fire_resist : brute_resist
	return take_damage(amount / resist, damage_type, null, FALSE)

/obj/effect/blob/proc/regen()
	repair_damage(1)

/obj/effect/blob/proc/expand(turf/T)
	if(istype(T, /turf/unsimulated/) || isopenturf(T) || (ismineralturf(T) && T.density))
		return
	if(istype(T, /turf/simulated/wall))
		var/turf/simulated/wall/SW = T
		SW.take_damage(80)
		return
	var/obj/structure/girder/G = locate() in T
	if(G)
		if(prob(40))
			G.dismantle()
		return
	var/obj/structure/window/W = locate() in T
	if(W)
		W.shatter()
		return
	var/obj/structure/grille/GR = locate() in T
	if(GR)
		qdel(GR)
		return
	for(var/obj/structure/reagent_dispensers/fueltank/Fuel in T)
		Fuel.ex_act(2)
		return
	for(var/obj/machinery/door/D in T) // There can be several - and some of them can be open, locate() is not suitable
		if(D.density)
			D.ex_act(2)
			return
	var/obj/structure/foamedmetal/F = locate() in T
	if(F)
		qdel(F)
		return
	var/obj/structure/inflatable/I = locate() in T
	if(I)
		I.deflate(1)
		return

	var/obj/vehicle/V = locate() in T
	if(V)
		V.ex_act(2)
		return
	var/obj/mecha/M = locate() in T
	if(M)
		M.visible_message(span_danger("The blob attacks \the [M]!"))
		M.take_damage(40)
		return

	// Above things, we destroy completely and thus can use locate. Mobs are different.
	for(var/mob/living/L in T)
		if(L.stat == DEAD)
			continue
		L.visible_message(span_danger("The blob attacks \the [L]!"), span_danger("The blob attacks you!"))
		playsound(src, 'sound/effects/attackblob.ogg', 50, 1)
		L.injure(INJURY_BLUNT, rand(30, 40), null, src)
		return
	new expandType(T)

/obj/effect/blob/proc/pulse(forceLeft, list/dirs)
	regen()
	animate(src, color = "#FF0000", time=1)
	animate(color = "#FFFFFF", time=4, easing=ELASTIC_EASING)
	sleep(5)
	var/pushDir = pick(dirs)
	var/turf/T = get_step(src, pushDir)
	var/obj/effect/blob/B = (locate() in T)
	if(!B)
		if(prob(get_integrity()))
			expand(T)
		return
	B.pulse(forceLeft - 1, dirs)

/// Projectile adapter: the blob's resistances divide the round.
/obj/effect/blob/projectile_damage(obj/item/projectile/P, def_zone)
	var/damage_type = P.obj_damage_type()
	if(damage_type != BRUTE && damage_type != BURN)
		return 0
	return blob_damage(P.damage, damage_type)

/obj/effect/blob/attackby(obj/item/W, mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	playsound(src, 'sound/effects/attackblob.ogg', 50, 1)
	visible_message(span_danger("\The [src] has been attacked with \the [W][(user ? " by [user]." : ".")]"))
	var/damage_type = W.obj_damage_type()
	if(damage_type == BURN && W.has_tool_quality(TOOL_WELDER))
		playsound(src, W.usesound, 100, 1)
	if(damage_type == BRUTE || damage_type == BURN)
		blob_damage(W.force, damage_type)

/obj/effect/blob/core
	name = "blob core"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blob_core"
	light_range = 3
	light_color = "#ffc880"
	max_integrity = 200
	brute_resist = 2
	fire_resist = 2

	expandType = /obj/effect/blob/shield

/obj/effect/blob/core/update_icon()
	return

/obj/effect/blob/core/Initialize(mapload)
	. = ..()
	REACT_PROCESS(src, 2 SECONDS, "pulses outward in all four diagonal directions")

/obj/effect/blob/core/process()
	pulse(20, list(NORTH, EAST))
	pulse(20, list(NORTH, WEST))
	pulse(20, list(SOUTH, EAST))
	pulse(20, list(SOUTH, WEST))

/obj/effect/blob/shield
	name = "strong blob"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blob_idle"
	light_range = 3
	desc = "Some blob creature thingy"
	max_integrity = 60
	brute_resist = 1
	fire_resist = 2

/obj/effect/blob/shield/Initialize(mapload)
	. = ..()
	update_nearby_tiles()

/obj/effect/blob/shield/Destroy()
	density = FALSE
	update_nearby_tiles()
	. = ..()

/obj/effect/blob/shield/update_icon()
	if(get_integrity() > max_integrity * 2 / 3)
		icon_state = "blob_idle"
	else if(get_integrity() > max_integrity / 3)
		icon_state = "blob"
	else
		icon_state = "blob_damaged"

/obj/effect/blob/shield/CanPass(atom/movable/mover, turf/target)
	return !density
