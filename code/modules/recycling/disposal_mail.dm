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
	if(loc?.release_refusal(src))
		return
	play_sfx(src, SFX_ITEMS_PACKAGE_UNWRAP)
	// Teardown drops our wrapped object on the turf, so let it.
	consume(src)

/// Old attackby.
/obj/structure/bigDelivery/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	return parcel_item_stage(user, W, interaction, list())

/obj/structure/bigDelivery/proc/parcel_item_stage(mob/user, obj/item/W, datum/interaction/interaction, list/parcel_answers)
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
				play_sfx(src, SFX_MACHINES_TWOBEEP)
			else
				to_chat(user, span_warning("The package is already labeled for [O.currTag]."))
		else
			to_chat(user, span_warning("You need to set a destination first!"))

	else if(istype(W, /obj/item/pen))
		if(!("k43" in parcel_answers))
			open_request(src, /datum/prompt/choice/parcel_label_review, PROC_REF(parcel_label_answered), answerer = user, parcel_operator = user, parcel_pen = W, parcel_interaction = interaction, parcel_answers = parcel_answers, parcel_key = "k43", question = "What would you like to alter?", title = "Select Alteration", choices = list("Title","Description","Cancel"), buttons = TRUE)
			return TRUE
		var/_answer_k43 = parcel_answers["k43"]
		if(isnull(_answer_k43))
			return TRUE
		switch(_answer_k43)
			if("Title")
				if(!("k45" in parcel_answers))
					open_request(src, /datum/prompt/text/parcel_label_review, PROC_REF(parcel_label_answered), answerer = user, parcel_operator = user, parcel_pen = W, parcel_interaction = interaction, parcel_answers = parcel_answers, parcel_key = "k45", question = "Label text?", title = "Set label", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
					return TRUE
				var/_answer_k45 = parcel_answers["k45"]
				if(isnull(_answer_k45))
					return TRUE
				var/str = sanitizeSafe(_answer_k45, MAX_NAME_LEN)
				if(!str || !length(str))
					to_chat(user, span_warning(" Invalid text."))
					return INTERACTION_HANDLED_PASS
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
				if(!("k60" in parcel_answers))
					open_request(src, /datum/prompt/text/parcel_label_review, PROC_REF(parcel_label_answered), answerer = user, parcel_operator = user, parcel_pen = W, parcel_interaction = interaction, parcel_answers = parcel_answers, parcel_key = "k60", question = "Label text?", title = "Set label")
					return TRUE
				var/str = parcel_answers["k60"]
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
				act_message(user, src, MSG_SELF(span_notice("You label %T%: \"[MSG_LITERAL(examtext)]\"")), \
					MSG_OTHERS("%U% labels %T% with \a [W], scribbling down: \"[MSG_LITERAL(examtext)]\""), \
					MSG_BLIND("You hear someone scribbling a note."))
				play_sfx(src, SFX_BUREAUCRACY_PEN)
	return INTERACTION_HANDLED_PASS

/// Old attack_robot: an adjacent cyborg unwraps it. Never fell through.
/obj/structure/bigDelivery/proc/big_delivery_robot_unwrap(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !Adjacent(user))
		return TRUE
	unwrap()
	return TRUE

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
	return parcel_item_stage(user, W, interaction, list())

/obj/item/smallDelivery/proc/parcel_item_stage(mob/user, obj/item/W, datum/interaction/interaction, list/parcel_answers)
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
				play_sfx(src, SFX_MACHINES_TWOBEEP)
			else
				to_chat(user, span_warning("The package is already labeled for [O.currTag]."))
		else
			to_chat(user, span_warning("You need to set a destination first!"))

	else if(istype(W, /obj/item/pen))
		if(!("k174" in parcel_answers))
			open_request(src, /datum/prompt/choice/parcel_label_review, PROC_REF(parcel_label_answered), answerer = user, parcel_operator = user, parcel_pen = W, parcel_interaction = interaction, parcel_answers = parcel_answers, parcel_key = "k174", question = "What would you like to alter?", title = "Select Alteration", choices = list("Title","Description","Cancel"), buttons = TRUE)
			return TRUE
		var/_answer_k174 = parcel_answers["k174"]
		if(isnull(_answer_k174))
			return TRUE
		switch(_answer_k174)
			if("Title")
				if(!("k176" in parcel_answers))
					open_request(src, /datum/prompt/text/parcel_label_review, PROC_REF(parcel_label_answered), answerer = user, parcel_operator = user, parcel_pen = W, parcel_interaction = interaction, parcel_answers = parcel_answers, parcel_key = "k176", question = "Label text?", title = "Set label", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
					return TRUE
				var/_answer_k176 = parcel_answers["k176"]
				if(isnull(_answer_k176))
					return TRUE
				var/str = sanitizeSafe(_answer_k176, MAX_NAME_LEN)
				if(!str || !length(str))
					to_chat(user, span_warning(" Invalid text."))
					return INTERACTION_HANDLED_PASS
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
				if(!("k192" in parcel_answers))
					open_request(src, /datum/prompt/text/parcel_label_review, PROC_REF(parcel_label_answered), answerer = user, parcel_operator = user, parcel_pen = W, parcel_interaction = interaction, parcel_answers = parcel_answers, parcel_key = "k192", question = "Label text?", title = "Set label")
					return TRUE
				var/str = parcel_answers["k192"]
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
				act_message(user, src, MSG_SELF(span_notice("You label %T%: \"[MSG_LITERAL(examtext)]\"")), \
					MSG_OTHERS("%U% labels %T% with \a [W], scribbling down: \"[MSG_LITERAL(examtext)]\""), \
					MSG_BLIND("You hear someone scribbling a note."))
				play_sfx(src, SFX_BUREAUCRACY_PEN)
	return INTERACTION_HANDLED_PASS

/// Old attack_robot: an adjacent cyborg unwraps it as in hand. Never fell through.
/obj/item/smallDelivery/proc/small_delivery_robot_unwrap(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(user.stat || !Adjacent(user))
		return TRUE
	attack_self(user)
	return TRUE

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

/obj/structure/bigDelivery/proc/parcel_label_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = parcel_label_apply(A)
	SStgui.update_uis(src)

/obj/structure/bigDelivery/proc/parcel_label_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/choice/parcel_label_review))
		var/datum/prompt/choice/parcel_label_review/ask = A.answer
		ask.parcel_answers[ask.parcel_key] = ask.value
		return parcel_item_stage(ask.parcel_operator, ask.parcel_pen, ask.parcel_interaction, ask.parcel_answers)
	var/datum/prompt/text/parcel_label_review/ask = A.answer
	ask.parcel_answers[ask.parcel_key] = ask.value
	return parcel_item_stage(ask.parcel_operator, ask.parcel_pen, ask.parcel_interaction, ask.parcel_answers)

/obj/item/smallDelivery/proc/parcel_label_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = parcel_label_apply(A)
	SStgui.update_uis(src)

/obj/item/smallDelivery/proc/parcel_label_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/choice/parcel_label_review))
		var/datum/prompt/choice/parcel_label_review/ask = A.answer
		ask.parcel_answers[ask.parcel_key] = ask.value
		return parcel_item_stage(ask.parcel_operator, ask.parcel_pen, ask.parcel_interaction, ask.parcel_answers)
	var/datum/prompt/text/parcel_label_review/ask = A.answer
	ask.parcel_answers[ask.parcel_key] = ask.value
	return parcel_item_stage(ask.parcel_operator, ask.parcel_pen, ask.parcel_interaction, ask.parcel_answers)

