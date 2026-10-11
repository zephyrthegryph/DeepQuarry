/// "12 kg", "size 3", "373.15 K".
/proc/dq_format_measure(value, unit)
	if(isnull(value))
		return "unknown"
	var/text = "[round(value, 0.01)]"
	switch(unit)
		if(PROP_UNIT_SIZE_CLASS)
			return "size [text]"
		if(PROP_UNIT_RATIO, null)
			return text
	return "[text] [unit]"

