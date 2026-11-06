/// A compact authored activity motif. The room solver positions the complete
/// arrangement as one unit, preserving relationships that independent feature
/// placement cannot express reliably.
/datum/generated_room_fragment/activity_motif
	width = 4
	height = 3
	allow_rotation = FALSE
	allow_mirroring = FALSE
	anchor_kind = "wall"
	// Irregular rooms frequently have a stepped bounding edge. The typed
	// against-wall constraint chooses real local frontage; pinning every motif
	// to the bounding-box north edge made spacious rooms incorrectly fall back
	// to compact content when that one edge happened to be recessed.
	anchor_edge = null
	var/list/feature_types

/datum/generated_room_fragment/activity_motif/New()
	feature_types = TYPE_TABLE_GET(src, build_motif_feature_types)
	return ..()

TYPE_TABLE_DECLARE(/datum/generated_room_fragment/activity_motif, build_motif_feature_types, list())

/datum/generated_room_fragment/activity_motif/composition_atom_types()
	var/list/atom_types = list()
	for(var/feature_type in feature_types)
		var/datum/generated_room_feature/feature = new feature_type
		if(feature.atom_type)
			atom_types += feature.atom_type
		spent(feature)
	return atom_types

// The semantic motif types are authored compositions, not aliases for one
// universal T-shaped furniture stamp. Spread the catalog across five stable
// arrangements (picked by length(id) % 5) so adjacent rooms with different purposes
// also have visibly different silhouettes.
GLOBAL_LIST_INIT(generated_motif_offset_patterns, list(
	list(list(1, 1), list(2, 1), list(3, 1), list(2, 2)),
	list(list(1, 1), list(1, 2), list(2, 2), list(3, 2)),
	list(list(1, 1), list(2, 1), list(3, 1), list(3, 2)),
	list(list(1, 1), list(1, 2), list(2, 1), list(3, 1)),
	list(list(1, 1), list(2, 1), list(2, 2), list(3, 2)),
))

TYPE_TABLE(/datum/generated_room_fragment/activity_motif, build_occupied_offsets, GLOB.generated_motif_offset_patterns[(length(id) % 5) + 1])

/datum/generated_room_fragment/activity_motif/build_constraints()
	return list(
		new /datum/generated_room_constraint/against_wall(id),
		new /datum/generated_room_constraint/clear_frontage(id),
		new /datum/generated_room_constraint/requires_access_path(id),
	)

/datum/generated_room_fragment/activity_motif/materialize(turf/origin, rotation, mirrored, datum/generated_station_materialization/owner)
	if(!origin || !owner || rotation || mirrored || !length(feature_types))
		return FALSE
	for(var/i in 1 to min(length(feature_types), length(occupied_offsets)))
		var/feature_type = feature_types[i]
		var/datum/generated_room_feature/feature = new feature_type
		var/list/offset = occupied_offsets[i]
		var/turf/target = locate(origin.x + offset[1] - 1, origin.y + offset[2] - 1, origin.z)
		if(!target || target.density || !feature.atom_type)
			spent(feature)
			return FALSE
		var/atom/movable/created = new feature.atom_type(target)
		created.set_dir(feature.placement_kind == "wall" ? SOUTH : NORTH)
		owner.register_furnishing(created)
		spent(feature)
	return TRUE

// Command: public service, administration, communications, planning, records, briefing.
/datum/generated_room_fragment/activity_motif/command_service
	id = "command-service"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/command_service, build_motif_feature_types, list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/id_console, /datum/generated_room_feature/reception_chair))
/datum/generated_room_fragment/activity_motif/command_admin
	id = "command-administration"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/command_admin, build_motif_feature_types, list(/datum/generated_room_feature/id_console, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/work_table, /datum/generated_room_feature/work_chair))
/datum/generated_room_fragment/activity_motif/command_comms
	id = "command-communications"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/command_comms, build_motif_feature_types, list(/datum/generated_room_feature/communications_console, /datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/work_table, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/command_planning
	id = "command-planning"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/command_planning, build_motif_feature_types, list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/work_chair))
/datum/generated_room_fragment/activity_motif/command_records
	id = "command-records"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/command_records, build_motif_feature_types, list(/datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/id_console, /datum/generated_room_feature/work_chair))
/datum/generated_room_fragment/activity_motif/command_briefing
	id = "command-briefing"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/command_briefing, build_motif_feature_types, list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/work_table, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/operator_chair))

