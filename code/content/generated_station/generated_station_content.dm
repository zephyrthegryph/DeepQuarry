/datum/generated_station_materializer/proc/department_id_for_module(datum/generated_station_module/module)
	if(!module)
		return null
	var/datum/generated_station_layout_node/node = node_by_id(module.department_node_id)
	if(!node)
		return null
	var/datum/generated_station_department_instance/department = department_for_node(node)
	return department?.definition()?.id
