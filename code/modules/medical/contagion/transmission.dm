// Contagion transmission: the trigger that turns exposure into infection.
//
// /datum/affliction_trigger/contagion is the one rule for how a contagion
// reaches a new host. Every contagion carries a transmission profile:
//   spread_flags      routes (DISEASE_SPREAD_AIRBORNE / CONTACT / BLOOD / FLUIDS)
//   infectivity       % chance per spread-lane step that an airborne carrier
//                     sheds into the air around it
//   permeability_mod  how well it gets past protection (clothing, masks)
//
// Exposure arrives on one of three routes (CONTAGION_ROUTE_*):
//   airborne  a carrier's breath (the spread lane below, coughs and sneezes):
//             internals and breath-proof hosts are safe, a mask filters
//   contact   touch, blood on the floor, a bump: the clothing on the body
//             zone filters (the old ContractDisease() rules)
//   blood     injection, ingestion, transfusion: nothing filters
// and then can_contract_contagion() (immunity, required organs, species
// carriers) decides whether it takes.
//
// Airborne shedding runs on a parkable periodic lane: a contagion that can
// spread through the air starts itself on PERIODIC_SLOW when it joins a body
// and parks when it leaves, goes dormant or loses the route. Nothing polls
// every mob every tick. Contact and blood routes are event driven (touch,
// bump, decals, reagents).

/datum/affliction_trigger/contagion
	name = "Contagion exposure"
	category = "Infection"
	subcategory = "Communicable disease"
	description = "An infectious agent passed from a carrier: through the air, by touch or through blood. Protective clothing, masks and internals block exposure; a body that has beaten a strain before is immune to it."

/// The book lists every contagion this trigger can produce.
/datum/affliction_trigger/contagion/setup()
	..()
	for(var/path in subtypesof(/datum/affliction/contagion))
		var/datum/affliction/contagion/proto = path
		if(!initial(proto.max_stages))
			continue
		if(initial(proto.spread_flags) & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS))
			continue
		declare(path, initial(proto.infectivity))

/// The shared contagion trigger.
/proc/contagion_trigger()
	RETURN_TYPE(/datum/affliction_trigger/contagion)
	var/static/datum/affliction_trigger/contagion/trigger
	if(!trigger)
		trigger = new
	return trigger

/// Expose `target` to contagion `D` through `route`. Protection for the route
/// applies, then the host has to be able to contract it. Returns TRUE when
/// the target was infected.
/datum/affliction_trigger/contagion/proc/expose(mob/living/target, datum/affliction/contagion/D, route = CONTAGION_ROUTE_CONTACT, target_zone)
	if(!istype(target) || !D || QDELETED(target))
		return FALSE
	if(!target.can_contract_contagion(D))
		return FALSE
	if(!passes_protection(target, D, route, target_zone))
		return FALSE
	var/datum/affliction/contagion/infection = D.try_infect(target)
	if(!infection)
		return FALSE
	log_game("CONTAGION: [key_name(target)] contracted [infection.name] ([infection.GetDiseaseID()]) by [route] exposure[target_zone ? " to [target_zone]" : ""].")
	return TRUE

/// Does exposure through `route` get past `target`'s protection?
/datum/affliction_trigger/contagion/proc/passes_protection(mob/living/target, datum/affliction/contagion/D, route, target_zone)
	switch(route)
		if(CONTAGION_ROUTE_BLOOD)
			return TRUE
		if(CONTAGION_ROUTE_AIRBORNE)
			return passes_airborne(target, D)
	return passes_contact(target, D, target_zone)

/// Breathing it in. Internals and breath-proof hosts are safe; a mask filters.
/datum/affliction_trigger/contagion/proc/passes_airborne(mob/living/target, datum/affliction/contagion/D)
	var/mob/living/carbon/C = target
	if(istype(C))
		if(C.internal)
			return FALSE
		if(C.has_mutation(mNobreath))
			return FALSE
		var/obj/item/clothing/mask = C.get_equipped_item(SLOT_ID_MASK)
		if(istype(mask) && !prob(mask.permeability_coefficient * 100))
			return FALSE
	return prob(clamp(50 * D.permeability_mod, 0, 100))

