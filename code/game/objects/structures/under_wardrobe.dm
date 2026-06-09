/obj/structure/undies_wardrobe
	name = "underwear dresser"
	desc = "Holds item of clothing you shouldn't be showing off in the hallways."
	icon = 'icons/obj/closets/undies_wardrobe.dmi'
	icon_state = "wardrobe"
	density = TRUE

/obj/structure/undies_wardrobe/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/climbable)

/obj/structure/undies_wardrobe/attack_hand(mob/user)
	if(!human_who_can_use_underwear(user))
		to_chat(user, span_warning("Sadly there's nothing in here for you to wear."))
		return
	interact(user)

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
		var/datum/category_item/underwear/UWI = H.all_underwear[UWC.name]
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
				H.all_underwear -= params["category"]
				changed = TRUE
		if("change_underwear")
			var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[params["category"]]
			if(!UWC)
				return TRUE
			var/datum/category_item/underwear/selected_underwear = tgui_input_list(H, "Choose underwear:", "Choose underwear", UWC.items, H.all_underwear[UWC.name])
			if(selected_underwear && CanUseTopic(H, GLOB.tgui_default_state))
				H.all_underwear[UWC.name] = selected_underwear
				H.hide_underwear[UWC.name] = FALSE
				changed = TRUE
		if("tweak")
			var/underwear = params["category"]
			if(!(underwear in H.all_underwear))
				return TRUE
			var/datum/gear_tweak/gt = locate(params["tweak"])
			if(!gt)
				return TRUE
			var/new_metadata = gt.get_metadata(usr, get_metadata(H, underwear, gt), "Wardrobe Underwear Selection")
			if(!isnull(new_metadata))
				set_metadata(H, underwear, gt, new_metadata)
				H.hide_underwear[underwear] = FALSE
				changed = TRUE
	if(changed)
		H.update_underwear()
	return TRUE
