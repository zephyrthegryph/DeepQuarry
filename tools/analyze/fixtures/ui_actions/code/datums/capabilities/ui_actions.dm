/proc/ui_action_key(raw)
	if(!istext(raw) || !length(raw) || length(raw) > 64 || !GLOB.ui_action_raw_regex.Find(raw))
		return null
	var/out = GLOB.ui_action_camel_regex.Replace(raw, "$1_$2")
	out = replacetext(lowertext(out), "-", "_")
	return out
GLOBAL_DATUM_INIT(ui_action_raw_regex, /regex, regex(@"^[A-Za-z0-9_-]+$"))
GLOBAL_DATUM_INIT(ui_action_camel_regex, /regex, regex(@"([a-z0-9])([A-Z])", "g"))
GLOBAL_LIST_INIT(ui_reserved_arg_names, list("user", "src", "usr", "ui", "state", "holder"))
