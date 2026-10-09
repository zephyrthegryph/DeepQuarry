/mob
	var/bloody_hands = 0
	var/track_blood = 0
	var/list/feet_blood_DNA
	var/track_blood_type
	var/feet_blood_color

/obj/item/clothing/gloves
	var/transfer_blood = 0

/obj/item/clothing/shoes/
	var/track_blood = 0

/obj/item/reagent_containers/glass/rag
	name = "rag"
	desc = "For cleaning up messes, you suppose."
	w_class = ITEMSIZE_TINY
	icon = 'icons/obj/toy.dmi'
	icon_state = "rag"
	amount_per_transfer_from_this = 5
	max_transfer_amount = 5
	volume = 10
	flags = OPENCONTAINER | NOBLUDGEON
	unacidable = FALSE
	drop_sound = SFX_ITEMS_DROP_CLOTH
	pickup_sound = SFX_ITEMS_PICKUP_CLOTH

	var/burn_time = 20 //if the rag burns for too long it turns to ashes

/obj/item/reagent_containers/glass/rag/var/rag_lit = FALSE
TRACKED(/obj/item/reagent_containers/glass/rag, rag_lit)

// A rag is not a container that is poured and drunk from: it soaks up from a tank or a bucket, wrings out into an open container (or onto the floor), wipes
// things and people, smothers somebody whose mouth is aimed at, and is set alight by a flame when it is soaked in spirits or fuel (wiper(), and the ops
// below). It keeps the glass handling: a label, a dip, a hot thing over blood.
CAPABILITIES(/obj/item/reagent_containers/glass/rag)
	without(CAP_GLASS_CONTAINER)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this))
	wiper(soaks_from = list(/obj/structure/reagent_dispensers, /obj/item/reagent_containers/glass/bucket, /obj/structure/mopbucket), burning = nameof(rag_lit))
	extend("wiper.soak", then(PROC_REF(name_refreshed)))
	extend("wiper.wring_into", then(PROC_REF(name_refreshed)))
	op("stamp_out", in_hand(), when(nameof(rag_lit)), label("Stamp it out"), then(PROC_REF(stamped_out)))
	op("wring_out", in_hand(), when(cond_not(nameof(rag_lit))), label("Wring it out"),
		needs(req_reagents(1, because = MSG(wiper/dry))), begins(MSG(rag/begin_wring_floor)), wait(PROC_REF(wring_floor_time)), then(PROC_REF(wrung_out)))
	op("light", item(/obj/item/flame), when(cond_not(nameof(rag_lit))), label("Light it"), then(PROC_REF(lit_by_flame)))
	op("rub", at_target(/mob/living), priority(OP_PRIORITY_PART), label("Use on"), begins(PROC_REF(rub_begins)), wait(PROC_REF(rub_wait)), then(PROC_REF(rubbed)))
	every(2 SECONDS, then(PROC_REF(rag_step)), when = nameof(rag_lit))

MSG_DEF(rag/begin_wring_floor, "You begin to wring out %I% over the floor.", "%U% begins to wring out %I%.")

/// What the rag is called follows what it holds and whether it burns.
/obj/item/reagent_containers/glass/rag/proc/name_refreshed(datum/act/op/A)
	update_name()
	return OP_OK

/obj/item/reagent_containers/glass/rag/Initialize(mapload)
	. = ..()
	update_name()

/// What a person reads when they look from two tiles: what is in it (a glass container says it through its capability; a rag is not one).
/obj/item/reagent_containers/glass/rag/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		if(reagents && reagents.reagent_list.len)
			. += span_notice("It contains [reagents.total_volume] units of liquid.")
		else
			. += span_notice("It is empty.")

/// Used in hand while it burns: it is stamped out.
/obj/item/reagent_containers/glass/rag/proc/stamped_out(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_warning("You stamp out %T%.")), MSG_OTHERS(span_warning("%U% stamps out %T%.")))
	user.unEquip(src)
	extinguish()
	return OP_OK

/// A lit flame held to it: it catches if it is soaked in something that burns.
/obj/item/reagent_containers/glass/rag/proc/lit_by_flame(datum/act/op/A)
	light_with(A.held, A.actor)
	return OP_OK

/// A flame held to it (by a hand, or by the bottle it is stuffed in).
/obj/item/reagent_containers/glass/rag/proc/light_with(obj/item/flame/F, mob/user)
	if(!rag_lit && F.lit)
		ignite()
		if(rag_lit)
			act_message(user, src, others = span_warning("%U% lights %T% with [F]."))
		else
			to_chat(user, span_warning("You manage to singe [src], but fail to light it."))
	update_name()
	return

/obj/item/reagent_containers/glass/rag/proc/update_name()
	if(rag_lit)
		name = "burning [initial(name)]"
	else if(reagents.total_volume)
		name = "damp [initial(name)]"
	else
		name = "dry [initial(name)]"

/// The look: the rag, lit or not.
/obj/item/reagent_containers/glass/rag/draw(datum/look/look)
	..()
	look.state(rag_lit ? "raglit" : "rag")

/// How long it takes to wring it out over the floor: five deciseconds a unit.
/obj/item/reagent_containers/glass/rag/proc/wring_floor_time(datum/act/A)
	return reagents.total_volume * 5

/// Wrung out over the floor under the one wringing.
/obj/item/reagent_containers/glass/rag/proc/wrung_out(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.loc || !reagents.total_volume)
		return OP_REFUSED
	reagents.splash(user.loc, reagents.total_volume)
	act_message(user, src, MSG_SELF(span_notice("You finish to wringing out %T%.")), MSG_OTHERS(span_danger("%U% wrings out %T% over \the [user.loc].")))
	update_name()
	return OP_OK

/// Used on a person: it will wipe them (a wait) unless it burns or the mouth is aimed at.
/obj/item/reagent_containers/glass/rag/proc/rub_wipes(mob/user)
	return !rag_lit && user.zone_sel.selecting != O_MOUTH && !!reagents.total_volume

/obj/item/reagent_containers/glass/rag/proc/rub_wait(datum/act/A)
	var/datum/act/op/O = A
	return rub_wipes(O.actor) ? 3 SECONDS : 0

/// The one who begins to wipe somebody is seen to.
/obj/item/reagent_containers/glass/rag/proc/rub_begins(datum/act/A)
	var/datum/act/op/O = A
	if(rub_wipes(O.actor))
		act_message(O.actor, O.target, others = "%U% starts to wipe %T% with [src].")
		update_name()
	return null

/// Used on a person: it sets them alight if it burns, smothers them if the mouth is aimed at, else wipes them.
/obj/item/reagent_containers/glass/rag/proc/rubbed(datum/act/op/A)
	var/mob/living/target = A.target
	var/mob/living/user = A.actor
	if(rag_lit) //Check if rag is on fire, if so igniting them and stopping.
		act_message(user, target, others = span_danger("%U% hits %T% with [src]!"))
		user.do_attack_animation(src)
		target.ignite_mob()
		return OP_OK
	if(user.zone_sel.selecting == O_MOUTH) //Check player target location, provided the rag is not on fire. Then check if mouth is exposed.
		if(!ishuman(target)) //Added this since player species process reagents in majority of cases.
			to_chat(user, span_warning("You can't smother this creature."))
			return OP_REFUSED
		var/mob/living/carbon/human/H = target
		if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)) //Check human head coverage.
			to_chat(user, span_warning("Remove their [H.get_equipped_item(SLOT_ID_HEAD)] first."))
			return OP_REFUSED
		if(!reagents.total_volume)
			to_chat(user, span_warning("You can't smother this creature."))
			return OP_REFUSED
		user.do_attack_animation(src)
		act_message(user, target, MSG_SELF(span_warning("You smother %T% with [src]!")), \
			MSG_OTHERS(span_danger("%U% smothers %T% with [src]!")), \
			MSG_BLIND("You hear some struggling and muffled cries of surprise"))
		//it's inhaled, so... maybe CHEM_BLOOD doesn't make a whole lot of sense but it's the best we can do for now
		reagents.trans_to_mob(target, amount_per_transfer_from_this, CHEM_BLOOD)
		update_name()
		return OP_OK
	if(!reagents.total_volume)
		to_chat(user, span_warning("The [initial(name)] is dry!"))
		return OP_REFUSED
	act_message(user, target, others = "%U% finishes wiping %T%!")
	target.on_rag_wipe(src)
	return OP_OK

/// Heat behaviour rule: a soaked rag lights at 50 C.
/obj/item/reagent_containers/glass/rag/proc/rule_ignite_rag(datum/rule/rule)
	ignite()

/// Heat behaviour rule: at 900 C the rag burns to ash and feeds the fire.
/obj/item/reagent_containers/glass/rag/proc/rule_ash(datum/rule/rule)
	var/turf/T = get_turf(src)
	T?.feed_lingering_fire(0.1)
	new /obj/effect/decal/cleanable/ash(T)
	destroyed(src, null, BURN)

//rag must have a minimum of 2 units welder fuel or ehtanol based reagents and at least 80% of the reagents must so.
/obj/item/reagent_containers/glass/rag/proc/can_ignite()
	var/fuel
	if(reagents.get_reagent_amount(REAGENT_ID_FUEL))
		fuel += reagents.get_reagent_amount(REAGENT_ID_FUEL)

	else
		for(var/datum/reagent/ethanol/R in reagents.reagent_list)
			fuel += reagents.get_reagent_amount(R.id)

	return (fuel >= 2 && fuel >= reagents.total_volume*0.8)

/obj/item/reagent_containers/glass/rag/proc/ignite()
	if(rag_lit)
		return
	if(!can_ignite())
		return

	//also copied from matches
	if(reagents.get_reagent_amount(REAGENT_ID_PHORON)) // the phoron explodes when exposed to fire
		visible_message(span_danger("\The [src] conflagrates violently!"))
		var/datum/effect/effect/system/reagents_explosion/e = new()
		e.set_up(round(reagents.get_reagent_amount(REAGENT_ID_PHORON) / 2.5, 1), get_turf(src), 0, 0)
		e.start()
		destroyed(src, null, "explosion")
		return

	set_light(2, null, "#E38F46")
	set_rag_lit(TRUE)
	update_name()

/obj/item/reagent_containers/glass/rag/extinguish()
	. = ..()
	set_light(0)
	set_rag_lit(FALSE)

	//rags sitting around with 1 second of burn time left is dumb.
	//ensures players always have a few seconds of burn time left when they light their rag
	if(burn_time <= 5)
		visible_message(span_warning("\The [src] falls apart!"))
		replace_with(src, /obj/effect/decal/cleanable/ash)
	update_name()

/obj/item/reagent_containers/glass/rag/proc/rag_step(datum/act/timer/A)
	if(!can_ignite())
		visible_message(span_warning("\The [src] burns out."))
		extinguish()
		return

	//copied from matches
	if(isliving(loc))
		var/mob/living/M = loc
		M.ignite_mob()
	var/turf/location = get_turf(src)
	if(location)
		location.hotspot_expose(700, 5)

	if(burn_time <= 0)
		new /obj/effect/decal/cleanable/ash(location)
		destroyed(src, null, BURN)
		return

	reagents.remove_reagent(REAGENT_ID_FUEL, reagents.maximum_volume/25)
	for(var/datum/reagent/ethanol/R in reagents.reagent_list)
		if(istype(R, /datum/reagent/ethanol))
			reagents.remove_reagent(R.id, reagents.maximum_volume/25)
	update_name()
	burn_time--
