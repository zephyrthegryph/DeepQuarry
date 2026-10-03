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

/obj/item/disk/botany/Initialize(mapload)
	. = ..()
	pixel_x = rand(-5,5)
	pixel_y = rand(-5,5)

DECLARE_INTERACTIONS(/obj/item/disk/botany, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/disk/botany/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(LAZYLEN(genes))
		var/choice = rerun_ask(user, "k21", PROC_REF(interaction_self), args, /datum/om/prompt/choice/alert, message = "Are you sure you want to wipe the disk?", title = "Xenobotany Data", choices = list("No", "Yes"))
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

/obj/item/storage/box/botanydisk/Initialize(mapload)
	. = ..()
	for(var/i = 0;i<7;i++)
		new /obj/item/disk/botany(src)

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

/obj/machinery/botany/Initialize(mapload)
	. = ..()
	default_apply_parts()

/* Currently part upgrades do nothing
/obj/machinery/botany/RefreshParts()
	..()
*/

/obj/machinery/botany/ownership()
	. = ..()
	. += owns(nameof(seed), policy = OWN_SPILL)
	. += owns(nameof(loaded_disk), policy = OWN_SPILL)

/obj/machinery/botany/machine_step()

	..()
	if(!active) return

	if(COOLDOWN_FINISHED(src, action_cooldown))
		finished_task()

/// Old attack_hand (never called ..()): open the interface.
/datum/interaction/machine_hand/ungated/botany_open_ui
	id = "botany_open_ui"
	name = "Use"
	effect = /obj/machinery/botany/proc/interaction_open_ui_impl

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

/obj/machinery/botany/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/botany_open_ui,
		/datum/interaction/machine_item/botany_load_seed,
		/datum/interaction/machine_item/botany_part_replacement,
		/datum/interaction/machine_item/botany_load_disk,
	)
	..()

/// Old attackby: load a seed packet.
/datum/interaction/machine_item/botany_load_seed
	id = "botany_load_seed"
	name = "Load seed"
	held_type = /obj/item/seeds
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_no_seed_loaded, "there is already a seed loaded"))
	effect = /obj/machinery/botany/proc/interaction_load_seed

/obj/machinery/botany/proc/botany_no_seed_loaded(mob/actor, atom/target, obj/item/held)
	return !seed

/obj/machinery/botany/proc/interaction_load_seed(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/seeds/S = W
	if(S.seed() && S.seed().get_trait(TRAIT_IMMUTABLE) > 0)
		to_chat(user, span_filter_notice("That seed is not compatible with our genetics technology."))
	else
		if(!own_set(src, nameof(src.seed), W, user = user))
			return TRUE
		to_chat(user, span_filter_notice("You load [W] into [src]."))
	return TRUE

/// Old attackby: `if(!active) if(default_part_replacement(user, W)) return`.
/datum/interaction/machine_item/botany_part_replacement
	id = "botany_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_not_active, null))
	effect = /obj/machinery/botany/proc/interaction_part_replacement_impl

/obj/machinery/botany/proc/botany_not_active(mob/actor, atom/target, obj/item/held)
	return !active

/obj/machinery/botany/proc/interaction_part_replacement_impl(mob/user, obj/item/held, datum/interaction/interaction)
	return default_part_replacement(user, held) ? TRUE : FALSE

/// Old attackby: load a botany data disk.
/datum/interaction/machine_item/botany_load_disk
	id = "botany_load_disk"
	name = "Load disk"
	held_type = /obj/item/disk/botany
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_disk_slot_reason, null))
	effect = /obj/machinery/botany/proc/interaction_load_disk

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
	if(!own_set(src, nameof(src.loaded_disk), W, user = user))
		return TRUE
	to_chat(user, span_filter_notice("You load [W] into [src]."))
	return TRUE

/obj/machinery/botany/screwdriver_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/botany/wrench_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 100, TRUE)
	to_chat(user, span_notice("You [anchored ? "un" : ""]secure \the [src]."))
	set_anchored(!anchored)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/botany/crowbar_act(mob/user, obj/item/tool)
	if(active)
		return ITEM_INTERACT_BLOCKING
	return ..()

// Allows for a trait to be extracted from a seed packet, destroying that seed.
/obj/machinery/botany/extractor
	name = "lysis-isolation centrifuge"
	icon_state = "traitcopier"

	var/tmp/datum/seed/genetics_static	// Currently scanned seed genetic structure.
	var/degradation = 0     // Increments with each scan, stops allowing gene mods after a certain point.
	circuit = /obj/item/circuitboard/botany_extractor

