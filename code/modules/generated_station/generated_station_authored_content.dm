/// Role-specific functional vocabulary. These fixtures make a room's purpose
/// legible even without its area label or department floor color.
/datum/generated_room_feature/filing_cabinet
	id = "filing-cabinet"
	atom_type = /obj/structure/filingcabinet
	placement_kind = "wall"

/datum/generated_room_feature/filing_cabinet/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/compact_work_table
	id = "compact-work-table"
	atom_type = /obj/structure/table/standard

/datum/generated_room_feature/compact_filing_cabinet
	id = "compact-filing-cabinet"
	atom_type = /obj/structure/filingcabinet
	placement_kind = "wall"

/datum/generated_room_feature/compact_filing_cabinet/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/compact_security_locker
	id = "compact-security-locker"
	atom_type = /obj/structure/closet/secure_closet/security
	placement_kind = "wall"

/datum/generated_room_feature/compact_security_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/compact_medical_locker
	id = "compact-medical-locker"
	atom_type = /obj/structure/closet/secure_closet/medical1
	placement_kind = "wall"

/datum/generated_room_feature/compact_medical_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/compact_engineering_locker
	id = "compact-engineering-locker"
	atom_type = /obj/structure/closet/secure_closet/engineering_electrical
	placement_kind = "wall"

/datum/generated_room_feature/compact_engineering_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/compact_cargo_locker
	id = "compact-cargo-locker"
	atom_type = /obj/structure/closet/secure_closet/cargotech
	placement_kind = "wall"

/datum/generated_room_feature/compact_cargo_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/compact_cargo_crate
	id = "compact-cargo-crate"
	atom_type = /obj/structure/closet/crate

/// Constraint-light functional fixtures for compact authored rooms. Their
/// surrounding room is already circulation-validated, so these do not require
/// the multi-tile frontage used by full workstation programs.
/datum/generated_room_feature/compact_command_machine
	id = "compact-command-machine"
	atom_type = /obj/machinery/computer/crew

/datum/generated_room_feature/compact_ai_machine
	id = "compact-ai-machine"
	atom_type = /obj/machinery/computer/aiupload

/datum/generated_room_feature/compact_security_machine
	id = "compact-security-machine"
	atom_type = /obj/machinery/recharger

/datum/generated_room_feature/compact_medical_machine
	id = "compact-medical-machine"
	atom_type = /obj/machinery/sleeper

/datum/generated_room_feature/compact_engineering_machine
	id = "compact-engineering-machine"
	atom_type = /obj/machinery/autolathe

/datum/generated_room_feature/compact_logistics_machine
	id = "compact-logistics-machine"
	atom_type = /obj/machinery/computer/supplycomp

/datum/generated_room_feature/compact_docking_machine
	id = "compact-docking-machine"
	atom_type = /obj/machinery/computer/communications

/datum/generated_room_feature/crew_monitor
	id = "crew-monitor"
	atom_type = /obj/machinery/computer/crew
	placement_kind = "wall"

/datum/generated_room_feature/crew_monitor/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/id_console
	id = "id-console"
	atom_type = /obj/machinery/computer/card
	placement_kind = "wall"

/datum/generated_room_feature/id_console/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/ai_upload
	id = "ai-upload"
	atom_type = /obj/machinery/computer/aiupload
	placement_kind = "wall"

/datum/generated_room_feature/ai_upload/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/robotics_console
	id = "robotics-console"
	atom_type = /obj/machinery/computer/robotics
	placement_kind = "wall"

/datum/generated_room_feature/robotics_console/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/autolathe
	id = "autolathe"
	atom_type = /obj/machinery/autolathe
	placement_kind = "wall"

/datum/generated_room_feature/autolathe/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/armory_autolathe
	id = "armory-autolathe"
	atom_type = /obj/machinery/autolathe/armory
	placement_kind = "wall"

/datum/generated_room_feature/armory_autolathe/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/security_records
	id = "security-records"
	atom_type = /obj/machinery/computer/secure_data
	placement_kind = "wall"

