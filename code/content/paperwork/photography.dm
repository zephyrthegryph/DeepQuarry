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
	var/id
	var/icon/img	//Big photo image
	var/scribble	//Scribble on the back.
	var/icon/tiny

	var/photo_size = 3
	resistance_flags = FLAMMABLE
	/// The drawing of this photo's picture while its atoms' pictures are being drawn (photo_render); null once it is filled.
	var/datum/photo_render/rendering


/obj/item/photo/proc/assign_photo_id(datum/act/timer/A)
	id = GLOB.photo_count++

/// Old attack_self.
/obj/item/photo/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	user.examinate(src)
	return OP_OK

/// Old attackby.
/obj/item/photo/proc/interaction_item(datum/act/op/A)
	return paperwork_caption_stage(A.actor, A.held)

/// The Rename photo menu entry.
/obj/item/photo/proc/photo_rename_op(datum/act/op/A)
	photo_verb_rename(A.actor)
	return OP_OK

/obj/item/photo/proc/paperwork_caption_stage(mob/user, obj/item/P, paperwork_answer, paperwork_answer_ready = FALSE)
	if(istype(P, /obj/item/pen))
		if(!paperwork_answer_ready)
			open_request(src, /datum/prompt/text/paperwork_review, PROC_REF(paperwork_caption_answered), answerer = user, paperwork_operator = user, paperwork_held = P, question = "What would you like to write on the back?", title = "Photo Writing", max_len = 128)
			return OP_OK
		var/txt = paperwork_answer
		if(isnull(txt))
			return OP_OK
		if(loc == user && user.stat == CONSCIOUS)
			set_scribble(txt)
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
	ref_one(nameof(rendering)) // the original and every early copy name it (the portrait cache owns it until it finishes)
	configure(item_sounds(drop = SFX_ITEMS_DROP_PAPER, pickup = SFX_ITEMS_PICKUP_PAPER))
	after_init(0, then(PROC_REF(assign_photo_id)))
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
/obj/item/photo/proc/photo_verb_rename(mob/user, obj/item/held)
	return paperwork_photo_label_stage(user, held)