/datum/prompt/choice/parcel_label_review
	timeout = 0
	var/mob/parcel_operator
	var/obj/item/parcel_pen
	var/datum/interaction/parcel_interaction
	var/parcel_operator_expected = FALSE
	var/parcel_pen_expected = FALSE
	var/parcel_interaction_expected = FALSE
	var/list/parcel_answers
	var/parcel_key

CAPABILITIES(/datum/prompt/choice/parcel_label_review)
	ref_one(nameof(parcel_operator), /mob)
	ref_one(nameof(parcel_pen), /obj/item)
	ref_one(nameof(parcel_interaction), /datum/interaction)

/datum/prompt/choice/parcel_label_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = parcel_operator
	var/obj/item/captured_pen = parcel_pen
	var/datum/interaction/captured_interaction = parcel_interaction
	parcel_operator_expected = !isnull(captured_operator)
	parcel_pen_expected = !isnull(captured_pen)
	parcel_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(parcel_operator))
	rel_clear(src, nameof(parcel_pen))
	rel_clear(src, nameof(parcel_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(parcel_operator), captured_operator)
	if(captured_pen && !QDELETED(captured_pen))
		rel_set(src, nameof(parcel_pen), captured_pen)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(parcel_interaction), captured_interaction)

/datum/prompt/choice/parcel_label_review/recheck_extra()
	if((parcel_operator_expected && QDELETED(parcel_operator)) || (parcel_pen_expected && QDELETED(parcel_pen)) || (parcel_interaction_expected && QDELETED(parcel_interaction)))
		return "gone"

/datum/prompt/text/parcel_label_review
	timeout = 0
	var/mob/parcel_operator
	var/obj/item/parcel_pen
	var/datum/interaction/parcel_interaction
	var/parcel_operator_expected = FALSE
	var/parcel_pen_expected = FALSE
	var/parcel_interaction_expected = FALSE
	var/list/parcel_answers
	var/parcel_key

CAPABILITIES(/datum/prompt/text/parcel_label_review)
	ref_one(nameof(parcel_operator), /mob)
	ref_one(nameof(parcel_pen), /obj/item)
	ref_one(nameof(parcel_interaction), /datum/interaction)

/datum/prompt/text/parcel_label_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = parcel_operator
	var/obj/item/captured_pen = parcel_pen
	var/datum/interaction/captured_interaction = parcel_interaction
	parcel_operator_expected = !isnull(captured_operator)
	parcel_pen_expected = !isnull(captured_pen)
	parcel_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(parcel_operator))
	rel_clear(src, nameof(parcel_pen))
	rel_clear(src, nameof(parcel_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(parcel_operator), captured_operator)
	if(captured_pen && !QDELETED(captured_pen))
		rel_set(src, nameof(parcel_pen), captured_pen)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(parcel_interaction), captured_interaction)

/datum/prompt/text/parcel_label_review/recheck_extra()
	if((parcel_operator_expected && QDELETED(parcel_operator)) || (parcel_pen_expected && QDELETED(parcel_pen)) || (parcel_interaction_expected && QDELETED(parcel_interaction)))
		return "gone"
