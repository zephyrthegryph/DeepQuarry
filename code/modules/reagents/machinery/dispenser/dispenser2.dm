/obj/machinery/chemical_dispenser
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 2 SECONDS
	name = "chemical dispenser"
	desc = "Automagically fabricates chemicals from electricity."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "dispenser"
	clicksound = "switch"

	var/list/spawn_cartridges = null // Set to a list of types to spawn one of each on New()

	var/list/cartridges = list() // Associative, label -> cartridge
	var/obj/item/reagent_containers/container = null

	var/ui_title = "Chemical Dispenser"

	var/accept_drinking = 0
	var/amount = 30
	var/max_catriges = 30

	use_power = USE_POWER_IDLE
	idle_power_usage = 100
	anchored = TRUE
	unacidable = TRUE

	/// Records the reagents dispensed by the user if this list is not null
	var/list/recording_recipe
	/// Saves all the recipes recorded by the machine
	var/list/saved_recipes
	var/import_job = JOB_CHEMIST

/obj/machinery/chemical_dispenser/Initialize(mapload)
	. = ..()
	if(spawn_cartridges)
		for(var/type in spawn_cartridges)
			add_cartridge(new type(src))
	AddElement(/datum/element/rotatable)

/obj/machinery/chemical_dispenser/examine(mob/user)
	. = ..()
	. += "It has [cartridges.len] cartridges installed, and has space for [max_catriges - cartridges.len] more."

/obj/machinery/chemical_dispenser/proc/add_cartridge(obj/item/reagent_containers/chem_disp_cartridge/C, mob/user)
	if(!istype(C))
		if(user)
			to_chat(user, span_warning("\The [C] will not fit in \the [src]!"))
		return

	if(cartridges.len >= max_catriges)
		if(user)
			to_chat(user, span_warning("\The [src] does not have any slots open for \the [C] to fit into!"))
		return

	if(!C.label)
		if(user)
			to_chat(user, span_warning("\The [C] does not have a label!"))
		return

	if(cartridges[C.label])
		if(user)
			to_chat(user, span_warning("\The [src] already contains a cartridge with that label!"))
		return

	if(user)
		user.drop_from_inventory(C)
		to_chat(user, span_notice("You add \the [C] to \the [src]."))

	C.loc = src
	cartridges[C.label] = C
	cartridges = sortAssoc(cartridges)
	SStgui.update_uis(src)

/obj/machinery/chemical_dispenser/proc/remove_cartridge(label)
	. = cartridges[label]
	cartridges -= label
	SStgui.update_uis(src)

/obj/machinery/chemical_dispenser/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/chemical_dispenser_add_cartridge,
		/datum/interaction/machine_item/chemical_dispenser_set_container,
		/datum/interaction/machine_hand/ungated/chemical_dispenser_use,
	)
	..()

/datum/interaction/machine_item/chemical_dispenser_add_cartridge
	id = "chemical_dispenser_add_cartridge"
	name = "Insert cartridge"
	held_type = /obj/item/reagent_containers/chem_disp_cartridge
	effect = /obj/machinery/chemical_dispenser/proc/interaction_add_cartridge

/obj/machinery/chemical_dispenser/proc/interaction_add_cartridge(mob/user, obj/item/W, datum/interaction/interaction)
	add_cartridge(W, user)
	return TRUE

/datum/interaction/machine_item/chemical_dispenser_set_container
	id = "chemical_dispenser_set_container"
	name = "Set container"
	held_type = list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food)
	effect = /obj/machinery/chemical_dispenser/proc/interaction_set_container

/obj/machinery/chemical_dispenser/proc/interaction_set_container(mob/user, obj/item/reagent_containers/RC, datum/interaction/interaction)
	if(container)
		to_chat(user, span_warning("There is already \a [container] on \the [src]!"))
		return TRUE

	if(!accept_drinking && istype(RC,/obj/item/reagent_containers/food))
		to_chat(user, span_warning("This machine only accepts beakers!"))
		return TRUE

	if(!RC.is_open_container())
		to_chat(user, span_warning("You don't see how \the [src] could dispense reagents into \the [RC]."))
		return TRUE
	if(istype(RC, /obj/item/reagent_containers/glass/cooler_bottle))
		to_chat(user, span_warning("You don't see how \the [RC] could fit into \the [src]."))
		return TRUE

	container =  RC
	user.drop_from_inventory(RC)
	RC.loc = src
	to_chat(user, span_notice("You set \the [RC] on \the [src]."))
	return TRUE

/obj/machinery/chemical_dispenser/wrench_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/chemical_dispenser/screwdriver_act(mob/user, obj/item/tool)
	var/label = tgui_input_list(user, "Which cartridge would you like to remove?", "Chemical Dispenser", cartridges)
	if(!label)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/reagent_containers/chem_disp_cartridge/cartridge = remove_cartridge(label)
	if(!cartridge)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You remove \the [cartridge] from \the [src]."))
	cartridge.forceMove(loc)
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/chemical_dispenser/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ChemDispenser", ui_title) // 390, 655
		ui.open()

/obj/machinery/chemical_dispenser/tgui_data(mob/user)
	var/data[0]
	data["amount"] = amount
	data["isBeakerLoaded"] = container ? 1 : 0
	data["glass"] = accept_drinking

	var/beakerContents[0]
	if(container && container.reagents && container.reagents.reagent_list.len)
		for(var/datum/reagent/R in container.reagents.reagent_list)
			beakerContents.Add(list(list("name" = R.name, "id" = R.id, "volume" = R.volume))) // list in a list because Byond merges the first list...
	data["beakerContents"] = beakerContents

	if(container)
		data["beakerCurrentVolume"] = container.reagents.total_volume
		data["beakerMaxVolume"] = container.reagents.maximum_volume
	else
		data["beakerCurrentVolume"] = null
		data["beakerMaxVolume"] = null

	var/chemicals[0]
	for(var/label in cartridges)
		var/obj/item/reagent_containers/chem_disp_cartridge/C = cartridges[label]
		chemicals.Add(list(list("name" = label, "id" = label, "volume" = C.reagents.total_volume))) // list in a list because Byond merges the first list...
	data["chemicals"] = chemicals

	data["recipes"] = (saved_recipes || list())
	data["recordingRecipe"] = recording_recipe
	return data

