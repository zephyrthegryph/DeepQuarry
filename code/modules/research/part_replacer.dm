/obj/item/storage/part_replacer
	name = "rapid part exchange device"
	desc = "A special mechanical module made to store, sort, and apply standard machine parts."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "RPED"
	item_state = "RPED"
	w_class = ITEMSIZE_HUGE
	storage_slots = 50
	use_to_pickup = TRUE
	allow_quick_gather = 1
	allow_quick_empty = 1
	collection_mode = 1
	display_contents_with_number = 1
	max_storage_space = 100
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	var/panel_req = TRUE
	var/pshoom_or_beepboopblorpzingshadashwoosh = SFX_ITEMS_RPED
	var/reskin_ran = FALSE
	var/unique_reskin = list("Soulless" = "RPED",
							"Soulful" = "RPED_old")


CAPABILITIES(/obj/item/storage/part_replacer)
	configure(storage(accepts = list(/obj/item/stock_parts), max_size = ITEMSIZE_NORMAL))
	op("reskin", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Reskin"), then(PROC_REF(interaction_reskin_alt)))

/obj/item/storage/part_replacer/proc/play_rped_sound()
	//Plays the sound for RPED exhanging or installing parts.
	playsound(src, pshoom_or_beepboopblorpzingshadashwoosh, 40, 1)

/obj/item/storage/part_replacer/examine(mob/user)
	. = ..()
	if(!reskin_ran)
		. += span_notice("[src]'s external casing can be modified via alt-click.")

/// Old click_alt: the storage's own alt-click, then the one-time reskin menu.
/obj/item/storage/part_replacer/proc/interaction_reskin_alt(datum/act/op/A)
	var/mob/user = A.actor
	. = toggle_window(user) ? OP_OK : OP_DECLINE
	if(!reskin_ran)
		reskin_radial(user)
		return OP_OK

/obj/item/storage/part_replacer/proc/reskin_radial(mob/M)
	if(!LAZYLEN(unique_reskin))
		return

	var/list/items = list()
	for(var/reskin_option in unique_reskin)
		var/image/item_image = image(icon = src.icon, icon_state = unique_reskin[reskin_option])
		items += list("[reskin_option]" = item_image)
	sortList(items)

	open_request(src, /datum/prompt/choice, PROC_REF(reskin_chosen), answerer = M, choices = items, anchor = src, radius = 38, require_near = TRUE, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/obj/item/storage/part_replacer/proc/reskin_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/M = A.request.answerer
	var/pick = A.answer.value
	if(!pick || reskin_ran)
		return
	if(!unique_reskin[pick])
		return
	icon_state = unique_reskin[pick]
	item_state = unique_reskin[pick]
	reskin_ran = TRUE
	to_chat(M, "[src] is now '[pick]'.")

/obj/item/storage/part_replacer/drop_contents(mob/user) // hacky-feeling tier-based drop system
	if(user)
		hide_from(user)
	var/turf/T = get_turf(src)
	var/lowest_rating = INFINITY // We want the lowest-part tier rating in the RPED so we only drop the lowest-tier parts.
	/*
	* Why not just use the stock part's rating variable?
	* Future-proofing for a potential future where stock parts aren't the only thing that can fit in an RPED.
	* see: /tg/ and /vg/'s RPEDs fitting power cells, beakers, etc.
	* 10/8/21 edit - It's Time.
	*/
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/B in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(B.rped_rating() < lowest_rating)
			lowest_rating = B.rped_rating()
	for(var/obj/item/B in contents) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(B.rped_rating() > lowest_rating)
			continue
		remove_from_storage(B, T, user)

/obj/item/storage/part_replacer/adv
	name = "advanced rapid part exchange device"
	desc = "A special mechanical module made to store, sort, and apply standard machine parts. This one has a greatly upgraded storage capacity, \
	and the ability to hold beakers."
	storage_slots = 200
	max_storage_space = 400


CAPABILITIES(/obj/item/storage/part_replacer/adv)
	configure(storage(accepts = list(
		/obj/item/stock_parts,
		/obj/item/reagent_containers/glass/beaker)))

/obj/item/storage/part_replacer/adv/discount_bluespace
	name = "prototype bluespace rapid part exchange device"
	icon_state = "DBRPED"
	item_state = "DBRPED"
	desc = "A special mechanical module made to store, sort, and apply standard machine parts. This one has a further increased storage capacity, \
	and the ability to work on machines with closed maintenance panels."
	storage_slots = 400
	max_storage_space = 800
	panel_req = FALSE
	pshoom_or_beepboopblorpzingshadashwoosh = SFX_ITEMS_PSHOOM
	unique_reskin = list("Soulless" = "DBRPED",
						"Soulful" = "DBRPED_old")

/obj/item/storage/part_replacer/adv/bluespace
	name = "bluespace rapid part exchange device"
	icon_state = "DBRPED"
	item_state = "DBRPED"
	desc = "A special mechanical module made to store, sort, and apply standard machine parts. This one has a further increased storage capacity, \
	and the ability to work on machines at a distance."
	storage_slots = 400
	max_storage_space = 800
	panel_req = FALSE
	pshoom_or_beepboopblorpzingshadashwoosh = SFX_ITEMS_PSHOOM
	unique_reskin = list("Soulless" = "DBRPED",
						"Soulful" = "DBRPED_old")

/obj/item/storage/part_replacer/adv/bluespace/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(!(target in view(user)))
		return ..()

	if(istype(target, /obj/structure/frame))
		var/obj/structure/frame/F = target
		if(F.mass_install_parts(user,src))
			play_rped_sound()
			user.Beam(F, icon_state = "rped_upgrade", time = 0.5 SECONDS)
		return

	if(!istype(target, /obj/machinery))
		return

	var/obj/machinery/M = target
	if(M.default_part_replacement(user, src))
		play_rped_sound()
		user.Beam(M, icon_state = "rped_upgrade", time = 0.5 SECONDS)
