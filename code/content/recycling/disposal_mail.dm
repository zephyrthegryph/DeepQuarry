/obj/structure/bigDelivery
	desc = "A big wrapped package."
	name = "large parcel"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "deliverycloset"
	var/tmp/obj/wrapped
	density = TRUE
	var/sortTag = null
	flags = NOBLUDGEON
	mouse_drag_pointer = MOUSE_ACTIVE_POINTER
	var/examtext = null
	var/nameset = 0

/// A fixed offset from low to high for this parcel and a purpose: the same every redraw, different between parcels, so a draw never rolls.
/proc/parcel_offset(atom/parcel, purpose, low, high)
	return low + (hex2num(copytext(md5("[ref(parcel)][purpose]"), 1, 5)) % (high - low + 1))


/// A destination tagger is used on a parcel: tells the user how it went; TRUE when the parcel's tag is to become the tagger's.
/proc/parcel_tag_accepted(obj/parcel, mob/user, current_tag, parcel_tag)
	if(!current_tag)
		to_chat(user, span_warning("You need to set a destination first!"))
		return FALSE
	if(parcel_tag == current_tag)
		to_chat(user, span_warning("The package is already labeled for [current_tag]."))
		return FALSE
	to_chat(user, span_notice("You have labeled the destination as [current_tag]."))
	play_sfx(parcel, SFX_MACHINES_TWOBEEP)
	return TRUE

/// A pen titles a parcel: the sanitized title (after the messages and the sound), or null when the text is not usable.
/proc/parcel_new_title(obj/parcel, mob/user, obj/item/pen, raw_title)
	var/str = sanitizeSafe(raw_title, MAX_NAME_LEN)
	if(!str || !length(str))
		to_chat(user, span_warning(" Invalid text."))
		return null
	act_message(user, parcel, MSG_SELF(span_notice("You title %T%: \"[MSG_LITERAL(str)]\"")), \
		MSG_OTHERS("%U% titles %T% with \a [pen], marking down: \"[MSG_LITERAL(str)]\""), \
		MSG_BLIND("You hear someone scribbling a note."))
	play_sfx(parcel, SFX_BUREAUCRACY_PEN)
	return str

/// A pen writes the note on a parcel: the note (after the messages and the sound), or null when it is empty.
/proc/parcel_new_note(obj/parcel, mob/user, obj/item/pen, str)
	if(!str || !length(str))
		to_chat(user, span_red("Invalid text."))
		return null
	act_message(user, parcel, MSG_SELF(span_notice("You label %T%: \"[MSG_LITERAL(str)]\"")), \
		MSG_OTHERS("%U% labels %T% with \a [pen], scribbling down: \"[MSG_LITERAL(str)]\""), \
		MSG_BLIND("You hear someone scribbling a note."))
	play_sfx(parcel, SFX_BUREAUCRACY_PEN)
	return str

