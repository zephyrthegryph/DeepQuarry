/obj/item/disk/botany
	name = "flora data disk"
	desc = "A small disk used for carrying data on plant genetics."
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "disk"
	w_class = ITEMSIZE_TINY

	var/list/genes = list()
	var/genesource = "unknown"

/obj/item/disk/botany/Initialize(mapload)
	. = ..()
	pixel_x = rand(-5,5)
	pixel_y = rand(-5,5)

/obj/item/disk/botany/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(LAZYLEN(genes))
		var/choice = tgui_alert(user, "Are you sure you want to wipe the disk?", "Xenobotany Data", list("No", "Yes"))
		if(src && user && genes && choice && choice == "Yes" && user.Adjacent(get_turf(src)))
			to_chat(user, span_filter_notice("You wipe the disk data."))
			name = initial(name)
			desc = initial(name)
			genes = list()
			genesource = "unknown"

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
	var/active = 0
	var/action_time = 5
	var/last_action = 0
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

/obj/machinery/botany/Destroy()
	if(seed)
		seed.forceMove(get_turf(src))
	if(loaded_disk)
		loaded_disk.forceMove(get_turf(src))
	. = ..()

/obj/machinery/botany/process()

	..()
	if(!active) return

	if(world.time > last_action + action_time)
		finished_task()

/// Old attack_hand (never called ..()): open the interface.
/datum/interaction/machine_hand/ungated/botany_open_ui
	id = "botany_open_ui"
	name = "Use"
	effect = /obj/machinery/botany/proc/interaction_open_ui

/obj/machinery/botany/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/obj/machinery/botany/proc/finished_task()
	active = 0
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
			loaded_disk = null

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
	if(S.seed && S.seed.get_trait(TRAIT_IMMUTABLE) > 0)
		to_chat(user, span_filter_notice("That seed is not compatible with our genetics technology."))
	else
		user.drop_from_inventory(W)
		W.forceMove(src)
		seed = W
		to_chat(user, span_filter_notice("You load [W] into [src]."))
	return TRUE

/// Old attackby: `if(!active) if(default_part_replacement(user, W)) return`.
/datum/interaction/machine_item/botany_part_replacement
	id = "botany_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/botany/proc/botany_not_active, null))
	effect = /obj/machinery/botany/proc/interaction_part_replacement

/obj/machinery/botany/proc/botany_not_active(mob/actor, atom/target, obj/item/held)
	return !active

/obj/machinery/botany/proc/interaction_part_replacement(mob/user, obj/item/held, datum/interaction/interaction)
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
	user.drop_from_inventory(W)
	W.forceMove(src)
	loaded_disk = W
	to_chat(user, span_filter_notice("You load [W] into [src]."))
	return TRUE

/obj/machinery/botany/screwdriver_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/botany/wrench_act(mob/user, obj/item/tool)
	playsound(src, tool.usesound, 100, TRUE)
	to_chat(user, span_notice("You [anchored ? "un" : ""]secure \the [src]."))
	anchored = !anchored
	return ITEM_INTERACT_SUCCESS

/obj/machinery/botany/crowbar_act(mob/user, obj/item/tool)
	if(active)
		return ITEM_INTERACT_BLOCKING
	return ..()

// Allows for a trait to be extracted from a seed packet, destroying that seed.
/obj/machinery/botany/extractor
	name = "lysis-isolation centrifuge"
	icon_state = "traitcopier"

	var/datum/seed/genetics // Currently scanned seed genetic structure.
	var/degradation = 0     // Increments with each scan, stops allowing gene mods after a certain point.
	circuit = /obj/item/circuitboard/botany_extractor

/obj/machinery/botany/extractor/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BotanyIsolator", name)
		ui.open()

