// The plain body as tinted overlays the client layers (doc/rewrite/proposals/client_side_compositing.md). A body this path cannot show yet stays composited by human_look.dm.

// ---- tints and parts ----

/// The `color` that does to a layer what `icon.Blend(colour, mode)` does to an icon: the colour itself for a multiply, a matrix whose constant row is the colour for an add.
/proc/human_tint(colour, mode = ICON_MULTIPLY)
	if(isnull(colour))
		return null
	if(mode != ICON_ADD)
		return colour
	var/list/channels = rgb2num(colour)
	return list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, channels[1] / 255, channels[2] / 255, channels[3] / 255, 0)

/// One part of a layered look: `state` of `file`, tinted, faded. Built inside a cache builder (human_look_icon()); the result is shared and never written again.
/proc/human_part(file, state, colour = null, mode = ICON_MULTIPLY, alpha = 255)
	READS_FROM()
	var/image/part = image(icon = file, icon_state = state)
	if(!isnull(colour))
		part.color = human_tint(colour, mode)
	part.alpha = alpha
	return part

/// `parts` as one picture on `layer`, offset and faded as a whole. A fade shows the parts through each other unless the group is rendered first, so a group
/// that fades (or that `together` asks for: an inset layer needs the group's own surface) is KEEP_TOGETHER.
/proc/human_part_group(list/parts, layer = FLOAT_LAYER, alpha = 255, pixel_x = 0, pixel_y = 0, together = FALSE, flags = null)
	READS_FROM()
	var/image/group = image(icon = null, layer = layer)
	if(!isnull(flags))
		group.appearance_flags = flags
	if(together || alpha < 255)
		group.appearance_flags |= KEEP_TOGETHER
	group.alpha = alpha
	group.pixel_x = pixel_x
	group.pixel_y = pixel_y
	return look_composed_image(group, parts)

/// The emissive blockers of `parts`: each part's shape, at `alpha`, shared by every colour of it.
/proc/human_em_blocks(list/parts, alpha = 255)
	READS_FROM()
	. = list()
	for(var/image/part as anything in parts)
		var/image/probe = image(part)
		probe.alpha = alpha
		. += em_block_image_generic(probe)

/// A tail or a wing: its `parts` (faded as one picture when `alpha` is under 255) and, for a sprite that blocks light, their blockers, on `layer`.
/proc/human_accessory_image(list/parts, layer, alpha = 255, pixel_x = 0, pixel_y = 0, em_block = FALSE, blocker_alpha = 255)
	READS_FROM()
	var/list/shown = parts
	if(alpha < 255)
		shown = list(human_part_group(parts, alpha = alpha))
	if(em_block)
		shown = shown + human_em_blocks(parts, blocker_alpha)
	return human_part_group(shown, layer, pixel_x = pixel_x, pixel_y = pixel_y)

/// Whether this body can be layered today: not a husk (a tone the client cannot make), not a taur whose legs a mask cuts, and no limb that needs pixels.
/mob/living/carbon/human/proc/can_layer_body(husk, skeleton)
	if(husk)
		return FALSE
	if(istype(tail_style, /datum/sprite_accessory/tail/taur) && tail_style.clip_mask)
		return FALSE
	for(var/obj/item/organ/external/part in organs)
		if(part.is_stump() || limb_hidden(part))
			continue
		if(!part.can_layer(skeleton))
			return FALSE
	return TRUE

/// A limb the client can colour: not see-through (a greyscale and a fade per limb), not dead (ColorTone), not drawn blank by a marking, and tinted at most once.
/obj/item/organ/external/proc/can_layer(skeleton)
	return !transparent && !(status & ORGAN_DEAD) && !is_hidden_by_markings() && layered_tint_count(skeleton) < 2

/// The body as one blank image carrying a tinted overlay per limb part. A cache builder (body_look()): every input is in its key.
/mob/living/carbon/human/proc/build_layered_body_look(template, hulk, skeleton)
	var/list/parts = list()
	var/list/under = list()
	for(var/obj/item/organ/external/part in organs)
		if(part.is_stump() || limb_hidden(part))
			continue
		if(part.icon_position & UNDER)
			under += part.layered_parts(skeleton)
		else
			parts += part.layered_parts(skeleton)
	var/image/body = image(icon = template, icon_state = "blank", layer = BODY_LAYER + BODYPARTS_LAYER)
	if(hulk && !skeleton)
		body.appearance_flags |= KEEP_TOGETHER // a hulk's green is one pass over the whole body, eyes and markings too
		body.color = rgb(48, 224, 40)
	look_composed_image(body, under + parts)
	return list(icon(template, "blank"), body)

/// This limb's images, in drawing order: its sprite, its markings, then the body hair and nail polish.
/obj/item/organ/external/proc/layered_parts(skeleton)
	. = list(layered_base(skeleton))
	. += layered_marking_parts()
	. += layered_surface_parts()

/// Whether the limb's own sprite (a prosthetic's) stands in for the species' one.
/obj/item/organ/external/proc/layered_forced_icon()
	return force_icon && !(skip_robo_icon || (digi_prosthetic && layered_digitigrade()))

/// How many times get_icon() colours the limb's sprite: once for a species or robotic sprite, again for a prosthetic model. (Twice would need the two tints folded into one.)
/obj/item/organ/external/proc/layered_tint_count(skeleton)
	. = 0
	if(!layered_forced_icon() && !skeleton)
		.++
	if(model && !(skip_robo_icon || (digi_prosthetic && layered_digitigrade())))
		.++

