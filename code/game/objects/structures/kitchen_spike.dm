//////Kitchen Spike

/obj/structure/kitchenspike
	name = "meat spike"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "spike"
	desc = "A spike for collecting meat from animals."
	density = TRUE
	anchored = TRUE
	var/meat = 0
	var/occupied = FALSE
	var/meat_type
	var/victim_name = "corpse"

TRACKED(/obj/structure/kitchenspike, occupied)

CAPABILITIES(/obj/structure/kitchenspike)
	op("spike", item(/obj/item/grab), label("Use"), then(PROC_REF(interaction_item)))
	op("carve", hand(), label("Carve"), when(nameof(occupied)), then(PROC_REF(interaction_hand)))

/// A grab forces the grabbed mob onto the spike.
/obj/structure/kitchenspike/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/grab/G = A.held
	if(!istype(G, /obj/item/grab) || !ismob(G?.grab_target()))
		return OP_OK
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
	return OP_OK

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
	set_occupied(TRUE)
	meat = 5
	return 1

/// A hand carves meat off the spiked corpse (offered only while one is on it).
/obj/structure/kitchenspike/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	meat--
	new meat_type(get_turf(src))
	if(meat > 1)
		to_chat(user, "You cut some meat from \the [victim_name]'s body.")
	else if(meat == 1)
		to_chat(user, "You remove the last piece of meat from \the [victim_name]!")
		icon_state = "spike"
		set_occupied(FALSE)
	return OP_OK
