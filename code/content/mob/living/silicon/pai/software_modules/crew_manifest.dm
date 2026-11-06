/datum/pai_software/crew_manifest
	name = "Crew Manifest"
	ram_cost = 0
	id = "manifest"
	toggle = 0
	default = 1		//Comes with the communicator already, also why not

CAPABILITIES(/datum/pai_software/crew_manifest)
	interface("CrewManifest", state = nameof(GLOB.tgui_always_state))
	ui_shape(manifest = map_of(schema_text(), list_of(map_of(schema_text(), schema_text()))))

/datum/pai_software/crew_manifest/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data
