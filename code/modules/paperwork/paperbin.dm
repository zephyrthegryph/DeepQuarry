/obj/item/paper_bin
	name = "paper bin"
	desc = "A plastic bin full of paper. It seems to have both regular and carbon-copy paper to choose from."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "paper_bin1"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_material.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_material.dmi',
			)
	item_state = "sheet-metal"
	throwforce = 1
	w_class = ITEMSIZE_NORMAL
	throw_speed = 3
	throw_range = 7
	pressure_resistance = 10
	layer = OBJ_LAYER - 0.1
	var/amount = 30					//How much paper is in the bin.
	var/list/papers	//List of papers put in the bin for reference.
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX


/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/paper_bin/proc/mousedrop_input(datum/act/input/A)
	return pickup_with_actor(A.actor, A.over)

/obj/item/paper_bin/proc/pickup_with_actor(mob/user, mob/destination)
	if(user && user == destination && !(user.restrained() || user.stat) && (user.contents.Find(src) || in_range(src, user)))
		if(ishuman(user))
			if( !user.get_active_hand() )		//if active hand is empty
				var/mob/living/carbon/human/H = user
				var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]

				if (H.hand)
					temp = H.organs_by_name[BP_L_HAND]
				if(temp && !temp.is_usable())
					to_chat(user, span_notice("You try to move your [temp.name], but cannot!"))
					return

				to_chat(user, span_notice("You pick up the [src]."))
				user.put_in_hands(src)

	return

CAPABILITIES(/obj/item/paper_bin)
	// a hand that cannot move takes nothing; with no custom paper in the bin it asks which paper
	op("take_paper", hand(), ungated(), needs(req(PROC_REF(hand_usable), because = PROC_REF(hand_unusable_reason))),
		asks(/datum/prompt/choice, fields = list("question" = "Do you take regular paper, or Carbon copy paper?", "title" = "Paper type request", "choices" = list("Regular", "Carbon-Copy", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "k52", when = PROC_REF(no_custom_paper)),
		then(PROC_REF(interaction_hand)))
	op("put_paper", item(/obj/item/paper), then(PROC_REF(interaction_item)))
	drag_onto(PROC_REF(mousedrop_input))

/// The actor's using hand, when it is a limb that cannot be used (the old attack_hand refused it).
/obj/item/paper_bin/proc/unusable_hand(mob/user)
	var/mob/living/carbon/human/H = user
	if(!istype(H))
		return null
	var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND] // ALLOW(reads): the hand's state is read when it reaches into the bin, never cached
	if (H.hand) // ALLOW(reads): which hand is used is read when it reaches into the bin, never cached
		temp = H.organs_by_name[BP_L_HAND]
	return (temp && !temp.is_usable()) ? temp : null

/obj/item/paper_bin/proc/hand_usable(datum/act/op/A)
	return isnull(unusable_hand(A.actor))

/obj/item/paper_bin/proc/hand_unusable_reason(datum/act/op/A)
	var/obj/item/organ/external/temp = unusable_hand(A.actor)
	return "You try to move your [temp?.name], but cannot!"

/// The paper question is asked only when there is no custom paper on top.
/obj/item/paper_bin/proc/no_custom_paper(datum/act/op/A)
	return !length(papers) // ALLOW(reads): the bin's papers are read when it is reached into, never cached

/// Old attack_hand.
/obj/item/paper_bin/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	var/response = ""
	if(!length(papers) > 0)
		response = A.step_value("k52")
		if (response != "Regular" && response != "Carbon-Copy")
			add_fingerprint(user)
			return TRUE
	if(amount >= 1)
		amount--

		var/obj/item/paper/P
		if(length(papers) > 0) //If there's any custom paper on the stack, use that instead of creating a new paper.
			P = papers[length(papers)]
			rel_remove(src, nameof(papers), P)
		else
			if(response == "Regular")
				P = new /obj/item/paper
				if(GLOB.Holiday == "April Fool's Day")
					if(prob(30))
						P.info = span_red(span_bold("<font face=\"[P.crayonfont]\">HONK HONK HONK HONK HONK HONK HONK<br>HOOOOOOOOOOOOOOOOOOOOOONK<br>APRIL FOOLS</font>"))
						P.rigged = 1
						P.updateinfolinks()
			else if (response == "Carbon-Copy")
				P = new /obj/item/paper/carbon

		P.forceMove(user.loc)
		user.put_in_hands(P)
		to_chat(user, span_notice("You take [P] out of the [src]."))
	else
		to_chat(user, span_notice("[src] is empty!"))

	add_fingerprint(user)
	return TRUE


/// Old attackby: a paper goes in the bin (the click goes on).
/obj/item/paper_bin/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/paper/i = A.held
	if(!own_bring_in(src, nameof(papers), i, null, user, TRUE, null, FALSE))
		return OP_PASS
	to_chat(user, span_notice("You put [i] in [src]."))
	rel_add(src, nameof(papers), i)
	amount++
	return OP_PASS


/obj/item/paper_bin/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(amount)
			. += span_notice("There " + (amount > 1 ? "are [amount] papers" : "is one paper") + " in the bin.")
		else
			. += span_notice("There are no papers in the bin.")

/// The look (the draw sweep: from its template).
/obj/item/paper_bin/draw(datum/look/look)
	..()
	look.state("paper_bin[amount ? "1" : "0"]")