/obj/item/photo/proc/paperwork_photo_label_stage(mob/user, obj/item/held, paperwork_answer, paperwork_answer_ready = FALSE)
	if(!paperwork_answer_ready)
		open_request(src, /datum/prompt/text/paperwork_review, PROC_REF(paperwork_photo_label_answered), answerer = user, paperwork_operator = user, paperwork_held = held, question = "What would you like to label the photo?", title = "Photo Labelling", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return
	var/_answer_k97 = paperwork_answer
	if(isnull(_answer_k97))
		return
	var/n_name = sanitizeSafe(_answer_k97, MAX_NAME_LEN)
	//loc.loc check is for making possible renaming photos in clipboards
	if(( (loc == user || (loc.loc && loc.loc == user)) && user.stat == CONSCIOUS))
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
	MATERIAL_BULK(MAT_STEEL, 2000)
	var/pictures_max = 10
	var/pictures_left = 10
	var/on = 1
	var/icon_on = "camera"
	var/icon_off = "camera_off"
	var/size = 3
	var/list/picture_planes

/// Old Set Photo Focus verb.
/obj/item/camera/proc/camera_verb_focus(mob/user, obj/item/held)
	return paperwork_focus_stage(user, held)

/obj/item/camera/proc/paperwork_focus_stage(mob/user, obj/item/held, paperwork_answer, paperwork_answer_ready = FALSE)
	if(!paperwork_answer_ready)
		open_request(src, /datum/prompt/choice/paperwork_review, PROC_REF(paperwork_focus_answered), answerer = user, paperwork_operator = user, paperwork_held = held, question = "Photo Size", title = "Pick a size of resulting photo.", choices = list(1,3,5,7))
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
	configure(item_worn(slots = SLOT_BELT))
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
		set_icon_state(icon_on)
	else
		set_icon_state(icon_off)
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


/// One photo being drawn: every atom's picture from the shared portrait cache (its look and place read when the shot was taken), composited
/// onto the black frame once the last lands (or after PHOTO_RENDER_TIMEOUT with what landed). The photo is filled in place.
#define PHOTO_RENDER_TIMEOUT (6 SECONDS)

/datum/photo_render
	/// The photo being drawn (it owns this drawing).
	var/obj/item/photo/photo
	/// Copies made of it before the picture was finished: filled with it too.
	var/list/copies
	var/size = 3
	/// list(list(picture or null, portrait key, lying, x, y, blend)) in layer order.
	var/list/entries
	/// The areas, drawn last: entries as above.
	var/list/tops
	var/pending = 0
	var/done = FALSE


CAPABILITIES(/datum/photo_render)
	ref_one(nameof(photo))
	ref_many(nameof(copies))

/// `copy` was copied from the photo before its picture was finished: it holds this drawing too and is filled when it is, even if the
/// original is gone by then.
/datum/photo_render/proc/add_copy(obj/item/photo/copy)
	rel_add(src, nameof(copies), copy)
	rel_set(copy, nameof(copy.rendering), src)

/datum/photo_render/proc/start(obj/item/camera/camera, obj/item/photo/photo, list/turfs, turf/center)
	rel_set(src, nameof(src.photo), photo)
	size = camera.size
	var/list/atoms = list()
	for(var/turf/the_turf in turfs)
		atoms.Add(the_turf)
		for(var/atom/A in the_turf)
			if(A.invisibility)
				continue
			if(A.plane > 0 && !(A.plane in camera.picture_planes))
				continue
			atoms.Add(A)
	var/list/sorted = sort_atoms_by_layer(atoms)
	var/center_offset = (size - 1) / 2 * 32 + 1
	entries = list()
	for(var/atom/A as anything in sorted)
		if(!A)
			continue
		var/xoff = (A.x - center.x) * 32 + center_offset
		var/yoff = (A.y - center.y) * 32 + center_offset
		if(ismovable(A))
			xoff += A.pixel_x
			yoff += A.pixel_y
		var/lying = isliving(A) && A:lying
		entries += list(ask(A, lying, A.pixel_x + xoff, A.pixel_y + yoff, blendMode2iconMode(A.blend_mode)))
	tops = list()
	for(var/turf/the_turf in turfs)
		var/xoff = (the_turf.x - center.x) * 32 + center_offset
		var/yoff = (the_turf.y - center.y) * 32 + center_offset
		tops += list(ask(the_turf.loc, FALSE, xoff, yoff, blendMode2iconMode(the_turf.blend_mode)))
	photo.fill_from(compose(FALSE)) // the black frame (what the photo shows while its pictures are drawn)
	if(!pending)
		finish()
		return
	rel_add(GLOB.portrait_cache, nameof(/datum/portrait_cache::photo_renders), src) // owned there until it finishes
	rel_set(photo, nameof(photo.rendering), src)
	after(src, PHOTO_RENDER_TIMEOUT, PROC_REF(finish), key = "photo_render_timeout")

/// The entry for `A` drawn at (x, y): list(picture or null while it is drawn, its portrait key, lying, x, y, blend).
/datum/photo_render/proc/ask(atom/A, lying, x, y, blend)
	var/datum/portrait/P = portrait_request(A, A.dir, src, PROC_REF(landed))
	var/key = P ? null : portrait_key_of(A, A.dir)
	if(!P && key)
		pending++
	return list(P?.picture, key, lying, x, y, blend)

/// An atom's picture landed.
/datum/photo_render/proc/landed(datum/portrait/P)
	for(var/list/entry as anything in entries + tops)
		if(P.answers(entry[2]) && !entry[1])
			entry[1] = P.picture
			pending--
	if(pending <= 0)
		finish()

/datum/photo_render/proc/finish()
	if(done)
		return
	done = TRUE
	cancel_after(src, "photo_render_timeout") // nothing holds a finished drawing
	var/icon/finished = compose(TRUE)
	for(var/obj/item/photo/holder as anything in list(src.photo) + copies)
		if(!holder || QDELETED(holder))
			continue
		holder.fill_from(holder == src.photo ? finished : icon(finished))
		if(holder.rendering == src)
			rel_clear(holder, nameof(holder.rendering))
	own_remove(GLOB.portrait_cache, nameof(/datum/portrait_cache::photo_renders), src) // done: the drawing goes

/// The photo's picture: the black frame, then (with `pictures`) every landed atom in layer order and the areas on top.
/datum/photo_render/proc/compose(pictures)
	var/icon/res = icon('icons/effects/96x96.dmi', "")
	res.Scale(size * 32, size * 32)
	res.Blend("#000", ICON_OVERLAY)
	if(!pictures)
		return res
	for(var/list/entry as anything in entries)
		if(!entry[1])
			continue
		var/icon/img = icon(entry[1]) // a copy: the cached picture is shared
		if(entry[3])
			img.BecomeLying()
		res.Blend(img, entry[6], entry[4], entry[5])
	for(var/list/top as anything in tops)
		if(top[1])
			res.Blend(top[1], top[6], top[4], top[5])
	return res

#undef PHOTO_RENDER_TIMEOUT

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
	set_icon_state(icon_off)
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
	var/obj/item/photo/p = new()
	p.name = "photo"
	p.desc = mobs
	p.set_pixel_x(rand(-10, 10))
	p.set_pixel_y(rand(-10, 10))
	p.set_photo_size(size)
	// The atoms' pictures come from the shared portrait cache (each one's look read now, drawn off the tick): the photo shows a black frame
	// until the last one lands, then the whole picture (photo_render).
	var/datum/photo_render/render = new
	render.start(src, p, turfs, target)
	return p

/// The photo's pictures from the finished picture `photoimage`: the big image, the item icon and the tiny thumbnail.
/obj/item/photo/proc/fill_from(icon/photoimage)
	var/icon/small_img = icon(photoimage)
	var/icon/tiny_img = icon(photoimage)
	var/icon/ic = icon('icons/obj/items.dmi',"photo")
	var/icon/pc = icon('icons/obj/bureaucracy.dmi', "photo")
	small_img.Scale(8, 8)
	tiny_img.Scale(4, 4)
	ic.Blend(small_img,ICON_OVERLAY, 10, 13)
	pc.Blend(tiny_img,ICON_OVERLAY, 12, 19)

	set_icon(ic)
	set_tiny(pc)
	set_img(photoimage)

/obj/item/camera/proc/printpicture(mob/user, obj/item/photo/p)
	p.forceMove(user.loc)
	if(!user.get_inactive_hand())
		user.put_in_inactive_hand(p)

/obj/item/photo/proc/copy(copy_id = 0)
	var/obj/item/photo/p = new/obj/item/photo()

	p.name = name
	p.set_icon(icon(icon, icon_state))
	p.set_tiny(icon(tiny))
	p.set_img(icon(img))
	p.desc = desc
	p.set_pixel_x(pixel_x)
	p.set_pixel_y(pixel_y)
	p.set_photo_size(photo_size)
	p.set_scribble(scribble)

	if(copy_id)
		p.id = id
	// Copied before its picture was finished: the copy is filled when it is (photo_render), not left with the black frame.
	rendering?.add_copy(p)

	return p

/obj/item/camera/proc/recharged()
	set_icon_state(icon_on)
	on = 1


/obj/item/photo/proc/paperwork_caption_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_caption_apply(A)
	SStgui.update_uis(src)

/obj/item/photo/proc/paperwork_caption_apply(datum/act/request/A)
	var/datum/prompt/text/paperwork_review/ask = A.answer
	return paperwork_caption_stage(ask.paperwork_operator, ask.paperwork_held, ask.value, TRUE)

/obj/item/photo/proc/paperwork_photo_label_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_photo_label_apply(A)
	SStgui.update_uis(src)

/obj/item/photo/proc/paperwork_photo_label_apply(datum/act/request/A)
	var/datum/prompt/text/paperwork_review/ask = A.answer
	return paperwork_photo_label_stage(ask.paperwork_operator, ask.paperwork_held, ask.value, TRUE)

/obj/item/camera/proc/paperwork_focus_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_focus_apply(A)
	SStgui.update_uis(src)

/obj/item/camera/proc/paperwork_focus_apply(datum/act/request/A)
	var/datum/prompt/choice/paperwork_review/ask = A.answer
	return paperwork_focus_stage(ask.paperwork_operator, ask.paperwork_held, ask.value, TRUE)
