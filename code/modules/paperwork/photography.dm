/*	Photography!
 *	Contains:
 *		Camera
 *		Camera Film
 *		Photos
 *		Photo Albums
 */

/*******
* film *
*******/
/obj/item/camera_film
	name = "film cartridge"
	icon = 'icons/obj/items.dmi'
	desc = "A camera film cartridge. Insert it into a camera to reload it."
	icon_state = "film"
	item_state = "camera"
	w_class = ITEMSIZE_TINY


/********
* photo *
********/
GLOBAL_VAR_INIT(photo_count, 0)

/obj/item/photo
	name = "photo"
	icon = 'icons/obj/items.dmi'
	icon_state = "photo"
	item_state = "paper"
	w_class = ITEMSIZE_SMALL
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	var/id
	var/icon/img	//Big photo image
	var/scribble	//Scribble on the back.
	var/icon/tiny

	var/photo_size = 3
	resistance_flags = FLAMMABLE

TRACKED(/obj/item/photo, tiny)

/obj/item/photo/Initialize(mapload)
	. = ..()
	id = GLOB.photo_count++

/// Old attack_self.
/obj/item/photo/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	user.examinate(src)
	return OP_OK

/// Old attackby.
/obj/item/photo/proc/interaction_item(datum/act/op/A)
	return paperwork_caption_stage(A.actor, A.held, null)

/// The Rename photo menu entry.
/obj/item/photo/proc/photo_rename_op(datum/act/op/A)
	photo_verb_rename(A.actor)
	return OP_OK

/obj/item/photo/proc/paperwork_caption_stage(mob/user, obj/item/P, datum/interaction/interaction, paperwork_answer, paperwork_answer_ready = FALSE)
	if(istype(P, /obj/item/pen))
		if(!paperwork_answer_ready)
			open_request(src, /datum/prompt/text/paperwork_review, PROC_REF(paperwork_caption_answered), answerer = user, paperwork_operator = user, paperwork_held = P, paperwork_interaction = interaction, question = "What would you like to write on the back?", title = "Photo Writing", max_len = 128)
			return OP_OK
		var/txt = paperwork_answer
		if(isnull(txt))
			return OP_OK
		if(loc == user && user.stat == 0)
			scribble = txt
	return OP_DECLINE

/obj/item/photo/examine(mob/user)
	//This is one time we're not going to call parent, because photos are 'secret' unless you're close enough.
	SHOULD_CALL_PARENT(FALSE)
	if(in_range(user, src))
		show(user)
		return list(desc)
	else
		return list(span_notice("It is too far away to examine."))

// TGUI migration. show() opens Photo.tsx; the image is
// embedded via icon2html (inline base64 data URL) instead of the legacy
// browse_rsc + img-tag dance.
/obj/item/photo/proc/show(mob/user as mob)
	tgui_interact(user)

