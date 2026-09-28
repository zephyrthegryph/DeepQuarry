/obj/structure/bigDelivery
	desc = "A big wrapped package."
	name = "large parcel"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "deliverycloset"
	var/tmp/wrapped_handle
	density = TRUE
	var/sortTag = null
	flags = NOBLUDGEON
	mouse_drag_pointer = MOUSE_ACTIVE_POINTER
	var/examtext = null
	var/nameset = 0
	var/label_y
	var/label_x
	var/tag_x

DECLARE_INTERACTIONS(/obj/structure/bigDelivery, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ROBOT("Unwrap", PROC_REF(big_delivery_robot_unwrap)), \
)

/// Old attack_hand.
/obj/structure/bigDelivery/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	unwrap()
	return TRUE

/obj/structure/bigDelivery/proc/unwrap()
	playsound(src, 'sound/items/package_unwrap.ogg', 50, 1)
	// Destroy will drop our wrapped object on the turf, so let it.
	qdel(src)

/// Old attackby.
/obj/structure/bigDelivery/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/destTagger))
		var/obj/item/destTagger/O = W
		if(O.currTag)
			if(src.sortTag != O.currTag)
				to_chat(user, span_notice("You have labeled the destination as [O.currTag]."))
				if(!src.sortTag)
					src.sortTag = O.currTag
					update_icon()
				else
					src.sortTag = O.currTag
				playsound(src, 'sound/machines/twobeep.ogg', 50, 1)
			else
				to_chat(user, span_warning("The package is already labeled for [O.currTag]."))
		else
			to_chat(user, span_warning("You need to set a destination first!"))

	else if(istype(W, /obj/item/pen))
		var/_answer_k43 = rerun_ask(user, "k43", PROC_REF(interaction_item), args, /datum/om/prompt/choice/alert, message = "What would you like to alter?", title = "Select Alteration", choices = list("Title","Description","Cancel"))
		if(isnull(_answer_k43))
			return TRUE
		switch(_answer_k43)
			if("Title")
				var/_answer_k45 = rerun_ask(user, "k45", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Label text?", title = "Set label", max_length = MAX_NAME_LEN, encode = FALSE)
				if(isnull(_answer_k45))
					return TRUE
				var/str = sanitizeSafe(_answer_k45, MAX_NAME_LEN)
				if(!str || !length(str))
					to_chat(user, span_warning(" Invalid text."))
					return INTERACTION_HANDLED_PASS
				user.visible_message("\The [user] titles \the [src] with \a [W], marking down: \"[str]\"",\
				span_notice("You title \the [src]: \"[str]\""),\
				"You hear someone scribbling a note.")
				playsound(src, pick('sound/bureaucracy/pen1.ogg','sound/bureaucracy/pen2.ogg'), 20)
				name = "[name] ([str])"
				if(!examtext && !nameset)
					nameset = 1
					update_icon()
				else
					nameset = 1
			if("Description")
				var/str = rerun_ask(user, "k60", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Label text?", title = "Set label")
				if(isnull(str))
					return TRUE
				if(!str || !length(str))
					to_chat(user, span_red("Invalid text."))
					return INTERACTION_HANDLED_PASS
				if(!examtext && !nameset)
					examtext = str
					update_icon()
				else
					examtext = str
				user.visible_message("\The [user] labels \the [src] with \a [W], scribbling down: \"[examtext]\"",\
				span_notice("You label \the [src]: \"[examtext]\""),\
				"You hear someone scribbling a note.")
				playsound(src, pick('sound/bureaucracy/pen1.ogg','sound/bureaucracy/pen2.ogg'), 20)
	return INTERACTION_HANDLED_PASS

/// Old attack_robot: an adjacent cyborg unwraps it. Never fell through.
/obj/structure/bigDelivery/proc/big_delivery_robot_unwrap(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !Adjacent(user))
		return TRUE
	unwrap()
	return TRUE

/obj/structure/bigDelivery/update_icon()
	cut_overlays()
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
		add_overlay(I)
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
		add_overlay(I)

/obj/structure/bigDelivery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 4)
		if(sortTag)
			. += span_notice("It is labeled \"[sortTag]\"")
		if(examtext)
			. += span_notice("It has a note attached which reads, \"[examtext]\"")

// the wrapped thing is unwrapped onto the floor.
/obj/structure/bigDelivery/on_destroy(force)
	if(wrapped()) //sometimes items can disappear. For example, bombs. --rastaf0
		wrapped().forceMove(get_turf(src))
		if(istype(wrapped(), /obj/structure/closet))
			var/obj/structure/closet/O = wrapped()
			O.sealed = 0
		wrapped_handle = null
	var/turf/T = get_turf(src)
	for(var/atom/movable/AM in contents)
		AM.forceMove(T)
	..()

/obj/item/smallDelivery
	desc = "A small wrapped package."
	name = "small parcel"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "deliverycrate3"
	drop_sound = 'sound/items/drop/cardboardbox.ogg'
	pickup_sound = 'sound/items/pickup/cardboardbox.ogg'
	var/obj/item/wrapped = null
	var/sortTag = null
	var/examtext = null
	var/nameset = 0
	var/tag_x

DECLARE_INTERACTIONS(/obj/item/smallDelivery, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ROBOT("Unwrap", PROC_REF(small_delivery_robot_unwrap)), \
)

/// Old attack_self.
/obj/item/smallDelivery/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if (wrapped) //sometimes items can disappear. For example, bombs. --rastaf0
		wrapped.forceMove(user.loc)
		if(ishuman(user))
			user.put_in_hands(wrapped)
		else
			wrapped.forceMove(get_turf(src))

	consume(src, user)
	return TRUE

/// Old attackby.
/obj/item/smallDelivery/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/destTagger))
		var/obj/item/destTagger/O = W
		if(O.currTag)
			if(src.sortTag != O.currTag)
				to_chat(user, span_notice("You have labeled the destination as [O.currTag]."))
				if(!src.sortTag)
					src.sortTag = O.currTag
					update_icon()
				else
					src.sortTag = O.currTag
				playsound(src, 'sound/machines/twobeep.ogg', 50, 1)
			else
				to_chat(user, span_warning("The package is already labeled for [O.currTag]."))
		else
			to_chat(user, span_warning("You need to set a destination first!"))

	else if(istype(W, /obj/item/pen))
		var/_answer_k174 = rerun_ask(user, "k174", PROC_REF(interaction_item), args, /datum/om/prompt/choice/alert, message = "What would you like to alter?", title = "Select Alteration", choices = list("Title","Description","Cancel"))
		if(isnull(_answer_k174))
			return TRUE
		switch(_answer_k174)
			if("Title")
				var/_answer_k176 = rerun_ask(user, "k176", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Label text?", title = "Set label", max_length = MAX_NAME_LEN, encode = FALSE)
				if(isnull(_answer_k176))
					return TRUE
				var/str = sanitizeSafe(_answer_k176, MAX_NAME_LEN)
				if(!str || !length(str))
					to_chat(user, span_warning(" Invalid text."))
					return INTERACTION_HANDLED_PASS
				user.visible_message("\The [user] titles \the [src] with \a [W], marking down: \"[str]\"",\
				span_notice("You title \the [src]: \"[str]\""),\
				"You hear someone scribbling a note.")
				playsound(src, pick('sound/bureaucracy/pen1.ogg','sound/bureaucracy/pen2.ogg'), 20)
				name = "[name] ([str])"
				if(!examtext && !nameset)
					nameset = 1
					update_icon()
				else
					nameset = 1

			if("Description")
				var/str = rerun_ask(user, "k192", PROC_REF(interaction_item), args, /datum/om/prompt/text, message = "Label text?", title = "Set label")
				if(isnull(str))
					return TRUE
				if(!str || !length(str))
					to_chat(user, span_red("Invalid text."))
					return INTERACTION_HANDLED_PASS
				if(!examtext && !nameset)
					examtext = str
					update_icon()
				else
					examtext = str
				user.visible_message("\The [user] labels \the [src] with \a [W], scribbling down: \"[examtext]\"",\
				span_notice("You label \the [src]: \"[examtext]\""),\
				"You hear someone scribbling a note.")
				playsound(src, pick('sound/bureaucracy/pen1.ogg','sound/bureaucracy/pen2.ogg'), 20)
	return INTERACTION_HANDLED_PASS

/// Old attack_robot: an adjacent cyborg unwraps it as in hand. Never fell through.
/obj/item/smallDelivery/proc/small_delivery_robot_unwrap(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !Adjacent(user))
		return TRUE
	attack_self(user)
	return TRUE

/obj/item/smallDelivery/update_icon()
	cut_overlays()
	if((nameset || examtext) && icon_state != "deliverycrate1")
		var/image/I = new/image('icons/obj/storage.dmi',"delivery_label")
		if(icon_state == "deliverycrate5")
			I.pixel_y = -1
		add_overlay(I)
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
		add_overlay(I)

/obj/item/smallDelivery/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 4)
		if(sortTag)
			. += span_notice("It is labeled \"[sortTag]\"")
		if(examtext)
			. += span_notice("It has a note attached which reads, \"[examtext]\"")

DECLARE_REF(/obj/item/smallDelivery, "wrapped", HELD, null)

/// LC-refs: the wrapped this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/bigDelivery/proc/wrapped() as /obj
	return om_resolve(wrapped_handle)
