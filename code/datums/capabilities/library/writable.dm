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

/proc/cap_writable(max_length = MAX_PAPER_MESSAGE_LEN, pen_types = /obj/item/pen, written_state, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/writable/C = new
	C.max_length = max_length
	C.pen_types = pen_types
	C.written_state = written_state
	cap_gating(C, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered)
	return C

/datum/capability/writable/interactions(atom/holder)
	var/datum/interaction/capability/write = adopt_entry(cap_use_on("Write", pen_types, TYPE_PROC_REF(/atom, cap_writable_write), needs = TYPE_PROC_REF(/atom, cap_writable_has_space), else_say = "there's no room left to write on it", works_broken = TRUE, works_unpowered = TRUE, priority = WRITABLE_PRIORITY))
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

/datum/capability/writable/ui_data(atom/holder, mob/user, list/data)
	data["written"] = cap_writable_text(holder)
	data["writable_left"] = cap_writable_space(holder)

/// A's written text (HTML), or null.
/proc/cap_writable_text(atom/A)
	var/datum/capability/writable/C = cap_of(A, /datum/capability/writable)
	if(!C)
		return null
	var/datum/cap_writable_data/D = A.cap_data?[C.key]
	return D?.text

/// Visible characters A still takes.
/proc/cap_writable_space(atom/A)
	var/datum/capability/writable/C = cap_of(A, /datum/capability/writable)
	if(!C)
		return 0
	var/datum/cap_writable_data/D = A.cap_data?[C.key]
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
	var/datum/cap_writable_data/D = A.cap_data?[C?.key]
	if(!D?.text)
		return
	D.text = null
	D.used = 0
	changed(A, CHANGE_CAPABILITY)

/atom/proc/cap_writable_has_space(mob/user, obj/item/held)
	return cap_writable_space(src) > 0

/atom/proc/cap_writable_write(mob/user, obj/item/held)
	var/text = ask_text(user, "What would you like to write?", "Write", max_length = cap_writable_space(src), multiline = TRUE)
	if(!text)
		return UI_REFUSED
	if(!cap_writable_add(src, text, held, user))
		return refuse(user, "There's no room left to write on \the [src].")
	play_sfx(src, SFX_BUREAUCRACY_PEN, 0.5)
	act_message(user, src, self = span_notice("You write on %T%."), others = span_notice("%U% writes something on %T%."), item = held)
	return TRUE

/// Paper keeps its own window: the pen opens it in the write view (its fields and signatures).
/obj/item/paper/cap_writable_write(mob/user, obj/item/held)
	if(icon_state == "scrap")
		return refuse(user, "\The [src] is too crumpled to write on.")
	can_read_view = TRUE
	tgui_view = "write"
	tgui_interact(user)
	return TRUE

#undef WRITABLE_PRIORITY
