// The explain tools of the declaration engine (doc/rewrite/final_api.html, section 15 "Tooling and enforcement"; section 19 "E1, declarations").
// They read the compiled tables and the live activations, never the declarations again, so what they print is what the engine runs, with the
// file:line of each entry kept in every build.

/// The merged compiled table of `type`, each item tagged with its origin (file:line): one line per capability and entry, a when() block's
/// entries indented, an entry a capability brought named for it. A fresh text.
/proc/explain_type(type)
	var/datum/type_table/T = table_of_type(type)
	if(!T)
		return null
	return table_dump(T)

/// The admin verb "List Activations": every activation on an entity with its source, scope and contributions.
ADMIN_VERB_AND_CONTEXT_MENU(e1_list_activations, R_DEBUG, "List Activations", "Every activation on a thing, with its source, scope and contributions.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	to_chat(user, "<b>Activations of [target] ([target.type])</b><br>[replacetext(explain_activations(target) || "none", "\n", "<br>")]")
