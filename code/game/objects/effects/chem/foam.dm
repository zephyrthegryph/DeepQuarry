// Foam
// Similar to smoke, but spreads out more
// metal foams leave behind a foamed metal wall

/obj/effect/effect/foam
	name = "foam"
	icon_state = "foam"
	opacity = 0
	anchored = TRUE
	density = FALSE
	layer = OBJ_LAYER + 0.9
	mouse_opacity = 0
	animate_movement = 0
	var/amount = 3
	var/expand = 1
	var/metal = 0
	var/dries = 1
	var/slips = 0

CAPABILITIES(/obj/effect/effect/foam)
	when(nameof(dries), after_init(15 SECONDS, then(PROC_REF(harden))))
	when(nameof(dries), after_init(12 SECONDS, then(PROC_REF(pre_harden))))
	param(nameof(metal), pos = 1)

// ALLOW(init/INSTANCE_STATE): foam bubbles, spreads and, when it dries, hardens on timers from its creation
/obj/effect/effect/foam/Initialize(mapload)
	. = ..()
	play_sfx(src, SFX_EFFECTS_BUBBLES2)
	if(dries)
		after(src, 3 + metal * 3, PROC_REF(post_spread))

/obj/effect/effect/foam/proc/post_spread()
	periodic_step()
	checkReagents()

/obj/effect/effect/foam/proc/pre_harden(datum/act/A)
	return

/obj/effect/effect/foam/proc/harden(datum/act/A)
	if(metal)
		var/obj/structure/foamedmetal/M = new(src.loc)
		M.metal = metal
	flick("[icon_state]-disolve", src)
	expire(5)

/obj/effect/effect/foam/proc/checkReagents() // transfer any reagents to the floor
	if(!metal && reagents)
		var/turf/T = get_turf(src)
		reagents.touch_turf(T)
		for(var/obj/O in turf_contents_of_type(T, /obj))
			reagents.touch_obj(O)

/obj/effect/effect/foam/periodic_step()
	if(--amount < 0)
		return

	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		if(!T)
			continue

		if(!T.Enter(src))
			continue

		var/obj/effect/effect/foam/F = locate_on(T, /obj/effect/effect/foam)
		if(F)
			continue

		F = new(T, metal)
		F.amount = amount
		if(!metal)
			F.create_reagents(10)
			if(reagents)
				for(var/datum/reagent/R in reagents.reagent_list)
					F.reagents.add_reagent(R.id, 1, safety = 1) //added safety check since reagents in the foam have already had a chance to react

/// Heat behaviour rule: foam dissolves when heated, except metal foam.
/obj/effect/effect/foam/proc/rule_dissolve(datum/rule/rule)
	if(metal)
		return
	flick("[icon_state]-disolve", src)
	expire(5)

/obj/effect/effect/foam/Crossed(atom/movable/AM)
	if(AM.is_incorporeal())
		return
	if(metal)
		return
	if(slips && isliving(AM))
		var/mob/living/M = AM
		M.slip("the foam", 6)

/datum/effect/effect/system/foam_spread
	var/amount = 5				// the size of the foam spread.
	var/list/carried_reagents	// the IDs of reagents present when the foam was mixed
	var/metal = 0				// 0 = foam, 1 = metalfoam, 2 = ironfoam

/datum/effect/effect/system/foam_spread/set_up(amt=5, loca, datum/reagents/carry = null, metalfoam = 0)
	amount = round(sqrt(amt / 3), 1)
	if(istype(loca, /turf/))
		rel_set(src, nameof(location), loca)
	else
		rel_set(src, nameof(location), get_turf(loca))

	carried_reagents = list()
	metal = metalfoam

	// bit of a hack here. Foam carries along any reagent also present in the glass it is mixed with (defaults to water if none is present). Rather than actually transfer the reagents, this makes a list of the reagent ids and spawns 1 unit of that reagent when the foam disolves.

	if(carry && !metal)
		for(var/datum/reagent/R in carry.reagent_list)
			carried_reagents += R.id