CAPABILITIES(/obj/structure/bigDelivery)
	op("hand", hand(), label("Use"), ungated(), then(PROC_REF(interaction_hand)))
	op("tag", item(/obj/item/destTagger), then(PROC_REF(parcel_tag)))
	op("label", item(/obj/item/pen),
		asks(/datum/prompt/choice, fields = list("question" = "What would you like to alter?", "title" = "Select Alteration", "choices" = list("Title", "Description", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "alteration"),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "title", when = PROC_REF(label_asks_title)),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "timeout" = 0), step = "description", when = PROC_REF(label_asks_description)),
		then(PROC_REF(parcel_label)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("robot_unwrap", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Unwrap"), then(PROC_REF(big_delivery_robot_unwrap)))
	owns_one(nameof(wrapped), on_destroy = ON_DESTROY_SPILL)

/// Old attack_hand.
/obj/structure/bigDelivery/proc/interaction_hand(datum/act/op/A)
	unwrap()
	return OP_OK

/obj/structure/bigDelivery/proc/unwrap()
	if(loc?.release_refusal(src))
		return
	play_sfx(src, SFX_ITEMS_PACKAGE_UNWRAP)
	// Teardown spills the wrapped object onto the turf before on_destroy() runs (the relation is gone by then), so unseal it first.
	var/obj/structure/closet/sealed = wrapped()
	if(istype(sealed))
		set_welded(sealed, FALSE)
	// Teardown drops our wrapped object on the turf, so let it.
	consume(src)

/// Old attackby for any other item: handled, the item not used up.
/obj/structure/bigDelivery/proc/interaction_item(datum/act/op/A)
	return OP_PASS

/// A destination tagger sets the sort tag.
/obj/structure/bigDelivery/proc/parcel_tag(datum/act/op/A)
	var/obj/item/destTagger/O = A.held
	if(parcel_tag_accepted(src, A.actor, O.currTag, sortTag))
		set_sortTag(O.currTag)
	return OP_PASS

/// The pen's menu answered Title: the title is asked.
/obj/structure/bigDelivery/proc/label_asks_title(datum/act/op/A)
	return A.step_value("alteration") == "Title"

/// The pen's menu answered Description: the description is asked.
/obj/structure/bigDelivery/proc/label_asks_description(datum/act/op/A)
	return A.step_value("alteration") == "Description"

/// A pen titles the parcel or writes the note on it.
/obj/structure/bigDelivery/proc/parcel_label(datum/act/op/A)
	switch(A.step_value("alteration"))
		if("Title")
			var/title = parcel_new_title(src, A.actor, A.held, A.step_value("title"))
			if(title)
				name = "[name] ([title])"
				set_nameset(1)
		if("Description")
			var/note = parcel_new_note(src, A.actor, A.held, A.step_value("description"))
			if(note)
				set_examtext(note)
	SStgui.update_uis(src)
	return OP_PASS

/// Old attack_robot: an adjacent cyborg unwraps it. Never fell through.
/obj/structure/bigDelivery/proc/big_delivery_robot_unwrap(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.stat || !Adjacent(user))
		return OP_OK
	unwrap()
	return OP_OK

/// The wrapping with its label and tag, set where the wrapping's kind puts them.
/obj/structure/bigDelivery/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(nameset || examtext)
		if(drawn_state == "deliverycloset")
			look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_label", pixel_x = 2, pixel_y = parcel_offset(src, "label_y", -6, 11)))
		else if(drawn_state == "deliverycrate")
			look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_label", pixel_x = parcel_offset(src, "label_x", -8, 6), pixel_y = -3))
		else
			look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_label"))
	if(sortTag)
		if(drawn_state == "deliverycloset")
			look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag", pixel_x = parcel_offset(src, "tag_closet", -2, 3), pixel_y = 9))
		else if(drawn_state == "deliverycrate")
			look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag", pixel_x = parcel_offset(src, "tag_crate", -8, 6), pixel_y = -3))
		else
			look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag"))

/obj/structure/bigDelivery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 4)
		if(sortTag)
			. += span_notice("It is labeled \"[sortTag]\"")
		if(examtext)
			. += span_notice("It has a note attached which reads, \"[examtext]\"")


// the wrapped thing is unwrapped onto the floor.
DESTROY_EFFECTS(/obj/structure/bigDelivery, new /datum/destroy_effects_data(drop_contents = TRUE))

/obj/structure/bigDelivery/on_destroy(force)
	if(wrapped()) //sometimes items can disappear. For example, bombs. --rastaf0
		wrapped().forceMove(get_turf(src))
		if(istype(wrapped(), /obj/structure/closet))
			var/obj/structure/closet/O = wrapped()
			set_welded(O, FALSE)
	..()

/obj/item/smallDelivery
	desc = "A small wrapped package."
	name = "small parcel"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "deliverycrate3"
	var/obj/item/wrapped = null
	var/sortTag = null
	var/examtext = null
	var/nameset = 0


CAPABILITIES(/obj/item/smallDelivery)
	configure(item_sounds(drop = SFX_ITEMS_DROP_CARDBOARDBOX, pickup = SFX_ITEMS_PICKUP_CARDBOARDBOX))
	op("use", in_hand(), then(PROC_REF(interaction_self)))
	op("tag", item(/obj/item/destTagger), then(PROC_REF(parcel_tag)))
	op("label", item(/obj/item/pen),
		asks(/datum/prompt/choice, fields = list("question" = "What would you like to alter?", "title" = "Select Alteration", "choices" = list("Title", "Description", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "alteration"),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "title", when = PROC_REF(label_asks_title)),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "timeout" = 0), step = "description", when = PROC_REF(label_asks_description)),
		then(PROC_REF(parcel_label)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("robot_unwrap", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Unwrap"), then(PROC_REF(small_delivery_robot_unwrap)))
	owns_one(nameof(wrapped), on_destroy = ON_DESTROY_CONTAINED)

/// Old attack_self.
/obj/item/smallDelivery/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if (wrapped) //sometimes items can disappear. For example, bombs. --rastaf0
		wrapped.forceMove(user.loc)
		if(ishuman(user))
			user.put_in_hands(wrapped)
		else
			wrapped.forceMove(get_turf(src))

	consume(src, user)
	return OP_OK

/// Old attackby for any other item: handled, the item not used up.
/obj/item/smallDelivery/proc/interaction_item(datum/act/op/A)
	return OP_PASS

/// A destination tagger sets the sort tag.
/obj/item/smallDelivery/proc/parcel_tag(datum/act/op/A)
	var/obj/item/destTagger/O = A.held
	if(parcel_tag_accepted(src, A.actor, O.currTag, sortTag))
		set_sortTag(O.currTag)
	return OP_PASS

/// The pen's menu answered Title: the title is asked.
/obj/item/smallDelivery/proc/label_asks_title(datum/act/op/A)
	return A.step_value("alteration") == "Title"

/// The pen's menu answered Description: the description is asked.
/obj/item/smallDelivery/proc/label_asks_description(datum/act/op/A)
	return A.step_value("alteration") == "Description"

/// A pen titles the parcel or writes the note on it.
/obj/item/smallDelivery/proc/parcel_label(datum/act/op/A)
	switch(A.step_value("alteration"))
		if("Title")
			var/title = parcel_new_title(src, A.actor, A.held, A.step_value("title"))
			if(title)
				name = "[name] ([title])"
				set_nameset(1)
		if("Description")
			var/note = parcel_new_note(src, A.actor, A.held, A.step_value("description"))
			if(note)
				set_examtext(note)
	SStgui.update_uis(src)
	return OP_PASS

/// Old attack_robot: an adjacent cyborg unwraps it as in hand. Never fell through.
/obj/item/smallDelivery/proc/small_delivery_robot_unwrap(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.stat || !Adjacent(user))
		return OP_OK
	attack_self(user)
	return OP_OK

/// The wrapping with its label and tag, set where the wrapping's kind puts them.
/obj/item/smallDelivery/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if((nameset || examtext) && drawn_state != "deliverycrate1")
		look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_label", pixel_y = drawn_state == "deliverycrate5" ? -1 : 0))
	if(sortTag)
		switch(drawn_state)
			if("deliverycrate1")
				look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag", pixel_y = -5))
			if("deliverycrate2")
				look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag", pixel_y = -2))
			if("deliverycrate3")
				look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag"))
			if("deliverycrate4")
				look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag", pixel_x = parcel_offset(src, "tag_small", 0, 5), pixel_y = 3))
			if("deliverycrate5")
				look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag", pixel_y = -3))
			else
				look.overlay(look_overlay_image('icons/obj/storage.dmi', "delivery_tag"))

/obj/item/smallDelivery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 4)
		if(sortTag)
			. += span_notice("It is labeled \"[sortTag]\"")
		if(examtext)
			. += span_notice("It has a note attached which reads, \"[examtext]\"")


/// the wrapped this refers to (a relation view: it reads null once the target is deleted).
/obj/structure/bigDelivery/proc/wrapped() as /obj
	return wrapped
