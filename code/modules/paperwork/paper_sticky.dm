/obj/item/sticky_pad/get_mechanics_info(list/additional_information)
	return ..(list("Sticky notes stuck to surfaces/objects persist for 50 rounds.") + additional_information)

/obj/item/sticky_pad
	name = "sticky note pad"
	desc = "A pad of densely packed sticky notes."
	color = COLOR_YELLOW
	icon = 'icons/obj/stickynotes.dmi'
	icon_state = "pad_full"
	item_state = "paper"
	w_class = ITEMSIZE_SMALL

	var/papers = 50
	var/written_text
	var/written_by
	var/paper_type = /obj/item/paper/sticky

/// The look (the draw sweep: from its template).
/obj/item/sticky_pad/draw(datum/look/look)
	..()
	look.state("[appearance_fill()][written_text ? "_writing" : ""]")

/// The pad state for how many papers are left.
/obj/item/sticky_pad/proc/appearance_fill()
	if(papers <= 15)
		return "pad_empty"
	if(papers <= 50)
		return "pad_used"
	return "pad_full"

/// Old attackby.
/obj/item/sticky_pad/proc/interaction_item(mob/user, obj/item/thing, datum/interaction/interaction)
	return paperwork_sticky_write_stage(user, thing, interaction)

/obj/item/sticky_pad/proc/paperwork_sticky_write_stage(mob/user, obj/item/thing, datum/interaction/interaction, paperwork_answer, paperwork_answer_ready = FALSE)
	if(istype(thing, /obj/item/pen))

		if(jobban_isbanned(user, JOB_GRAFFITI))
			to_chat(user, span_warning("You are banned from leaving persistent information across rounds."))
			return INTERACTION_HANDLED_PASS

		var/writing_space = MAX_MESSAGE_LEN - length(written_text)
		if(writing_space <= 0)
			to_chat(user, span_warning("There is no room left on \the [src]."))
			return INTERACTION_HANDLED_PASS
		if(!paperwork_answer_ready)
			open_request(src, /datum/prompt/text/paperwork_review, PROC_REF(paperwork_sticky_write_answered), answerer = user, paperwork_operator = user, paperwork_held = thing, paperwork_interaction = interaction, question = "What would you like to write?", max_len = writing_space, encode = FALSE, name_text = (writing_space <= MAX_NAME_LEN))
			return TRUE
		var/_answer_k37 = paperwork_answer
		if(isnull(_answer_k37))
			return TRUE
		var/text = sanitizeSafe(_answer_k37, writing_space)
		if(!text || thing.loc != user || (!Adjacent(user) && loc != user) || user.incapacitated())
			return INTERACTION_HANDLED_PASS
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " jots a note down on %T%."))
		written_by = user.ckey
		if(written_text)
			written_text = "[written_text] [text]"
		else
			written_text = text
		changed(src)
		return INTERACTION_HANDLED_PASS
	return FALSE

/obj/item/sticky_pad/examine(mob/user)
	. = ..()
	if(.)
		to_chat(user, span_notice("It has [papers] sticky note\s left."))

DECLARE_INTERACTIONS(/obj/item/sticky_pad, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/item/sticky_pad/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/paper/paper = new paper_type(get_turf(src))
	paper.set_content(written_text, "sticky note")
	paper.last_modified_ckey = written_by
	paper.color = color
	written_text = null
	user.put_in_hands(paper)
	to_chat(user, span_notice("You pull \the [paper] off \the [src]."))
	papers--
	if(papers <= 0)
		consume(src, user)
	else
		changed(src)
	return TRUE

CAPABILITIES(/obj/item/sticky_pad)
	drag_onto(PROC_REF(mousedrop_input))

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/sticky_pad/proc/mousedrop_input(datum/act/input/A)
	return pickup_with_actor(A.actor, A.over)

/obj/item/sticky_pad/proc/pickup_with_actor(mob/user, mob/destination)
	if(user && user == destination && !(user.restrained() || user.stat) && (user.contents.Find(src) || in_range(src, user)))
		if(ishuman(user))
			if( !user.get_active_hand() )		//if active hand is empty
				var/mob/living/carbon/human/H = user
				var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]

				if (H.hand)
					temp = H.organs_by_name[BP_L_HAND]
				if(temp && !temp.is_usable())
					to_chat(user, span_notice("You try to move your [temp.name], but cannot!"))
					return

				to_chat(user, span_notice("You pick up the [src]."))
				user.put_in_hands(src)

	return

