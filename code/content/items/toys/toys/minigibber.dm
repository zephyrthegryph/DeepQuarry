/*
 * Toy gibber
 */
/obj/item/toy/minigibber
	name = "miniature gibber"
	desc = "A miniature recreation of NanoTrasen's famous meat grinder. Equipped with a special interlock that prevents insertion of organic material."
	icon = 'icons/obj/toy.dmi'
	icon_state = "gibber"
	COOLDOWN_DECLARE(cooldown)
	var/obj/stored_minature = null // owned: the miniature held by the toy gibber, kept in its contents

CAPABILITIES(/obj/item/toy/minigibber)
	configure(item_combat(attack_verbs = list("grinded", "gibbed")))
	owns_one(nameof(stored_minature), /obj)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("feed", item(/obj/item/toy/figure), item(/obj/item/toy/character), label("Feed"), when(req(PROC_REF(can_feed))), claims(), begins(PROC_REF(feed_begins)), wait(1 SECOND), on_interrupt(PROC_REF(feed_stopped)), then(PROC_REF(interaction_feed)))

/// Old attack_self.
/obj/item/toy/minigibber/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(stored_minature)
		to_chat(user, span_danger("\The [src] makes a violent grinding noise as it tears apart the miniature figure inside!"))
		play_sfx(src, SFX_EFFECTS_SPLAT)
		rel_clear(src, nameof(stored_minature))
		COOLDOWN_START(src, cooldown, 0.8 SECONDS)
	if(COOLDOWN_FINISHED(src, cooldown))
		to_chat(user, span_notice("You hit the gib button on \the [src]."))

		COOLDOWN_START(src, cooldown, 0.8 SECONDS)
	return TRUE

/// A figure goes in, a character only from the feeder's own hands.
/obj/item/toy/minigibber/proc/can_feed(datum/act/op/A)
	var/obj/item/O = A.held
	return (istype(O, /obj/item/toy/figure) || read_once(O.loc == A.actor)) ? null : /datum/msg/req_failed

/obj/item/toy/minigibber/proc/feed_begins(datum/act/op/A)
	return msg_text(span_notice("You start feeding \the [A.held] [icon2html(A.held, A.actor.client)] into \the [src]'s mini-input."))

/// Old attackby: feed a figure into the gibber.
/obj/item/toy/minigibber/proc/interaction_feed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/O = A.held
	if(O.loc != user)
		to_chat(user, span_warning("\The [O] is too far away to feed into \the [src]!"))
	else
		act_message(user, src, MSG_SELF(span_notice("You feed \the [O] into %T%!")), MSG_OTHERS(span_notice("%U% feeds \the [O] into %T%!")))
		move_into(src, nameof(src.stored_minature), O, user)
	return OP_OK

/obj/item/toy/minigibber/proc/feed_stopped(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF(span_notice("You stop feeding \the [A.held] into %T%.")), MSG_OTHERS(span_notice("%U% stops feeding \the [A.held] into %T%!")))
