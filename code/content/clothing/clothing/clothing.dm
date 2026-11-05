/obj/item/clothing
	name = DEVELOPER_WARNING_NAME // "Clothing"
	resistance_flags = FLAMMABLE

	var/list/accessories
	var/list/valid_accessory_slots
	var/list/restricted_accessory_slots
	var/list/starting_accessories

	/// Trait modification, lazylist of traits to add/take away, on equipment/drop in the correct slot
	var/list/clothing_traits

	var/flash_protection = FLASH_PROTECTION_NONE
	var/tint = TINT_NONE
	var/list/enables_planes		//Enables these planes in the wearing mob's plane_holder
	var/list/plane_slots		//But only if it's equipped into this specific slot

	var/ear_protection = 0
	var/blood_sprite_state

	var/update_icon_define = null	// Only needed if you've got multiple files for the same type of clothing

	/// The carrier may recolour its colour channels (the Recolour verb). Only types with channels (clothing_channels.dm) can be.
	var/recolourable = FALSE

	var/update_icon_define_orig = null	// temp storage for original update_icon_define (if it exists)
	var/update_icon_define_digi = null	// dmi used for the digi sprites
	var/fit_for_digi = FALSE // flag for if clothing has already been reskinned to digitigrade
	var/mob/wearer	//Who the person currently wearing us is.

/// Attaches the accessories the type starts wearing (starting_accessories).
/obj/item/clothing/proc/attach_starting_accessories()
	if(starting_accessories)
		for(var/T in starting_accessories)
			var/obj/item/clothing/accessory/tie = new T(src)
			src.attach_accessory(null, tie)

/// Clothing's own blood and gurgle layers come from the item's look (/obj/item/draw()).
/obj/item/clothing/draw(datum/look/look)
	..()
	// Attached accessories show their inventory sprite on the garment.
	for(var/obj/item/clothing/accessory/attached in accessories)
		look.watch(attached)
		look.overlay(attached.get_inv_overlay())

DECLARE_SHARED_CACHE_EX(item_stain_images, GLOBAL_PROC_REF(build_item_stain_image), SC_NEVER, 2048, 0)

/obj/item/clothing/equipped(mob/user,slot)
	..()
	if(enables_planes)
		user.recalculate_vis()
	if(dq_item_fits_slot_flags(src, slot))
		for(var/trait in clothing_traits)
			ADD_CLOTHING_TRAIT(user, trait)

// Set while this clothing is deployed as part of a hardsuit. Lets the piece free
// itself if the control module is removed, destroyed, or its owner dies, so a
// deployed component is never left locked onto the wearer. See rig_self_detach().
/obj/item/clothing
	var/obj/item/rig/master_rig

// The self-detach primitive. Gets a deployed rig piece off its wearer and somewhere
// safe: retracted back into the control module if it still exists, otherwise dropped
// to the floor as a normal item. After this runs the piece is never "stuck".
/obj/item/clothing/proc/rig_self_detach()
	var/obj/item/rig/owner_rig = master_rig()
	rel_clear(src, nameof(master_rig))
	set_canremove(TRUE)
	if(ismob(loc))
		var/mob/M = loc
		M.drop_from_inventory(src)
	if(owner_rig && !QDELETED(owner_rig))
		forceMove(owner_rig)   // retracted into the module (which may now be on the floor)
		set_canremove(FALSE)
	else
		forceMove(get_turf(src))   // module is gone; settle on the floor

/obj/item/clothing/dropped(mob/user, equipping, slot)
	..()
	if(enables_planes)
		user.recalculate_vis()
	for(var/trait in clothing_traits)
		REMOVE_CLOTHING_TRAIT(user, trait)
	// Safety net: a deployed hardsuit piece pulled off by something other than its own
	// control module (dismemberment, stripping, gibbing) frees itself instead of
	// staying locked. The module's own retract clears master_rig first, so this no-ops
	// for the normal path.
	if(master_rig())
		rig_self_detach()

