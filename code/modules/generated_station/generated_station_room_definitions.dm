/// Placement vocabulary shared by room features, groups, and authored fragments.
/datum/generated_room_constraint
	var/hard = TRUE
	var/weight = 1
	var/subject_id
	var/target_id
	var/radius = 0
	var/utility_id

/datum/generated_room_constraint/New(new_subject_id = null, new_target_id = null, new_hard = TRUE, new_weight = 1)
	..()
	subject_id = new_subject_id
	target_id = new_target_id
	hard = new_hard
	weight = max(0, new_weight)

/datum/generated_room_constraint/against_wall
/datum/generated_room_constraint/in_corner
/datum/generated_room_constraint/faces_room
/datum/generated_room_constraint/faces_feature
/datum/generated_room_constraint/visible_from_entrance
/datum/generated_room_constraint/near_feature
/datum/generated_room_constraint/clear_radius
/datum/generated_room_constraint/clear_frontage
/datum/generated_room_constraint/requires_utility
/datum/generated_room_constraint/requires_access_path
/datum/generated_room_constraint/separated_from
/datum/generated_room_constraint/behind_access_boundary

/// One independently placeable object and the contracts needed to use it.
/datum/generated_room_feature
	var/id = "feature"
	var/atom_type
	var/placement_kind = "floor"
	var/interaction_clearance = 0
	var/weight = 1
	var/list/constraints
	var/list/utility_requirements
	var/list/variant_options

/datum/generated_room_feature/New()
	..()
	constraints = build_constraints()
	utility_requirements = build_utility_requirements()
	variant_options = build_variant_options()

/datum/generated_room_feature/Destroy()
	QDEL_LIST(constraints)
	utility_requirements = null
	variant_options = null
	return ..()

/datum/generated_room_feature/proc/build_constraints()
	return list()

/datum/generated_room_feature/proc/build_utility_requirements()
	return list()

/datum/generated_room_feature/proc/build_variant_options()
	return list()

/datum/generated_room_feature/surgery_table
	id = "surgery-table"
	atom_type = /obj/machinery/optable
	interaction_clearance = 1

/datum/generated_room_feature/surgery_table/build_constraints()
	return list(
		new /datum/generated_room_constraint/visible_from_entrance(id, null, FALSE, 3),
		new /datum/generated_room_constraint/clear_radius(id, null, TRUE, 1),
		new /datum/generated_room_constraint/requires_access_path(id),
	)

/datum/generated_room_feature/surgery_table/build_utility_requirements()
	return list("power")

/datum/generated_room_feature/operating_computer
	id = "operating-computer"
	atom_type = /obj/machinery/computer/operating
	placement_kind = "wall"

/datum/generated_room_feature/operating_computer/build_constraints()
	var/datum/generated_room_constraint/near_feature/near_table = new(id, "surgery-table", TRUE, 3)
	near_table.radius = 3
	return list(new /datum/generated_room_constraint/against_wall(id), near_table)

/datum/generated_room_feature/operating_computer/build_utility_requirements()
	return list("power", "data")

/datum/generated_room_feature/medical_storage
	id = "medical-storage"
	atom_type = /obj/structure/closet/secure_closet/medical1
	placement_kind = "wall"

/datum/generated_room_feature/medical_storage/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id))

/datum/generated_room_feature/reception_desk
	id = "reception-desk"
	atom_type = /obj/structure/table

/datum/generated_room_feature/reception_desk/build_constraints()
	return list(new /datum/generated_room_constraint/visible_from_entrance(id, null, TRUE, 4))

/datum/generated_room_feature/reception_chair
	id = "reception-chair"
	atom_type = /obj/structure/bed/chair

/datum/generated_room_feature/reception_chair/build_constraints()
	return list(
		new /datum/generated_room_constraint/faces_feature(id, "reception-desk"),
		new /datum/generated_room_constraint/requires_access_path(id),
	)

/datum/generated_room_feature/waiting_chair
	id = "waiting-chair"
	atom_type = /obj/structure/bed/chair

/datum/generated_room_feature/waiting_chair/build_constraints()
	return list(
		new /datum/generated_room_constraint/faces_room(id),
		new /datum/generated_room_constraint/clear_frontage(id),
	)

/datum/generated_room_feature/work_table
	id = "work-table"
	atom_type = /obj/structure/table/standard

