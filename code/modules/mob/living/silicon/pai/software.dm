/mob/living/silicon/pai/Initialize(mapload)
	. = ..()
	software = list()
	for(var/id in GLOB.default_pai_software)
		software[id] = TRUE

/mob/living/silicon/pai/verb/paiInterface()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Software Interface"

	tgui_interact(src)

/mob/living/silicon/pai/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["available_ram"] = ram

	// Software we have bought
	var/list/bought_software = list()
	// Software we have not bought
	var/list/not_bought_software = list()

	for(var/key in GLOB.pai_software_by_key)
		var/datum/pai_software/S = GLOB.pai_software_by_key[key]
		var/software_data[0]
		software_data["name"] = S.name
		software_data["id"] = S.id
		if(key in software)
			software_data["on"] = S.is_active(src)
			bought_software.Add(list(software_data))
		else
			software_data["ram"] = S.ram_cost
			not_bought_software.Add(list(software_data))

	data["bought"] = bought_software
	data["not_bought"] = not_bought_software

	// Emotions
	var/list/emotions = list()
	for(var/name in GLOB.pai_emotions)
		var/list/emote = list(
			"displayText" = name,
			"value" = GLOB.pai_emotions[name]
		)
		UNTYPED_LIST_ADD(emotions, emote)

	data["emotions"] = emotions
	data["current_emotion"] = card.current_emotion

	return data

/mob/living/silicon/pai/proc/ui_act_software(datum/act/op/A, software_id)
	var/soft = software_id
	var/datum/pai_software/S = software[soft] ? GLOB.pai_software_by_key[soft] : null
	if(S.toggle)
		S.toggle(src)
	else
		S.tgui_interact(src, parent_ui = SStgui.get_open_ui(src, src))
	return TRUE

/mob/living/silicon/pai/proc/ui_act_purchase(datum/act/op/A, purchase)
	var/soft = purchase
	var/datum/pai_software/S = GLOB.pai_software_by_key[soft]
	if(S && (ram >= S.ram_cost))
		ram -= S.ram_cost
		software[S.id] = TRUE
	return TRUE

/mob/living/silicon/pai/proc/ui_act_image(datum/act/op/A, image)
	var/img = image
	if(1 <= img && img <= length(GLOB.pai_emotions))
		card.setEmotion(img)
	return TRUE
