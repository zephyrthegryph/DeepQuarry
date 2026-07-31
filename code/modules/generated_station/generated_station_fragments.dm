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
	feature_types = build_feature_types()
	return ..()

/datum/generated_room_fragment/activity_motif/Destroy()
	feature_types = null
	return ..()

/datum/generated_room_fragment/activity_motif/proc/build_feature_types()
	return list()

/datum/generated_room_fragment/activity_motif/composition_atom_types()
	var/list/atom_types = list()
	for(var/feature_type in feature_types)
		var/datum/generated_room_feature/feature = new feature_type
		if(feature.atom_type)
			atom_types += feature.atom_type
		qdel(feature)
	return atom_types

/datum/generated_room_fragment/activity_motif/build_occupied_offsets()
	// The semantic motif types are authored compositions, not aliases for one
	// universal T-shaped furniture stamp. Spread the catalog across five stable
	// arrangements so adjacent rooms with different purposes also have visibly
	// different silhouettes.
	switch(length(id) % 5)
		if(0)
			return list(list(1, 1), list(2, 1), list(3, 1), list(2, 2))
		if(1)
			return list(list(1, 1), list(1, 2), list(2, 2), list(3, 2))
		if(2)
			return list(list(1, 1), list(2, 1), list(3, 1), list(3, 2))
		if(3)
			return list(list(1, 1), list(1, 2), list(2, 1), list(3, 1))
	return list(list(1, 1), list(2, 1), list(2, 2), list(3, 2))

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
			qdel(feature)
			return FALSE
		var/atom/movable/created = new feature.atom_type(target)
		created.set_dir(feature.placement_kind == "wall" ? SOUTH : NORTH)
		owner.register_furnishing(created)
		qdel(feature)
	return TRUE

// Command: public service, administration, communications, planning, records, briefing.
/datum/generated_room_fragment/activity_motif/command_service
	id = "command-service"
/datum/generated_room_fragment/activity_motif/command_service/build_feature_types()
	return list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/id_console, /datum/generated_room_feature/reception_chair)
/datum/generated_room_fragment/activity_motif/command_admin
	id = "command-administration"
/datum/generated_room_fragment/activity_motif/command_admin/build_feature_types()
	return list(/datum/generated_room_feature/id_console, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/work_table, /datum/generated_room_feature/work_chair)
/datum/generated_room_fragment/activity_motif/command_comms
	id = "command-communications"
/datum/generated_room_fragment/activity_motif/command_comms/build_feature_types()
	return list(/datum/generated_room_feature/communications_console, /datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/work_table, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/command_planning
	id = "command-planning"
/datum/generated_room_fragment/activity_motif/command_planning/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/work_chair)
/datum/generated_room_fragment/activity_motif/command_records
	id = "command-records"
/datum/generated_room_fragment/activity_motif/command_records/build_feature_types()
	return list(/datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/id_console, /datum/generated_room_feature/work_chair)
/datum/generated_room_fragment/activity_motif/command_briefing
	id = "command-briefing"
/datum/generated_room_fragment/activity_motif/command_briefing/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/work_table, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/operator_chair)

// AI: monitoring, upload, robotics, server support, secure equipment, operator control.
/datum/generated_room_fragment/activity_motif/ai_monitoring
	id = "ai-monitoring"
