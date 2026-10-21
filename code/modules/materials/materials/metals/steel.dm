/datum/material/steel
	name = MAT_STEEL
	stack_type = /obj/item/stack/material/steel
	hardness = 60
	density = 20
	integrity = 150
	conductivity = 11 // Assuming this is carbon steel, it would actually be slightly less conductive than iron, but lets ignore that.
	protectiveness = 10 // 33%
	icon_base = "solid"
	icon_reinf = "reinf_over"
	icon_colour = "#666666"
	supply_conversion_value = 0.15

/transformation/stack/steel__dark_office_chair
CAPABILITIES(/transformation/stack/steel__dark_office_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/bed/chair/office/dark, 1)),
		chosen = chosen(title = "dark office chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "office chairs")))

/transformation/stack/steel__light_office_chair
CAPABILITIES(/transformation/stack/steel__light_office_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/structure/bed/chair/office/light, 1)),
		chosen = chosen(title = "light office chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "office chairs")))

/transformation/stack/steel__beige_comfy_chair
CAPABILITIES(/transformation/stack/steel__beige_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/beige, 1)),
		chosen = chosen(title = "beige comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__black_comfy_chair
CAPABILITIES(/transformation/stack/steel__black_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/black, 1)),
		chosen = chosen(title = "black comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__brown_comfy_chair
CAPABILITIES(/transformation/stack/steel__brown_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/brown, 1)),
		chosen = chosen(title = "brown comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__lime_comfy_chair
CAPABILITIES(/transformation/stack/steel__lime_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/lime, 1)),
		chosen = chosen(title = "lime comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__teal_comfy_chair
CAPABILITIES(/transformation/stack/steel__teal_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/teal, 1)),
		chosen = chosen(title = "teal comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__red_comfy_chair
CAPABILITIES(/transformation/stack/steel__red_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/red, 1)),
		chosen = chosen(title = "red comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__blue_comfy_chair
CAPABILITIES(/transformation/stack/steel__blue_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/blue, 1)),
		chosen = chosen(title = "blue comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__purple_comfy_chair
CAPABILITIES(/transformation/stack/steel__purple_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/purp, 1)),
		chosen = chosen(title = "purple comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__green_comfy_chair
CAPABILITIES(/transformation/stack/steel__green_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/green, 1)),
		chosen = chosen(title = "green comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__yellow_comfy_chair
CAPABILITIES(/transformation/stack/steel__yellow_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/yellow, 1)),
		chosen = chosen(title = "yellow comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__orange_comfy_chair
CAPABILITIES(/transformation/stack/steel__orange_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/orange, 1)),
		chosen = chosen(title = "orange comfy chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "comfy chairs")))

/transformation/stack/steel__beige_rounded_chair
CAPABILITIES(/transformation/stack/steel__beige_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/beige, 1)),
		chosen = chosen(title = "beige rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__black_rounded_chair
CAPABILITIES(/transformation/stack/steel__black_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/black, 1)),
		chosen = chosen(title = "black rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__brown_rounded_chair
CAPABILITIES(/transformation/stack/steel__brown_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/brown, 1)),
		chosen = chosen(title = "brown rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__lime_rounded_chair
CAPABILITIES(/transformation/stack/steel__lime_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/lime, 1)),
		chosen = chosen(title = "lime rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__teal_rounded_chair
CAPABILITIES(/transformation/stack/steel__teal_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/teal, 1)),
		chosen = chosen(title = "teal rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__red_rounded_chair
CAPABILITIES(/transformation/stack/steel__red_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/red, 1)),
		chosen = chosen(title = "red rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__blue_rounded_chair
CAPABILITIES(/transformation/stack/steel__blue_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/blue, 1)),
		chosen = chosen(title = "blue rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__purple_rounded_chair
CAPABILITIES(/transformation/stack/steel__purple_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/purple, 1)),
		chosen = chosen(title = "purple rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__green_rounded_chair
CAPABILITIES(/transformation/stack/steel__green_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/green, 1)),
		chosen = chosen(title = "green rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__yellow_rounded_chair
CAPABILITIES(/transformation/stack/steel__yellow_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/yellow, 1)),
		chosen = chosen(title = "yellow rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__orange_rounded_chair
CAPABILITIES(/transformation/stack/steel__orange_rounded_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/comfy/rounded/orange, 1)),
		chosen = chosen(title = "orange rounded chair",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "rounded chairs")))

