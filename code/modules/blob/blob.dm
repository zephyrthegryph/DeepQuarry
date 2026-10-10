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

/obj/effect/blob/CanPass(atom/movable/mover, turf/target)
	return FALSE


/// A blast hurts the blob by its own severity ladder, scaled down by its brute resistance (instead of the blast packet).
/obj/effect/blob/proc/blob_blast_damage(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	switch(packet.severity)
		if(1)
			take_damage(rand(100, 120) / brute_resist)
		if(2)
			take_damage(rand(60, 100) / brute_resist)
		if(3)
			take_damage(rand(20, 60) / brute_resist)
	return OP_OK

/obj/effect/blob/proc/appearance_state()
	return get_integrity() > max_integrity / 2 ? "blob" : "blob_damaged"

/// The look (the draw sweep: from its template).
/obj/effect/blob/draw(datum/look/look)
	..()
	look.state("[appearance_state()]")

/obj/effect/blob/on_update_integrity(old_value, new_value)
	. = ..()

/obj/effect/blob/atom_destruction(damage_flag)
	play_sfx(src, SFX_EFFECTS_SPLAT)
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
	var/obj/structure/girder/G = locate_on(T, /obj/structure/girder)
	if(G)
		if(prob(40))
			G.dismantle()
		return
	var/obj/structure/window/W = locate_on(T, /obj/structure/window)
	if(W)
		W.shatter()
		return
	var/obj/structure/grille/GR = locate_on(T, /obj/structure/grille)
	if(GR)
		destroyed(GR, src)
		return
	for(var/obj/structure/reagent_dispensers/fueltank/Fuel in turf_contents_of_type(T, /obj/structure/reagent_dispensers/fueltank))
		Fuel.ex_act(2)
		return
	for(var/obj/machinery/door/D in turf_contents_of_type(T, /obj/machinery/door)) // There can be several - and some of them can be open, locate() is not suitable
		if(D.density)
			D.ex_act(2)
			return
	var/obj/structure/foamedmetal/F = locate_on(T, /obj/structure/foamedmetal)
	if(F)
		destroyed(F, src)
		return
	var/obj/structure/inflatable/I = locate_on(T, /obj/structure/inflatable)
	if(I)
		I.deflate(1)
		return

	var/obj/vehicle/V = locate_on(T, /obj/vehicle)
	if(V)
		V.ex_act(2)
		return
	var/obj/mecha/M = locate_on(T, /obj/mecha)
	if(M)
		M.visible_message(span_danger("The blob attacks \the [M]!"))
		M.take_damage(40)
		return

	// Above things, we destroy completely and thus can use locate. Mobs are different.
	for(var/mob/living/L in turf_contents_of_type(T, /mob/living))
		if(L.stat == DEAD)
			continue
		act_message(L, null, MSG_SELF(span_danger("The blob attacks you!")), MSG_OTHERS(span_danger("The blob attacks %U%!")))
		play_sfx(src, SFX_EFFECTS_ATTACKBLOB)
		L.injure(INJURY_BLUNT, rand(30, 40), null, src)
		return
	new expandType(T)

/obj/effect/blob/proc/pulse(forceLeft, list/dirs)
	regen()
	animate(src, color = "#FF0000", time=1)
	animate(color = "#FFFFFF", time=4, easing=ELASTIC_EASING)
	after(src, 0.5 SECONDS, PROC_REF(pulse_on), with = list(forceLeft, dirs))

/// The rest of a pulse, after its flash.
/obj/effect/blob/proc/pulse_on(forceLeft, list/dirs)
	var/pushDir = pick(dirs)
	var/turf/T = get_step(src, pushDir)
	var/obj/effect/blob/B = (locate_within(T, /obj/effect/blob))
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

CAPABILITIES(/obj/effect/blob)
	op("hit_blob", item(/obj/item), then(PROC_REF(interaction_hit_blob)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(blob_blast_damage))))

/// Old attackby: any item hits the blob (afterattack still follows, as before).
/obj/effect/blob/proc/interaction_hit_blob(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/obj/item/W = held
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	play_sfx(src, SFX_EFFECTS_ATTACKBLOB)
	act_message(src, user, others = span_danger("%U% has been attacked with %I%[user ? " by %T%." : "."]"), item = W)
	var/damage_type = W.obj_damage_type()
	if(damage_type == BURN && W.has_tool_quality(TOOL_WELDER))
		playsound(src, W.usesound, 100, 1)
	if(damage_type == BRUTE || damage_type == BURN)
		blob_damage(W.force, damage_type)
	return OP_PASS

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

/// The look: the mapped sprite, none of what the types above draw.
/obj/effect/blob/core/draw(datum/look/look)
	..()
	// the mapped sprite, without the parent's states and layers
	look.state(null)

CAPABILITIES(/obj/effect/blob/core)
	every(2 SECONDS, then(PROC_REF(blob_core_step)))

/obj/effect/blob/core/proc/blob_core_step(datum/act/timer/A)
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

/obj/effect/blob/shield/appearance_state()
	if(get_integrity() > max_integrity * 2 / 3)
		return "blob_idle"
	if(get_integrity() > max_integrity / 3)
		return "blob"
	return "blob_damaged"

/obj/effect/blob/shield/CanPass(atom/movable/mover, turf/target)
	return !density