CAPABILITIES(/obj/item/photo)
	op("photo_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("photo_item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("photo_rename", menu(), label("Rename photo"), needs(carried()), then(PROC_REF(photo_rename_op)))
	interface("Photo")
	without("ui_open")
	ui_shape(title = schema_text(), size = num(), scribble = bool(), image_html = schema_text())

/obj/item/photo/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["title"] = name
	data["size"] = photo_size
	var/list/merged_1 = ui_data_obj_item_photo(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/photo's window data.
/obj/item/photo/proc/ui_data_obj_item_photo(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["scribble"] = scribble || ""
	if(img)
		var/icon/scaled = icon(img)
		scaled.Scale(64 * photo_size, 64 * photo_size)
		data["image_html"] = icon2html(scaled, user, sourceonly = FALSE)
	else
		data["image_html"] = ""
	return data

/// Old Rename photo verb.
/obj/item/photo/proc/photo_verb_rename(mob/user, obj/item/held, datum/interaction/interaction)
	return paperwork_photo_label_stage(user, held, interaction)

/obj/item/photo/proc/paperwork_photo_label_stage(mob/user, obj/item/held, datum/interaction/interaction, paperwork_answer, paperwork_answer_ready = FALSE)
	if(!paperwork_answer_ready)
		open_request(src, /datum/prompt/text/paperwork_review, PROC_REF(paperwork_photo_label_answered), answerer = user, paperwork_operator = user, paperwork_held = held, paperwork_interaction = interaction, question = "What would you like to label the photo?", title = "Photo Labelling", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return
	var/_answer_k97 = paperwork_answer
	if(isnull(_answer_k97))
		return
	var/n_name = sanitizeSafe(_answer_k97, MAX_NAME_LEN)
	//loc.loc check is for making possible renaming photos in clipboards
	if(( (loc == user || (loc.loc && loc.loc == user)) && user.stat == 0))
		name = "[(n_name ? text("[n_name]") : "photo")]"
	add_fingerprint(user)
	return


/**************
* photo album *
**************/
/obj/item/storage/photo_album
	name = "Photo album"
	icon = 'icons/obj/items.dmi'
	icon_state = "album"
	item_state = "briefcase"


CAPABILITIES(/obj/item/storage/photo_album)
	configure(storage(accepts = list(/obj/item/photo)))
	drag_onto(PROC_REF(mousedrop_input))

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/storage/photo_album/mousedrop_input(datum/act/input/A)
	if(!handle_album_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/storage/photo_album/proc/handle_album_drop(mob/user, obj/over_object)

	if(ishuman(user))
		var/mob/living/carbon/human/M = user
		if(!( istype(over_object, /atom/movable/screen) ))
			return FALSE
		play_sfx(src, SFX_RUSTLE, 2)
		if((!( M.restrained() ) && !( M.stat ) && M.get_equipped_item(SLOT_ID_BACK) == src))
			switch(over_object.name)
				if("r_hand")
					M.unEquip(src)
					M.put_in_r_hand(src)
				if("l_hand")
					M.unEquip(src)
					M.put_in_l_hand(src)
			add_fingerprint(user)
			return TRUE
		if(over_object == user && in_range(src, user) || user.contents.Find(src))
			if(user.s_active)
				user.s_active.close(user)
			show_to(user)
			return TRUE
	return TRUE

/*********
* camera *
*********/
/obj/item/camera
	name = "camera"
	icon = 'icons/obj/items.dmi'
	desc = "A polaroid camera. 10 photos left."
	icon_state = "camera"
	item_state = "camera"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	MATERIAL_BULK(MAT_STEEL, 2000)
	var/pictures_max = 10
	var/pictures_left = 10
	var/on = 1
	var/icon_on = "camera"
	var/icon_off = "camera_off"
	var/size = 3
	var/list/picture_planes

/// Old Set Photo Focus verb.
/obj/item/camera/proc/camera_verb_focus(mob/user, obj/item/held, datum/interaction/interaction)
	return paperwork_focus_stage(user, held, interaction)

/obj/item/camera/proc/paperwork_focus_stage(mob/user, obj/item/held, datum/interaction/interaction, paperwork_answer, paperwork_answer_ready = FALSE)
	if(!paperwork_answer_ready)
		open_request(src, /datum/prompt/choice/paperwork_review, PROC_REF(paperwork_focus_answered), answerer = user, paperwork_operator = user, paperwork_held = held, paperwork_interaction = interaction, question = "Photo Size", title = "Pick a size of resulting photo.", choices = list(1,3,5,7))
		return
	var/nsize = paperwork_answer
	if(isnull(nsize))
		return
	if(nsize)
		size = nsize
		to_chat(user, span_notice("Camera will now take [size]x[size] photos."))

/obj/item/camera/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

CAPABILITIES(/obj/item/camera)
	op("camera_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("camera_item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("camera_focus", menu(), label("Set Photo Focus"), needs(carried()), then(PROC_REF(camera_focus_op)))

/// The Set Photo Focus menu entry.
/obj/item/camera/proc/camera_focus_op(datum/act/op/A)
	camera_verb_focus(A.actor)
	return OP_OK

/// Old attack_self.
/obj/item/camera/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	on = !on
	if(on)
		src.icon_state = icon_on
	else
		src.icon_state = icon_off
	to_chat(user, "You switch the camera [on ? "on" : "off"].")
	return OP_OK

/// Old attackby.
/obj/item/camera/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/camera_film))
		if(pictures_left)
			to_chat(user, span_notice("[src] still has some film in it!"))
			return OP_PASS
		var/film_name = "[I]"
		if(!consume(I, user))
			return OP_PASS
		to_chat(user, span_notice("You insert [film_name] into [src]."))
		pictures_left = pictures_max
		return OP_PASS
	return OP_DECLINE


/obj/item/camera/proc/get_icon(list/turfs, turf/center)

	//Bigger icon base to capture those icons that were shifted to the next tile
	//i.e. pretty much all wall-mounted machinery
	var/icon/res = icon('icons/effects/96x96.dmi', "")
	res.Scale(size*32, size*32)
	// Initialize the photograph to black.
	res.Blend("#000", ICON_OVERLAY)

	var/atoms[] = list()
	for(var/turf/the_turf in turfs)
		// Add outselves to the list of stuff to draw
		atoms.Add(the_turf);
		// As well as anything that isn't invisible.
		for(var/atom/A in the_turf)
			if(A.invisibility) continue
			if(A.plane > 0 && !(A.plane in picture_planes)) continue
			atoms.Add(A)

	// Sort the atoms into their layers
	var/list/sorted = sort_atoms_by_layer(atoms)
	var/center_offset = (size-1)/2 * 32 + 1
	for(var/i = 1; i <= sorted.len; i++)
		var/atom/A = sorted[i]
		if(A)
			var/icon/img = getFlatIcon(A, no_anim = TRUE) // picture_planes = picture_planes)//build_composite_icon(A) //

			// If what we got back is actually a picture, draw it.
			if(istype(img, /icon))
				// Check if we're looking at a mob that's lying down
				if(isliving(A) && A:lying)
					// If they are, apply that effect to their picture.
					img.BecomeLying()
				// Calculate where we are relative to the center of the photo
				var/xoff = (A.x - center.x) * 32 + center_offset
				var/yoff = (A.y - center.y) * 32 + center_offset
				if (istype(A,/atom/movable))
					xoff+=A:pixel_x
					yoff+=A:pixel_y
				res.Blend(img, blendMode2iconMode(A.blend_mode),  A.pixel_x + xoff, A.pixel_y + yoff)

	// Lastly, render any contained effects on top.
	for(var/turf/the_turf in turfs)
		// Calculate where we are relative to the center of the photo
		var/xoff = (the_turf.x - center.x) * 32 + center_offset
		var/yoff = (the_turf.y - center.y) * 32 + center_offset
		res.Blend(getFlatIcon(the_turf.loc, no_anim = TRUE), blendMode2iconMode(the_turf.blend_mode),xoff,yoff)
	return res


/obj/item/camera/proc/get_mobs(turf/the_turf as turf)
	var/mob_detail
	for(var/mob/living/carbon/A in turf_contents_of_type(the_turf, /mob/living/carbon))
		if(A.invisibility) continue
		var/holding = null
		if(A.get_equipped_item(SLOT_ID_HAND_L) || A.get_equipped_item(SLOT_ID_HAND_R))
			if(A.get_equipped_item(SLOT_ID_HAND_L)) holding = "They are holding \a [A.get_equipped_item(SLOT_ID_HAND_L)]"
			if(A.get_equipped_item(SLOT_ID_HAND_R))
				if(holding)
					holding += " and \a [A.get_equipped_item(SLOT_ID_HAND_R)]"
				else
					holding = "They are holding \a [A.get_equipped_item(SLOT_ID_HAND_R)]"

		if(!mob_detail)
			mob_detail = "You can see [A] on the photo[A.vitality() < 0.75 ? " - [A] looks hurt":""].[holding ? " [holding]":"."]. "
		else
			mob_detail += "You can also see [A] on the photo[A.vitality() < 0.75 ? " - [A] looks hurt":""].[holding ? " [holding]":"."]."

	return mob_detail

/obj/item/camera/afterattack(atom/target as mob|obj|turf|area, mob/user as mob, flag)
	if(!on || !pictures_left || ismob(target.loc)) return
	captureimage(target, user, flag)

	play_sfx(src, SFX_ITEMS_POLAROID)

	pictures_left--
	desc = "A polaroid camera. It has [pictures_left] photos left."
	to_chat(user, span_notice("[pictures_left] photos left."))
	icon_state = icon_off
	on = 0
	after(src, 6.4 SECONDS, PROC_REF(recharged))

/obj/item/camera/proc/can_capture_turf(turf/T, mob/user)
	var/viewer = user
	if(user.client)		//To make shooting through security cameras possible
		viewer = user.client.eye
	var/can_see = (T in view(viewer))

	return can_see

/obj/item/camera/proc/captureimage(atom/target, mob/user, flag)
	var/x_c = target.x - (size-1)/2
	var/y_c = target.y + (size-1)/2
	var/z_c	= target.z
	var/list/turfs = list()
	var/mobs = ""
	for(var/i = 1 to size)
		for(var/j = 1 to size)
			var/turf/T = locate(x_c, y_c, z_c)
			if(can_capture_turf(T, user))
				turfs.Add(T)
				mobs += get_mobs(T)
			x_c++
		y_c--
		x_c = x_c - size

	var/obj/item/photo/p = createpicture(target, user, turfs, mobs, flag)

	printpicture(user, p)

/obj/item/camera/proc/createpicture(atom/target, mob/user, list/turfs, mobs, flag)
	var/icon/photoimage = get_icon(turfs, target)

	var/icon/small_img = icon(photoimage)
	var/icon/tiny_img = icon(photoimage)
	var/icon/ic = icon('icons/obj/items.dmi',"photo")
	var/icon/pc = icon('icons/obj/bureaucracy.dmi', "photo")
	small_img.Scale(8, 8)
	tiny_img.Scale(4, 4)
	ic.Blend(small_img,ICON_OVERLAY, 10, 13)
	pc.Blend(tiny_img,ICON_OVERLAY, 12, 19)

	var/obj/item/photo/p = new()
	p.name = "photo"
	p.icon = ic
	p.set_tiny(pc)
	p.img = photoimage
	p.desc = mobs
	p.pixel_x = rand(-10, 10)
	p.pixel_y = rand(-10, 10)
	p.photo_size = size
	return p

/obj/item/camera/proc/printpicture(mob/user, obj/item/photo/p)
	p.forceMove(user.loc)
	if(!user.get_inactive_hand())
		user.put_in_inactive_hand(p)

/obj/item/photo/proc/copy(copy_id = 0)
	var/obj/item/photo/p = new/obj/item/photo()

	p.name = name
	p.icon = icon(icon, icon_state)
	p.set_tiny(icon(tiny))
	p.img = icon(img)
	p.desc = desc
	p.pixel_x = pixel_x
	p.pixel_y = pixel_y
	p.photo_size = photo_size
	p.scribble = scribble

	if(copy_id)
		p.id = id

	return p

/obj/item/camera/proc/recharged()
	icon_state = icon_on
	on = 1


/obj/item/photo/proc/paperwork_caption_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_caption_apply(A)
	SStgui.update_uis(src)

/obj/item/photo/proc/paperwork_caption_apply(datum/act/request/A)
	var/datum/prompt/text/paperwork_review/ask = A.answer
	return paperwork_caption_stage(ask.paperwork_operator, ask.paperwork_held, ask.paperwork_interaction, ask.value, TRUE)

/obj/item/photo/proc/paperwork_photo_label_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_photo_label_apply(A)
	SStgui.update_uis(src)

/obj/item/photo/proc/paperwork_photo_label_apply(datum/act/request/A)
	var/datum/prompt/text/paperwork_review/ask = A.answer
	return paperwork_photo_label_stage(ask.paperwork_operator, ask.paperwork_held, ask.paperwork_interaction, ask.value, TRUE)

/obj/item/camera/proc/paperwork_focus_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_focus_apply(A)
	SStgui.update_uis(src)

/obj/item/camera/proc/paperwork_focus_apply(datum/act/request/A)
	var/datum/prompt/choice/paperwork_review/ask = A.answer
	return paperwork_focus_stage(ask.paperwork_operator, ask.paperwork_held, ask.paperwork_interaction, ask.value, TRUE)
