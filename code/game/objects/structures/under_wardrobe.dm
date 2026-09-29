/obj/structure/undies_wardrobe
	name = "underwear dresser"
	desc = "Holds item of clothing you shouldn't be showing off in the hallways."
	icon = 'icons/obj/closets/undies_wardrobe.dmi'
	icon_state = "wardrobe"
	density = TRUE

/obj/structure/undies_wardrobe/Initialize(mapload)
	. = ..()
	make_climbable()

/obj/structure/undies_wardrobe/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/undies_wardrobe_open_ui,
	)
	..()

/datum/interaction/entry_hand/undies_wardrobe_open_ui
	id = "undies_wardrobe_open_ui"
	name = "Use"
	effect = /obj/structure/undies_wardrobe/proc/wardrobe_open_ui

/obj/structure/undies_wardrobe/proc/wardrobe_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	if(!human_who_can_use_underwear(user))
		to_chat(user, span_warning("Sadly there's nothing in here for you to wear."))
		return TRUE
	interact(user)
	return TRUE

// TGUI migration. interact opens UndiesWardrobe.tsx; Topic
// handlers move to tgui_act below.
/obj/structure/undies_wardrobe/interact(mob/living/carbon/human/H)
	tgui_interact(H)

DECLARE_UI(/obj/structure/undies_wardrobe, "UndiesWardrobe", UI_TITLE("Underwear Dresser"))

/obj/structure/undies_wardrobe/tgui_data(mob/user)
	var/list/data = list()
	var/list/cats = list()
	if(!ishuman(user))
		data["categories"] = cats
		return data
	var/mob/living/carbon/human/H = user
	for(var/datum/category_group/underwear/UWC in GLOB.global_underwear.categories)
		var/datum/category_item/underwear/UWI = LAZYACCESS(H.all_underwear, UWC.name)
		var/list/tweaks = list()
		if(UWI)
			for(var/datum/gear_tweak/gt in UWI.tweaks)
				tweaks += list(list(
					"ref" = "\ref[gt]",
					"label" = gt.get_contents(get_metadata(H, UWC.name, gt)),
				))
		cats += list(list(
			"name" = UWC.name,
			"item_name" = UWI ? UWI.name : "None",
			"has_item" = !!UWI,
			"tweaks" = tweaks,
		))
	data["categories"] = cats
	return data

/obj/structure/undies_wardrobe/proc/get_metadata(mob/living/carbon/human/H, underwear_category, datum/gear_tweak/gt)
	var/metadata = H.all_underwear_metadata[underwear_category]
	if(!metadata)
		metadata = list()
		H.all_underwear_metadata[underwear_category] = metadata

	var/tweak_data = metadata["[gt]"]
	if(!tweak_data)
		tweak_data = gt.get_default()
		metadata["[gt]"] = tweak_data
	return tweak_data

/obj/structure/undies_wardrobe/proc/set_metadata(mob/living/carbon/human/H, underwear_category, datum/gear_tweak/gt, new_metadata)
	var/list/metadata = H.all_underwear_metadata[underwear_category]
	metadata["[gt]"] = new_metadata

/obj/structure/undies_wardrobe/proc/human_who_can_use_underwear(mob/living/carbon/human/H)
	if(!istype(H) || !H.species || !(H.species.appearance_flags & HAS_UNDERWEAR))
		return FALSE
	return TRUE

/obj/structure/undies_wardrobe/CanUseTopic(user)
	if(!human_who_can_use_underwear(user))
		return STATUS_CLOSE

	return ..()

// Topic switch lifted into tgui_act with stable action names.
/datum/om/prompt/choice/underwear
	title = "Choose underwear"
	message = "Choose underwear:"
	requires = PROMPT_USABLE
	var/category

/obj/structure/undies_wardrobe/proc/underwear_chosen(datum/om/prompt/choice/underwear/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/category_item/underwear/selected_underwear = ask.choice
	if(!istype(H))
		return
	var/category = ask.category
	LAZYSET(H.all_underwear, category, selected_underwear)
	H.hide_underwear[category] = FALSE
	H.update_underwear()

/obj/structure/undies_wardrobe/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!ishuman(usr))
		return FALSE
	return TRUE

UI_ACT(/obj/structure/undies_wardrobe, "remove_underwear", ui_act_remove_underwear, UI_ARG_VALUE("category"))
UI_ACT_PROC(/obj/structure/undies_wardrobe, ui_act_remove_underwear)
	var/mob/living/carbon/human/H = usr
	var/changed = FALSE
	if(params["category"] in H.all_underwear)
		LAZYREMOVE(H.all_underwear, params["category"])
		changed = TRUE
	if(changed)
		H.update_underwear()
	return TRUE

UI_ACT(/obj/structure/undies_wardrobe, "change_underwear", ui_act_change_underwear, UI_ARG_VALUE("category"))
UI_ACT_PROC(/obj/structure/undies_wardrobe, ui_act_change_underwear)
	var/mob/living/carbon/human/H = usr
	var/changed = FALSE
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[params["category"]]
	if(!UWC)
		return TRUE
	om_ask(H, /datum/om/prompt/choice/underwear, PROC_REF(underwear_chosen), choices = UWC.items, default = LAZYACCESS(H.all_underwear, UWC.name), category = UWC.name)
	if(changed)
		H.update_underwear()
	return TRUE

UI_ACT(/obj/structure/undies_wardrobe, "tweak", ui_act_tweak, UI_ARG_VALUE("category"), UI_ARG_REF("tweak", null, /datum/gear_tweak))
UI_ACT_PROC(/obj/structure/undies_wardrobe, ui_act_tweak)
	var/mob/living/carbon/human/H = usr
	var/changed = FALSE
	var/underwear = params["category"]
	if(!(underwear in H.all_underwear))
		return TRUE
	var/datum/gear_tweak/gt = params["tweak"]
	if(!gt)
		return TRUE
	gt.ask_metadata(H, get_metadata(H, underwear, gt), null, "Wardrobe Underwear Selection", src, PROC_REF(underwear_tweak_answered), new /datum/om/flow/ask_sequence/gear_tweak/underwear(underwear, gt), PROMPT_USABLE)
	if(changed)
		H.update_underwear()
	return TRUE

/// An underwear gear tweak change: which underwear category and tweak it is for.
/datum/om/flow/ask_sequence/gear_tweak/underwear
	var/category
	var/datum/gear_tweak/tweak

/datum/om/flow/ask_sequence/gear_tweak/underwear/New(category, datum/gear_tweak/tweak)
	..()
	src.category = category
	src.tweak = tweak

/obj/structure/undies_wardrobe/proc/underwear_tweak_answered(mob/living/carbon/human/H, new_metadata, datum/om/flow/ask_sequence/gear_tweak/underwear/seq)
	var/underwear = seq.category
	var/datum/gear_tweak/gt = seq.tweak
	if(!istype(H) || !(underwear in H.all_underwear))
		return
	set_metadata(H, underwear, gt, new_metadata)
	H.hide_underwear[underwear] = FALSE
	H.update_underwear()
	SStgui.update_uis(src)