DECLARE_UI(/obj/machinery/botany/extractor, "BotanyIsolator")

UI_DATA(/obj/machinery/botany/extractor, "degradation:num", "merge:ui_data_obj_machinery_botany_extractor{geneMasks:list,activity:num,disk:num,loaded:unknown,hasGenetics:num,sourceName:unknown}")

/// The computed part of /obj/machinery/botany/extractor's window data (declared on its UI_DATA row).
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

/obj/machinery/botany/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/botany, "eject_packet", ui_act_eject_packet)
UI_ACT_PROC(/obj/machinery/botany, ui_act_eject_packet)
	if(!seed)
		return
	seed.forceMove(get_turf(src))

	if(seed.seed().name == "new line" || isnull(SSplants.seeds[seed.seed().name]))
		SSplants.register_line(seed.seed()) // the packet keeps its private copy, renamed to the line

	seed.update_seed()
	visible_message("[icon2html(src,viewers(src))] [src] beeps and spits out [seed].")

	own_take(src, nameof(/datum/generated_station_spec::seed))
	return TRUE

UI_ACT(/obj/machinery/botany, "eject_disk", ui_act_eject_disk)
UI_ACT_PROC(/obj/machinery/botany, ui_act_eject_disk)
	if(!loaded_disk)
		return
	loaded_disk.forceMove(get_turf(src))
	visible_message("[icon2html(src,viewers(src))] [src] beeps and spits out [loaded_disk].")
	own_take(src, nameof(/obj/machinery/botany::loaded_disk))
	return TRUE

UI_ACT(/obj/machinery/botany/extractor, "scan_genome", ui_act_scan_genome)
UI_ACT_PROC(/obj/machinery/botany/extractor, ui_act_scan_genome)
	if(!seed)
		return

	COOLDOWN_START(src, action_cooldown, action_time)
	set_active(1)

	if(seed && seed.seed())
		seed_hand_over(seed, "seed_static", src, "genetics_static") // the packet is consumed below
		degradation = 0

	consume(seed)
	own_take(src, nameof(/datum/generated_station_spec::seed))
	return TRUE

UI_ACT(/obj/machinery/botany/extractor, "get_gene", ui_act_get_gene, UI_ARG_TEXT("get_gene"))
UI_ACT_PROC(/obj/machinery/botany/extractor, ui_act_get_gene)
	if(!genetics() || !loaded_disk)
		return

	COOLDOWN_START(src, action_cooldown, action_time)
	set_active(1)

	var/datum/plantgene/P = genetics().get_gene(params["get_gene"])
	if(!P)
		return
	rel_add(loaded_disk, nameof(/obj/item/disk/botany::genes), P) // get_gene() makes a fresh copy: the disk owns it

	loaded_disk.genesource = "[genetics().display_name]"
	if(!genetics().roundstart)
		loaded_disk.genesource += " (variety #[genetics().uid])"

	loaded_disk.name += " ([SSplants.gene_tag_masks[params["get_gene"]]], #[genetics().uid])"
	loaded_disk.desc += " The label reads \'gene [SSplants.gene_tag_masks[params["get_gene"]]], sampled from [genetics().display_name]\'."
	eject_disk = 1

	degradation += rand(20,60)
	if(degradation >= 100)
		failed_task = 1
		proto_set(src, nameof(/obj/machinery/botany/extractor::genetics_static), null)
		degradation = 0
	return TRUE

UI_ACT(/obj/machinery/botany/extractor, "clear_buffer", ui_act_clear_buffer)
UI_ACT_PROC(/obj/machinery/botany/extractor, ui_act_clear_buffer)
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

DECLARE_UI(/obj/machinery/botany/editor, "BotanyEditor")

UI_DATA(/obj/machinery/botany/editor, "merge:ui_data_obj_machinery_botany_editor{activity:num,degradation:num,disk:num,sourceName:unknown,locus:unknown,loaded:unknown}")

/// The computed part of /obj/machinery/botany/editor's window data (declared on its UI_DATA row).
/obj/machinery/botany/editor/proc/ui_data_obj_machinery_botany_editor(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

UI_ACT(/obj/machinery/botany/editor, "apply_gene", ui_act_apply_gene)
UI_ACT_PROC(/obj/machinery/botany/editor, ui_act_apply_gene)
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

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/botany/step_start_condition()
	return active

/// The scanned seed: a registered line, or the private copy taken from a consumed packet.
/obj/machinery/botany/extractor/proc/genetics() as /datum/seed
	return genetics_static

/obj/machinery/botany/extractor/ownership()
	. = ..()
	. += rel_one(nameof(genetics_static), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)
