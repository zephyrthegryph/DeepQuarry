/datum/material/resin
	name = MAT_RESIN
	icon_colour = "#ffffff" // No longer needed
	icon_base = "resin"
	integrity = 50 // Same as wood.
	hardness = 15 // Same as wood.
	table_icon_base = "stone"
	dooropen_noise = SFX_EFFECTS_ATTACKBLOB
	door_icon_base = "resin"
	icon_reinf = "reinf_mesh"
	melting_point = T0C+300
	sheet_singular_name = "blob"
	sheet_plural_name = "blobs"
	conductive = 0
	explosion_resistance = 60
	radiation_resistance = 10
	stack_type = /obj/item/stack/material/resin
	supply_conversion_value = 2

/datum/material/resin/can_open_material_door(mob/living/user)
	var/mob/living/carbon/M = user
	if(istype(M) && locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode))
		return TRUE
	if(istype(M) && locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/resinspinner/replicant))
		return TRUE
	return FALSE

/datum/material/resin/wall_touch_special(turf/simulated/wall/W, mob/living/L)
	var/mob/living/carbon/M = L
	if(istype(M) && ((locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/hivenode)) || (locate_in_list(M.internal_organ_list(), /obj/item/organ/internal/xenos/resinspinner/replicant))))
		to_chat(M, "\The [W] shudders under your touch, starting to become porous.")
		play_sfx(W, SFX_EFFECTS_ATTACKBLOB)
		task_timed(L, 5 SECONDS, W, null, GLOBAL_PROC_REF(resin_wall_dissolve), list(W))
		return TRUE
	return FALSE

/proc/resin_wall_dissolve(turf/simulated/wall/W)
	play_sfx(W, SFX_EFFECTS_ATTACKBLOB, 2)
	W.dismantle_wall()

/datum/material/resin/generate_recipes()
	var/list/recipes = list(
		new /datum/stack_recipe("[display_name] door", /obj/structure/simple_door/resin, 1, one_per_turf = 1, on_floor = 1, supplied_material = "[name]", pass_stack_color = TRUE), // Reduced material cost.
		new /datum/stack_recipe("[display_name] barricade", /obj/structure/alien/wall, 1, time = 5 SECONDS, one_per_turf = 1, on_floor = 1, pass_stack_color = TRUE, recycle_material = "[name]"), // Reduced material cost.
		new /datum/stack_recipe("[display_name] nest", /obj/structure/bed/nest, 1, one_per_turf = 1, on_floor = 1, supplied_material = "[name]", pass_stack_color = TRUE), // Reduced material cost.
// new /datum/stack_recipe("[display_name] wall girders", /obj/structure/girder/resin, 1, time = 5 SECONDS, one_per_turf = 1, on_floor = 1, supplied_material = "[name]", pass_stack_color = TRUE), // Removed, build walls with secrete resin
		new /datum/stack_recipe("crude [display_name] bandage", /obj/item/stack/medical/crude_pack, 2, time = 2 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"), // Increased material cost.
		new /datum/stack_recipe("[display_name] net", /obj/item/material/fishing_net, 2, time = 5 SECONDS, supplied_material = "[name]", pass_stack_color = TRUE), // Reduced material cost.
		new /datum/stack_recipe("[display_name] membrane", /obj/structure/alien/membrane, 1, time = 2 SECONDS, pass_stack_color = TRUE, recycle_material = "[name]"),
// new /datum/stack_recipe("[display_name] node", /obj/effect/alien/weeds/node, 1, time = 4 SECONDS, recycle_material = "[name]") // No nodes.
	)
	return recipes