// AI: monitoring, upload, robotics, server support, secure equipment, operator control.
/datum/generated_room_fragment/activity_motif/ai_monitoring
	id = "ai-monitoring"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/ai_monitoring, build_motif_feature_types, list(/datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/security_console, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/ai_upload
	id = "ai-upload"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/ai_upload, build_motif_feature_types, list(/datum/generated_room_feature/ai_upload, /datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/ai_robotics
	id = "ai-robotics"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/ai_robotics, build_motif_feature_types, list(/datum/generated_room_feature/robotics_console, /datum/generated_room_feature/autolathe, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/ai_server
	id = "ai-server-support"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/ai_server, build_motif_feature_types, list(/datum/generated_room_feature/robotics_console, /datum/generated_room_feature/power_monitor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/ai_secure
	id = "ai-secure-equipment"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/ai_secure, build_motif_feature_types, list(/datum/generated_room_feature/ai_upload, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/security_locker))
/datum/generated_room_fragment/activity_motif/ai_operator
	id = "ai-operator-control"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/ai_operator, build_motif_feature_types, list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/robotics_console, /datum/generated_room_feature/work_table, /datum/generated_room_feature/operator_chair))

// Security: desk, armory, evidence, interrogation, equipment, brig support.
/datum/generated_room_fragment/activity_motif/security_desk
	id = "security-desk"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/security_desk, build_motif_feature_types, list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/security_records, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/security_armory
	id = "security-armory"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/security_armory, build_motif_feature_types, list(/datum/generated_room_feature/armory_autolathe, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/security_locker))
/datum/generated_room_fragment/activity_motif/security_evidence
	id = "security-evidence"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/security_evidence, build_motif_feature_types, list(/datum/generated_room_feature/security_records, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/work_chair))
/datum/generated_room_fragment/activity_motif/security_interview
	id = "security-interview"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/security_interview, build_motif_feature_types, list(/datum/generated_room_feature/reinforced_table, /datum/generated_room_feature/security_records, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/security_equipment
	id = "security-equipment"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/security_equipment, build_motif_feature_types, list(/datum/generated_room_feature/security_locker, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/reinforced_table))
/datum/generated_room_fragment/activity_motif/security_brig
	id = "security-brig-support"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/security_brig, build_motif_feature_types, list(/datum/generated_room_feature/cell_timer, /datum/generated_room_feature/security_console, /datum/generated_room_feature/brig_bed, /datum/generated_room_feature/operator_chair))

// Medical: examination, treatment, surgery, pharmacy, recovery, stores.
/datum/generated_room_fragment/activity_motif/medical_exam
	id = "medical-examination"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/medical_exam, build_motif_feature_types, list(/datum/generated_room_feature/patient_bed, /datum/generated_room_feature/medical_vendor, /datum/generated_room_feature/sink, /datum/generated_room_feature/iv_drip))
/datum/generated_room_fragment/activity_motif/medical_treatment
	id = "medical-treatment"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/medical_treatment, build_motif_feature_types, list(/datum/generated_room_feature/sleeper, /datum/generated_room_feature/medical_storage, /datum/generated_room_feature/sink, /datum/generated_room_feature/iv_drip))
/datum/generated_room_fragment/activity_motif/medical_surgery
	id = "medical-surgery"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/medical_surgery, build_motif_feature_types, list(/datum/generated_room_feature/operating_computer, /datum/generated_room_feature/medical_storage, /datum/generated_room_feature/surgery_table, /datum/generated_room_feature/iv_drip))
/datum/generated_room_fragment/activity_motif/medical_pharmacy
	id = "medical-pharmacy"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/medical_pharmacy, build_motif_feature_types, list(/datum/generated_room_feature/chemical_dispenser, /datum/generated_room_feature/chem_master, /datum/generated_room_feature/reagent_grinder, /datum/generated_room_feature/sink))
/datum/generated_room_fragment/activity_motif/medical_recovery
	id = "medical-recovery"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/medical_recovery, build_motif_feature_types, list(/datum/generated_room_feature/sleeper, /datum/generated_room_feature/patient_bed, /datum/generated_room_feature/medical_vendor, /datum/generated_room_feature/iv_drip))
/datum/generated_room_fragment/activity_motif/medical_stores
	id = "medical-stores"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/medical_stores, build_motif_feature_types, list(/datum/generated_room_feature/medical_storage, /datum/generated_room_feature/medical_storage, /datum/generated_room_feature/oxygen_canister, /datum/generated_room_feature/work_table))