/transformation/stack/steel__standard_airlock_assembly
CAPABILITIES(/transformation/stack/steel__standard_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly, 1)),
		chosen = chosen(title = "standard airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__command_airlock_assembly
CAPABILITIES(/transformation/stack/steel__command_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_com, 1)),
		chosen = chosen(title = "command airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__security_airlock_assembly
CAPABILITIES(/transformation/stack/steel__security_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_sec, 1)),
		chosen = chosen(title = "security airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__eng_atmos_airlock_assembly
CAPABILITIES(/transformation/stack/steel__eng_atmos_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_eat, 1)),
		chosen = chosen(title = "eng atmos airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__engineering_airlock_assembly
CAPABILITIES(/transformation/stack/steel__engineering_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_eng, 1)),
		chosen = chosen(title = "engineering airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__mining_airlock_assembly
CAPABILITIES(/transformation/stack/steel__mining_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_min, 1)),
		chosen = chosen(title = "mining airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__atmospherics_airlock_assembly
CAPABILITIES(/transformation/stack/steel__atmospherics_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_atmo, 1)),
		chosen = chosen(title = "atmospherics airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__research_airlock_assembly
CAPABILITIES(/transformation/stack/steel__research_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_research, 1)),
		chosen = chosen(title = "research airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__medical_airlock_assembly
CAPABILITIES(/transformation/stack/steel__medical_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_med, 1)),
		chosen = chosen(title = "medical airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__maintenance_airlock_assembly
CAPABILITIES(/transformation/stack/steel__maintenance_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_mai, 1)),
		chosen = chosen(title = "maintenance airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__external_airlock_assembly
CAPABILITIES(/transformation/stack/steel__external_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_ext, 1)),
		chosen = chosen(title = "external airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__freezer_airlock_assembly
CAPABILITIES(/transformation/stack/steel__freezer_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_fre, 1)),
		chosen = chosen(title = "freezer airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__airtight_hatch_assembly
CAPABILITIES(/transformation/stack/steel__airtight_hatch_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_hatch, 1)),
		chosen = chosen(title = "airtight hatch assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__maintenance_hatch_assembly
CAPABILITIES(/transformation/stack/steel__maintenance_hatch_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_mhatch, 1)),
		chosen = chosen(title = "maintenance hatch assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__high_security_airlock_assembly
CAPABILITIES(/transformation/stack/steel__high_security_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_highsecurity, 1)),
		chosen = chosen(title = "high security airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__voidcraft_airlock_assembly_horizontal
CAPABILITIES(/transformation/stack/steel__voidcraft_airlock_assembly_horizontal)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_voidcraft, 1)),
		chosen = chosen(title = "voidcraft airlock assembly horizontal",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__voidcraft_airlock_assembly_vertical
CAPABILITIES(/transformation/stack/steel__voidcraft_airlock_assembly_vertical)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/door_assembly_voidcraft/vertical, 1)),
		chosen = chosen(title = "voidcraft airlock assembly vertical",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__emergency_shutter
CAPABILITIES(/transformation/stack/steel__emergency_shutter)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/firedoor_assembly, 1)),
		chosen = chosen(title = "emergency shutter",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__multi_tile_airlock_assembly
CAPABILITIES(/transformation/stack/steel__multi_tile_airlock_assembly)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/door_assembly/multi_tile, 1)),
		chosen = chosen(title = "multi-tile airlock assembly",
			subject = /datum/material/steel,
			build_time = 50,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "airlock assemblies")))

/transformation/stack/steel__modular_console_frame
CAPABILITIES(/transformation/stack/steel__modular_console_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 20)), makes = list(item_term(/obj/item/modular_computer/console, 1)),
		chosen = chosen(title = "modular console frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF,
			group = "modular computer frames")))

/transformation/stack/steel__modular_telescreen_frame
CAPABILITIES(/transformation/stack/steel__modular_telescreen_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/modular_computer/telescreen, 1)),
		chosen = chosen(title = "modular telescreen frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF,
			group = "modular computer frames")))

/transformation/stack/steel__modular_laptop_frame
CAPABILITIES(/transformation/stack/steel__modular_laptop_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/modular_computer/laptop, 1)),
		chosen = chosen(title = "modular laptop frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF,
			group = "modular computer frames")))

