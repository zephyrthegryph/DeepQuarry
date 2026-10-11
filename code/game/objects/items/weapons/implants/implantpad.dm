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


CAPABILITIES(/obj/item/implantpad)
	interface("ImplantPad", title = "Implant Mini-Computer", input = in_hand())
	op("take_case", hand(), when(cond_all(PROC_REF(has_case), carried())), then(PROC_REF(case_taken)))
	op("insert_case", item(/obj/item/implantcase), passes(), when(req(PROC_REF(has_no_case))), then(PROC_REF(case_inserted)))
	op("tracking_id", ui_act("tracking_id", arg("delta", num())), then(PROC_REF(ui_act_tracking_id)))
	extend(TAG_UI, needs(req(PROC_REF(user_conscious), because = MSG(implantpad/unconscious))))

/// An empty hand takes the case out of a pad it carries; a pad that is not carried, or holds none, is picked up as any item.
/obj/item/implantpad/proc/has_case(datum/act/A)
	return !!case

/obj/item/implantpad/proc/case_taken(datum/act/op/A)
	var/mob/living/user = A.actor
	user.put_in_active_hand(case)

	src.case.add_fingerprint(user)
	rel_take(src, nameof(case))

	src.add_fingerprint(user)
	update()
	return OP_OK

/// The pad takes one case.
/obj/item/implantpad/proc/has_no_case(datum/act/op/A)
	return (!case) ? null : /datum/msg/req_failed

/obj/item/implantpad/proc/case_inserted(datum/act/op/A)
	move_into(src, nameof(src.case), A.held, A.actor)
	src.update()
	return OP_OK

MSG_DEF_SELF(implantpad/unconscious, "You can't do that right now.")

/// The window only answers someone who is conscious.
/obj/item/implantpad/proc/user_conscious(datum/act/op/A)
	var/mob/user = A.actor
	return (!user.stat) ? null : MSG(implantpad/unconscious)

/obj/item/implantpad/ui_data(datum/act/eval/A)
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

/obj/item/implantpad/proc/ui_act_tracking_id(datum/act/op/A, delta)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!istype(case?.imp, /obj/item/implant/tracking))
		return OP_OK
	var/obj/item/implant/tracking/T = case.imp
	T.id += delta
	T.id = clamp(T.id, 1, 1000)
	return OP_OK

/obj/item/implantpad/ownership()
	. = ..()
	. += owns(nameof(case), policy = OWN_CONTAINED)
