// The body as tinted overlays the client layers (doc/rewrite/proposals/client_side_compositing.md): the one way a human's body is drawn.

// ---- tints and parts ----

/// The `color` that does to a layer what `icon.Blend(colour, mode)` does to an icon: the colour itself for a multiply, a matrix whose constant row is the colour for an add.
/proc/human_tint(colour, mode = ICON_MULTIPLY)
	if(isnull(colour))
		return null
	if(mode != ICON_ADD)
		return colour
	var/list/channels = rgb2num(colour)
	return list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, channels[1] / 255, channels[2] / 255, channels[3] / 255, 0)

// ---- colour matrices ----
// A colour matrix is the 20 numbers a client colour takes: a row of four per input channel (red, green, blue, alpha) and then the constant row.

GLOBAL_LIST_INIT(human_identity_matrix, list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, 0,0,0,0))

/proc/human_matrix_identity()
	return GLOB.human_identity_matrix

/// What `first` then `second` do to a colour, as one matrix.
/proc/human_matrix_then(list/first, list/second)
	READS_FROM()
	var/list/result = new /list(20)
	for(var/row in 0 to 3)
		for(var/column in 1 to 4)
			var/sum = 0
			for(var/k in 1 to 4)
				sum += first[row * 4 + k] * second[(k - 1) * 4 + column]
			result[row * 4 + column] = sum
	for(var/column in 1 to 4)
		var/sum = second[16 + column]
		for(var/k in 1 to 4)
			sum += first[16 + k] * second[(k - 1) * 4 + column]
		result[16 + column] = sum
	return result

/// The matrix of `icon.Blend(colour, mode)` for a multiply or an add.
/proc/human_tint_matrix(colour, mode = ICON_MULTIPLY)
	READS_FROM()
	var/list/channels = rgb2num(colour)
	if(mode == ICON_ADD)
		return list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, channels[1] / 255, channels[2] / 255, channels[3] / 255, 0)
	return list(channels[1] / 255,0,0,0, 0,channels[2] / 255,0,0, 0,0,channels[3] / 255,0, 0,0,0,1, 0,0,0,0)

/// A grey picture toned to `colour` (icon.ColorTone() then SetIntensity(intensity)): the luminance of each pixel, a mid grey showing the tone itself.
/proc/human_tone_matrix(colour, intensity = 1)
	READS_FROM()
	var/list/channels = rgb2num(colour)
	var/static/list/weights = list(0.3, 0.59, 0.11)
	var/list/matrix = list()
	for(var/weight in weights)
		matrix += list(weight * channels[1] / 127.5 * intensity, weight * channels[2] / 127.5 * intensity, weight * channels[3] / 127.5 * intensity, 0)
	matrix += list(0,0,0,1, 0,0,0,0)
	return matrix

/// The see-through grey of a transparent limb (apply_colouration()).
GLOBAL_LIST_INIT(human_glass_matrix_values, list(0.302,0.302,0.302,0, 0.588,0.588,0.588,0, 0.11,0.11,0.11,0, 0,0,0,1, 0,0,0,0))

/proc/human_glass_matrix()
	return GLOB.human_glass_matrix_values

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
	// An explicit blank state: a group with no icon of its own would draw the icon of whatever it is flattened over (a composed body is the mob's own icon).
	var/image/group = image(icon = 'icons/mob/human.dmi', icon_state = "blank", layer = layer)
	if(!isnull(flags))
		group.appearance_flags = flags
	if(together || alpha < 255)
		group.appearance_flags |= KEEP_TOGETHER
	group.alpha = alpha
	group.pixel_x = pixel_x
	group.pixel_y = pixel_y
	return look_composed_image(group, parts)