/transformation/stack/steel__modular_tablet_frame
CAPABILITIES(/transformation/stack/steel__modular_tablet_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/modular_computer/tablet, 1)),
		chosen = chosen(title = "modular tablet frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF,
			group = "modular computer frames")))

/transformation/stack/steel__filing_cabinet
CAPABILITIES(/transformation/stack/steel__filing_cabinet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/filingcabinet, 1)),
		chosen = chosen(title = "filing cabinet",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "filing cabinets")))

/transformation/stack/steel__tall_filing_cabinet
CAPABILITIES(/transformation/stack/steel__tall_filing_cabinet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/filingcabinet/filingcabinet, 1)),
		chosen = chosen(title = "tall filing cabinet",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "filing cabinets")))

/transformation/stack/steel__chest_drawer
CAPABILITIES(/transformation/stack/steel__chest_drawer)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/filingcabinet/chestdrawer, 1)),
		chosen = chosen(title = "chest drawer",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF,
			group = "filing cabinets")))

/transformation/stack/steel__table_frame
CAPABILITIES(/transformation/stack/steel__table_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/table, 1)),
		chosen = chosen(title = "table frame",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__bench_frame
CAPABILITIES(/transformation/stack/steel__bench_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/table/bench, 1)),
		chosen = chosen(title = "bench frame",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__rack
CAPABILITIES(/transformation/stack/steel__rack)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/table/rack, 1)),
		chosen = chosen(title = "rack",
			subject = /datum/material/steel,
			build_time = 5,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__steel_shelves
CAPABILITIES(/transformation/stack/steel__steel_shelves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/table/rack/shelf/steel, 1)),
		chosen = chosen(title = "steel shelves",
			subject = /datum/material/steel,
			build_time = 5,
			one_per_turf = TRUE,
			on_floor = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__closet
CAPABILITIES(/transformation/stack/steel__closet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/closet, 1)),
		chosen = chosen(title = "closet",
			subject = /datum/material/steel,
			build_time = 15,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__canister
CAPABILITIES(/transformation/stack/steel__canister)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/machinery/portable_atmospherics/canister, 1)),
		chosen = chosen(title = "canister",
			subject = /datum/material/steel,
			build_time = 15,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__cannon_frame
CAPABILITIES(/transformation/stack/steel__cannon_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/cannonframe, 1)),
		chosen = chosen(title = "cannon frame",
			subject = /datum/material/steel,
			build_time = 15,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__maintenance_panel
CAPABILITIES(/transformation/stack/steel__maintenance_panel)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/stack/tile/maintenance_panel, 1)),
		chosen = chosen(title = "maintenance panel",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__regular_floor_tile
CAPABILITIES(/transformation/stack/steel__regular_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor, 4)),
		chosen = chosen(title = "regular floor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

/transformation/stack/steel__steel_hi_grip_tile
CAPABILITIES(/transformation/stack/steel__steel_hi_grip_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/steelgrip, 4)),
		chosen = chosen(title = "steel hi-grip tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

/transformation/stack/steel__techfloor_tile
CAPABILITIES(/transformation/stack/steel__techfloor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/techgrey, 4)),
		chosen = chosen(title = "techfloor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

/transformation/stack/steel__techfloor_grid_tile
CAPABILITIES(/transformation/stack/steel__techfloor_grid_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/techgrid, 4)),
		chosen = chosen(title = "techfloor grid tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

/transformation/stack/steel__techmaint_floor_tile
CAPABILITIES(/transformation/stack/steel__techmaint_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/techmaint, 4)),
		chosen = chosen(title = "techmaint floor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "floor tiles")))

/transformation/stack/steel__floor_tile
CAPABILITIES(/transformation/stack/steel__floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel, 4)),
		chosen = chosen(title = "floor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__panel_tile
CAPABILITIES(/transformation/stack/steel__panel_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/panels, 4)),
		chosen = chosen(title = "panel tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__techfloor_tile_2
CAPABILITIES(/transformation/stack/steel__techfloor_tile_2)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/techfloor, 4)),
		chosen = chosen(title = "techfloor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__techfloor_tile_with_vents
CAPABILITIES(/transformation/stack/steel__techfloor_tile_with_vents)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/techfloor_grid, 4)),
		chosen = chosen(title = "techfloor tile with vents",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__brown_perforated_tile
CAPABILITIES(/transformation/stack/steel__brown_perforated_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/brown_perforated, 4)),
		chosen = chosen(title = "brown perforated tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__gray_perforated_tile
CAPABILITIES(/transformation/stack/steel__gray_perforated_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/gray_perforated, 4)),
		chosen = chosen(title = "gray perforated tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__cargo_tile
CAPABILITIES(/transformation/stack/steel__cargo_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/cargo, 4)),
		chosen = chosen(title = "cargo tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__brown_platform_tile
CAPABILITIES(/transformation/stack/steel__brown_platform_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/brown_platform, 4)),
		chosen = chosen(title = "brown platform tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__gray_platform_tile
CAPABILITIES(/transformation/stack/steel__gray_platform_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/gray_platform, 4)),
		chosen = chosen(title = "gray platform tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__danger_tile
CAPABILITIES(/transformation/stack/steel__danger_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/danger, 4)),
		chosen = chosen(title = "danger tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__golden_tile
CAPABILITIES(/transformation/stack/steel__golden_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/golden, 4)),
		chosen = chosen(title = "golden tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__monofloor_tile
CAPABILITIES(/transformation/stack/steel__monofloor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/monofloor, 4)),
		chosen = chosen(title = "monofloor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__bar_flat_tile
CAPABILITIES(/transformation/stack/steel__bar_flat_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/bar_flat, 4)),
		chosen = chosen(title = "bar flat tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__bar_dance_tile
CAPABILITIES(/transformation/stack/steel__bar_dance_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/bar_dance, 4)),
		chosen = chosen(title = "bar dance tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__bar_light_tile
CAPABILITIES(/transformation/stack/steel__bar_light_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/bar_light, 4)),
		chosen = chosen(title = "bar light tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal")))