/datum/generated_room_feature/work_table/build_constraints()
	return list(new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/work_chair
	id = "work-chair"
	atom_type = /obj/structure/bed/chair/office

/datum/generated_room_feature/work_chair/build_constraints()
	return list(new /datum/generated_room_constraint/faces_feature(id, "work-table"), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/operator_chair
	id = "operator-chair"
	atom_type = /obj/structure/bed/chair/office
	interaction_clearance = 1

/datum/generated_room_feature/operator_chair/build_constraints()
	return list(new /datum/generated_room_constraint/faces_room(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/communications_console
	id = "communications-console"
	atom_type = /obj/machinery/computer/communications
	placement_kind = "wall"

/datum/generated_room_feature/communications_console/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/security_console
	id = "security-console"
	atom_type = /obj/machinery/computer/security
	placement_kind = "wall"

/datum/generated_room_feature/security_console/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/recharger
	id = "equipment-recharger"
	atom_type = /obj/machinery/recharger
	placement_kind = "wall"

/datum/generated_room_feature/recharger/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/security_locker
	id = "security-locker"
	atom_type = /obj/structure/closet/secure_closet/security
	placement_kind = "wall"

/datum/generated_room_feature/security_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/behind_access_boundary(id, "public-area"))

/datum/generated_room_feature/electrical_locker
	id = "electrical-locker"
	atom_type = /obj/structure/closet/secure_closet/engineering_electrical
	placement_kind = "wall"

/datum/generated_room_feature/electrical_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/atmos_locker
	id = "atmospherics-locker"
	atom_type = /obj/structure/closet/secure_closet/engineering_welding
	placement_kind = "wall"

/datum/generated_room_feature/atmos_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/patient_bed
	id = "patient-bed"
	atom_type = /obj/structure/bed
	placement_kind = "wall"

/datum/generated_room_feature/patient_bed/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/sleeper
	id = "medical-sleeper"
	atom_type = /obj/machinery/sleeper
	placement_kind = "wall"

/datum/generated_room_feature/sleeper/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/iv_drip
	id = "iv-drip"
	atom_type = /obj/machinery/iv_drip
	interaction_clearance = 1

/datum/generated_room_feature/iv_drip/build_constraints()
	return list(new /datum/generated_room_constraint/clear_frontage(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/brig_bed
	id = "brig-bed"
	atom_type = /obj/structure/bed
	placement_kind = "wall"

/datum/generated_room_feature/brig_bed/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/behind_access_boundary(id, "security-desk"))

/datum/generated_room_feature/supply_console
	id = "supply-console"
	atom_type = /obj/machinery/computer/supplycomp
	placement_kind = "wall"

/datum/generated_room_feature/supply_console/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/cargo_locker
	id = "cargo-locker"
	atom_type = /obj/structure/closet/secure_closet/cargotech
	placement_kind = "wall"

/datum/generated_room_feature/cargo_locker/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/cargo_crate
	id = "cargo-crate"
	atom_type = /obj/structure/closet/crate
	placement_kind = "wall"

/datum/generated_room_feature/cargo_crate/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/requires_access_path(id))

/datum/generated_room_feature/internals_crate
	id = "internals-crate"
	atom_type = /obj/structure/closet/crate/internals
	placement_kind = "wall"

/datum/generated_room_feature/internals_crate/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/clear_frontage(id))

/datum/generated_room_feature/shuttle_seat
	id = "shuttle-seat"
	atom_type = /obj/structure/bed/chair/shuttle
	placement_kind = "wall"

/datum/generated_room_feature/shuttle_seat/build_constraints()
	return list(new /datum/generated_room_constraint/against_wall(id), new /datum/generated_room_constraint/faces_room(id), new /datum/generated_room_constraint/clear_frontage(id))

/// A functional arrangement whose member features are solved together.
/datum/generated_room_feature_group
	var/id = "group"
	var/list/feature_types
	var/list/constraints
	var/min_instances = 1
	var/max_instances = 1
	/// Approximate usable floor area supported by one complete activity cluster.
	var/tiles_per_instance = 0

/datum/generated_room_feature_group/New()
	..()
	feature_types = build_feature_types()
	constraints = build_constraints()

/datum/generated_room_feature_group/Destroy()
	feature_types = null
	QDEL_LIST(constraints)
	return ..()

/datum/generated_room_feature_group/proc/build_feature_types()
	return list()

/datum/generated_room_feature_group/proc/build_constraints()
	return list()

/datum/generated_room_feature_group/operating_theatre
	id = "operating-theatre"

/datum/generated_room_feature_group/operating_theatre/build_feature_types()
	return list(/datum/generated_room_feature/surgery_table, /datum/generated_room_feature/operating_computer)

/datum/generated_room_feature_group/waiting_area
	id = "waiting-area"
	min_instances = 1
	max_instances = 3

/datum/generated_room_feature_group/waiting_area/build_feature_types()
	return list(/datum/generated_room_feature/waiting_chair)

/datum/generated_room_feature_group/waiting_area/build_constraints()
	return list(new /datum/generated_room_constraint/separated_from(id, "staff-area", FALSE, 2))

/datum/generated_room_feature_group/command_desk
	id = "command-desk"
	max_instances = 3
	tiles_per_instance = 24

/datum/generated_room_feature_group/command_desk/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/work_chair)

/datum/generated_room_feature_group/security_post
	id = "security-post"
	max_instances = 2
	tiles_per_instance = 30

/datum/generated_room_feature_group/security_post/build_feature_types()
	return list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/recharger, /datum/generated_room_feature/security_locker)

/datum/generated_room_feature_group/patient_bay
	id = "patient-bay"
	min_instances = 1
	max_instances = 4
	tiles_per_instance = 18

/datum/generated_room_feature_group/patient_bay/build_feature_types()
	return list(/datum/generated_room_feature/patient_bed, /datum/generated_room_feature/sleeper, /datum/generated_room_feature/iv_drip)

/datum/generated_room_feature_group/cargo_stack
	id = "cargo-stack"
	min_instances = 2
	max_instances = 6
	tiles_per_instance = 12

/datum/generated_room_feature_group/cargo_stack/build_feature_types()
	return list(/datum/generated_room_feature/cargo_crate)

/datum/generated_room_feature_group/berth_seating
	id = "berth-seating"
	min_instances = 2
	max_instances = 6
	tiles_per_instance = 12

/datum/generated_room_feature_group/berth_seating/build_feature_types()
	return list(/datum/generated_room_feature/shuttle_seat)

/datum/generated_room_feature_group/workstation_bank
	id = "workstation-bank"
	min_instances = 1
	max_instances = 4
	tiles_per_instance = 20

/datum/generated_room_feature_group/workstation_bank/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/work_chair)

/datum/generated_room_feature_group/communications_bank
	id = "communications-bank"
	min_instances = 1
	max_instances = 3
	tiles_per_instance = 24

/datum/generated_room_feature_group/communications_bank/build_feature_types()
	return list(/datum/generated_room_feature/communications_console, /datum/generated_room_feature/operator_chair)

/datum/generated_room_feature_group/security_console_bank
	id = "security-console-bank"
	min_instances = 1
	max_instances = 3
	tiles_per_instance = 24

/datum/generated_room_feature_group/security_console_bank/build_feature_types()
	return list(/datum/generated_room_feature/security_console, /datum/generated_room_feature/operator_chair)

/datum/generated_room_feature_group/engineering_bench
	id = "engineering-bench"
	min_instances = 1
	max_instances = 3
	tiles_per_instance = 24

/datum/generated_room_feature_group/engineering_bench/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/recharger, /datum/generated_room_feature/electrical_locker)

/datum/generated_room_feature_group/atmospherics_bench
	id = "atmospherics-bench"
	min_instances = 1
	max_instances = 3
	tiles_per_instance = 24

/datum/generated_room_feature_group/atmospherics_bench/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/recharger, /datum/generated_room_feature/atmos_locker)

/datum/generated_room_feature_group/medical_storage_bank
	id = "medical-storage-bank"
	min_instances = 1
	max_instances = 4
	tiles_per_instance = 18

/datum/generated_room_feature_group/medical_storage_bank/build_feature_types()
	return list(/datum/generated_room_feature/medical_storage)

/datum/generated_room_feature_group/electrical_storage_bank
	id = "electrical-storage-bank"
	min_instances = 1
	max_instances = 4
	tiles_per_instance = 18

/datum/generated_room_feature_group/electrical_storage_bank/build_feature_types()
	return list(/datum/generated_room_feature/electrical_locker)

/datum/generated_room_feature_group/security_storage_bank
	id = "security-storage-bank"
	min_instances = 1
	max_instances = 4
	tiles_per_instance = 18

/datum/generated_room_feature_group/security_storage_bank/build_feature_types()
	return list(/datum/generated_room_feature/security_locker)

/datum/generated_room_feature_group/brig_bunks
	id = "brig-bunks"
	min_instances = 1
	max_instances = 4
	tiles_per_instance = 16

