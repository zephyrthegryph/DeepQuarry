#define RND_TECH_DISK	"tech"
#define RND_DESIGN_DISK	"design"

/*
Research and Development (R&D) Console

This is the main work horse of the R&D system. It contains the menus/controls for the Destructive Analyzer, Protolathe, and Circuit
imprinter.

Basic use: When it first is created, it will attempt to link up to related devices within 3 squares. It'll only link up if they
aren't already linked to another console. Any consoles it cannot link up with (either because all of a certain type are already
linked or there aren't any in range), you'll just not have access to that menu. In the settings menu, there are menu options that
allow a player to attempt to re-sync with nearby consoles. You can also force it to disconnect from a specific console.

The only thing that requires ordnance access is locking and unlocking the console on the settings menu.
Nothing else in the console has ID requirements.

*/
/obj/machinery/computer/rdconsole_tg
	name = "R&D Console"
	desc = "A console used to interface with R&D tools."
	icon_screen = "rdcomp"
	icon_keyboard = "rd_key"
	circuit = VARIANT(/obj/item/circuitboard/rdconsole)
	req_access = list(ACCESS_RESEARCH) // Locking and unlocking the console requires research access
	/// Reference to global science techweb (a registered, shared web)
	var/datum/techweb/stored_research
	/// The stored technology disk, if present
	var/obj/item/disk/tech_disk/t_disk
	/// The stored design disk, if present
	var/obj/item/disk/design_disk/d_disk
	/// Determines if the console is locked, and consequently if actions can be performed with it
	locked = FALSE
	/// Cooldown that prevents hanging the MC when tech disks are copied
	STATIC_COOLDOWN_DECLARE(cooldowncopy)

/obj/machinery/computer/rdconsole_tg/proc/connect_initial_console()
	if(!stored_research)
		CONNECT_TO_RND_SERVER_ROUNDSTART(stored_research, src)
	if(stored_research)
		rel_add(stored_research, nameof(stored_research.consoles_accessing), src)

MSG_DEF_SELF(rdconsole/locked, "Console is locked, cannot perform further actions.")

