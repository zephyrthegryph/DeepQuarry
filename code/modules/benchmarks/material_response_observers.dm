/// Measures the cost of eight material-response signal hooks on ordinary items.
/// The same fixture can run before and after an observer API migration.
/datum/benchmark/material_response_observers
	id = "material_response_observers"
	description = "Material response attachment, signal dispatch and teardown (bench_items, bench_rounds)"

/obj/item/material_response_benchmark_item

/datum/benchmark/material_response_observers/Run()
	var/item_count = max(1, min(5000, round(param("items", 1000))))
	var/rounds = max(1, min(20, round(param("rounds", 5))))
	var/datum/material/steel = GLOB.name_to_material[MAT_STEEL]
	if(!steel)
		fail("steel material is unavailable")
		return
	metric("items", item_count, "items", "none")
	metric("rounds", rounds, "rounds", "none")
	mark("before")
	var/list/obj/item/material_response_benchmark_item/items = list()
	var/list/datum/component/material_response/responses = list()
	for(var/i in 1 to item_count)
		items += new /obj/item/material_response_benchmark_item(null)
		CHECK_TICK
	mark("fixture")
	stoplag()
	rustg_time_reset("material_response_observers")
	for(var/obj/item/material_response_benchmark_item/item as anything in items)
		var/datum/component/material_response/response = item.AddComponent(/datum/component/material_response, steel, FALSE, FALSE, FALSE, FALSE)
		if(!response)
			fail("material response failed to attach")
			return
		responses += response
	var/attach_us = rustg_time_microseconds("material_response_observers") / item_count
	var/component_om_states = 0
	var/observation_records = 0
	for(var/datum/component/material_response/response as anything in responses)
		component_om_states += !!response.om_state
		observation_records += length(response.om_state?.observations)
	metric("component_om_states", component_om_states, "states", "none")
	metric("observation_records", observation_records, "records", "none")
	mark("attached")
	var/dispatch_best = INFINITY
	for(var/round in 1 to rounds)
		stoplag()
		rustg_time_reset("material_response_observers")
		for(var/obj/item/material_response_benchmark_item/item as anything in items)
			if(SEND_SIGNAL(item, COMSIG_ATOM_PRE_EMP_ACT, 1) & EMP_PROTECT_SELF)
				fail("inert steel response unexpectedly protected an item from EMP")
		dispatch_best = min(dispatch_best, rustg_time_microseconds("material_response_observers") / item_count)
	metric("attach_us_per_item", attach_us, "us/item")
	metric("pre_emp_dispatch_us_per_item", dispatch_best, "us/item")
	stoplag()
	rustg_time_reset("material_response_observers")
	for(var/datum/component/material_response/response as anything in responses)
		qdel(response)
	var/detach_us = rustg_time_microseconds("material_response_observers") / item_count
	for(var/obj/item/material_response_benchmark_item/item as anything in items)
		if(item.GetComponent(/datum/component/material_response))
			fail("material response remained attached after deletion")
	metric("detach_us_per_item", detach_us, "us/item")
	for(var/obj/item/material_response_benchmark_item/item as anything in items)
		qdel(item)
	mark("after")
