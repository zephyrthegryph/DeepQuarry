// Actual seat admission/posture/transport policy. Rider links remain native relations.
STATIC_ENTRY(seat_policy)
/proc/seat_policy(movable = null, direction = null, lying = null, require_restraints = null, capacity = null)
	return entry_make(ENTRY_SEAT_POLICY, null, list("movable" = movable, "direction" = direction, "lying" = lying, "require_restraints" = require_restraints, "capacity" = capacity))
/datum/type_trait/seat_policy
	var/movable = 0
	var/direction = 0
	var/lying = -1
	var/require_restraints = 0
	var/capacity = 1
/datum/type_trait/seat_policy/copy_values(datum/type_trait/seat_policy/into)
	into.movable = movable
	into.direction = direction
	into.lying = lying
	into.require_restraints = require_restraints
	into.capacity = capacity
/datum/entry_engine/type_trait/seat_policy
	kind = ENTRY_SEAT_POLICY
	trait_type = /datum/type_trait/seat_policy
	publish_key = SEAT_POLICY_KEY
	base_type = /atom/movable
	var_names = list("buckle_movable" = "movable", "buckle_dir" = "direction", "buckle_lying" = "lying", "buckle_require_restraints" = "require_restraints", "max_buckled_mobs" = "capacity")
READS_AS(/proc/seat_policy_of, SEAT_POLICY_KEY)
/proc/seat_policy_of(atom/movable/seat) as /datum/type_trait/seat_policy
	READS_FROM(seat)
	return type_trait_of(seat, ENTRY_SEAT_POLICY)
/proc/seat_policy_of_type(path) as /datum/type_trait/seat_policy
	READS_FROM()
	return type_trait_of_type(path, ENTRY_SEAT_POLICY)
