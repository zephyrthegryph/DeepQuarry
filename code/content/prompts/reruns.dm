// Shared helpers of the question layer (doc/rewrite/final_api.html section 13, "Requests, prompts and workflows"). Every question is a
// /datum/prompt request (open_request()); a question that asks several things in a row is a question sequence (sequence.dm), an op asks
// with asks(). What is left here is the weak handle a question holds its asker and subject by, and the shared questions.

// ---------------------------------------------------------------- weak arguments

/// A value held while a question is open: a client as its ckey, a datum as a handle, anything else as it is.
/proc/rerun_wrap(value)
	if(istype(value, /client))
		var/client/C = value
		return "ckey:[C.ckey]"
	if(isdatum(value))
		return list("rerun_h" = ref_token(value))
	return value

/proc/rerun_unwrap(value)
	if(istext(value) && copytext(value, 1, 6) == "ckey:")
		return GLOB.directory[copytext(value, 6)]
	if(islist(value) && length(value) == 1 && value["rerun_h"])
		return resolve_token(value["rerun_h"])
	return value

/// TRUE when `wrapped` held a datum or client (so a null unwrap means it is gone).
/proc/rerun_was_ref(wrapped)
	return islist(wrapped) || (istext(wrapped) && copytext(wrapped, 1, 6) == "ckey:")

// ---------------------------------------------------------------- shared questions

/// A name typed into one of the asker's vars (a bot assembly's created_name, a label). The user must still be next to the atom and able.
/datum/prompt/text/name_var
	name_text = TRUE
	encode = FALSE
	ask_flags = ASK_ADJACENT | ASK_CAPABLE
	max_len = MAX_NAME_LEN
	/// The var of the asking atom the name goes into.
	var/var_name

/// Asks for a new name and stores it in `var_name`.
/atom/proc/ask_name_var(mob/user, var_name = "created_name", message = "Enter new robot name", max_length = MAX_NAME_LEN)
	open_request(src, /datum/prompt/text/name_var, PROC_REF(name_var_entered), answerer = user, question = message, title = name, default = vars[var_name], max_len = max_length, var_name = var_name)

/atom/proc/name_var_entered(datum/act/request/A)
	var/datum/prompt/text/name_var/asked = A.answer
	if(!asked)
		return
	var/value = sanitizeSafe(asked.value, asked.max_len)
	if(value)
		vars[asked.var_name] = value // ALLOW(api): ask_name_var() writes the var its caller named

/// The types under `root` whose path contains `text` (a type picker's matches).
/proc/typepaths_matching(text, root)
	READS_FROM() // reads the type tree, which no state changes at run time
	var/list/matches = list()
	for(var/path in typesof(root))
		if(findtext("[path]", text))
			matches += path
	return matches
