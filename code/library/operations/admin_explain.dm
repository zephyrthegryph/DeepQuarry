// ---- the admin verbs ----
// "Explain Type" (the merged table of a type, each entry with its file:line), "Explain Interaction" (every candidate of a click on a thing and the filter
// that dropped each), "List Pending Ops" (every wait in the world) and, in code/engine/declare/explain.dm, "List Activations".

ADMIN_VERB_AND_CONTEXT_MENU(e2_explain_type, R_DEBUG, "Explain Type", "The merged declaration table of a thing's type: every capability and entry, with the file and line that declared it.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	to_chat(user, "<b>Table of [target.type]</b><br>[replacetext(explain_type(target.type) || "no table", "\n", "<br>")]")

ADMIN_VERB_AND_CONTEXT_MENU(e2_explain_interaction, R_DEBUG, "Explain Interaction", "Every candidate op of a click on a thing with what you hold, the filter that dropped each, and the winner.", ADMIN_CATEGORY_DEBUG, atom/target in view())
	var/mob/actor = user.mob
	if(!actor)
		return
	to_chat(user, "<b>Click on [target] ([target.type])</b><br>[replacetext(explain_click(actor, target, actor.held_for_ops(), GESTURE_CLICK), "\n", "<br>")]")

ADMIN_VERB(e2_list_pending_ops, R_DEBUG, "List Pending Ops", "Every op that is waiting in the world: who, what, which step, and the request it is waiting on.", ADMIN_CATEGORY_DEBUG)
	to_chat(user, "<b>Pending ops</b><br>[replacetext(op_pending_all_text(), "\n", "<br>")]")
