// The human's look: one draw(look) over the body, the looks profile record, the worn and held items, the furry accessories and the
// body's own states. Nothing calls a redraw: equipping, a limb's damage, a style or colour change, a tail starting to wag all publish
// what they wrote, and the engine runs the draw again.
//
// Layer order is the order of the *_LAYER defines (code/__defines/update_icons.dm): every layer is an image at BODY_LAYER + its index,
// so the body sits under the uniform, the tail as seen from the south sits under the uniform and over it from the north
// (get_tail_layer()), and the hands sit over everything worn.
//
// The images are shared: a layer whose inputs did not change is the same cached icon or image, so its change key is the same and the
// look is not applied again. Icons composed with Blend() are cached by the text of every input (human_look_icon()), never rebuilt per draw.
//
// look_layers() is also what other code reads when it wants the human's layers (a gargoyle's statue, a voodoo doll, a ghost's copy).

/mob/living/carbon/human/draw(datum/look/look)
	..()
	if(!species)
		return
	var/list/body = body_look()
	if(body)
		look.set_icon(body[1])
	// A protean form that is not a body (a blob, a beast) shows its own appearance instead of the body's layers.
	var/datum/forms/forms = character_forms
	if(forms && has_trait(src, TRAIT_FORM_HIDES_BODY))
		look.watch(forms)
		for(var/form_overlay in forms.form_overlays)
			look.overlay(form_overlay)
		return
	var/list/layers = look_layers(look, body)
	for(var/index in 1 to TOTAL_LAYERS)
		var/entry = layers[index]
		if(islist(entry))
			for(var/part in entry)
				look.overlay(part)
		else if(entry)
			look.overlay(entry)
	look_body_effects(look, body)

/// The human's layers as a list of TOTAL_LAYERS entries (an image, a list of images, or null), indexed by the *_LAYER defines. `look`
/// is the draw's builder (null for a reader outside a draw): the items read are watched through it.
/mob/living/carbon/human/proc/look_layers(datum/look/look, list/body)
	RETURN_TYPE(/list)
	. = new /list(TOTAL_LAYERS)
	if(!species)
		return
	if(!body)
		body = body_look()
	if(body)
		.[BODYPARTS_LAYER] = body[2]
	.[MUTATIONS_LAYER] = mutations_look()
	.[SKIN_LAYER] = species.skin_look(src)
	.[BLOOD_LAYER] = blood_look()
	.[MOB_DAM_LAYER] = damage_look(look)
	.[SURGERY_LAYER] = surgery_look(look)
	.[UNDERWEAR_LAYER] = underwear_look()
	var/list/hair = hair_look(look)
	.[HAIR_LAYER] = hair[1]
	.[HAIR_ACCESSORY_LAYER] = hair[2]
	.[EYES_LAYER] = eyes_look()
	var/list/tail = tail_look()
	if(tail)
		.[tail[1]] = tail[2]
	.[WING_LAYER] = wing_look(FALSE)
	if(wing_style?.multi_dir)
		.[WING_LOWER_LAYER] = wing_look(TRUE)
	.[VORE_BELLY_LAYER] = vore_belly_look()
	.[VORE_TAIL_LAYER] = vore_tail_look()
	.[MODIFIER_EFFECTS_LAYER] = modifier_look()
	.[FIRE_LAYER] = fire_look()
	.[MOB_WATER_LAYER] = water_look()
	worn_look(., look, !!tail && (tail[1] == TAIL_LOWER_LAYER || tail[1] == TAIL_UPPER_LAYER))

TRACKED(/mob/living/carbon/human, wagging)
TRACKED(/mob/living/carbon/human, flapping)
TRACKED(/mob/living/carbon/human, struggle_anim_stomach)
TRACKED(/mob/living/carbon/human, struggle_anim_taur)

/// The human's layers as one flat list of images (look_layers()), less the layer indices in `discarded`.
/mob/living/carbon/human/proc/look_layer_images(list/discarded)
	RETURN_TYPE(/list)
	. = list()
	var/list/layers = look_layers()
	for(var/index in 1 to TOTAL_LAYERS)
		if(discarded && (index in discarded))
			continue
		var/entry = layers[index]
		if(islist(entry))
			. += entry
		else if(entry)
			. += entry

TRACKED(/mob/living/carbon/human, all_underwear)
TRACKED(/mob/living/carbon/human, all_underwear_metadata)
TRACKED(/mob/living/carbon/human, hide_underwear)

/// The underwear lists (what is worn, its tweaks, what is hidden) are edited in place: the editor says so, and the draw follows.
/mob/living/carbon/human/proc/underwear_edited()
	tracked_changed(src, nameof(all_underwear))
	tracked_changed(src, nameof(all_underwear_metadata))
	tracked_changed(src, nameof(hide_underwear))

/// The appearance flags the human's own overlays carry (the eyes, the bellies): the mob's, which lose PIXEL_SCALE for a fuzzy sprite.
/mob/living/carbon/human/proc/overlay_flags()
	return fuzzy ? (initial(appearance_flags) & ~PIXEL_SCALE) : initial(appearance_flags)

/// A layer image built in one call (a draw writes no image's members): `state` of `icon`, at `layer`, tinted and faded.
/proc/human_layer_image(icon, state, layer = FLOAT_LAYER, plane = FLOAT_PLANE, alpha = 255, color = null, flags = null)
	READS_FROM()
	var/image/I = image(icon = icon, icon_state = state, layer = layer)
	I.plane = plane
	I.alpha = alpha
	if(!isnull(color))
		I.color = color
	if(!isnull(flags))
		I.appearance_flags = flags
	return I

// ---- the cache ----

/// Icons composed from a human's inputs, by the text of every input. Built once and kept: a body, a hair style, a tail in one colour.
DECLARE_SHARED_CACHE(human_look_icons, GLOBAL_PROC_REF(build_human_look_icon), SC_NEVER)

/// The cached value for `key`: built by `builder` (a proc of H) from `args` on the first ask. Every input of the builder is in the key.
/mob/living/carbon/human/proc/human_look_icon(key, builder, ...)
	return CACHED_KEY(human_look_icons, key, src, builder, args.Copy(3))

/proc/build_human_look_icon(mob/living/carbon/human/H, builder, list/builder_args)
	return call(H, builder)(arglist(builder_args))

// ---- the body ----

/// The body: list(the mob's icon, the body image), or null when nothing is drawn.
/mob/living/carbon/human/proc/body_look()
	var/husk = has_mutation(HUSK)
	var/fat = has_mutation(FAT)
	var/hulk = has_mutation(HULK)
	var/skeleton = has_mutation(SKELETON)
	var/list/key_result = body_icon_key()
	var/icon_key = "[key_result[1]][husk ? 1 : 0][fat ? 1 : 0][hulk ? 1 : 0][skeleton ? 1 : 0]"
	var/template = species.icon_template ? species.icon_template : 'icons/mob/human.dmi'
	return human_look_icon("body|[template]|[icon_key]", "build_body_look", template, key_result[2], husk, hulk, skeleton)