/datum/generated_room_feature_group/brig_bunks/build_feature_types()
	return list(/datum/generated_room_feature/brig_bed)

/datum/generated_room_feature_group/cargo_workstation
	id = "cargo-workstation"
	min_instances = 1
	max_instances = 3
	tiles_per_instance = 24

/datum/generated_room_feature_group/cargo_workstation/build_feature_types()
	return list(/datum/generated_room_feature/work_table, /datum/generated_room_feature/operator_chair, /datum/generated_room_feature/cargo_crate)

/// Connection exposed by a fragment to its containing room.
/datum/generated_room_fragment_socket
	var/id
	var/kind = "access"
	var/edge = NORTH
	var/offset = 1
	var/required = TRUE

/datum/generated_room_fragment_socket/New(new_id, new_kind = "access", new_edge = NORTH, new_offset = 1, new_required = TRUE)
	..()
	id = new_id
	kind = new_kind
	edge = new_edge
	offset = new_offset
	required = new_required

/// Metadata for a small authored arrangement embedded inside a generated shell.
/datum/generated_room_fragment
	var/id = "fragment"
	var/template_path
	var/width = 1
	var/height = 1
	var/allow_rotation = TRUE
	var/allow_mirroring = FALSE
	var/anchor_kind = "wall"
	var/anchor_edge = 0
	var/list/sockets
	var/list/constraints
	var/list/occupied_offsets

/datum/generated_room_fragment/New()
	..()
	sockets = build_sockets()
	constraints = build_constraints()
	occupied_offsets = build_occupied_offsets()

/datum/generated_room_fragment/Destroy()
	QDEL_LIST(sockets)
	QDEL_LIST(constraints)
	occupied_offsets = null
	return ..()

/datum/generated_room_fragment/proc/build_sockets()
	return list()

/datum/generated_room_fragment/proc/build_constraints()
	return list()

/datum/generated_room_fragment/proc/build_occupied_offsets()
	var/list/offsets = list()
	for(var/x in 1 to width)
		for(var/y in 1 to height)
			offsets += list(list(x, y))
	return offsets

/// Fragments reserve and score their footprint even when their authored map is unavailable.
/datum/generated_room_fragment/proc/materialize(turf/origin, rotation, mirrored, datum/generated_station_materialization/owner)
	if(!origin || !owner || !template_path || rotation || mirrored)
		return FALSE
	var/list/existing = list()
	for(var/turf/T in block(origin, locate(origin.x + width - 1, origin.y + height - 1, origin.z)))
		for(var/atom/movable/movable in T)
			existing[movable] = TRUE
	var/datum/map_template/template = new(template_path, "generated room fragment [id]", TRUE)
	if(template.width != width || template.height != height)
		qdel(template)
		return FALSE
	template.load(origin)
	var/created = FALSE
	for(var/turf/T in block(origin, locate(origin.x + width - 1, origin.y + height - 1, origin.z)))
		for(var/atom/movable/movable in T)
			if(existing[movable])
				continue
			owner.register_furnishing(movable)
			if(istype(movable, /obj/machinery/door))
				owner.doors |= movable
			created = TRUE
	qdel(template)
	return created

/datum/generated_room_fragment/reception_corner
	id = "reception-corner"
	width = 5
	height = 4
	allow_rotation = FALSE
	allow_mirroring = FALSE
	anchor_kind = "corner"
	// The desk backs onto the north wall while its public sockets face south
	// into the room's clear circulation zone.
	anchor_edge = NORTH

/datum/generated_room_fragment/reception_corner/build_sockets()
	return list(
		new /datum/generated_room_fragment_socket("public-frontage", "circulation", SOUTH, 2),
		new /datum/generated_room_fragment_socket("staff-door", "access", SOUTH, 2),
		new /datum/generated_room_fragment_socket("power", "utility", NORTH, 3),
	)

/datum/generated_room_fragment/reception_corner/build_occupied_offsets()
	return list(list(2, 2), list(3, 2), list(4, 2), list(3, 3))

/datum/generated_room_fragment/reception_corner/materialize(turf/origin, rotation, mirrored, datum/generated_station_materialization/owner)
	if(!origin || !owner || rotation || mirrored)
		return FALSE
	var/turf/left_desk = locate(origin.x + 1, origin.y + 1, origin.z)
	var/turf/center_desk = locate(origin.x + 2, origin.y + 1, origin.z)
	var/turf/right_desk = locate(origin.x + 3, origin.y + 1, origin.z)
	var/turf/seat_turf = locate(origin.x + 2, origin.y + 2, origin.z)
	if(!left_desk || !center_desk || !right_desk || !seat_turf)
		return FALSE
	owner.register_furnishing(new /obj/structure/table/standard(left_desk))
	owner.register_furnishing(new /obj/structure/table/standard(center_desk))
	owner.register_furnishing(new /obj/structure/table/standard(right_desk))
	var/obj/structure/bed/chair/office/seat = new(seat_turf)
	seat.set_dir(SOUTH)
	owner.register_furnishing(seat)
	return TRUE

/datum/generated_room_fragment/reception_corner/build_constraints()
	return list(
		new /datum/generated_room_constraint/in_corner(id),
		new /datum/generated_room_constraint/visible_from_entrance(id),
		new /datum/generated_room_constraint/clear_frontage(id),
	)

/// A complete operator position reused by control, monitoring, and dispatch rooms.
/datum/generated_room_fragment/operator_nook
	id = "operator-nook"
	width = 4
	height = 3
	allow_rotation = FALSE
	anchor_kind = "wall"
	anchor_edge = NORTH

/datum/generated_room_fragment/operator_nook/build_occupied_offsets()
	return list(list(2, 1), list(3, 1), list(2, 2), list(3, 2))

/datum/generated_room_fragment/operator_nook/materialize(turf/origin, rotation, mirrored, datum/generated_station_materialization/owner)
	if(!origin || !owner || rotation || mirrored)
		return FALSE
	var/turf/left = locate(origin.x + 1, origin.y, origin.z)
	var/turf/right = locate(origin.x + 2, origin.y, origin.z)
	var/turf/left_seat = locate(origin.x + 1, origin.y + 1, origin.z)
	var/turf/right_seat = locate(origin.x + 2, origin.y + 1, origin.z)
	if(!left || !right || !left_seat || !right_seat)
		return FALSE
	owner.register_furnishing(new /obj/machinery/computer/security(left))
	owner.register_furnishing(new /obj/machinery/computer/communications(right))
	var/obj/structure/bed/chair/office/first_chair = new(left_seat)
	first_chair.set_dir(NORTH)
	owner.register_furnishing(first_chair)
	var/obj/structure/bed/chair/office/second_chair = new(right_seat)
	second_chair.set_dir(NORTH)
	owner.register_furnishing(second_chair)
	return TRUE

