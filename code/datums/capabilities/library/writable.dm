// cap_writable(): a pen writes on the holder. The text is pencode rendered by the paper parser
// (pencode_to_html(), code/modules/paperwork/paper.dm), in the pen's colour, and kept in the
// holder's capability data up to max_length characters. On paper the pen opens the paper window in
// its write view instead, so the paper's own fields, signatures and space accounting stay in charge.
//
//	/obj/item/sign_board/capabilities()
//		. = ..()
//		. += cap_writable(max_length = 200)
//		. += cap_rename()
//
// With cap_rename() on the same type the pen writes by default and "Rename" stays in the Menu.

/// The priority of "Write" over the other pen entries (cap_rename()), so a pen click writes.
#define WRITABLE_PRIORITY 5

/datum/capability/writable
	data_type = /datum/cap_writable_data
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// Characters of visible text the holder takes in total (type default).
	var/max_length = MAX_PAPER_MESSAGE_LEN
	/// The held types that write (pens and crayons by default).
	var/pen_types = /obj/item/pen
	/// An overlay drawn while something is written, or null.
	var/written_state

/datum/cap_writable_data
	/// The written HTML, or null.
	var/text
	/// Visible characters written so far.
	var/used = 0

/proc/cap_writable(max_length = MAX_PAPER_MESSAGE_LEN, pen_types = /obj/item/pen, written_state, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/writable/C = new
	C.max_length = max_length
	C.pen_types = pen_types
	C.written_state = written_state
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/writable/interactions(atom/holder)
	// "write": a click with a pen or crayon, ahead of a rename by the same pen (WRITABLE_PRIORITY); a full page refuses.
	var/datum/interaction/capability/write = adopt_entry(lib_op("Write", GLOBAL_PROC_REF(cap_writable_write), OP_SHAPE_USE_ON, using = pen_types, key = "write", needs = GLOBAL_PROC_REF(cap_writable_has_space), else_say = "there's no room left to write on it", works_broken = TRUE, works_unpowered = TRUE, priority = WRITABLE_PRIORITY))
	return list(write)

/datum/capability/writable/examine(atom/holder, mob/user)
	var/text = cap_writable_text(holder)
	if(!text)
		return null
	if(!user || get_dist(user, holder) > 1)
		return list("Something is written on it. You have to go closer to read it.")
	return list("It reads: [text]")

/datum/capability/writable/draw(atom/holder, datum/look/look)
	look.part(written_state, !!(!isnull(cap_writable_text(holder))))

/datum/capability/writable/legacy_ui_data(atom/holder, mob/user, list/data)
	data["written"] = cap_writable_text(holder)
	data["writable_left"] = cap_writable_space(holder)

/// A's written text (HTML), or null.
/proc/cap_writable_text(atom/A)
	var/datum/capability/writable/C = cap_of(A, /datum/capability/writable)
	if(!C)
		return null
	var/datum/cap_writable_data/D = capability_data(A)?[C.key]
	return D?.text

/// Visible characters A still takes.
/proc/cap_writable_space(atom/A)
	var/datum/capability/writable/C = cap_of(A, /datum/capability/writable)
	if(!C)
		return 0
	var/datum/cap_writable_data/D = capability_data(A)?[C.key]
	return max(0, C.max_length - (D ? D.used : 0))

/**
 * Writes pencode `text` on A with pen P as user: rendered by the paper parser, cut to the space
 * left. Returns the HTML written, or null when nothing fit.
 */
/proc/cap_writable_add(atom/A, text, obj/item/pen/P, mob/user)
	var/datum/capability/writable/C = cap_of(A, /datum/capability/writable)
	var/space = cap_writable_space(A)
	if(!C || !text || space <= 0)
		return null
	text = copytext(text, 1, space + 1)
	var/html = pencode_to_html(replacetext(text, "\n", "<BR>"), P, user, istype(P, /obj/item/pen/crayon))
	var/datum/cap_writable_data/D = cap_data(A, C)
	D.text = D.text ? "[D.text]<BR>[html]" : html
	D.used += length(strip_html_properly(html))
	changed(A, CHANGE_CAPABILITY)
	return html

/// Clears what is written on A.
/proc/cap_writable_clear(atom/A)
	var/datum/capability/writable/C = cap_of(A, /datum/capability/writable)
	var/datum/cap_writable_data/D = capability_data(A)?[C?.key]
	if(!D?.text)
		return
	D.text = null
	D.used = 0
	changed(A, CHANGE_CAPABILITY)

/proc/cap_writable_has_space(mob/user, atom/holder, obj/item/held)
	return cap_writable_space(holder) > 0

/// Writes on holder: asks the text and adds it. Paper keeps its own window: the pen opens it in the write view (its
/// fields and signatures). A holder that writes another way declares a subtype overriding it.
/datum/capability/writable/proc/write(atom/holder, mob/user, obj/item/held)
	var/obj/item/paper/P = holder
	if(istype(P))
		if(P.crumpled)
			return refuse(user, "\The [P] is too crumpled to write on.")
		P.can_read_view = TRUE
		P.tgui_view = "write"
		P.tgui_interact(user)
		return TRUE
	var/text = ask_text(user, "What would you like to write?", "Write", max_length = cap_writable_space(holder), multiline = TRUE)
	if(!text)
		return UI_REFUSED
	if(!cap_writable_add(holder, text, held, user))
		return refuse(user, "There's no room left to write on \the [holder].")
	play_sfx(holder, SFX_BUREAUCRACY_PEN, 0.5)
	act_message(user, holder, self = span_notice("You write on %T%."), others = span_notice("%U% writes something on %T%."), item = held)
	return TRUE

/// The write op's handler: its capability's write().
/proc/cap_writable_write(atom/holder, mob/user, obj/item/held)
	var/datum/capability/writable/C = cap_of(holder, /datum/capability/writable)
	return C ? C.write(holder, user, held) : FALSE

#undef WRITABLE_PRIORITY