/// `parts` drawn only facing `dirs`: each part's sprite reduced to those facings (a copy of the part, the same tint), as a tail is split by facing.
/// An overlay made from it shows only while its holder faces one of `dirs`, so a body layered by facing needs no redraw when it turns.
/// `cut`: the taur's leg cutter takes its share of each sprite too (the legs a taur's lower half stands in for).
/mob/living/carbon/human/proc/human_dirs_parts(list/parts, list/dirs, cut = FALSE)
	READS_FROM()
	. = list()
	var/cutter = cut && body_taur_cuts()
	for(var/image/part as anything in parts)
		var/image/kept = image(part)
		kept.icon = human_look_icon("limb_dirs|[part.icon]|[part.icon_state]|[jointext(dirs, ",")]|[cutter ? tail_style.type : ""]", "build_limb_dirs", part.icon, part.icon_state, dirs, cutter)
		kept.icon_state = ""
		. += kept

/// One state of `file` with only its `dirs` facings drawn. A cache builder (human_dirs_parts()).
/mob/living/carbon/human/proc/build_limb_dirs(file, state, list/dirs, cut)
	human_icon_op(3 + length(dirs))
	var/icon/kept = icon_keep_dirs(icon(file, state), dirs)
	var/list/cutter = cut ? body_taur_cutter() : null
	if(cutter)
		kept.Blend(cutter[1], ICON_AND, x = cutter[2], y = cutter[3])
	return kept

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

