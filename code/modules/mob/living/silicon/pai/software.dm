/mob/living/silicon/pai/Initialize(mapload)
	. = ..()
	software = list()
	for(var/id in GLOB.default_pai_software)
		software[id] = TRUE

/mob/living/silicon/pai/verb/paiInterface()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Software Interface"

	tgui_interact(src)

DECLARE_UI_STATE(/mob/living/silicon/pai, GLOB.tgui_self_state)

DECLARE_UI(/mob/living/silicon/pai, "pAIInterface", UI_TITLE("pAI Software Interface"))

UI_DATA(/mob/living/silicon/pai, "available_ram=ram:num", "merge:ui_data_mob_living_silicon_pai{bought:list,not_bought:list,emotions:list,current_emotion:num}")

/// The computed part of /mob/living/silicon/pai's window data (declared on its UI_DATA row).
/mob/living/silicon/pai/proc/ui_data_mob_living_silicon_pai(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

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

UI_ACT(/mob/living/silicon/pai, "software", ui_act_software, UI_ARG_TEXT("software"))
UI_ACT_PROC(/mob/living/silicon/pai, ui_act_software)
	var/soft = params["software"]
	var/datum/pai_software/S = software[soft] ? GLOB.pai_software_by_key[soft] : null
	if(S.toggle)
		S.toggle(src)
	else
		S.tgui_interact(src, parent_ui = ui)
	return TRUE

UI_ACT(/mob/living/silicon/pai, "purchase", ui_act_purchase, UI_ARG_TEXT("purchase"))
UI_ACT_PROC(/mob/living/silicon/pai, ui_act_purchase)
	var/soft = params["purchase"]
	var/datum/pai_software/S = GLOB.pai_software_by_key[soft]
	if(S && (ram >= S.ram_cost))
		ram -= S.ram_cost
		software[S.id] = TRUE
	return TRUE

UI_ACT(/mob/living/silicon/pai, "image", ui_act_image, UI_ARG_NUM("image"))
UI_ACT_PROC(/mob/living/silicon/pai, ui_act_image)
	var/img = params["image"]
	if(1 <= img && img <= length(GLOB.pai_emotions))
		card.setEmotion(img)
	return TRUE
