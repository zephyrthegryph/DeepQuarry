/obj/item/disk/botany
	name = "flora data disk"
	desc = "A small disk used for carrying data on plant genetics."
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "disk"
	w_class = ITEMSIZE_TINY

	var/list/genes
	var/genesource = "unknown"

CAPABILITIES(/obj/item/disk/botany)
	owns_many(nameof(genes))
	rolls(ROLL_PIXEL, PIXEL_JITTER(5))

DECLARE_INTERACTIONS(/obj/item/disk/botany, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/disk/botany/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return botany_disk_wipe_stage(user, held, interaction)

/obj/item/disk/botany/proc/botany_disk_wipe_stage(mob/user, obj/item/held, datum/interaction/interaction, botany_answer, botany_answer_ready = FALSE)
	if(LAZYLEN(genes))
		if(!botany_answer_ready)
			open_request(src, /datum/prompt/choice/botany_disk_wipe, PROC_REF(botany_disk_wipe_answered), answerer = user, botany_operator = user, botany_held = held, botany_interaction = interaction, question = "Are you sure you want to wipe the disk?", title = "Xenobotany Data", choices = list("No", "Yes"), buttons = TRUE)
			return TRUE
		var/choice = botany_answer
		if(isnull(choice))
			return TRUE
		if(src && user && genes && choice && choice == "Yes" && user.Adjacent(get_turf(src)))
			to_chat(user, span_filter_notice("You wipe the disk data."))
			name = initial(name)
			desc = initial(name)
			own_clear(src, nameof(genes), OWN_DELETE)
			genesource = "unknown"
	return TRUE

/obj/item/storage/box/botanydisk
	name = "flora disk box"
	desc = "A box of flora data disks, apparently."

/obj/item/storage/box/botanydisk
	starts_with = list(
		/obj/item/disk/botany = 7,
	)

/obj/machinery/botany
	maintenance_flags = MACHINE_MAINT_STANDARD
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "hydrotray3"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE

	var/obj/item/seeds/seed // Currently loaded seed packet.
	var/obj/item/disk/botany/loaded_disk //Currently loaded data disk.

	var/open = 0
	active = 0
	var/action_time = 5
	COOLDOWN_DECLARE(action_cooldown)
	var/eject_disk = 0
	var/failed_task = 0
	var/disk_needs_genes = 0

/* Currently part upgrades do nothing
/obj/machinery/botany/RefreshParts()
	..()
*/

CAPABILITIES(/obj/machinery/botany)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	owns_one(nameof(seed), on_destroy = ON_DESTROY_SPILL)
	owns_one(nameof(loaded_disk), on_destroy = ON_DESTROY_SPILL)
	op("eject_packet", ui_act("eject_packet"), then(PROC_REF(ui_act_eject_packet)))
	op("eject_disk", ui_act("eject_disk"), then(PROC_REF(ui_act_eject_disk)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	default_parts()

/obj/machinery/botany/proc/work_step(datum/act/timer/A)

	if(!active) return

	if(COOLDOWN_FINISHED(src, action_cooldown))
		finished_task()

/obj/machinery/botany/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/obj/machinery/botany/proc/finished_task()
	set_active(0)
	if(failed_task)
		failed_task = 0
		visible_message(span_filter_notice("[icon2html(src,viewers(src))] [src] pings unhappily, flashing a red warning light."))
	else
		visible_message(span_filter_notice("[icon2html(src,viewers(src))] [src] pings happily."))

	if(eject_disk)
		eject_disk = 0
		if(loaded_disk)
			loaded_disk.forceMove(get_turf(src))
			visible_message(span_filter_notice("[icon2html(src,viewers(src))] [src] beeps and spits out [loaded_disk]."))
			own_take(src, nameof(loaded_disk))

EXTEND_INTERACTIONS(/obj/machinery/botany, \
	INTERACT_HAND_UNGATED("Use", PROC_REF(interaction_open_ui_impl)), \
	INTERACT_INSERT(/obj/item/seeds, PROC_REF(interaction_load_seed), "Load seed", REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_no_seed_loaded, "there is already a seed loaded")), \
	INTERACT_INSERT(/obj/item/storage/part_replacer, PROC_REF(interaction_part_replacement_impl), "Replace parts", OFFERED_WHEN(REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_not_active, null))), \
	INTERACT_INSERT(/obj/item/disk/botany, PROC_REF(interaction_load_disk), "Load disk", REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_disk_slot_reason, null)), \
)

/obj/machinery/botany/proc/botany_no_seed_loaded(mob/actor, atom/target, obj/item/held)
	return !seed

