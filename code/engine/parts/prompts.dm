// The prompt kinds an op's workflow can ask (doc/rewrite/final_api.html, section 13 "Requests, prompts and workflows (X3)"). A prompt is a request a
// player answers; its answer is the uniform `value` field. E2 declares the few kinds the engine itself uses (confirms() is
// asks(/datum/prompt/yes_no, question = "text")); the library (phase 2) declares the rest.

/datum/prompt
	/// What the answerer is asked.
	var/question
	/// The answer, once answered: the uniform value field every prompt kind reads it from.
	var/value

/// confirms("text"): a yes or no. "No" ends the op and nothing is spent.
/datum/prompt/yes_no
	question = "Are you sure?"
	timeout = 30 SECONDS

/// A line of text.
/datum/prompt/text
	question = "Enter text."
	timeout = 60 SECONDS

/// A number.
/datum/prompt/number
	question = "Enter a number."
	timeout = 60 SECONDS

/datum/request
	/// The workflow step name an asks() gave this request (A.step("name")).
	var/step_name

/// One of a list of choices: the `choices` field lists them (text), and the answer's value is the text picked.
/datum/prompt/choice
	question = "Choose one."
	timeout = 60 SECONDS
	var/list/choices
