/obj/machinery/ore_silo
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "ore silo"
	desc = "An all-in-one bluespace storage and transmission system for the station's mineral distribution needs."
	icon = 'icons/obj/machines/ore_silo.dmi'
	icon_state = "silo"
	density = TRUE
	circuit = /obj/item/circuitboard/machine/ore_silo

	/// Connections on hold from accessing materials (relation list, written by /datum/remote_materials).
	var/list/holds
	/// Connections sharing ores with this silo (relation list, written by /datum/remote_materials).
	var/list/datum/remote_materials/ore_connected_machines
	/// Material Container
	var/datum/material_container/materials

CAPABILITIES(/obj/machinery/ore_silo)
	ref_many(nameof(holds))
	ref_many(nameof(ore_connected_machines))
	owns_one(nameof(materials), /datum/material_container)
	interface("OreSilo")
	op("remove", ui_act("remove", arg("id", num())), then(PROC_REF(ui_act_remove)))
	op("hold", ui_act("hold", arg("id", num())), then(PROC_REF(ui_act_hold)))
	op("remove_mat", ui_act("remove_mat", arg("amount", num()), arg("id", schema_text(4096))), then(PROC_REF(ui_act_remove_mat)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(crowbar_used)))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(multitool_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(screwdriver_used)))

/obj/machinery/ore_silo/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(materials), new /datum/material_container( \
		src, \
		subtypesof(/datum/material), \
		INFINITY, \
		MATCONTAINER_EXAMINE, \
		container_events = list( \
			(/datum/notice/matcontainer_item_consumed) = TYPE_PROC_REF(/obj/machinery/ore_silo, on_item_consumed), \
			(/datum/notice/matcontainer_stack_retrieved) = TYPE_PROC_REF(/obj/machinery/ore_silo, log_sheets_ejected), \
		), \
		allowed_items = /obj/item/stack \
	))
	if(!GLOB.ore_silo_default && mapload && (z in using_map.station_levels))
		GLOB.ore_silo_default = src

// the default silo clears.
/obj/machinery/ore_silo/lifecycle_dematerialize()
	..()
	if(GLOB.ore_silo_default == src)
		GLOB.ore_silo_default = null

// connected machines disconnect.
/obj/machinery/ore_silo/on_destroy(force)
	for(var/datum/remote_materials/mats as anything in ore_connected_machines)
		mats.disconnect()
	..()

/obj/machinery/ore_silo/examine(mob/user)
	. = ..()
	. += span_notice("It can be linked to techfabs, circuit printers and protolathes with a multitool.")
	. += span_notice("Its maintainence panel can be [span_bold("screwed")] [panel_open ? "closed" : "open"].")
	if(panel_open)
		. += span_notice("The whole machine can be [span_bold("pried")] apart.")

/obj/machinery/ore_silo/proc/on_item_consumed(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/matcontainer_item_consumed/event = N
	var/obj/item/item_inserted = event.item
	var/mats_consumed = event.mats_consumed
	var/amount_inserted = event.material_amount
	var/atom/context = event.context

	silo_log(context, "deposited", amount_inserted, item_inserted.name, mats_consumed)

/obj/machinery/ore_silo/proc/log_sheets_ejected(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/matcontainer_stack_retrieved/event = N
	var/obj/item/stack/material/sheets = event.new_stack
	var/atom/context = event.context

	silo_log(context, "ejected", -sheets.amount, "[sheets.singular_name]", list(GET_MATERIAL_REF(sheets.default_type) = sheets.amount * SHEET_MATERIAL_AMOUNT))

/obj/machinery/ore_silo/proc/screwdriver_used(datum/act/op/A)
	return OP_DECLINE

/obj/machinery/ore_silo/proc/crowbar_used(datum/act/op/A)
	return OP_DECLINE

/obj/machinery/ore_silo/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/obj/item/multitool/multitool = tool
	rel_set(multitool, nameof(multitool.buffer), src)
	balloon_alert(user, "saved to multitool buffer")
	return OP_OK

/obj/machinery/ore_silo/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/sheetmaterials)
	)

/obj/machinery/ore_silo/tgui_static_data(mob/user)
	return materials.tgui_static_data(user)

/// /obj/machinery/ore_silo's window data.
/obj/machinery/ore_silo/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	data["materials"] = materials.material_list_data(user)

	data["machines"] = list()
	for(var/datum/remote_materials/remote as anything in ore_connected_machines)
		var/atom/parent = remote.owner
		data["machines"] += list(
			list(
				"icon" = icon2base64(icon(initial(parent.icon), initial(parent.icon_state), frame = 1)),
				"name" = parent.name,
				"onHold" = (remote in holds),
				"location" = get_area_name(parent, TRUE),
			)
		)

	data["logs"] = list()
	for(var/datum/ore_silo_log/entry as anything in GLOB.silo_access_logs[REF(src)])
		data["logs"] += list(
			list(
				"rawMaterials" = entry.get_raw_materials(""),
				"machineName" = entry.machine_name,
				"areaName" = entry.area_name,
				"action" = entry.action,
				"amount" = entry.amount,
				"time" = entry.timestamp,
				"noun" = entry.noun,
			)
		)

	return data