/// The body as one blank image carrying a tinted overlay per limb part. A cache builder (body_look()): every input is in its key.
/// `husk`: the body is toned grey-brown with the species' husk marks inset; `whole_transparent`: every limb is see-through, so the body is faded as one picture.
/mob/living/carbon/human/proc/build_layered_body_look(template, hulk, skeleton, husk = FALSE, whole_transparent = FALSE)
	var/list/parts = list()
	var/list/under = list()
	var/cut = body_taur_cuts()
	for(var/obj/item/organ/external/part in organs)
		if(part.is_stump() || limb_hidden(part))
			continue
		var/list/layered = part.layered_shown_parts(skeleton, whole_transparent)
		// A composed body underlays each part in turn, so a later one lies under the earlier ones: the layered list is built the same way round.
		if(part.icon_position & (LEFT | RIGHT))
			// The far limb goes under the body: the left one facing east, the right one facing west. The near copy shows in the other three facings.
			var/far_dir = (part.icon_position & LEFT) ? EAST : WEST
			var/cut_part = cut && (part.organ_tag in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
			under = human_dirs_parts(layered, list(far_dir), cut_part) + under
			parts += human_dirs_parts(layered, GLOB.cardinal - far_dir, cut_part)
		else if(part.icon_position & UNDER)
			under = layered + under
		else
			parts += layered
	var/image/body = image(icon = template, icon_state = "blank", layer = BODY_LAYER + BODYPARTS_LAYER)
	var/list/shown = under + parts
	if(husk && !skeleton)
		// The husk is one tone over the limbs, and the species' husk marks lie only where there is body (an inset layer, over the toned group).
		var/image/limbs = human_part_group(shown, together = TRUE)
		limbs.color = human_tone_matrix(rgb(96, 88, 80))
		shown = list(limbs)
		if(icon_exists(species.icobase, "overlay_husk"))
			var/image/marks = human_part(species.icobase, "overlay_husk")
			marks.blend_mode = BLEND_INSET_OVERLAY
			shown += marks
		body.appearance_flags |= KEEP_TOGETHER
	else if(hulk && !skeleton)
		body.appearance_flags |= KEEP_TOGETHER // a hulk's green is one pass over the whole body, eyes and markings too
		body.color = rgb(48, 224, 40)
	if(whole_transparent)
		body.appearance_flags |= KEEP_TOGETHER // a whole-slime body fades as one picture
		body.alpha = 180
	look_composed_image(body, shown)
	return list(icon(template, "blank"), body)

/// This limb's parts as the body shows them: faded as one picture when it is see-through on a body that is not see-through as a whole.
/obj/item/organ/external/proc/layered_shown_parts(skeleton, whole_transparent)
	var/list/shown = layered_parts(skeleton)
	var/alpha = layered_alpha(skeleton, whole_transparent)
	if(alpha < 255)
		return list(human_part_group(shown, alpha = alpha))
	return shown

/// How opaque the limb is: a see-through one (not the head) shows through at 180, as get_icon() fades it.
/obj/item/organ/external/proc/layered_alpha(skeleton, whole_transparent)
	if(!transparent || whole_transparent || istype(src, /obj/item/organ/external/head))
		return 255
	var/skip_forced_icon = skip_robo_icon || (digi_prosthetic && layered_digitigrade())
	if((!layered_forced_icon() && !skeleton) || (model && !skip_forced_icon))
		return 180
	return 255

/// This limb's images, in drawing order: its sprite, its markings, then the body hair and nail polish.
/obj/item/organ/external/proc/layered_parts(skeleton)
	. = list()
	var/image/base = layered_base(skeleton)
	if(base)
		. += base
	. += layered_marking_parts()
	. += layered_surface_parts()

/// Whether the limb's own sprite (a prosthetic's) stands in for the species' one.
/obj/item/organ/external/proc/layered_forced_icon()
	return force_icon && !(skip_robo_icon || (digi_prosthetic && layered_digitigrade()))

/// How many times get_icon() colours the limb's sprite: once for a species or robotic sprite, again for a prosthetic model.
/obj/item/organ/external/proc/layered_tint_count(skeleton)
	. = 0
	if(!layered_forced_icon() && !skeleton)
		.++
	if(model && !(skip_robo_icon || (digi_prosthetic && layered_digitigrade())))
		.++

/// The colour of the limb's sprite after every apply_colouration() pass: a plain tint as the colour itself; a see-through, dead or doubly tinted limb as one matrix. Null for none.
/obj/item/organ/external/proc/layered_base_color(skeleton)
	var/passes = layered_tint_count(skeleton)
	if(!passes)
		return null
	var/has_tint = s_col && s_col.len >= 3
	var/datum/robolimb/franchise = is_robotic() ? GLOB.all_robolimbs[model] : null
	var/mode = ICON_ADD
	if(has_tint)
		// Plain robotic art is tinted, never added to: an added skin colour washes metal out to white.
		mode = (data.get_species_color_mult() || (is_robotic() && !franchise?.skin_color)) ? ICON_MULTIPLY : ICON_ADD
	var/dead = !transparent && (status & ORGAN_DEAD)
	if(passes == 1 && !transparent && !dead)
		return has_tint ? human_tint(rgb(s_col[1], s_col[2], s_col[3]), mode) : null
	var/list/pass = human_matrix_identity()
	if(transparent)
		pass = human_glass_matrix()
	else if(dead)
		pass = human_tone_matrix(rgb(10, 50, 0), 0.7)
	if(has_tint)
		pass = human_matrix_then(pass, human_tint_matrix(rgb(s_col[1], s_col[2], s_col[3]), mode))
	var/list/chain = human_matrix_identity()
	for(var/i in 1 to passes)
		chain = human_matrix_then(chain, pass)
	return chain

/// The limb's sprite in its colour (apply_colouration()), or null for a limb a marking blanks out.
/obj/item/organ/external/proc/layered_base(skeleton)
	var/digitigrade = layered_digitigrade()
	var/skip_forced_icon = skip_robo_icon || (digi_prosthetic && digitigrade)
	var/base_file
	var/state
	if(layered_forced_icon())
		state = "[icon_name][gendered_icon ? "_[owner.gender == FEMALE ? "f" : "m"]" : ""]"
		base_file = forced_icon_file(state)
	else
		var/gender = gendered_icon ? (data.body_gender ? "f" : "m") : null
		state = "[icon_name][gender ? "_[gender]" : ""]"
		if(skeleton)
			base_file = 'icons/mob/human_races/r_skeleton.dmi'
		else if(is_robotic() && !skip_forced_icon)
			base_file = 'icons/mob/human_races/robotic.dmi'
		else if(is_hidden_by_markings())
			return null // a marking draws the limb in place of its sprite
		else
			base_file = digitigrade ? data.get_species_icodigi() : data.get_species_icobase(owner, (status & ORGAN_MUTATED))
	var/image/base = image(icon = base_file, icon_state = state)
	var/colour = layered_base_color(skeleton)
	if(!isnull(colour))
		base.color = colour
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
	. = list()
	var/image/base = layered_base(skeleton)
	if(base)
		. += base
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