/mob/living/carbon/human/proc/build_body_look(template, wholeicontransparent, husk, hulk, skeleton)
	var/icon/stand_icon = new(template, icon_state = "blank")
	stand_icon.Blend(build_body_icon(wholeicontransparent, husk, hulk, skeleton), ICON_OVERLAY)
	var/image/body = image(stand_icon)
	body.layer = BODY_LAYER + BODYPARTS_LAYER
	return list(stand_icon, body)

/// The body icon cache key from the species, skin, eyes and every visible part, and whether every part is transparent: list(key, whole icon
/// transparent).
/mob/living/carbon/human/proc/body_icon_key()
	var/icon_key = "[species.get_race_key(src)][looks.skin_tone][looks.skin_color]" // the parts carry the body's gender (their data's body_gender)
	icon_key += looks.lip_style ? "[looks.lip_style]" : "nolips"
	var/obj/item/organ/internal/eyes/eyes = organ_in(O_EYES)
	if(eyes)
		icon_key += "[eyes.eye_rgb()]"
	else
		icon_key += "[looks.eyes_color]"
	var/obj/item/organ/external/head/head = organs_by_name[BP_HEAD]
	if(head && !istype(head, /obj/item/organ/external/stump))
		icon_key += "[head.eye_icon]"

	var/wholeicontransparent = TRUE
	for(var/organ_tag in species.has_limbs)
		var/obj/item/organ/external/part = organs_by_name[organ_tag]
		if(isnull(part) || part.is_stump() || part.is_hidden_by_sprite_accessory()) //Allowing tails to prevent bodyparts rendering, granting more spriter freedom for taur/digitigrade stuff.
			icon_key += "0"
			continue
		wholeicontransparent &&= part.transparent
		icon_key += body_part_icon_key(part)
	return list(icon_key, wholeicontransparent)

/// One visible part's share of the body icon key: species, colours, markings, polish and state (1 normal, 2 robotic, 3 necrotic),
/// transparency, taur clip and digitigrade legs.
/mob/living/carbon/human/proc/body_part_icon_key(obj/item/organ/external/part)
	. = "[part.data.get_species_race_key(part.owner)][part.data.body_gender][part.s_tone]"
	if(part.s_col && part.s_col.len >= 3)
		. += "[rgb(part.s_col[1],part.s_col[2],part.s_col[3])]"
	if(part.body_hair && part.h_col && part.h_col.len >= 3)
		. += "[rgb(part.h_col[1],part.h_col[2],part.h_col[3])]"
		. += species.color_mult ? "[ICON_MULTIPLY]" : "[ICON_ADD]"
	else
		. += "#000000"
	for(var/M in part.markings)
		if(part.markings[M]["on"])
			. += "[M][part.markings[M]["color"]]"
	if(part.nail_polish)
		. += "_[part.nail_polish.icon]_[part.nail_polish.icon_state]_[part.nail_polish.color]"
	if(part.is_robotic())
		. += "2[part.model ? "-[part.model]": ""]"
	else if(part.status & ORGAN_DEAD)
		. += "3"
	else
		. += "1"
	if(part.transparent) //For better slime limbs. Avoids using solid var due to limb dropping.
		. += "_t"
	if(istype(tail_style, /datum/sprite_accessory/tail/taur) && tail_style.clip_mask)
		. += tail_style.clip_mask_state
	if(looks.digitigrade && (part.organ_tag in list(BP_R_LEG, BP_L_LEG, BP_R_FOOT, BP_L_FOOT)))
		. += "_digi"

/// A taur tail's leg "cookie cutter" (preserved areas inverted): list(icon, x offset, y offset), or null.
/mob/living/carbon/human/proc/body_taur_cutter()
	if(!istype(tail_style, /datum/sprite_accessory/tail/taur) || !tail_style.clip_mask)
		return null
	var/icon/Cutter = new(icon = (tail_style.clip_mask_icon ? tail_style.clip_mask_icon : tail_style.icon), icon_state = tail_style.clip_mask_state)
	Cutter.Blend("#000000", ICON_MULTIPLY)	// Make it all black.
	Cutter.SwapColor("#00000000", "#FFFFFFFF")	// Everywhere empty, make white.
	Cutter.SwapColor("#000000FF", "#00000000")	// Everywhere black, make empty.
	Cutter.Blend("#000000", ICON_MULTIPLY)	// Black again.
	return list(Cutter, tail_style.offset_x, tail_style.offset_y)

/// Compose the body icon from every visible part, then tint it for husk or hulk. A cache builder (body_look()).
/mob/living/carbon/human/proc/build_body_icon(wholeicontransparent, husk, hulk, skeleton)
	var/obj/item/organ/external/chest = get_organ(BP_TORSO)
	var/icon/base_icon = new(chest?.get_icon(skeleton, !wholeicontransparent))

	var/apply_extra_transparency_leg = organs_by_name[BP_L_LEG] && organs_by_name[BP_R_LEG]
	var/apply_extra_transparency_foot = organs_by_name[BP_L_FOOT] && organs_by_name[BP_R_FOOT]
	var/list/cutter = body_taur_cutter()

	for(var/obj/item/organ/external/part in organs)
		if(part.is_stump() || part == chest || part.is_hidden_by_sprite_accessory()) //Allowing tails to prevent bodyparts rendering, granting more spriter freedom for taur/digitigrade stuff.
			continue
		var/icon/temp = new(part.get_icon(skeleton, !wholeicontransparent))

		if(cutter && (part.organ_tag in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)))
			temp.Blend(cutter[1], ICON_AND, x = cutter[2], y = cutter[3])

		//That part makes left and right legs drawn topmost and lowermost when human looks WEST or EAST
		//And no change in rendering for other parts (they icon_position is 0, so goes to 'else' part)
		if(part.icon_position & (LEFT | RIGHT))
			var/icon/temp2 = new(species.icon_template ? species.icon_template : 'icons/mob/human.dmi', icon_state = "blank")
			temp2.Insert(new/icon(temp,dir=NORTH),dir=NORTH)
			temp2.Insert(new/icon(temp,dir=SOUTH),dir=SOUTH)
			if(!(part.icon_position & LEFT))
				temp2.Insert(new/icon(temp,dir=EAST),dir=EAST)
			if(!(part.icon_position & RIGHT))
				temp2.Insert(new/icon(temp,dir=WEST),dir=WEST)
			base_icon.Blend(temp2, ICON_OVERLAY)
			temp2 = new(species.icon_template ? species.icon_template : 'icons/mob/human.dmi', icon_state = "blank")
			if(part.icon_position & LEFT)
				temp2.Insert(new/icon(temp,dir=EAST),dir=EAST)
			if(part.icon_position & RIGHT)
				temp2.Insert(new/icon(temp,dir=WEST),dir=WEST)
			if(part.transparent && !wholeicontransparent) //apply a little (a lot) extra transparency to make it look better.
				if((istype(part, /obj/item/organ/external/leg) && apply_extra_transparency_leg) || (istype(part, /obj/item/organ/external/foot) && apply_extra_transparency_foot))
					temp2 += rgb(,,,30)
			base_icon.Blend(temp2, ICON_UNDERLAY)
		else if(part.icon_position & UNDER)
			base_icon.Blend(temp, ICON_UNDERLAY)
		else
			base_icon.Blend(temp, ICON_OVERLAY)

	if(wholeicontransparent) // A whole-slime body; a lone solid limb would look uneven, but that's rare.
		base_icon += rgb(,,,180)

	if(!skeleton)
		if(husk)
			base_icon.ColorTone(rgb(96,88,80))
		else if(hulk)
			var/list/tone = rgb2num(rgb(48,224,40))
			base_icon.MapColors(rgb(tone[1],0,0),rgb(0,tone[2],0),rgb(0,0,tone[3]))

	//Handle husk overlay.
	if(husk && icon_exists(species.icobase, "overlay_husk"))
		var/icon/mask = new(base_icon)
		var/icon/husk_over = new(species.icobase,"overlay_husk")
		mask.MapColors(0,0,0,1, 0,0,0,1, 0,0,0,1, 0,0,0,1, 0,0,0,0)
		husk_over.Blend(mask, ICON_ADD)
		base_icon.Blend(husk_over, ICON_OVERLAY)
	return base_icon

