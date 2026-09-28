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
	effect = /obj/structure/undies_wardrobe/proc/interaction_open_ui

/obj/structure/undies_wardrobe/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	if(!human_who_can_use_underwear(user))
		to_chat(user, span_warning("Sadly there's nothing in here for you to wear."))
		return TRUE
	interact(user)
	return TRUE

// TGUI migration. interact opens UndiesWardrobe.tsx; Topic
// handlers move to tgui_act below.
/obj/structure/undies_wardrobe/interact(mob/living/carbon/human/H)
	tgui_interact(H)

/obj/structure/undies_wardrobe/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "UndiesWardrobe", "Underwear Dresser")
		ui.open()

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
/obj/structure/undies_wardrobe/proc/underwear_chosen(mob/living/carbon/human/H, datum/category_item/underwear/selected_underwear, datum/om/prompt/ask)
	if(!istype(H))
		return
	var/category = ask.get("category")
	LAZYSET(H.all_underwear, category, selected_underwear)
	H.hide_underwear[category] = FALSE
	H.update_underwear()

/obj/structure/undies_wardrobe/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(!ishuman(usr))
		return
	var/mob/living/carbon/human/H = usr
	var/changed = FALSE
	switch(action)
		if("remove_underwear")
			if(params["category"] in H.all_underwear)
				LAZYREMOVE(H.all_underwear, params["category"])
				changed = TRUE
		if("change_underwear")
			var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[params["category"]]
			if(!UWC)
				return TRUE
			om_prompt(src, H, list("kind" = "list", "message" = "Choose underwear:", "title" = "Choose underwear", "choices" = UWC.items, "default" = LAZYACCESS(H.all_underwear, UWC.name), "requires" = PROMPT_USABLE, "data" = list("category" = UWC.name)), PROC_REF(underwear_chosen))
		if("tweak")
			var/underwear = params["category"]
			if(!(underwear in H.all_underwear))
				return TRUE
			var/datum/gear_tweak/gt = locate(params["tweak"])
			if(!gt)
				return TRUE
			gt.ask_metadata(H, get_metadata(H, underwear, gt), null, "Wardrobe Underwear Selection", src, PROC_REF(underwear_tweak_answered), list("category" = underwear, "tweak" = gt), PROMPT_USABLE)
	if(changed)
		H.update_underwear()
	return TRUE

/obj/structure/undies_wardrobe/proc/underwear_tweak_answered(mob/living/carbon/human/H, new_metadata, datum/om/prompt/P)
	var/underwear = P.get("category")
	var/datum/gear_tweak/gt = P.get("tweak")
	if(!istype(H) || !(underwear in H.all_underwear))
		return
	set_metadata(H, underwear, gt, new_metadata)
	H.hide_underwear[underwear] = FALSE
	H.update_underwear()
	SStgui.update_uis(src)