/obj/machinery/botany/proc/interaction_load_seed(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/seeds/S = W
	if(S.seed() && S.seed().get_trait(TRAIT_IMMUTABLE) > 0)
		to_chat(user, span_filter_notice("That seed is not compatible with our genetics technology."))
	else
		if(!move_into(src, nameof(src.seed), W, user))
			return TRUE
		to_chat(user, span_filter_notice("You load [W] into [src]."))
	return TRUE

/obj/machinery/botany/proc/botany_not_active(mob/actor, atom/target, obj/item/held)
	return !active

/obj/machinery/botany/proc/interaction_part_replacement_impl(mob/user, obj/item/held, datum/interaction/interaction)
	return default_part_replacement(user, held) ? TRUE : FALSE

/obj/machinery/botany/proc/botany_disk_slot_reason(mob/actor, atom/target, obj/item/held)
	if(loaded_disk)
		return "there is already a data disk loaded"
	var/obj/item/disk/botany/B = held
	if(B.genes && B.genes.len)
		if(!disk_needs_genes)
			return "that disk already has gene data loaded"
	else
		if(disk_needs_genes)
			return "that disk does not have any gene data loaded"
	return TRUE

/obj/machinery/botany/proc/interaction_load_disk(mob/user, obj/item/W, datum/interaction/interaction)
	if(!move_into(src, nameof(src.loaded_disk), W, user))
		return TRUE
	to_chat(user, span_filter_notice("You load [W] into [src]."))
	return TRUE

/obj/machinery/botany/proc/screwdriver_used(datum/act/op/A)
	return OP_DECLINE

/obj/machinery/botany/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 100, TRUE)
	to_chat(user, span_notice("You [anchored ? "un" : ""]secure \the [src]."))
	set_anchored(!anchored)
	return OP_OK

/obj/machinery/botany/proc/crowbar_used(datum/act/op/A)
	if(active)
		return OP_OK
	return OP_DECLINE

// Allows for a trait to be extracted from a seed packet, destroying that seed.
/obj/machinery/botany/extractor
	name = "lysis-isolation centrifuge"
	icon_state = "traitcopier"

	var/tmp/datum/seed/genetics_static	// Currently scanned seed genetic structure.
	var/degradation = 0     // Increments with each scan, stops allowing gene mods after a certain point.
	circuit = /obj/item/circuitboard/botany_extractor

