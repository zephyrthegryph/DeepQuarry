/*
** The Parts Lathe! Able to produce all tech level 1 stock parts for building machines!
**
** The idea is that engineering etc should be able to build/repair basic technology machines
** without having to use a protolathe to print what are not prototype technologies.
** Some felt having an autolathe do this might be OP, so its a separate machine.
**
** The other advantage is that this machine, specially focused for helping build stuff,
** actually reads circuit boards, tells you what parts are needed to build them, and
** can automatically queue them up to build!
**
** Leshana says:
** - Phase 1 of this project adds the machine and basic operation.
** - Phase 2 will enhance usability by making & labeling boxes with a set of parts.
**
** TODO - Implement phase 2 by adding cardboard boxes
*/

/obj/machinery/partslathe
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "parts lathe"
	icon = 'icons/obj/partslathe_vr.dmi'
	icon_state = "partslathe-idle"
	circuit = /obj/item/circuitboard/partslathe
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 30
	active_power_usage = 5000

	// Amount of materials we can store total
	var/list/materials = list(MAT_STEEL = 0, MAT_GLASS = 0) // ALLOW(instance_list): d: edited in place per instance (7 writers)
	var/list/storage_capacity = list(MAT_STEEL = 0, MAT_GLASS = 0) // ALLOW(instance_list): d: edited in place per instance (2 writers)

	var/obj/item/circuitboard/copy_board // Inserted board

	// ALLOW(instance_list): d: the build queue; kept index-parallel with queue_producer_accounts
	var/list/datum/category_item/partslathe/queue = list() // Queue of things to build
	/// Producer account parallel to each queued design.
	var/list/queue_producer_accounts = list() // ALLOW(instance_list): d: kept index-parallel with queue (Cut() by index)
	var/busy = 0			// Currently building stuff y/n
	var/progress = 0		// How many machine ticks have we spent building current thing?
	var/mat_efficiency = 3	// Material usage efficiency (less efficient than protolathe)
	var/speed = 1			// Ticks per tick build speed multiplier

	// Static list of recipies we will lazily generate
	// type -> /datum/category_item/partslathe/
	var/static/list/partslathe_recipies

// ALLOW(init/INSTANCE_STATE): takes its built parts and lists what they can make
/obj/machinery/partslathe/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_recipe_list()

/obj/machinery/partslathe/RefreshParts()
	var/mb_rating = get_part_rating(/obj/item/stock_parts/matter_bin)
	storage_capacity[MAT_STEEL] = mb_rating  * 16000
	storage_capacity[MAT_GLASS] = mb_rating  * 8000
	var/T = get_part_rating(/obj/item/stock_parts/manipulator)
	mat_efficiency = 6 / T // Ranges from 3.0 to 1.0
	speed = T / 2 // Ranges from 1.0 to 3.0

/obj/machinery/partslathe/dismantle()
	for(var/f in materials)
		eject_materials(f, -1)
	..()

/obj/machinery/partslathe/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(panel_open)
		drawn_state = look.state("partslathe-open")
	else if(!operable())
		drawn_state = look.state("partslathe-off")
	else if(busy)
		drawn_state = look.state("partslathe-lidclose")
	else
		if(drawn_state == "partslathe-lidclose")
			look.play_flick("partslathe-lidopen")
		drawn_state = look.state("partslathe-idle")

/// Requirement: TRUE, or why an item can't be used on the lathe right now.
/obj/machinery/partslathe/proc/can_load_item(mob/user, atom/target, obj/item/O)
	if(busy) // ALLOW(reads): the legacy check is read when the op is tried, never from a cached menu
		return "it's busy, wait for the previous operation to complete"
	if(istype(O, /obj/item/storage/part_replacer) || !operable())
		return TRUE // part replacement, or swallowed silently
	if(panel_open)
		return "you can't load it while it's opened"
	return TRUE

