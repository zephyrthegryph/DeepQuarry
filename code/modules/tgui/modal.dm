/**
 * tgui modals
 *
 * Allows creation of modals within tgui.
 */

GLOBAL_LIST(tgui_modals)

/**
 * Modal actions: act_<action> procs (doc/rewrite/dx_conventions.md §5). Every host has them; a host's modal opens through its op
 * bound to "modal:<id>" (an asks() question shown inline), and the answer goes to the current modal's delegate.
 * `id` is the modal's text id, `answer` the modal's answer text after the current modal's preprocess_answer().
 */
/datum/proc/act_modal_open(mob/user, id, arguments)
	id = ui_text(id, 64)
	if(isnull(id))
		return refuse(user, null)
	return FALSE // a modal opens through the host's op bound to "modal:<id>" (asks()); nothing else opens one

/datum/proc/act_modal_answer(mob/user, id, answer, arguments)
	id = ui_text(id, 64)
	if(isnull(id))
		return refuse(user, null)
	answer = tgui_modal_preprocess_answer(src, ui_text(answer, TGUI_MODAL_INPUT_MAX_LENGTH))
	// A current modal whose delegate handled the answer needs nothing more.
	var/delegated = tgui_modal_answer(src, id, answer)
	// A question of an op (asks(..., inline)) that refused the answer stays open for another try: answered, it is gone already.
	if(istype(LAZYACCESS(GLOB.tgui_modals, REF(src)), /datum/tgui_modal/prompt))
		return TRUE
	tgui_modal_clear(src)
	if(delegated)
		return TRUE
	return FALSE

/datum/proc/act_modal_close(mob/user, id)
	tgui_modal_clear(src)
	return TRUE

/**
 * Call this from tgui_data() to return modal information if needed

 * Arguments:
 * * source - The source datum
 */
/proc/tgui_modal_data(datum/source)
	ASSERT(istype(source))

	var/datum/tgui_modal/current = LAZYACCESS(GLOB.tgui_modals, REF(source))
	if(!current)
		return null

	return current.to_data()

/**
 * Clears the current modal for a given datum
 *
 * Arguments:
 * * source - The source datum
 */
/proc/tgui_modal_clear(datum/source)
	ASSERT(istype(source))

	LAZYINITLIST(GLOB.tgui_modals)
	var/datum/tgui_modal/previous = GLOB.tgui_modals[REF(source)]
	if(!previous)
		return FALSE

	for(var/i in 1 to length(GLOB.tgui_modals))
		var/key = GLOB.tgui_modals[i]
		if(previous == GLOB.tgui_modals[key])
			GLOB.tgui_modals.Cut(i, i + 1)
			break

	SStgui.update_uis(source)
	previous.closed()
	return TRUE

/**
 * Opens a message TGUI modal
 *
 * Arguments:
 * * source - The source datum
 * * id - The ID of the modal
 * * text - The text to display above the answers
 * * delegate - The proc to call when closed
 * * arguments - List of arguments passed to and from JS (mostly useful for chaining modals)
 */
/proc/tgui_modal_message(datum/source, id, text = "Default modal message", delegate, arguments)
	ASSERT(length(id))

	var/datum/tgui_modal/modal = new(id, text, delegate, arguments)
	return tgui_modal_new(source, modal)

/**
 * Opens a text input TGUI modal
 *
 * Arguments:
 * * source - The source datum
 * * id - The ID of the modal
 * * text - The text to display above the answers
 * * delegate - The proc to call when submitted
 * * arguments - List of arguments passed to and from JS (mostly useful for chaining modals)
 * * value - The default value of the input
 * * max_length - The maximum char length of the input
 */
/proc/tgui_modal_input(datum/source, id, text = "Default modal message", delegate, arguments, value = "", max_length = TGUI_MODAL_INPUT_MAX_LENGTH)
	ASSERT(length(id))
	ASSERT(max_length > 0)

	var/datum/tgui_modal/input/modal = new(id, text, delegate, arguments, value, max_length)
	return tgui_modal_new(source, modal)

/**
 * Opens a dropdown input TGUI modal
 *
 * Internally checks if the answer is in the list of choices.
 * Arguments:
 * * source - The source datum
 * * id - The ID of the modal
 * * text - The text to display above the answers
 * * delegate - The proc to call when submitted
 * * arguments - List of arguments passed to and from JS (mostly useful for chaining modals)
 * * value - The default value of the dropdown
 * * choices - The list of available choices in the dropdown
 */
/proc/tgui_modal_choice(datum/source, id, text = "Default modal message", delegate, arguments, value = "", choices)
	ASSERT(length(id))

	var/datum/tgui_modal/input/choice/modal = new(id, text, delegate, arguments, value, choices)
	return tgui_modal_new(source, modal)

/**
 * Registers a given modal to a source. Private.
 *
 * Arguments:
 * * source - The source datum
 * * modal - The datum/tgui_modal to register
 * * replace_previous - Whether any modal currently assigned to source should be replaced
 * * instant_update - Whether the changes should reflect immediately
 */
/proc/tgui_modal_new(datum/source, datum/tgui_modal/modal = null, replace_previous = TRUE, instant_update = TRUE)
	ASSERT(istype(source))
	ASSERT(istype(modal))

	var/datum/tgui_modal/previous = LAZYACCESS(GLOB.tgui_modals, REF(source))
	if(previous && !replace_previous)
		return FALSE

	rel_set(modal, nameof(modal.owning_source), source)

	// Previous one should get GC'd (a question it showed ends cancelled)
	LAZYSET(GLOB.tgui_modals, REF(source), modal)
	if(previous && previous != modal)
		previous.closed()
	if(instant_update)
		SStgui.update_uis(source)
	return TRUE

