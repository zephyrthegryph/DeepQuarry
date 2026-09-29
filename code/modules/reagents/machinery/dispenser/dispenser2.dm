/obj/machinery/chemical_dispenser
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 2 SECONDS
	name = "chemical dispenser"
	desc = "Automagically fabricates chemicals from electricity."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "dispenser"
	clicksound = SFX_SWITCH

	var/list/spawn_cartridges = null // Set to a list of types to spawn one of each on New()

	// ALLOW(instance_list): d: cartridges are spawned into it at init
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
	make_rotatable()

/obj/machinery/chemical_dispenser/examine(mob/user)
	. = ..()
	. += "It has [length(cartridges)] cartridges installed, and has space for [max_catriges - length(cartridges)] more."

/obj/machinery/chemical_dispenser/proc/add_cartridge(obj/item/reagent_containers/chem_disp_cartridge/C, mob/user)
	if(!istype(C))
		if(user)
			to_chat(user, span_warning("\The [C] will not fit in \the [src]!"))
		return

	if(length(cartridges) >= max_catriges)
		if(user)
			to_chat(user, span_warning("\The [src] does not have any slots open for \the [C] to fit into!"))
		return

	if(!C.label)
		if(user)
			to_chat(user, span_warning("\The [C] does not have a label!"))
		return

	if(LAZYACCESS(cartridges, C.label))
		if(user)
			to_chat(user, span_warning("\The [src] already contains a cartridge with that label!"))
		return

	if(!own_put(src, "cartridges", C.label, C, user = user, into = TRUE))
		return
	if(user)
		to_chat(user, span_notice("You add \the [C] to \the [src]."))

	sortTim(cartridges, GLOBAL_PROC_REF(cmp_text_asc)) // in place: the owned list keeps its identity
	SStgui.update_uis(src)

/obj/machinery/chemical_dispenser/proc/remove_cartridge(label)
	. = own_take_member(src, "cartridges", label)
	SStgui.update_uis(src)

/obj/machinery/chemical_dispenser/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_OBSERVER("View", PROC_REF(chemical_dispenser_ghost_view)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
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
	also_requires = list(REQ_FIELD_NOT("container"), REQ_TARGET_STATE(/obj/machinery/chemical_dispenser/proc/can_take_container))

/// Requirement: TRUE, or why this container can't be set on the dispenser.
/obj/machinery/chemical_dispenser/proc/can_take_container(mob/user, atom/target, obj/item/held)
	if(!accept_drinking && istype(held, /obj/item/reagent_containers/food))
		return "this machine only accepts beakers"
	if(!held?.is_open_container())
		return "you don't see how it could dispense reagents into [held]"
	if(istype(held, /obj/item/reagent_containers/glass/cooler_bottle))
		return "you don't see how [held] could fit into it"
	return TRUE

/obj/machinery/chemical_dispenser/proc/interaction_set_container(mob/user, obj/item/reagent_containers/RC, datum/interaction/interaction)
	if(!own_set(src, "container", RC, user = user))
		return TRUE
	to_chat(user, span_notice("You set \the [RC] on \the [src]."))
	return TRUE

/obj/machinery/chemical_dispenser/wrench_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/chemical_dispenser/screwdriver_act(mob/user, obj/item/tool)
	var/label = rerun_ask(user, "a1", TYPE_PROC_REF(/atom, screwdriver_act), args, /datum/om/prompt/choice, message = "Which cartridge would you like to remove?", title = "Chemical Dispenser", choices = cartridges)
	if(!label)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/reagent_containers/chem_disp_cartridge/cartridge = remove_cartridge(label)
	if(!cartridge)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You remove \the [cartridge] from \the [src]."))
	cartridge.forceMove(loc)
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

DECLARE_UI(/obj/machinery/chemical_dispenser, "ChemDispenser")

/obj/machinery/chemical_dispenser/ui_title(mob/user)
	return ui_title

UI_DATA_REPLACE(/obj/machinery/chemical_dispenser, "amount:num", "glass=accept_drinking:num", "recordingRecipe=recording_recipe:list", "merge:ui_data_obj_machinery_chemical_dispenser{isBeakerLoaded:num,beakerContents:list,beakerCurrentVolume:num,beakerMaxVolume:num,chemicals:list,recipes:bool}")

/// The computed part of /obj/machinery/chemical_dispenser's window data (declared on its UI_DATA row).
/obj/machinery/chemical_dispenser/proc/ui_data_obj_machinery_chemical_dispenser(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["isBeakerLoaded"] = container ? 1 : 0

	var/list/beakerContents = list()
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

	var/list/chemicals = list()
	for(var/label in cartridges)
		var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
		chemicals.Add(list(list("name" = label, "id" = label, "volume" = C.reagents.total_volume))) // list in a list because Byond merges the first list...
	data["chemicals"] = chemicals

	data["recipes"] = (saved_recipes || list())
	return data

/obj/machinery/chemical_dispenser/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(has_stat(BROKEN))
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "amount", ui_act_amount, UI_ARG_NUM("amount"))
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_amount)
	amount = clamp(round(params["amount"], 1), 0, 120) // round to nearest 1 and clamp 0 - 120
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "dispense", ui_act_dispense, UI_ARG_TEXT("reagent"))
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_dispense)
	var/label = params["reagent"]
	if(recording_recipe)
		recording_recipe += list(list("id" = label, "amount" = amount))
	else if(LAZYACCESS(cartridges, label) && container && container.is_open_container())
		var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
		play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
		C.reagents.trans_to(container, amount)
		MACHINE_WAKE(src)
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "remove", ui_act_remove, UI_ARG_NUM("amount"), UI_ARG_VALUE("reagent"))
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_remove)
	var/amount = params["amount"]
	if(!container || !amount || recording_recipe)
		return
	var/datum/reagents/R = container.reagents
	var/id = params["reagent"]
	if(amount > 0)
		R.remove_reagent(id, amount)
	else if(amount == -1) // Isolate
		R.isolate_reagent(id)
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "ejectBeaker", ui_act_ejectbeaker)
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_ejectbeaker)
	if(container)
		container.forceMove(get_turf(src))
		if(Adjacent(ui.user)) // So the AI doesn't get a beaker somehow.
			ui.user.put_in_hands(container)
		own_take(src, "container")
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "import_config", ui_act_import_config, UI_ARG_LIST("config"))
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_import_config)
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