CAPABILITIES(/obj/item/sticky_pad/random)
	rolls(nameof(color), pick_one(list(COLOR_YELLOW, COLOR_LIME, COLOR_CYAN, COLOR_ORANGE, COLOR_PINK)))

/obj/item/paper/sticky
	name = "sticky note"
	desc = "Note to self: buy more sticky notes."
	icon = 'icons/obj/stickynotes.dmi'
	color = COLOR_YELLOW
	slot_flags = 0

/obj/item/paper/sticky/Initialize(mapload)
	. = ..()
	dq_add_recursive_move(src)
	observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(reset_persistence_tracking)))

/obj/item/paper/sticky/proc/reset_persistence_tracking(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	SSpersistence.forget_value(src, /datum/persistent/paper/sticky)
	pixel_x = 0
	pixel_y = 0

// persistence stops tracking it.
/obj/item/paper/sticky/lifecycle_dematerialize()
	..()
	reset_persistence_tracking()

DECLARE_APPEARANCE_PROC(/obj/item/paper/sticky, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/paper/sticky/appearance_overlays()
	. = list()
	if(icon_state != "scrap")
		icon_state = info ? "paper_words" : "paper"

// Copied from duct tape.
EXTEND_INTERACTIONS(/obj/item/paper/sticky, INTERACT_HAND_DEFAULT("Pick up", PROC_REF(sticky_pick_up)))

/// Picking a note up off a wall ends its persistence.
/obj/item/paper/sticky/proc/sticky_pick_up(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	interaction_pick_up(user, held, interaction)
	if(!istype(loc, /turf))
		reset_persistence_tracking()

/obj/item/paper/sticky/afterattack(A, mob/user, flag, params)

	if(!in_range(user, A) || istype(A, /obj/machinery/door) || icon_state == "scrap")
		return

	var/turf/target_turf = get_turf(A)
	var/turf/source_turf = get_turf(user)

	var/dir_offset = 0
	if(target_turf != source_turf)
		dir_offset = get_dir(source_turf, target_turf)
		if(!(dir_offset in GLOB.cardinal))
			to_chat(user, span_warning("You cannot reach that from here."))
			return

	if(user.unEquip(src, source_turf))
		SSpersistence.track_value(src, /datum/persistent/paper/sticky)
		if(params)
			var/list/mouse_control = params2list(params)
			if(mouse_control["icon-x"])
				pixel_x = text2num(mouse_control["icon-x"]) - 16
				if(dir_offset & EAST)
					pixel_x += 32
				else if(dir_offset & WEST)
					pixel_x -= 32
			if(mouse_control["icon-y"])
				pixel_y = text2num(mouse_control["icon-y"]) - 16
				if(dir_offset & NORTH)
					pixel_y += 32
				else if(dir_offset & SOUTH)
					pixel_y -= 32

/obj/item/sticky_pad/proc/paperwork_sticky_write_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paperwork_sticky_write_apply(A)
	SStgui.update_uis(src)

/obj/item/sticky_pad/proc/paperwork_sticky_write_apply(datum/act/request/A)
	var/datum/prompt/text/paperwork_review/ask = A.answer
	return paperwork_sticky_write_stage(ask.paperwork_operator, ask.paperwork_held, ask.paperwork_interaction, ask.value, TRUE)
