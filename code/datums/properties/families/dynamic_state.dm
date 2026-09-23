// Properties that change while the game runs, for rules (rules.md §4).
//
// Temperature is channel-backed (PROP_SOURCE_DOMAIN): rules over it compile to
// reactor watches on the object's heat node. Integrity is DM-owned: it
// publishes a reactor key when it changes, and rules over it re-evaluate then.

// ---- Channel-backed (domain) providers ----

/// A base provider whose value lives on a reactor channel of a per-object node.
/datum/property_provider/domain
	source = PROP_SOURCE_DOMAIN
	/// DQ_RX_CH_* channel on the node.
	var/channel

/// The node handle for `D`, creating it when `create`. Null if it has none.
/datum/property_provider/domain/proc/node_of(datum/D, create)
	return dq_rule_node(D, property, create ? src : null)

/datum/property_provider/domain/instance_value(datum/D)
	var/handle = node_of(D, FALSE)
	return isnull(handle) ? null : dq_rx_node_read(handle, channel)

/datum/property_provider/domain/test_write(datum/D, value)
	var/handle = node_of(D, FALSE)
	if(isnull(handle))
		return FALSE
	dq_rx_node_write(handle, channel, value)
	return TRUE

/datum/property_def/temperature
	id = PROP_TEMPERATURE
	name = "Temperature"
	desc = "The object's own temperature, from its heat node."
	unit = PROP_UNIT_KELVIN
	aggregator = PROP_AGG_MAX
	min_value = 0
	high_word = "hot"
	low_word = "cold"

/// An object's temperature is its heat body's, or its surroundings' at rest
/// (M4). Rules over it watch the body (reactor_adapter.dm).
/datum/property_provider/domain/heat
	property = PROP_TEMPERATURE
	applies_to = /obj
	unit = PROP_UNIT_KELVIN
	channel = DQ_RX_CH_TEMPERATURE

/datum/property_provider/domain/heat/instance_value(datum/D)
	var/atom/A = D
	return A.get_temperature()

/datum/property_provider/domain/heat/test_write(datum/D, value)
	var/atom/A = D
	if(!A.create_heat_body())
		return FALSE
	vg_heat_body_couple(A.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
	vg_heat_body_set_temperature(A.heat_body, value)
	return TRUE

// ---- DM-owned: integrity ----

/datum/property_def/integrity_ratio
	id = PROP_INTEGRITY_RATIO
	name = "Integrity"
	desc = "Current integrity as a fraction of the maximum."
	unit = PROP_UNIT_RATIO
	aggregator = PROP_AGG_MIN
	min_value = 0
	max_value = 1
	low_word = "damaged"
	dm_key_kind = RULE_KEY_INTEGRITY

/datum/property_provider/integrity_ratio
	property = PROP_INTEGRITY_RATIO
	source = PROP_SOURCE_TYPE
	applies_to = /atom
	unit = PROP_UNIT_RATIO

/datum/property_provider/integrity_ratio/type_value(path, list/variant_vars)
	var/atom/A = path
	return (initial(A.uses_integrity) && initial(A.max_integrity) > 0) ? 1 : null

/datum/property_provider/integrity_ratio/instance_value(datum/D)
	var/atom/A = D
	if(!A.uses_integrity || A.max_integrity <= 0)
		return null
	return A.get_integrity() / A.max_integrity

/datum/property_provider/integrity_ratio/test_write(datum/D, value)
	var/atom/A = D
	if(!A.uses_integrity || A.max_integrity <= 0)
		return FALSE
	A.update_integrity(value * A.max_integrity)
	return TRUE

/datum/property_def/integrity_failure
	id = PROP_INTEGRITY_FAILURE
	name = "Breaking point"
	desc = "Integrity fraction at or below which the object is broken (0: never)."
	unit = PROP_UNIT_RATIO
	min_value = 0
	max_value = 1

/datum/property_provider/type_var/integrity_failure
	property = PROP_INTEGRITY_FAILURE
	applies_to = /atom
	unit = PROP_UNIT_RATIO

/datum/property_provider/type_var/integrity_failure/read_initial(path)
	var/atom/A = path
	return initial(A.integrity_failure)

// ---- Fixed per-type values ----

/// A constant for a type that has no var or material to read it from yet.
/datum/property_provider/constant
	source = PROP_SOURCE_TYPE
	var/value

/datum/property_provider/constant/type_value(path, list/variant_vars)
	return value

/// Paper has no `matter`; its ignition point is book paper's (about 506 K).
/// Replace with a paper material when composition lands.
/datum/property_provider/constant/paper_ignition_point
	property = PROP_IGNITION_POINT
	applies_to = /obj/item/paper
	unit = PROP_UNIT_KELVIN
	value = T0C + 233
	overrides = list(/datum/property_provider/material/ignition_point)