/// Requirement (was REQ_* can_load_item): the legacy check answers TRUE to pass.
/obj/machinery/partslathe/proc/can_load_item_holds(datum/act/op/A)
	var/answer = can_load_item(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_load_item_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/partslathe/proc/can_load_item_refusal(datum/act/op/A)
	var/answer = can_load_item(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/partslathe/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(default_part_replacement(user, O))
		return TRUE
	if(!operable() || panel_open)
		return TRUE
	if(istype(O, /obj/item/circuitboard))
		if(copy_board)
			to_chat(user, span_warning("There is already a board inserted in \the [src]."))
			return TRUE
		if(!move_into(src, nameof(src.copy_board), O, user))
			return TRUE
		act_message(user, src, MSG_SELF(span_notice("You insert [O] into %T%'s circuit reader.")), MSG_OTHERS("%U% inserts [O] into %T%'s circuit reader."))
		return TRUE
	if(try_load_materials(user, O))
		return TRUE
	to_chat(user, span_notice("You cannot insert this item into \the [src]!"))
	return TRUE

// Attept to load materials.  Returns 0 if item wasn't a stack of materials, otherwise 1 (even if failed to load)
/obj/machinery/partslathe/proc/try_load_materials(mob/user, obj/item/stack/material/S)
	if(!istype(S))
		return 0
	if(!(S.material.name in materials))
		to_chat(user, span_warning("The [src] doesn't accept [material_display_name(S.material)]!"))
		return 1
	if(S.get_amount() < 1)
		return 1 // Does this even happen? Sanity check I guess.
	var/max_res_amount = storage_capacity[S.material.name]
	if(materials[S.material.name] + S.perunit <= max_res_amount)
		var/count = 0
		while(materials[S.material.name] + S.perunit <= max_res_amount && S.get_amount() >= 1)
			materials[S.material.name] += S.perunit
			S.use(1)
			count++
		act_message(user, src, MSG_SELF(span_notice("You insert [count] [S.name] into %T%.")), MSG_OTHERS("%U% inserts [S.name] into %T%."))
		flick("partslathe-load-[S.material.name]", src)
	else
		to_chat(user, span_warning("\The [src] cannot hold more [S.name]."))
	return 1

/obj/machinery/partslathe/proc/work_step(datum/act/timer/A)
	if(has_stat(MACHINE_STAT_ANY))
		return
	if(queue.len == 0)
		if (busy)
			ping() // Job's done!
		busy = 0
		return
	var/datum/category_item/partslathe/D = queue[1]
	if(canBuild(D))
		busy = 1
		set_use_power(USE_POWER_ACTIVE)
		progress += speed
		if(progress >= D.time)
			build(D, queue_producer_accounts[1])
			progress = 0
			removeFromQueue(1)
	else if(busy)
		visible_message(span_notice("[icon2html(src,viewers(src))] flashes: insufficient materials: [getLackingMaterials(D)]."))
		busy = 0
		set_use_power(USE_POWER_IDLE)
		play_sfx(src, SFX_MACHINES_CHIME, vary = FALSE)

/obj/machinery/partslathe/proc/addToQueue(datum/category_item/partslathe/D, producer_account = 0)
	queue += D
	queue_producer_accounts += producer_account
	return

/obj/machinery/partslathe/proc/removeFromQueue(index)
	if(queue.len >= index)
		queue.Cut(index, index + 1)
		queue_producer_accounts.Cut(index, index + 1)
		return

/obj/machinery/partslathe/proc/canBuild(datum/category_item/partslathe/D)
	for(var/M in D.resources)
		if(materials[M] < CEILING((D.resources[M] * mat_efficiency), 1))
			return 0
	return 1

/obj/machinery/partslathe/proc/getLackingMaterials(datum/category_item/partslathe/D)
	var/ret = ""
	for(var/M in D.resources)
		if(materials[M] < CEILING((D.resources[M] * mat_efficiency), 1))
			if(ret != "")
				ret += ", "
			ret += "[CEILING((D.resources[M] * mat_efficiency), 1) - materials[M]] [M]"
	return ret

/obj/machinery/partslathe/proc/build(datum/category_item/partslathe/D, producer_account = 0)
	for(var/M in D.resources)
		materials[M] = max(0, materials[M] - CEILING((D.resources[M] * mat_efficiency), 1))
	var/obj/item/new_item = D.build(loc);
	if(new_item)
		new_item.set_economic_provenance(DEPARTMENT_RESEARCH, 15, producer_account)
		new_item.forceMove(loc)
		if(mat_efficiency < 1) // No matter out of nowhere
			new_item.scale_materials(mat_efficiency)
	return new_item

// 0 amount = 0 means ejecting a full stack; -1 means eject everything
/obj/machinery/partslathe/proc/eject_materials(material, amount)
	var/recursive = amount == -1 ? TRUE : FALSE
	material = lowertext(material)
	var/mattype
	switch(material)
		if(MAT_STEEL)
			mattype = /obj/item/stack/material/steel
		if(MAT_GLASS)
			mattype = /obj/item/stack/material/glass
		else
			return
	var/obj/item/stack/material/S = new mattype(loc)
	if(amount <= 0)
		amount = S.max_amount
	var/ejected = min(round(materials[material] / S.perunit), amount)
	if(!S.set_amount(min(ejected, amount)))
		return
	materials[material] -= ejected * S.perunit
	if(recursive && materials[material] >= S.perunit)
		eject_materials(material, -1)

/obj/machinery/partslathe/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/sheetmaterials)
	)