/// What the body look does besides drawing: a taur or a long tail moves the whole mob (its offsets are the mob's), a rideable taur is mountable,
/// and a shadekin recomputes what its body changes. Effects run once the look is applied, outside the draw.
/mob/living/carbon/human/proc/look_body_effects(datum/look/look, list/body)
	if(tail_style && body)
		look.effect(PROC_REF(look_effect_tail_offsets), tail_style.mob_offset_x, tail_style.mob_offset_y, (tail_style.can_loaf && !is_shifted) ? (resting ? -tail_style.loaf_offset * size_multiplier : null) : null)
	var/datum/sprite_accessory/tail/taur/taurtype = tail_style
	look.effect_if(istype(taurtype) && taurtype.can_ride && !tail_hidden, PROC_REF(look_effect_taur_mount))
	look.effect_if(species.component_requires_late_recalc, PROC_REF(look_effect_shadekin_recalc))

/mob/living/carbon/human/proc/look_effect_tail_offsets(offset_x, offset_y, loaf_y)
	pixel_x = offset_x
	pixel_y = offset_y
	default_pixel_x = offset_x
	default_pixel_y = offset_y
	if(!isnull(loaf_y))
		pixel_y = loaf_y

/mob/living/carbon/human/proc/look_effect_taur_mount()
	if(riding_datum)
		return
	rel_set(src, nameof(riding_datum), new /datum/riding/taur(src))
	grant(src, granted_verb(/mob/living/carbon/human/proc/taur_mount), src)
	grant(src, granted_verb(/mob/living/proc/toggle_rider_reins), src)

/mob/living/carbon/human/proc/look_effect_shadekin_recalc()
	var/datum/shadekin/SK = get_shadekin_state()
	SK?.recalc_values()

/// A body that picks its body type draws the base species' eyes, unless the head keeps its own (eye_icon_override). Set when the head joins
/// and when the species changes, never by the draw.
/mob/living/carbon/human/proc/sync_head_eye_icon()
	var/obj/item/organ/external/head/head = organs_by_name[BP_HEAD]
	if(!istype(head) || head.eye_icon_override || species.selects_bodytype == SELECTS_BODYTYPE_FALSE)
		return
	var/list/headtype = GLOB.all_species[species.base_species]?.has_limbs[BP_HEAD]
	var/obj/item/organ/external/head/headtypepath = headtype?["path"]
	if(!headtypepath)
		return
	head.eye_icon = initial(headtypepath.eye_icon)
	head.eye_icon_location = initial(headtypepath.eye_icon_location)

/obj/item/organ/external/head/joined_body(mob/living/M)
	..()
	var/mob/living/carbon/human/H = M
	if(istype(H) && H.species)
		H.sync_head_eye_icon()

/// Torso, groin and head prostheses (ORGAN_ROBOT or ORGAN_LIFELIKE): the parts that run hot.
/mob/living/carbon/human/proc/robobody_count()
	. = 0
	for(var/organ_tag in list(BP_HEAD, BP_TORSO, BP_GROIN))
		var/obj/item/organ/external/part = organs_by_name[organ_tag]
		if(part && !part.is_stump() && (part.robotic == ORGAN_ROBOT || part.robotic == ORGAN_LIFELIKE))
			.++

// ---- the body's own layers ----

/mob/living/carbon/human/proc/mutations_look()
	if(!has_mutation(LASER_EYES))
		return null
	var/static/image/laser_eyes
	if(!laser_eyes)
		laser_eyes = image(icon = 'icons/effects/genetics.dmi', layer = BODY_LAYER + MUTATIONS_LAYER)
		laser_eyes.overlays += "lasereyes_s" // ALLOW(dx_raw_overlays): a shared image built once, never a holder's overlays
	return laser_eyes

/// The species' skin overlay (most species have none).
/datum/species/proc/skin_look(mob/living/carbon/human/H)
	return null

/mob/living/carbon/human/proc/blood_look()
	var/bloody_hands = forensic_data?.get_blooddna()
	if(!bloody_hands && !feet_blood_DNA)
		return null
	. = list()
	if(LAZYLEN(bloody_hands))
		. += human_layer_image(species.get_blood_mask(src), "bloodyhands", BODY_LAYER + BLOOD_LAYER, color = hand_blood_color)
	if(feet_blood_DNA)
		. += human_layer_image(looks.digitigrade ? 'icons/mob/human_races/masks/blood_digitigrade.dmi' : species.get_blood_mask(src), "shoeblood", BODY_LAYER + BLOOD_LAYER, color = feet_blood_color)

/// The wound overlay of every damaged, visible limb, blended with the species' blood colour.
/mob/living/carbon/human/proc/damage_look(datum/look/look)
	var/key = ""
	for(var/obj/item/organ/external/O in organs)
		look?.watch(O)
		if(isnull(O) || O.is_stump() || O.is_hidden_by_sprite_accessory() || O.damage_state == "00")
			continue
		key += "[O.damage_state]/[O.icon_name];"
	if(!length(key))
		return null
	var/blood_colour = species.get_blood_colour(src)
	var/bodytype = species.get_bodytype(src)
	return human_look_icon("damage|[species.get_damage_overlays(src)]|[species.get_damage_mask(src)]|[blood_colour]|[bodytype]|[key]", "build_damage_look", key, blood_colour)

/mob/living/carbon/human/proc/build_damage_look(key, blood_colour)
	var/image/standing = image(icon = species.damage_overlays, icon_state = "00", layer = BODY_LAYER + MOB_DAM_LAYER)
	for(var/part in splittext(key, ";"))
		if(!length(part))
			continue
		var/list/bits = splittext(part, "/")
		var/icon/DI = icon(species.get_damage_overlays(src), bits[1])			// the damage icon for whole human
		DI.Blend(icon(species.get_damage_mask(src), bits[2]), ICON_MULTIPLY)	// mask with this organ's pixels
		DI.Blend(blood_colour, ICON_MULTIPLY)
		standing.overlays += DI // ALLOW(dx_raw_overlays): a cached image built once, never a holder's overlays
	return standing

/mob/living/carbon/human/proc/surgery_look(datum/look/look)
	. = null
	for(var/obj/item/organ/external/E in organs)
		look?.watch(E)
		if(E.open)
			LAZYADD(., human_layer_image('icons/mob/surgery.dmi', "[E.icon_name][round(E.open)]", BODY_LAYER + SURGERY_LAYER))

