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
	var/active_handle
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

//look at it
/obj/item/holowarrant/examine(mob/user)
	. = ..()
	if(active())
		. += "It's a holographic warrant for '[active().fields["namewarrant"]]'."
	if(in_range(user, src) || isobserver(user))
		show_content(user) //Opens a browse window, not chatbox related
	else
		. += span_notice("You have to go closer if you want to read it.")

//hit yourself with it
/obj/item/holowarrant/get_interactions()
	var/static/list/L = list(
		INTERACT_USE(null, PROC_REF(interaction_self)),
		INTERACT_ITEM(null, PROC_REF(interaction_item)),
	)
	return L

/obj/item/holowarrant/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	active_handle = null
	var/list/warrants = list()
	if(!isnull(GLOB.data_core.general))
		for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
			warrants += W.fields["namewarrant"]
	if(warrants.len == 0)
		to_chat(user,span_notice("There are no warrants available"))
		return
	om_prompt(src, user, list("kind" = "list", "message" = "Which warrant would you like to load?", "title" = "Warrant Selection", "choices" = warrants, "requires" = PROMPT_HELD), PROC_REF(warrant_chosen))

/obj/item/holowarrant/proc/warrant_chosen(mob/user, temp, datum/om/prompt/ask)
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		if(W.fields["namewarrant"] == temp)
			active_handle = om_handle(W)
	update_icon()

/obj/item/holowarrant/proc/authorize_answered(mob/user, choice, datum/om/prompt/ask)
	var/obj/item/card/id/I = ask.get("card")
	if(choice == "Yes" && active() == ask.get("warrant"))
		active().fields["auth"] = "[I.registered_name] - [I.assignment ? I.assignment : "(Unknown)"]"
	user.visible_message(span_notice("You swipe \the [I] through the [src]."), \
			span_notice("[user] swipes \the [I] through the [src]."))

/obj/item/holowarrant/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(active())
		var/obj/item/card/id/I = W.GetIdCard()
		if(I && (ACCESS_HOS in I.GetAccess()))
			om_prompt(src, user, list("message" = "Would you like to authorize this warrant?", "title" = "Warrant authorization", "choices" = list("Yes","No"), "target" = W, "requires" = PROMPT_IN_HAND, "data" = list("card" = I, "warrant" = active())), PROC_REF(authorize_answered))
			return TRUE
		to_chat(user, span_warning("You don't have the access to do this!"))
		return TRUE
	return FALSE

//hit other people with it
/obj/item/holowarrant/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	user.visible_message(span_notice("You show the warrant to [M]."), \
			span_notice("[user] holds up a warrant projector and shows the contents to [M]."))
	M.examinate(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/holowarrant/update_icon()
	if(active())
		icon_state = "holowarrant_filled"
	else
		icon_state = "holowarrant"

// show_content moved to code/modules/holowarrant_panel.dm (structured TGUI).

/obj/item/storage/box/holowarrants // addition starts
	name = "holowarrant devices"
	desc = "A box of holowarrant displays for security use."

/obj/item/storage/box/holowarrants/Initialize(mapload)
	. = ..()
	for(var/i = 0 to 3)
		new /obj/item/holowarrant(src) // addition ends

/// LC-refs: active -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/holowarrant/proc/active() as /datum/data/record/warrant
	return om_resolve(active_handle)