/datum/generated_room_fragment/activity_motif/ai_monitoring/build_feature_types()
	return list(/datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/security_console, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/ai_upload
	id = "ai-upload"
/datum/generated_room_fragment/activity_motif/ai_upload/build_feature_types()
	return list(/datum/generated_room_feature/ai_upload, /datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/ai_robotics
	id = "ai-robotics"
/datum/generated_room_fragment/activity_motif/ai_robotics/build_feature_types()
	return list(/datum/generated_room_feature/robotics_console, /datum/generated_room_feature/autolathe, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/ai_server
	id = "ai-server-support"
/datum/generated_room_fragment/activity_motif/ai_server/build_feature_types()
	return list(/datum/generated_room_feature/robotics_console, /datum/generated_room_feature/power_monitor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/ai_secure
	id = "ai-secure-equipment"
/datum/generated_room_fragment/activity_motif/ai_secure/build_feature_types()
	return list(/datum/generated_room_feature/ai_upload, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/security_locker)
/datum/generated_room_fragment/activity_motif/ai_operator
	id = "ai-operator-control"
/datum/generated_room_fragment/activity_motif/ai_operator/build_feature_types()
	return list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/robotics_console, /datum/generated_room_feature/work_table, /datum/generated_room_feature/operator_chair)

// Security: desk, armory, evidence, interrogation, equipment, brig support.
/datum/generated_room_fragment/activity_motif/security_desk
	id = "security-desk"
/datum/generated_room_fragment/activity_motif/security_desk/build_feature_types()
	return list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/security_records, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/security_armory
	id = "security-armory"
/datum/generated_room_fragment/activity_motif/security_armory/build_feature_types()
	return list(/datum/generated_room_feature/armory_autolathe, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/security_locker)
/datum/generated_room_fragment/activity_motif/security_evidence
	id = "security-evidence"
/datum/generated_room_fragment/activity_motif/security_evidence/build_feature_types()
	return list(/datum/generated_room_feature/security_records, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/work_chair)
/datum/generated_room_fragment/activity_motif/security_interview
	id = "security-interview"
/datum/generated_room_fragment/activity_motif/security_interview/build_feature_types()
	return list(/datum/generated_room_feature/reinforced_table, /datum/generated_room_feature/security_records, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/security_equipment
	id = "security-equipment"
/datum/generated_room_fragment/activity_motif/security_equipment/build_feature_types()
	return list(/datum/generated_room_feature/security_locker, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/reinforced_table)
/datum/generated_room_fragment/activity_motif/security_brig
	id = "security-brig-support"
/datum/generated_room_fragment/activity_motif/security_brig/build_feature_types()
	return list(/datum/generated_room_feature/cell_timer, /datum/generated_room_feature/security_console, /datum/generated_room_feature/brig_bed, /datum/generated_room_feature/operator_chair)

// Medical: examination, treatment, surgery, pharmacy, recovery, stores.
/datum/generated_room_fragment/activity_motif/medical_exam
	id = "medical-examination"
/datum/generated_room_fragment/activity_motif/medical_exam/build_feature_types()
	return list(/datum/generated_room_feature/patient_bed, /datum/generated_room_feature/medical_vendor, /datum/generated_room_feature/sink, /datum/generated_room_feature/iv_drip)
/datum/generated_room_fragment/activity_motif/medical_treatment
	id = "medical-treatment"
/datum/generated_room_fragment/activity_motif/medical_treatment/build_feature_types()
	return list(/datum/generated_room_feature/sleeper, /datum/generated_room_feature/medical_storage, /datum/generated_room_feature/sink, /datum/generated_room_feature/iv_drip)
/datum/generated_room_fragment/activity_motif/medical_surgery
	id = "medical-surgery"
/datum/generated_room_fragment/activity_motif/medical_surgery/build_feature_types()
	return list(/datum/generated_room_feature/operating_computer, /datum/generated_room_feature/medical_storage, /datum/generated_room_feature/surgery_table, /datum/generated_room_feature/iv_drip)
/datum/generated_room_fragment/activity_motif/medical_pharmacy
	id = "medical-pharmacy"
/datum/generated_room_fragment/activity_motif/medical_pharmacy/build_feature_types()
	return list(/datum/generated_room_feature/chemical_dispenser, /datum/generated_room_feature/chem_master, /datum/generated_room_feature/reagent_grinder, /datum/generated_room_feature/sink)
/datum/generated_room_fragment/activity_motif/medical_recovery
	id = "medical-recovery"
/datum/generated_room_fragment/activity_motif/medical_recovery/build_feature_types()
	return list(/datum/generated_room_feature/sleeper, /datum/generated_room_feature/patient_bed, /datum/generated_room_feature/medical_vendor, /datum/generated_room_feature/iv_drip)
/datum/generated_room_fragment/activity_motif/medical_stores
	id = "medical-stores"
/datum/generated_room_fragment/activity_motif/medical_stores/build_feature_types()
	return list(/datum/generated_room_feature/medical_storage, /datum/generated_room_feature/medical_storage, /datum/generated_room_feature/oxygen_canister, /datum/generated_room_feature/work_table)

// Engineering: fabrication, power, atmospherics, tools, maintenance, stores.
/datum/generated_room_fragment/activity_motif/engineering_fabrication
	id = "engineering-fabrication"
/datum/generated_room_fragment/activity_motif/engineering_fabrication/build_feature_types()
	return list(/datum/generated_room_feature/autolathe, /datum/generated_room_feature/tool_vendor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/work_table)
/datum/generated_room_fragment/activity_motif/engineering_power
	id = "engineering-power"
/datum/generated_room_fragment/activity_motif/engineering_power/build_feature_types()
	return list(/datum/generated_room_feature/power_monitor, /datum/generated_room_feature/engineering_vendor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/engineering_atmos
	id = "engineering-atmospherics"
/datum/generated_room_fragment/activity_motif/engineering_atmos/build_feature_types()
	return list(/datum/generated_room_feature/atmos_control, /datum/generated_room_feature/air_sensor, /datum/generated_room_feature/air_canister, /datum/generated_room_feature/oxygen_canister)
/datum/generated_room_fragment/activity_motif/engineering_tools
	id = "engineering-tools"
/datum/generated_room_fragment/activity_motif/engineering_tools/build_feature_types()
	return list(/datum/generated_room_feature/tool_vendor, /datum/generated_room_feature/engineering_vendor, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/work_table)
/datum/generated_room_fragment/activity_motif/engineering_maintenance
	id = "engineering-maintenance"
/datum/generated_room_fragment/activity_motif/engineering_maintenance/build_feature_types()
	return list(/datum/generated_room_feature/recharger, /datum/generated_room_feature/air_sensor, /datum/generated_room_feature/atmos_locker, /datum/generated_room_feature/work_table)
/datum/generated_room_fragment/activity_motif/engineering_stores
	id = "engineering-stores"
/datum/generated_room_fragment/activity_motif/engineering_stores/build_feature_types()
	return list(/datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/atmos_locker, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/recharger)

// Logistics: intake, freight, sorting, dispatch, inventory, bulk storage.
/datum/generated_room_fragment/activity_motif/logistics_intake
	id = "logistics-intake"
/datum/generated_room_fragment/activity_motif/logistics_intake/build_feature_types()
	return list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/supply_console, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/reception_chair)
/datum/generated_room_fragment/activity_motif/logistics_freight
	id = "logistics-freight"
/datum/generated_room_fragment/activity_motif/logistics_freight/build_feature_types()
	return list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_locker, /datum/generated_room_feature/work_table)
/datum/generated_room_fragment/activity_motif/logistics_sorting
	id = "logistics-sorting"
/datum/generated_room_fragment/activity_motif/logistics_sorting/build_feature_types()
	return list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/logistics_dispatch
	id = "logistics-dispatch"
/datum/generated_room_fragment/activity_motif/logistics_dispatch/build_feature_types()
	return list(/datum/generated_room_feature/supply_console, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/logistics_inventory
	id = "logistics-inventory"
/datum/generated_room_fragment/activity_motif/logistics_inventory/build_feature_types()
	return list(/datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/cargo_locker, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/work_chair)
/datum/generated_room_fragment/activity_motif/logistics_bulk
	id = "logistics-bulk-storage"
/datum/generated_room_fragment/activity_motif/logistics_bulk/build_feature_types()
	return list(/datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/cargo_locker)

// Docking: control, customs, security, passenger lounge, equipment, supply.
/datum/generated_room_fragment/activity_motif/docking_control
	id = "docking-control"
/datum/generated_room_fragment/activity_motif/docking_control/build_feature_types()
	return list(/datum/generated_room_feature/communications_console, /datum/generated_room_feature/security_console, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/docking_customs
	id = "docking-customs"
/datum/generated_room_fragment/activity_motif/docking_customs/build_feature_types()
	return list(/datum/generated_room_feature/id_console, /datum/generated_room_feature/security_records, /datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/docking_security
	id = "docking-security"
/datum/generated_room_fragment/activity_motif/docking_security/build_feature_types()
	return list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger, /datum/generated_room_feature/operator_chair)
/datum/generated_room_fragment/activity_motif/docking_lounge
	id = "docking-lounge"
/datum/generated_room_fragment/activity_motif/docking_lounge/build_feature_types()
	return list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/shuttle_seat, /datum/generated_room_feature/shuttle_seat, /datum/generated_room_feature/reception_chair)
/datum/generated_room_fragment/activity_motif/docking_equipment
	id = "docking-equipment"
/datum/generated_room_fragment/activity_motif/docking_equipment/build_feature_types()
	return list(/datum/generated_room_feature/oxygen_canister, /datum/generated_room_feature/internals_crate, /datum/generated_room_feature/recharger, /datum/generated_room_feature/work_table)
/datum/generated_room_fragment/activity_motif/docking_supply
	id = "docking-supply"
/datum/generated_room_fragment/activity_motif/docking_supply/build_feature_types()
	return list(/datum/generated_room_feature/internals_crate, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_locker, /datum/generated_room_feature/shuttle_seat)

/// Returns role-appropriate authored motifs. Each department has six distinct
/// arrangements, and every generated role receives two meaningful alternatives.
/proc/generated_room_semantic_fragment_options(department_id, role)
	switch(department_id)
		if("command")
			switch(role)
				if("reception") return list(/datum/generated_room_fragment/activity_motif/command_service, /datum/generated_room_fragment/reception_corner)
				if("communications") return list(/datum/generated_room_fragment/activity_motif/command_comms, /datum/generated_room_fragment/activity_motif/command_planning)
				if("records", "archive") return list(/datum/generated_room_fragment/activity_motif/command_records, /datum/generated_room_fragment/activity_motif/command_admin)
				if("meeting", "briefing") return list(/datum/generated_room_fragment/activity_motif/command_briefing, /datum/generated_room_fragment/activity_motif/command_planning)
			return list(/datum/generated_room_fragment/activity_motif/command_admin, /datum/generated_room_fragment/activity_motif/command_comms)
		if("ai")
			switch(role)
				if("foyer") return list(/datum/generated_room_fragment/activity_motif/ai_operator, /datum/generated_room_fragment/activity_motif/ai_monitoring)
				if("robotics") return list(/datum/generated_room_fragment/activity_motif/ai_robotics, /datum/generated_room_fragment/activity_motif/ai_operator)
				if("server-closet", "support") return list(/datum/generated_room_fragment/activity_motif/ai_server, /datum/generated_room_fragment/activity_motif/ai_robotics)
				if("secure-storage") return list(/datum/generated_room_fragment/activity_motif/ai_secure, /datum/generated_room_fragment/activity_motif/ai_server)
				if("satellite", "monitoring") return list(/datum/generated_room_fragment/activity_motif/ai_monitoring, /datum/generated_room_fragment/activity_motif/ai_upload)
			return list(/datum/generated_room_fragment/activity_motif/ai_operator, /datum/generated_room_fragment/activity_motif/ai_monitoring)
		if("security")
			switch(role)
				if("reception") return list(/datum/generated_room_fragment/activity_motif/security_desk, /datum/generated_room_fragment/activity_motif/security_interview)
				if("armory", "locker-room") return list(/datum/generated_room_fragment/activity_motif/security_armory, /datum/generated_room_fragment/activity_motif/security_equipment)
				if("evidence") return list(/datum/generated_room_fragment/activity_motif/security_evidence, /datum/generated_room_fragment/activity_motif/security_desk)
				if("interrogation", "checkpoint") return list(/datum/generated_room_fragment/activity_motif/security_interview, /datum/generated_room_fragment/activity_motif/security_desk)
				if("brig") return list(/datum/generated_room_fragment/activity_motif/security_brig, /datum/generated_room_fragment/activity_motif/security_equipment)
			return list(/datum/generated_room_fragment/activity_motif/security_desk, /datum/generated_room_fragment/activity_motif/security_equipment)
		if("medical")
			switch(role)
				if("reception") return list(/datum/generated_room_fragment/activity_motif/medical_exam, /datum/generated_room_fragment/activity_motif/medical_stores)
				if("surgery") return list(/datum/generated_room_fragment/activity_motif/medical_surgery, /datum/generated_room_fragment/treatment_bay)
				if("treatment", "exam") return list(/datum/generated_room_fragment/activity_motif/medical_exam, /datum/generated_room_fragment/activity_motif/medical_treatment)
				if("pharmacy") return list(/datum/generated_room_fragment/activity_motif/medical_pharmacy, /datum/generated_room_fragment/activity_motif/medical_stores)
				if("recovery", "ward") return list(/datum/generated_room_fragment/activity_motif/medical_recovery, /datum/generated_room_fragment/activity_motif/medical_treatment)
			return list(/datum/generated_room_fragment/activity_motif/medical_stores, /datum/generated_room_fragment/activity_motif/medical_exam)
		if("engineering")
			switch(role)
				if("foyer") return list(/datum/generated_room_fragment/activity_motif/engineering_tools, /datum/generated_room_fragment/activity_motif/engineering_fabrication)
				if("power") return list(/datum/generated_room_fragment/activity_motif/engineering_power, /datum/generated_room_fragment/activity_motif/engineering_fabrication)
				if("atmospherics") return list(/datum/generated_room_fragment/activity_motif/engineering_atmos, /datum/generated_room_fragment/activity_motif/engineering_maintenance)
				if("workshop", "equipment") return list(/datum/generated_room_fragment/activity_motif/engineering_fabrication, /datum/generated_room_fragment/activity_motif/engineering_tools)
				if("maintenance", "tool-room") return list(/datum/generated_room_fragment/activity_motif/engineering_maintenance, /datum/generated_room_fragment/activity_motif/engineering_tools)
			return list(/datum/generated_room_fragment/activity_motif/engineering_stores, /datum/generated_room_fragment/activity_motif/engineering_tools)
		if("logistics")
			switch(role)
				if("reception") return list(/datum/generated_room_fragment/activity_motif/logistics_intake, /datum/generated_room_fragment/reception_corner)
				if("warehouse", "cargo") return list(/datum/generated_room_fragment/activity_motif/logistics_freight, /datum/generated_room_fragment/activity_motif/logistics_bulk)
				if("sorting", "processing") return list(/datum/generated_room_fragment/activity_motif/logistics_sorting, /datum/generated_room_fragment/activity_motif/logistics_freight)
				if("dispatch") return list(/datum/generated_room_fragment/activity_motif/logistics_dispatch, /datum/generated_room_fragment/activity_motif/logistics_intake)
			return list(/datum/generated_room_fragment/activity_motif/logistics_inventory, /datum/generated_room_fragment/activity_motif/logistics_bulk)
		if("docking")
			switch(role)
				if("control", "reception") return list(/datum/generated_room_fragment/activity_motif/docking_control, /datum/generated_room_fragment/reception_corner)
				if("customs") return list(/datum/generated_room_fragment/activity_motif/docking_customs, /datum/generated_room_fragment/activity_motif/docking_security)
				if("security") return list(/datum/generated_room_fragment/activity_motif/docking_security, /datum/generated_room_fragment/activity_motif/docking_customs)
				if("lounge", "berth") return list(/datum/generated_room_fragment/activity_motif/docking_lounge, /datum/generated_room_fragment/activity_motif/docking_control)
				if("equipment") return list(/datum/generated_room_fragment/activity_motif/docking_equipment, /datum/generated_room_fragment/activity_motif/docking_supply)
			return list(/datum/generated_room_fragment/activity_motif/docking_supply, /datum/generated_room_fragment/activity_motif/docking_equipment)
	return list()