/mob/living/carbon/human/proc/underwear_look()
	if(!(species.appearance_flags & HAS_UNDERWEAR))
		return null
	. = list()
	for(var/category in all_underwear)
		if(hide_underwear[category])
			continue
		var/datum/category_item/underwear/UWI = LAZYACCESS(all_underwear, category)
		var/image/wear = UWI.generate_image(all_underwear_metadata[category], layer = BODY_LAYER + UNDERWEAR_LAYER, digitigrade = looks.digitigrade)
		if(wear)
			. += wear

/// Hair, facial hair and ears as one image, and the hair accessory: list(hair, accessory). Masks and helmets that block hair hide them.
/mob/living/carbon/human/proc/hair_look(datum/look/look)
	. = list(null, null)
	var/obj/item/organ/external/head/head_organ = get_organ(BP_HEAD)
	if(!head_organ || head_organ.is_stump())
		return
	var/obj/item/head_item = get_equipped_item(SLOT_ID_HEAD)
	var/obj/item/mask_item = get_equipped_item(SLOT_ID_MASK)
	look?.watch(head_item)
	look?.watch(mask_item)
	if((head_item && (worn_of(head_item).hides & BLOCKHAIR)) || (mask_item && (worn_of(mask_item).hides & BLOCKHAIR)))
		return
	var/block_head_hair = head_item && (worn_of(head_item).hides & BLOCKHEADHAIR)
	var/bodytype = species.get_bodytype(src)

	var/facial_key = ""
	if(looks.facial_style)
		var/datum/sprite_accessory/facial_hair_style = GLOB.facial_hair_styles_list[looks.facial_style]
		if(facial_hair_style && facial_hair_style.species_allowed && (bodytype in facial_hair_style.species_allowed))
			facial_key = "[looks.facial_style]|[looks.facial_color]"
	var/hair_key = ""
	if(looks.hair_style)
		var/datum/sprite_accessory/hair/hair_style = GLOB.hair_styles_list[looks.hair_style]
		var/hair_name = looks.hair_style
		if(block_head_hair && hair_style && !(hair_style.flags & HAIR_VERY_SHORT))
			hair_name = "Short Hair"
			hair_style = GLOB.hair_styles_list[hair_name]
		if(hair_style && (bodytype in hair_style.species_allowed))
			hair_key = "[hair_name]|[looks.hair_color]|[looks.grad_style]|[looks.grad_color]"
	var/ears_key = ears_look_key(block_head_hair)
	.[1] = human_look_icon("hair|[facial_key]|[hair_key]|[ears_key]|[head_organ.transparent]|[head_organ.head_offset]", "build_hair_look", facial_key, hair_key, block_head_hair, head_organ.transparent, head_organ.head_offset)

	var/datum/sprite_accessory/hair_accessory/accessory = hair_accessory_style()
	if(accessory && !block_head_hair)
		.[2] = human_look_icon("hair_accessory|[accessory.type]|[looks.ears_color]|[overlay_flags()]", "build_hair_accessory_look", looks.ears_color, overlay_flags())

/mob/living/carbon/human/proc/build_hair_look(facial_key, hair_key, block_head_hair, transparent, head_offset)
	var/icon/face_standing = icon(icon = 'icons/mob/human_face.dmi', icon_state = "bald_s")
	if(length(facial_key))
		var/datum/sprite_accessory/facial_hair_style = GLOB.facial_hair_styles_list[looks.facial_style]
		var/icon/facial_s = new/icon("icon" = facial_hair_style.icon, "icon_state" = "[facial_hair_style.icon_state]_s")
		if(facial_hair_style.do_colouration)
			facial_s.Blend(looks.facial_color, facial_hair_style.color_blend_mode)
		face_standing.Blend(facial_s, ICON_OVERLAY)
	if(length(hair_key))
		var/datum/sprite_accessory/hair/hair_style = GLOB.hair_styles_list[splittext(hair_key, "|")[1]]
		var/icon/grad_s = null
		var/icon/hair_s = new/icon("icon" = hair_style.icon, "icon_state" = "[hair_style.icon_state]_s")
		var/icon/hair_s_add = new/icon("icon" = hair_style.icon_add, "icon_state" = "[hair_style.icon_state]_s")
		if(hair_style.do_colouration)
			if(looks.grad_style)
				grad_s = new/icon("icon" = 'icons/mob/hair_gradients.dmi', "icon_state" = GLOB.hair_gradients[looks.grad_style])
				grad_s.Blend(hair_s, ICON_AND)
				grad_s.Blend(looks.grad_color, ICON_MULTIPLY)
			hair_s.Blend(looks.hair_color, ICON_MULTIPLY)
			hair_s.Blend(hair_s_add, ICON_ADD)
			if(!isnull(grad_s))
				hair_s.Blend(grad_s, ICON_OVERLAY)
		face_standing.Blend(hair_s, ICON_OVERLAY)

	var/icon/ears_s = get_ears_overlay(block_head_hair)
	if(transparent)
		face_standing += rgb(,,,120)
	var/image/em_block_ears
	if(ears_s)
		if(ears_s.Height() > face_standing.Height()) // Tol ears
			face_standing.Crop(1, 1, face_standing.Width(), ears_s.Height())
		face_standing.Blend(ears_s, ICON_OVERLAY)
		// todo: these should be considered separately, but it'd take a slight refactor to how sprite acc's are rendered (or atleast ears)
		if(ear_style?.em_block || ear_secondary_style?.em_block)
			em_block_ears = em_block_image_generic(image(ears_s))
	var/image/semifinal = image(face_standing, layer = BODY_LAYER + HAIR_LAYER, "pixel_y" = head_offset)
	if(em_block_ears)
		semifinal.overlays += em_block_ears // ALLOW(dx_raw_overlays): a cached image built once, never a holder's overlays
	return semifinal

/mob/living/carbon/human/proc/build_hair_accessory_look(colour, flags)
	var/datum/sprite_accessory/hair_accessory/accessory = hair_accessory_style()
	var/icon/hair_acc_s = icon(accessory.icon, accessory.icon_state)
	if(accessory.do_colouration)
		hair_acc_s.Blend(colour, accessory.color_blend_mode)
	if(accessory.ignores_lighting)
		return human_layer_image(hair_acc_s, null, plane = PLANE_LIGHTING_ABOVE, flags = flags)
	return image(hair_acc_s, layer = BODY_LAYER + HAIR_ACCESSORY_LAYER)

/// The text of every input of the ears overlay (get_ears_overlay()).
/mob/living/carbon/human/proc/ears_look_key(block_head_hair)
	var/datum/robolimb/model = robolimb_model()
	if(istype(model) && model.includes_ears && !ear_style && !ear_secondary_style)
		return "synth|[synthetic.icon]|[looks.ears_color]|[species.color_mult]"
	if(block_head_hair)
		return ""
	. = ""
	if(ear_style)
		. += "[ear_style.type]|[looks.ears_color]|[looks.ears_color2]|[looks.ears_color3]|[looks.ears_alpha]"
	if(ear_secondary_style)
		. += "|2|[ear_secondary_style.type]|[jointext(ear_secondary_colors || list(), ",")]|[looks.ears_alpha2]"

