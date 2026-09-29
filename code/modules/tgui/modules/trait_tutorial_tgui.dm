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

/datum/tgui_module/trait_tutorial_tgui/tgui_data(mob/user)
	var/list/data = list()
	data["names"] = trait_names //passes a list of strings
	data["descriptions"] = trait_desc //passes an assoc list as obj
	data["categories"] = trait_category //passes an assoc list as obj
	data["tutorials"] = trait_tutorial //passes an assoc list as obj
	data["selection"] = trait_selected //passes a string
	return data

UI_ACT(/datum/tgui_module/trait_tutorial_tgui, "select_trait", ui_act_select_trait, UI_ARG_VALUE("name"))
UI_ACT_PROC(/datum/tgui_module/trait_tutorial_tgui, ui_act_select_trait)
	var/selection = params["name"]
	trait_selected = selection
	. = TRUE

/datum/tgui_module/trait_tutorial_tgui/tgui_state(mob/user)
	return GLOB.tgui_always_state
