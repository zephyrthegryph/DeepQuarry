/datum/tgui_module/crew_manifest
	name = "Crew Manifest"

CAPABILITIES(/datum/tgui_module/crew_manifest)
	interface("CrewManifest")
	ui_shape(manifest = map_of(schema_text(), list_of(map_of(schema_text(), schema_text()))))

/datum/tgui_module/crew_manifest/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data

/datum/tgui_module/crew_manifest/robot
DECLARE_UI_STATE(/datum/tgui_module/crew_manifest/robot, GLOB.tgui_self_state)

/datum/tgui_module/crew_manifest/new_player
DECLARE_UI_STATE(/datum/tgui_module/crew_manifest/new_player, GLOB.tgui_always_state)

// Module that deletes itself when it's closed
/datum/tgui_module/crew_manifest/self_deleting

/datum/tgui_module/crew_manifest/self_deleting/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

DECLARE_UI_STATE(/datum/tgui_module/crew_manifest/self_deleting, GLOB.tgui_always_state)