/obj/machinery/ore_silo/proc/ui_act_remove(datum/act/op/A, id)
	var/index = id
	if(isnull(index))
		return

	var/datum/remote_materials/remote = LAZYACCESS(ore_connected_machines, index)
	if(isnull(remote))
		return

	remote.disconnect()
	return TRUE

/obj/machinery/ore_silo/proc/ui_act_hold(datum/act/op/A, id)
	var/index = id
	if(isnull(index))
		return

	var/datum/remote_materials/remote = LAZYACCESS(ore_connected_machines, index)
	if(isnull(remote))
		return

	remote.toggle_holding()
	return TRUE

/obj/machinery/ore_silo/proc/ui_act_remove_mat(datum/act/op/A, amount_arg, id)
	var/datum/material/ejecting = GET_MATERIAL_REF(id)
	if(!istype(ejecting))
		return

	var/amount = amount_arg
	if(isnull(amount))
		return

	materials.retrieve_sheets(amount, ejecting, drop_location())
	return TRUE

/**
 * Creates a log entry for depositing/withdrawing from the silo both ingame and in text based log
 *
 * Arguments:
 * - [M][/obj/machinery]: The machine performing the action.
 * - action: Text that visually describes the action (smelted/deposited/resupplied...)
 * - amount: The amount of sheets/objects deposited/withdrawn by this action. Positive for depositing, negative for withdrawing.
 * - noun: Name of the object the action was performed with (sheet, units, ore...)
 * - [mats][list]: Assoc list in format (material datum = amount of raw materials). Wants the actual amount of raw (iron, glass...) materials involved in this action. If you have 10 metal sheets each worth 100 iron you would pass a list with the iron material datum = 1000
 */
/obj/machinery/ore_silo/proc/silo_log(obj/machinery/M, action, amount, noun, list/mats)
	if (!length(mats))
		return

	var/datum/ore_silo_log/entry = new(M, action, amount, noun, mats)
	var/list/datum/ore_silo_log/logs = GLOB.silo_access_logs[REF(src)]
	if(!LAZYLEN(logs))
		GLOB.silo_access_logs[REF(src)] = logs = list(entry)
	else if(!logs[1].merge(entry))
		logs.Insert(1, entry)

	flick("silo_active", src)

///The log entry for an ore silo action
/datum/ore_silo_log
	///The time of action
	var/timestamp
	///The name of the machine that remotely acted on the ore silo
	var/machine_name
	///The area of the machine that remotely acted on the ore silo
	var/area_name
	///The actual action performed by the machine
	var/action
	///An short verb describing the action
	var/noun
	///The amount of items affected by this action e.g. print quantity, sheets ejected etc.
	var/amount
	///List of individual materials used in the action
	var/list/materials

/datum/ore_silo_log/New(obj/machinery/M, _action, _amount, _noun, list/mats=list())
	timestamp = stationtime2text()
	machine_name = M.name
	area_name = get_area_name(M, TRUE)
	action = _action
	amount = _amount
	noun = _noun
	materials = mats.Copy()
	// var/list/data = list(
	// 	"machine_name" = machine_name,
	// 	"area_name" = AREACOORD(M),
	// 	"action" = action,
	// 	"amount" = abs(amount),
	// 	"noun" = noun,
	// 	"raw_materials" = get_raw_materials(""),
	// 	"direction" = amount < 0 ? "withdrawn" : "deposited",
	// )
	// logger.Log(
	// 	LOG_CATEGORY_SILO,
	// 	"[machine_name] in \[[AREACOORD(M)]\] [action] [abs(amount)]x [noun] | [get_raw_materials("")]",
	// 	data,
	// )

/**
 * Merges a silo log entry with this one
 * Arguments
 *
 * * datum/ore_silo_log/other - the other silo entry we are trying to merge with this one
 */
/datum/ore_silo_log/proc/merge(datum/ore_silo_log/other)
	if (other == src || action != other.action || noun != other.noun)
		return FALSE
	if (machine_name != other.machine_name || area_name != other.area_name)
		return FALSE

	timestamp = other.timestamp
	amount += other.amount
	for(var/each in other.materials)
		materials[each] += other.materials[each]
	return TRUE

/**
 * Returns list/materials but with each entry joined by an seperator to create 1 string
 * Arguments
 *
 * * separator - the string used to concatenate all entries in list/materials
 */
/datum/ore_silo_log/proc/get_raw_materials(separator)
	var/list/msg = list()
	for(var/key in materials)
		var/datum/material/M = key
		var/val = round(materials[key])
		msg += separator
		separator = ", "
		msg += "[amount < 0 ? "-" : "+"][val] [M.name]"
	return msg.Join()
