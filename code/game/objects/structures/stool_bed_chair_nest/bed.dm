/* Beds... get your mind out of the gutter, they're for sleeping!
 * Contains:
 * 		Beds
 *		Roller beds
 */

/*
 * Beds
 */
/obj/structure/bed
	name = "bed"
	desc = "This is used to lie in, sleep in or strap on."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "bed"
	pressure_resistance = 15
	anchored = TRUE
	can_buckle = TRUE
	buckle_dir = SOUTH
	buckle_lying = 1
	var/datum/material/material
	var/datum/material/padding_material
	var/base_icon = "bed"
	var/applies_material_colour = 1
	var/flippable = TRUE
	/// What a stack, wirecutters and a wrench can do to it: pad it, take the padding off, take it apart. FALSE on the kinds that are built to stay as they are.
	var/can_pad = TRUE
	var/can_unpad = TRUE
	var/can_dismantle = TRUE

/obj/structure/bed/Initialize(mapload, new_material, new_padding_material)
	..()
	color = null
	if(!new_material)
		new_material = MAT_STEEL
	material = get_material_by_name(new_material)
	if(!istype(material))
		stack_trace("Material of type: [new_material] does not exist.")
		return INITIALIZE_HINT_QDEL
	if(new_padding_material)
		padding_material = get_material_by_name(new_padding_material)
	update_icon()
	if(flippable) // If we can't change directions, don't bother.
		// Ugly check for chairs, beds can only be flipped north and south...
		if(istype(src,/obj/structure/bed/chair))
			make_rotatable()
		else
			make_rotatable(only_flip = TRUE)
	return INITIALIZE_HINT_NORMAL

/obj/structure/bed/get_material()
	return material

