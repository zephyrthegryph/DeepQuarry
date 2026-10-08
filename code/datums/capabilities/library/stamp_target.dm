// cap_stamp_target(): a rubber stamp (or a seal ring) marks the holder. Each stamp leaves its line
// (stamp_mark_text(), shared with paper) in the holder's capability data and its mark as an
// overlay, "paper_[stamp icon_state]" in the holder's icon, as paper draws it. The clown's stamp only
// works for clowns (stamp_usable_by()).
//
//	/obj/item/form/capabilities()
//		. = ..()
//		. += cap_writable()
//		. += cap_stamp_target(max_stamps = 3)

/datum/capability/stamp_target
	data_type = /datum/cap_stamp_data
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// How many stamps fit (type default); null for no limit.
	var/max_stamps
	/// The word examine uses for the holder ("This [noun] has been stamped with ...").
	var/noun = "document"
	/// Draw each stamp's mark as an overlay.
	var/draws_marks = TRUE

/datum/cap_stamp_data
	/// The stamp lines, in stamping order.
	var/list/lines
	/// The overlay state of each stamp, in stamping order.
	var/list/marks

/proc/cap_stamp_target(max_stamps, noun = "document", draws_marks = TRUE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/stamp_target/C = new
	C.max_stamps = max_stamps
	C.noun = noun
	C.draws_marks = draws_marks
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/stamp_target/interactions(atom/holder)
	// "stamp": a click with a stamp or a seal ring; with no room left, it refuses.
	var/datum/interaction/capability/stamp = adopt_entry(lib_op("Stamp", GLOBAL_PROC_REF(cap_stamp_apply), OP_SHAPE_USE_ON, using = list(/obj/item/stamp, /obj/item/clothing/accessory/ring/seal), key = "stamp", needs = GLOBAL_PROC_REF(cap_stamp_has_room), else_say = "there's no room left for another stamp", works_broken = TRUE, works_unpowered = TRUE))
	return list(stamp)

/datum/capability/stamp_target/examine(atom/holder, mob/user)
	var/datum/cap_stamp_data/D = capability_data(holder)?[key]
	if(!LAZYLEN(D?.lines))
		return null
	. = list()
	for(var/line in D.lines)
		. += span_italics(line)

/datum/capability/stamp_target/draw(atom/holder, datum/look/look)
	if(!draws_marks)
		return
	var/datum/cap_stamp_data/D = capability_data(holder)?[key]
	for(var/mark in D?.marks)
		look.overlay(mark)

/datum/capability/stamp_target/legacy_ui_data(atom/holder, mob/user, list/data)
	var/datum/cap_stamp_data/D = capability_data(holder)?[key]
	data["stamps"] = D?.lines ? D.lines.Copy() : list()

/// A's stamp lines (a copy), or an empty list.
/proc/cap_stamps_of(atom/A)
	var/datum/capability/stamp_target/C = cap_of(A, /datum/capability/stamp_target)
	var/datum/cap_stamp_data/D = capability_data(A)?[C?.key]
	return D?.lines ? D.lines.Copy() : list()

/// Adds stamp S's line and mark to A. TRUE when it went on.
/proc/cap_stamp_add(atom/A, obj/item/S)
	var/datum/capability/stamp_target/C = cap_of(A, /datum/capability/stamp_target)
	if(!C)
		return FALSE
	var/datum/cap_stamp_data/D = cap_data(A, C)
	if(!isnull(C.max_stamps) && LAZYLEN(D.lines) >= C.max_stamps)
		return FALSE
	LAZYADD(D.lines, stamp_mark_text(S, C.noun))
	LAZYADD(D.marks, "paper_[S.icon_state]")
	changed(A, CHANGE_CAPABILITY)
	return TRUE

/proc/cap_stamp_has_room(mob/user, atom/holder, obj/item/held)
	var/datum/capability/stamp_target/C = cap_of(holder, /datum/capability/stamp_target)
	var/datum/cap_stamp_data/D = capability_data(holder)?[C.key]
	return isnull(C.max_stamps) || LAZYLEN(D?.lines) < C.max_stamps

/proc/cap_stamp_apply(atom/holder, mob/user, obj/item/held)
	if(!stamp_usable_by(held, user))
		return refuse(user, "You are totally unable to use the stamp. HONK!")
	if(!cap_stamp_add(holder, held))
		return refuse(user, "There's no room left on \the [holder] for another stamp.")
	play_sfx(holder, SFX_BUREAUCRACY_STAMP)
	act_message(user, holder, self = span_notice("You stamp %T% with \the [held]."), others = span_notice("%U% stamps %T% with \the [held]."), item = held)
	return TRUE
