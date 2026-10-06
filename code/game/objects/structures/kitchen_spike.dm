//////Kitchen Spike

/obj/structure/kitchenspike
	name = "meat spike"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "spike"
	desc = "A spike for collecting meat from animals."
	density = TRUE
	anchored = TRUE
	var/meat = 0
	var/occupied
	var/meat_type
	var/victim_name = "corpse"

/obj/structure/kitchenspike/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/kitchenspike_item,
		/datum/interaction/entry_hand/kitchenspike_hand,
	)
	..()

/// Old attackby: force a grabbed mob onto the spike.
/datum/interaction/entry_item/kitchenspike_item
	id = "kitchenspike_item"
	name = "Use"
	held_type = /obj/item/grab
	effect = /obj/structure/kitchenspike/proc/interaction_item

/obj/structure/kitchenspike/proc/interaction_item(mob/user, obj/item/grab/G, datum/interaction/interaction)
	if(!istype(G, /obj/item/grab) || !ismob(G?.grab_target()))
		return TRUE
	if(occupied)
		to_chat(user, span_danger("The spike already has something on it, finish collecting its meat first!"))
	else
		if(spike(G?.grab_target()))
			act_message(user, null, others = span_danger("%U% has forced [G?.grab_target()] onto the spike, killing [G.p_them()] instantly!"))
			var/mob/M = G?.grab_target()
			M.forceMove(src)
			consume(G, user)
			consumed(M, src)
		else
			to_chat(user, span_danger("They are too big for the spike, try something smaller!"))
	return TRUE

/obj/structure/kitchenspike/proc/spike(mob/living/victim)
	if(!istype(victim))
		return

	if(ishuman(victim))
		var/mob/living/carbon/human/H = victim
		if(istype(H.species, /datum/species/monkey))
			meat_type = H.species.meat_type
			icon_state = "spikebloody"
		else
			return 0
	else if(istype(victim, /mob/living/carbon/alien))
		meat_type = /obj/item/reagent_containers/food/snacks/xenomeat
		icon_state = "spikebloodygreen"
	else
		return 0

	victim_name = victim.name
	occupied = 1
	meat = 5
	return 1

/// Old attack_hand: carve meat off the spiked corpse.
/datum/interaction/entry_hand/kitchenspike_hand
	id = "kitchenspike_hand"
	name = "Carve"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/structure/kitchenspike/proc/kitchenspike_occupied, null))
	effect = /obj/structure/kitchenspike/proc/interaction_hand

/obj/structure/kitchenspike/proc/kitchenspike_occupied(mob/actor, atom/target, obj/item/held)
	return !!occupied

/obj/structure/kitchenspike/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	meat--
	new meat_type(get_turf(src))
	if(meat > 1)
		to_chat(user, "You cut some meat from \the [victim_name]'s body.")
	else if(meat == 1)
		to_chat(user, "You remove the last piece of meat from \the [victim_name]!")
		icon_state = "spike"
		occupied = 0
	return TRUE
