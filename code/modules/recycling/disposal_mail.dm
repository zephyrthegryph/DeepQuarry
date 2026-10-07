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
	var/label_y
	var/label_x
	var/tag_x

CAPABILITIES(/obj/structure/bigDelivery)
	op("hand", hand(), ungated(), then(PROC_REF(interaction_hand)))
	op("tag", item(/obj/item/destTagger), then(PROC_REF(parcel_tag)))
	op("label", item(/obj/item/pen),
		asks(/datum/prompt/choice, fields = list("question" = "What would you like to alter?", "title" = "Select Alteration", "choices" = list("Title", "Description", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "alteration"),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "title", when = PROC_REF(label_asks_title)),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "timeout" = 0), step = "description", when = PROC_REF(label_asks_description)),
		then(PROC_REF(parcel_label)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("robot_unwrap", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Unwrap"), then(PROC_REF(big_delivery_robot_unwrap)))

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
	var/mob/user = A.actor
	var/obj/item/destTagger/O = A.held
	if(O.currTag)
		if(src.sortTag != O.currTag)
			to_chat(user, span_notice("You have labeled the destination as [O.currTag]."))
			if(!src.sortTag)
				src.sortTag = O.currTag
				update_icon()
			else
				src.sortTag = O.currTag
			play_sfx(src, SFX_MACHINES_TWOBEEP)
		else
			to_chat(user, span_warning("The package is already labeled for [O.currTag]."))
	else
		to_chat(user, span_warning("You need to set a destination first!"))
	return OP_PASS

/// The pen's menu answered Title: the title is asked.
/obj/structure/bigDelivery/proc/label_asks_title(datum/act/op/A)
	return A.step_value("alteration") == "Title"

/// The pen's menu answered Description: the description is asked.
/obj/structure/bigDelivery/proc/label_asks_description(datum/act/op/A)
	return A.step_value("alteration") == "Description"

/// A pen titles the parcel or writes the note on it.
/obj/structure/bigDelivery/proc/parcel_label(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	switch(A.step_value("alteration"))
		if("Title")
			var/str = sanitizeSafe(A.step_value("title"), MAX_NAME_LEN)
			if(!str || !length(str))
				to_chat(user, span_warning(" Invalid text."))
				return OP_PASS
			act_message(user, src, MSG_SELF(span_notice("You title %T%: \"[MSG_LITERAL(str)]\"")), \
				MSG_OTHERS("%U% titles %T% with \a [W], marking down: \"[MSG_LITERAL(str)]\""), \
				MSG_BLIND("You hear someone scribbling a note."))
			play_sfx(src, SFX_BUREAUCRACY_PEN)
			name = "[name] ([str])"
			if(!examtext && !nameset)
				nameset = 1
				update_icon()
			else
				nameset = 1
		if("Description")
			var/str = A.step_value("description")
			if(!str || !length(str))
				to_chat(user, span_red("Invalid text."))
				return OP_PASS
			if(!examtext && !nameset)
				examtext = str
				update_icon()
			else
				examtext = str
			act_message(user, src, MSG_SELF(span_notice("You label %T%: \"[MSG_LITERAL(examtext)]\"")), \
				MSG_OTHERS("%U% labels %T% with \a [W], scribbling down: \"[MSG_LITERAL(examtext)]\""), \
				MSG_BLIND("You hear someone scribbling a note."))
			play_sfx(src, SFX_BUREAUCRACY_PEN)
	SStgui.update_uis(src)
	return OP_PASS

/// Old attack_robot: an adjacent cyborg unwraps it. Never fell through.
/obj/structure/bigDelivery/proc/big_delivery_robot_unwrap(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.stat || !Adjacent(user))
		return OP_OK
	unwrap()
	return OP_OK

DECLARE_APPEARANCE_PROC(/obj/structure/bigDelivery, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/bigDelivery/appearance_overlays()
	. = list()
	if(nameset || examtext)
		var/image/I = new/image('icons/obj/storage.dmi',"delivery_label")
		if(icon_state == "deliverycloset")
			I.pixel_x = 2
			if(label_y == null)
				label_y = rand(-6, 11)
			I.pixel_y = label_y
		else if(icon_state == "deliverycrate")
			if(label_x == null)
				label_x = rand(-8, 6)
			I.pixel_x = label_x
			I.pixel_y = -3
		. += I
	if(src.sortTag)
		var/image/I = new/image('icons/obj/storage.dmi',"delivery_tag")
		if(icon_state == "deliverycloset")
			if(tag_x == null)
				tag_x = rand(-2, 3)
			I.pixel_x = tag_x
			I.pixel_y = 9
		else if(icon_state == "deliverycrate")
			if(tag_x == null)
				tag_x = rand(-8, 6)
			I.pixel_x = tag_x
			I.pixel_y = -3
		. += I

/obj/structure/bigDelivery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 4)
		if(sortTag)
			. += span_notice("It is labeled \"[sortTag]\"")
		if(examtext)
			. += span_notice("It has a note attached which reads, \"[examtext]\"")

/obj/structure/bigDelivery/ownership()
	. = ..()
	. += owns(nameof(wrapped), policy = OWN_SPILL)

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
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX
	var/obj/item/wrapped = null
	var/sortTag = null
	var/examtext = null
	var/nameset = 0
	var/tag_x

CAPABILITIES(/obj/item/smallDelivery)
	op("use", in_hand(), then(PROC_REF(interaction_self)))
	op("tag", item(/obj/item/destTagger), then(PROC_REF(parcel_tag)))
	op("label", item(/obj/item/pen),
		asks(/datum/prompt/choice, fields = list("question" = "What would you like to alter?", "title" = "Select Alteration", "choices" = list("Title", "Description", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "alteration"),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "title", when = PROC_REF(label_asks_title)),
		asks(/datum/prompt/text, fields = list("question" = "Label text?", "title" = "Set label", "timeout" = 0), step = "description", when = PROC_REF(label_asks_description)),
		then(PROC_REF(parcel_label)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	op("robot_unwrap", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Unwrap"), then(PROC_REF(small_delivery_robot_unwrap)))

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
	var/mob/user = A.actor
	var/obj/item/destTagger/O = A.held
	if(O.currTag)
		if(src.sortTag != O.currTag)
			to_chat(user, span_notice("You have labeled the destination as [O.currTag]."))
			if(!src.sortTag)
				src.sortTag = O.currTag
				update_icon()
			else
				src.sortTag = O.currTag
			play_sfx(src, SFX_MACHINES_TWOBEEP)
		else
			to_chat(user, span_warning("The package is already labeled for [O.currTag]."))
	else
		to_chat(user, span_warning("You need to set a destination first!"))
	return OP_PASS

/// The pen's menu answered Title: the title is asked.
/obj/item/smallDelivery/proc/label_asks_title(datum/act/op/A)
	return A.step_value("alteration") == "Title"

/// The pen's menu answered Description: the description is asked.
/obj/item/smallDelivery/proc/label_asks_description(datum/act/op/A)
	return A.step_value("alteration") == "Description"

/// A pen titles the parcel or writes the note on it.
/obj/item/smallDelivery/proc/parcel_label(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	switch(A.step_value("alteration"))
		if("Title")
			var/str = sanitizeSafe(A.step_value("title"), MAX_NAME_LEN)
			if(!str || !length(str))
				to_chat(user, span_warning(" Invalid text."))
				return OP_PASS
			act_message(user, src, MSG_SELF(span_notice("You title %T%: \"[MSG_LITERAL(str)]\"")), \
				MSG_OTHERS("%U% titles %T% with \a [W], marking down: \"[MSG_LITERAL(str)]\""), \
				MSG_BLIND("You hear someone scribbling a note."))
			play_sfx(src, SFX_BUREAUCRACY_PEN)
			name = "[name] ([str])"
			if(!examtext && !nameset)
				nameset = 1
				update_icon()
			else
				nameset = 1
		if("Description")
			var/str = A.step_value("description")
			if(!str || !length(str))
				to_chat(user, span_red("Invalid text."))
				return OP_PASS
			if(!examtext && !nameset)
				examtext = str
				update_icon()
			else
				examtext = str
			act_message(user, src, MSG_SELF(span_notice("You label %T%: \"[MSG_LITERAL(examtext)]\"")), \
				MSG_OTHERS("%U% labels %T% with \a [W], scribbling down: \"[MSG_LITERAL(examtext)]\""), \
				MSG_BLIND("You hear someone scribbling a note."))
			play_sfx(src, SFX_BUREAUCRACY_PEN)
	SStgui.update_uis(src)
	return OP_PASS

/// Old attack_robot: an adjacent cyborg unwraps it as in hand. Never fell through.
/obj/item/smallDelivery/proc/small_delivery_robot_unwrap(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.stat || !Adjacent(user))
		return OP_OK
	attack_self(user)
	return OP_OK

DECLARE_APPEARANCE_PROC(/obj/item/smallDelivery, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/smallDelivery/appearance_overlays()
	. = list()
	if((nameset || examtext) && icon_state != "deliverycrate1")
		var/image/I = new/image('icons/obj/storage.dmi',"delivery_label")
		if(icon_state == "deliverycrate5")
			I.pixel_y = -1
		. += I
	if(src.sortTag)
		var/image/I = new/image('icons/obj/storage.dmi',"delivery_tag")
		switch(icon_state)
			if("deliverycrate1")
				I.pixel_y = -5
			if("deliverycrate2")
				I.pixel_y = -2
			if("deliverycrate3")
				I.pixel_y = 0
			if("deliverycrate4")
				if(tag_x == null)
					tag_x = rand(0,5)
				I.pixel_x = tag_x
				I.pixel_y = 3
			if("deliverycrate5")
				I.pixel_y = -3
		. += I

/obj/item/smallDelivery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 4)
		if(sortTag)
			. += span_notice("It is labeled \"[sortTag]\"")
		if(examtext)
			. += span_notice("It has a note attached which reads, \"[examtext]\"")

/obj/item/smallDelivery/ownership()
	. = ..()
	. += owns(nameof(wrapped), policy = OWN_CONTAINED)

/// the wrapped this refers to (a relation view: it reads null once the target is deleted).
/obj/structure/bigDelivery/proc/wrapped() as /obj
	return wrapped
