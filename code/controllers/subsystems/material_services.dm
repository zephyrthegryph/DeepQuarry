/// Coalesced, resumable exposure work. A station can contain tens of thousands
/// of assemblies; they must not each put an unbudgeted callback on SStimer.
SUBSYSTEM_DEF(material_services)
	name = "Material exposure"
	flags = SS_KEEP_TIMING | SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	priority = FIRE_PRIORITY_OBJ
	wait = 1 SECOND
	/// Min-heap keyed by each service's next meaningful update. Future work is
	/// never linearly rescanned on every subsystem fire.
	var/list/scheduled = list()
	var/list/scheduled_due = list()
	var/list/scheduled_indices = list()
	var/list/currentrun

/datum/controller/subsystem/material_services/proc/swap_scheduled(a, b)
	var/datum/material_service/service = scheduled[a]
	var/due = scheduled_due[a]
	scheduled[a] = scheduled[b]
	scheduled_due[a] = scheduled_due[b]
	scheduled[b] = service
	scheduled_due[b] = due
	scheduled_indices[REF(scheduled[a])] = a
	scheduled_indices[REF(scheduled[b])] = b

/datum/controller/subsystem/material_services/proc/queue(datum/material_service/service, due)
	var/key = REF(service)
	var/index = scheduled_indices[key]
	if(index)
		if(scheduled_due[index] <= due)
			return
		scheduled_due[index] = due
	else
		scheduled += service
		scheduled_due += due
		index = length(scheduled)
		scheduled_indices[key] = index
	while(index > 1)
		var/parent = index >> 1
		if(scheduled_due[parent] <= scheduled_due[index])
			break
		swap_scheduled(parent, index)
		index = parent

/datum/controller/subsystem/material_services/proc/unqueue(datum/material_service/service)
	var/index = scheduled_indices[REF(service)]
	if(!index)
		return FALSE
	var/last = length(scheduled)
	scheduled_indices.Remove(REF(service))
	if(index == last)
		scheduled.Cut(last, last + 1)
		scheduled_due.Cut(last, last + 1)
		return TRUE
	scheduled[index] = scheduled[last]
	scheduled_due[index] = scheduled_due[last]
	scheduled_indices[REF(scheduled[index])] = index
	scheduled.Cut(last, last + 1)
	scheduled_due.Cut(last, last + 1)
	while(index > 1)
		var/parent = index >> 1
		if(scheduled_due[parent] <= scheduled_due[index])
			break
		swap_scheduled(parent, index)
		index = parent
	while(TRUE)
		var/left = index * 2
		if(left > length(scheduled))
			break
		var/right = left + 1
		var/smallest = right <= length(scheduled) && scheduled_due[right] < scheduled_due[left] ? right : left
		if(scheduled_due[index] <= scheduled_due[smallest])
			break
		swap_scheduled(index, smallest)
		index = smallest
	return TRUE

/datum/controller/subsystem/material_services/proc/pop_due()
	if(!length(scheduled) || scheduled_due[1] > world.time)
		return
	var/datum/material_service/service = scheduled[1]
	unqueue(service)
	return service

/datum/controller/subsystem/material_services/fire(resumed)
	if(!resumed)
		currentrun = list()
		var/datum/material_service/due_service = pop_due()
		while(due_service)
			currentrun += due_service
			due_service = pop_due()
	while(length(currentrun))
		var/datum/material_service/service = currentrun[length(currentrun)]
		currentrun.len--
		if(QDELETED(service))
			continue
		service.timer = FALSE
		service.advance()
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/material_services/stat_entry(msg)
	msg += " P:[length(scheduled)]"
	return ..()