/transformation/stack/steel__blue_corner_tile
CAPABILITIES(/transformation/stack/steel__blue_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/bluecorner, 4)),
		chosen = chosen(title = "blue corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal::corner tiles")))

/transformation/stack/steel__orange_corner_tile
CAPABILITIES(/transformation/stack/steel__orange_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/orangecorner, 4)),
		chosen = chosen(title = "orange corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal::corner tiles")))

/transformation/stack/steel__cyan_corner_tile
CAPABILITIES(/transformation/stack/steel__cyan_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/cyancorner, 4)),
		chosen = chosen(title = "cyan corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal::corner tiles")))

/transformation/stack/steel__violet_corner_tile
CAPABILITIES(/transformation/stack/steel__violet_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/steel/violetcorener, 4)),
		chosen = chosen(title = "violet corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-normal::corner tiles")))

/transformation/stack/steel__dark_floor_tile
CAPABILITIES(/transformation/stack/steel__dark_floor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark, 4)),
		chosen = chosen(title = "dark floor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_panel_tile
CAPABILITIES(/transformation/stack/steel__dark_panel_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/panels, 4)),
		chosen = chosen(title = "dark panel tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_techfloor_tile
CAPABILITIES(/transformation/stack/steel__dark_techfloor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/techfloor, 4)),
		chosen = chosen(title = "dark techfloor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_techfloor_tile_with_vents
CAPABILITIES(/transformation/stack/steel__dark_techfloor_tile_with_vents)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/techfloor_grid, 4)),
		chosen = chosen(title = "dark techfloor tile with vents",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_brown_perforated_tile
CAPABILITIES(/transformation/stack/steel__dark_brown_perforated_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/brown_perforated, 4)),
		chosen = chosen(title = "dark brown perforated tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_gray_perforated_tile
CAPABILITIES(/transformation/stack/steel__dark_gray_perforated_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/gray_perforated, 4)),
		chosen = chosen(title = "dark gray perforated tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_cargo_tile
CAPABILITIES(/transformation/stack/steel__dark_cargo_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/cargo, 4)),
		chosen = chosen(title = "dark cargo tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_brown_platform_tile
CAPABILITIES(/transformation/stack/steel__dark_brown_platform_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/brown_platform, 4)),
		chosen = chosen(title = "dark brown platform tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_gray_platform_tile
CAPABILITIES(/transformation/stack/steel__dark_gray_platform_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/gray_platform, 4)),
		chosen = chosen(title = "dark gray platform tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_danger_tile
CAPABILITIES(/transformation/stack/steel__dark_danger_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/danger, 4)),
		chosen = chosen(title = "dark danger tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_golden_tile
CAPABILITIES(/transformation/stack/steel__dark_golden_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/golden, 4)),
		chosen = chosen(title = "dark golden tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_monofloor_tile
CAPABILITIES(/transformation/stack/steel__dark_monofloor_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/monofloor, 4)),
		chosen = chosen(title = "dark monofloor tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark")))