/// Glowing eyes, above the lighting plane. Plain eyes are drawn by the head itself.
/mob/living/carbon/human/proc/eyes_look()
	if(!species.has_glowing_eyes)
		return null
	var/obj/item/head_item = get_equipped_item(SLOT_ID_HEAD)
	var/obj/item/mask_item = get_equipped_item(SLOT_ID_MASK)
	if((!should_have_organ(O_EYES) && !species.dispersed_eyes) || (head_item && (worn_of(head_item).hides & BLOCKHAIR)) || (mask_item && (worn_of(mask_item).hides & BLOCKHAIR)))
		return null
	var/obj/item/organ/external/head/head_organ = get_organ(BP_HEAD)
	if(!head_organ || head_organ.is_stump() || !head_organ.eye_icon)
		return null
	var/obj/item/organ/internal/eyes/eyes = organ_in(O_EYES)
	var/tint = null
	if(!findtext(head_organ.eye_icon, regex("-colored")))
		if(species.dispersed_eyes) // Set so all species who would lack eye organs still have glowing eyes colored correctly
			tint = "blend|[looks.eyes_color]"
		else if(eyes)
			tint = "add|[eyes.eye_rgb()]"
		else
			tint = "add|[rgb(128,0,0)]"
	return human_look_icon("eyes|[head_organ.eye_icon_location]|[head_organ.eye_icon]|[tint]|[head_organ.transparent]|[overlay_flags()]", "build_eyes_look", head_organ.eye_icon_location, head_organ.eye_icon, tint, head_organ.transparent, overlay_flags())

/mob/living/carbon/human/proc/build_eyes_look(location, state, tint, transparent, flags)
	var/icon/eyes_icon = new/icon(location, state)
	if(tint)
		var/list/how = splittext(tint, "|")
		if(how[1] == "blend")
			eyes_icon.Blend(how[2])
		else
			eyes_icon.Blend(how[2], ICON_ADD)
	if(transparent)
		eyes_icon += rgb(,,,180)
	return human_layer_image(eyes_icon, null, plane = PLANE_LIGHTING_ABOVE, flags = flags)

/mob/living/carbon/human/proc/modifier_look()
	return body_effect_overlays()

/mob/living/carbon/human/proc/fire_look()
	if(!stat_value(src, STAT_ON_FIRE))
		return null
	return human_layer_image('icons/mob/OnFire.dmi', get_fire_icon_state(), BODY_LAYER + FIRE_LAYER)

/// Standing in water (or the stardog's fur): the legs are drawn sunk in it.
/mob/living/carbon/human/proc/water_look()
	if(lying || !water_depth)
		return null
	if(water_depth == WATER_DEPTH_FUR)
		return human_layer_image('icons/turf/fur.dmi', "submerged", BODY_LAYER + MOB_WATER_LAYER, color = water_color)
	return human_layer_image('icons/mob/submerged.dmi', "human_swimming_[water_depth]", BODY_LAYER + MOB_WATER_LAYER, color = water_color)

// ---- the tail, wings and bellies ----

/mob/living/carbon/human/proc/get_tail_layer()
	// Layer follows facing direction: the tail sits under the clothing when facing south, east or west, and over the uniform
	// (TAIL_UPPER_LAYER) when facing north, where it hangs over the back of the pants. Individual tail sprites may override the lower dirs.
	var/list/lower_layer_dirs = list(SOUTH, EAST, WEST)
	if(tail_style)
		lower_layer_dirs = tail_style.lower_layer_dirs
	if(dir in lower_layer_dirs)
		return TAIL_LOWER_LAYER
	return TAIL_UPPER_LAYER

/// The tail: list(layer, image), or null for none.
/mob/living/carbon/human/proc/tail_look()
	var/tail_layer = get_tail_layer()
	if(tail_style?.clip_mask_state)
		tail_layer = TAIL_UPPER_LAYER		// Use default, let clip mask handle everything
	var/image/tail_image = get_tail_image(BODY_LAYER + tail_layer)
	if(tail_image)
		return list(tail_layer, tail_image)
	var/species_tail = species.get_tail(src) // Species tail icon_state prefix.
	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	if(!species_tail || (suit && (worn_of(suit).hides & HIDETAIL)))
		return null
	var/obj/item/organ/external/chest = organs_by_name[BP_TORSO]
	var/state = "[species_tail]_s"
	if(species.get_tail_animation(src))
		state = (stat == DEAD) ? "[species_tail]_static" : (tail_anim_state || state)
	return list(tail_layer, human_layer_image(get_tail_icon(), state, BODY_LAYER + tail_layer, alpha = chest?.transparent ? 180 : 255))

/mob/living/carbon/human/proc/get_tail_icon()
	return human_look_icon("tail_icon|[species.get_race_key(src)]|[looks.skin_color]|[looks.hair_color]", "build_tail_icon")

/mob/living/carbon/human/proc/build_tail_icon()
	var/species_tail_anim = species.get_tail_animation(src)
	if(!species_tail_anim && species.icobase_tail)
		species_tail_anim = species.icobase //Allow override of file for non-animated tails
	if(!species_tail_anim)
		species_tail_anim = 'icons/effects/species.dmi'
	var/icon/tail_icon = new/icon(species_tail_anim)
	tail_icon.Blend(looks.skin_color, species.color_mult ? ICON_MULTIPLY : ICON_ADD)
	// The following will not work with animated tails.
	var/use_species_tail = species.get_tail_hair(src)
	if(use_species_tail)
		var/icon/hair_icon = icon('icons/effects/species.dmi', "[species.get_tail(src)]_[use_species_tail]")
		hair_icon.Blend(looks.hair_color, species.color_mult ? ICON_MULTIPLY : ICON_ADD)				//Check for species color_mult
		tail_icon.Blend(hair_icon, ICON_OVERLAY)
	return tail_icon

/// A custom or prosthetic tail's image at `layer`, or null.
/mob/living/carbon/human/proc/get_tail_image(layer = FLOAT_LAYER)
	//If you are FBP with tail style and didn't set a custom one
	var/datum/robolimb/model = robolimb_model()
	if(istype(model) && model.includes_tail && !tail_style && !tail_hidden)
		return human_look_icon("synth_tail|[synthetic.icon]|[looks.skin_color]|[species.color_mult]|[layer]", "build_synth_part", "tail", layer)
	//If you have a custom tail selected
	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	if(!tail_style || (suit && (worn_of(suit).hides & HIDETAIL) && !istaurtail(tail_style)) || tail_hidden)
		return null
	var/loaf = tail_style.can_loaf && resting
	var/wag = wagging && tail_style.ani_state
	return human_look_icon("tail|[tail_style.type]|[loaf]|[wag]|[looks.tail_color]|[looks.tail_color2]|[looks.tail_color3]|[looks.tail_alpha]|[layer]", "build_tail_image", loaf, wag, layer)

