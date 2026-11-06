/// Fluff item for digitalsquirrel

/obj/item/toy/acorn_branch
	name = "oak staff"
	desc = "A branch of oak wood bearing a collection of still living leaves, and many acorns hanging among them."
	icon = 'icons/obj/items.dmi'
	icon_state = "acorn_branch"
	w_class = ITEMSIZE_SMALL
	COOLDOWN_DECLARE(next_use)
	var/registered_mob // Weak handle of the one person who may use it; a registrant who is gone frees the branch for the next person.

CAPABILITIES(/obj/item/toy/acorn_branch)
	ref_one(nameof(registered_mob), /mob/living/carbon/human, weak = TRUE)
	op("pick_acorn", in_hand(), when(req_actor_kind(/mob/living/carbon/human)), needs(req_conscious()), then(PROC_REF(interaction_self)))

/// Old attack_self: a person pulls an acorn out (one at a time, and only its registered owner).
/obj/item/toy/acorn_branch/proc/interaction_self(datum/act/op/A)
	var/mob/living/carbon/human/H = A.actor
	var/mob/user = H
	if(!COOLDOWN_FINISHED(src, next_use))
		to_chat(user, span_notice("You need to wait a bit longer before you can pull out another acorn."))
		return OP_OK
	if(registered_mob())
		if(registered_mob() != H)
			to_chat(user, span_notice("It's a lovely branch!"))
			return OP_OK
	else
		rel_set(src, nameof(registered_mob), H)
	if(H.get_inactive_hand())
		to_chat(user, span_notice("You need to have a free hand to pick an acorn out!"))
		return OP_OK
	var/spawnloc = get_turf(H)
	var/obj/item/I = new /obj/item/reagent_containers/food/snacks/acorn(spawnloc)
	H.put_in_inactive_hand(I)
	COOLDOWN_START(src, next_use, 30 SECONDS)
	act_message(H, src, others = span_notice("%U% pulls an acorn from %T%!"))
	return OP_OK