/transformation/stack/steel__dark_blue_corner_tile
CAPABILITIES(/transformation/stack/steel__dark_blue_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/bluecorner, 4)),
		chosen = chosen(title = "dark blue corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark::dark corner tiles")))

/transformation/stack/steel__dark_orange_corner_tile
CAPABILITIES(/transformation/stack/steel__dark_orange_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/orangecorner, 4)),
		chosen = chosen(title = "dark orange corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark::dark corner tiles")))

/transformation/stack/steel__dark_cyan_corner_tile
CAPABILITIES(/transformation/stack/steel__dark_cyan_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/cyancorner, 4)),
		chosen = chosen(title = "dark cyan corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark::dark corner tiles")))

/transformation/stack/steel__dark_violet_corner_tile
CAPABILITIES(/transformation/stack/steel__dark_violet_corner_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/tile/floor/eris/dark/violetcorener, 4)),
		chosen = chosen(title = "dark violet corner tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF,
			group = "eris floors-dark::dark corner tiles")))

/transformation/stack/steel__roofing_tile
CAPABILITIES(/transformation/stack/steel__roofing_tile)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/stack/tile/roofing, 4)),
		chosen = chosen(title = "roofing tile",
			subject = /datum/material/steel,
			max_made = 20,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__metal_rod
CAPABILITIES(/transformation/stack/steel__metal_rod)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/rods, 2)),
		chosen = chosen(title = "metal rod",
			subject = /datum/material/steel,
			max_made = 60,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__frame_parts
CAPABILITIES(/transformation/stack/steel__frame_parts)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/frame, 1)),
		chosen = chosen(title = "frame parts",
			subject = /datum/material/steel,
			build_time = 25,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__mirror_frame
CAPABILITIES(/transformation/stack/steel__mirror_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/frame/mirror, 1)),
		chosen = chosen(title = "mirror frame",
			subject = /datum/material/steel,
			build_time = 5,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__fire_extinguisher_cabinet_frame
CAPABILITIES(/transformation/stack/steel__fire_extinguisher_cabinet_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/frame/extinguisher_cabinet, 1)),
		chosen = chosen(title = "fire extinguisher cabinet frame",
			subject = /datum/material/steel,
			build_time = 5,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__railing
CAPABILITIES(/transformation/stack/steel__railing)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/railing, 1)),
		chosen = chosen(title = "railing",
			subject = /datum/material/steel,
			build_time = 50,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__turret_frame
CAPABILITIES(/transformation/stack/steel__turret_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/machinery/porta_turret_construct, 1)),
		chosen = chosen(title = "turret frame",
			subject = /datum/material/steel,
			build_time = 25,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__medical_stand
CAPABILITIES(/transformation/stack/steel__medical_stand)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/medical_stand, 1)),
		chosen = chosen(title = "medical stand",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__conveyor_switch
CAPABILITIES(/transformation/stack/steel__conveyor_switch)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/machinery/conveyor_switch, 1)),
		chosen = chosen(title = "conveyor switch",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__grenade_casing
CAPABILITIES(/transformation/stack/steel__grenade_casing)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/grenade/chem_grenade, 1)),
		chosen = chosen(title = "grenade casing",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__light_fixture_frame
CAPABILITIES(/transformation/stack/steel__light_fixture_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/frame/light, 1)),
		chosen = chosen(title = "light fixture frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__floor_light_fixture_frame
CAPABILITIES(/transformation/stack/steel__floor_light_fixture_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/machinery/light_construct/floortube, 1)),
		chosen = chosen(title = "floor light fixture frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__small_light_fixture_frame
CAPABILITIES(/transformation/stack/steel__small_light_fixture_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/frame/light/small, 1)),
		chosen = chosen(title = "small light fixture frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__floor_lamp_fixture_frame
CAPABILITIES(/transformation/stack/steel__floor_lamp_fixture_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/machinery/light_construct/flamp, 1)),
		chosen = chosen(title = "floor lamp fixture frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__big_floor_lamp_fixture_frame
CAPABILITIES(/transformation/stack/steel__big_floor_lamp_fixture_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/machinery/light_construct/bigfloorlamp, 1)),
		chosen = chosen(title = "big floor lamp fixture frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__apc_frame
CAPABILITIES(/transformation/stack/steel__apc_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/frame/apc, 1)),
		chosen = chosen(title = "apc frame",
			subject = /datum/material/steel,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__desk_bell
CAPABILITIES(/transformation/stack/steel__desk_bell)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/deskbell, 1)),
		chosen = chosen(title = "desk bell",
			subject = /datum/material/steel,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/steel__steel_kettle
CAPABILITIES(/transformation/stack/steel__steel_kettle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/reagent_containers/glass/kettle, 1)),
		chosen = chosen(title = "steel kettle",
			subject = /datum/material/steel,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/steel__bunsen_burner
CAPABILITIES(/transformation/stack/steel__bunsen_burner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/machinery/bunsen_burner, 1)),
		chosen = chosen(title = "bunsen burner",
			subject = /datum/material/steel,
			build_time = 25,
			on_floor = 1,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/steel__tanning_rack
CAPABILITIES(/transformation/stack/steel__tanning_rack)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/tanning_rack, 1)),
		chosen = chosen(title = "tanning rack",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = TRUE,
			on_floor = TRUE,
			material = STACK_MATERIAL_SELF)))

