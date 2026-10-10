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

CAPABILITIES(/obj/machinery/chemical_dispenser)
	rotatable()
	owns_one(nameof(container), /obj/item/reagent_containers)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(_recharge_reagents), gate = PROC_REF(operable), wakes_on = list(nameof(_recharge_reagents), STAT_OPERABLE))
	interface("ChemDispenser", observe = TRUE)
	extend("ui_observe", needs(req(PROC_REF(not_broken), silent = TRUE)))
	op("amount", ui_act("amount", arg("amount", num())), then(PROC_REF(ui_act_amount)))
	op("dispense", ui_act("dispense", arg("reagent", schema_text(4096))), then(PROC_REF(ui_act_dispense)))
	op("remove", ui_act("remove", arg("amount", num()), arg("reagent")), then(PROC_REF(ui_act_remove)))
	op("ejectBeaker", ui_act("ejectBeaker"), then(PROC_REF(ui_act_ejectbeaker)))
	op("import_config", ui_act("import_config", arg("config")), then(PROC_REF(ui_act_import_config)))
	op("record_recipe", ui_act("record_recipe"), then(PROC_REF(ui_act_record_recipe)))
	op("cancel_recording", ui_act("cancel_recording"), then(PROC_REF(ui_act_cancel_recording)))
	op("clear_recipes", ui_act("clear_recipes"),
		asks(/datum/prompt/choice, fields = list("question" = "Clear all recipes?", "title" = "Clear?", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "a1"),
		then(PROC_REF(ui_act_clear_recipes)))
	// the name, then (only when a recipe has that name) whether to overwrite it
	op("save_recording", ui_act("save_recording"),
		asks(/datum/prompt/text, fields = list("question" = "What do you want to name this recipe?", "title" = "Recipe Name?", "default" = "Recipe Name", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "a2"),
		asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(recipe_overwrite_question)), "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "a3", when = PROC_REF(recipe_name_taken)),
		then(PROC_REF(ui_act_save_recording)))
	op("dispense_recipe", ui_act("dispense_recipe", arg("recipe", schema_text(4096))), then(PROC_REF(ui_act_dispense_recipe)))
	op("remove_recipe", ui_act("remove_recipe", arg("recipe", schema_text(4096))), then(PROC_REF(ui_act_remove_recipe)))
	extend(TAG_UI, needs(req(PROC_REF(not_broken), silent = TRUE)))
	owns_many(nameof(cartridges), /obj/item/reagent_containers/chem_disp_cartridge)
	op("add_cartridge", item(/obj/item/reagent_containers/chem_disp_cartridge), label("Insert cartridge"), then(PROC_REF(cartridge_added)))
	// A chemical canister refills the cartridge under its label (it was the canister's afterattack, which the dispenser's ops now answer first).
	op("refill_cartridge", item(/obj/item/reagent_containers/chem_canister), label("Refill cartridge"), then(PROC_REF(canister_refill)))
	op("set_container", item(/obj/item/reagent_containers), when(req(list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food))), label("Set container"),
		needs(req(PROC_REF(no_container), silent = TRUE), req(PROC_REF(can_take_container))), then(PROC_REF(container_set)))
	op("remove_cartridge", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), label("Remove cartridge"), asks(/datum/prompt/choice, fields = list("question" = "Which cartridge would you like to remove?", "title" = "Chemical Dispenser", "choices" = computed(PROC_REF(cartridge_choices)), "timeout" = 0)), then(PROC_REF(cartridge_chosen)))

/obj/machinery/chemical_dispenser/proc/canister_refill(datum/act/op/A)
	var/obj/item/reagent_containers/chem_canister/C = A.held
	C.refill_dispenser(src, A.actor)
	return OP_OK

/obj/machinery/chemical_dispenser/Initialize(mapload)
	. = ..()
	if(spawn_cartridges)
		for(var/type in spawn_cartridges)
			add_cartridge(new type(src))

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

	if(!move_into(src, nameof(src.cartridges), C, user, key = C.label))
		return
	if(user)
		to_chat(user, span_notice("You add \the [C] to \the [src]."))

	sortTim(cartridges, GLOBAL_PROC_REF(cmp_text_asc)) // in place: the owned list keeps its identity
	SStgui.update_uis(src)