CAPABILITIES(/obj/machinery/computer/rdconsole_tg)
	setup(PROC_REF(connect_initial_console))
	owns_one(nameof(t_disk), on_destroy = ON_DESTROY_SPILL)
	owns_one(nameof(d_disk), on_destroy = ON_DESTROY_SPILL)
	interface("Techweb")
	ui_shape(stored_research = bool(), locked = bool(), nodes = list_of(row(id = schema_text(), is_free = bool(), can_unlock = bool(), have_experiments_done = bool(), tier = num(), enqueued_by_user = bool())), queue_nodes = map_of(schema_text(), schema_text()), experiments = map_of(schema_text(), row(name = schema_text(), description = schema_text(), tag = schema_text(), progress = list_of(list_of(any)), completed = bool(), performance_hint = nullable(schema_text()))), researched_designs = map_of(schema_text(), num()), points = map_of(schema_text(), num()), points_last_tick = map_of(schema_text(), num()), sec_protocols = bool(), t_disk = nullable(row(stored_research = map_of(schema_text(), num()))), d_disk = nullable(row(blueprints = list_of(schema_text()))), static_data = row(node_cache = map_of(schema_text(), row()), design_cache = map_of(schema_text(), list_of(schema_text())), id_cache = list_of(schema_text())), point_types_abbreviations = map_of(schema_text(), schema_text()))
	without("ui_open")
	extend(TAG_UI, then(PROC_REF(controls_touched), early = TRUE))
	op("toggleLock", ui_act("toggleLock"), then(PROC_REF(ui_act_togglelock)))
	op("researchNode", ui_act("researchNode", arg("node_id", schema_text(4096))), needs(req(PROC_REF(unlocked_refusal))), then(PROC_REF(ui_act_researchnode)))
	op("enqueueNode", ui_act("enqueueNode", arg("node_id", schema_text(4096))), needs(req(PROC_REF(unlocked_refusal))), then(PROC_REF(ui_act_enqueuenode)))
	op("dequeueNode", ui_act("dequeueNode", arg("node_id", schema_text(4096))), needs(req(PROC_REF(unlocked_refusal))), then(PROC_REF(ui_act_dequeuenode)))
	op("ejectDisk", ui_act("ejectDisk", arg("type", schema_text(4096))), needs(req(PROC_REF(unlocked_refusal))), then(PROC_REF(ui_act_ejectdisk)))
	op("uploadDisk", ui_act("uploadDisk", arg("type", schema_text(4096))), needs(req(PROC_REF(unlocked_refusal))), then(PROC_REF(ui_act_uploaddisk)))
	op("loadTech", ui_act("loadTech"), needs(req(PROC_REF(unlocked_refusal))), then(PROC_REF(ui_act_loadtech)))
	op("insert_disk", item(/obj/item/disk), priority(OP_PRIORITY_DEFAULT - 1), label("Insert disk"), then(PROC_REF(interaction_insert_disk)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/computer/rdconsole_tg/proc/interaction_insert_disk(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/D = A.held
	if(istype(D, /obj/item/disk/tech_disk))
		if(t_disk)
			to_chat(user, span_warning("A technology disk is already loaded!"))
			return TRUE
		if(!move_into(src, nameof(src.t_disk), D, user)) // the user is told why
			return TRUE
	else if (istype(D, /obj/item/disk/design_disk))
		if(d_disk)
			to_chat(user, span_warning("A design disk is already loaded!"))
			return TRUE
		if(!move_into(src, nameof(src.d_disk), D, user)) // the user is told why
			return TRUE
	else
		to_chat(user, span_warning("Machine cannot accept disks in that format."))
		return TRUE
	to_chat(user, span_notice("You insert [D] into \the [src]!"))
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/enqueue_node(id, mob/user)
	if(!stored_research || !LAZYACCESS(stored_research.available_nodes, id) || LAZYACCESS(stored_research.researched_nodes, id))
		atom_say("Node enqueue failed: Either no techweb is found, node is already researched or is not available!")
		return FALSE
	stored_research.enqueue_node(id, user)
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/dequeue_node(id, mob/user)
	if(!stored_research || !LAZYACCESS(stored_research.available_nodes, id) || LAZYACCESS(stored_research.researched_nodes, id))
		atom_say("Node dequeue failed: Either no techweb is found, node is already researched or is not available!")
		return FALSE
	stored_research.dequeue_node(id, user)
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/research_node(id, mob/user)
	if(!stored_research || !LAZYACCESS(stored_research.available_nodes, id) || LAZYACCESS(stored_research.researched_nodes, id))
		atom_say("Node unlock failed: Either no techweb is found, node is already researched or is not available!")
		return FALSE
	var/datum/techweb_node/TN = SSresearch.techweb_node_by_id(id)
	if(!istype(TN))
		atom_say("Node unlock failed: Unknown error.")
		return FALSE
	var/list/price = TN.get_price(stored_research)
	if(stored_research.can_afford(price))
		user.investigate_log("researched [id]([json_encode(price)]) on techweb id [stored_research.id].", INVESTIGATE_RESEARCH)
		if(stored_research.research_node_id(id, research_source = src))
			atom_say("Successfully researched [TN.display_name].")
			if(SScontracts)
				var/mob/living/researcher = user
				emit_contract_event(CONTRACT_EVENT_RESEARCH_MILESTONE, list(
					"department" = DEPARTMENT_RESEARCH,
					"node_id" = TN.id,
					"node_name" = TN.display_name,
					"point_cost" = price[TECHWEB_POINT_TYPE_GENERIC] || 0,
					"design_count" = length(TN.design_ids),
					"detail" = "Unlocked the [TN.display_name] research node.",
				), "research-node:[REF(stored_research)]:[TN.id]", src, researcher)
			var/logname = user?.research_audit_identity() || "Unknown"
			if(iscarbon(user))
				var/obj/item/card/id/idcard = user.get_active_hand()
				if(istype(idcard))
					logname = "[idcard.registered_name]"
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				var/obj/item/I = H.get_equipped_item(SLOT_ID_ID)
				if(istype(I))
					var/obj/item/card/id/ID = I.GetID()
					if(istype(ID))
						logname = "[ID.registered_name]"
			LAZYINITLIST(stored_research.research_logs); stored_research.research_logs += list(list(
				"node_name" = TN.display_name,
				"node_cost" = price[TECHWEB_POINT_TYPE_GENERIC],
				"node_researcher" = logname,
				"node_research_location" = "[get_area(src)] ([src.x],[src.y],[src.z])",
			))
			return TRUE
		else
			atom_say("Failed to research node: Internal database error!")
			return FALSE
	atom_say("Not enough research points...")
	return FALSE

/obj/machinery/computer/rdconsole_tg/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return TRUE

	tgui_interact(user)
	return TRUE

/obj/machinery/computer/rdconsole_tg/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/research_designs),
	)

/// /obj/machinery/computer/rdconsole_tg's window data.
/obj/machinery/computer/rdconsole_tg/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list(
		"stored_research" = !!stored_research,
		"locked" = locked ? TRUE : FALSE,
		"nodes" = list(),
		"queue_nodes" = list(),
		"experiments" = list(),
		"researched_designs" = list(),
		"points" = list(),
		"points_last_tick" = list(),
		"sec_protocols" = FALSE, // !(obj_flags & EMAGGED),
		"t_disk" = null,
		"d_disk" = null,
	)
	if(!stored_research) //lack of a research node is all we care about.
		return data
	data["queue_nodes"] = stored_research.queue_node_names()
	data["researched_designs"] = stored_research.researched_designs || list()
	data["points"] = stored_research.research_points || list()
	data["points_last_tick"] = stored_research.last_bitcoins || list()

	if(t_disk)
		data["t_disk"] = list (
			"stored_research" = (t_disk.stored_research().researched_nodes || list()),
		)
	if(d_disk)
		data["d_disk"] = list("blueprints" = list())
		for (var/datum/design_techweb/D in d_disk.blueprints)
			data["d_disk"]["blueprints"] += D.id

	// Serialize all nodes to display
	for(var/v in stored_research.tiers)
		var/datum/techweb_node/n = SSresearch.techweb_node_by_id(v)
		var/enqueued_by_user = FALSE

		if((v in stored_research.research_queue_nodes) && LAZYACCESS(stored_research.research_queue_nodes, v) == handle_of(user))
			enqueued_by_user = TRUE

		// Ensure node is supposed to be visible
		if (LAZYACCESS(stored_research.hidden_nodes, v))
			continue

		data["nodes"] += list(list(
			"id" = n.id,
			"is_free" = n.is_free(stored_research) ? TRUE : FALSE,
			"can_unlock" = stored_research.can_unlock_node(n) ? TRUE : FALSE,
			"have_experiments_done" = stored_research.have_experiments_for_node(n) ? TRUE : FALSE,
			"tier" = LAZYACCESS(stored_research.tiers, n.id),
			"enqueued_by_user" = enqueued_by_user
		))

	// Get experiments and serialize them
	var/list/exp_to_process = LAZYCOPY(stored_research.available_experiments)
	for (var/e in stored_research.completed_experiments)
		exp_to_process += LAZYACCESS(stored_research.completed_experiments, e)
	for (var/e in exp_to_process)
		var/datum/experiment/ex = e
		data["experiments"][ex.type] = list(
			"name" = ex.name,
			"description" = ex.description,
			"tag" = ex.exp_tag,
			"progress" = ex.check_progress(),
			"completed" = ex.completed ? TRUE : FALSE,
			"performance_hint" = ex.performance_hint,
		)
	return data

/**
 * Compresses an ID to an integer representation using the payload's id cache, used for deduplication
 * in sent JSON payloads. The cache is built per payload (ui_static_data() sends it beside the data), so an output never writes the console.
 *
 * Arguments:
 * * id - the ID to compress
 * * id_cache - the payload's id -> compressed id list
 */
/obj/machinery/computer/rdconsole_tg/proc/compress_id(id, list/id_cache)
	if(!id_cache[id])
		id_cache[id] = length(id_cache) + 1
	return id_cache[id]

/obj/machinery/computer/rdconsole_tg/ui_static_data(datum/act/eval/A)
	var/mob/user = A.actor
	. = list(
		"static_data" = list(),
		"point_types_abbreviations" = SSresearch.point_types,
	)

	// Build node cache...
	// Note this looks a bit ugly but its to reduce the size of the JSON payload
	// by the greatest amount that we can, as larger JSON payloads result in
	// hanging when the user opens the UI
	var/list/id_cache = list()
	var/node_cache = list()
	for (var/node_id in SSresearch.techweb_nodes)
		var/datum/techweb_node/node = SSresearch.techweb_nodes[node_id] || SSresearch.error_node
		var/compressed_id = "[compress_id(node.id, id_cache)]"
		node_cache[compressed_id] = list(
			"name" = node.display_name,
			"description" = node.description
		)
		if (LAZYLEN(node.research_costs))
			node_cache[compressed_id]["costs"] = list()
			for (var/node_cost in node.research_costs)
				node_cache[compressed_id]["costs"]["[compress_id(node_cost, id_cache)]"] = LAZYACCESS(node.research_costs, node_cost)
		if (LAZYLEN(node.prereq_ids))
			node_cache[compressed_id]["prereq_ids"] = list()
			for (var/prerequisite_node in node.prereq_ids)
				node_cache[compressed_id]["prereq_ids"] += compress_id(prerequisite_node, id_cache)
		if (LAZYLEN(node.design_ids))
			node_cache[compressed_id]["design_ids"] = list()
			for (var/unlocked_design in node.design_ids)
				node_cache[compressed_id]["design_ids"] += compress_id(unlocked_design, id_cache)
		if (LAZYLEN(node.unlock_ids))
			node_cache[compressed_id]["unlock_ids"] = list()
			for (var/unlocked_node in node.unlock_ids)
				node_cache[compressed_id]["unlock_ids"] += compress_id(unlocked_node, id_cache)
		if (LAZYLEN(node.required_experiments))
			node_cache[compressed_id]["required_experiments"] = node.required_experiments
		if (LAZYLEN(node.discount_experiments))
			node_cache[compressed_id]["discount_experiments"] = node.discount_experiments

	// Build design cache
	var/design_cache = list()
	var/datum/asset/spritesheet_batched/research_designs/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/research_designs)
	var/size32x32 = "[spritesheet.name]32x32"
	for (var/design_id in SSresearch.techweb_designs)
		var/datum/design_techweb/design = SSresearch.techweb_designs[design_id] || SSresearch.error_design
		var/compressed_id = "[compress_id(design.id, id_cache)]"
		var/css_id = sanitize_css_class_name(design.id)
		var/size = spritesheet.icon_size_id(css_id)
		design_cache[compressed_id] = list(
			design.name,
			"[size == size32x32 ? "" : "[size] "][css_id]"
		)

	// Ensure id cache is included for decompression
	var/flat_id_cache = list()
	for (var/id in id_cache)
		flat_id_cache += id

	.["static_data"] = list(
		"node_cache" = node_cache,
		"design_cache" = design_cache,
		"id_cache" = flat_id_cache,
	)