UI_ACT(/obj/machinery/chemical_dispenser, "record_recipe", ui_act_record_recipe)
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_record_recipe)
	recording_recipe = list()
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "cancel_recording", ui_act_cancel_recording)
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_cancel_recording)
	recording_recipe = null
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "clear_recipes", ui_act_clear_recipes)
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_clear_recipes)
	var/_answer_a1 = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/choice/alert, message = "Clear all recipes?", title = "Clear?", choices = list("No", "Yes"))
	if(isnull(_answer_a1))
		return
	if(_answer_a1 == "Yes")
		saved_recipes = list()
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "save_recording", ui_act_save_recording)
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_save_recording)
	var/name = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/text, message = "What do you want to name this recipe?", title = "Recipe Name?", default = "Recipe Name", max_length = MAX_NAME_LEN)
	if(isnull(name))
		return
	if(tgui_status(ui.user, state) != STATUS_INTERACTIVE)
		return
	if(LAZYACCESS(saved_recipes, name) && act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/choice/alert, message = "\"[name]\" already exists, do you want to overwrite it?", choices = list("No", "Yes")) != "Yes")
		return
	if(name && recording_recipe)
		for(var/list/L in recording_recipe)
			var/label = L["id"]
			// Verify this dispenser can dispense every chemical
			if(!LAZYACCESS(cartridges, label))
				visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
				to_chat(ui.user, span_warning("[src] cannot find <b>[label]</b>!"))
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)
				return
		LAZYSET(saved_recipes, name, recording_recipe)
		recording_recipe = null
		. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "dispense_recipe", ui_act_dispense_recipe, UI_ARG_TEXT("recipe"))
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_dispense_recipe)
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

			var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
			if(!C)
				visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
				to_chat(ui.user, span_warning("[src] cannot find <b>[label]</b>!"))
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)
				break

			// Allows copying recipes
			play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
			var/amount_actually_dispensed = C.reagents.trans_to(container, dispense_amount)
			MACHINE_WAKE(src)
			if(dispense_amount != amount_actually_dispensed)
				visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
				to_chat(ui.user, span_warning("[src] was only able to dispense [amount_actually_dispensed ? amount_actually_dispensed : 0]u out of [dispense_amount]u requested of <b>[label]</b>!"))
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)
				break
	else
		recording_recipe += chemicals_to_dispense
	. = TRUE

UI_ACT(/obj/machinery/chemical_dispenser, "remove_recipe", ui_act_remove_recipe, UI_ARG_TEXT("recipe"))
UI_ACT_PROC(/obj/machinery/chemical_dispenser, ui_act_remove_recipe)
	LAZYREMOVE(saved_recipes, params["recipe"])
	. = TRUE

/// Old attack_ghost: view the interface unless broken. Never fell through.
/obj/machinery/chemical_dispenser/proc/chemical_dispenser_ghost_view(mob/user, obj/item/held, datum/interaction/interaction)
	if(!has_stat(BROKEN))
		tgui_interact(user)
	return TRUE

/datum/interaction/machine_hand/ungated/chemical_dispenser_use
	id = "chemical_dispenser_use"
	name = "Use"
	effect = /obj/machinery/chemical_dispenser/proc/interaction_use

/obj/machinery/chemical_dispenser/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_stat(BROKEN))
		return TRUE
	tgui_interact(user)
	return TRUE

OWN(/obj/machinery/chemical_dispenser, container, OWN_CONTAINED)
// Label -> installed cartridge (in contents); they go with the machine.
