/// Runtime state for one department instance. Stockpiles are finite quantities
/// consumed transactionally by concrete work such as healing and repairs.
/datum/generated_station_department_runtime
	var/datum/generated_station_department_instance/department
	var/state = GENERATED_DEPARTMENT_OFFLINE
	var/integrity = 100
	var/list/stockpiles
	var/list/minimum_stockpiles

/datum/generated_station_department_runtime/New(datum/generated_station_department_instance/new_department)
	..()
	department = new_department
	stockpiles = list()
	minimum_stockpiles = list()

/datum/generated_station_department_runtime/Destroy()
	department = null
	stockpiles = null
	minimum_stockpiles = null
	return ..()

/datum/generated_station_department_runtime/proc/has_resources()
	for(var/resource_id in minimum_stockpiles)
		if((stockpiles[resource_id] || 0) < minimum_stockpiles[resource_id])
			return FALSE
	return TRUE

GLOBAL_LIST_EMPTY(generated_station_runtimes)

/proc/generated_station_runtime(station_id)
	return GLOB.generated_station_runtimes[station_id]

/// Authoritative dependency simulation for one generated station.
/datum/generated_station_simulation
	var/datum/generated_station_spec/spec
	var/list/departments
	var/list/capabilities
	var/list/power_areas
	var/dirty = TRUE
	var/revision = 0

/datum/generated_station_simulation/New(datum/generated_station_spec/new_spec)
	..()
	spec = new_spec
	departments = list()
	capabilities = list()
	power_areas = list()
	for(var/datum/generated_station_department_instance/department in spec?.departments)
		departments[department.id] = new /datum/generated_station_department_runtime(department)
	configure_default_resources()
	if(spec?.id)
		GLOB.generated_station_runtimes[spec.id] = src

/datum/generated_station_simulation/Destroy()
	if(spec?.id && GLOB.generated_station_runtimes[spec.id] == src)
		GLOB.generated_station_runtimes -= spec.id
	spec = null
	for(var/id in departments)
		qdel(departments[id])
	departments = null
	capabilities = null
	power_areas = null
	return ..()

/datum/generated_station_simulation/proc/configure_default_resources()
	for(var/id in departments)
		var/datum/generated_station_department_runtime/runtime = departments[id]
		switch(runtime.department.definition.id)
			if("engineering")
				runtime.stockpiles["fuel"] = 100
				runtime.minimum_stockpiles["fuel"] = 1
			if("logistics")
				runtime.stockpiles["supplies"] = 100
				runtime.minimum_stockpiles["supplies"] = 1
			if("medical")
				runtime.stockpiles["medicine"] = 50
				runtime.minimum_stockpiles["medicine"] = 1

/datum/generated_station_simulation/proc/invalidate()
	dirty = TRUE
	revision++
	recompute()
	for(var/area/generated_station/A in power_areas)
		if(!QDELETED(A))
			A.power_change()

/datum/generated_station_simulation/proc/register_power_area(area/generated_station/A)
	if(!A)
		return
	power_areas |= A
	A.power_change()

/datum/generated_station_simulation/proc/set_integrity(department_id, value)
	var/datum/generated_station_department_runtime/runtime = departments[department_id]
	if(!runtime)
		return FALSE
	runtime.integrity = clamp(value, 0, 100)
	invalidate()
	return TRUE

/datum/generated_station_simulation/proc/set_stockpile(department_id, resource_id, amount)
	var/datum/generated_station_department_runtime/runtime = departments[department_id]
	if(!runtime || !resource_id)
		return FALSE
	runtime.stockpiles[resource_id] = max(0, amount)
	invalidate()
	return TRUE

/datum/generated_station_simulation/proc/add_stockpile(department_id, resource_id, amount)
	var/datum/generated_station_department_runtime/runtime = departments[department_id]
	if(!runtime || !resource_id)
		return FALSE
	return set_stockpile(department_id, resource_id, (runtime.stockpiles[resource_id] || 0) + amount)

/datum/generated_station_simulation/proc/consume_stockpile(department_id, resource_id, amount)
	var/datum/generated_station_department_runtime/runtime = departments[department_id]
	if(!runtime || amount < 0 || (runtime.stockpiles[resource_id] || 0) < amount)
		return FALSE
	runtime.stockpiles[resource_id] -= amount
	invalidate()
	return TRUE

/datum/generated_station_simulation/proc/recompute()
	if(!dirty)
		return
	var/list/candidates = list()
	for(var/id in departments)
		var/datum/generated_station_department_runtime/runtime = departments[id]
		if(runtime.integrity > 0 && runtime.has_resources())
			candidates[id] = TRUE
	var/changed = TRUE
	while(changed)
		changed = FALSE
		var/list/available = aggregate_capabilities(candidates)
		for(var/id in candidates.Copy())
			var/datum/generated_station_department_runtime/runtime = departments[id]
			for(var/datum/generated_station_capability_requirement/requirement in runtime.department.definition.requirements)
				if(requirement.optional)
					continue
				if((available[requirement.capability_id] || 0) < requirement.amount)
					candidates -= id
					changed = TRUE
					break
	capabilities = aggregate_capabilities(candidates)
	for(var/id in departments)
		var/datum/generated_station_department_runtime/runtime = departments[id]
		if(!candidates[id])
			runtime.state = GENERATED_DEPARTMENT_OFFLINE
		else if(runtime.integrity < 50)
			runtime.state = GENERATED_DEPARTMENT_DEGRADED
		else
			runtime.state = GENERATED_DEPARTMENT_OPERATIONAL
	dirty = FALSE

/datum/generated_station_simulation/proc/aggregate_capabilities(list/candidates)
	var/list/available = list()
	for(var/id in candidates)
		var/datum/generated_station_department_runtime/runtime = departments[id]
		var/output_scale = runtime.integrity < 50 ? 0.5 : 1
		for(var/datum/generated_station_capability_provision/provision in runtime.department.definition.provisions)
			available[provision.capability_id] = (available[provision.capability_id] || 0) + provision.amount * output_scale
	return available

/datum/generated_station_simulation/proc/department_state(department_id)
	recompute()
	var/datum/generated_station_department_runtime/runtime = departments[department_id]
	return runtime?.state || GENERATED_DEPARTMENT_OFFLINE

/datum/generated_station_simulation/proc/capability_available(capability_id, amount = 1)
	var/datum/generated_station_utility_topology/utilities = generated_station_utility_topology(spec?.id)
	if(capability_id == "power")
		return amount <= 1 && utilities?.power_available()
	if(capability_id == "atmosphere")
		return amount <= 1 && utilities?.atmosphere_available()
	recompute()
	return (capabilities[capability_id] || 0) >= amount