/// The limb's sprite in its colour (apply_colouration()).
/obj/item/organ/external/proc/layered_base(skeleton)
	var/digitigrade = layered_digitigrade()
	var/skip_forced_icon = skip_robo_icon || (digi_prosthetic && digitigrade)
	var/base_file
	var/state
	if(layered_forced_icon())
		base_file = force_icon
		state = "[icon_name][gendered_icon ? "_[owner.gender == FEMALE ? "f" : "m"]" : ""]"
	else
		var/gender = gendered_icon ? (data.body_gender ? "f" : "m") : null
		state = "[icon_name][gender ? "_[gender]" : ""]"
		if(skeleton)
			base_file = 'icons/mob/human_races/r_skeleton.dmi'
		else if(is_robotic() && !skip_forced_icon)
			base_file = 'icons/mob/human_races/robotic.dmi'
		else
			base_file = digitigrade ? data.get_species_icodigi() : data.get_species_icobase(owner, (status & ORGAN_MUTATED))
	var/image/base = image(icon = base_file, icon_state = state)
	if(layered_tint_count(skeleton) && s_col && s_col.len >= 3)
		// Plain robotic art is tinted, never added to: an added skin colour washes metal out to white.
		var/datum/robolimb/franchise = is_robotic() ? GLOB.all_robolimbs[model] : null
		base.color = human_tint(rgb(s_col[1], s_col[2], s_col[3]), (data.get_species_color_mult() || (is_robotic() && !franchise?.skin_color)) ? ICON_MULTIPLY : ICON_ADD)
	return base

/obj/item/organ/external/proc/layered_digitigrade()
	return (istype(src, /obj/item/organ/external/leg) || istype(src, /obj/item/organ/external/foot)) && owner.looks.digitigrade

/// The limb's markings, tinted (a prosthetic's own sprite carries its own, unless `always`: the head draws its markings after the eyes and lips whatever it is made of).
/obj/item/organ/external/proc/layered_marking_parts(always = FALSE)
	. = list()
	if(!always && layered_forced_icon() && !(model && owner))
		return
	var/digitigrade = layered_digitigrade()
	var/check_digi = istype(src, /obj/item/organ/external/leg) || istype(src, /obj/item/organ/external/foot)
	for(var/M in markings)
		if(!markings[M]["on"])
			continue
		var/datum/sprite_accessory/marking/mark_style = markings[M]["datum"]
		if(check_digi && !(mark_style.digitigrade_acceptance & (digitigrade ? MARKING_DIGITIGRADE_ONLY : MARKING_NONDIGI_ONLY)))
			continue
		. += human_part(digitigrade ? mark_style.digitigrade_icon : mark_style.icon, "[mark_style.icon_state]-[organ_tag]", markings[M]["color"], mark_style.color_blend_mode)

/obj/item/organ/external/proc/layered_surface_parts()
	. = list()
	if(body_hair && islist(h_col) && h_col.len >= 3)
		. += human_part(data.get_species_icobase(owner), "[icon_name]_[body_hair]", rgb(h_col[1], h_col[2], h_col[3]))
	if(nail_polish && !layered_forced_icon())
		. += human_part(nail_polish.icon, nail_polish.icon_state, nail_polish.color)

/// The head: its sprite, then eyes, lips and markings (the order get_icon() blends them in), with the eyes above the markings for a head that says so.
/obj/item/organ/external/head/layered_parts(skeleton)
	. = list(layered_base(skeleton))
	. += layered_surface_parts()
	var/image/eyes_part = layered_eyes_part()
	if(eyes_part && !eyes_over_markings)
		. += eyes_part
	if(owner.looks.lip_style && (data.get_species_appearance_flags() & HAS_LIPS))
		. += human_part('icons/mob/human_face.dmi', "lips_[owner.looks.lip_style]_s")
	. += layered_marking_parts(TRUE)
	if(eyes_part && eyes_over_markings)
		. += eyes_part

/// The eyes the head draws on itself, tinted as get_icon() blends them, or null.
/obj/item/organ/external/head/proc/layered_eyes_part()
	if(!owner.species || !eye_icon)
		return null
	var/should_have_eyes = owner.should_have_organ(O_EYES)
	var/has_eye_sprites = owner.species.appearance_flags & HAS_EYE_COLOR
	if(!should_have_eyes && !has_eye_sprites)
		return null
	var/tint = null
	if(!findtext(eye_icon, regex("-colored")))
		if(should_have_eyes)
			var/obj/item/organ/internal/eyes/eyes = owner.organ_in(O_EYES)
			if(!eyes)
				tint = rgb(128,0,0)
			else if(has_eye_sprites)
				tint = eyes.eye_rgb()
		else
			tint = owner.looks.eyes_color
	return human_part(eye_icon_location, eye_icon, tint, ICON_ADD)

ADMIN_VERB(spawn_look_test_crowd, R_DEBUG|R_SPAWN, "Spawn Look Test Crowd", "Put 20 humans around you, to check client frame cost of human looks.", ADMIN_CATEGORY_DEBUG_GAME)
	var/turf/centre = get_turf(user.mob)
	if(!centre)
		return
	var/spawned = 0
	for(var/turf/T in orange(3, centre))
		if(spawned >= 20)
			break
		if(T.density)
			continue
		new /mob/living/carbon/human(T)
		spawned++
	log_world("human look: spawned a test crowd of [spawned]")
	message_admins("[key_name_admin(user)] spawned a look test crowd of [spawned].")
