
ADMIN_VERB(map_template_load, R_SPAWN, "Map template - Place At Loc", "Spawns a new map template at the current position.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = verb_prompt(user, "map", list("kind" = "list", "message" = "Choose a Map Template to place at your CURRENT LOCATION", "title" = "Place Map Template", "choices" = SSmapping.map_templates), args)
	if(!map)
		return
	var/datum/map_template/template = SSmapping.map_templates[map]

	var/turf/T = get_turf(user.mob)
	if(!T)
		return

	// The preview stays up while the admin confirms; the answer takes it down.
	var/list/preview = list()
	template.preload_size(template.mappath)
	for(var/S in template.get_affected_turfs(T,centered = TRUE))
		preview += image('icons/misc/debug_group.dmi',S ,"red")
	user.images += preview
	om_prompt_sequence(user, user, list(
		list("key" = "confirm", "message" = "Confirm location.", "title" = "Template Confirm", "choices" = list("No","Yes"), "confirm" = "Yes", "on_stop" = GLOBAL_PROC_REF(map_template_preview_end)),
		template.annihilate ? list("key" = "annihilate", "message" = "This template is set to annihilate everything in the red square. EVERYTHING IN THE RED SQUARE WILL BE DELETED, ARE YOU ABSOLUTELY SURE?", "title" = "Template Confirm", "choices" = list("No","Yes"), "confirm" = "Yes", "on_stop" = GLOBAL_PROC_REF(map_template_preview_end)) : null,
	), GLOBAL_PROC_REF(map_template_place_confirmed), list("requires" = PROMPT_ADMIN(R_SPAWN), "on_cancel" = GLOBAL_PROC_REF(map_template_preview_end), "data" = list("template" = map, "turf" = T, "preview" = preview)))

/proc/map_template_preview_end(client/C, mob/user, datum/om/prompt/ask)
	C?.images -= ask.get("preview")

/proc/map_template_place_confirmed(client/C, mob/user, datum/om/prompt/ask)
	map_template_preview_end(C, user, ask)
	var/datum/map_template/template = SSmapping.map_templates[ask.get("template")]
	if(template?.load(ask.get("turf"), centered = TRUE))
		message_admins(span_adminnotice("[key_name_admin(user)] has placed a map template ([template.name])."))
	else
		to_chat(user, "Failed to place map")

ADMIN_VERB(map_template_load_on_new_z, R_SPAWN, "Map template - New Z", "Spawns a new map template at the selected z level.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = verb_prompt(user, "a1", list("kind" = "list", "message" = "Choose a Map Template to place on a new Z-level.", "title" = "Place Map Template", "choices" = SSmapping.map_templates), args)
	if(isnull(map))
		return
	if(!map)
		return
	var/datum/map_template/template = SSmapping.map_templates[map]

	if(template.width > world.maxx || template.height > world.maxx)
		var/_answer_a2 = verb_prompt(user, "a2", list("message" = "This template is larger than the existing z-levels. It will EXPAND ALL Z-LEVELS to match the size of the template. This may cause chaos. Are you sure you want to do this?", "title" = "DANGER!!!", "choices" = list("Cancel","Yes")), args)
		if(isnull(_answer_a2))
			return
		if(_answer_a2 == "Cancel")
			to_chat(user,"Template placement aborted.")
			return

	var/_answer_a3 = verb_prompt(user, "a3", list("message" = "Confirm map load.", "title" = "Template Confirm", "choices" = list("No","Yes")), args)
	if(isnull(_answer_a3))
		return
	if(_answer_a3 == "Yes")
		if(template.load_new_z())
			message_admins(span_adminnotice("[key_name_admin(user)] has placed a map template ([template.name]) on Z level [world.maxz]."))
		else
			to_chat(user, "Failed to place map")

ADMIN_VERB(map_template_upload, R_SPAWN, "Map Template - Upload", "Uploads the selected map template to the template storage.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = input(user, "Choose a Map Template to upload to template storage","Upload Map Template") as null|file
	if(!map)
		return
	if(copytext("[map]",-4) != ".dmm")
		to_chat(user, "Bad map file: [map]")
		return

	var/datum/map_template/M = new(map, "[map]")
	if(M.preload_size(map))
		to_chat(user, "Map template '[map]' ready to place ([M.width]x[M.height])")
		SSmapping.map_templates[M.name] = M
		message_admins(span_adminnotice("[key_name_admin(user)] has uploaded a map template ([map])"))
	else
		to_chat(user, "Map template '[map]' failed to load properly")