/// Compact treatment cluster with a bed, IV stand, and accessible medical storage.
/datum/generated_room_fragment/treatment_bay
	id = "treatment-bay"
	width = 4
	height = 4
	allow_rotation = FALSE
	anchor_kind = "wall"
	anchor_edge = NORTH

/datum/generated_room_fragment/treatment_bay/build_occupied_offsets()
	return list(list(1, 1), list(2, 1), list(3, 1), list(2, 2))

/datum/generated_room_fragment/treatment_bay/materialize(turf/origin, rotation, mirrored, datum/generated_station_materialization/owner)
	if(!origin || !owner || rotation || mirrored)
		return FALSE
	owner.register_furnishing(new /obj/structure/closet/secure_closet/medical1(origin))
	owner.register_furnishing(new /obj/structure/bed(locate(origin.x + 1, origin.y, origin.z)))
	owner.register_furnishing(new /obj/machinery/iv_drip(locate(origin.x + 2, origin.y, origin.z)))
	owner.register_furnishing(new /obj/machinery/sleeper(locate(origin.x + 1, origin.y + 1, origin.z)))
	return TRUE

/// Dense storage/loading motif used by cargo, equipment, and secure stores.
/datum/generated_room_fragment/storage_bay
	id = "storage-bay"
	width = 4
	height = 3
	allow_rotation = FALSE
	anchor_kind = "wall"
	anchor_edge = NORTH

/datum/generated_room_fragment/storage_bay/build_occupied_offsets()
	return list(list(1, 1), list(2, 1), list(3, 1), list(3, 2))

/datum/generated_room_fragment/storage_bay/materialize(turf/origin, rotation, mirrored, datum/generated_station_materialization/owner)
	if(!origin || !owner || rotation || mirrored)
		return FALSE
	owner.register_furnishing(new /obj/structure/closet/crate(origin))
	owner.register_furnishing(new /obj/structure/closet/crate(locate(origin.x + 1, origin.y, origin.z)))
	owner.register_furnishing(new /obj/structure/closet/crate/internals(locate(origin.x + 2, origin.y, origin.z)))
	owner.register_furnishing(new /obj/machinery/recharger(locate(origin.x + 2, origin.y + 1, origin.z)))
	return TRUE

/// Content modifier selected by station faction and architectural style.
/datum/generated_room_variant
	var/id = "default"
	var/list/faction_ids
	var/list/style_ids
	var/weight = 1
	var/list/added_feature_types
	var/list/removed_feature_ids
	var/list/added_group_types
	var/list/added_fragment_types

/datum/generated_room_variant/New()
	..()
	faction_ids = build_faction_ids()
	style_ids = build_style_ids()
	added_feature_types = build_added_feature_types()
	removed_feature_ids = build_removed_feature_ids()
	added_group_types = build_added_group_types()
	added_fragment_types = build_added_fragment_types()

/datum/generated_room_variant/proc/build_faction_ids()
	return list()

/datum/generated_room_variant/proc/build_style_ids()
	return list()

/datum/generated_room_variant/proc/build_added_feature_types()
	return list()

/datum/generated_room_variant/proc/build_removed_feature_ids()
	return list()

/datum/generated_room_variant/proc/build_added_group_types()
	return list()

/datum/generated_room_variant/proc/build_added_fragment_types()
	return list()

/datum/generated_room_variant/proc/matches(faction_id, style_id)
	return (!length(faction_ids) || (faction_id in faction_ids)) && (!length(style_ids) || (style_id in style_ids))

/datum/generated_room_variant/sterile_research
	id = "sterile-research"
	weight = 3

/datum/generated_room_variant/sterile_research/build_faction_ids()
	return list("research", "corporate")

/datum/generated_room_variant/sterile_research/build_style_ids()
	return list("sterile")

/datum/generated_room_variant/salvage_industrial
	id = "salvage-industrial"
	weight = 2

/datum/generated_room_variant/salvage_industrial/build_faction_ids()
	return list("salvage")

/datum/generated_room_variant/salvage_industrial/build_style_ids()
	return list("industrial")

/// Deterministic, geometry-independent content request consumed by a room solver.
/datum/generated_room_content_plan
	var/definition_id
	var/variant_id = "default"
	var/list/feature_types
	var/list/group_types
	var/list/fragment_types

/datum/generated_room_content_plan/New()
	..()
	feature_types = list()
	group_types = list()
	fragment_types = list()

/datum/generated_room_content_plan/Destroy()
	feature_types = null
	group_types = null
	fragment_types = null
	return ..()

/// Visual language for a generated room, independent of its functional contents.
/datum/generated_room_style
	var/floor_type = /turf/simulated/floor/tiled
	var/accent_color = COLOR_WHITE
	var/aesthetic_id = "general"
	var/trim_density = 0.18
	var/decoration_density = 0.14

/datum/generated_room_style/proc/is_valid()
	return ispath(floor_type, /turf/simulated/floor) && accent_color && aesthetic_id && trim_density >= 0 && trim_density <= 1 && decoration_density >= 0 && decoration_density <= 1

/datum/generated_room_style/command
	floor_type = /turf/simulated/floor/tiled/neutral
	accent_color = COLOR_COMMAND_BLUE
	aesthetic_id = "command"
	decoration_density = 0.18

/datum/generated_room_style/ai
	floor_type = /turf/simulated/floor/tiled/techfloor/grid
	accent_color = COLOR_CYAN_BLUE
	aesthetic_id = "ai"
	trim_density = 0.28
	decoration_density = 0.12

/datum/generated_room_style/ai/support
	floor_type = /turf/simulated/floor/tiled/techfloor
	aesthetic_id = "ai-support"

/datum/generated_room_style/security
	floor_type = /turf/simulated/floor/tiled/dark
	accent_color = COLOR_RED_GRAY
	aesthetic_id = "security"
	decoration_density = 0.16

/datum/generated_room_style/security/brig
	floor_type = /turf/simulated/floor/tiled/red
	aesthetic_id = "security-brig"

/datum/generated_room_style/medical
	floor_type = /turf/simulated/floor/tiled/white
	accent_color = COLOR_BLUE_GRAY
	aesthetic_id = "medical"
	decoration_density = 0.18

/datum/generated_room_style/engineering
	floor_type = /turf/simulated/floor/tiled/eris/steel/techfloor
	accent_color = COLOR_DARK_ORANGE
	aesthetic_id = "engineering"
	trim_density = 0.25
	decoration_density = 0.16

