/*
 * Toy nuke
 */

/obj/item/toy/nuke
	name = "\improper Nuclear Fission Explosive toy"
	desc = "A plastic model of a Nuclear Fission Explosive."
	icon = 'icons/obj/toy.dmi'
	icon_state = "nuketoyidle"
	var/cooldown = 0

CAPABILITIES(/obj/item/toy/nuke)
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_self.
/obj/item/toy/nuke/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 180 SECONDS) //3 minutes
		act_message(user, src, MSG_SELF(span_notice("You activate %T%, it plays a loud noise!")), MSG_OTHERS(span_warning("%U% presses a button on %T%")), MSG_BLIND(span_notice("You hear the click of a button.")))
		after(src, 0.5 SECONDS, PROC_REF(alarm_sequence)) //gia said so
	else
		var/timeleft = (cooldown - world.time)
		to_chat(user, span_warning("Nothing happens, and") + " '[round(timeleft/10)]' " + span_warning("appears on a small display."))
	return TRUE

/// Old attackby.
/obj/item/toy/nuke/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/disk/nuclear))
		to_chat(user, span_warning("Nice try. Put that disk back where it belongs."))
	return OP_PASS

/obj/item/toy/nuke/proc/alarm_sequence()
	set_icon_state("nuketoy")
	play_sfx(src, SFX_MACHINES_ALARM)
	after(src, 13.5 SECONDS, TYPE_PROC_REF(/atom, set_icon_state), with = list("nuketoycool"))
	after(src, 13.5 SECONDS + (cooldown - world.time), TYPE_PROC_REF(/atom, set_icon_state), with = list("nuketoyidle"))
