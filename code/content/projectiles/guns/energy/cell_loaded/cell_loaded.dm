// The Gun //
/obj/item/gun/projectile/cell_loaded //this one can load both medical and security cells! for ERT/admin use.
	name = "multipurpose cell-loaded revolver"
	desc = "Variety is the spice of life! This weapon is a hybrid of the HI-102b 'Nanotech Selectable-Cell Weapon' and the Vey-Med NERD 'Medigun'. \
	It can fire both harmful and healing cells with an internal nanite fabricator and energy weapon cell loader. Up to three combinations of \
	energy beams can be configured at once. Ammo not included."

	icon = 'icons/vore/custom_guns_vr.dmi'
	icon_state = "nsfw"

	icon_override = 'icons/vore/custom_guns_vr.dmi'
	item_state = "gun"

	caliber = "nsfw"

	fire_sound = SFX_WEAPONS_TASER

	load_method = MAGAZINE //Nyeh heh hehhh.
	magazine_type = null
	allowed_magazines = list(/obj/item/ammo_magazine/cell_mag)
	handle_casings = HOLD_CASINGS //Don't eject batteries!
	recoil = 0
	charge_sections = 5

	special_handling = TRUE
	special_weapon_handling = TRUE

CAPABILITIES(/obj/item/gun/projectile/cell_loaded)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/information/organization/hephaestus, /datum/category_item/catalogue/information/organization/vey_med)))

/obj/item/gun/projectile/cell_loaded/consume_next_projectile()
	if(chambered && ammo_magazine)
		var/obj/item/ammo_casing/microbattery/batt = chambered
		if(batt.shots_left)
			return new chambered.projectile_type()
		else
			for(var/obj/item/ammo_casing/microbattery/other_batt as anything in ammo_magazine.stored_ammo)
				if(istype(other_batt,chambered.type) && other_batt.shots_left)
					switch_to(other_batt)
					return new chambered.projectile_type()

	return null

/// The charge of the chambered kind of microbattery across the magazine, as a fraction of what those batteries hold full (0 with nothing chambered).
/obj/item/gun/projectile/cell_loaded/proc/charge_fraction()
	if(!chambered || !ammo_magazine)
		return 0
	var/obj/item/ammo_casing/microbattery/batt = chambered
	var/charge_left = 0
	var/max_charge = 0
	for(var/obj/item/ammo_casing/microbattery/bullet as anything in ammo_magazine.stored_ammo)
		if(istype(bullet,batt.type))
			charge_left += bullet.shots_left
			max_charge += initial(bullet.shots_left)
	return max_charge ? charge_left / max_charge : 0

/obj/item/gun/projectile/cell_loaded/proc/switch_to(obj/item/ammo_casing/microbattery/new_batt)
	if(ishuman(loc))
		if(chambered && new_batt.type == chambered.type)
			to_chat(loc,span_warning("\The [src] is now using the next [new_batt.type_name] power cell."))
		else
			to_chat(loc,span_warning("\The [src] is now firing [new_batt.type_name]."))

	rel_set(src, nameof(chambered), new_batt)
	var/mob/living/M = loc // TGMC Ammo HUD
	if(istype(M)) // TGMC Ammo HUD
		M?.hud_used?.update_ammo_hud(M, src)

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/projectile/cell_loaded/gun_operate(datum/act/op/A, callback)
	. = ..()
	if(. == OP_OK)
		return OP_OK
	if(!chambered)
		return

	var/list/stored_ammo = ammo_magazine.stored_ammo

	if(length(stored_ammo) == 1)
		return //silly you.

	//Find an ammotype that ISN'T the same, or exhaust the list and don't change.
	var/our_slot = stored_ammo.Find(chambered)

	for(var/index in 1 to length(stored_ammo))
		var/true_index = ((our_slot + index - 1) % length(stored_ammo)) + 1 // Stupid ONE BASED lists!
		var/obj/item/ammo_casing/microbattery/next_batt = stored_ammo[true_index]
		if(chambered != next_batt && !istype(next_batt, chambered.type))
			switch_to(next_batt)
			break
/obj/item/gun/projectile/cell_loaded/load_ammo(obj/item/A, mob/user)
	. = ..()
	if(ammo_magazine && length(ammo_magazine.stored_ammo))
		switch_to(ammo_magazine.stored_ammo[1])

/obj/item/gun/projectile/cell_loaded/unload_ammo(mob/user, allow_dump=1)
	rel_clear(src, nameof(chambered))
	return ..()

/// The look: the chambered battery's mode bar, barrel tint and charge bar, all in its colour.
/obj/item/gun/projectile/cell_loaded/draw(datum/look/look)
	..()
	if(!chambered)
		return
	var/obj/item/ammo_casing/microbattery/batt = chambered
	var/batt_color = batt.type_color //Used many times
	look.overlay(look_overlay_image(icon, "[initial(icon_state)]_type", color = batt_color))
	look.overlay(look_overlay_image(icon, "[initial(icon_state)]_barrel", alpha = 150, color = batt_color))
	var/ratio = CEILING(charge_fraction() * charge_sections, 1)
	for(var/i = 0, i < ratio, i++)
		look.overlay(look_overlay_image(icon, "[initial(icon_state)]_charge", pixel_x = i, color = batt_color))

// TGMC Ammo HUD: Custom handling for cell-loaded weaponry.
/obj/item/gun/projectile/cell_loaded/get_ammo_count()
	if(!chambered)
		return 0 // We're not chambered, so we have 0 rounds loaded.

	var/obj/item/ammo_casing/microbattery/batt = chambered

	var/shots
	if(ammo_magazine) // Check how much ammo we have
		for(var/obj/item/ammo_casing/microbattery/bullet as anything in ammo_magazine.stored_ammo)
			if(istype(bullet,batt.type))
				shots += bullet.shots_left
		if(shots > 0) // We have shots ready to fire.
			return shots
		else // We're out of shots.
			return 0
	else // Else, we're unloaded/don't have a magazine.
		return 0
