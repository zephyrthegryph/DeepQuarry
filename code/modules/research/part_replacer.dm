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
	drop_sound = 'sound/items/drop/device.ogg'
	pickup_sound = 'sound/items/pickup/device.ogg'
	var/panel_req = TRUE
	var/pshoom_or_beepboopblorpzingshadashwoosh = 'sound/items/rped.ogg'
	var/reskin_ran = FALSE
	var/unique_reskin = list("Soulless" = "RPED",
							"Soulful" = "RPED_old")

/obj/item/storage/part_replacer/hold_constraint()
	var/list/holds = list(/obj/item/stock_parts)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_NORMAL))

/obj/item/storage/part_replacer/proc/play_rped_sound()
	//Plays the sound for RPED exhanging or installing parts.
	playsound(src, pshoom_or_beepboopblorpzingshadashwoosh, 40, 1)

/obj/item/storage/part_replacer/examine(mob/user)
	. = ..()
	if(!reskin_ran)
		. += span_notice("[src]'s external casing can be modified via alt-click.")

/obj/item/storage/part_replacer/click_alt(mob/user)
	. = ..()
	if(!reskin_ran)
		reskin_radial(user)

/obj/item/storage/part_replacer/proc/reskin_radial(mob/M)
	if(!LAZYLEN(unique_reskin))
		return

	var/list/items = list()
	for(var/reskin_option in unique_reskin)
		var/image/item_image = image(icon = src.icon, icon_state = unique_reskin[reskin_option])
		items += list("[reskin_option]" = item_image)
	sortList(items)

	var/pick = show_radial_menu(M, src, items, radius = 38, require_near = TRUE)
	if(!pick)
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
	for(var/obj/item/B in contents)
		if(B.rped_rating() < lowest_rating)
			lowest_rating = B.rped_rating()
	for(var/obj/item/B in contents)
		if(B.rped_rating() > lowest_rating)
			continue
		remove_from_storage(B, T, user)

/obj/item/storage/part_replacer/adv
	name = "advanced rapid part exchange device"
	desc = "A special mechanical module made to store, sort, and apply standard machine parts. This one has a greatly upgraded storage capacity, \
	and the ability to hold beakers."
	storage_slots = 200
	max_storage_space = 400

/obj/item/storage/part_replacer/adv/hold_constraint()
	var/list/holds = list(/obj/item/stock_parts, /obj/item/reagent_containers/glass/beaker)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_NORMAL))

/obj/item/storage/part_replacer/adv/discount_bluespace
	name = "prototype bluespace rapid part exchange device"
	icon_state = "DBRPED"
	item_state = "DBRPED"
	desc = "A special mechanical module made to store, sort, and apply standard machine parts. This one has a further increased storage capacity, \
	and the ability to work on machines with closed maintenance panels."
	storage_slots = 400
	max_storage_space = 800
	panel_req = FALSE
	pshoom_or_beepboopblorpzingshadashwoosh = 'sound/items/pshoom.ogg'
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
	pshoom_or_beepboopblorpzingshadashwoosh = 'sound/items/pshoom.ogg'
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
