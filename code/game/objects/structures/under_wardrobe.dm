/obj/structure/undies_wardrobe
	name = "underwear dresser"
	desc = "Holds item of clothing you shouldn't be showing off in the hallways."
	icon = 'icons/obj/closets/undies_wardrobe.dmi'
	icon_state = "wardrobe"
	density = TRUE

CAPABILITIES(/obj/structure/undies_wardrobe)
	climb()
	interface("UndiesWardrobe", title = "Underwear Dresser")
	op("remove_underwear", ui_act("remove_underwear", arg("category")), then(PROC_REF(ui_act_remove_underwear)))
	op("change_underwear", ui_act("change_underwear", arg("category")), then(PROC_REF(ui_act_change_underwear)))
	op("tweak", ui_act("tweak", arg("category"), arg("tweak")), then(PROC_REF(ui_act_tweak)))
	extend(TAG_UI, needs(req(PROC_REF(user_is_human), because = MSG(undies_wardrobe/not_human))))
	extend("ui_open", needs(req(PROC_REF(can_browse))))

/// Requirement: only someone who wears underwear finds anything in here.
/obj/structure/undies_wardrobe/proc/can_browse(datum/act/op/A)
	return (wears_underwear(A.actor)) ? null : MSG(undies_wardrobe/nothing)

/// Does `M` wear underwear (a human whose species has it)?
/proc/wears_underwear(mob/living/carbon/human/H)
	READS_FROM() // a species is set when the body is made; the window asks again when it opens
	return istype(H) && H.species && (H.species.appearance_flags & HAS_UNDERWEAR)

MSG_DEF_SELF(undies_wardrobe/nothing, "Sadly there's nothing in here for you to wear.")

// TGUI migration. interact opens UndiesWardrobe.tsx; Topic
// handlers move to tgui_act below.
/obj/structure/undies_wardrobe/interact(mob/living/carbon/human/H)
	tgui_interact(H)

MSG_DEF_SELF(undies_wardrobe/not_human, "You can't use that.")

/// Only a human works the window.
/obj/structure/undies_wardrobe/proc/user_is_human(datum/act/op/A)
	return (ishuman(A.actor)) ? null : MSG(undies_wardrobe/not_human)

/obj/structure/undies_wardrobe/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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

/// The choice of an item for one underwear category; `category` is the name of the category the question is about.
/datum/prompt/choice/underwear
	title = "Choose underwear"
	question = "Choose underwear:"
	var/category

/// The wardrobe stands and the person is next to it and can still wear underwear.
/obj/structure/undies_wardrobe/proc/request_usable(datum/request/R)
	var/mob/M = R.answerer
	return istype(M) && !QDELETED(src) && in_range(src, M) && human_who_can_use_underwear(M)

/obj/structure/undies_wardrobe/proc/underwear_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/underwear/R = A.request
	var/mob/living/carbon/human/H = R.answerer
	if(!istype(H))
		return
	var/category = R.category
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[category]
	var/datum/category_item/underwear/selected_underwear = UWC?.items_by_name[A.answer.value]
	if(!selected_underwear)
		return
	LAZYSET(H.all_underwear, category, selected_underwear)
	H.hide_underwear[category] = FALSE
	H.update_underwear()

/obj/structure/undies_wardrobe/proc/ui_act_remove_underwear(datum/act/op/A, category)
	var/mob/living/carbon/human/H = A.actor
	var/changed = FALSE
	if(category in H.all_underwear)
		LAZYREMOVE(H.all_underwear, category)
		changed = TRUE
	if(changed)
		H.update_underwear()
	return TRUE

/obj/structure/undies_wardrobe/proc/ui_act_change_underwear(datum/act/op/A, category)
	var/mob/living/carbon/human/H = A.actor
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[category]
	if(!UWC)
		return TRUE
	var/list/names = list()
	for(var/datum/category_item/underwear/UWI in UWC.items)
		names += UWI.name
	var/datum/category_item/underwear/current = LAZYACCESS(H.all_underwear, UWC.name)
	open_request(src, /datum/prompt/choice/underwear, PROC_REF(underwear_chosen), valid = PROC_REF(request_usable), answerer = H, choices = names, default = current?.name, category = UWC.name, timeout = 0)
	return TRUE

/obj/structure/undies_wardrobe/proc/ui_act_tweak(datum/act/op/A, category, tweak)
	var/mob/living/carbon/human/H = A.actor
	var/underwear = category
	if(!(underwear in H.all_underwear))
		return TRUE
	var/datum/gear_tweak/gt = ui_ref(tweak, null, /datum/gear_tweak)
	if(!gt)
		return TRUE
	gt.ask_metadata(H, get_metadata(H, underwear, gt), null, "Wardrobe Underwear Selection", src, PROC_REF(underwear_tweak_answered), new /datum/ask_sequence/gear_tweak/underwear(underwear, gt), list("usable_state" = "default"))
	return TRUE

/// An underwear gear tweak change: which underwear category and tweak it is for.
/datum/ask_sequence/gear_tweak/underwear
	var/category
	var/datum/gear_tweak/tweak

/datum/ask_sequence/gear_tweak/underwear/New(category, datum/gear_tweak/tweak)
	..()
	src.category = category
	rel_set(src, nameof(tweak), tweak)

/obj/structure/undies_wardrobe/proc/underwear_tweak_answered(mob/living/carbon/human/H, new_metadata, datum/ask_sequence/gear_tweak/underwear/seq)
	var/underwear = seq.category
	var/datum/gear_tweak/gt = seq.tweak
	if(!istype(H) || !(underwear in H.all_underwear))
		return
	set_metadata(H, underwear, gt, new_metadata)
	H.hide_underwear[underwear] = FALSE
	H.update_underwear()
	SStgui.update_uis(src)
