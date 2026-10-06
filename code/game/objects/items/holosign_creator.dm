/obj/item/holosign_creator
	name = "holographic sign projector"
	desc = "A handy-dandy holographic projector that displays a janitorial sign."
	icon = 'icons/obj/device.dmi'
	icon_state = "signmaker"
	item_state = "electronic"
	force = 0
	w_class = ITEMSIZE_SMALL
	throwforce = 0
	throw_speed = 3
	throw_range = 7
	var/list/signs
	var/max_signs = 10
	var/creation_time = 0 //time to create a holosign in deciseconds.
	var/holosign_type = /obj/structure/holosign/wetsign

/obj/item/holosign_creator/proc/create_sign(mob/user, turf/T, waited = TRUE)
	if(waited)
		if(length(signs) >= max_signs)
			return
		if(is_blocked_turf(T, TRUE)) //don't try to sneak dense stuff on our tile during the wait.
			return
	var/obj/structure/holosign/H = new holosign_type(T, src)
	to_chat(user, span_notice("You create \a [H] with [src]."))

/obj/item/holosign_creator/afterattack(atom/target, mob/user, clickchain_flags, list/params)
	. = ..()
	if(!check_allowed_items(target, 1))
		return
	var/turf/T = get_turf(target)
	var/obj/structure/holosign/H = locate_on(T, holosign_type)
	if(H)
		to_chat(user, span_notice("You use [src] to deactivate [H]."))
		consume(H, user)
	else
		if(task_busy(src)) // a sign being projected claims the creator
			to_chat(user, span_notice("[src] is busy creating a hologram."))
			return
		if(length(signs) < max_signs)
			play_sfx(src.loc, SFX_MACHINES_CLICK, 0.4)
			if(creation_time)
				task_timed(user, creation_time, target = target, receiver = src, on_done = PROC_REF(create_sign), done_args = list(user, T), busy = src)
				return
			create_sign(user, T, FALSE)
		else
			to_chat(user, span_notice("[src] is projecting at max capacity!"))

CAPABILITIES(/obj/item/holosign_creator)
	op("clear_holograms", in_hand(), then(PROC_REF(clear_holograms)))

/// Clear only this projector's current signs through their existing checked consumption path.
/obj/item/holosign_creator/proc/clear_holograms(datum/act/op/A)
	var/mob/user = A.actor
	if(length(signs))
		for(var/obj/structure/holosign/H as anything in signs.Copy())
			consume(H, user)
		to_chat(user, span_notice("You clear all active holograms."))
	return OP_OK

/obj/item/holosign_creator/combifan
	name = "ATMOS holo-combifan projector"
	desc = "A holographic projector that creates holographic combi-fans that prevent changes in atmosphere and temperature conditions. Somehow."
	icon_state = "signmaker_engi"
	holosign_type = /obj/structure/holosign/barrier/combifan
	creation_time = 0
	max_signs = 3

/obj/item/holosign_creator/medical
	name = "Vey-Med barrier projector"
	desc = "A holographic projector that creates Vey-Medical holobarriers. Useful during quarantines since they halt those with malicious diseases."
	icon = 'icons/obj/device.dmi'
	icon_state = "signmaker_med"
	holosign_type = /obj/structure/holosign/barrier/medical
	creation_time = 0
	max_signs = 6