/datum/generated_room_feature/security_records/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/cell_timer
	id = "cell-timer"
	atom_type = /obj/machinery/door_timer
	placement_kind = "wall"

/datum/generated_room_feature/cell_timer/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/chem_master
	id = "chem-master"
	atom_type = /obj/machinery/chem_master
	placement_kind = "wall"

/datum/generated_room_feature/chem_master/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/reagent_grinder
	id = "reagent-grinder"
	atom_type = /obj/machinery/reagentgrinder
	placement_kind = "wall"

/datum/generated_room_feature/reagent_grinder/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/air_sensor
	id = "air-sensor"
	atom_type = /obj/machinery/air_sensor
	placement_kind = "wall"

/datum/generated_room_feature/air_sensor/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/air_canister
	id = "air-canister"
	atom_type = /obj/machinery/portable_atmospherics/canister/air
	placement_kind = "wall"

/datum/generated_room_feature/air_canister/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/oxygen_canister
	id = "oxygen-canister"
	atom_type = /obj/machinery/portable_atmospherics/canister/oxygen
	placement_kind = "wall"

/datum/generated_room_feature/oxygen_canister/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/disposal_unit
	id = "disposal-unit"
	atom_type = /obj/machinery/disposal
	placement_kind = "wall"

/datum/generated_room_feature/disposal_unit/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/reinforced_table
	id = "reinforced-table"
	atom_type = /obj/structure/table/reinforced

/datum/generated_room_feature/reinforced_table/build_constraints()
	return list(new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/sink
	id = "sink"
	atom_type = /obj/structure/sink
	placement_kind = "wall"

/datum/generated_room_feature/sink/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/chemical_dispenser
	id = "chemical-dispenser"
	atom_type = /obj/machinery/chemical_dispenser/full
	placement_kind = "wall"

/datum/generated_room_feature/chemical_dispenser/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/medical_vendor
	id = "medical-vendor"
	atom_type = /obj/machinery/vending/medical
	placement_kind = "wall"

/datum/generated_room_feature/medical_vendor/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/tool_vendor
	id = "tool-vendor"
	atom_type = /obj/machinery/vending/tool
	placement_kind = "wall"

/datum/generated_room_feature/tool_vendor/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/engineering_vendor
	id = "engineering-vendor"
	atom_type = /obj/machinery/vending/engineering
	placement_kind = "wall"

/datum/generated_room_feature/engineering_vendor/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/power_monitor
	id = "power-monitor"
	atom_type = /obj/machinery/computer/power_monitor
	placement_kind = "wall"

/datum/generated_room_feature/power_monitor/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/atmos_control
	id = "atmos-control"
	atom_type = /obj/machinery/computer/atmoscontrol
	placement_kind = "wall"

/datum/generated_room_feature/atmos_control/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature_group/records_office
	id = "records-office"
	max_instances = 2
	tiles_per_instance = 28

/datum/generated_room_feature_group/records_office/build_feature_types()
	return list(/datum/generated_room_feature/filing_cabinet, /datum/generated_room_feature/work_table, /datum/generated_room_feature/work_chair)

/datum/generated_room_feature_group/command_monitoring
	id = "command-monitoring"
	max_instances = 2
	tiles_per_instance = 28

/datum/generated_room_feature_group/command_monitoring/build_feature_types()
	return list(/datum/generated_room_feature/crew_monitor, /datum/generated_room_feature/communications_console, /datum/generated_room_feature/operator_chair)

/datum/generated_room_feature_group/robotics_workcell
	id = "robotics-workcell"
	max_instances = 2
	tiles_per_instance = 30

/datum/generated_room_feature_group/robotics_workcell/build_feature_types()
	return list(/datum/generated_room_feature/robotics_console, /datum/generated_room_feature/autolathe, /datum/generated_room_feature/recharger)

/datum/generated_room_feature_group/interrogation_suite
	id = "interrogation-suite"
	max_instances = 2
	tiles_per_instance = 24

/datum/generated_room_feature_group/interrogation_suite/build_feature_types()
	return list(/datum/generated_room_feature/reinforced_table, /datum/generated_room_feature/operator_chair, /datum/generated_room_feature/security_records)

/datum/generated_room_feature_group/pharmacy_line
	id = "pharmacy-line"
	max_instances = 1
	tiles_per_instance = 24

/datum/generated_room_feature_group/pharmacy_line/build_feature_types()
	return list(/datum/generated_room_feature/chemical_dispenser, /datum/generated_room_feature/chem_master, /datum/generated_room_feature/reagent_grinder, /datum/generated_room_feature/sink, /datum/generated_room_feature/medical_storage)

/datum/generated_room_feature_group/clinical_bay
	id = "clinical-bay"
	max_instances = 1
	tiles_per_instance = 24

/datum/generated_room_feature_group/clinical_bay/build_feature_types()
	return list(/datum/generated_room_feature/patient_bed, /datum/generated_room_feature/iv_drip, /datum/generated_room_feature/sink, /datum/generated_room_feature/medical_vendor)

/datum/generated_room_feature_group/atmos_service_bay
	id = "atmos-service-bay"
	max_instances = 2
	tiles_per_instance = 30

/datum/generated_room_feature_group/atmos_service_bay/build_feature_types()
	return list(/datum/generated_room_feature/atmos_control, /datum/generated_room_feature/air_sensor, /datum/generated_room_feature/air_canister, /datum/generated_room_feature/oxygen_canister)

/datum/generated_room_feature_group/fabrication_bay
	id = "fabrication-bay"
	max_instances = 2
	tiles_per_instance = 28

/datum/generated_room_feature_group/fabrication_bay/build_feature_types()
	return list(/datum/generated_room_feature/autolathe, /datum/generated_room_feature/work_table, /datum/generated_room_feature/power_monitor, /datum/generated_room_feature/tool_vendor, /datum/generated_room_feature/electrical_locker)

/datum/generated_room_feature_group/freight_line
	id = "freight-line"
	max_instances = 3
	tiles_per_instance = 22

/datum/generated_room_feature_group/freight_line/build_feature_types()
	return list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_crate, /datum/generated_room_feature/cargo_locker)

