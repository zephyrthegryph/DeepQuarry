/*
Verb/Main definition path: code\modules\mob\living\carbon\human\species\station\traits_vr\traits_tutorial.dm
Frontend path: tgui\packages\tgui\interfaces\TraitTutorial.tsx
*/

/datum/tgui_module/trait_tutorial_tgui
	name = "Explain Custom Traits"
	tgui_id = "TraitTutorial"
	var/trait_names = list()
	var/trait_category = list() // name:category
	var/trait_desc = list() // name:desc
	var/trait_tutorial = list() //name:tutorial
	var/trait_selected = ""

/datum/tgui_module/trait_tutorial_tgui/proc/set_vars(list/names, list/categories, list/descriptions, list/tutorials)
	trait_names = names
	trait_category = categories
	trait_desc = descriptions
	trait_tutorial = tutorials

DECLARE_UI(/datum/tgui_module/trait_tutorial_tgui, UI_FROM_VAR("tgui_id"))

UI_DATA_REPLACE(/datum/tgui_module/trait_tutorial_tgui, "names=trait_names:list", "descriptions=trait_desc:list", "categories=trait_category:list", "tutorials=trait_tutorial:list", "selection=trait_selected:text")

UI_ACT(/datum/tgui_module/trait_tutorial_tgui, "select_trait", ui_act_select_trait, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/tgui_module/trait_tutorial_tgui, ui_act_select_trait)
	var/selection = params["name"]
	trait_selected = selection
	. = TRUE

DECLARE_UI_STATE(/datum/tgui_module/trait_tutorial_tgui, GLOB.tgui_always_state)
