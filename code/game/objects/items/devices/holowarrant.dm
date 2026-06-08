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
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

//look at it
/obj/item/holowarrant/examine(mob/user)
	. = ..()
	if(active)
		. += "It's a holographic warrant for '[active.fields["namewarrant"]]'."
	if(in_range(user, src) || isobserver(user))
		show_content(user) //Opens a browse window, not chatbox related
	else
		. += span_notice("You have to go closer if you want to read it.")

//hit yourself with it
/obj/item/holowarrant/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	active = null
	var/list/warrants = list()
	if(!isnull(GLOB.data_core.general))
		for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
			warrants += W.fields["namewarrant"]
	if(warrants.len == 0)
		to_chat(user,span_notice("There are no warrants available"))
		return
	var/temp
	temp = tgui_input_list(user, "Which warrant would you like to load?", "Warrant Selection", warrants)
	for(var/datum/data/record/warrant/W in GLOB.data_core.warrants)
		if(W.fields["namewarrant"] == temp)
			active = W
	update_icon()

/obj/item/holowarrant/attackby(obj/item/W, mob/user)
	if(active)
		var/obj/item/card/id/I = W.GetIdCard()
		if(ACCESS_HOS in I.GetAccess())
			var/choice = tgui_alert(user, "Would you like to authorize this warrant?","Warrant authorization",list("Yes","No"))
			if(choice == "Yes")
				active.fields["auth"] = "[I.registered_name] - [I.assignment ? I.assignment : "(Unknown)"]"
			user.visible_message(span_notice("You swipe \the [I] through the [src]."), \
					span_notice("[user] swipes \the [I] through the [src]."))
			return 1
		to_chat(user, span_warning("You don't have the access to do this!"))
		return 1
	..()

//hit other people with it
/obj/item/holowarrant/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	user.visible_message(span_notice("You show the warrant to [M]."), \
			span_notice("[user] holds up a warrant projector and shows the contents to [M]."))
	M.examinate(src)
	return ITEM_INTERACT_SUCCESS

/obj/item/holowarrant/update_icon()
	if(active)
		icon_state = "holowarrant_filled"
	else
		icon_state = "holowarrant"

/obj/item/storage/box/holowarrants
	name = "holowarrant devices"
	desc = "A box of holowarrant displays for security use."

/obj/item/storage/box/holowarrants/Initialize(mapload)
	. = ..()
	for(var/i = 0 to 3)
		new /obj/item/holowarrant(src)