/// Adds the authored activity program for roles which do not use a dedicated
/// room-definition subtype. Every program has a role-defining machine or
/// arrangement plus supporting furniture.
/proc/generated_room_apply_authored_role_program(datum/generated_room_definition/definition, department_id, role)
	if(!definition)
		return
	switch("[department_id]/[role]")
		if("command/reception", "security/reception", "medical/reception", "logistics/reception", "docking/reception", "ai/foyer", "engineering/foyer")
			definition.required_features |= list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/reception_chair, /datum/generated_room_feature/filing_cabinet)
			definition.required_groups |= list(/datum/generated_room_feature_group/waiting_area)
		if("command/meeting", "command/briefing")
			definition.required_groups |= list(/datum/generated_room_feature_group/command_desk, /datum/generated_room_feature_group/command_monitoring)
		if("command/records")
			definition.required_groups |= list(/datum/generated_room_feature_group/records_office)
			definition.required_features |= list(/datum/generated_room_feature/id_console)
		if("command/liaison", "command/archive")
			definition.required_groups |= list(/datum/generated_room_feature_group/records_office, /datum/generated_room_feature_group/communications_bank)
		if("ai/foyer")
			definition.required_features |= list(/datum/generated_room_feature/crew_monitor)
		if("ai/satellite", "ai/monitoring")
			definition.required_groups |= list(/datum/generated_room_feature_group/command_monitoring)
			definition.required_features |= list(/datum/generated_room_feature/ai_upload)
		if("ai/robotics", "ai/server-closet")
			definition.required_groups |= list(/datum/generated_room_feature_group/robotics_workcell)
			definition.required_features |= list(/datum/generated_room_feature/robotics_console, /datum/generated_room_feature/autolathe)
		if("ai/secure-storage")
			definition.required_features |= list(/datum/generated_room_feature/ai_upload, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/recharger)
		if("security/armory")
			definition.required_features |= list(/datum/generated_room_feature/armory_autolathe, /datum/generated_room_feature/security_locker, /datum/generated_room_feature/recharger)
		if("security/evidence")
			definition.required_groups |= list(/datum/generated_room_feature_group/records_office)
			definition.required_features |= list(/datum/generated_room_feature/security_records, /datum/generated_room_feature/security_locker)
		if("security/locker-room")
			definition.required_groups |= list(/datum/generated_room_feature_group/security_storage_bank)
			definition.required_features |= list(/datum/generated_room_feature/recharger, /datum/generated_room_feature/work_table)
		if("security/interrogation", "security/checkpoint")
			definition.required_groups |= list(/datum/generated_room_feature_group/interrogation_suite)
			definition.required_features |= list(/datum/generated_room_feature/reinforced_table, /datum/generated_room_feature/security_records)
		if("medical/pharmacy")
			definition.required_groups |= list(/datum/generated_room_feature_group/pharmacy_line)
			definition.required_features |= list(/datum/generated_room_feature/chem_master, /datum/generated_room_feature/reagent_grinder)
		if("medical/recovery")
			definition.required_groups |= list(/datum/generated_room_feature_group/clinical_bay)
			definition.required_features |= list(/datum/generated_room_feature/sleeper, /datum/generated_room_feature/iv_drip)
		if("medical/storage")
			definition.required_groups |= list(/datum/generated_room_feature_group/medical_storage_bank)
			definition.required_features |= list(/datum/generated_room_feature/oxygen_canister, /datum/generated_room_feature/medical_vendor)
		if("medical/exam")
			definition.required_groups |= list(/datum/generated_room_feature_group/clinical_bay)
			definition.required_features |= list(/datum/generated_room_feature/sink, /datum/generated_room_feature/medical_vendor)
		if("engineering/workshop", "engineering/equipment", "engineering/tool-room")
			definition.required_groups |= list(/datum/generated_room_feature_group/fabrication_bay)
			definition.required_features |= list(/datum/generated_room_feature/autolathe, /datum/generated_room_feature/electrical_locker)
		if("engineering/maintenance")
			definition.required_groups |= list(/datum/generated_room_feature_group/fabrication_bay, /datum/generated_room_feature_group/atmos_service_bay)
			definition.required_features |= list(/datum/generated_room_feature/autolathe, /datum/generated_room_feature/air_sensor)
		if("engineering/storage")
			definition.required_features |= list(/datum/generated_room_feature/air_canister, /datum/generated_room_feature/electrical_locker, /datum/generated_room_feature/internals_crate)
		if("logistics/warehouse", "logistics/sorting", "logistics/inventory")
			definition.required_groups |= list(/datum/generated_room_feature_group/freight_line, /datum/generated_room_feature_group/cargo_workstation)
			definition.required_features |= list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_crate)
		if("logistics/storage")
			definition.required_groups |= list(/datum/generated_room_feature_group/cargo_stack)
			definition.required_features |= list(/datum/generated_room_feature/disposal_unit, /datum/generated_room_feature/cargo_locker)
		if("logistics/dispatch")
			definition.required_features |= list(/datum/generated_room_feature/supply_console, /datum/generated_room_feature/communications_console)
			definition.required_groups |= list(/datum/generated_room_feature_group/freight_line)
		if("docking/security")
			definition.required_features |= list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/security_records, /datum/generated_room_feature/recharger)
		if("docking/customs")
			definition.required_features |= list(/datum/generated_room_feature/id_console, /datum/generated_room_feature/security_records)
			definition.required_groups |= list(/datum/generated_room_feature_group/records_office)
		if("docking/lounge")
			definition.required_groups |= list(/datum/generated_room_feature_group/berth_seating, /datum/generated_room_feature_group/waiting_area)
			definition.required_features |= list(/datum/generated_room_feature/reception_desk)
		if("docking/equipment", "docking/supply")
			definition.required_groups |= list(/datum/generated_room_feature_group/freight_line)
			definition.required_features |= list(/datum/generated_room_feature/oxygen_canister, /datum/generated_room_feature/internals_crate)