/obj/machinery/botany/extractor/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["degradation"] = degradation
	var/list/merged_1 = ui_data_obj_machinery_botany_extractor(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/botany/extractor's window data.
/obj/machinery/botany/extractor/proc/ui_data_obj_machinery_botany_extractor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/geneMasks = SSplants.gene_masked_list
	data["geneMasks"] = geneMasks

	data["activity"] = active

	if(loaded_disk)
		data["disk"] = 1
	else
		data["disk"] = 0

	if(seed)
		data["loaded"] = "[seed.name]"
	else
		data["loaded"] = 0

	if(genetics())
		data["hasGenetics"] = 1
		data["sourceName"] = genetics().display_name
		if(!genetics().roundstart)
			data["sourceName"] += " (variety #[genetics().uid])"
	else
		data["hasGenetics"] = 0
		data["sourceName"] = 0

	return data

/obj/machinery/botany/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	return TRUE

/obj/machinery/botany/proc/ui_act_eject_packet(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!seed)
		return
	seed.forceMove(get_turf(src))

	if(seed.seed().name == "new line" || isnull(SSplants.seeds[seed.seed().name]))
		SSplants.register_line(seed.seed()) // the packet keeps its private copy, renamed to the line

	seed.update_seed()
	visible_message("[icon2html(src,viewers(src))] [src] beeps and spits out [seed].")

	own_take(src, nameof(seed))
	return TRUE

/obj/machinery/botany/proc/ui_act_eject_disk(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!loaded_disk)
		return
	loaded_disk.forceMove(get_turf(src))
	visible_message("[icon2html(src,viewers(src))] [src] beeps and spits out [loaded_disk].")
	own_take(src, nameof(/obj/machinery/botany::loaded_disk))
	return TRUE

/obj/machinery/botany/extractor/proc/ui_act_scan_genome(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!seed)
		return

	COOLDOWN_START(src, action_cooldown, action_time)
	set_active(1)

	if(seed && seed.seed())
		seed_hand_over(seed, "seed_static", src, "genetics_static") // the packet is consumed below
		degradation = 0

	consume(seed)
	own_take(src, nameof(seed))
	return TRUE

/obj/machinery/botany/extractor/proc/ui_act_get_gene(datum/act/op/A, get_gene)
	if(!ui_gate(A))
		return FALSE
	if(!genetics() || !loaded_disk)
		return

	COOLDOWN_START(src, action_cooldown, action_time)
	set_active(1)

	var/datum/plantgene/P = genetics().get_gene(get_gene)
	if(!P)
		return
	rel_add(loaded_disk, nameof(/obj/item/disk/botany::genes), P) // get_gene() makes a fresh copy: the disk owns it

	loaded_disk.genesource = "[genetics().display_name]"
	if(!genetics().roundstart)
		loaded_disk.genesource += " (variety #[genetics().uid])"

	loaded_disk.name += " ([SSplants.gene_tag_masks[get_gene]], #[genetics().uid])"
	loaded_disk.desc += " The label reads \'gene [SSplants.gene_tag_masks[get_gene]], sampled from [genetics().display_name]\'."
	eject_disk = 1

	degradation += rand(20,60)
	if(degradation >= 100)
		failed_task = 1
		proto_set(src, nameof(/obj/machinery/botany/extractor::genetics_static), null)
		degradation = 0
	return TRUE

/obj/machinery/botany/extractor/proc/ui_act_clear_buffer(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!genetics())
		return
	proto_set(src, nameof(/obj/machinery/botany/extractor::genetics_static), null)
	degradation = 0
	return TRUE

// Fires an extracted trait into another packet of seeds with a chance
// of destroying it based on the size/complexity of the plasmid.
/obj/machinery/botany/editor
	name = "bioballistic delivery system"
	icon_state = "traitgun"
	disk_needs_genes = 1
	circuit = /obj/item/circuitboard/botany_editor

CAPABILITIES(/obj/machinery/botany/editor)
	interface("BotanyEditor")
	without("ui_open")
	op("apply_gene", ui_act("apply_gene"), then(PROC_REF(ui_act_apply_gene)))

/// /obj/machinery/botany/editor's window data.
/obj/machinery/botany/editor/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["activity"] = active

	if(seed)
		data["degradation"] = seed.modified
	else
		data["degradation"] = 0

	if(loaded_disk && length(loaded_disk.genes))
		data["disk"] = 1
		data["sourceName"] = loaded_disk.genesource
		data["locus"] = ""

		for(var/datum/plantgene/P in loaded_disk.genes)
			if(data["locus"] != "") data["locus"] += ", "
			data["locus"] += "[SSplants.gene_tag_masks[P.genetype]]"

	else
		data["disk"] = 0
		data["sourceName"] = 0
		data["locus"] = 0

	if(seed)
		data["loaded"] = "[seed.name]"
	else
		data["loaded"] = 0

	return data

/obj/machinery/botany/editor/proc/ui_act_apply_gene(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!loaded_disk || !seed)
		return

	COOLDOWN_START(src, action_cooldown, action_time)
	set_active(1)

	if(!isnull(SSplants.seeds[seed.seed().name]))
		var/datum/seed/modified_seed = seed.seed().diverge(1)
		if(!modified_seed) // TRAIT_IMMUTABLE: never edit the shared line
			set_active(FALSE)
			return
		proto_set(seed, nameof(/obj/effect/plant::seed_static), modified_seed)
		seed.seed_type = seed.seed().name
		seed.update_seed()

	if(prob(seed.modified))
		failed_task = 1
		seed.modified = 101

	for(var/datum/plantgene/gene in loaded_disk.genes)
		seed.seed().apply_gene(gene)
		seed.modified += rand(5,10)
	return TRUE

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/botany/step_start_condition()
	return active

/// The scanned seed: a registered line, or the private copy taken from a consumed packet.
/obj/machinery/botany/extractor/proc/genetics() as /datum/seed
	return genetics_static

CAPABILITIES(/obj/machinery/botany/extractor)
	owns_one(nameof(genetics_static), on_destroy = ON_DESTROY_PRIVATE_COPY)
	interface("BotanyIsolator")
	without("ui_open")
	op("scan_genome", ui_act("scan_genome"), then(PROC_REF(ui_act_scan_genome)))
	op("get_gene", ui_act("get_gene", arg("get_gene", schema_text(4096))), then(PROC_REF(ui_act_get_gene)))
	op("clear_buffer", ui_act("clear_buffer"), then(PROC_REF(ui_act_clear_buffer)))
/obj/item/disk/botany/proc/botany_disk_wipe_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = botany_disk_wipe_apply(A)
	SStgui.update_uis(src)

/obj/item/disk/botany/proc/botany_disk_wipe_apply(datum/act/request/A)
	var/datum/prompt/choice/botany_disk_wipe/ask = A.answer
	return botany_disk_wipe_stage(ask.botany_operator, ask.botany_held, ask.botany_interaction, ask.value, TRUE)

/datum/prompt/choice/botany_disk_wipe
	timeout = 0
	var/mob/botany_operator
	var/obj/item/botany_held
	var/datum/interaction/botany_interaction
	var/botany_operator_expected = FALSE
	var/botany_held_expected = FALSE
	var/botany_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/choice/botany_disk_wipe)
	ref_one(nameof(botany_operator), /mob)
	ref_one(nameof(botany_held), /obj/item)
	ref_one(nameof(botany_interaction), /datum/interaction)

/datum/prompt/choice/botany_disk_wipe/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = botany_operator
	var/obj/item/captured_held = botany_held
	var/datum/interaction/captured_interaction = botany_interaction
	botany_operator_expected = !isnull(captured_operator)
	botany_held_expected = !isnull(captured_held)
	botany_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(botany_operator))
	rel_clear(src, nameof(botany_held))
	rel_clear(src, nameof(botany_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(botany_operator), captured_operator)
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(botany_held), captured_held)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(botany_interaction), captured_interaction)

/datum/prompt/choice/botany_disk_wipe/recheck_extra()
	if((botany_operator_expected && QDELETED(botany_operator)) || (botany_held_expected && QDELETED(botany_held)) || (botany_interaction_expected && QDELETED(botany_interaction)))
		return "gone"