/// Old click_alt: take off an attached accessory. Falls through to the default alt-click, as before.
/obj/item/clothing/proc/clothing_remove_accessory_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user) || user == src.loc)
		removetie_proc(user)
	return OP_DECLINE

/obj/item/clothing/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	. = ..()
	if((. == 0) && LAZYLEN(accessories))
		for(var/obj/item/I in accessories)
			var/check = I.handle_shield(user, damage, damage_source, attacker, def_zone, attack_text)

			if(check != 0)	// Projectiles sometimes use negatives IIRC, 0 is only returned if something is not blocked.
				. = check
				break

// For now, these two temp procs only return TRUE or FALSE if they can provide resistance to a given temperature.
/obj/item/clothing/proc/handle_low_temperature(tempcheck = T20C)
	. = FALSE
	if(LAZYLEN(accessories))
		for(var/obj/item/clothing/C in accessories)
			if(C.handle_low_temperature(tempcheck))
				. = TRUE

	if(protection_of(src).min_cold && protection_of(src).min_cold <= tempcheck)
		. = TRUE

/obj/item/clothing/proc/handle_high_temperature(tempcheck = T20C)
	. = FALSE
	if(LAZYLEN(accessories))
		for(var/obj/item/clothing/C in accessories)
			if(C.handle_high_temperature(tempcheck))
				. = TRUE

	if(protection_of(src).max_heat && protection_of(src).max_heat >= tempcheck)
		. = TRUE

// Returns the relative flag-vars for covered protection.
/obj/item/clothing/proc/get_cold_protection_flags()
	. = protection_of(src).cold_parts

	if(LAZYLEN(accessories))
		for(var/obj/item/clothing/C in accessories)
			. |= C.get_cold_protection_flags()

/obj/item/clothing/proc/get_heat_protection_flags()
	. = protection_of(src).heat_parts

	if(LAZYLEN(accessories))
		for(var/obj/item/clothing/C in accessories)
			. |= C.get_heat_protection_flags()

/obj/item/clothing/proc/refit_for_species(target_species)
	if(!dq_constraint_present(src, CONSTRAINT_FIT))
		return //this item doesn't restrict who it fits

	switch(target_species)
		if(SPECIES_HUMAN, SPECIES_SKRELL)	//humanoid bodytypes
			restrict_fit_category(FIT_REFIT_HUMANOID)
		if(SPECIES_UNATHI)
			restrict_fit_category(FIT_REFIT_UNATHI)
		if(SPECIES_TAJARAN)
			restrict_fit_category(FIT_REFIT_TAJARAN)
		if(SPECIES_VULPKANIN)
			restrict_fit_category(FIT_REFIT_VULPKANIN)
		if(SPECIES_SERGAL)
			restrict_fit_category(FIT_REFIT_SERGAL)
		if("Metamorphic")
			if(sprite_sheets[SPECIES_TESHARI]) //We have a custom teshari species sprite. Sorry teshari, but otherwise the fallback looks awful on you.
				restrict_fit_category(FIT_REFIT_ALL)
			else
				restrict_fit_category(FIT_REFIT_ALL_BUT_TESHARI)
		else
			restrict_fit(list(target_species))

	//Set icon
	if (item_rules_of(src).sprite_sheets_obj && (target_species in item_rules_of(src).sprite_sheets_obj))
		set_icon(item_rules_of(src).sprite_sheets_obj[target_species])
	else
		set_icon(initial(icon))

/obj/item/clothing/proc/recolour_channels()
	set name = "Recolour"
	set category = VERB_CAT_OBJECT
	set desc = "Change the colours of the clothing."
	set src in usr

	perform_op(usr, src, "recolour_channels", null, ORIGIN_VERB)

/// The channels the Recolour op offers, by name.
/obj/item/clothing/proc/recolour_channel_names(datum/act/op/A)
	var/static/list/names = list("Primary", "Secondary", "Tertiary")
	return names.Copy(1, length(clothing_channel_bases(channel_type())) + 1)