// Reuse the cache/code from stools, todo maybe unify.
DECLARE_APPEARANCE_PROC(/obj/structure/bed, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/bed/appearance_overlays()
	. = list()
	// Prep icon.
	icon_state = ""
	// Base icon.
	var/cache_key = "[base_icon]-[material.name]"
	if(isnull(GLOB.stool_cache[cache_key]))
		var/image/I = image(icon, base_icon)
		if(applies_material_colour) // Goes with added var
			I.color = material.icon_colour
		GLOB.stool_cache[cache_key] = I
	. += GLOB.stool_cache[cache_key]
	// Padding overlay.
	if(padding_material)
		var/padding_cache_key = "[base_icon]-padding-[padding_material.name]"
		if(isnull(GLOB.stool_cache[padding_cache_key]))
			var/image/I =  image(icon, "[base_icon]_padding")
			I.color = padding_material.icon_colour
			GLOB.stool_cache[padding_cache_key] = I
		. += GLOB.stool_cache[padding_cache_key]
	// Strings.
	desc = initial(desc)
	if(padding_material)
		name = "[padding_material.display_name] [initial(name)]" //this is not perfect but it will do for now.
		desc += " It's made of [material.use_name] and covered with [padding_material.use_name]."
	else
		name = "[material.display_name] [initial(name)]"
		desc += " It's made of [material.use_name]."

/obj/structure/bed/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return ..()

MSG_DEF_SELF(bed/already_padded, "It is already padded.")
MSG_DEF_SELF(bed/not_padding, "You cannot pad that with that.")
MSG_DEF_SELF(bed/no_padding, "It has no padding to remove.")
MSG_DEF_SELF(bed/cant_pad, "You cannot pad that.")
MSG_DEF_SELF(bed/cant_unpad, "You cannot take the padding off that.")
MSG_DEF_SELF(bed/cant_dismantle, "You cannot dismantle that.")
MSG_DEF(bed/padded, "You add padding to %T%.", "%U% adds padding to %T%.")
MSG_DEF(bed/unpadded, "You remove the padding from %T%.", "%U% removes the padding from %T%.")

CAPABILITIES(/obj/structure/bed)
	buckle()
	op("pad", stack(/obj/item/stack, 1), wait(0), label("Pad"),
		needs(req(PROC_REF(can_be_padded), because = PROC_REF(padding_refusal))), then(PROC_REF(padded_with)), says(MSG(bed/padded)))
	op("tuck_disk", item(/obj/item/disk), then(PROC_REF(tucked_in)))
	op("tuck_plushie", item(/obj/item/toy/plushie), then(PROC_REF(tucked_in)))
	op("unpad", tool(TOOL_WIRECUTTER), wait(0), label("Remove padding"),
		needs(req(PROC_REF(has_padding), because = MSG(bed/no_padding)), req(PROC_REF(unpad_allowed), because = MSG(bed/cant_unpad))),
		then(PROC_REF(unpadded)), says(MSG(bed/unpadded)))
	op("dismantle", tool(TOOL_WRENCH), wait(0), label("Dismantle"),
		needs(req(PROC_REF(dismantle_allowed), because = MSG(bed/cant_dismantle))), then(PROC_REF(taken_apart)))

/// What a bed that is not for lying on does without: the nest, the pillow piles (their own hands and items replace the bed's).
/proc/bed_hands_off()
	return list(without(CAP_BUCKLE), without("pad"), without("tuck_disk"), without("tuck_plushie"), without("unpad"), without("dismantle"))

/// The name of the material a stack pads with (a padding carpet tile or sheet), or null when it is no padding.
/proc/padding_type_of(obj/item/stack/S)
	READS_FROM() // what a stack is made of is fixed for its life
	if(istype(S, /obj/item/stack/tile/carpet))
		var/obj/item/stack/tile/carpet/C = S
		if(C.material && (C.material.flags & MATERIAL_PADDING))
			return "[C.material.name]"
	else if(istype(S, /obj/item/stack/material))
		var/obj/item/stack/material/M = S
		if(M.material && (M.material.flags & MATERIAL_PADDING))
			return "[M.material.name]"
	return null

/obj/structure/bed/proc/can_be_padded(datum/act/op/A)
	return can_pad && !padding_material && !isnull(padding_type_of(A.held)) // ALLOW(reads): the padding is a material set when the seat is made or padded; a menu entry that asks is advisory, the click asks again

/obj/structure/bed/proc/padding_refusal(datum/act/op/A)
	if(!can_pad)
		return /datum/msg/bed/cant_pad
	if(padding_material)
		return /datum/msg/bed/already_padded
	return /datum/msg/bed/not_padding

/// A stack of padding goes on: the sheet is spent by the op.
/obj/structure/bed/proc/padded_with(datum/act/op/A)
	if(!istype(src.loc, /turf))
		A.actor.drop_from_inventory(src)
		src.forceMove(get_turf(src))
	add_padding(padding_type_of(A.held))
	return OP_OK

/// A disk or a plushie is set down on the bed, at the pillow.
/obj/structure/bed/proc/tucked_in(datum/act/op/A)
	var/obj/item/W = A.held
	A.actor.drop_from_inventory(W, get_turf(src))
	W.pixel_x = 10 //make sure they reach the pillow
	W.pixel_y = -6
	if(istype(W, /obj/item/disk))
		A.actor.visible_message(span_notice("[src] sleeps soundly. Sleep tight, disky."))
	return OP_OK

/obj/structure/bed/proc/has_padding(datum/act/A)
	return !!padding_material // ALLOW(reads): the padding is a material set when the seat is made or padded; a menu entry that asks is advisory, the click asks again

/obj/structure/bed/proc/unpad_allowed(datum/act/A)
	return can_unpad

/obj/structure/bed/proc/unpadded(datum/act/op/A)
	playsound(src, A.held.usesound, 100, 1)
	remove_padding()
	return OP_OK

/obj/structure/bed/proc/dismantle_allowed(datum/act/A)
	return can_dismantle

/obj/structure/bed/proc/taken_apart(datum/act/op/A)
	playsound(src, A.held.usesound, 50, 1)
	dismantle()
	consume(src, A.actor)
	return OP_OK

/obj/structure/bed/proc/remove_padding()
	if(padding_material)
		padding_material.place_sheet(get_turf(src), 1)
		padding_material = null
	update_icon()

/obj/structure/bed/proc/add_padding(padding_type)
	padding_material = get_material_by_name(padding_type)
	update_icon()

/obj/structure/bed/proc/dismantle()
	material.place_sheet(get_turf(src), 1)
	if(padding_material)
		padding_material.place_sheet(get_turf(src), 1)

/obj/structure/bed/ghosts_can_use_rotate_verbs()
	return CONFIG_GET(flag/ghost_interaction)

/obj/structure/bed/can_use_rotate_verbs_while_anchored()
	return TRUE

/obj/structure/bed/psych
	name = "psychiatrist's couch"
	desc = "For prime comfort during psychiatric evaluations."
	icon_state = "psychbed"
	base_icon = "psychbed"

/obj/structure/bed/psych/Initialize(mapload)
	. = ..(mapload, MAT_WOOD, MAT_LEATHER)

/obj/structure/bed/padded/Initialize(mapload)
	. = ..(mapload, MAT_PLASTIC, MAT_CLOTH)

/obj/structure/bed/double
	name = "double bed"
	icon_state = "doublebed"
	base_icon = "doublebed"

/obj/structure/bed/double/padded/Initialize(mapload)
	. = ..(mapload, MAT_WOOD, MAT_CLOTH)

/obj/structure/bed/double/post_buckle_mob(mob/living/M as mob)
	if(M?.buckled_to() == src)
		M.pixel_y = 13
		M.old_y = 13
	else
		M.pixel_y = 0
		M.old_y = 0

/*
 * Roller beds
 */
/obj/structure/bed/roller
	name = "roller bed"
	desc = "A portable bed-on-wheels made for transporting medical patients."
	icon = 'icons/obj/rollerbed.dmi'
	icon_state = "rollerbed"
	anchored = FALSE
	surgery_cleanliness = 60
	var/bedtype = /obj/structure/bed/roller
	var/rollertype = /obj/item/roller
	flippable = FALSE
	can_pad = FALSE
	can_unpad = FALSE
	can_dismantle = FALSE

/obj/structure/bed/roller/adv
	name = "advanced roller bed"
	icon_state = "rollerbedadv"
	surgery_cleanliness = 75
	bedtype = /obj/structure/bed/roller/adv
	rollertype = /obj/item/roller/adv

APPEARANCE_NONE(/obj/structure/bed/roller)

CAPABILITIES(/obj/structure/bed/roller)
	op("collapse", item(/obj/item/roller_holder), label("Collapse"), then(PROC_REF(collapse_with_rack)))

/// A roller bed rack collapses an empty bed into its folded item; a bed with somebody on it lets them go instead.
/obj/structure/bed/roller/proc/collapse_with_rack(datum/act/op/A)
	var/mob/user = A.actor
	if(has_buckled_mobs())
		for(var/mob/living/occupant in src.buckled_mob_list())
			user_unbuckle_mob(occupant, user)
	else
		act_message(user, null, others = "%U% collapses \the [src.name].")
		new rollertype(get_turf(src))
		expire(0)
	return OP_OK

/obj/item/roller
	name = "roller bed"
	desc = "A collapsed roller bed that can be carried around."
	icon = 'icons/obj/rollerbed.dmi'
	icon_state = "folded_rollerbed"
	center_of_mass_x = 17
	center_of_mass_y = 7
	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_LARGE
	var/rollertype = /obj/item/roller
	var/bedtype = /obj/structure/bed/roller
	drop_sound = SFX_ITEMS_DROP_AXE
	pickup_sound = SFX_ITEMS_PICKUP_AXE

CAPABILITIES(/obj/item/roller)
	op("unfold", in_hand(), label("Unfold"), then(PROC_REF(unfolded)))
	op("rack", item(/obj/item/roller_holder), label("Rack"), when(req(PROC_REF(rack_is_empty))), then(PROC_REF(racked)), passes())

/// The folded bed is set up where its carrier stands, and is used up.
/obj/item/roller/proc/unfolded(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/bed/roller/R = new bedtype(user.loc)
	R.add_fingerprint(user)
	consume(src, user)
	return OP_OK

/// The rack held in hand has nothing in it.
/obj/item/roller/proc/rack_is_empty(datum/act/op/A)
	var/obj/item/roller_holder/RH = A.held
	return istype(RH) && !RH.held

/// The rack takes the folded bed.
/obj/item/roller/proc/racked(datum/act/op/A)
	var/obj/item/roller_holder/RH = A.held
	to_chat(A.actor, span_notice("You collect the roller bed."))
	rel_set(RH, nameof(RH.held), src)
	return OP_OK

/obj/item/roller/adv
	name = "advanced roller bed"
	desc = "A high-tech, compact version of the regular roller bed."
	icon_state = "folded_rollerbedadv"
	w_class = ITEMSIZE_NORMAL
	rollertype = /obj/item/roller/adv
	bedtype = /obj/structure/bed/roller/adv

/obj/item/roller_holder
	name = "roller bed rack"
	desc = "A rack for carrying a collapsed roller bed."
	icon = 'icons/obj/rollerbed.dmi'
	icon_state = "rollerbed"
	var/obj/item/roller/held

CAPABILITIES(/obj/item/roller_holder)
	owns_one(nameof(held), /obj/item/roller, starts = /obj/item/roller)
	op("deploy", in_hand(), label("Deploy"), when(nameof(held)), then(PROC_REF(deployed)))

/// The rack sets its folded bed up where its carrier stands.
/obj/item/roller_holder/proc/deployed(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You deploy the roller bed."))
	var/obj/structure/bed/roller/R = new held.bedtype(user.loc)
	R.add_fingerprint(user)
	rel_clear(src, nameof(held))
	return OP_OK

/obj/structure/bed/roller/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	play_sfx(src, SFX_EFFECTS_ROLL)

/obj/structure/bed/roller/post_buckle_mob(mob/living/M as mob)
	if(M?.buckled_to() == src)
		M.pixel_y = 6
		M.old_y = 6
		set_density(TRUE)
		icon_state = "[initial(icon_state)]_up"
	else
		M.pixel_y = 0
		M.old_y = 0
		set_density(FALSE)
		icon_state = "[initial(icon_state)]"
	update_icon()
	return ..()

/obj/structure/bed/roller/MouseDrop(over_object, src_location, over_location)
	..()
	return collapse_with_actor(usr, over_object) // ALLOW(sys_usr_outside_verb): Native roller bed drag supplies the actor after the unchanged parent input routing.

/obj/structure/bed/roller/proc/collapse_with_actor(mob/user, atom/over_object)
	if((over_object == user && (in_range(src, user) || user.contents.Find(src))))
		if(!ishuman(user))	return
		if(has_buckled_mobs())	return 0
		act_message(user, null, others = "%U% collapses \the [src.name].")
		new rollertype(get_turf(src))
		expire(0)
		return

/datum/category_item/catalogue/anomalous/precursor_a/alien_bed
	name = "Precursor Alpha Object - Resting Contraption"
	desc = "This appears to be a relatively long and flat object, with the top side being made of \
	an soft material, giving it very similar characteristics to an ordinary bed. If this object was \
	designed to act as a bed, this carries several implications for whatever species had built it, such as;\
	<br><br>\
	Being capable of experiencing comfort, or at least being able to suffer from some form of fatigue.<br>\
	Developing while under the influence of gravitational forces, to be able to 'lie' on the object.<br>\
	Being within a range of sizes in order for the object to function as a bed. Too small, and the species \
	would be unable to reach the top of the object. Too large, and they would have little room to contact \
	the top side of the object.<br>\
	<br><br>\
	As a note, the size of this object appears to be within the bounds for an average human to be able to \
	rest comfortably on top of it."
	value = CATALOGUER_REWARD_EASY

/obj/structure/bed/alien
	name = "resting contraption"
	desc = "Whatever species designed this must've enjoyed relaxation as well. Looks vaguely comfy."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_bed)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "bed_red"
	flippable = FALSE
	can_pad = FALSE
	can_unpad = FALSE
	can_dismantle = FALSE

APPEARANCE_NONE(/obj/structure/bed/alien)

/*
 * Dirty Mattress
 */
/obj/structure/dirtybed
	name = "dirty mattress"
	desc = "A stained matress. Guess it's better than sleeping on the floor."
	icon = 'icons/obj/furniture.dmi'
	icon_state = "dirtybed"
	pressure_resistance = 15
	anchored = TRUE
	can_buckle = TRUE
	buckle_dir = SOUTH
	buckle_lying = 1

MSG_DEF_SELF(dirtybed/loose, "The bed isn't secured.")

CAPABILITIES(/obj/structure/dirtybed)
	buckle()
	anchor()
	extend("anchor.toggle", wait(2 SECONDS))
	op("loose", item(/obj/item), label("Use"), when(req(PROC_REF(is_loose))), then(PROC_REF(note_loose)))

/// The mattress is not bolted down.
/obj/structure/dirtybed/proc/is_loose(datum/act/A)
	return !anchored

/// Anything clicked on a loose mattress only says it is not secured.
/obj/structure/dirtybed/proc/note_loose(datum/act/op/A)
	to_chat(A.actor, span_notice(" The bed isn't secured."))
	return OP_OK