/datum/effect/effect/system/foam_spread/proc/do_start()
	var/obj/effect/effect/foam/F = locate_within(get_location(), /obj/effect/effect/foam)
	if(F)
		F.amount += amount
		return

	F = new /obj/effect/effect/foam(get_location(), metal)
	F.amount = amount

	if(!metal) // don't carry other chemicals if a metal foam
		F.create_reagents(10)

		if(carried_reagents)
			for(var/id in carried_reagents)
				F.reagents.add_reagent(id, 1, safety = 1) //makes a safety call because all reagents should have already reacted anyway
		else
			F.reagents.add_reagent(REAGENT_ID_WATER, 1, safety = 1)

/datum/effect/effect/system/foam_spread/start()
	do_start()

// wall formed by metal foams, dense and opaque, but easy to break

/obj/structure/foamedmetal
	icon = 'icons/effects/effects.dmi'
	icon_state = "metalfoam"
	density = TRUE
	opacity = 1 // changed in New()
	anchored = TRUE
	name = "foamed metal"
	desc = "A lightweight foamed metal wall."
	can_atmos_pass = ATMOS_PASS_NO
	var/metal = 1 // 1 = aluminum, 2 = iron

/obj/structure/foamedmetal/Initialize(mapload)
	. = ..()
	update_nearby_tiles(1)

/// The look (the draw sweep: from its layers).
/obj/structure/foamedmetal/draw(datum/look/look)
	..()
	switch("[metal]")
		if("1")
			look.state("metalfoam")
		else
			look.state("ironfoam")

/obj/structure/foamedmetal/bullet_act(obj/item/projectile/P)
	if(istype(P, /obj/item/projectile/test))
		return
	else if(metal == 1 || prob(50))
		consume(src)

CAPABILITIES(/obj/structure/foamedmetal)
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_hand.
/obj/structure/foamedmetal/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if ((user.has_mutation(HULK)) || (prob(75 - metal * 25)))
		act_message(user, null, MSG_SELF(span_notice("You smash through the metal foam wall.")), \
			MSG_OTHERS(span_warning("%U% smashes through the foamed metal.")))
		consume(src, user)
	else
		to_chat(user, span_notice("You hit the metal foam but bounce off it."))
	return TRUE

/// Old attackby.
/obj/structure/foamedmetal/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/grab))
		var/obj/item/grab/G = I
		var/mob/grabbed = G?.grab_target()
		grabbed.forceMove(src.loc)
		visible_message(span_warning("[G?.grab_assailant()] smashes [grabbed] through the foamed metal wall."))
		consume(I, user)
		consume(src, user)
		return OP_PASS

	if(prob(I.force * 20 - metal * 25))
		act_message(user, null, MSG_SELF(span_notice("You smash through the foamed metal with %I%.")), \
			MSG_OTHERS(span_warning("%U% smashes through the foamed metal.")), \
			item = I)
		consume(src, user)
	else
		to_chat(user, span_notice("You hit the metal foam to no effect."))
	return OP_PASS

/obj/effect/effect/foam/firefighting
	name = "firefighting foam"
	icon_state = "mfoam" //Whiter
	color = "#A6FAFF"
	var/lifetime = 3
	dries = FALSE // We do this ourselves
	slips = FALSE

CAPABILITIES(/obj/effect/effect/foam/firefighting)
	after_init(PROC_REF(foam_lifetime), then(PROC_REF(dissolve)))

/// How long it lasts: the old lifetime, one per 2 s step.
/obj/effect/effect/foam/firefighting/proc/foam_lifetime(datum/act/timer/A)
	return (lifetime + 1) * 2 SECONDS

/obj/effect/effect/foam/firefighting/proc/dissolve(datum/act/timer/A)
	flick("[icon_state]-disolve", src)
	expire(5)