/mob/living/carbon/human/proc/build_synth_part(state, layer)
	var/icon/part_s = new/icon("icon" = synthetic.icon, "icon_state" = state)
	part_s.Blend(looks.skin_color, species.color_mult ? ICON_MULTIPLY : ICON_ADD)
	var/image/working = image(part_s)
	if(state == "wing")
		working.overlays += em_block_image_generic(working) // ALLOW(dx_raw_overlays): a cached image built once, never a holder's overlays
	working.layer = layer
	return working

/mob/living/carbon/human/proc/build_tail_image(loaf, wag, layer)
	var/tail_file = loaf ? tail_style.icon_loaf : tail_style.icon
	var/icon/tail_s = new/icon("icon" = tail_file, "icon_state" = (wag ? tail_style.ani_state : tail_style.icon_state))
	if(tail_style.do_colouration)
		tail_s.Blend(looks.tail_color, tail_style.color_blend_mode)
	if(tail_style.extra_overlay)
		var/icon/overlay = new/icon("icon" = tail_file, "icon_state" = wag ? tail_style.extra_overlay_w : tail_style.extra_overlay)
		overlay.Blend(looks.tail_color2, tail_style.color_blend_mode)
		tail_s.Blend(overlay, ICON_OVERLAY)
	if(tail_style.extra_overlay2)
		var/icon/overlay = new/icon("icon" = tail_file, "icon_state" = wag ? tail_style.extra_overlay2_w : tail_style.extra_overlay2)
		overlay.Blend(looks.tail_color3, tail_style.color_blend_mode)
		tail_s.Blend(overlay, ICON_OVERLAY)
	var/image/working = image(tail_s)
	if(tail_style.em_block)
		working.overlays += em_block_image_generic(working) // ALLOW(dx_raw_overlays): a cached image built once, never a holder's overlays
	if(istaurtail(tail_style) || islongtail(tail_style))
		working.pixel_x = tail_style.offset_x
		working.pixel_y = tail_style.offset_y
	working.alpha = looks.tail_alpha
	working.layer = layer
	return working

/// The wings (`under_layer`: the half drawn behind the body, for wings drawn in two halves), or null.
/mob/living/carbon/human/proc/wing_look(under_layer)
	var/layer = BODY_LAYER + (under_layer ? WING_LOWER_LAYER : WING_LAYER)
	//If you are FBP with wing style and didn't set a custom one
	if(synthetic && synthetic.includes_wing && !wing_style && !wings_hidden)
		return human_look_icon("synth_wing|[synthetic.icon]|[looks.skin_color]|[species.color_mult]|[layer]", "build_synth_part", "wing", layer)
	//If you have custom wings selected
	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	if(!wing_style || (suit && (worn_of(suit).hides & HIDETAIL)) || wings_hidden)
		return null
	var/flap = flapping && wing_style.ani_state
	return human_look_icon("wing|[wing_style.type]|[under_layer]|[flap]|[looks.wing_color]|[looks.wing_color2]|[looks.wing_color3]|[looks.wing_alpha]|[layer]", "build_wing_image", under_layer, flap, layer)

/mob/living/carbon/human/proc/build_wing_image(under_layer, flap, layer)
	var/wing_state = flap ? wing_style.ani_state : wing_style.icon_state
	if(wing_style.multi_dir)
		wing_state += "_[under_layer ? "back" : "front"]"
	var/icon/wing_s = new/icon("icon" = wing_style.icon, "icon_state" = wing_state)
	if(wing_style.do_colouration)
		wing_s.Blend(looks.wing_color, wing_style.color_blend_mode)
	if(wing_style.extra_overlay)
		var/icon/overlay = new/icon("icon" = wing_style.icon, "icon_state" = wing_style.extra_overlay)
		overlay.Blend(looks.wing_color2, wing_style.color_blend_mode)
		wing_s.Blend(overlay, ICON_OVERLAY)
	if(wing_style.extra_overlay2)
		var/icon/overlay = new/icon("icon" = wing_style.icon, "icon_state" = wing_style.ani_state ? wing_style.extra_overlay2_w : wing_style.extra_overlay2)
		overlay.Blend(looks.wing_color3, wing_style.color_blend_mode)
		wing_s.Blend(overlay, ICON_OVERLAY)
	var/image/working = image(wing_s)
	working.alpha = looks.wing_alpha
	if(wing_style.em_block)
		working.overlays += em_block_image_generic(working) // ALLOW(dx_raw_overlays): a cached image built once, never a holder's overlays
	working.pixel_x -= wing_style.wing_offset
	working.layer = layer
	return working

/// The ears overlay: the prosthetic's, or the chosen ears and secondary ears in their colours. A cache builder input of build_hair_look().
/mob/living/carbon/human/proc/get_ears_overlay(block_head_hair)
	//If you are FBP with ear style and didn't set a custom one
	var/datum/robolimb/model = robolimb_model()
	if(istype(model) && model.includes_ears && !ear_style && !ear_secondary_style)
		var/icon/ears_s = new/icon("icon" = synthetic.icon, "icon_state" = "ears")
		ears_s.Blend(src.looks.ears_color, species.color_mult ? ICON_MULTIPLY : ICON_ADD)
		return ears_s

	var/icon/rendered
	if(ear_style && !block_head_hair)
		var/icon/ears_s = new/icon("icon" = ear_style.icon, "icon_state" = ear_style.icon_state)
		if(ear_style.do_colouration)
			ears_s.Blend(src.looks.ears_color, ear_style.color_blend_mode)
		if(ear_style.extra_overlay)
			var/icon/overlay = new/icon("icon" = ear_style.icon, "icon_state" = ear_style.extra_overlay)
			overlay.Blend(src.looks.ears_color2, ear_style.color_blend_mode)
			ears_s.Blend(overlay, ICON_OVERLAY)
		if(ear_style.extra_overlay2) //MORE COLOURS IS BETTERER
			var/icon/overlay = new/icon("icon" = ear_style.icon, "icon_state" = ear_style.extra_overlay2)
			overlay.Blend(src.looks.ears_color3, ear_style.color_blend_mode)
			ears_s.Blend(overlay, ICON_OVERLAY)
		rendered = ears_s
		rendered += rgb(,,,src.looks.ears_alpha)

	if(ear_secondary_style && !block_head_hair)
		var/icon/ears_s = new/icon("icon" = ear_secondary_style.icon, "icon_state" = ear_secondary_style.icon_state)
		if(ear_secondary_style.do_colouration)
			var/color = LAZYACCESS(ear_secondary_colors, 1)
			if(color)
				ears_s.Blend(color, ear_secondary_style.color_blend_mode)
		if(ear_secondary_style.extra_overlay)
			var/icon/overlay = new/icon("icon" = ear_secondary_style.icon, "icon_state" = ear_secondary_style.extra_overlay)
			var/color = LAZYACCESS(ear_secondary_colors, 2)
			if(color)
				overlay.Blend(color, ear_secondary_style.color_blend_mode)
			ears_s.Blend(overlay, ICON_OVERLAY)
		if(ear_secondary_style.extra_overlay2) //MORE COLOURS IS BETTERER
			var/icon/overlay = new/icon("icon" = ear_secondary_style.icon, "icon_state" = ear_secondary_style.extra_overlay2)
			var/color = LAZYACCESS(ear_secondary_colors, 3)
			if(color)
				overlay.Blend(color, ear_secondary_style.color_blend_mode)
			ears_s.Blend(overlay, ICON_OVERLAY)
		ears_s += rgb(,,,src.looks.ears_alpha2)
		if(!rendered)
			rendered = ears_s
		else
			rendered.Blend(ears_s, ICON_OVERLAY)
	return rendered