/transformation/stack/steel__steel_hull_sheet
CAPABILITIES(/transformation/stack/steel__steel_hull_sheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/material/steel/hull, 1)),
		chosen = chosen(title = "steel hull sheet",
			subject = /datum/material/steel,
			max_made = 5,
			build_time = 20,
			on_floor = 1,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/steel__mounted_chair
CAPABILITIES(/transformation/stack/steel__mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair, 1)),
		chosen = chosen(title = "mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__red_mounted_chair
CAPABILITIES(/transformation/stack/steel__red_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/red, 1)),
		chosen = chosen(title = "red mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__brown_mounted_chair
CAPABILITIES(/transformation/stack/steel__brown_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/brown, 1)),
		chosen = chosen(title = "brown mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__teal_mounted_chair
CAPABILITIES(/transformation/stack/steel__teal_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/teal, 1)),
		chosen = chosen(title = "teal mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__black_mounted_chair
CAPABILITIES(/transformation/stack/steel__black_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/black, 1)),
		chosen = chosen(title = "black mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__green_mounted_chair
CAPABILITIES(/transformation/stack/steel__green_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/green, 1)),
		chosen = chosen(title = "green mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__purple_mounted_chair
CAPABILITIES(/transformation/stack/steel__purple_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/purple, 1)),
		chosen = chosen(title = "purple mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__blue_mounted_chair
CAPABILITIES(/transformation/stack/steel__blue_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/blue, 1)),
		chosen = chosen(title = "blue mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__beige_mounted_chair
CAPABILITIES(/transformation/stack/steel__beige_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/beige, 1)),
		chosen = chosen(title = "beige mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__lime_mounted_chair
CAPABILITIES(/transformation/stack/steel__lime_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/lime, 1)),
		chosen = chosen(title = "lime mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__yellow_mounted_chair
CAPABILITIES(/transformation/stack/steel__yellow_mounted_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/yellow, 1)),
		chosen = chosen(title = "yellow mounted chair",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted chairs")))

/transformation/stack/steel__mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy, 1)),
		chosen = chosen(title = "mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__red_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__red_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/red, 1)),
		chosen = chosen(title = "red mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__brown_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__brown_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/brown, 1)),
		chosen = chosen(title = "brown mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__teal_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__teal_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/teal, 1)),
		chosen = chosen(title = "teal mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__black_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__black_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/black, 1)),
		chosen = chosen(title = "black mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__green_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__green_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/green, 1)),
		chosen = chosen(title = "green mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__purple_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__purple_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/purple, 1)),
		chosen = chosen(title = "purple mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__blue_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__blue_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/blue, 1)),
		chosen = chosen(title = "blue mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__beige_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__beige_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/beige, 1)),
		chosen = chosen(title = "beige mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__lime_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__lime_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/lime, 1)),
		chosen = chosen(title = "lime mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__yellow_mounted_comfy_chair
CAPABILITIES(/transformation/stack/steel__yellow_mounted_comfy_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/yellow, 1)),
		chosen = chosen(title = "yellow mounted comfy chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1,
			group = "mounted comfy chairs")))

/transformation/stack/steel__mounted_captain_s_chair
CAPABILITIES(/transformation/stack/steel__mounted_captain_s_chair)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/bed/chair/bay/comfy/captain, 1)),
		chosen = chosen(title = "mounted captain's chair",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1)))

/transformation/stack/steel__dropship_seat
CAPABILITIES(/transformation/stack/steel__dropship_seat)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/bed/chair/bay/shuttle, 1)),
		chosen = chosen(title = "dropship seat",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1)))

