// Content-aware message rendering and delivery.

/// The lines for this call as list(self, others, blind), still holding tokens.
/datum/msg/proc/texts(atom/user, atom/target, obj/item/item)
	return list(self, others, blind)

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

/// The stand-in for a literal % inside a line (a private-use character); msg_fill() restores it.
/proc/msg_percent_mark()
	var/static/mark = ascii2text(0xE025)
	return mark

/**
 * Marks free text (anything a player typed: emotes, labels) as literal, so a `%U%` in it is shown
 * as typed instead of being filled. Use it through MSG_LITERAL(), and only in the text arguments
 * of act_message(): msg_fill() is what turns the marks back into `%`.
 */
/proc/msg_literal(text)
	if(!istext(text) || !findtext(text, "%"))
		return text
	return replacetext(text, "%", msg_percent_mark())

/// Turns msg_literal()'s marks back into %.
/proc/msg_unmark(text)
	if(!istext(text))
		return text
	var/mark = msg_percent_mark()
	if(!findtext(text, mark))
		return text
	return replacetext(text, mark, "%")

/// The text for one token name (the part between the %s), or null when it is not a token.
/proc/msg_token(token, atom/user, atom/target, obj/item/item, capital)
	switch(token)
		if("U")
			return msg_name(user, capital)
		if("T")
			return msg_name(target, capital)
		if("I")
			return msg_name(item, capital)
	if(!istype(user))
		return null
	switch(token)
		if("THEY")
			return user.p_they()
		if("They")
			return user.p_They()
		if("THEM")
			return user.p_them()
		if("Them")
			return user.p_Them()
		if("THEIRS")
			return user.p_theirs()
		if("THEIR")
			return user.p_their()
		if("Their")
			return user.p_Their()
		if("THEMSELVES")
			return user.p_themselves()
		if("THEYRE")
			return user.p_theyre()
		if("Theyre")
			return user.p_Theyre()
		if("THEYVE")
			return user.p_theyve()
		if("ES")
			return user.p_es()
		if("S")
			return user.p_s()
	return null

/**
 * Fills the tokens of one line in a single left-to-right pass: substituted text (a name, a
 * pronoun) is never scanned again, so a name holding "%T%" stays as it is. A U/T/I token that
 * opens the line (after any tags or spaces) is capitalised. MSG_LITERAL() marks become % last.
 */
/proc/msg_fill(text, atom/user, atom/target, obj/item/item)
	if(!text)
		return text
	if(!findtext(text, "%"))
		return msg_unmark(text)
	var/static/regex/lead = regex(@"^(?:<[^>]*>|\s)*")
	var/static/regex/tok = regex(@"%([A-Za-z]+)%")
	var/cap_at = lead.Find(text) ? length(lead.match) + 1 : 1
	var/out = ""
	var/pos = 1
	while(tok.Find(text, pos))
		var/at = tok.index
		var/value = msg_token(tok.group[1], user, target, item, at == cap_at)
		if(isnull(value))
			// Not a token ("50%of%"): keep the first % and look again just past it.
			out += copytext(text, pos, at + 1)
			pos = at + 1
			continue
		out += copytext(text, pos, at) + value
		pos = at + length(tok.match)
	out += copytext(text, pos)
	return msg_unmark(out)

/**
 * An action seen from two sides: `user` reads `self`, everyone else in `range` who can see
 * reads `others`, and those who can't see get `blind`. Any line may be null. A non-mob user
 * (a machine acting) only has the others and blind lines. `exclude` lists mobs that see none of it.
 * `runemessage` is the chat bubble shown over `user` to those who see it (tokens are filled);
 * null keeps the default (none for a mob, the eye glyph for anything else).
 */
/proc/act_message(atom/user, atom/target, self, others, blind, range = world.view, obj/item/item, list/exclude, runemessage)
	OP_PURE_GUARD("an act message was spoken")
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
	OP_PURE_GUARD("an act message was spoken")
	if(!msg_type || !user)
		return
	var/datum/msg/def = msg_def(msg_type)
	var/list/lines = def.texts(user, target, item)
	act_message(user, target, msg_span(lines[1], def.span_class), msg_span(lines[2], def.span_class), \
		msg_span(lines[3], def.span_class), range || def.range || world.view, item)