/// A stable set of atom types whose presence makes a role recognizable in a
/// materialized room. Tests and runtime diagnostics consume the same contract.
/proc/generated_room_required_signature(department_id, role, compact = FALSE)
	if(compact)
		switch(department_id)
			if("command") return list(/obj/machinery/computer/crew, /obj/structure/filingcabinet)
			if("ai") return list(/obj/machinery/computer/aiupload, /obj/structure/filingcabinet)
			if("security") return list(/obj/machinery/recharger, /obj/structure/closet/secure_closet/security)
			if("medical") return list(/obj/machinery/sleeper, /obj/structure/closet/secure_closet/medical1)
			if("engineering") return list(/obj/machinery/autolathe, /obj/structure/closet/secure_closet/engineering_electrical)
			if("logistics") return list(/obj/machinery/computer/supplycomp, /obj/structure/closet/crate)
			if("docking") return list(/obj/machinery/computer/communications, /obj/structure/closet/secure_closet/security)
	switch("[department_id]/[role]")
		if("command/records") return list(/obj/structure/filingcabinet, /obj/machinery/computer/card)
		if("ai/robotics", "ai/server-closet") return list(/obj/machinery/computer/robotics, /obj/machinery/autolathe)
		if("ai/satellite", "ai/monitoring") return list(/obj/machinery/computer/aiupload, /obj/machinery/computer/crew)
		if("security/armory") return list(/obj/machinery/autolathe/armory, /obj/structure/closet/secure_closet/security)
		if("security/evidence") return list(/obj/machinery/computer/secure_data, /obj/structure/filingcabinet)
		if("security/interrogation", "security/checkpoint") return list(/obj/structure/table/reinforced, /obj/machinery/computer/secure_data)
		if("medical/pharmacy") return list(/obj/machinery/chem_master, /obj/machinery/reagentgrinder)
		if("medical/exam") return list(/obj/structure/sink, /obj/machinery/vending/medical)
		if("medical/recovery") return list(/obj/machinery/sleeper, /obj/machinery/iv_drip)
		if("engineering/workshop", "engineering/equipment", "engineering/tool-room") return list(/obj/machinery/autolathe, /obj/structure/closet/secure_closet/engineering_electrical)
		if("engineering/maintenance") return list(/obj/machinery/autolathe, /obj/machinery/air_sensor)
		if("logistics/warehouse", "logistics/sorting", "logistics/inventory") return list(/obj/machinery/disposal, /obj/structure/closet/crate)
		if("logistics/dispatch") return list(/obj/machinery/computer/supplycomp, /obj/machinery/computer/communications)
		if("docking/customs") return list(/obj/machinery/computer/card, /obj/machinery/computer/secure_data)
		if("docking/security") return list(/obj/machinery/computer/security, /obj/machinery/computer/secure_data)
	return list()

/// Minimal two-fixture compositions for pockets too small to host a complete
/// activity cluster. These are authored reductions, not generic substitutes.
/proc/generated_room_compact_authored_features(department_id, role)
	switch(department_id)
		if("command") return list(/datum/generated_room_feature/compact_command_machine, /datum/generated_room_feature/compact_filing_cabinet)
		if("ai") return list(/datum/generated_room_feature/compact_ai_machine, /datum/generated_room_feature/compact_filing_cabinet)
		if("security") return list(/datum/generated_room_feature/compact_security_machine, /datum/generated_room_feature/compact_security_locker)
		if("medical") return list(/datum/generated_room_feature/compact_medical_machine, /datum/generated_room_feature/compact_medical_locker)
		if("engineering") return list(/datum/generated_room_feature/compact_engineering_machine, /datum/generated_room_feature/compact_engineering_locker)
		if("logistics") return list(/datum/generated_room_feature/compact_logistics_machine, /datum/generated_room_feature/compact_cargo_crate)
		if("docking") return list(/datum/generated_room_feature/compact_docking_machine, /datum/generated_room_feature/compact_security_locker)
	return list()