/// What the item's channels are now: the chosen colours, "" where a channel is as drawn.
/obj/item/clothing/proc/current_channel_colours()
	var/list/bases = clothing_channel_bases(channel_type())
	var/key = STATE_PEEK(src, item_misc, clothing_channel_colors)
	var/list/current = key ? splittext(key, "|") : list()
	while(length(current) < length(bases))
		current += ""
	return current

/// The picked colour goes on the picked channel; the channel's own base colour puts it back as drawn.
/obj/item/clothing/proc/recoloured_channel(datum/act/op/A)
	var/index = recolour_channel_names(A).Find(A.step_value("channel"))
	var/picked = clothing_channel_normal_hex(istext(A.step_value("colour")) ? lowertext(A.step_value("colour")) : null)
	if(!index || !picked)
		return OP_DECLINE
	var/list/colours = current_channel_colours()
	colours[index] = picked == clothing_channel_bases(channel_type())[index] ? "" : picked
	apply_clothing_channels(colours)
	return OP_OK

// Attached accessories are part of the garment: deleted with it, not spilled
// (dq_lifecycle_spill_declared skips owned children held in contents).

/obj/item/clothing/proc/handle_digitigrade(mob/user)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user

		// if digitigrade-use flag is set
		if(H.looks.digitigrade)

			// Don't reset if already set
			if(!fit_for_digi)
				fit_for_digi = TRUE // set flag even if no icon_state exists, so we don't repeat checks

				//if update_icon_define is already set to something, place it in a var to hold it temporarily
				if(update_icon_define)
					update_icon_define_orig = update_icon_define

				// only override icon if a corresponding digitigrade replacement icon_state exists
				// otherwise, keep the old non-digi icon_define (or nothing)
				if(icon_state && icon_states_fast(update_icon_define_digi):Find(icon_state)) //Unsure what to do to this seeing as it does :Find()
					update_icon_define = update_icon_define_digi

		// if not-digitigrade, only act if the clothing was previously fit for a digitigrade char
		else
			if(fit_for_digi)
				fit_for_digi = FALSE

				//either reset update_icon_define to it's old value
				// or reset update_icon_define to null
				if(update_icon_define_orig)
					update_icon_define = update_icon_define_orig
					update_icon_define_orig = null
				else
					update_icon_define = null

/obj/item/clothing
	MATERIAL_BULK(MAT_FIBERS, 50)

/obj/item/clothing
	COOLDOWN_DECLARE(struggle_cooldown)

/obj/item/clothing/relaymove(mob/living/user,direction)

	if(!COOLDOWN_FINISHED(src, struggle_cooldown))
		return
	COOLDOWN_START(src, struggle_cooldown, 10 SECONDS)

	if(ishuman(src.loc)) //Is this on a person?
		var/mob/living/carbon/human/H = src.loc
		if(isvoice(user)) //Is this a possessed item? Spooky. It can move on it's own!
			to_chat(H, span_red("The [src] shifts about, almost as if squirming!"))
			to_chat(user, span_red("You cause the [src] to shift against [H]'s form! Well, what little you can get to, given your current state!"))
		else if(H.get_equipped_item(SLOT_ID_SHOES) == src)
			to_chat(H, span_red("[user]'s tiny body presses against you in \the [src], squirming!"))
			to_chat(user, span_red("Your body presses out against [H]'s form! Well, what little you can get to!"))
		else
			to_chat(H, span_red("[user]'s form shifts around in the \the [src], squirming!"))
			to_chat(user, span_red("You move around inside the [src], to no avail."))
	else if(isvoice(user)) //Possessed!
		src.visible_message(span_red("The [src] shifts about!"))
		to_chat(user, span_red("You cause the [src] to shift about!"))
	else
		src.visible_message(span_red("\The [src] moves a little!"))
		to_chat(user, span_red("You throw yourself against the inside of \the [src]!"))

/// the master_rig this refers to (a relation view: null once it is deleted).
/obj/item/clothing/proc/master_rig() as /obj/item/rig
	return master_rig