/datum/generated_room_style/engineering/atmospherics
	floor_type = /turf/simulated/floor/tiled/steel_grid
	aesthetic_id = "engineering-atmospherics"

/datum/generated_room_style/cargo
	floor_type = /turf/simulated/floor/tiled/eris/steel/cargo
	accent_color = COLOR_YELLOW_GRAY
	aesthetic_id = "cargo"
	trim_density = 0.24
	decoration_density = 0.17

/datum/generated_room_style/cargo/processing
	floor_type = /turf/simulated/floor/tiled/steel_grid
	aesthetic_id = "cargo-processing"

/datum/generated_room_style/docking
	floor_type = /turf/simulated/floor/tiled/eris/steel/panels
	accent_color = COLOR_DARK_GUNMETAL
	aesthetic_id = "docking"
	decoration_density = 0.15

/datum/generated_room_style/docking/control
	floor_type = /turf/simulated/floor/tiled
	aesthetic_id = "docking-control"

/// Functional contract used to synthesize one room inside an authored shell.
/datum/generated_room_definition
	var/id = "room"
	var/name = "Generated Room"
	var/min_width = 5
	var/max_width = 12
	var/min_height = 5
	var/max_height = 12
	var/min_entrances = 1
	var/max_entrances = 2
	var/density_min = 0.12
	var/density_max = 0.42
	var/wall_utilization_target = 0.35
	var/circulation_min = 0.25
	var/allow_narrow_irregular = FALSE
	var/list/required_features
	var/list/required_groups
	var/list/optional_groups
	var/list/fragment_options
	var/list/constraints
	var/list/variant_options
	var/datum/generated_room_style/room_style

/datum/generated_room_definition/New()
	..()
	required_features = build_required_features()
	required_groups = build_required_groups()
	optional_groups = build_optional_groups()
	fragment_options = build_fragment_options()
	constraints = build_constraints()
	variant_options = build_variant_options()
	room_style = build_room_style()

/datum/generated_room_definition/Destroy()
	required_features = null
	required_groups = null
	optional_groups = null
	fragment_options = null
	QDEL_LIST(constraints)
	variant_options = null
	QDEL_NULL(room_style)
	return ..()

/datum/generated_room_definition/proc/build_required_features()
	return list()

/datum/generated_room_definition/proc/build_required_groups()
	return list()

/datum/generated_room_definition/proc/build_optional_groups()
	return list()

/datum/generated_room_definition/proc/build_fragment_options()
	return list()

/datum/generated_room_definition/proc/build_constraints()
	return list()

/datum/generated_room_definition/proc/build_variant_options()
	return list()

/datum/generated_room_definition/proc/build_room_style()
	return new /datum/generated_room_style

/datum/generated_room_definition/proc/is_contract_valid()
	if(!id || min_width < 3 || min_height < 3 || max_width < min_width || max_height < min_height)
		return FALSE
	if(min_entrances < 1 || max_entrances < min_entrances)
		return FALSE
	if(density_min < 0 || density_max > 1 || density_max < density_min)
		return FALSE
	return circulation_min >= 0 && circulation_min <= 1 && wall_utilization_target >= 0 && wall_utilization_target <= 1 && room_style?.is_valid()

/// Returns whether an inclusive room footprint obeys this program's geometry contract.
/datum/generated_room_definition/proc/accepts_dimensions(width, height)
	return width >= min_width && width <= max_width && height >= min_height && height <= max_height

/// Prefers balanced footprints near the center of the authored size range.
/datum/generated_room_definition/proc/dimension_score(width, height)
	if(!accepts_dimensions(width, height))
		return -1
	var/ideal_width = (min_width + max_width) / 2
	var/ideal_height = (min_height + max_height) / 2
	return 100 - abs(width - ideal_width) - abs(height - ideal_height) - abs(width - height) * 0.25

/datum/generated_room_definition/proc/build_content_plan(seed, faction_id, style_id)
	var/datum/generated_room_content_plan/plan = new
	plan.definition_id = id
	plan.feature_types = required_features.Copy()
	plan.group_types = required_groups.Copy()
	// Fragment options are optional alternatives, not a list of mandatory pieces.
	// Selecting one here keeps the content request small while allowing the room
	// solver to omit it when an irregular footprint has no legal anchor.
	if(length(fragment_options))
		var/datum/generated_station_prng/fragment_prng = new(seed + 3571)
		if(fragment_prng.next_range(0, 1))
			plan.fragment_types += fragment_options[fragment_prng.next_range(1, length(fragment_options))]
		qdel(fragment_prng)
	var/list/matches = list()
	var/total_weight = 0
	for(var/variant_type in variant_options)
		var/datum/generated_room_variant/variant = new variant_type
		if(variant.matches(faction_id, style_id) && variant.weight > 0)
			matches += variant
			total_weight += variant.weight
		else
			qdel(variant)
	if(total_weight)
		var/datum/generated_station_prng/prng = new(seed)
		var/roll = prng.next_range(1, total_weight)
		qdel(prng)
		for(var/datum/generated_room_variant/variant in matches)
			roll -= variant.weight
			if(roll > 0)
				continue
			plan.variant_id = variant.id
			plan.feature_types |= variant.added_feature_types
			plan.group_types |= variant.added_group_types
			plan.fragment_types |= variant.added_fragment_types
			break
	QDEL_LIST(matches)
	if(length(optional_groups))
		var/datum/generated_station_prng/optional_prng = new(seed + 7919)
		plan.group_types |= optional_groups[optional_prng.next_range(1, length(optional_groups))]
		qdel(optional_prng)
	return plan

/datum/generated_room_definition/surgery
	id = "medical-surgery"
	name = "Surgery"
	min_width = 7
	max_width = 11
	min_height = 7
	max_height = 12
	density_min = 0.16
	density_max = 0.38

/datum/generated_room_definition/surgery/build_required_features()
	return list(/datum/generated_room_feature/medical_storage, /datum/generated_room_feature/sleeper)

/datum/generated_room_definition/surgery/build_required_groups()
	return list(/datum/generated_room_feature_group/operating_theatre, /datum/generated_room_feature_group/medical_storage_bank)

/datum/generated_room_definition/surgery/build_variant_options()
	return list(/datum/generated_room_variant/sterile_research, /datum/generated_room_variant/salvage_industrial)

/datum/generated_room_definition/surgery/build_room_style()
	return new /datum/generated_room_style/medical

/datum/generated_room_definition/surgery/dedicated
	id = "medical-dedicated-surgery"
	name = "Surgical Theatre"

/datum/generated_room_definition/reception
	id = "public-reception"
	name = "Reception"
	min_width = 8
	max_width = 13
	min_height = 6
	max_height = 12
	density_min = 0.18
	density_max = 0.45