/mob/living/carbon/human/proc/vore_belly_look()
	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	if(suit && (worn_of(suit).hides & HIDETAIL))
		return null
	var/state = "[species.vore_belly_default_variant]Belly[vore_fullness_ex["stomach"]][struggle_anim_stomach ? "" : " idle"]"
	var/colour = vore_prefs.vore_sprite_color["stomach"]
	var/multiply = vore_prefs.vore_sprite_multiply["stomach"]
	return human_look_icon("vore_belly|[state]|[colour]|[multiply]|[overlay_flags()]", "build_vore_belly", 'icons/mob/vore/Bellies.dmi', state, colour, multiply, 0, TRUE, BODY_LAYER + VORE_BELLY_LAYER, overlay_flags())

/mob/living/carbon/human/proc/vore_tail_look()
	if(!tail_style || !istaurtail(tail_style) || !tail_style.vore_tail_sprite_variant)
		return null
	var/vs_fullness = vore_fullness_ex["taur belly"]
	var/loaf_alt = lying && tail_style.belly_variant_when_loaf
	var/fullness_icons = min(tail_style.fullness_icons, vs_fullness)
	var/state = "Taur[tail_style.vore_tail_sprite_variant]-Belly-[fullness_icons][loaf_alt ? " loaf" : (struggle_anim_taur ? "" : " idle")]"
	var/colour = vore_prefs.vore_sprite_color["taur belly"]
	var/multiply = vore_prefs.vore_sprite_multiply["taur belly"]
	return human_look_icon("vore_tail|[tail_style.bellies_icon_path]|[state]|[colour]|[multiply]|[tail_style.em_block]|[overlay_flags()]", "build_vore_belly", tail_style.bellies_icon_path, state, colour, multiply, -16, tail_style.em_block, BODY_LAYER + VORE_TAIL_LAYER, overlay_flags())

/mob/living/carbon/human/proc/build_vore_belly(file, state, colour, multiply, offset_x, em_block, layer, flags)
	var/icon/vorebelly_s = new/icon(icon = file, icon_state = state)
	vorebelly_s.Blend(colour, multiply ? ICON_MULTIPLY : ICON_ADD)
	var/image/working = image(vorebelly_s)
	working.pixel_x = offset_x
	if(em_block)
		working.overlays += em_block_image_generic(working) // ALLOW(dx_raw_overlays): a cached image built once, never a holder's overlays
	working.layer = layer
	working.appearance_flags = flags
	return working

// ---- what is worn and held ----

/// Each worn and held item's layer, into `layers`. `tail_rendered`: a tail is drawn at TAIL_LOWER_LAYER or TAIL_UPPER_LAYER (a taur's clip mask
/// then cuts the suit).
/mob/living/carbon/human/proc/worn_look(list/layers, datum/look/look, tail_rendered)
	var/body_type = worn_bodytype()
	var/obj/item/uniform = worn_item(look, SLOT_ID_UNIFORM)
	var/obj/item/suit = worn_item(look, SLOT_ID_SUIT)
	var/obj/item/head = worn_item(look, SLOT_ID_HEAD)
	var/obj/item/mask = worn_item(look, SLOT_ID_MASK)
	var/suit_hides = suit ? worn_of(suit).hides : NONE
	var/head_hides = head ? worn_of(head).hides : NONE
	var/mask_hides = mask ? worn_of(mask).hides : NONE

	// Uniform: a suit that hides the jumpsuit hides it (a hardsuit does not).
	if(uniform && !((suit_hides & HIDEJUMPSUIT) && !istype(suit, /obj/item/clothing/suit/space/rig)))
		var/obj/item/clothing/under/under = uniform
		var/uniform_sprite = (istype(under) && !isnull(under.update_icon_define)) ? under.update_icon_define : INV_W_UNIFORM_DEF_ICON
		var/icon/c_mask = tail_style?.clip_mask
		var/obj/item/clothing/suit/S = suit
		if(c_mask && ((suit_hides & HIDETAIL) || (istype(S) && S.taurized))) // Reasons to not mask: a suit that hides the tail, or a taurized suit.
			c_mask = null
		layers[UNIFORM_LAYER] = uniform.make_worn_icon(body_type = body_type, slot_name = slot_w_uniform_str, default_icon = uniform_sprite, default_layer = UNIFORM_LAYER, clip_mask = c_mask)

	// ID: only when the uniform shows it.
	var/obj/item/id = worn_item(look, SLOT_ID_ID)
	var/obj/item/clothing/under/id_under = uniform
	if(id && istype(id_under) && id_under.displays_id)
		layers[ID_LAYER] = id.make_worn_icon(body_type = body_type, slot_name = slot_wear_id_str, default_icon = INV_WEAR_ID_DEF_ICON, default_layer = ID_LAYER)

	var/obj/item/gloves = worn_item(look, SLOT_ID_GLOVES)
	if(gloves)
		layers[GLOVES_LAYER] = gloves.make_worn_icon(body_type = body_type, slot_name = slot_gloves_str, default_icon = INV_GLOVES_DEF_ICON, default_layer = GLOVES_LAYER)

	var/obj/item/glasses = worn_item(look, SLOT_ID_EYES)
	if(glasses && !hide_glasses)
		var/obj/item/clothing/glasses/our_glasses = glasses
		var/glasses_layer = (istype(our_glasses) && our_glasses.glasses_layer_above) ? GLASSES_LAYER_ALT : GLASSES_LAYER
		layers[glasses_layer] = glasses.make_worn_icon(body_type = body_type, slot_name = slot_glasses_str, default_icon = INV_EYES_DEF_ICON, default_layer = glasses_layer)

	layers[EARS_LAYER] = ears_worn_look(look, head_hides, mask_hides)
	layers[SHOES_LAYER] = shoes_worn_look(look, body_type, suit_hides, uniform ? worn_of(uniform).hides : NONE)
	if(islist(layers[SHOES_LAYER]))
		var/list/shoes = layers[SHOES_LAYER]
		layers[SHOES_LAYER] = null
		layers[shoes[1]] = shoes[2]

	var/obj/item/suit_storage = worn_item(look, SLOT_ID_SUIT_STORAGE)
	if(suit_storage)
		//Basically has no variety in slot icon choices at all. WHY SPECIES ONLY??
		var/t_state = suit_storage.item_state || suit_storage.icon_state
		layers[SUIT_STORE_LAYER] = human_layer_image(species.suit_storage_icon, t_state, BODY_LAYER + SUIT_STORE_LAYER)

	if(head)
		layers[HEAD_LAYER] = head.make_worn_icon(body_type = body_type, slot_name = slot_head_str, default_icon = INV_HEAD_DEF_ICON, default_layer = HEAD_LAYER)

	var/obj/item/belt = worn_item(look, SLOT_ID_BELT)
	if(belt)
		var/obj/item/storage/belt/ubelt = belt
		var/belt_layer = (istype(ubelt) && ubelt.show_above_suit) ? BELT_LAYER_ALT : BELT_LAYER
		layers[belt_layer] = belt.make_worn_icon(body_type = body_type, slot_name = slot_belt_str, default_icon = INV_BELT_DEF_ICON, default_layer = belt_layer, clip_mask = tail_style?.clip_mask)

	if(suit)
		var/obj/item/clothing/suit/clothing_suit = suit
		var/suit_sprite = (istype(clothing_suit) && !isnull(clothing_suit.update_icon_define)) ? clothing_suit.update_icon_define : INV_SUIT_DEF_ICON
		var/icon/c_mask = null
		if(tail_rendered && tail_style?.clip_mask && !(istype(clothing_suit) && clothing_suit.taurized)) //Clip the lower half of the suit off using the tail's clip mask for taurs since taur bodies aren't hidden.
			c_mask = tail_style.clip_mask
		layers[SUIT_LAYER] = suit.make_worn_icon(body_type = body_type, slot_name = slot_wear_suit_str, default_icon = suit_sprite, default_layer = SUIT_LAYER, clip_mask = c_mask)

	if(mask && !(head_hides & HIDEMASK))
		layers[FACEMASK_LAYER] = mask.make_worn_icon(body_type = body_type, slot_name = slot_wear_mask_str, default_icon = INV_MASK_DEF_ICON, default_layer = FACEMASK_LAYER)

	var/obj/item/back = worn_item(look, SLOT_ID_BACK)
	if(back)
		var/icon/c_mask = tail_style?.clip_mask
		if(c_mask && (istype(back, /obj/item/storage/backpack/saddlebag) || istype(back, /obj/item/storage/backpack/saddlebag_common)))
			c_mask = null
		layers[BACK_LAYER] = back.make_worn_icon(body_type = body_type, slot_name = slot_back_str, default_icon = INV_BACK_DEF_ICON, default_layer = BACK_LAYER, clip_mask = c_mask)

	var/obj/item/cuffs = worn_item(look, SLOT_ID_HANDCUFFED)
	if(cuffs)
		layers[HANDCUFF_LAYER] = cuffs.make_worn_icon(body_type = body_type, slot_name = slot_handcuffed_str, default_icon = INV_HCUFF_DEF_ICON, default_layer = HANDCUFF_LAYER)
	var/obj/item/legcuffs = worn_item(look, SLOT_ID_LEGCUFFED)
	if(legcuffs)
		layers[LEGCUFF_LAYER] = legcuffs.make_worn_icon(body_type = body_type, slot_name = slot_legcuffed_str, default_icon = INV_LCUFF_DEF_ICON, default_layer = LEGCUFF_LAYER)

	var/obj/item/right = worn_item(look, SLOT_ID_HAND_R)
	if(right)
		layers[R_HAND_LAYER] = right.make_worn_icon(body_type = body_type, inhands = TRUE, slot_name = slot_r_hand_str, default_icon = INV_R_HAND_DEF_ICON, default_layer = R_HAND_LAYER)
	var/obj/item/left = worn_item(look, SLOT_ID_HAND_L)
	if(left)
		layers[L_HAND_LAYER] = left.make_worn_icon(body_type = body_type, inhands = TRUE, slot_name = slot_l_hand_str, default_icon = INV_L_HAND_DEF_ICON, default_layer = L_HAND_LAYER)

