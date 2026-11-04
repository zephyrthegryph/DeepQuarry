/obj/random/carp_plushie
	name = "Random Carp Plushie"
	desc = "This is a random plushie"
	icon = 'icons/obj/toy.dmi'
	icon_state = "basecarp"

CAPABILITIES(/obj/random/carp_plushie)
	loot(table = list(loot_types(1, typesof(/obj/item/toy/plushie/carp))))

//Large plushies.
/obj/structure/plushie
	name = "generic plush"
	desc = "A very generic plushie. It seems to not want to exist."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ianplushie"
	anchored = FALSE
	density = TRUE
	var/phrase = "I don't want to exist anymore!"
	var/opened = FALSE	// has this been slit open? this will allow you to store an object in a plushie.
	var/obj/item/stored_item	// Note: Stored items can't be bigger than the plushie itself.

/obj/structure/plushie/examine(mob/user)
	. = ..()
	if(opened)
		. += span_italics("You notice an incision has been made on [src].")
		if(in_range(user, src) && stored_item)
			. += span_italics("You can see something in there...")

CAPABILITIES(/obj/structure/plushie)
	owns_one(nameof(stored_item), /obj/item)
	op("punch", hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_punch)))
	op("hug", hand(), ungated(), stance(I_HELP), label("Hug"), then(PROC_REF(interaction_hug)))
	op("poke", hand(), ungated(), stance(I_DISARM), label("Poke"), then(PROC_REF(interaction_poke)))
	op("strangle", hand(), ungated(), stance(I_GRAB), label("Strangle"), then(PROC_REF(interaction_strangle)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	// A touch of an opened plushie takes a second to find what is stitched inside; the plushie is claimed meanwhile.
	op("find_inside", ai(), claims(CLAIM_TARGET), wait(1 SECOND), then(PROC_REF(found_inside)))

/// Old attack_hand's harm branch: punch the plushie (combat mode only).
/obj/structure/plushie/proc/interaction_punch(datum/act/op/A)
	var/mob/user = A.actor
	touch_started(user)
	act_message(user, src, MSG_SELF(span_warning("You punch %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " punches %T%!")))
	if(phrase)
		atom_say("[phrase]")
	return OP_OK

/// A touch of any kind: take out whatever is hidden inside.
/obj/structure/plushie/proc/touch_started(mob/user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(stored_item && opened && !op_claimed(src))
		perform_op(user, src, "find_inside", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

/obj/structure/plushie/proc/interaction_hug(datum/act/op/A)
	return plushie_touched(A.actor, I_HELP)

/obj/structure/plushie/proc/interaction_poke(datum/act/op/A)
	return plushie_touched(A.actor, I_DISARM)

/obj/structure/plushie/proc/interaction_strangle(datum/act/op/A)
	return plushie_touched(A.actor, I_GRAB)

/// Old attack_hand: hug it (or, holding Grab, strangle it; Disarm pokes it).
/obj/structure/plushie/proc/plushie_touched(mob/user, stance)
	touch_started(user)
	if(stance == I_HELP)
		act_message(user, src, MSG_SELF(span_notice("You hug %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " hugs %T%!")))
	else if (stance == I_GRAB)
		act_message(user, src, MSG_SELF(span_warning("You attempt to strangle %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " attempts to strangle %T%!")))
	else
		act_message(user, src, MSG_SELF(span_notice("You poke %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " pokes %T%.")))
	if(phrase) //There was no indiciation you had to use disarm intent to make it speak...So now it speaks if you touch it at all!
		atom_say("[phrase]")
	return OP_OK

/obj/structure/plushie/proc/found_inside(datum/act/op/A)
	var/mob/user = A.actor
	if(!stored_item)
		return OP_FAILED
	to_chat(user, "You find [icon2html(stored_item, user.client)] [stored_item] in [src]!")
	stored_item.forceMove(get_turf(src))
	rel_take(src, nameof(stored_item))
	return OP_OK

/// Old attackby: sew it shut, cut it open, or hide a small thing inside.
/obj/structure/plushie/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/threadneedle) && opened)
		to_chat(user, "You sew the hole in [src].")
		opened = FALSE
		return OP_PASS

	if(is_sharp(I) && !opened)
		to_chat(user, "You open a small incision in [src]. You can place tiny items inside.")
		opened = TRUE
		return OP_PASS

	if(opened)
		if(stored_item)
			to_chat(user, "There is already something in here.")
			return OP_PASS

		if(!(I.w_class > w_class))
			to_chat(user, "You place [I] inside [src].")
			if(!move_into(src, nameof(src.stored_item), I, user))
				return OP_PASS
			return OP_PASS
		else
			to_chat(user, "You open a small incision in [src]. You can place tiny items inside.")

	return OP_DECLINE

/obj/structure/plushie/ian
	name = "plush corgi"
	desc = "A plushie of an adorable corgi! Don't you just want to hug it and squeeze it and call it \"Ian\"?"
	icon_state = "ianplushie"
	phrase = "Arf!"

/obj/structure/plushie/drone
	name = "plush drone"
	desc = "A plushie of a happy drone! It appears to be smiling."
	icon_state = "droneplushie"
	phrase = "Beep boop!"

CAPABILITIES(/obj/structure/plushie/drone)
	configure(atom_rules(bubble_icon = "machine"))

/obj/structure/plushie/carp
	name = "plush carp"
	desc = "A plushie of an elated carp! Straight from the wilds of the Vir frontier, now right here in your hands."
	icon_state = "carpplushie"
	phrase = "Glorf!"

/obj/structure/plushie/beepsky
	name = "plush Officer Sweepsky"
	desc = "A plushie of a popular industrious cleaning robot! If it could feel emotions, it would love you."
	icon_state = "beepskyplushie"
	phrase = "Ping!"

CAPABILITIES(/obj/structure/plushie/beepsky)
	configure(atom_rules(bubble_icon = "security"))

/// Balloon structures

/obj/structure/balloon
	name = "generic balloon"
	desc = "A generic balloon. How boring."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ghostballoon"
	anchored = FALSE
	density = FALSE

CAPABILITIES(/obj/structure/balloon)
	op("punch", hand(), stance(I_HURT), label("Punch"), then(PROC_REF(interaction_punch)))
	op("poke", hand(), ungated(), stance(I_HELP), label("Poke"), then(PROC_REF(interaction_poke)))
	op("bat", hand(), ungated(), stance(I_DISARM), label("Bat"), then(PROC_REF(interaction_bat)))
	op("pop", hand(), ungated(), stance(I_GRAB), label("Try to pop"), then(PROC_REF(interaction_pop)))

/// Old attack_hand's harm branch: punch the balloon (combat mode only).
/obj/structure/balloon/proc/interaction_punch(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, src, MSG_SELF(span_warning("You punch %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " punches %T%!")))
	return OP_OK

/obj/structure/balloon/proc/interaction_poke(datum/act/op/A)
	return balloon_touched(A.actor, I_HELP)

/obj/structure/balloon/proc/interaction_bat(datum/act/op/A)
	return balloon_touched(A.actor, I_DISARM)

/obj/structure/balloon/proc/interaction_pop(datum/act/op/A)
	return balloon_touched(A.actor, I_GRAB)

/// Old attack_hand: poke it (or, holding Grab, try to pop it; Disarm bats it).
/obj/structure/balloon/proc/balloon_touched(mob/user, stance)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)

	if(stance == I_HELP)
		act_message(user, src, MSG_SELF(span_notice("You poke %T%!")), MSG_OTHERS(span_notice(span_bold("%U%") + " pokes %T%!")))
	else if (stance == I_GRAB)
		act_message(user, src, MSG_SELF(span_warning("You attempt to pop %T%!")), MSG_OTHERS(span_warning(span_bold("%U%") + " attempts to pop %T%!")))
	else
		act_message(user, src, MSG_SELF(span_notice("You lightly bat %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " lightly bats %T%.")))
	return OP_OK

/obj/structure/balloon/bat
	name = "giant bat balloon"
	desc = "A large balloon in the shape of a spooky bat with orange eyes."
	icon_state = "batballoon"

/obj/structure/balloon/ghost
	name = "giant ghost balloon"
	desc = "Oh no, it's a ghost! Oh wait, it's just a balloon. Phew!"
	icon_state = "ghostballoon"

/*
 * Random miniature spawner
 */
/obj/random/miniature
	name = "Random miniature"
	desc = "This is a random miniature."
	icon = 'icons/obj/toy.dmi'
	icon_state = "aliencharacter"

CAPABILITIES(/obj/random/miniature)
	loot(table = list(loot_types(1, typesof(/obj/item/toy/character))))

/// Does `M` have a mind (a player's or an AI's)?
/proc/has_a_mind(mob/M)
	READS_FROM() // a mind is set when a player takes the body; asked when the name is given
	return !!M?.mind

MSG_DEF_SELF(plushie/no_mind, "You can't think of a name.")
