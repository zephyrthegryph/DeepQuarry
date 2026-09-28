/mob
	var/hive_lang_range = 0

/mob/proc/adjust_hive_range()
	set name = "Adjust Special Language Range"
	set desc = "Changes the range you will transmit your hive language to!"
	set category = "IC.Settings"

	om_ask(src, /datum/om/prompt/choice, PROC_REF(hive_range_chosen), message = "What range?", title = "Adjust special language range", choices = list("Global","This Z level","Local", "Subtle"), buttons = TRUE)

/mob/proc/hive_range_chosen(datum/om/prompt/choice/ask)
	switch(ask.choice)
		if("Global")
			hive_lang_range = 0
		if("This Z level")
			hive_lang_range = -1
		if("Local")
			hive_lang_range = world.view
		if("Subtle")
			hive_lang_range = 1