/// The item in `slot`, watched by the draw: its own changes (a visor flipped, a light on, an accessory clipped on) and its look redraw the wearer.
/mob/living/carbon/human/proc/worn_item(datum/look/look, slot)
	var/obj/item/I = get_equipped_item(slot)
	if(I && look)
		look.watch(I)
		look.watch_look(I)
	return I

/// Both ears' items, unless the head or mask blocks the ears or headsets are hidden.
/mob/living/carbon/human/proc/ears_worn_look(datum/look/look, head_hides, mask_hides)
	if((head_hides | mask_hides) & (BLOCKHAIR | BLOCKHEADHAIR))
		return null //Ears are blocked (by hair being blocked, overloaded)
	. = list()
	for(var/slot in list(SLOT_ID_EAR_L, SLOT_ID_EAR_R))
		var/obj/item/ear = worn_item(look, slot)
		if(!ear || (hide_headset && istype(ear, /obj/item/radio/headset)))
			continue
		. += ear.make_worn_icon(body_type = species.get_bodytype(src), slot_name = (slot == SLOT_ID_EAR_L ? slot_l_ear_str : slot_r_ear_str), default_icon = INV_EARS_DEF_ICON, default_layer = EARS_LAYER)

/// The shoes as list(layer, image), or null: hidden by a suit or uniform that hides shoes, or by a tail that hides the feet.
/mob/living/carbon/human/proc/shoes_worn_look(datum/look/look, body_type, suit_hides, uniform_hides)
	var/obj/item/shoe_item = worn_item(look, SLOT_ID_SHOES)
	if(!shoe_item || (suit_hides & HIDESHOES) || (uniform_hides & HIDESHOES))
		return null //Either nothing to draw, or it'd be hidden.
	for(var/f in list(BP_L_FOOT, BP_R_FOOT))
		var/obj/item/organ/external/foot/foot = get_organ(f)
		if(istype(foot) && foot.is_hidden_by_sprite_accessory(clothing_only = TRUE)) //If either foot is hidden by the tail, don't render footwear.
			return null
	var/obj/item/clothing/shoes/shoe = shoe_item
	var/shoe_sprite = (istype(shoe) && !isnull(shoe.update_icon_define)) ? shoe.update_icon_define : INV_FEET_DEF_ICON
	var/shoe_layer = (istype(shoe) && shoe.shoes_under_pants == 1) ? SHOES_LAYER_ALT : SHOES_LAYER
	return list(shoe_layer, shoe_item.make_worn_icon(body_type = body_type, slot_name = slot_shoes_str, default_icon = shoe_sprite, default_layer = shoe_layer))

/// The bodytype worn sprites are drawn for.
/mob/living/carbon/human/proc/worn_bodytype()
	return species.get_bodytype(src)

/// How deep the mob stands in water and the water's colour, kept as tracked state: the turfs, buckles and vehicles that change it call
/// refresh_submersion() (it was update_water(), which redrew the overlay by hand). A hovering, flying, buckled or incorporeal mob, or one on a
/// catwalk, is not in the water.
/mob/living
	var/water_depth = 0
	var/water_color

TRACKED(/mob/living, water_depth)
TRACKED(/mob/living, water_color)

/mob/living/proc/refresh_submersion()
	var/depth = 0
	var/colour = null
	if(istype(loc, /turf/simulated/floor/outdoors/fur) && ishuman(src))
		depth = WATER_DEPTH_FUR
		colour = loc.color
	else if(!(buckled_to() || dq_get_hovering(src) || stat_value(src, STAT_FLYING) || is_incorporeal() || locate_within(loc, /obj/structure/catwalk)))
		var/turf/simulated/floor/water/T = loc
		if(istype(T))
			depth = T.depth
			colour = T.watercolor || T.color
	set_water_depth(depth)
	set_water_color(colour)