/obj/machinery/chemical_dispenser/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	if(stat & BROKEN)
		return FALSE

	add_fingerprint(ui.user)

	switch(action)
		if("amount")
			amount = clamp(round(text2num(params["amount"]), 1), 0, 120) // round to nearest 1 and clamp 0 - 120
			. = TRUE

		if("dispense")
			var/label = params["reagent"]
			if(recording_recipe)
				recording_recipe += list(list("id" = label, "amount" = amount))
			else if(cartridges[label] && container && container.is_open_container())
				var/obj/item/reagent_containers/chem_disp_cartridge/C = cartridges[label]
				playsound(src, 'sound/machines/reagent_dispense.ogg', 25, 1)
				C.reagents.trans_to(container, amount)
				START_MACHINE_PROCESSING(src)
			. = TRUE

		if("remove")
			var/amount = text2num(params["amount"])
			if(!container || !amount || recording_recipe)
				return
			var/datum/reagents/R = container.reagents
			var/id = params["reagent"]
			if(amount > 0)
				R.remove_reagent(id, amount)
			else if(amount == -1) // Isolate
				R.isolate_reagent(id)
			. = TRUE

		if("ejectBeaker")
			if(container)
				container.forceMove(get_turf(src))
				if(Adjacent(ui.user)) // So the AI doesn't get a beaker somehow.
					ui.user.put_in_hands(container)
				container = null
			. = TRUE

		if("import_config")
			var/list/our_data = params["config"]
			if(!islist(our_data))
				return FALSE
			var/list/new_recipes = list()
			for(var/key, value in our_data)
				if(istext(key) && islist(value))
					for(var/list/steps in value)
						if(istext(steps["id"]) && isnum(steps["amount"]))
							new_recipes[key] += list(list("id" = steps["id"], "amount" = steps["amount"]))
			if(length(new_recipes))
				saved_recipes = new_recipes
			. = TRUE

		if("record_recipe")
			recording_recipe = list()
			. = TRUE

		if("cancel_recording")
			recording_recipe = null
			. = TRUE

		if("clear_recipes")
			if(tgui_alert(ui.user, "Clear all recipes?", "Clear?", list("No", "Yes")) == "Yes")
				saved_recipes = list()
			. = TRUE

		if("save_recording")
			var/name = tgui_input_text(ui.user, "What do you want to name this recipe?", "Recipe Name?", "Recipe Name", MAX_NAME_LEN)
			if(tgui_status(ui.user, state) != STATUS_INTERACTIVE)
				return
			if(LAZYACCESS(saved_recipes, name) && tgui_alert(ui.user, "\"[name]\" already exists, do you want to overwrite it?",, list("No", "Yes")) != "Yes")
				return
			if(name && recording_recipe)
				for(var/list/L in recording_recipe)
					var/label = L["id"]
					// Verify this dispenser can dispense every chemical
					if(!cartridges[label])
						visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
						to_chat(ui.user, span_warning("[src] cannot find <b>[label]</b>!"))
						playsound(src, 'sound/machines/buzz-two.ogg', 50, TRUE)
						return
				LAZYSET(saved_recipes, name, recording_recipe)
				recording_recipe = null
				. = TRUE

		if("dispense_recipe")
			var/list/chemicals_to_dispense = LAZYACCESS(saved_recipes, params["recipe"])
			if(!LAZYLEN(chemicals_to_dispense))
				return

			if(!recording_recipe)
				if(!container)
					to_chat(ui.user, span_warning("There is no beaker in [src]."))
					return

				for(var/list/L in chemicals_to_dispense)
					var/label = L["id"]
					var/dispense_amount = L["amount"]

					var/obj/item/reagent_containers/chem_disp_cartridge/C = cartridges[label]
					if(!C)
						visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
						to_chat(ui.user, span_warning("[src] cannot find <b>[label]</b>!"))
						playsound(src, 'sound/machines/buzz-two.ogg', 50, TRUE)
						break

					// Allows copying recipes
					playsound(src, 'sound/machines/reagent_dispense.ogg', 25, 1)
					var/amount_actually_dispensed = C.reagents.trans_to(container, dispense_amount)
					START_MACHINE_PROCESSING(src)
					if(dispense_amount != amount_actually_dispensed)
						visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
						to_chat(ui.user, span_warning("[src] was only able to dispense [amount_actually_dispensed ? amount_actually_dispensed : 0]u out of [dispense_amount]u requested of <b>[label]</b>!"))
						playsound(src, 'sound/machines/buzz-two.ogg', 50, TRUE)
						break
			else
				recording_recipe += chemicals_to_dispense
			. = TRUE
		if("remove_recipe")
			LAZYREMOVE(saved_recipes, params["recipe"])
			. = TRUE

/obj/machinery/chemical_dispenser/attack_ghost(mob/user)
	if(stat & BROKEN)
		return
	tgui_interact(user)

/datum/interaction/machine_hand/ungated/chemical_dispenser_use
	id = "chemical_dispenser_use"
	name = "Use"
	effect = /obj/machinery/chemical_dispenser/proc/interaction_use

/obj/machinery/chemical_dispenser/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(stat & BROKEN)
		return TRUE
	tgui_interact(user)
	return TRUE