/datum/generated_room_definition/reception/build_required_features()
	return list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/reception_chair)

/datum/generated_room_definition/reception/build_optional_groups()
	return list(/datum/generated_room_feature_group/waiting_area)

/datum/generated_room_definition/reception/build_fragment_options()
	return list(/datum/generated_room_fragment/reception_corner)

/datum/generated_room_definition/reception/build_constraints()
	return list(new /datum/generated_room_constraint/behind_access_boundary("staff-area", "public-area"))

/datum/generated_room_definition/command_operations
	id = "command-operations"
	name = "Command Operations"
	min_width = 6
	max_width = 10
	min_height = 6
	density_min = 0.16
	density_max = 0.4

/datum/generated_room_definition/command_operations/build_required_groups()
	return list(/datum/generated_room_feature_group/command_desk, /datum/generated_room_feature_group/communications_bank)

/datum/generated_room_definition/command_operations/build_optional_groups()
	return list(/datum/generated_room_feature_group/waiting_area)

/datum/generated_room_definition/command_operations/build_fragment_options()
	return list(/datum/generated_room_fragment/reception_corner)

/datum/generated_room_definition/command_operations/build_variant_options()
	return list(/datum/generated_room_variant/sterile_research, /datum/generated_room_variant/salvage_industrial)

/datum/generated_room_definition/command_operations/build_room_style()
	return new /datum/generated_room_style/command

/datum/generated_room_definition/command_communications
	id = "command-communications"
	name = "Communications Center"
	density_min = 0.14
	density_max = 0.38

/datum/generated_room_definition/command_communications/build_required_features()
	return list(/datum/generated_room_feature/internals_crate)

/datum/generated_room_definition/command_communications/build_required_groups()
	return list(/datum/generated_room_feature_group/communications_bank, /datum/generated_room_feature_group/workstation_bank)

/datum/generated_room_definition/command_communications/build_room_style()
	return new /datum/generated_room_style/command

/datum/generated_room_definition/ai_core
	id = "ai-core"
	name = "AI Core Control"
	density_min = 0.12
	density_max = 0.34

/datum/generated_room_definition/ai_core/build_required_features()
	return list(/datum/generated_room_feature/recharger)

/datum/generated_room_definition/ai_core/build_required_groups()
	return list(/datum/generated_room_feature_group/security_console_bank, /datum/generated_room_feature_group/electrical_storage_bank)

/datum/generated_room_definition/ai_core/build_constraints()
	return list(new /datum/generated_room_constraint/behind_access_boundary("ai-control", "public-area"), new /datum/generated_room_constraint/requires_utility("ai-control", null, TRUE, 1))

/datum/generated_room_definition/ai_core/build_room_style()
	return new /datum/generated_room_style/ai

/datum/generated_room_definition/ai_support
	id = "ai-support"
	name = "AI Support"
	density_min = 0.14
	density_max = 0.38

/datum/generated_room_definition/ai_support/build_required_features()
	return list(/datum/generated_room_feature/recharger)

/datum/generated_room_definition/ai_support/build_required_groups()
	return list(/datum/generated_room_feature_group/engineering_bench, /datum/generated_room_feature_group/electrical_storage_bank)

/datum/generated_room_definition/ai_support/build_room_style()
	return new /datum/generated_room_style/ai/support

/datum/generated_room_definition/security_operations
	id = "security-operations"
	name = "Security Operations"
	density_min = 0.18
	density_max = 0.45

/datum/generated_room_definition/security_operations/build_required_groups()
	return list(/datum/generated_room_feature_group/security_post, /datum/generated_room_feature_group/security_console_bank, /datum/generated_room_feature_group/workstation_bank)

/datum/generated_room_definition/security_operations/build_room_style()
	return new /datum/generated_room_style/security

/datum/generated_room_definition/security_brig
	id = "security-brig"
	name = "Brig"
	density_min = 0.12
	density_max = 0.36

/datum/generated_room_definition/security_brig/build_required_features()
	return list(/datum/generated_room_feature/work_table)

/datum/generated_room_definition/security_brig/build_required_groups()
	return list(/datum/generated_room_feature_group/brig_bunks, /datum/generated_room_feature_group/security_console_bank)

/datum/generated_room_definition/security_brig/build_constraints()
	return list(new /datum/generated_room_constraint/behind_access_boundary("cell", "security-desk"))

/datum/generated_room_definition/security_brig/build_room_style()
	return new /datum/generated_room_style/security/brig

/datum/generated_room_definition/medical_ward
	id = "medical-ward"
	name = "Patient Ward"
	density_min = 0.15
	density_max = 0.4

/datum/generated_room_definition/medical_ward/build_required_groups()
	return list(/datum/generated_room_feature_group/patient_bay, /datum/generated_room_feature_group/medical_storage_bank)

/datum/generated_room_definition/medical_ward/build_required_features()
	return list(/datum/generated_room_feature/medical_storage)

/datum/generated_room_definition/medical_ward/build_room_style()
	return new /datum/generated_room_style/medical

/datum/generated_room_definition/engineering_power
	id = "engineering-power"
	name = "Power Control"
	density_min = 0.16
	density_max = 0.42

/datum/generated_room_definition/engineering_power/build_required_features()
	return list(/datum/generated_room_feature/recharger)

/datum/generated_room_definition/engineering_power/build_required_groups()
	return list(/datum/generated_room_feature_group/engineering_bench, /datum/generated_room_feature_group/electrical_storage_bank)

/datum/generated_room_definition/engineering_power/build_constraints()
	return list(new /datum/generated_room_constraint/requires_utility("power-control", null, TRUE, 1))

/datum/generated_room_definition/engineering_power/build_room_style()
	return new /datum/generated_room_style/engineering

/datum/generated_room_definition/engineering_atmospherics
	id = "engineering-atmospherics"
	name = "Atmospherics Workshop"
	density_min = 0.15
	density_max = 0.42

/datum/generated_room_definition/engineering_atmospherics/build_required_features()
	return list(/datum/generated_room_feature/internals_crate)

/datum/generated_room_definition/engineering_atmospherics/build_required_groups()
	return list(/datum/generated_room_feature_group/atmospherics_bench)

/datum/generated_room_definition/engineering_atmospherics/build_constraints()
	return list(new /datum/generated_room_constraint/requires_utility("atmos-workshop", null, TRUE, 1))

/datum/generated_room_definition/engineering_atmospherics/build_room_style()
	return new /datum/generated_room_style/engineering/atmospherics

