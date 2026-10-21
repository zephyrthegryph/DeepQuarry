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
		perform_op(L, W, "wall_dissolve", origin = ORIGIN_SYSTEM)
		return TRUE
	return FALSE

/transformation/stack/resin__door
CAPABILITIES(/transformation/stack/resin__door)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/simple_door/resin, 1)),
		chosen = chosen(title = "{display_name} door",
			subject = /datum/material/resin,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE,
			replaces = TRUE)))

/transformation/stack/resin__barricade
CAPABILITIES(/transformation/stack/resin__barricade)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/alien/wall, 1)),
		chosen = chosen(title = "{display_name} barricade",
			subject = /datum/material/resin,
			build_time = 5 SECONDS,
			one_per_turf = 1,
			on_floor = 1,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/resin__nest
CAPABILITIES(/transformation/stack/resin__nest)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/nest, 1)),
		chosen = chosen(title = "{display_name} nest",
			subject = /datum/material/resin,
			one_per_turf = 1,
			on_floor = 1,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/resin__crude_bandage
CAPABILITIES(/transformation/stack/resin__crude_bandage)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/medical/crude_pack, 1)),
		chosen = chosen(title = "crude {display_name} bandage",
			subject = /datum/material/resin,
			build_time = 2 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/resin__net
CAPABILITIES(/transformation/stack/resin__net)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/material/fishing_net, 1)),
		chosen = chosen(title = "{display_name} net",
			subject = /datum/material/resin,
			build_time = 5 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/resin__membrane
CAPABILITIES(/transformation/stack/resin__membrane)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/alien/membrane, 1)),
		chosen = chosen(title = "{display_name} membrane",
			subject = /datum/material/resin,
			build_time = 2 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