CAPABILITIES(/obj/machinery/partslathe)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	interface("PartsLathe")
	op("queue", ui_act("queue", arg("queue")), then(PROC_REF(ui_act_queue)))
	op("queueBoard", ui_act("queueBoard"), then(PROC_REF(ui_act_queueboard)))
	op("cancel", ui_act("cancel", arg("cancel", num())), then(PROC_REF(ui_act_cancel)))
	op("ejectBoard", ui_act("ejectBoard"), then(PROC_REF(ui_act_ejectboard)))
	op("remove_mat", ui_act("remove_mat", arg("amount", num()), arg("id", schema_text(4096))), then(PROC_REF(ui_act_remove_mat)))
	extend(TAG_UI, then(PROC_REF(ui_fingerprint), early = TRUE))
	op("attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use item"), needs(req(PROC_REF(can_load_item_holds), because = PROC_REF(can_load_item_refusal))), then(PROC_REF(interaction_attackby)))

/// Whoever presses a button leaves their prints on the lathe.
/obj/machinery/partslathe/proc/ui_fingerprint(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/partslathe/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/list/materials_ui = list()
	for(var/M in materials)
		materials_ui.Add(list(list(
			"name" = M,
			"amount" = materials[M],
			"sheets" = round(materials[M] / SHEET_MATERIAL_AMOUNT),
			"removable" = materials[M] >= SHEET_MATERIAL_AMOUNT,
		)))
	data["materials"] = materials_ui
	data["SHEET_MATERIAL_AMOUNT"] = SHEET_MATERIAL_AMOUNT

	data["copyBoard"] = null
	data["copyBoardReqComponents"] = null
	if(istype(copy_board))
		data["copyBoard"] = copy_board.name
		var/list/req_components_ui = list()
		for(var/obj/comp_path as anything in (copy_board.req_components || list()))
			var/comp_amt = copy_board.req_components[comp_path]
			if(comp_amt && (comp_path in partslathe_recipies))
				req_components_ui.Add(list(list("name" = initial(comp_path.name), "qty" = comp_amt)))
		data["copyBoardReqComponents"] = req_components_ui

	data["queue"] = list()
	for(var/datum/category_item/partslathe/Q in queue)
		data["queue"] += Q.name

	data["building"] = null
	data["buildPercent"] = null
	if(busy && queue.len > 0)
		var/datum/category_item/partslathe/current = queue[1]
		data["building"] = current.name
		data["buildPercent"] = (progress / current.time * 100)

	data["error"] = null
	if(queue.len > 0 && !canBuild(queue[1]))
		data["error"] = getLackingMaterials(queue[1])

	var/list/recipies_ui = list()
	for(var/T in partslathe_recipies)
		var/datum/category_item/partslathe/R = partslathe_recipies[T]
		recipies_ui.Add(list(list("name" = R.name, "type" = "[T]")))
	data["recipies"] = recipies_ui

	data["panelOpen"] = panel_open
	return data


/obj/machinery/partslathe/proc/ui_act_queue(datum/act/op/A, queue)
	var/mob/user = A.actor
	var/obj/item/card/id/producer_id = user.GetIdCard()
	var/producer_account = producer_id?.associated_account_number || 0
	var/type_to_build = text2path(queue)
	var/datum/category_item/partslathe/to_build = ispath(type_to_build, /datum) ? partslathe_recipies[type_to_build] : null
	if(to_build)
		addToQueue(to_build, producer_account)
	return TRUE

/obj/machinery/partslathe/proc/ui_act_queueboard(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/producer_id = user.GetIdCard()
	var/producer_account = producer_id?.associated_account_number || 0
	if(!istype(copy_board) || !copy_board.req_components)
		return
	for(var/comp_path in copy_board.req_components)
		var/comp_amt = copy_board.req_components[comp_path]
		if(!comp_amt)
			continue
		var/datum/category_item/partslathe/to_build = partslathe_recipies[comp_path]
		if(!to_build)
			continue // We don't support building whatever this is
		for(var/i in 1 to comp_amt)
			addToQueue(to_build, producer_account)
	return TRUE

/obj/machinery/partslathe/proc/ui_act_cancel(datum/act/op/A, cancel)
	var/index = cancel
	if(index < 1 || index > queue.len)
		return
	if(busy && index == 1)
		return
	removeFromQueue(index)
	return TRUE

/obj/machinery/partslathe/proc/ui_act_ejectboard(datum/act/op/A)
	var/mob/user = A.actor
	if(busy)
		to_chat(user, span_notice("[src] is busy. Please wait for completion of previous operation."))
		return
	if(copy_board)
		visible_message(span_notice("[copy_board] is ejected from [src]'s circuit reader."))
		copy_board.forceMove(src.loc)
		rel_take(src, nameof(/obj/machinery/partslathe::copy_board))
	return TRUE

/obj/machinery/partslathe/proc/ui_act_remove_mat(datum/act/op/A, raw_amount, id)
	var/mob/user = A.actor
	if(busy)
		to_chat(user, span_notice("[src] is busy. Please wait for completion of previous operation."))
		return
	// Remove a material from the fab
	var/mat_id = id
	var/amount = raw_amount
	eject_materials(mat_id, amount)
	return

/** Build list of recipies to include all tech level 1 stock parts. */
/obj/machinery/partslathe/proc/update_recipe_list()
	if(!partslathe_recipies)
		partslathe_recipies = list()
		var/list/paths = subtypesof(/obj/item/stock_parts) - typesof(/obj/item/stock_parts/subspace)
		for(var/type in paths)
			var/obj/item/stock_parts/I = new type()
			var/list/part_matter = I.material_totals()
			if(!length(part_matter) || I.rating > 1)
				spent(I)
				continue // Ignore parts we can't build

			var/datum/category_item/partslathe/recipie = new()
			recipie.name = I.name
			recipie.path = type
			recipie.resources = list()
			for(var/material in part_matter)
				recipie.resources[material] = part_matter[material]*1.25 // More expensive to produce than they are to recycle.
			partslathe_recipies[type] = recipie
			spent(I)

/***************************
* Parts Lathe Recipie Type *
***************************/

/datum/category_item/partslathe
	var/path
	var/list/resources
	var/time = 2 // In machine controller ticks, so about 4 seconds.

/datum/category_item/partslathe/dd_SortValue()
	return name

/datum/category_item/partslathe/proc/build(loc)
	return new path(loc)


/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/partslathe/step_start_condition()
	return busy

/obj/machinery/partslathe/ownership()
	. = ..()
	. += owns(nameof(copy_board), policy = OWN_CONTAINED)

