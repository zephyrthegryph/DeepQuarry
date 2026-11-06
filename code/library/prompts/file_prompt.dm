// The file prompt kind (doc/rewrite/final_api.html, section 13 "Requests, prompts and workflows (X3)"): the answerer sends a file from their own computer.
//
//   asks(/datum/prompt/file, fields = list("question" = "Choose a circuit file.", "extensions" = list("json"), "max_bytes" = 262144), step = "upload")
//   open_request(src, /datum/prompt/file, PROC_REF(uploaded), answerer = M, question = "...", extensions = list("png"))
//
// The answer (A.answer.value) is the file. BYOND hands a client's file over only through the input() dialog, which waits for the client, so this kind is the one
// place that dialog runs (prompt_file_dialog): the request is opened and returns at once, and the dialog's result comes back through prompt_window_answer() or
// prompt_window_closed() like a tgui window's, meeting the same normalize() and refusal(). An answer that arrives after the request ended (it timed out, or its
// owner went) is dropped. A prompt with no client to ask (a test driver, an AI) is answered with request_answer(), as any prompt is.
//
// Docs: doc/rewrite/proposals/nonblocking_ui.md.

/// A file from the answerer's computer.
/datum/prompt/file
	question = "Choose a file to upload."
	timeout = 5 MINUTES
	/// The extensions accepted, lower case without the dot (null: any).
	var/list/extensions
	/// The largest file accepted, in bytes (0: no limit).
	var/max_bytes = 0

/datum/prompt/file/normalize(given)
	return isfile(given) ? given : null

/datum/prompt/file/refusal(given)
	if(!isfile(given))
		return "that is not a file"
	if(max_bytes && length(given) > max_bytes)
		return "that file is larger than [max_bytes] bytes"
	if(length(extensions))
		var/list/parts = splittext("[given]", ".")
		var/extension = length(parts) > 1 ? lowertext(parts[length(parts)]) : ""
		if(!(extension in extensions))
			return "that file must be one of: [english_list(extensions)]"
	return null

/// The dialog is shown to the answerer; nothing else is. A prompt with no client waits for request_answer().
/datum/prompt/file/begin()
	var/mob/user = answerer
	if(!istype(user) || !user.client)
		return
	log_game("prompt: [type] file dialog opened for [key_name(user)]")
	prompt_file_dialog(src, user)

/// A refused file asks again, after saying why.
/datum/prompt/file/reopen()
	if(!is_open())
		return
	begin()

/datum/prompt/file/presentation_refused(mob/user, reason)
	to_chat(user, span_warning("[capitalize(reason)]."))

/// The one place the file dialog runs: input() waits for the client, so this proc is not waited on. It ends with the file as the prompt's answer, or with the
/// prompt cancelled when the dialog was dismissed.
/proc/prompt_file_dialog(datum/prompt/file/P, mob/user)
	set waitfor = FALSE // ALLOW(scheduler): the one proc that runs BYOND's input() as file dialog, the only way to receive a client file; the request returns at once and the answer re-enters through prompt_window_answer()
	var/title = P.title || "Upload file"
	var/question = P.question
	var/picked = input(user, question, title) as null|file // ALLOW(scheduler): the file dialog itself: BYOND offers no other way to receive a client file
	if(QDELETED(P) || !P.is_open())
		log_game("prompt: [P?.type] file answer dropped: the request ended while the dialog was open")
		return
	if(isnull(picked))
		log_game("prompt: [P.type] file dialog dismissed by [key_name(user)]")
		prompt_window_closed(P)
		return
	log_game("prompt: [P.type] file received from [key_name(user)] ([length(picked)] bytes)")
	prompt_window_answer(P, picked)
