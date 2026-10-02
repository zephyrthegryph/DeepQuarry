// Examine (doc/rewrite/final_api.html, section 13 "Examine"): examine_line(text | PROC_REF, when =) entries on a type or a capability, collected on demand.
//
//   examine_line("It is heavy.")                          a fixed line
//   examine_line(MSG(cover/open_examine), when = COVER_OPEN)   a declared message (its self text), only while a key or condition holds
//   examine_line(PROC_REF(fill_text))                      x(datum/act/A) returns text or a list of text; A.actor is the examiner, A.holder the examined
//   examine_line(CAP_PROC(count_text))                     the same on the capability datum (A.cap)
//
// Capabilities contribute their own lines and the engine adds them in one list: the type's own lines first in table order, then the lines of
// what is granted to the instance, in attach order. `examine_collect()` is that list; /atom/proc/examine_lines() appends it to what the legacy
// capabilities say. The design's on-demand output `examine(datum/act/A)` keeps its legacy name (/atom/proc/examine(mob/user)) until the atom base
// is converted: a type that computes text in code overrides examine_lines() as before, or declares an examine_line(PROC_REF(x)).

/// examine_line(text | PROC_REF | CAP_PROC | MSG(x), when = condition): the holder's examine text gains this line while the condition holds.
/proc/examine_line(text, when = null)
	return entry_make(ENTRY_EXAMINE_LINE, null, list("text" = text, "when" = when))

/// One present entry in play: the entry, the capability definition that brought it (or null for the type's own), the activation, the when() blocks
/// it sits in.
/datum/present_row
	var/datum/entry/entry
	var/datum/capability/def
	var/datum/activation/activation
	var/list/whens

/// The entries of `kind` that apply to `holder` now, in order: the compiled table's (a type-level capability's included), then the live,
/// running activations that are not type-level, each with the capability that brought it. The when() blocks are not evaluated here.
/proc/present_rows(datum/holder, kind)
	. = list()
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, kind))
		var/datum/present_row/R = new
		R.entry = C.item // ALLOW(ownership): a transient record of one collection: dropped with it
		R.def = C.owner ? T.caps[C.owner] : null // ALLOW(ownership): a transient record of one collection: dropped with it
		R.whens = C.whens // ALLOW(ownership): a transient record of one collection: dropped with it
		. += R
	for(var/datum/activation/A as anything in holder.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		for(var/datum/centry/C as anything in activation_plan(A.def))
			var/datum/entry/E = C.item
			if(!istype(E) || E.kind != kind)
				continue
			var/datum/present_row/R = new
			R.entry = E // ALLOW(ownership): a transient record of one collection: dropped with it
			R.def = A.def // ALLOW(ownership): a transient record of one collection: dropped with it
			R.activation = A // ALLOW(ownership): a transient record of one collection: dropped with it
			R.whens = C.whens // ALLOW(ownership): a transient record of one collection: dropped with it
			. += R

/// A context for evaluating a present row's condition or text proc: holder, capability, activation, and the examiner as the actor.
/proc/present_context(datum/holder, datum/present_row/R, mob/examiner)
	RETURN_TYPE(/datum/act/op)
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder // ALLOW(ownership): a pooled transient: reset on release
	A.cap = R?.def // ALLOW(ownership): a pooled transient: reset on release
	A.activation = R?.activation // ALLOW(ownership): a pooled transient: reset on release
	A.actor = examiner // ALLOW(ownership): a pooled transient: reset on release
	A.target = holder // ALLOW(ownership): a pooled transient: reset on release
	return A

/// Do the when() blocks around a row and its own `when` argument all hold? Evaluated when read (a condition used for matching).
/proc/present_row_holds(datum/holder, datum/present_row/R, datum/act/op/A)
	for(var/datum/entry/W as anything in R.whens)
		if(!op_cond(A, W.args["cond"]))
			return FALSE
	return op_cond(A, R.entry.args["when"])

/// The examine lines the engine adds to `holder` for `examiner`: a list of text, empty when nothing is declared.
/proc/examine_collect(datum/holder, mob/examiner)
	RETURN_TYPE(/list)
	. = list()
	if(!holder || QDELETED(holder))
		return
	var/datum/type_table/T = table_of(holder)
	if(!length(T.items) && !length(holder.rx?.activations))
		return
	for(var/datum/present_row/R as anything in present_rows(holder, ENTRY_EXAMINE_LINE))
		var/datum/act/op/A = present_context(holder, R, examiner)
		if(present_row_holds(holder, R, A))
			examine_row_text(A, R.entry.args["text"], .)
		A.release()

/// Adds the text of one examine_line to `into`: a text, a declared message, or a handler's answer (text or a list of text).
/proc/examine_row_text(datum/act/op/A, source, list/into)
	if(isnull(source))
		return
	if(ispath(source, /datum/msg))
		var/datum/msg/def = msg_def(source)
		if(def?.self)
			into += def.self
		return
	if(istext(source) && (copytext(source, 1, 5) == "cap:" || (A.holder && hascall(A.holder, source))))
		var/answer = op_call(A, source)
		if(islist(answer))
			for(var/line in answer)
				if(istext(line) && length(line))
					into += line
		else if(istext(answer) && length(answer))
			into += answer
		return
	if(istext(source) && length(source))
		into += source
