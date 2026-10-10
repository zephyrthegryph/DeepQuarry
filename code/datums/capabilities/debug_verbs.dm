// Debugging automatic behaviour (doc/rewrite/dx_conventions.md, M10): "why did this redraw?" traces the next
// marks of an atom with where they came from. (Why an op is refused: the admin explain tools, code/library/operations/admin_explain.dm.)

ADMIN_VERB_AND_CONTEXT_MENU(dx_why_redrawn, R_DEBUG, "Why Redrawn", "Traces the next marks of an atom (who called changed()), or shows the trace so far.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	var/ref_text = REF(target)
	if(ref_text in GLOB.refresh_traced)
		var/list/lines = GLOB.refresh_traced[ref_text]
		to_chat(user, "<b>Marks of [target] ([target.type]):</b><br>[islist(lines) && length(lines) ? jointext(lines, "<br>") : "none yet"]<br>look key: [target.rx?.look_key]")
		GLOB.refresh_traced -= ref_text
		to_chat(user, "Tracing stopped.")
		return
	GLOB.refresh_traced[ref_text] = list()
	to_chat(user, "Tracing the marks of [target]. Use the verb again to see them and stop.")