/obj/machinery/botany/extractor/tgui_data(mob/user)
	var/list/data = ..()

	var/list/geneMasks = SSplants.gene_masked_list
	data["geneMasks"] = geneMasks

	data["activity"] = active
	data["degradation"] = degradation

	if(loaded_disk)
		data["disk"] = 1
	else
		data["disk"] = 0

	if(seed)
		data["loaded"] = "[seed.name]"
	else
		data["loaded"] = 0

	if(genetics)
		data["hasGenetics"] = 1
		data["sourceName"] = genetics.display_name
		if(!genetics.roundstart)
			data["sourceName"] += " (variety #[genetics.uid])"
	else
		data["hasGenetics"] = 0
		data["sourceName"] = 0

	return data

/obj/machinery/botany/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	add_fingerprint(ui.user)

	switch(action)
		if("eject_packet")
			if(!seed)
				return
			seed.forceMove(get_turf(src))

			if(seed.seed.name == "new line" || isnull(SSplants.seeds[seed.seed.name]))
				seed.seed.uid = SSplants.seeds.len + 1
				seed.seed.name = "[seed.seed.uid]"
				SSplants.seeds[seed.seed.name] = seed.seed

			seed.update_seed()
			visible_message("[icon2html(src,viewers(src))] [src] beeps and spits out [seed].")

			seed = null
			return TRUE

		if("eject_disk")
			if(!loaded_disk)
				return
			loaded_disk.forceMove(get_turf(src))
			visible_message("[icon2html(src,viewers(src))] [src] beeps and spits out [loaded_disk].")
			loaded_disk = null
			return TRUE

/obj/machinery/botany/extractor/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("scan_genome")
			if(!seed)
				return

			last_action = world.time
			active = 1

			if(seed && seed.seed)
				genetics = seed.seed
				degradation = 0

			qdel(seed)
			seed = null
			return TRUE

		if("get_gene")
			if(!genetics || !loaded_disk)
				return

			last_action = world.time
			active = 1

			var/datum/plantgene/P = genetics.get_gene(params["get_gene"])
			if(!P)
				return
			loaded_disk.genes += P

			loaded_disk.genesource = "[genetics.display_name]"
			if(!genetics.roundstart)
				loaded_disk.genesource += " (variety #[genetics.uid])"

			loaded_disk.name += " ([SSplants.gene_tag_masks[params["get_gene"]]], #[genetics.uid])"
			loaded_disk.desc += " The label reads \'gene [SSplants.gene_tag_masks[params["get_gene"]]], sampled from [genetics.display_name]\'."
			eject_disk = 1

			degradation += rand(20,60)
			if(degradation >= 100)
				failed_task = 1
				genetics = null
				degradation = 0
			return TRUE

		if("clear_buffer")
			if(!genetics)
				return
			genetics = null
			degradation = 0
			return TRUE

// Fires an extracted trait into another packet of seeds with a chance
// of destroying it based on the size/complexity of the plasmid.
/obj/machinery/botany/editor
	name = "bioballistic delivery system"
	icon_state = "traitgun"
	disk_needs_genes = 1
	circuit = /obj/item/circuitboard/botany_editor

/obj/machinery/botany/editor/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BotanyEditor", name)
		ui.open()

/obj/machinery/botany/editor/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["activity"] = active

	if(seed)
		data["degradation"] = seed.modified
	else
		data["degradation"] = 0

	if(loaded_disk && loaded_disk.genes.len)
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

/obj/machinery/botany/editor/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("apply_gene")
			if(!loaded_disk || !seed)
				return

			last_action = world.time
			active = 1

			if(!isnull(SSplants.seeds[seed.seed.name]))
				seed.seed = seed.seed.diverge(1)
				seed.seed_type = seed.seed.name
				seed.update_seed()

			if(prob(seed.modified))
				failed_task = 1
				seed.modified = 101

			for(var/datum/plantgene/gene in loaded_disk.genes)
				seed.seed.apply_gene(gene)
				seed.modified += rand(5,10)
			return TRUE
