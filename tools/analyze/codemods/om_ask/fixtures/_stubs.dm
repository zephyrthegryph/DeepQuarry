#define SECONDS *10
#define PROC_REF(X) (#X)
#define TYPE_PROC_REF(T, X) (#X)
#define MAX_NAME_LEN 26
#define MAX_MESSAGE_LEN 1024
#define om_ask(answerer, prompt, on_answer, params...) om_ask_begin(src, answerer, prompt, on_answer, list(params))
#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))

/proc/om_ask_begin(receiver, mob/answerer, prompt, on_answer, list/params)
	return 1

/proc/request_open(datum/owner, request_type, handler, list/fields)
	return 1

/datum/om/prompt
	var/title
	var/message
	var/mob/answerer
	var/mob/asker

/datum/om/prompt/confirm
	var/yes

/datum/om/prompt/confirm/malf

/datum/om/prompt/text
	var/text

/datum/om/prompt/number
	var/number

/datum/om/prompt/choice
	var/choice

/datum/request
	var/datum/answerer
	var/value

/datum/prompt
	parent_type = /datum/request

/datum/prompt/yes_no
/datum/prompt/text
/datum/prompt/number
/datum/prompt/choice

/datum/act
	var/datum/holder

/datum/act/request
	parent_type = /datum/act
	var/datum/request/request
	var/datum/request/answer
