// Debugging automatic behaviour (doc/rewrite/dx_conventions.md, M10): "why was this refused?" walks
// every interaction entry of an atom for the admin's mob and prints the gate chain's answer; "why did
// this redraw?" traces the next marks of an atom with where they came from.

ADMIN_VERB_AND_CONTEXT_MENU(dx_why_refused, R_DEBUG, "Why Refused", "Every interaction of an atom, and why each is refused for you now.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	var/mob/actor = user.mob
	var/obj/item/held = actor.get_active_hand()
	var/list/lines = list("<b>Interactions of [target] ([target.type]) for [actor], holding [held || "nothing"]</b>")
	for(var/datum/interaction/I as anything in interaction_candidates(target) + cap_extra_interactions(target))
		if(!I.applies_to(target))
			lines += "[I.name] ([I.id]): not offered on this instance"
			continue
		var/reason = I.why_not(actor, target, held)
		lines += "[I.name] ([I.id]): [reason ? "refused: [reason]" : "allowed"]"
		if(istype(I, /datum/interaction/capability))
			var/datum/interaction/capability/E = I
			lines += "&nbsp;&nbsp;gating: behind=[E.behind] locked_by=[E.locked_by] needs=[json_encode(E.needs)] works_broken=[E.works_broken] works_unpowered=[E.works_unpowered] cap_state=[capability_bits(target)] powered=[target.cap_powered()]"
	to_chat(user, jointext(lines, "<br>"))

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
