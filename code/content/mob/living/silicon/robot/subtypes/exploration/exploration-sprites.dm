/datum/robot_sprite/dogborg/explorer
	module_type = "Exploration"
	sprite_icon = 'icons/mob/robot/widerobot/widerobot_exp.dmi'
	sprite_hud_icon_state = "platform"

/datum/robot_sprite/dogborg/explorer/vale2
	name = "Explorationhound V2"
	sprite_icon_state = "exploration-v2"
	has_eye_light_sprites = TRUE

/datum/robot_sprite/dogborg/explorer/vale
	name = "Explorationhound V2 - Pink"
	sprite_icon_state = "exploration"
	has_eye_light_sprites = TRUE

/datum/robot_sprite/dogborg/tall/explorer
	module_type = "Exploration"

/datum/robot_sprite/dogborg/tall/explorer/dullahan
	sprite_icon = 'icons/mob/robot/dullahan/v1/dullahan_explorer.dmi'
	icon_x = 32
	pixel_x = 0

/datum/robot_sprite/dogborg/tall/explorer/dullahan/explorer
	name = "Dullahan"
	sprite_icon_state = "dullahanexplo"
	has_eye_light_sprites = TRUE
	has_vore_belly_sprites = TRUE
	rest_sprite_options = list("Default", "Sit")
	sprite_decals = list("breastplate","loincloth","eyecover")

/datum/robot_sprite/dogborg/tall/explorer/bulwark
	name = "Bulwark"
	sprite_icon = 'icons/mob/robot/tallrobot/tallrobots.dmi'
	sprite_icon_state = "bulwark"
	has_eye_light_sprites = FALSE
	rest_sprite_options = list("Default")
	icon_x = 32
	pixel_x = 0

/datum/robot_sprite/dogborg/explorer/smolraptor
	sprite_icon = 'icons/mob/robot/smallraptors/smolraptor_ninja.dmi'
	name = "Small Raptor"
	sprite_icon_state = "smolraptor"
	has_eye_light_sprites = TRUE
	has_vore_belly_sprites = TRUE
	has_dead_sprite_overlay = FALSE
	rest_sprite_options = list("Default", "Sit", "Bellyup")