/datum/generated_room_definition/logistics_cargo
	id = "logistics-cargo"
	name = "Cargo Office"
	density_min = 0.18
	density_max = 0.48

/datum/generated_room_definition/logistics_cargo/build_required_features()
	return list(/datum/generated_room_feature/supply_console, /datum/generated_room_feature/cargo_locker)

/datum/generated_room_definition/logistics_cargo/build_required_groups()
	return list(/datum/generated_room_feature_group/cargo_stack)

/datum/generated_room_definition/logistics_cargo/build_room_style()
	return new /datum/generated_room_style/cargo

/datum/generated_room_definition/logistics_processing
	id = "logistics-processing"
	name = "Freight Processing"
	density_min = 0.16
	density_max = 0.46

/datum/generated_room_definition/logistics_processing/build_required_features()
	return list()

/datum/generated_room_definition/logistics_processing/build_required_groups()
	return list(/datum/generated_room_feature_group/cargo_stack, /datum/generated_room_feature_group/cargo_workstation)

/datum/generated_room_definition/logistics_processing/build_room_style()
	return new /datum/generated_room_style/cargo/processing

/datum/generated_room_definition/docking_control
	id = "docking-control"
	name = "Dock Control"
	density_min = 0.15
	density_max = 0.4

/datum/generated_room_definition/docking_control/build_required_features()
	return list(/datum/generated_room_feature/internals_crate)

/datum/generated_room_definition/docking_control/build_required_groups()
	return list(/datum/generated_room_feature_group/communications_bank, /datum/generated_room_feature_group/workstation_bank)

/datum/generated_room_definition/docking_control/build_room_style()
	return new /datum/generated_room_style/docking/control

/datum/generated_room_definition/docking_berth
	id = "docking-berth"
	name = "Docking Concourse"
	density_min = 0.14
	density_max = 0.4

/datum/generated_room_definition/docking_berth/build_required_features()
	return list(/datum/generated_room_feature/internals_crate, /datum/generated_room_feature/communications_console)

/datum/generated_room_definition/docking_berth/build_required_groups()
	return list(/datum/generated_room_feature_group/berth_seating)

/datum/generated_room_definition/docking_berth/build_room_style()
	return new /datum/generated_room_style/docking

/proc/generated_room_definition_catalog()
	return list(
		new /datum/generated_room_definition/command_operations,
		new /datum/generated_room_definition/command_communications,
		new /datum/generated_room_definition/ai_core,
		new /datum/generated_room_definition/ai_support,
		new /datum/generated_room_definition/security_operations,
		new /datum/generated_room_definition/security_brig,
		new /datum/generated_room_definition/surgery,
		new /datum/generated_room_definition/medical_ward,
		new /datum/generated_room_definition/engineering_power,
		new /datum/generated_room_definition/engineering_atmospherics,
		new /datum/generated_room_definition/logistics_cargo,
		new /datum/generated_room_definition/logistics_processing,
		new /datum/generated_room_definition/docking_control,
		new /datum/generated_room_definition/docking_berth,
	)