/obj/machinery/chemical_dispenser/proc/remove_cartridge(label)
	. = rel_take(src, nameof(cartridges), key = label)
	SStgui.update_uis(src)

/// The old attackby: a cartridge goes into a free slot under its label.
/obj/machinery/chemical_dispenser/proc/cartridge_added(datum/act/op/A)
	add_cartridge(A.held, A.actor)
	return OP_OK

MSG_DEF_SELF(chemical_dispenser/beakers_only, "This machine only accepts beakers.")
MSG_DEF_SELF(chemical_dispenser/not_open, "You don't see how it could dispense reagents into %I%.")
MSG_DEF_SELF(chemical_dispenser/no_fit, "You don't see how %I% could fit into it.")

/// No container is set on it.
/obj/machinery/chemical_dispenser/proc/no_container(datum/act/op/A)
	return (!container) ? null : /datum/msg/req_failed

/// The held container can be set on the dispenser.
/obj/machinery/chemical_dispenser/proc/can_take_container(datum/act/op/A)
	return container_refusal(A)

/// Why the held container can't be set on the dispenser, or null.
/obj/machinery/chemical_dispenser/proc/container_refusal(datum/act/op/A)
	var/obj/item/held = A.held
	if(!accept_drinking && istype(held, /obj/item/reagent_containers/food))
		return MSG(chemical_dispenser/beakers_only)
	if(!held?.is_open_container())
		return MSG(chemical_dispenser/not_open)
	if(istype(held, /obj/item/reagent_containers/glass/cooler_bottle))
		return MSG(chemical_dispenser/no_fit)
	return null

