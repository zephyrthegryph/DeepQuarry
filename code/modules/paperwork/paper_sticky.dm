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
TRACKED(/obj/item/sticky_pad, written_text)

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

MSG_DEF_SELF(sticky_pad/banned, span_warning("You are banned from leaving persistent information across rounds."))
MSG_DEF_SELF(sticky_pad/full, span_warning("There is no room left on the pad."))

/// Old attackby with a pen: the pad may be written on by someone not banned from graffiti while it has room.
/obj/item/sticky_pad/proc/can_write(datum/act/op/A)
	return !jobban_isbanned(A.actor, JOB_GRAFFITI)

/obj/item/sticky_pad/proc/has_room(datum/act/op/A)
	return writing_space() > 0

/obj/item/sticky_pad/proc/writing_space()
	return MAX_MESSAGE_LEN - length(written_text)

/obj/item/sticky_pad/proc/write_max_len(datum/act/A)
	return writing_space()

/obj/item/sticky_pad/proc/write_name_text(datum/act/A)
	return writing_space() <= MAX_NAME_LEN

/// The answer is written when the pen is still held and in reach, and the writer able.
/obj/item/sticky_pad/proc/sticky_write(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/thing = A.held
	var/text = sanitizeSafe(A.step_value("write"), writing_space())
	if(!text || !thing || thing.loc != user || (!Adjacent(user) && loc != user) || user.incapacitated())
		return OP_PASS
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " jots a note down on %T%."))
	written_by = user.ckey
	if(written_text)
		set_written_text("[written_text] [text]")
	else
		set_written_text(text)
	changed(src)
	SStgui.update_uis(src)
	return OP_PASS

/obj/item/sticky_pad/examine(mob/user)
	. = ..()
	if(.)
		to_chat(user, span_notice("It has [papers] sticky note\s left."))

/// Old attack_hand.
/obj/item/sticky_pad/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/paper/paper = new paper_type(get_turf(src))
	paper.set_content(written_text, "sticky note")
	paper.last_modified_ckey = written_by
	paper.color = color
	set_written_text(null)
	user.put_in_hands(paper)
	to_chat(user, span_notice("You pull \the [paper] off \the [src]."))
	papers--
	if(papers <= 0)
		consume(src, user)
	else
		changed(src)
	return OP_OK

CAPABILITIES(/obj/item/sticky_pad)
	drag_onto(PROC_REF(mousedrop_input))
	op("sticky_pad_hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("sticky_pad_item", item(/obj/item/pen), label("Use"), needs(req_bool(PROC_REF(can_write), because = MSG(sticky_pad/banned)), req_bool(PROC_REF(has_room), because = MSG(sticky_pad/full))), asks(/datum/prompt/text/paperwork_review, fields = list("question" = "What would you like to write?", "max_len" = computed(PROC_REF(write_max_len)), "encode" = FALSE, "name_text" = computed(PROC_REF(write_name_text))), step = "write"), then(PROC_REF(sticky_write)))

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

// Copied from duct tape.
EXTEND_INTERACTIONS(/obj/item/paper/sticky, INTERACT_HAND_DEFAULT("Pick up", PROC_REF(sticky_pick_up)))

/// Picking a note up off a wall ends its persistence.
/obj/item/paper/sticky/proc/sticky_pick_up(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	interaction_pick_up(user, held, interaction)
	if(!istype(loc, /turf))
		reset_persistence_tracking()

/obj/item/paper/sticky/afterattack(A, mob/user, flag, params)

	if(!in_range(user, A) || istype(A, /obj/machinery/door) || crumpled)
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