/// A locked console refuses every button but the lock toggle; the user alone is told (it used to announce it aloud to the room).
/obj/machinery/computer/rdconsole_tg/proc/unlocked_refusal(datum/act/op/A)
	if(locked)
		return /datum/msg/rdconsole/locked
	return null

/obj/machinery/computer/rdconsole_tg/proc/controls_touched(datum/act/op/A)
	add_fingerprint(A.actor)

/obj/machinery/computer/rdconsole_tg/proc/ui_act_togglelock(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		set_locked(!locked)
	else
		to_chat(user, span_boldwarning("Unauthorized Access."))
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/ui_act_researchnode(datum/act/op/A, node_id)
	var/mob/user = A.actor
	research_node(node_id, user)
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/ui_act_enqueuenode(datum/act/op/A, node_id)
	var/mob/user = A.actor
	enqueue_node(node_id, user)
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/ui_act_dequeuenode(datum/act/op/A, node_id)
	var/mob/user = A.actor
	dequeue_node(node_id, user)
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/ui_act_ejectdisk(datum/act/op/A, type)
	eject_disk(type)
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/ui_act_uploaddisk(datum/act/op/A, type)
	if(type == RND_DESIGN_DISK)
		if(QDELETED(d_disk))
			atom_say("No design disk inserted!")
			return TRUE
		for(var/D in d_disk.blueprints)
			if(D)
				stored_research.add_design(D, TRUE)
		atom_say("Uploading blueprints from disk.")
		d_disk.on_upload(stored_research, src)
		return TRUE
	if(type == RND_TECH_DISK)
		if(!COOLDOWN_FINISHED(src, cooldowncopy)) // prevents MC hang
			atom_say("Servers busy!")
			return
		if (QDELETED(t_disk))
			atom_say("No tech disk inserted!")
			return TRUE
		COOLDOWN_START(src, cooldowncopy, 5 SECONDS)
		atom_say("Uploading technology disk.")
		t_disk.stored_research().copy_research_to(stored_research)
	return TRUE

//Tech disk-only action.

/obj/machinery/computer/rdconsole_tg/proc/ui_act_loadtech(datum/act/op/A)
	if(!COOLDOWN_FINISHED(src, cooldowncopy)) // prevents MC hang
		atom_say("Servers busy!")
		return
	if(QDELETED(t_disk))
		atom_say("No tech disk inserted!")
		return
	COOLDOWN_START(src, cooldowncopy, 5 SECONDS)
	atom_say("Downloading to technology disk.")
	stored_research.copy_research_to(t_disk.stored_research())
	return TRUE

/obj/machinery/computer/rdconsole_tg/proc/eject_disk(type)
	if(type == RND_DESIGN_DISK && d_disk)
		d_disk.forceMove(get_turf(src))
		rel_take(src, nameof(d_disk))
	if(type == RND_TECH_DISK && t_disk)
		t_disk.forceMove(get_turf(src))
		rel_take(src, nameof(t_disk))

#undef RND_TECH_DISK
#undef RND_DESIGN_DISK
