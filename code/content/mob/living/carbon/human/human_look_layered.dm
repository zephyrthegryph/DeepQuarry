// The plain body as tinted overlays the client layers (doc/rewrite/proposals/client_side_compositing.md). A body this path cannot show yet stays composited by human_look.dm.

/// Whether this body can be layered today: none of the looks the proposal classes as needing a filter, a matrix pass or pixels.
/mob/living/carbon/human/proc/can_layer_body(husk, hulk, skeleton)
	if(husk || hulk || skeleton)
		return FALSE
	if(istype(tail_style, /datum/sprite_accessory/tail/taur) && tail_style.clip_mask)
		return FALSE
	for(var/obj/item/organ/external/part in organs)
		if(part.is_stump() || limb_hidden(part))
			continue
		if(!part.can_layer())
			return FALSE
	return TRUE

/obj/item/organ/external/proc/can_layer()
	return !transparent && !(status & ORGAN_DEAD) && !is_robotic() && !force_icon && !model && !is_hidden_by_markings()

/// The body as one blank image carrying a tinted overlay per limb part. A cache builder (body_look()): every input is in its key.
/mob/living/carbon/human/proc/build_layered_body_look(template)
	var/list/parts = list()
	var/list/under = list()
	for(var/obj/item/organ/external/part in organs)
		if(part.is_stump() || limb_hidden(part))
			continue
		if(part.icon_position & UNDER)
			under += part.layered_parts()
		else
			parts += part.layered_parts()
	var/image/body = image(icon = template, icon_state = "blank", layer = BODY_LAYER + BODYPARTS_LAYER)
	look_composed_image(body, under + parts)
	return list(icon(template, "blank"), body)

/// This limb's images, in drawing order. The head draws its own eyes and lips in get_icon(), so it stays one generated icon here.
/obj/item/organ/external/proc/layered_parts()
	if(istype(src, /obj/item/organ/external/head))
		return list(image(new /icon(get_icon(FALSE, TRUE, item_layers = FALSE))))
	var/check_digi = istype(src, /obj/item/organ/external/leg) || istype(src, /obj/item/organ/external/foot)
	var/digitigrade = check_digi && owner.looks.digitigrade
	var/gender = gendered_icon ? (data.body_gender ? "f" : "m") : null
	var/base_file = digitigrade ? data.get_species_icodigi() : data.get_species_icobase(owner, (status & ORGAN_MUTATED))
	var/image/base = image(icon = base_file, icon_state = "[icon_name][gender ? "_[gender]" : ""]")
	if(s_col && s_col.len >= 3)
		if(data.get_species_color_mult())
			base.color = rgb(s_col[1], s_col[2], s_col[3])
		else
			base.color = list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, s_col[1] / 255, s_col[2] / 255, s_col[3] / 255, 0)
	. = list(base)
	for(var/M in markings)
		if(!markings[M]["on"])
			continue
		var/datum/sprite_accessory/marking/mark_style = markings[M]["datum"]
		if(check_digi && !(mark_style.digitigrade_acceptance & (digitigrade ? MARKING_DIGITIGRADE_ONLY : MARKING_NONDIGI_ONLY)))
			continue
		var/image/mark = image(icon = digitigrade ? mark_style.digitigrade_icon : mark_style.icon, icon_state = "[mark_style.icon_state]-[organ_tag]")
		mark.color = markings[M]["color"]
		. += mark
	if(body_hair && islist(h_col) && h_col.len >= 3)
		var/image/hair = image(icon = data.get_species_icobase(owner), icon_state = "[icon_name]_[body_hair]")
		hair.color = rgb(h_col[1], h_col[2], h_col[3])
		. += hair
	if(nail_polish)
		var/image/polish = image(icon = nail_polish.icon, icon_state = nail_polish.icon_state)
		polish.color = nail_polish.color
		. += polish

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
