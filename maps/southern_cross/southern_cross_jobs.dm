// Pilots

/datum/access/pilot
	id = ACCESS_PILOT
	desc = "Pilot"
	region = ACCESS_REGION_SUPPLY

/datum/access/explorer
	id = ACCESS_EXPLORER
	desc = "Explorer"
	region = ACCESS_REGION_GENERAL

//SC Jobs

/datum/department/planetside
	name = DEPARTMENT_PLANET
	color = "#555555"
	sorting_order = 2 // Same as cargo in importance.

/datum/job/pilot
	title = "Pilot"
	flag = PILOT
	departments = list(DEPARTMENT_PLANET)
	department_flag = CIVILIAN
	faction = FACTION_STATION
	total_positions = 2
	spawn_positions = 2
	supervisors = "the Head of Personnel"
	selection_color = "#515151"
	economic_modifier = 4
	access = list(ACCESS_PILOT, ACCESS_CARGO, ACCESS_MINING, ACCESS_MINING_STATION)
	minimal_access = list(ACCESS_PILOT, ACCESS_CARGO, ACCESS_MINING, ACCESS_MINING_STATION)

	outfit_type = /datum/decl/hierarchy/outfit/job/pilot
	job_description = "A Pilot flies one of the shuttles between the Southern Cross and the outpost on Sif."

/datum/job/explorer
	title = "Explorer"
	flag = EXPLORER
	departments = list(DEPARTMENT_RESEARCH, DEPARTMENT_PLANET)
	department_flag = MEDSCI
	faction = FACTION_STATION
	total_positions = 4
	spawn_positions = 4
	supervisors = "the Research Director"
	selection_color =  "#633D63"
	economic_modifier = 4
	access = list(ACCESS_EXPLORER, ACCESS_RESEARCH)
	minimal_access = list(ACCESS_EXPLORER, ACCESS_RESEARCH)
	banned_job_species = list(SPECIES_ZADDAT)

	outfit_type = /datum/decl/hierarchy/outfit/job/explorer2
	job_description = "An Explorer searches for interesting things on the surface of Sif, and returns them to the station."

/datum/job/sar
	title = "Search and Rescue"
	flag = SAR
	departments = list(DEPARTMENT_PLANET, DEPARTMENT_MEDICAL)
	department_flag = MEDSCI
	faction = FACTION_STATION
	total_positions = 2
	spawn_positions = 2
	supervisors = "the Chief Medical Officer"
	selection_color = "#515151"
	economic_modifier = 4
	access = list(ACCESS_MEDICAL, ACCESS_MEDICAL_EQUIP, ACCESS_MORGUE, ACCESS_SURGERY, ACCESS_CHEMISTRY, ACCESS_VIROLOGY, ACCESS_EVA, ACCESS_MAINT_TUNNELS, ACCESS_EXTERNAL_AIRLOCKS, ACCESS_PSYCHIATRIST, ACCESS_EXPLORER)
	minimal_access = list(ACCESS_MEDICAL, ACCESS_MEDICAL_EQUIP, ACCESS_MORGUE, ACCESS_EXPLORER)
	min_age_by_species = list(SPECIES_PROMETHEAN = 2)

	outfit_type = /datum/decl/hierarchy/outfit/job/medical/sar
	job_description = "A Search and Rescue operative recovers individuals who are injured or dead on the surface of Sif."