// Engineering: fabrication, power, atmospherics, tools, maintenance, stores.
/datum/generated_room_fragment/activity_motif/engineering_fabrication
	id = "engineering-fabrication"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/engineering_fabrication, build_motif_feature_types, list(/datum/generated_room_feature/autolathe, /datum/generated_room_feature/tool_vendor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/work_table))
/datum/generated_room_fragment/activity_motif/engineering_power
	id = "engineering-power"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/engineering_power, build_motif_feature_types, list(/datum/generated_room_feature/power_monitor, /datum/generated_room_feature/engineering_vendor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/engineering_atmos
	id = "engineering-atmospherics"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/engineering_atmos, build_motif_feature_types, list(/datum/generated_room_feature/atmos_control, /datum/generated_room_feature/air_sensor, /datum/generated_room_feature/air_canister, /datum/generated_room_feature/oxygen_canister))
/datum/generated_room_fragment/activity_motif/engineering_tools
	id = "engineering-tools"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/engineering_tools, build_motif_feature_types, list(/datum/generated_room_feature/tool_vendor, /datum/generated_room_feature/engineering_vendor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/work_table))
/datum/generated_room_fragment/activity_motif/engineering_maintenance
	id = "engineering-maintenance"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/engineering_maintenance, build_motif_feature_types, list(/datum/generated_room_feature/recharger, /datum/generated_room_feature/air_sensor, /datum/generated_room_feature/atmos_locker, /datum/generated_room_feature/work_table))
/datum/generated_room_fragment/activity_motif/engineering_stores
	id = "engineering-stores"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/engineering_stores, build_motif_feature_types, list(/datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/atmos_locker, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/recharger))

// Logistics: intake, freight, sorting, dispatch, inventory, bulk storage.
/datum/generated_room_fragment/activity_motif/logistics_intake
	id = "logistics-intake"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/logistics_intake, build_motif_feature_types, list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/supply_console, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/reception_chair))
/datum/generated_room_fragment/activity_motif/logistics_freight
	id = "logistics-freight"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/logistics_freight, build_motif_feature_types, list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_locker, /datum/generated_room_feature/work_table))
/datum/generated_room_fragment/activity_motif/logistics_sorting
	id = "logistics-sorting"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/logistics_sorting, build_motif_feature_types, list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/logistics_dispatch
	id = "logistics-dispatch"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/logistics_dispatch, build_motif_feature_types, list(/datum/generated_room_feature/supply_console, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/logistics_inventory
	id = "logistics-inventory"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/logistics_inventory, build_motif_feature_types, list(/datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/cargo_locker, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/work_chair))
/datum/generated_room_fragment/activity_motif/logistics_bulk
	id = "logistics-bulk-storage"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/logistics_bulk, build_motif_feature_types, list(/datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/cargo_locker))

// Docking: control, customs, security, passenger lounge, equipment, supply.
/datum/generated_room_fragment/activity_motif/docking_control
	id = "docking-control"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/docking_control, build_motif_feature_types, list(/datum/generated_room_feature/communications_console, /datum/generated_room_feature/security_console, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/docking_customs
	id = "docking-customs"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/docking_customs, build_motif_feature_types, list(/datum/generated_room_feature/id_console, /datum/generated_room_feature/security_records, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/docking_security
	id = "docking-security"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/docking_security, build_motif_feature_types, list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair))
/datum/generated_room_fragment/activity_motif/docking_lounge
	id = "docking-lounge"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/docking_lounge, build_motif_feature_types, list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/shuttle_seat, /datum/generated_room_feature/shuttle_seat, /datum/generated_room_feature/reception_chair))
/datum/generated_room_fragment/activity_motif/docking_equipment
	id = "docking-equipment"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/docking_equipment, build_motif_feature_types, list(/datum/generated_room_feature/oxygen_canister, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/recharger, /datum/generated_room_feature/work_table))
/datum/generated_room_fragment/activity_motif/docking_supply
	id = "docking-supply"
TYPE_TABLE(/datum/generated_room_fragment/activity_motif/docking_supply, build_motif_feature_types, list(/datum/generated_room_feature/internals_crate, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_locker, /datum/generated_room_feature/shuttle_seat))

