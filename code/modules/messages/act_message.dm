// Message templates runtime (doc/rewrite/systems.md §15). See code/__defines/messages.dm.

/// The /datum/msg singletons, by type.
GLOBAL_LIST_EMPTY(msg_defs)

/**
 * A declared message template (a DEF singleton: never mutated, shared by every sender).
 * `self` goes to the actor, `others` to the people who see it, `blind` to those who can't.
 * Each is wrapped in `span_class` when shown ("notice" -> span_notice); null leaves it raw.
 * Subtypes whose wording depends on the call override texts().
 */
/datum/msg
	var/self
	var/others
	var/blind
	var/span_class = "notice"
	/// Range for the others line.
	var/range

/// The lines for this call as list(self, others, blind), still holding tokens.
/datum/msg/proc/texts(atom/user, atom/target, obj/item/item)
	return list(self, others, blind)

/// The singleton for a template type.
/proc/msg_def(msg_type)
	var/datum/msg/def = GLOB.msg_defs[msg_type]
	if(!def)
		if(!ispath(msg_type, /datum/msg))
			CRASH("msg_def: [msg_type] is not a /datum/msg type")
		def = new msg_type
		GLOB.msg_defs[msg_type] = def
	return def

/// Wraps text in a span class, or leaves it as is.
/proc/msg_span(text, span_class)
	if(!text || !span_class)
		return text
	return "<span class='[span_class]'>[text]</span>"

/// The \the / \The form of an atom's name.
/proc/msg_name(atom/A, capital)
	if(isnull(A))
		return ""
	if(!isatom(A))
		return "[A]"
	return capital ? "\The [A]" : "\the [A]"

/// Fills the tokens of one line. A token that opens the line (after any tags) is capitalised.
/proc/msg_fill(text, atom/user, atom/target, obj/item/item)
	if(!text)
		return text
	if(!findtext(text, "%"))
		return text
	var/static/regex/lead = regex(@"^((?:<[^>]*>|\s)*)%(U|T|I)%")
	if(lead.Find(text))
		var/atom/first
		switch(lead.group[2])
			if("U")
				first = user
			if("T")
				first = target
			if("I")
				first = item
		text = lead.group[1] + msg_name(first, TRUE) + copytext(text, length(lead.match) + 1)
	text = replacetext(text, "%U%", msg_name(user))
	text = replacetext(text, "%T%", msg_name(target))
	text = replacetext(text, "%I%", msg_name(item))
	if(findtext(text, "%") && istype(user))
		text = replacetext(text, "%THEY%", user.p_they())
		text = replacetext(text, "%They%", user.p_They())
		text = replacetext(text, "%THEM%", user.p_them())
		text = replacetext(text, "%Them%", user.p_Them())
		text = replacetext(text, "%THEIRS%", user.p_theirs())
		text = replacetext(text, "%THEIR%", user.p_their())
		text = replacetext(text, "%Their%", user.p_Their())
		text = replacetext(text, "%THEMSELVES%", user.p_themselves())
		text = replacetext(text, "%THEYRE%", user.p_theyre())
		text = replacetext(text, "%Theyre%", user.p_Theyre())
		text = replacetext(text, "%THEYVE%", user.p_theyve())
		text = replacetext(text, "%ES%", user.p_es())
		text = replacetext(text, "%S%", user.p_s())
	return text

/**
 * An action seen from two sides: `user` reads `self`, everyone else in `range` who can see
 * reads `others`, and those who can't see get `blind`. Any line may be null. A non-mob user
 * (a machine acting) only has the others and blind lines. `exclude` lists mobs that see none of it.
 * `runemessage` is the chat bubble shown over `user` to those who see it (tokens are filled);
 * null keeps the default (none for a mob, the eye glyph for anything else).
 */
/proc/act_message(atom/user, atom/target, self, others, blind, range = world.view, obj/item/item, list/exclude, runemessage)
	if(!user)
		return
	self = msg_fill(self, user, target, item)
	others = msg_fill(others, user, target, item)
	blind = msg_fill(blind, user, target, item)
	runemessage = msg_fill(runemessage, user, target, item)
	if(ismob(user))
		var/mob/M = user
		if(others || blind)
			M.visible_message(others, self, blind, exclude ? exclude.Copy() : null, range, runemessage)
		else if(self)
			to_chat(M, self)
		return
	if(!(others || blind))
		return
	if(runemessage)
		user.visible_message(others, blind, exclude ? exclude.Copy() : null, range, runemessage)
	else
		user.visible_message(others, blind, exclude ? exclude.Copy() : null, range)

/// act_message() with a declared template (a /datum/msg type). Null msg_type sends nothing.
/proc/act_message_t(atom/user, atom/target, msg_type, obj/item/item, range)
	if(!msg_type || !user)
		return
	var/datum/msg/def = msg_def(msg_type)
	var/list/lines = def.texts(user, target, item)
	act_message(user, target, msg_span(lines[1], def.span_class), msg_span(lines[2], def.span_class), \
		msg_span(lines[3], def.span_class), range || def.range || world.view, item)
