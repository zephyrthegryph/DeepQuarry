/// The live cargo shuttle, used by status displays and the cargo/PDA controls.
/datum/system/supply/proc/cargo_shuttle()
	return shuttle

/datum/system/supply/proc/register_cargo_shuttle(datum/shuttle/autodock/ferry/supply/candidate)
	if(shuttle)
		CRASH("A supply shuttle is already defined.")
	rel_set(src, nameof(shuttle), candidate)

/datum/system/supply/proc/unregister_cargo_shuttle(datum/shuttle/candidate)
	if(shuttle == candidate)
		rel_clear(src, nameof(shuttle))

/// UI snapshots keep the actual order/receipt datums while isolating list mutation.
/datum/system/supply/proc/order_history_snapshot()
	return order_history?.Copy()

/datum/system/supply/proc/export_history_snapshot()
	return exported_crates?.Copy()

/// Resolve a UI reference against the live owner collection, just as the console did.
/datum/system/supply/proc/order_from_ref(reference)
	return ui_ref(reference, order_history, /datum/supply_order)

/datum/system/supply/proc/export_from_ref(reference)
	return ui_ref(reference, exported_crates, /datum/exported_crate)

/datum/system/supply/proc/market_counterparty(id)
	return market_counterparties?[id]

/datum/system/supply/proc/catalog_names()
	var/list/names = list()
	for(var/name in supply_pack)
		names += name
	return names

/datum/system/supply/proc/catalog_pack(name)
	return supply_pack[name]

/datum/system/supply/proc/pick_catalog_pack()
	return supply_pack[pick(supply_pack)]

/datum/system/supply/proc/current_order_index()
	return ordernum

/// A shipping-error event queues its already-built order without changing order history.
/datum/system/supply/proc/queue_shipping_order(datum/supply_order/order)
	rel_add(src, nameof(shoppinglist), order)

/datum/system/supply/proc/shuttle_travel_duration()
	return movetime

/datum/system/supply/proc/salary_support_ratio()
	return nt_salary_support

/datum/system/supply/proc/allocation_policy_name()
	return allocation_policy

/datum/system/supply/proc/time_until_payroll()
	return max(0, next_payroll - world.time)

/// Convert Thalers to the legacy export-point unit; callers still decide rounding.
/datum/system/supply/proc/money_to_export_points(thalers)
	return thalers * points_per_money
