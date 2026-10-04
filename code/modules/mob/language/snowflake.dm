/mob
	var/hive_lang_range = 0

/mob/proc/adjust_hive_range()
	set name = "Adjust Special Language Range"
	set desc = "Changes the range you will transmit your hive language to!"
	set category = VERB_CAT_IC_SETTINGS

	open_request(src, /datum/prompt/choice, PROC_REF(hive_range_chosen), answerer = src, title = "Adjust special language range", question = "What range?", choices = list("Global","This Z level","Local", "Subtle"), buttons = TRUE, timeout = 0)

/mob/proc/hive_range_chosen(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.answer_value)
		if("Global")
			hive_lang_range = 0
		if("This Z level")
			hive_lang_range = -1
		if("Local")
			hive_lang_range = world.view
		if("Subtle")
			hive_lang_range = 1
