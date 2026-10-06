/obj/item/holowarrant
	name = "warrant projector"
	desc = "The practical paperwork replacement for the officer on the go."
	icon = 'icons/obj/device.dmi'
	icon_state = "holowarrant"
	item_state = "flashtool"
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 4
	throw_range = 10
	var/datum/data/record/warrant/active
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

//look at it
/obj/item/holowarrant/examine(mob/user)
	. = ..()
	if(active())
		. += "It's a holographic warrant for '[active().fields["namewarrant"]]'."
	if(in_range(user, src) || isobserver(user))
		show_content(user) //Opens a browse window, not chatbox related
	else
		. += span_notice("You have to go closer if you want to read it.")

/// The names on the warrants on file.
/obj/item/holowarrant/proc/warrant_names(datum/act/A)
	return warrants_on_file()

/proc/warrants_on_file()
	READS_FROM() // the records are read when the projector asks
	. = list()
	if(!isnull(GLOB.data_core.general))
		for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
			. += W.fields["namewarrant"]

/obj/item/holowarrant/proc/warrants_exist(datum/act/op/A)
	return length(warrants_on_file()) > 0

/// The held thing carries the Head of Security's access: the authorization is asked.
/obj/item/holowarrant/proc/authorizing_card(datum/act/op/A)
	return carries_access(A.held, ACCESS_HOS)

/// Does `thing` carry an ID with `access`?
/proc/carries_access(obj/item/thing, access)
	READS_FROM() // an ID's access is asked when it is swiped
	var/obj/item/card/id/I = thing?.GetIdCard()
	return I && (access in I.GetAccess())

/// The warrant picked is loaded (none on file: say so).
/obj/item/holowarrant/proc/warrant_chosen(datum/act/op/A)
	rel_clear(src, nameof(active))
	var/datum/prompt/R = A.answer
	if(!R)
		if(!length(warrants_on_file()))
			to_chat(A.actor, span_notice("There are no warrants available"))
		update_icon()
		return OP_OK
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		if(W.fields["namewarrant"] == R.value)
			rel_set(src, nameof(active), W)
	update_icon()
	return OP_OK

/// An ID swiped through it: authorized after a yes; without the access it says so; anything else goes on.
/obj/item/holowarrant/proc/authorize_answered(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = A.held?.GetIdCard()
	if(!I)
		return OP_DECLINE
	if(!carries_access(A.held, ACCESS_HOS))
		to_chat(user, span_warning("You don't have the access to do this!"))
		return OP_OK
	var/datum/prompt/R = A.answer
	if(R?.value && active())
		active().fields["auth"] = "[I.registered_name] - [I.assignment ? I.assignment : "(Unknown)"]"
	act_message(user, src, MSG_SELF(span_notice("You swipe \the [I] through %T%.")), \
		MSG_OTHERS(span_notice("%U% swipes \the [I] through %T%.")))
	return OP_OK

//hit other people with it
/obj/item/holowarrant/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	act_message(user, M, MSG_SELF(span_notice("You show the warrant to %T%.")), \
		MSG_OTHERS(span_notice("%U% holds up a warrant projector and shows the contents to %T%.")))
	M.examinate(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/holowarrant/proc/appearance_active()
	return active() ? TRUE : FALSE

APPEARANCE_TEMPLATE(/obj/item/holowarrant, "{appearance_active?holowarrant_filled:holowarrant}")

// show_content moved to code/modules/holowarrant_panel.dm (structured TGUI).

/obj/item/storage/box/holowarrants // addition starts
	name = "holowarrant devices"
	desc = "A box of holowarrant displays for security use."

/obj/item/storage/box/holowarrants/Initialize(mapload)
	. = ..()
	for(var/i = 0 to 3)
		new /obj/item/holowarrant(src) // addition ends

/// Relation view: active (reads null once it is gone).
/obj/item/holowarrant/proc/active() as /datum/data/record/warrant
	return active