GLOBAL_LIST_INIT(generated_room_semantic_fragments, list(
	"command/reception" = list(/datum/generated_room_fragment/activity_motif/command_service, /datum/generated_room_fragment/reception_corner),
	"command/communications" = list(/datum/generated_room_fragment/activity_motif/command_comms, /datum/generated_room_fragment/activity_motif/command_planning),
	"command/records" = list(/datum/generated_room_fragment/activity_motif/command_records, /datum/generated_room_fragment/activity_motif/command_admin),
	"command/archive" = list(/datum/generated_room_fragment/activity_motif/command_records, /datum/generated_room_fragment/activity_motif/command_admin),
	"command/meeting" = list(/datum/generated_room_fragment/activity_motif/command_briefing, /datum/generated_room_fragment/activity_motif/command_planning),
	"command/briefing" = list(/datum/generated_room_fragment/activity_motif/command_briefing, /datum/generated_room_fragment/activity_motif/command_planning),
	"command" = list(/datum/generated_room_fragment/activity_motif/command_admin, /datum/generated_room_fragment/activity_motif/command_comms),
	"ai/foyer" = list(/datum/generated_room_fragment/activity_motif/ai_operator, /datum/generated_room_fragment/activity_motif/ai_monitoring),
	"ai/robotics" = list(/datum/generated_room_fragment/activity_motif/ai_robotics, /datum/generated_room_fragment/activity_motif/ai_operator),
	"ai/server-closet" = list(/datum/generated_room_fragment/activity_motif/ai_server, /datum/generated_room_fragment/activity_motif/ai_robotics),
	"ai/support" = list(/datum/generated_room_fragment/activity_motif/ai_server, /datum/generated_room_fragment/activity_motif/ai_robotics),
	"ai/secure-storage" = list(/datum/generated_room_fragment/activity_motif/ai_secure, /datum/generated_room_fragment/activity_motif/ai_server),
	"ai/satellite" = list(/datum/generated_room_fragment/activity_motif/ai_monitoring, /datum/generated_room_fragment/activity_motif/ai_upload),
	"ai/monitoring" = list(/datum/generated_room_fragment/activity_motif/ai_monitoring, /datum/generated_room_fragment/activity_motif/ai_upload),
	"ai" = list(/datum/generated_room_fragment/activity_motif/ai_operator, /datum/generated_room_fragment/activity_motif/ai_monitoring),
	"security/reception" = list(/datum/generated_room_fragment/activity_motif/security_desk, /datum/generated_room_fragment/activity_motif/security_interview),
	"security/armory" = list(/datum/generated_room_fragment/activity_motif/security_armory, /datum/generated_room_fragment/activity_motif/security_equipment),
	"security/locker-room" = list(/datum/generated_room_fragment/activity_motif/security_armory, /datum/generated_room_fragment/activity_motif/security_equipment),
	"security/evidence" = list(/datum/generated_room_fragment/activity_motif/security_evidence, /datum/generated_room_fragment/activity_motif/security_desk),
	"security/interrogation" = list(/datum/generated_room_fragment/activity_motif/security_interview, /datum/generated_room_fragment/activity_motif/security_desk),
	"security/checkpoint" = list(/datum/generated_room_fragment/activity_motif/security_interview, /datum/generated_room_fragment/activity_motif/security_desk),
	"security/brig" = list(/datum/generated_room_fragment/activity_motif/security_brig, /datum/generated_room_fragment/activity_motif/security_equipment),
	"security" = list(/datum/generated_room_fragment/activity_motif/security_desk, /datum/generated_room_fragment/activity_motif/security_equipment),
	"medical/reception" = list(/datum/generated_room_fragment/activity_motif/medical_exam, /datum/generated_room_fragment/activity_motif/medical_stores),
	"medical/surgery" = list(/datum/generated_room_fragment/activity_motif/medical_surgery, /datum/generated_room_fragment/treatment_bay),
	"medical/treatment" = list(/datum/generated_room_fragment/activity_motif/medical_exam, /datum/generated_room_fragment/activity_motif/medical_treatment),
	"medical/exam" = list(/datum/generated_room_fragment/activity_motif/medical_exam, /datum/generated_room_fragment/activity_motif/medical_treatment),
	"medical/pharmacy" = list(/datum/generated_room_fragment/activity_motif/medical_pharmacy, /datum/generated_room_fragment/activity_motif/medical_stores),
	"medical/recovery" = list(/datum/generated_room_fragment/activity_motif/medical_recovery, /datum/generated_room_fragment/activity_motif/medical_treatment),
	"medical/ward" = list(/datum/generated_room_fragment/activity_motif/medical_recovery, /datum/generated_room_fragment/activity_motif/medical_treatment),
	"medical" = list(/datum/generated_room_fragment/activity_motif/medical_stores, /datum/generated_room_fragment/activity_motif/medical_exam),
	"engineering/foyer" = list(/datum/generated_room_fragment/activity_motif/engineering_tools, /datum/generated_room_fragment/activity_motif/engineering_fabrication),
	"engineering/power" = list(/datum/generated_room_fragment/activity_motif/engineering_power, /datum/generated_room_fragment/activity_motif/engineering_fabrication),
	"engineering/atmospherics" = list(/datum/generated_room_fragment/activity_motif/engineering_atmos, /datum/generated_room_fragment/activity_motif/engineering_maintenance),
	"engineering/workshop" = list(/datum/generated_room_fragment/activity_motif/engineering_fabrication, /datum/generated_room_fragment/activity_motif/engineering_tools),
	"engineering/equipment" = list(/datum/generated_room_fragment/activity_motif/engineering_fabrication, /datum/generated_room_fragment/activity_motif/engineering_tools),
	"engineering/maintenance" = list(/datum/generated_room_fragment/activity_motif/engineering_maintenance, /datum/generated_room_fragment/activity_motif/engineering_tools),
	"engineering/tool-room" = list(/datum/generated_room_fragment/activity_motif/engineering_maintenance, /datum/generated_room_fragment/activity_motif/engineering_tools),
	"engineering" = list(/datum/generated_room_fragment/activity_motif/engineering_stores, /datum/generated_room_fragment/activity_motif/engineering_tools),
	"logistics/reception" = list(/datum/generated_room_fragment/activity_motif/logistics_intake, /datum/generated_room_fragment/reception_corner),
	"logistics/warehouse" = list(/datum/generated_room_fragment/activity_motif/logistics_freight, /datum/generated_room_fragment/activity_motif/logistics_bulk),
	"logistics/cargo" = list(/datum/generated_room_fragment/activity_motif/logistics_freight, /datum/generated_room_fragment/activity_motif/logistics_bulk),
	"logistics/sorting" = list(/datum/generated_room_fragment/activity_motif/logistics_sorting, /datum/generated_room_fragment/activity_motif/logistics_freight),
	"logistics/processing" = list(/datum/generated_room_fragment/activity_motif/logistics_sorting, /datum/generated_room_fragment/activity_motif/logistics_freight),
	"logistics/dispatch" = list(/datum/generated_room_fragment/activity_motif/logistics_dispatch, /datum/generated_room_fragment/activity_motif/logistics_intake),
	"logistics" = list(/datum/generated_room_fragment/activity_motif/logistics_inventory, /datum/generated_room_fragment/activity_motif/logistics_bulk),
	"docking/control" = list(/datum/generated_room_fragment/activity_motif/docking_control, /datum/generated_room_fragment/reception_corner),
	"docking/reception" = list(/datum/generated_room_fragment/activity_motif/docking_control, /datum/generated_room_fragment/reception_corner),
	"docking/customs" = list(/datum/generated_room_fragment/activity_motif/docking_customs, /datum/generated_room_fragment/activity_motif/docking_security),
	"docking/security" = list(/datum/generated_room_fragment/activity_motif/docking_security, /datum/generated_room_fragment/activity_motif/docking_customs),
	"docking/lounge" = list(/datum/generated_room_fragment/activity_motif/docking_lounge, /datum/generated_room_fragment/activity_motif/docking_control),
	"docking/berth" = list(/datum/generated_room_fragment/activity_motif/docking_lounge, /datum/generated_room_fragment/activity_motif/docking_control),
	"docking/equipment" = list(/datum/generated_room_fragment/activity_motif/docking_equipment, /datum/generated_room_fragment/activity_motif/docking_supply),
	"docking" = list(/datum/generated_room_fragment/activity_motif/docking_supply, /datum/generated_room_fragment/activity_motif/docking_equipment),
))

/// Returns role-appropriate authored motifs. Each department has six distinct
/// arrangements, and every generated role receives two meaningful alternatives.
/// Shared list; never write into it.
/proc/generated_room_semantic_fragment_options(department_id, role)
	return GLOB.generated_room_semantic_fragments["[department_id]/[role]"] || GLOB.generated_room_semantic_fragments[department_id]
