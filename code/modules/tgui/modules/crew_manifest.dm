/datum/tgui_module/crew_manifest
	name = "Crew Manifest"
	tgui_id = "CrewManifest"

UI_DATA(/datum/tgui_module/crew_manifest, "merge:ui_data_datum_tgui_module_crew_manifest{manifest:unknown}")

/// The computed part of /datum/tgui_module/crew_manifest's window data (declared on its UI_DATA row).
/datum/tgui_module/crew_manifest/proc/ui_data_datum_tgui_module_crew_manifest(mob/user, datum/tgui/ui, datum/tgui_state/state)
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