/// Returns a fresh functional contract for a department module when one is authored.
/proc/generated_room_definition_for(department_id, role)
	if(!(role in generated_station_rust_room_roles(department_id)))
		return null
	switch("[department_id]/[role]")
		if("command/operations")
			return new /datum/generated_room_definition/command_operations
		if("command/communications")
			return new /datum/generated_room_definition/command_communications
		if("ai/core")
			return new /datum/generated_room_definition/ai_core
		if("ai/support")
			return new /datum/generated_room_definition/ai_support
		if("security/operations")
			return new /datum/generated_room_definition/security_operations
		if("security/brig")
			return new /datum/generated_room_definition/security_brig
		if("medical/treatment")
			return new /datum/generated_room_definition/surgery
		if("medical/surgery")
			return new /datum/generated_room_definition/surgery/dedicated
		if("medical/ward")
			return new /datum/generated_room_definition/medical_ward
		if("engineering/power")
			return new /datum/generated_room_definition/engineering_power
		if("engineering/atmospherics")
			return new /datum/generated_room_definition/engineering_atmospherics
		if("logistics/cargo")
			return new /datum/generated_room_definition/logistics_cargo
		if("logistics/processing")
			return new /datum/generated_room_definition/logistics_processing
		if("docking/control")
			return new /datum/generated_room_definition/docking_control
		if("docking/berth")
			return new /datum/generated_room_definition/docking_berth
	var/datum/generated_room_definition/fallback = new
	fallback.id = "[department_id]-[role]"
	fallback.name = capitalize(replacetext(role, "-", " "))
	QDEL_NULL(fallback.room_style)
	switch(department_id)
		if("command")
			fallback.room_style = new /datum/generated_room_style/command
		if("ai")
			fallback.room_style = new /datum/generated_room_style/ai/support
		if("security")
			fallback.room_style = new /datum/generated_room_style/security
		if("medical")
			fallback.room_style = new /datum/generated_room_style/medical
		if("engineering")
			fallback.room_style = new /datum/generated_room_style/engineering
		if("logistics")
			fallback.room_style = new /datum/generated_room_style/cargo
		if("docking")
			fallback.room_style = new /datum/generated_room_style/docking
		else
			fallback.room_style = new /datum/generated_room_style
	fallback.density_min = 0.2
	fallback.density_max = 0.5
	switch("[department_id]/[role]")
		if("command/reception", "security/reception", "medical/reception", "logistics/reception", "docking/reception", "ai/foyer", "engineering/foyer")
			fallback.required_features = list(/datum/generated_room_feature/reception_desk, /datum/generated_room_feature/reception_chair)
			fallback.required_groups = list(/datum/generated_room_feature_group/waiting_area)
			fallback.fragment_options = list(/datum/generated_room_fragment/reception_corner)
		if("command/meeting", "command/briefing")
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank, /datum/generated_room_feature_group/berth_seating)
			fallback.fragment_options = list(/datum/generated_room_fragment/operator_nook)
		if("command/records")
			fallback.required_features = list(/datum/generated_room_feature/internals_crate)
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank, /datum/generated_room_feature_group/cargo_stack)
		if("command/liaison", "command/flex")
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank, /datum/generated_room_feature_group/communications_bank)
			fallback.fragment_options = list(/datum/generated_room_fragment/operator_nook)
		if("ai/satellite", "ai/monitoring")
			fallback.required_features = list(/datum/generated_room_feature/recharger)
			fallback.required_groups = list(/datum/generated_room_feature_group/security_console_bank, /datum/generated_room_feature_group/electrical_storage_bank)
			fallback.fragment_options = list(/datum/generated_room_fragment/operator_nook)
		if("ai/robotics", "ai/flex")
			fallback.required_groups = list(/datum/generated_room_feature_group/engineering_bench, /datum/generated_room_feature_group/workstation_bank)
		if("ai/secure-storage")
			fallback.required_groups = list(/datum/generated_room_feature_group/electrical_storage_bank)
			fallback.fragment_options = list(/datum/generated_room_fragment/storage_bay)
		if("security/armory", "security/evidence", "security/locker-room")
			fallback.required_features = list(/datum/generated_room_feature/recharger)
			fallback.required_groups = list(/datum/generated_room_feature_group/security_storage_bank, /datum/generated_room_feature_group/cargo_stack)
			fallback.fragment_options = list(/datum/generated_room_fragment/storage_bay)
		if("security/interrogation", "security/flex")
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank, /datum/generated_room_feature_group/security_console_bank)
		if("medical/pharmacy", "medical/storage")
			fallback.required_groups = list(/datum/generated_room_feature_group/medical_storage_bank, /datum/generated_room_feature_group/workstation_bank)
			fallback.fragment_options = list(/datum/generated_room_fragment/treatment_bay)
		if("medical/recovery")
			fallback.required_groups = list(/datum/generated_room_feature_group/patient_bay, /datum/generated_room_feature_group/medical_storage_bank)
			fallback.fragment_options = list(/datum/generated_room_fragment/treatment_bay)
		if("medical/flex")
			fallback.required_features = list(/datum/generated_room_feature/medical_storage)
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank)
		if("engineering/workshop", "engineering/equipment", "engineering/maintenance", "engineering/flex")
			fallback.required_groups = list(/datum/generated_room_feature_group/engineering_bench, /datum/generated_room_feature_group/electrical_storage_bank)
		if("engineering/storage")
			fallback.required_groups = list(/datum/generated_room_feature_group/electrical_storage_bank, /datum/generated_room_feature_group/cargo_stack)
			fallback.fragment_options = list(/datum/generated_room_fragment/storage_bay)
		if("logistics/warehouse", "logistics/sorting", "logistics/storage", "logistics/flex")
			fallback.required_groups = list(/datum/generated_room_feature_group/cargo_stack, /datum/generated_room_feature_group/cargo_workstation)
			fallback.fragment_options = list(/datum/generated_room_fragment/storage_bay)
		if("logistics/dispatch")
			fallback.required_features = list(/datum/generated_room_feature/supply_console)
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank, /datum/generated_room_feature_group/cargo_stack)
			fallback.fragment_options = list(/datum/generated_room_fragment/operator_nook)
		if("docking/security")
			fallback.required_groups = list(/datum/generated_room_feature_group/security_console_bank, /datum/generated_room_feature_group/security_storage_bank)
			fallback.fragment_options = list(/datum/generated_room_fragment/operator_nook)
		if("docking/customs")
			fallback.required_groups = list(/datum/generated_room_feature_group/workstation_bank, /datum/generated_room_feature_group/security_console_bank)
		if("docking/lounge")
			fallback.required_groups = list(/datum/generated_room_feature_group/berth_seating, /datum/generated_room_feature_group/waiting_area)
		if("docking/equipment", "docking/flex")
			fallback.required_features = list(/datum/generated_room_feature/internals_crate)
			fallback.required_groups = list(/datum/generated_room_feature_group/cargo_stack, /datum/generated_room_feature_group/berth_seating)
			fallback.fragment_options = list(/datum/generated_room_fragment/storage_bay)
	// Role-level flooring makes adjacent rooms readable even when they belong to
	// the same department. Borders remain department-colored and are never scattered.
	switch(role)
		if("reception", "foyer", "lounge") fallback.room_style.floor_type = /turf/simulated/floor/tiled/neutral
		if("operations", "control", "monitoring", "dispatch") fallback.room_style.floor_type = /turf/simulated/floor/tiled/techfloor/grid
		if("storage", "warehouse", "equipment", "secure-storage", "armory", "evidence") fallback.room_style.floor_type = /turf/simulated/floor/tiled/eris/steel/cargo
		if("treatment", "recovery", "pharmacy") fallback.room_style.floor_type = /turf/simulated/floor/tiled/white
		if("maintenance", "workshop", "sorting", "processing") fallback.room_style.floor_type = /turf/simulated/floor/tiled/steel_grid
	generated_room_apply_authored_role_program(fallback, department_id, role)
	return fallback

/// Returns a lightweight department-styled contract for a footprint too small
/// to support the full functional room assigned to that space.
/proc/generated_compact_room_definition_for(department_id, role)
	var/datum/generated_room_definition/compact = generated_room_definition_for(department_id, role)
	compact.id = "[department_id]-compact-[role]"
	compact.name = "Compact [capitalize(replacetext(role, "-", " "))]"
	compact.min_width = 2
	compact.min_height = 2
	compact.max_width = 12
	compact.max_height = 12
	compact.allow_narrow_irregular = TRUE
	// Compact rooms retain every independently required fixture and the defining
	// fixture from each activity group. Role signatures are independently required,
	// so this reduction cannot erase the room's purpose.
	var/list/compact_features = generated_room_compact_authored_features(department_id, role)
	if(!length(compact_features))
		compact_features = compact.required_features.Copy()
		if(length(compact_features) > 2)
			compact_features.Cut(3)
		if(length(compact_features) < 2)
			for(var/group_type in compact.required_groups)
				var/datum/generated_room_feature_group/group = new group_type
				if(length(group.feature_types))
					compact_features |= group.feature_types[1]
				qdel(group)
				if(length(compact_features) >= 2)
					break
	compact.required_features = compact_features
	compact.required_groups = list()
	compact.optional_groups = list()
	compact.fragment_options = list()
	compact.density_min = 0.12
	compact.density_max = 0.36
	compact.circulation_min = 0.2
	return compact

/// Guaranteed room shell used only after authored and compact content cannot
/// satisfy a runtime footprint. Tests keep strict contracts and never accept it.
/proc/generated_minimum_room_definition_for(department_id, role)
	var/datum/generated_room_definition/minimum = generated_room_definition_for(department_id, role)
	if(!minimum)
		minimum = new
	minimum.id = "[department_id]-minimum-[role]"
	minimum.name = "Minimum [capitalize(replacetext(role, "-", " "))]"
	minimum.min_width = 1
	minimum.min_height = 1
	minimum.max_width = 255
	minimum.max_height = 255
	minimum.allow_narrow_irregular = TRUE
	minimum.required_features = list()
	minimum.required_groups = list()
	minimum.optional_groups = list()
	minimum.fragment_options = list()
	minimum.density_min = 0
	minimum.density_max = 0
	minimum.circulation_min = 0
	return minimum