/transformation/stack/steel__small_teshari_nest
CAPABILITIES(/transformation/stack/steel__small_teshari_nest)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/red/smallnest, 1)),
		chosen = chosen(title = "small teshari nest",
			subject = /datum/material/steel,
			build_time = 10,
			one_per_turf = 1,
			on_floor = 1)))

/transformation/stack/steel__large_teshari_nest
CAPABILITIES(/transformation/stack/steel__large_teshari_nest)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/structure/bed/chair/bay/chair/padded/red/bignest, 1)),
		chosen = chosen(title = "large teshari nest",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1)))

/transformation/stack/steel__dance_pole
CAPABILITIES(/transformation/stack/steel__dance_pole)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/structure/dancepole, 1)),
		chosen = chosen(title = "dance pole",
			subject = /datum/material/steel,
			build_time = 20,
			one_per_turf = 1,
			on_floor = 1)))

/transformation/stack/steel__light_switch_frame
CAPABILITIES(/transformation/stack/steel__light_switch_frame)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/frame/lightswitch, 1)),
		chosen = chosen(title = "light switch frame",
			subject = /datum/material/steel)))

/transformation/stack/steel__red_sofa_middle
CAPABILITIES(/transformation/stack/steel__red_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa, 1)),
		chosen = chosen(title = "red sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__red_sofa_left
CAPABILITIES(/transformation/stack/steel__red_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left, 1)),
		chosen = chosen(title = "red sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__red_sofa_right
CAPABILITIES(/transformation/stack/steel__red_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right, 1)),
		chosen = chosen(title = "red sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__red_sofa_corner
CAPABILITIES(/transformation/stack/steel__red_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner, 1)),
		chosen = chosen(title = "red sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__brown_sofa_middle
CAPABILITIES(/transformation/stack/steel__brown_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/brown, 1)),
		chosen = chosen(title = "brown sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__brown_sofa_left
CAPABILITIES(/transformation/stack/steel__brown_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/brown, 1)),
		chosen = chosen(title = "brown sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__brown_sofa_right
CAPABILITIES(/transformation/stack/steel__brown_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/brown, 1)),
		chosen = chosen(title = "brown sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__brown_sofa_corner
CAPABILITIES(/transformation/stack/steel__brown_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/brown, 1)),
		chosen = chosen(title = "brown sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__teal_sofa_middle
CAPABILITIES(/transformation/stack/steel__teal_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/teal, 1)),
		chosen = chosen(title = "teal sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__teal_sofa_left
CAPABILITIES(/transformation/stack/steel__teal_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/teal, 1)),
		chosen = chosen(title = "teal sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__teal_sofa_right
CAPABILITIES(/transformation/stack/steel__teal_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/teal, 1)),
		chosen = chosen(title = "teal sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__teal_sofa_corner
CAPABILITIES(/transformation/stack/steel__teal_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/teal, 1)),
		chosen = chosen(title = "teal sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__black_sofa_middle
CAPABILITIES(/transformation/stack/steel__black_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/black, 1)),
		chosen = chosen(title = "black sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__black_sofa_left
CAPABILITIES(/transformation/stack/steel__black_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/black, 1)),
		chosen = chosen(title = "black sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__black_sofa_right
CAPABILITIES(/transformation/stack/steel__black_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/black, 1)),
		chosen = chosen(title = "black sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__black_sofa_corner
CAPABILITIES(/transformation/stack/steel__black_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/black, 1)),
		chosen = chosen(title = "black sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__green_sofa_middle
CAPABILITIES(/transformation/stack/steel__green_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/green, 1)),
		chosen = chosen(title = "green sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__green_sofa_left
CAPABILITIES(/transformation/stack/steel__green_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/green, 1)),
		chosen = chosen(title = "green sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__green_sofa_right
CAPABILITIES(/transformation/stack/steel__green_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/green, 1)),
		chosen = chosen(title = "green sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__green_sofa_corner
CAPABILITIES(/transformation/stack/steel__green_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/green, 1)),
		chosen = chosen(title = "green sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__purple_sofa_middle
CAPABILITIES(/transformation/stack/steel__purple_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/purp, 1)),
		chosen = chosen(title = "purple sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__purple_sofa_left
CAPABILITIES(/transformation/stack/steel__purple_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/purp, 1)),
		chosen = chosen(title = "purple sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__purple_sofa_right
CAPABILITIES(/transformation/stack/steel__purple_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/purp, 1)),
		chosen = chosen(title = "purple sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__purple_sofa_corner
CAPABILITIES(/transformation/stack/steel__purple_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/purp, 1)),
		chosen = chosen(title = "purple sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__blue_sofa_middle
CAPABILITIES(/transformation/stack/steel__blue_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/blue, 1)),
		chosen = chosen(title = "blue sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__blue_sofa_left
CAPABILITIES(/transformation/stack/steel__blue_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/blue, 1)),
		chosen = chosen(title = "blue sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__blue_sofa_right
CAPABILITIES(/transformation/stack/steel__blue_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/blue, 1)),
		chosen = chosen(title = "blue sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__blue_sofa_corner
CAPABILITIES(/transformation/stack/steel__blue_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/blue, 1)),
		chosen = chosen(title = "blue sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__beige_sofa_middle
CAPABILITIES(/transformation/stack/steel__beige_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/beige, 1)),
		chosen = chosen(title = "beige sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__beige_sofa_left
CAPABILITIES(/transformation/stack/steel__beige_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/beige, 1)),
		chosen = chosen(title = "beige sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__beige_sofa_right
CAPABILITIES(/transformation/stack/steel__beige_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/beige, 1)),
		chosen = chosen(title = "beige sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__beige_sofa_corner
CAPABILITIES(/transformation/stack/steel__beige_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/beige, 1)),
		chosen = chosen(title = "beige sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__lime_sofa_middle
CAPABILITIES(/transformation/stack/steel__lime_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/lime, 1)),
		chosen = chosen(title = "lime sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__lime_sofa_left
CAPABILITIES(/transformation/stack/steel__lime_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/lime, 1)),
		chosen = chosen(title = "lime sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__lime_sofa_right
CAPABILITIES(/transformation/stack/steel__lime_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/lime, 1)),
		chosen = chosen(title = "lime sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__lime_sofa_corner
CAPABILITIES(/transformation/stack/steel__lime_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/lime, 1)),
		chosen = chosen(title = "lime sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__yellow_sofa_middle
CAPABILITIES(/transformation/stack/steel__yellow_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/yellow, 1)),
		chosen = chosen(title = "yellow sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__yellow_sofa_left
CAPABILITIES(/transformation/stack/steel__yellow_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/yellow, 1)),
		chosen = chosen(title = "yellow sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__yellow_sofa_right
CAPABILITIES(/transformation/stack/steel__yellow_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/yellow, 1)),
		chosen = chosen(title = "yellow sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__yellow_sofa_corner
CAPABILITIES(/transformation/stack/steel__yellow_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/yellow, 1)),
		chosen = chosen(title = "yellow sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__orange_sofa_middle
CAPABILITIES(/transformation/stack/steel__orange_sofa_middle)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/orange, 1)),
		chosen = chosen(title = "orange sofa middle",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__orange_sofa_left
CAPABILITIES(/transformation/stack/steel__orange_sofa_left)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/left/orange, 1)),
		chosen = chosen(title = "orange sofa left",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__orange_sofa_right
CAPABILITIES(/transformation/stack/steel__orange_sofa_right)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/right/orange, 1)),
		chosen = chosen(title = "orange sofa right",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

/transformation/stack/steel__orange_sofa_corner
CAPABILITIES(/transformation/stack/steel__orange_sofa_corner)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/structure/bed/chair/sofa/corner/orange, 1)),
		chosen = chosen(title = "orange sofa corner",
			subject = /datum/material/steel,
			one_per_turf = 1,
			on_floor = 1,
			group = "sofas")))

