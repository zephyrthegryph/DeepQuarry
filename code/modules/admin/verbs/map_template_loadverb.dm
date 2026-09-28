
ADMIN_VERB(map_template_load, R_SPAWN, "Map template - Place At Loc", "Spawns a new map template at the current position.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = verb_ask(user, "map", args, /datum/om/prompt/choice, message = "Choose a Map Template to place at your CURRENT LOCATION", title = "Place Map Template", choices = SSmapping.map_templates)
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
	om_flow_start(/datum/om/flow/map_template_place, user.mob, null, template_name = map, place_at = T, preview = preview)

/// Placing a map template at a turf: confirm the location (and, for an annihilating template,
/// confirm again). The red preview stays up until the flow ends either way.
/datum/om/flow/map_template_place
	name = "place map template"
	requires = PROMPT_ADMIN(R_SPAWN)
	var/template_name
	var/turf/place_at
	/// The preview images shown to the admin.
	var/list/preview

/datum/om/flow/map_template_place/start()
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(location_confirmed), title = "Template Confirm", message = "Confirm location.", no_first = TRUE)

/datum/om/flow/map_template_place/proc/location_confirmed()
	var/datum/map_template/template = SSmapping.map_templates[template_name]
	if(template?.annihilate)
		om_ask(actor, /datum/om/prompt/confirm, PROC_REF(place), title = "Template Confirm", message = "This template is set to annihilate everything in the red square. EVERYTHING IN THE RED SQUARE WILL BE DELETED, ARE YOU ABSOLUTELY SURE?", no_first = TRUE)
		return
	place()

/datum/om/flow/map_template_place/proc/place()
	var/mob/user = actor
	end_preview()
	var/datum/map_template/template = SSmapping.map_templates[template_name]
	if(template?.load(place_at, centered = TRUE))
		message_admins(span_adminnotice("[key_name_admin(user)] has placed a map template ([template.name])."))
	else
		to_chat(user, "Failed to place map")

/datum/om/flow/map_template_place/proc/end_preview()
	var/mob/user = actor
	user?.client?.images -= preview

/datum/om/flow/map_template_place/ended(reason)
	end_preview()

ADMIN_VERB(map_template_load_on_new_z, R_SPAWN, "Map template - New Z", "Spawns a new map template at the selected z level.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = verb_ask(user, "a1", args, /datum/om/prompt/choice, message = "Choose a Map Template to place on a new Z-level.", title = "Place Map Template", choices = SSmapping.map_templates)
	if(isnull(map))
		return
	if(!map)
		return
	var/datum/map_template/template = SSmapping.map_templates[map]

	if(template.width > world.maxx || template.height > world.maxx)
		var/_answer_a2 = verb_ask(user, "a2", args, /datum/om/prompt/choice/alert, message = "This template is larger than the existing z-levels. It will EXPAND ALL Z-LEVELS to match the size of the template. This may cause chaos. Are you sure you want to do this?", title = "DANGER!!!", choices = list("Cancel","Yes"))
		if(isnull(_answer_a2))
			return
		if(_answer_a2 == "Cancel")
			to_chat(user,"Template placement aborted.")
			return

	var/_answer_a3 = verb_ask(user, "a3", args, /datum/om/prompt/choice/alert, message = "Confirm map load.", title = "Template Confirm", choices = list("No","Yes"))
	if(isnull(_answer_a3))
		return
	if(_answer_a3 == "Yes")
		if(template.load_new_z())
			message_admins(span_adminnotice("[key_name_admin(user)] has placed a map template ([template.name]) on Z level [world.maxz]."))
		else
			to_chat(user, "Failed to place map")

ADMIN_VERB(map_template_upload, R_SPAWN, "Map Template - Upload", "Uploads the selected map template to the template storage.", ADMIN_CATEGORY_DEBUG_EVENTS)
	var/map = input(user, "Choose a Map Template to upload to template storage","Upload Map Template") as null|file // S10 keeps: file uploads need the BYOND file dialog
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
