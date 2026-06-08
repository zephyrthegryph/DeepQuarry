//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/obj/item/implantpad
	name = "implantpad"
	desc = "Used to modify implants."
	icon = 'icons/obj/items.dmi'
	icon_state = "implantpad-0"
	item_state = "electronic"
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	var/obj/item/implantcase/case = null
	var/broadcasting = null
	var/listening = 1.0
/obj/item/implantpad/proc/update()
	if (src.case)
		src.icon_state = "implantpad-1"
	else
		src.icon_state = "implantpad-0"
	return


/obj/item/implantpad/attack_hand(mob/living/user as mob)
	if ((src.case && user.item_is_in_hands(src)))
		user.put_in_active_hand(case)

		src.case.add_fingerprint(user)
		src.case = null

		src.add_fingerprint(user)
		update()
	else
		return ..()
	return


/obj/item/implantpad/attackby(obj/item/implantcase/C as obj, mob/user as mob)
	..()
	if(istype(C, /obj/item/implantcase))
		if(!( src.case ))
			user.drop_item()
			C.loc = src
			src.case = C
	else
		return
	src.update()
	return


/obj/item/implantpad/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	tgui_interact(user)

/obj/item/implantpad/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ImplantPad", "Implant Mini-Computer")
		ui.open()

/obj/item/implantpad/tgui_data(mob/user)
	var/list/data = list()
	data["has_case"] = !!case
	data["has_implant"] = !!(case?.imp)
	data["implant_info"] = ""
	data["is_tracking"] = FALSE
	data["tracking_id"] = 0
	if(case?.imp && istype(case.imp, /obj/item/implant))
		data["implant_info"] = case.imp.get_data()
		if(istype(case.imp, /obj/item/implant/tracking))
			var/obj/item/implant/tracking/T = case.imp
			data["is_tracking"] = TRUE
			data["tracking_id"] = T.id
	return data

/obj/item/implantpad/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = ui.user
	if(user.stat)
		return TRUE
	add_fingerprint(user)
	switch(action)
		if("tracking_id")
			if(!istype(case?.imp, /obj/item/implant/tracking))
				return TRUE
			var/obj/item/implant/tracking/T = case.imp
			T.id += text2num(params["delta"])
			T.id = clamp(T.id, 1, 1000)
			return TRUE
