/obj/item/hand_labeler
	name = "hand labeler"
	desc = "Label everything like you've always wanted to! Stuck to the side is a label reading \'Labeler\'. Seems you're too late for that one."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "labeler0"
	var/label = null
	var/labels_left = 30
	var/mode = 0	//off or on.
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE

/obj/item/hand_labeler/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/hand_labeler/afterattack(atom/A, mob/user, proximity)
	if(!proximity)
		return
	if(!mode)	//if it's off, give up.
		return
	if(A == loc)	// if placing the labeller into something (e.g. backpack)
		return		// don't set a label

	if(!labels_left)
		to_chat(user, span_warning("\The [src] has no labels left."))
		return
	if(!label || !length(label))
		to_chat(user, span_warning("\The [src] has no label text set."))
		return
	if(length(A.name) + length(label) > 64)
		to_chat(user, span_warning("\The [src]'s label too big."))
		return
	if(istype(A, /mob/living/silicon/robot/platform))
		var/mob/living/silicon/robot/platform/P = A
		if(!P.allowed(user))
			to_chat(user, span_warning("Access denied."))
		else if(P.client || P.key)
			to_chat(user, span_notice("You rename \the [P] to [label]."))
			to_chat(P, span_notice("\The [user] renames you to [label]."))
			P.custom_name = label
			P.SetName(P.custom_name)
		else
			to_chat(user, span_warning("\The [src] is inactive and cannot be renamed."))
		return
	if(ishuman(A))
		to_chat(user, span_warning("The label refuses to stick to [A.name]."))
		return
	if(issilicon(A))
		to_chat(user, span_warning("The label refuses to stick to [A.name]."))
		return
	if(isobserver(A))
		to_chat(user, span_warning("[src] passes through [A.name]."))
		return
	if(istype(A, /obj/item/reagent_containers/glass))
		to_chat(user, span_warning("The label can't stick to the [A.name] (Try using a pen)."))
		return
	if(istype(A, /obj/machinery/portable_atmospherics/hydroponics))
		var/obj/machinery/portable_atmospherics/hydroponics/tray = A
		if(!tray.mechanical)
			to_chat(user, span_warning("How are you going to label that?"))
			return
		tray.set_labelled(label)

	act_message(user, A, MSG_SELF(span_notice("You label %T% as [label].")), MSG_OTHERS(span_notice("%U% labels %T% as [label].")))
	A.name = "[A.name] ([label])"

CAPABILITIES(/obj/item/hand_labeler)
	op("labeler_self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/hand_labeler/proc/interaction_self(datum/act/op/A)
	label_configuration_begin(A.actor, A.held)
	return OP_OK

/obj/item/hand_labeler/proc/label_configuration_begin(mob/user, obj/item/held)
	mode = !mode
	icon_state = "labeler[mode]"
	if(mode)
		to_chat(user, span_notice("You turn on \the [src]."))
		//Now let them chose the text.
		open_request(src, /datum/prompt/text/hand_labeler_label, PROC_REF(label_configuration_answered), answerer = user, label_operator = user, label_held = held, question = "Label text?", title = "Set label", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
	else
		to_chat(user, span_notice("You turn off \the [src]."))
	return TRUE

/obj/item/hand_labeler/proc/label_configuration_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = label_configuration_apply(A)
	SStgui.update_uis(src)

/obj/item/hand_labeler/proc/label_configuration_apply(datum/act/request/A)
	var/datum/prompt/text/hand_labeler_label/ask = A.answer
	var/str = sanitizeSafe(ask.value, MAX_NAME_LEN)
	if(!str || !length(str))
		to_chat(ask.label_operator, span_warning("Invalid text."))
		return TRUE
	label = str
	to_chat(ask.label_operator, span_notice("You set the text to '[str]'."))
	return TRUE

/datum/prompt/text/hand_labeler_label
	timeout = 0
	var/mob/label_operator
	var/obj/item/label_held
	var/label_operator_expected = FALSE
	var/label_held_expected = FALSE

CAPABILITIES(/datum/prompt/text/hand_labeler_label)
	ref_one(nameof(label_operator), /mob)
	ref_one(nameof(label_held), /obj/item)

/datum/prompt/text/hand_labeler_label/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = label_operator
	var/obj/item/captured_held = label_held
	label_operator_expected = !isnull(captured_operator)
	label_held_expected = !isnull(captured_held)
	rel_clear(src, nameof(label_operator))
	rel_clear(src, nameof(label_held))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(label_operator), captured_operator)
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(label_held), captured_held)

/datum/prompt/text/hand_labeler_label/recheck_extra()
	if((label_operator_expected && QDELETED(label_operator)) || (label_held_expected && QDELETED(label_held)))
		return "gone"
	var/obj/item/hand_labeler/labeler = owner
	if(!istype(labeler) || !labeler.mode)
		return "labeler is switched off"
