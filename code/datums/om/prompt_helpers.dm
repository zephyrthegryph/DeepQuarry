// Object-model core: small shared om_prompt continuations (doc/rewrite/object_model_core.md §4.11).
// Sites that asked the same question the same way share one of these instead of each writing
// its own continuation proc.

/// Asks for a new name and stores it in `var_name` (a bot assembly's created_name, a label).
/// The answer is re-checked: the user must still be next to or holding `src`.
/atom/proc/ask_name_var(mob/user, var_name = "created_name", message = "Enter new robot name", max_length = MAX_NAME_LEN)
	om_prompt(src, user, list("kind" = "text", "message" = message, "title" = name, "default" = vars[var_name], "max_length" = max_length, "encode" = FALSE, "requires" = PROMPT_ADJACENT, "data" = list("var" = var_name, "len" = max_length)), PROC_REF(name_var_entered))

/atom/proc/name_var_entered(mob/user, value, datum/om/prompt/ask)
	value = sanitizeSafe(value, ask.get("len"))
	if(value)
		vars[ask.get("var")] = value
