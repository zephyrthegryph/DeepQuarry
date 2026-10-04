/*
Verb/Main definition path: code\modules\mob\living\carbon\human\species\station\traits_vr\traits_tutorial.dm
Frontend path: tgui\packages\tgui\interfaces\TraitTutorial.tsx
*/

/datum/tgui_module/trait_tutorial_tgui
	name = "Explain Custom Traits"
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

CAPABILITIES(/datum/tgui_module/trait_tutorial_tgui)
	interface("TraitTutorial", state = nameof(GLOB.tgui_always_state))
	op("select_trait", ui_act("select_trait", arg("name", schema_text(4096))), then(PROC_REF(ui_act_select_trait)))

/datum/tgui_module/trait_tutorial_tgui/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["names"] = trait_names
	data["descriptions"] = trait_desc
	data["categories"] = trait_category
	data["tutorials"] = trait_tutorial
	data["selection"] = trait_selected
	return data

/datum/tgui_module/trait_tutorial_tgui/proc/ui_act_select_trait(datum/act/op/A, name)
	var/selection = name
	trait_selected = selection
	. = TRUE