/**
 * Calls the source's currently assigned modal's (if there is one) on_answer() proc. Private.
 *
 * Arguments:
 * * source - The source datum
 * * id - The ID of the modal
 * * answer - The provided answer
 */
/proc/tgui_modal_answer(datum/source, id, answer = "")
	ASSERT(istype(source))

	var/datum/tgui_modal/current = LAZYACCESS(GLOB.tgui_modals, REF(source))
	if(!current)
		return FALSE

	return current.on_answer(answer)

/**
 * Passes an answer from JS through the modal's proc.
 *
 * Used namely for cutting the text short if it's longer
 * than an input modal's max_length.
 * Arguments:
 * * source - The source datum
 * * answer - The provided answer
 */
/proc/tgui_modal_preprocess_answer(datum/source, answer = "")
	ASSERT(istype(source))

	var/datum/tgui_modal/current = LAZYACCESS(GLOB.tgui_modals, REF(source))
	if(!current)
		return answer

	return current.preprocess_answer(answer)

/**
 * Modal datum (contains base information for a modal)
 */
/datum/tgui_modal
	var/tmp/datum/owning_source
	var/id
	var/text
	var/delegate
	var/list/arguments
	var/modal_type = "message"

/datum/tgui_modal/New(id, text, delegate, list/arguments)
	src.id = id
	src.text = text
	src.delegate = delegate
	src.arguments = arguments

/**
 * Called when it's time to pre-process the answer before using it
 *
 * Arguments:
 * * answer - The answer, a nullable text
 */
/datum/tgui_modal/proc/preprocess_answer(answer)
	return reject_bad_text(answer, TGUI_MODAL_INPUT_MAX_LENGTH) // bleh

/**
 * Called when a modal receives an answer
 *
 * Arguments:
 * * answer - The answer, a nullable text
 */
/datum/tgui_modal/proc/on_answer(answer)
	if(delegate)
		return call(owning_source(), delegate)(answer, arguments)
	return FALSE

/**
 * Creates a list that describes a modal visually to be passed to JS
 */
/datum/tgui_modal/proc/to_data()
	. = list()
	.["id"] = id
	.["text"] = text
	.["args"] = arguments || list()
	.["type"] = modal_type

/**
 * Input modal - has a text entry that can be used to enter an answer
 */
/datum/tgui_modal/input
	modal_type = "input"
	var/value
	var/max_length

/datum/tgui_modal/input/New(id, text, delegate, list/arguments, value, max_length)
	..(id, text, delegate, arguments)
	src.value = value
	src.max_length = max_length

/datum/tgui_modal/input/preprocess_answer(answer)
	. = ..(answer)
	if(length(answer) > max_length)
		. = copytext(., 1, max_length + 1)

/datum/tgui_modal/input/to_data()
	. = ..()
	.["value"] = value

/**
 * Choice modal - has a dropdown menu that can be used to select an answer
 */
/datum/tgui_modal/input/choice
	modal_type = "choice"
	var/choices

/datum/tgui_modal/input/choice/New(id, text, delegate, list/arguments, value, choices)
	..(id, text, delegate, arguments, value, TGUI_MODAL_INPUT_MAX_LENGTH) // Max length doesn't really matter in dropdowns, but whatever
	src.choices = choices

/datum/tgui_modal/input/choice/on_answer(answer)
	if(answer in choices) // Make sure the answer is actually in our choices!
		return ..(answer, arguments)
	return FALSE

/datum/tgui_modal/input/choice/to_data()
	. = ..()
	.["choices"] = choices

/**
 * Bento modal - Similar to choice, it displays the choices in a grid of images
 *
 * The returned answer is the index of the choice.
 */
/datum/tgui_modal/input/bento
	modal_type = "bento"
	var/choices

/datum/tgui_modal/input/bento/New(id, text, delegate, list/arguments, value, choices)
	..(id, text, delegate, arguments, text2num(value), TGUI_MODAL_INPUT_MAX_LENGTH) // Max length doesn't really matter in here, but whatever
	src.choices = choices

/datum/tgui_modal/input/bento/preprocess_answer(answer)
	return text2num(answer) || 0

/datum/tgui_modal/input/bento/on_answer(answer)
	if(answer >= 1 && answer <= length(choices)) // Make sure the answer index is actually in our indexes!
		return ..(answer, arguments)
	return FALSE

/datum/tgui_modal/input/bento/to_data()
	. = ..()
	.["choices"] = choices

//Bento modal but takes spritesheet classes as choices
/datum/tgui_modal/input/bento/spritesheet
	modal_type = "bentospritesheet"

/**
 * Boolean modal - has yes/no buttons that do different actions depending on which is pressed
 */
/datum/tgui_modal/boolean
	modal_type = "boolean"
	var/delegate_no
	var/yes_text
	var/no_text

/datum/tgui_modal/boolean/New(id, text, delegate, delegate_no, list/arguments, yes_text, no_text)
	..(id, text, delegate, arguments)
	src.delegate_no = delegate_no
	src.yes_text = yes_text
	src.no_text = no_text

/datum/tgui_modal/boolean/preprocess_answer(answer)
	return text2num(answer) || FALSE

/datum/tgui_modal/boolean/on_answer(answer)
	if(answer)
		return ..(answer, arguments)
	else if(delegate_no)
		return call(owning_source(), delegate_no)(arguments)
	return FALSE

/datum/tgui_modal/boolean/to_data()
	. = ..()
	.["yes_text"] = yes_text
	.["no_text"] = no_text

/// The modal went away without an answer (cleared, closed by the client, replaced): a question it showed ends cancelled.
/datum/tgui_modal/proc/closed()
	return

/// The owning_source this refers to (a relation view: null once that is deleted).
/datum/tgui_modal/proc/owning_source() as /datum
	return owning_source