/// The old attackby: the container is set on the dispenser.
/obj/machinery/chemical_dispenser/proc/container_set(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/RC = A.held
	if(!move_into(src, nameof(src.container), RC, user))
		return OP_OK
	to_chat(user, span_notice("You set \the [RC] on \the [src]."))
	return OP_OK

/obj/machinery/chemical_dispenser/ui_title(mob/user)
	return ui_title

/// The window's data.
/obj/machinery/chemical_dispenser/ui_data(datum/act/eval/A)
	. = list()
	.["amount"] = amount
	.["glass"] = accept_drinking
	.["recordingRecipe"] = recording_recipe
	var/list/part = ui_data_part_chemical_dispenser(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/chemical_dispenser/proc/ui_data_part_chemical_dispenser(datum/act/eval/A)
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

/// Requirement: a broken dispenser ignores its buttons (silently, as the old ui_act_allowed() did).
/obj/machinery/chemical_dispenser/proc/not_broken(datum/act/op/A)
	return (!broken_now()) ? null : /datum/msg/req_silent

/// The save question's second step: a recipe of that name exists already.
/obj/machinery/chemical_dispenser/proc/recipe_name_taken(datum/act/op/A)
	return !!LAZYACCESS(saved_recipes, A.step_value("a2")) // ALLOW(reads): the saved recipes are read when the name is answered, never cached

/obj/machinery/chemical_dispenser/proc/recipe_overwrite_question(datum/act/op/A)
	return "\"[A.step_value("a2")]\" already exists, do you want to overwrite it?"

/obj/machinery/chemical_dispenser/proc/ui_act_amount(datum/act/op/A, amount_set)
	var/mob/user = A.actor
	add_fingerprint(user)
	amount = clamp(round(amount_set, 1), 0, 120) // round to nearest 1 and clamp 0 - 120
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_dispense(datum/act/op/A, reagent)
	var/mob/user = A.actor
	add_fingerprint(user)
	var/label = reagent
	if(recording_recipe)
		recording_recipe += list(list("id" = label, "amount" = amount))
	else if(LAZYACCESS(cartridges, label) && container && container.is_open_container())
		var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
		play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
		C.reagents.trans_to(container, amount)
		work_start(src)
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_remove(datum/act/op/A, amount_out, reagent)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!container || !amount_out || recording_recipe)
		return
	var/datum/reagents/R = container.reagents
	var/id = reagent
	if(amount_out > 0)
		R.remove_reagent(id, amount_out)
	else if(amount_out == -1) // Isolate
		R.isolate_reagent(id)
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_ejectbeaker(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(container)
		container.forceMove(get_turf(src))
		if(Adjacent(user)) // So the AI doesn't get a beaker somehow.
			user.put_in_hands(container)
		rel_take(src, nameof(container))
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_import_config(datum/act/op/A, config)
	var/mob/user = A.actor
	add_fingerprint(user)
	var/list/our_data = config
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

/obj/machinery/chemical_dispenser/proc/ui_act_record_recipe(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	recording_recipe = list()
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_cancel_recording(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	recording_recipe = null
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_clear_recipes(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(A.step_value("a1") == "Yes")
		saved_recipes = list()
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_save_recording(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	var/name = A.step_value("a2")
	if(LAZYACCESS(saved_recipes, name) && A.step_value("a3") != "Yes")
		return
	if(name && recording_recipe)
		for(var/list/L in recording_recipe)
			var/label = L["id"]
			// Verify this dispenser can dispense every chemical
			if(!LAZYACCESS(cartridges, label))
				visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
				to_chat(user, span_warning("[src] cannot find <b>[label]</b>!"))
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)
				return
		LAZYSET(saved_recipes, name, recording_recipe)
		recording_recipe = null
		. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_dispense_recipe(datum/act/op/A, recipe)
	var/mob/user = A.actor
	add_fingerprint(user)
	var/list/chemicals_to_dispense = LAZYACCESS(saved_recipes, recipe)
	if(!LAZYLEN(chemicals_to_dispense))
		return

	if(!recording_recipe)
		if(!container)
			to_chat(user, span_warning("There is no beaker in [src]."))
			return

		for(var/list/L in chemicals_to_dispense)
			var/label = L["id"]
			var/dispense_amount = L["amount"]

			var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
			if(!C)
				visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
				to_chat(user, span_warning("[src] cannot find <b>[label]</b>!"))
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)
				break

			// Allows copying recipes
			play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
			var/amount_actually_dispensed = C.reagents.trans_to(container, dispense_amount)
			work_start(src)
			if(dispense_amount != amount_actually_dispensed)
				visible_message(span_warning("[src] buzzes."), span_warning("You hear a faint buzz."))
				to_chat(user, span_warning("[src] was only able to dispense [amount_actually_dispensed ? amount_actually_dispensed : 0]u out of [dispense_amount]u requested of <b>[label]</b>!"))
				play_sfx(src, SFX_MACHINES_BUZZ_TWO, vary = TRUE)
				break
	else
		recording_recipe += chemicals_to_dispense
	. = TRUE

/obj/machinery/chemical_dispenser/proc/ui_act_remove_recipe(datum/act/op/A, recipe)
	var/mob/user = A.actor
	add_fingerprint(user)
	LAZYREMOVE(saved_recipes, recipe)
	. = TRUE

// Label -> installed cartridge (in contents); they go with the machine.

/// The cartridges the screwdriver's question offers, by label.
/obj/machinery/chemical_dispenser/proc/cartridge_choices(datum/act/A)
	return cartridges

/// The screwdriver's answer: that cartridge comes out.
/obj/machinery/chemical_dispenser/proc/cartridge_chosen(datum/act/op/A)
	var/obj/item/tool = A.held
	var/label = A.answer?.value
	if(!label)
		return OP_OK
	var/obj/item/reagent_containers/chem_disp_cartridge/cartridge = remove_cartridge(label)
	if(!cartridge)
		return OP_OK
	to_chat(A.actor, span_notice("You remove \the [cartridge] from \the [src]."))
	cartridge.forceMove(loc)
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK
