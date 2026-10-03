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

OM_FIELD(/obj/item/reagent_containers/glass/rag, rag_lit, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/reagent_containers/glass/rag, PERIODIC_SLOW, "rag_lit")

// A rag is not a container that is poured and drunk from: it wrings itself out, wipes, smothers and soaks by the rules below (it keeps the glass
// handling: a label, a dip, a hot thing over blood).
CAPABILITIES(/obj/item/reagent_containers/glass/rag, \
	without(CAP_GLASS_CONTAINER))

/obj/item/reagent_containers/glass/rag/Initialize(mapload)
	. = ..()
	update_name()

EXTEND_INTERACTIONS(/obj/item/reagent_containers/glass/rag, \
	INTERACT_SELF(null, PROC_REF(rag_self)), \
	INTERACT_ITEM_AS(I_HELP, null, PROC_REF(rag_item)), \
	INTERACT_ITEM_AS(I_DISARM, "Dip into it", PROC_REF(rag_item)), \
	INTERACT_ITEM_AS(I_GRAB, "Dip into it", PROC_REF(rag_item)), \
	INTERACT_ITEM_AS(I_HURT, "Dip into it", PROC_REF(rag_item)), \
)

/// What a person reads when they look from two tiles: what is in it (a glass container says it through its capability; a rag is not one).
/obj/item/reagent_containers/glass/rag/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		if(reagents && reagents.reagent_list.len)
			. += span_notice("It contains [reagents.total_volume] units of liquid.")
		else
			. += span_notice("It is empty.")

/// Old attack_self.
/obj/item/reagent_containers/glass/rag/proc/rag_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(rag_lit)
		act_message(user, src, MSG_SELF(span_warning("You stamp out %T%.")), MSG_OTHERS(span_warning("%U% stamps out %T%.")))
		user.unEquip(src)
		extinguish()
	else
		remove_contents(user)
	return TRUE

/// Old attackby: its own lighting, then the name update. A pen, a dip or a hot thing over blood is the glass handling's (its ops come first).
/obj/item/reagent_containers/glass/rag/proc/rag_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(!rag_lit && istype(W, /obj/item/flame))
		var/obj/item/flame/F = W
		if(F.lit)
			src.ignite()
			if(rag_lit)
				act_message(user, src, others = span_warning("%U% lights %T% with [W]."))
			else
				to_chat(user, span_warning("You manage to singe [src], but fail to light it."))

	update_name()
	return INTERACTION_HANDLED_PASS

/obj/item/reagent_containers/glass/rag/proc/update_name()
	if(rag_lit)
		name = "burning [initial(name)]"
	else if(reagents.total_volume)
		name = "damp [initial(name)]"
	else
		name = "dry [initial(name)]"

DECLARE_APPEARANCE_PROC(/obj/item/reagent_containers/glass/rag, TYPE_PROC_REF(/atom, appearance_overlays), list("rag_lit"))
/obj/item/reagent_containers/glass/rag/appearance_overlays()
	. = list()
	if(rag_lit)
		icon_state = "raglit"
	else
		icon_state = "rag"

	var/obj/item/reagent_containers/food/drinks/bottle/B = loc
	if(istype(B))
		B.update_icon()

/obj/item/reagent_containers/glass/rag/proc/remove_contents(mob/user, atom/trans_dest = null)
	if(!trans_dest && !user.loc)
		return

	if(reagents.total_volume)
		var/target_text = trans_dest? "\the [trans_dest]" : "\the [user.loc]"
		act_message(user, src, MSG_SELF(span_notice("You begin to wring out %T% over [target_text].")), \
			MSG_OTHERS(span_danger("%U% begins to wring out %T% over [target_text].")))

		//50 for a fully soaked rag
		om_task_start(/datum/om/task/timed/rag_wring, user, src, duration = reagents.total_volume*5, trans_dest = trans_dest, target_text = target_text)

/datum/om/task/timed/rag_wring
	complete_proc = /obj/item/reagent_containers/glass/rag/proc/wring_done
	var/atom/trans_dest
	var/target_text

/obj/item/reagent_containers/glass/rag/proc/wring_done(datum/om/task/timed/rag_wring/task)
	var/mob/user = task.actor
	var/atom/trans_dest = task.trans_dest
	var/target_text = task.target_text
	if(trans_dest)
		reagents.trans_to(trans_dest, reagents.total_volume)
	else
		reagents.splash(user.loc, reagents.total_volume)
	act_message(user, src, MSG_SELF(span_notice("You finish to wringing out %T%.")), MSG_OTHERS(span_danger("%U% wrings out %T% over [target_text].")))
	update_name()

/obj/item/reagent_containers/glass/rag/proc/wipe_down(atom/A, mob/user)
	if(!reagents.total_volume)
		to_chat(user, span_warning("The [initial(name)] is dry!"))
	else
		act_message(user, A, others = "%U% starts to wipe %T% with [src].")
		update_name()
		om_task_timed(user, 3 SECONDS, src, src, PROC_REF(wipe_done), list(user, A))

/obj/item/reagent_containers/glass/rag/proc/wipe_done(mob/user, atom/A)
	act_message(user, A, others = "%U% finishes wiping %T%!")
	A.on_rag_wipe(src)

/obj/item/reagent_containers/glass/rag/attack(mob/living/target, mob/living/user, target_zone, attack_modifier)
	if(isliving(target)) //Leaving this as isliving.
		var/mob/living/M = target
		if(rag_lit) //Check if rag is on fire, if so igniting them and stopping.
			act_message(user, target, others = span_danger("%U% hits %T% with [src]!"))
			user.do_attack_animation(src)
			M.ignite_mob()
		else if(user.zone_sel.selecting == O_MOUTH) //Check player target location, provided the rag is not on fire. Then check if mouth is exposed.
			if(ishuman(target)) //Added this since player species process reagents in majority of cases.
				var/mob/living/carbon/human/H = target
				if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)) //Check human head coverage.
					to_chat(user, span_warning("Remove their [H.get_equipped_item(SLOT_ID_HEAD)] first."))
					return ITEM_INTERACT_FAILURE
				else if(reagents.total_volume) //Final check. If the rag is not on fire and their face is uncovered, smother target.
					user.do_attack_animation(src)
					act_message(user, target, MSG_SELF(span_warning("You smother %T% with [src]!")), \
						MSG_OTHERS(span_danger("%U% smothers %T% with [src]!")), \
						MSG_BLIND("You hear some struggling and muffled cries of surprise"))
					//it's inhaled, so... maybe CHEM_BLOOD doesn't make a whole lot of sense but it's the best we can do for now
					reagents.trans_to_mob(target, amount_per_transfer_from_this, CHEM_BLOOD)
					update_name()
				else
					to_chat(user, span_warning("You can't smother this creature."))
					return ITEM_INTERACT_FAILURE
			else
				to_chat(user, span_warning("You can't smother this creature."))
				return ITEM_INTERACT_FAILURE
		else
			wipe_down(target, user)
	else
		wipe_down(target, user)
	return ITEM_INTERACT_SUCCESS

/obj/item/reagent_containers/glass/rag/afterattack(atom/A as obj|turf|area, mob/user as mob, proximity)
	if(!proximity)
		return

	if(istype(A, /obj/structure/reagent_dispensers) || istype(A, /obj/item/reagent_containers/glass/bucket) || istype(A, /obj/structure/mopbucket)) // "Allows rags to be used on buckets and mopbuckets"
		if(!reagents.get_free_space())
			to_chat(user, span_warning("\The [src] is already soaked."))
			return

		if(A.reagents && A.reagents.trans_to_obj(src, reagents.maximum_volume))
			act_message(user, src, MSG_SELF(span_notice("You soak %T% using [A].")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " soaks %T% using [A].")))
			update_name()
		return

	if(!rag_lit && istype(A) && (src in user))
		if(A.is_open_container() && !(A in user))
			remove_contents(user, A)
		else if(!ismob(A)) //mobs are handled in attack() - this prevents us from wiping down people while smothering them.
			wipe_down(A, user)
		return

/// Heat behaviour rule: a soaked rag lights at 50 C.
/obj/item/reagent_containers/glass/rag/proc/rule_ignite_rag(datum/rule/rule)
	ignite()

/// Heat behaviour rule: at 900 C the rag burns to ash and feeds the fire.
/obj/item/reagent_containers/glass/rag/proc/rule_ash(datum/rule/rule)
	var/turf/T = get_turf(src)
	T?.feed_lingering_fire(0.1)
	new /obj/effect/decal/cleanable/ash(T)
	qdel(src)

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
		qdel(src)
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

/obj/item/reagent_containers/glass/rag/periodic_step()
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
		qdel(src)
		return

	reagents.remove_reagent(REAGENT_ID_FUEL, reagents.maximum_volume/25)
	for(var/datum/reagent/ethanol/R in reagents.reagent_list)
		if(istype(R, /datum/reagent/ethanol))
			reagents.remove_reagent(R.id, reagents.maximum_volume/25)
	update_name()
	burn_time--
