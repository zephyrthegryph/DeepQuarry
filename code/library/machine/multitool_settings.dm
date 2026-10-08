// The multitool settings capability (doc/rewrite/final_api.html, section 11 "The library"): the tags, the frequency and the command a machine is set
// to with a multitool.
//
// A multitool used on the holder asks what to set (the labels of its settings, or "None"); the one picked asks its own question and sets the var.
// Each setting is its own op (`multitool_settings.set_<var>`, reached by key from the choice), so what it asks and what it needs are declared where
// the holder says it. A setting is list(label, var, kind, max, hint): kind "text" (the answer, kept when empty, cut to `max` characters) or
// "frequency" (a number the holder's set_frequency() takes, clamped to the radio band); `hint` is added to the question. A text setting goes through
// the holder's set_<var>() when it has one (a radio device re-keys itself there). An "action" setting asks nothing: list(label, PROC_REF(x), "action")
// runs the holder's x(datum/act/op/A) when it is picked (flip a direction, save the device to the multitool's buffer).
//
//   multitool_settings(list(list("Master Tag", "master_tag", "text", 30), list("Frequency", "frequency", "frequency")))

MSG_DEF_SELF(multitool_settings/nothing, "You leave it as it is.")

CAPABILITY_TYPE(multitool_settings, CAP_MULTITOOL_SETTINGS, /datum/capability/lib/multitool_settings, key = NONE, settings = null)

/datum/capability/lib/multitool_settings/entries()
	var/list/out = list(op("configure", tool(TOOL_MULTITOOL), label("Configure"), wait(0), \
		asks(/datum/prompt/choice, fields = list("question" = "What would you like to configure?", "choices" = computed(CAP_PROC(choices)), "buttons" = TRUE)), then(CAP_PROC(chosen))))
	for(var/list/setting in settings)
		var/kind = setting[3]
		if(kind == "action")
			continue
		out += op("set_[setting[2]]", ai(), wait(0), \
			asks(kind == "frequency" ? /datum/prompt/number : /datum/prompt/text, fields = list("question" = computed(CAP_PROC(question)))), then(CAP_PROC(apply)))
	return out

/// The labels of the settings, and the way out.
/datum/capability/lib/multitool_settings/proc/choices(datum/act/op/A)
	var/list/labels = list()
	for(var/list/setting in settings)
		labels += setting[1]
	labels += "None"
	return labels

/// The setting an op key names (`multitool_settings.set_<var>`).
/datum/capability/lib/multitool_settings/proc/setting_of_key(key)
	for(var/list/setting in settings)
		if(key == "multitool_settings.set_[setting[2]]")
			return setting
	return null

/datum/capability/lib/multitool_settings/proc/chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	for(var/list/setting in settings)
		if(R?.value == setting[1])
			if(setting[3] == "action")
				op_call(A, setting[2])
			else
				perform_op(A.actor, A.holder, "multitool_settings.set_[setting[2]]", null, ORIGIN_SYSTEM)
			break
	return OP_OK

/// What a setting asks: its current value, and the hint.
/datum/capability/lib/multitool_settings/proc/question(datum/act/op/A)
	var/list/setting = setting_of_key(A.key)
	if(!setting)
		return "What would you like it to be?"
	var/atom/holder = A.holder
	var/current = holder.vars[setting[2]]
	return "[holder] has a [lowertext(setting[1])] of \"[current]\". What would you like it to be?[length(setting) >= 5 && setting[5] ? " [setting[5]]" : ""]"

/datum/capability/lib/multitool_settings/proc/apply(datum/act/op/A)
	var/list/setting = setting_of_key(A.key)
	var/datum/prompt/R = A.answer
	var/atom/holder = A.holder
	if(!setting || isnull(R?.value))
		return OP_OK
	if(setting[3] == "frequency")
		var/new_frequency = text2num("[R.value]")
		if(new_frequency && hascall(holder, "set_frequency"))
			call(holder, "set_frequency")(sanitize_frequency(new_frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ))
	else
		var/text = "[R.value]"
		if(length(text))
			text = copytext(text, 1, (length(setting) >= 4 && setting[4] ? setting[4] : MAX_NAME_LEN) + 1)
			if(hascall(holder, "set_[setting[2]]"))
				call(holder, "set_[setting[2]]")(text)
			else
				holder.vars[setting[2]] = text
	return OP_OK