/// Skin contact on a body zone: whatever covers the zone filters.
/datum/affliction_trigger/contagion/proc/passes_contact(mob/living/target, datum/affliction/contagion/D, target_zone)
	var/mob/living/carbon/human/H = target
	if(!istype(H))
		return TRUE
	if(prob(15 / max(D.permeability_mod, 0.01)))
		return FALSE

	if(!target_zone)
		target_zone = pick(list(
			BP_HEAD = 80,
			BP_TORSO = 100,
			BP_R_HAND = 35/2,
			BP_L_HAND = 35/2,
			BP_R_FOOT = 15/2,
			BP_L_FOOT = 15/2
		))
	else
		target_zone = check_zone(target_zone)

	switch(target_zone)
		if(BP_HEAD)
			if(!clothing_passes(H.get_equipped_item(SLOT_ID_HEAD), TRUE))
				return FALSE
			return clothing_passes(H.get_equipped_item(SLOT_ID_MASK))
		if(BP_TORSO)
			if(!clothing_passes(H.get_equipped_item(SLOT_ID_SUIT)))
				return FALSE
			return clothing_passes(H.get_equipped_item(SLOT_ID_UNIFORM))
		if(BP_L_HAND, BP_R_HAND)
			var/obj/item/suit = H.get_equipped_item(SLOT_ID_SUIT)
			if(isobj(suit) && (suit.body_parts_covered & HANDS) && !clothing_passes(suit))
				return FALSE
			return clothing_passes(H.get_equipped_item(SLOT_ID_GLOVES))
		if(BP_L_FOOT, BP_R_FOOT)
			var/obj/item/suit = H.get_equipped_item(SLOT_ID_SUIT)
			if(isobj(suit) && (suit.body_parts_covered & FEET) && !clothing_passes(suit))
				return FALSE
			return clothing_passes(H.get_equipped_item(SLOT_ID_SHOES))
	return TRUE

/// One layer of clothing: passes with its permeability. Paper on the head is
/// not protection.
/datum/affliction_trigger/contagion/proc/clothing_passes(obj/item/I, head = FALSE)
	if(!isobj(I))
		return TRUE
	if(head && istype(I, /obj/item/paper))
		return TRUE
	return prob((I.permeability_coefficient * 100) - 1)

/// Shed `D` into the air around its host: every human in range with an
/// open-air path is exposed (airborne route). `force_spread` widens the range
/// and ignores the route flags (coughing fits, admin).
/datum/affliction_trigger/contagion/proc/spread_from(datum/affliction/contagion/D, force_spread = 0)
	var/mob/living/carbon/human/source = D.host
	if(!source || source.is_incorporeal())
		return 0
	if(!(D.spread_flags & DISEASE_SPREAD_AIRBORNE) && !force_spread)
		return 0
	if(source.stat == DEAD && !global_flag_check(D.virus_modifiers, SPREAD_DEAD) && !force_spread)
		return 0
	if(source.reagents?.has_reagent(REAGENT_ID_SPACEACILLIN))
		return 0
	var/turf/origin = source.loc
	if(!istype(origin))
		return 0

	var/spread_range = force_spread ? force_spread : 2
	if(D.spread_flags & DISEASE_SPREAD_AIRBORNE)
		spread_range++

	. = 0
	for(var/mob/living/carbon/human/C in oview(spread_range, source))
		if(C.is_incorporeal())
			continue
		if(!disease_air_spread_walk(origin, get_turf(C)))
			continue
		if(expose(C, D, CONTAGION_ROUTE_AIRBORNE))
			.++

/// Is there an open-air path from `end` back to `start`?
/proc/disease_air_spread_walk(turf/start, turf/end)
	if(!start || !end)
		return FALSE
	while(TRUE)
		if(end == start)
			return TRUE
		var/turf/Temp = get_step_towards(end, start)
		if(!end.CanZASPass(Temp))
			return FALSE
		end = Temp


// --- The spread lane on the contagion ------------------------------------------------

/// Can this strain shed into the air from its host right now?
/datum/affliction/contagion/proc/can_shed_airborne()
	return host && is_spreadable() && (spread_flags & DISEASE_SPREAD_AIRBORNE) && infectivity > 0 && !(virus_modifiers & DORMANT)

/// Does this strain keep its course in a dead host (the body stops ticking
/// the dead, so the lane carries it)?
/datum/affliction/contagion/proc/acts_in_dead_host()
	return host?.stat == DEAD && (virus_modifiers & SPREAD_DEAD) && !(virus_modifiers & DORMANT)

/// The spread lane runs while the strain is in a body and either sheds airborne or keeps its course in a dead host. The gate reads this strain's
/// tracked state and the host's stat through the host relation, so the every() in CAPABILITIES parks and wakes on all of it (every_hop_watch).
/datum/affliction/contagion/proc/spread_lane_wanted(datum/act/eval/A)
	return host && body && (can_shed_airborne() || acts_in_dead_host())

/// One lane step (every 2 s): a SPREAD_DEAD strain in a corpse keeps its
/// course, and an airborne strain rolls infectivity and sheds (the declaration
/// parks it once neither applies).
/datum/affliction/contagion/proc/contagion_step(datum/act/timer/A)
	var/dead_course = acts_in_dead_host()
	var/airborne = can_shed_airborne()
	if(dead_course)
		progress()
		if(QDELETED(src) || !host)
			return
	if(airborne && prob(infectivity))
		spread()

/// Shed into the air now (see /datum/affliction_trigger/contagion/proc/spread_from).
/datum/affliction/contagion/proc/spread(force_spread = 0)
	return contagion_trigger().spread_from(src, force_spread)
