#define SYNTHESIZER_MAX_CARTRIDGES 40
#define SYNTHESIZER_MAX_RECIPES 20
#define SYNTHESIZER_MAX_QUEUE 40
#define RECIPE_MAX_STRING 240
#define RECIPE_MAX_STEPS 20

// Recipes are stored as a list which alternates between chemical id's and volumes to add, e.g. 1 = 'Carbon', 2 = 20, 3 = 'Silicon', 4 = 20
/obj/machinery/chemical_synthesizer
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 4 SECONDS
	name = "chemical synthesizer"
	desc = "A programmable machine capable of automatically synthesizing medicine."
	icon = 'icons/obj/chemical_ch.dmi'
	icon_state = "synth_idle_bottle"

	use_power = USE_POWER_IDLE
	power_channel = EQUIP
	idle_power_usage = 100
	active_power_usage = 150
	anchored = TRUE
	unacidable = TRUE
	density = TRUE
	panel_open = TRUE

	var/busy = FALSE
	var/production_mode = FALSE // Toggle between click-step input and comma-delineated text input for creating recipes.
	var/use_catalyst = TRUE // Determines whether or not the catalyst will be added to reagents while processing a recipe.
	var/stalled = FALSE  // Required for emergency stop to interrupt on-going recipes.
	var/drug_substance = 1 // Controls which form medicine takes (bottle, pill, etc). 1 for bottle, 2 for pill, 3 for patch.
	var/delay_modifier = 4 // This is multiplied by the volume of a step to determine how long each step takes. Bigger volume = slower.
	var/obj/item/reagent_containers/glass/catalyst = null // This is where the user adds catalyst. Usually phoron.

	var/bottle_icon = 4 // Determines icon states of bottles, pills, and patches.
	var/pill_icon = 2
	var/patch_icon = 2

	// ALLOW(instance_list): d: saved recipes; many call sites
	var/list/recipes = list() // This holds chemical recipes up to a maximum determined by SYNTHESIZER_MAX_RECIPES. Two-dimensional.
	// ALLOW(instance_list): d: synthesizer build queue, many call sites index it
	var/list/queue = list() // This holds the recipe id's for queued up recipes.
	var/list/catalyst_ids // This keeps track of the chemicals in the catalyst to remove before bottling.
	// ALLOW(instance_list): d: cartridges are spawned into it at init
	var/list/cartridges = list() // Associative, label -> cartridge

	var/static/list/spawn_cartridges = list(
			/obj/item/reagent_containers/chem_disp_cartridge/hydrogen,
			/obj/item/reagent_containers/chem_disp_cartridge/lithium,
			/obj/item/reagent_containers/chem_disp_cartridge/carbon,
			/obj/item/reagent_containers/chem_disp_cartridge/nitrogen,
			/obj/item/reagent_containers/chem_disp_cartridge/oxygen,
			/obj/item/reagent_containers/chem_disp_cartridge/fluorine,
			/obj/item/reagent_containers/chem_disp_cartridge/sodium,
			/obj/item/reagent_containers/chem_disp_cartridge/aluminum,
			/obj/item/reagent_containers/chem_disp_cartridge/silicon,
			/obj/item/reagent_containers/chem_disp_cartridge/phosphorus,
			/obj/item/reagent_containers/chem_disp_cartridge/sulfur,
			/obj/item/reagent_containers/chem_disp_cartridge/chlorine,
			/obj/item/reagent_containers/chem_disp_cartridge/potassium,
			/obj/item/reagent_containers/chem_disp_cartridge/iron,
			/obj/item/reagent_containers/chem_disp_cartridge/copper,
			/obj/item/reagent_containers/chem_disp_cartridge/mercury,
			/obj/item/reagent_containers/chem_disp_cartridge/radium,
			/obj/item/reagent_containers/chem_disp_cartridge/water,
			/obj/item/reagent_containers/chem_disp_cartridge/ethanol,
			/obj/item/reagent_containers/chem_disp_cartridge/sugar,
			/obj/item/reagent_containers/chem_disp_cartridge/sacid,
			/obj/item/reagent_containers/chem_disp_cartridge/tungsten,
			/obj/item/reagent_containers/chem_disp_cartridge/calcium
		)

	var/process_tick = 0
	var/list/dispense_reagents = list( // ALLOW(instance_list): d: edited in place per instance (1 writers)
		REAGENT_ID_HYDROGEN, REAGENT_ID_LITHIUM, REAGENT_ID_CARBON, REAGENT_ID_NITROGEN, REAGENT_ID_OXYGEN, REAGENT_ID_FLUORINE, REAGENT_ID_SODIUM,
		REAGENT_ID_ALUMINIUM, REAGENT_ID_SILICON, REAGENT_ID_PHOSPHORUS, REAGENT_ID_SULFUR, REAGENT_ID_CHLORINE, REAGENT_ID_POTASSIUM, REAGENT_ID_IRON,
		REAGENT_ID_COPPER, REAGENT_ID_MERCURY, REAGENT_ID_RADIUM, REAGENT_ID_WATER, REAGENT_ID_ETHANOL, REAGENT_ID_SUGAR, REAGENT_ID_SACID, REAGENT_ID_TUNGSTEN, REAGENT_ID_CALCIUM
		)

OM_FIELD(/obj/machinery/chemical_synthesizer, _recharge_reagents, TRUE, CHANGE_MACHINE_SETTINGS)
/// Refills its cartridges while it recharges at all (full, it sleeps until a cartridge is drawn or added).
DECLARE_PERIODIC_WHILE(/obj/machinery/chemical_synthesizer, MACHINE_PIPELINE, "_recharge_reagents")

// The reagents datum acts as the machine's reaction vessel.
DECLARE_REAGENTS(/obj/machinery/chemical_synthesizer, 600, null)
DECLARE_DEFAULT_CHILD(/obj/machinery/chemical_synthesizer, "catalyst", /obj/item/reagent_containers/glass/beaker)

/obj/machinery/chemical_synthesizer/Initialize(mapload)
	. = ..()

	if(spawn_cartridges)
		for(var/type in spawn_cartridges)
			add_cartridge(new type(src))
		set_panel_open(FALSE)

	var/obj/item/paper/P = new /obj/item/paper(get_turf(src))
	P.name = "Synthesizer Instructions"
	P.desc = "A photocopy of a handwritten note."
	P.info = {"Hello there! This device is a new NanoTrasen product currently being shipped to select facilities \
	for internal testing! We haven't finished the instruction manual yet so each unit shipped with this pamphlet \
	(I really hope you can read my handwriting). This machine is a programmable chemical synthesizer which, if used \
	correctly, will allow you to queue up some recipes and go work on something else while the medicine manufactures. \
	It's slower than doing things by hand but it also keeps your hands free! And yes, it bottles automatically. \
	<BR><BR>To get started, you need to program some recipes. The machine has two modes for this: tutorial and production. \
	Tutorial is intended to teach you how recipes work, or to create recipes for later use with production mode. This one \
	should be self-explanatory, just follow the prompts. Production mode allows you to rapidly import recipes in CSV format. \
	If I've lost you, just keep reading; once you give it a name and tell the machine how many steps are in the recipe, just \
	input the recipe as a comma-separated string of chemical names and volumes to be added, like "Chem1,10,Chem2,20,... \
	<BR><BR>If that still doesn't make sense, I've included an example for Dylovene at the bottom. Also, don't include \
	catalyst reagents in the recipe, read below for that part. Also also, remember that chemical names are case sensitive and \
	cartridge names are usually Capitalized Like These Words (AND FOR THE LOVE OF GOD KEVIN, STOP CHANGING THE NAMES ON THE \
	LABELS WHEN THE CHEMISTS AREN'T LOOKING IT ISN'T FUNNY ANYMORE). \
	<BR><BR>Next important concept is the catalyst, intended for catalyst reagents (usually phoron). When the catalyst option is \
	enabled, whatever is in the catalyst bottle gets added to the reaction chamber before synthesis begins. When the \
	recipe is done, it extracts the catalyst, bottles whatever you made, then adds the catalyst back before starting \
	the next recipe in the queue. It's up to you to make sure no unwanted side reactions happen, and yes, this means \
	you cannot queue up catalyst recipes with recipes ruined by the catalyst. Maybe add "NO CAT" or something to the \
	name for recipes like that? \
	<BR><BR>And that's the really important stuff. Remember you can export recipes for later shifts, just copy the \
	output into your PDA or something. Oh, and stalling. Say you're missing a cartridge or the vessel is full (the \
	capacity is [src.reagents.maximum_volume]) or you press the emergency stop button. The machine will stall, \
	clearing the temporary memory. To get it started again, you just need to empty the vessel. Anyway, here's \
	example recipe. \
	<BR><BR> Name: Dylovene (60u) \
	<BR> Number of steps: 3 \
	<BR> Recipe string: Silicon,20,Nitrogen,20,Potassium,20"}

/obj/machinery/chemical_synthesizer/examine(mob/user)
	. = ..()
	if(panel_open)
		. += "It has [length(cartridges)] cartridges installed, and has space for [SYNTHESIZER_MAX_CARTRIDGES - length(cartridges)] more."

DECLARE_APPEARANCE_PROC(/obj/machinery/chemical_synthesizer, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/chemical_synthesizer/appearance_overlays()
	. = list()
	underlays.Cut()
	if(has_stat(BROKEN))
		icon_state = "synth_broken"
		return .
	if(has_stat(NOPOWER))
		icon_state = "synth_off"
		return .
	if(!busy)
		if(catalyst)
			icon_state = "synth_idle_bottle"
		else
			icon_state = "synth_idle"
	else
		icon_state = "synth_working"
	if(catalyst) // All underlay icon_states requires the catalyst bottle to be present, so this works as a check.
		if(catalyst.reagents.reagent_list.len)
			var/image/cat_filling = image(icon, src, "synth_catalyst", -1)
			cat_filling.color = catalyst.reagents.get_color()
			underlays += cat_filling
		if(src.reagents.reagent_list.len)
			var/image/ves_filling = image(icon, src, "synth_vessel", -2)
			ves_filling.color = src.reagents.get_color()
			underlays += ves_filling

/obj/machinery/chemical_synthesizer/proc/add_cartridge(obj/item/reagent_containers/chem_disp_cartridge/C, mob/user)
	if(!panel_open)
		if(user)
			to_chat(user, span_warning("The panel is locked!"))
		return

	if(!istype(C))
		if(user)
			to_chat(user, span_warning("\The [C] will not fit in \the [src]!"))
		return

	if(length(cartridges) >= SYNTHESIZER_MAX_CARTRIDGES)
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

	if(!own_put(src, nameof(src.cartridges), C.label, C, user = user, into = TRUE))
		return
	if(user)
		to_chat(user, span_notice("You add \the [C] to \the [src]."))

	sortTim(cartridges, GLOBAL_PROC_REF(cmp_text_asc)) // in place: the owned list keeps its identity
	MACHINE_WAKE(src)
	SStgui.update_uis(src)

/obj/machinery/chemical_synthesizer/proc/remove_cartridge(label)
	. = own_take_member(src, nameof(cartridges), label)
	SStgui.update_uis(src)

/obj/machinery/chemical_synthesizer/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_OBSERVER("View", PROC_REF(chem_synthesizer_ghost_view)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_item/chem_synthesizer_add_cartridge,
		/datum/interaction/machine_item/chem_synthesizer_add_catalyst,
		/datum/interaction/machine_hand/ungated/chem_synthesizer_use,
	)
	..()

/datum/interaction/machine_item/chem_synthesizer_add_cartridge
	id = "chem_synthesizer_add_cartridge"
	name = "Insert cartridge"
	held_type = /obj/item/reagent_containers/chem_disp_cartridge
	effect = /obj/machinery/chemical_synthesizer/proc/interaction_add_cartridge

/obj/machinery/chemical_synthesizer/proc/interaction_add_cartridge(mob/user, obj/item/reagent_containers/chem_disp_cartridge/W, datum/interaction/interaction)
	add_cartridge(W, user)
	return TRUE

// We don't need a busy check here as the catalyst slot must be occupied for the machine to function.
/datum/interaction/machine_item/chem_synthesizer_add_catalyst
	id = "chem_synthesizer_add_catalyst"
	name = "Set catalyst"
	held_type = /obj/item/reagent_containers/glass
	effect = /obj/machinery/chemical_synthesizer/proc/interaction_add_catalyst
	also_requires = list(
		REQ_FIELD_NOT("catalyst"),
		REQ_BECAUSE(REQ_FIELD("operable"), "the clamp will not secure the catalyst while the machine is down"),
		REQ_TARGET_STATE(/obj/machinery/chemical_synthesizer/proc/can_extract_from),
	)

/// Requirement: the held container must be open for reagents to be drawn from it.
/obj/machinery/chemical_synthesizer/proc/can_extract_from(mob/user, atom/target, obj/item/held)
	return held?.is_open_container() ? TRUE : "you don't see how it could extract reagents from [held]"

/obj/machinery/chemical_synthesizer/proc/interaction_add_catalyst(mob/user, obj/item/reagent_containers/RC, datum/interaction/interaction)

	if(!own_set(src, nameof(src.catalyst), RC, user = user))
		return TRUE
	to_chat(user, span_notice("You set \the [RC] on \the [src]."))
	update_icon()

	return TRUE

/obj/machinery/chemical_synthesizer/wrench_act(mob/user, obj/item/tool)
	if(busy)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/chemical_synthesizer/screwdriver_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ..()
	var/label = rerun_ask(user, "a1", TYPE_PROC_REF(/atom, screwdriver_act), args, /datum/om/prompt/choice, message = "Which cartridge would you like to remove?", title = "Chemical Synthesizer", choices = cartridges)
	if(!label)
		return ITEM_INTERACT_BLOCKING
	var/obj/item/reagent_containers/chem_disp_cartridge/cartridge = remove_cartridge(label)
	if(!cartridge)
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You remove \the [cartridge] from \the [src]."))
	cartridge.forceMove(loc)
	playsound(src, tool.usesound, 50, TRUE)
	return ITEM_INTERACT_SUCCESS

// More stolen chemical_dispenser code.
/// Refills its cartridges every 15 frames while any is short; full (or not recharging) it sleeps
/// until a cartridge is drawn from or added.
/obj/machinery/chemical_synthesizer/machine_step()
	if(!operable())
		return sleep_until_powered()
	var/short = FALSE
	for(var/label in cartridges)
		var/obj/item/reagent_containers/chem_disp_cartridge/cart = LAZYACCESS(cartridges, label)
		if(cart && cart.reagents.total_volume < cart.reagents.maximum_volume)
			short = TRUE
			break
	if(!short)
		return PROCESS_KILL
	if(--process_tick <= 0)
		process_tick = 15
		. = 0
		for(var/id in dispense_reagents)
			var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
			if(!R)
				stack_trace("[src] at [x],[y],[z] failed to find reagent '[id]'!")
				dispense_reagents -= id
				continue
			var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, R.name)
			if(C && C.reagents.total_volume < C.reagents.maximum_volume)
				var/to_restore = min(C.reagents.maximum_volume - C.reagents.total_volume, 5)
				use_power(to_restore * 500)
				C.reagents.add_reagent(id, to_restore)
				. = 1
		if(.)
			SStgui.update_uis(src)

DECLARE_UI(/obj/machinery/chemical_synthesizer, "ChemSynthesizer")

UI_DATA_REPLACE(/obj/machinery/chemical_synthesizer, "busy:num", "production_mode", "panel_open:num", "use_catalyst", "drug_substance:num", "bottle_icon:num", "pill_icon:num", "patch_icon:num", "merge:ui_data_obj_machinery_chemical_synthesizer{queue:list,recipes:list,rxn_vessel:list,catalyst:num,catalyst_reagents:list,catalystCurrentVolume:num,catalystMaxVolume:num,chemicals:num,modal:unknown}")

/// The computed part of /obj/machinery/chemical_synthesizer's window data (declared on its UI_DATA row).
/obj/machinery/chemical_synthesizer/proc/ui_data_obj_machinery_chemical_synthesizer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()


	var/list/tmp_queue = list()
	for(var/i = 1, i <= queue.len, i++)
		tmp_queue.Add(list(list("name" = queue[i], "index" = i))) // Thanks byond
	data["queue"] = tmp_queue

	// Convert the recipes list into an array of strings. The UI does not need the associative list attached to each string.
	var/list/tmp_recipes = list()
	for(var/i = 1, i <= recipes.len, i++)
		tmp_recipes.Add(list(list("name" = recipes[i])))
	data["recipes"] = tmp_recipes


	// Read data from the reaction vessel.
	var/list/vessel_reagents_list = list()
	data["rxn_vessel"] = vessel_reagents_list
	for(var/datum/reagent/R in src.reagents.reagent_list)
		vessel_reagents_list[++vessel_reagents_list.len] = list("name" = R.name, "volume" = R.volume, "description" = R.description, "id" = R.id)

	// Read data from the catalyst, if present.
	data["catalyst"] = catalyst ? 1 : 0
	if(catalyst)
		var/list/catalyst_reagents_list = list()
		data["catalyst_reagents"] = catalyst_reagents_list
		for(var/datum/reagent/R in catalyst.reagents.reagent_list)
			catalyst_reagents_list[++catalyst_reagents_list.len] = list("name" = R.name, "volume" = R.volume, "description" = R.description, "id" = R.id)

	if(catalyst)
		data["catalystCurrentVolume"] = catalyst.reagents.total_volume
		data["catalystMaxVolume"] = catalyst.reagents.maximum_volume
	else
		data["catalystCurrentVolume"] = null
		data["catalystMaxVolume"] = null

	var/chemicals[0]
	for(var/label in cartridges)
		var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
		chemicals.Add(list(list("title" = label, "id" = label, "amount" = C.reagents.total_volume))) // list in a list because Byond merges the first list
	data["chemicals"] = chemicals

	data["modal"] = tgui_modal_data(src)

	return data

/obj/machinery/chemical_synthesizer/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(user)
	return TRUE

UI_ACT(/obj/machinery/chemical_synthesizer, "start_queue", ui_act_start_queue)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_start_queue)
	. = TRUE
	// Start up the queue.
	if(!busy)
		start_queue(user)

UI_ACT(/obj/machinery/chemical_synthesizer, "rem_queue", ui_act_rem_queue, UI_ARG_NUM("q_index"))
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_rem_queue)
	. = TRUE
	// Remove a single entry from the queue. Sanity checks also prevent removing the first entry if the machine is busy though UI should already prevent that.
	var/index = params["q_index"]
	if(!isnum(index) || !ISINTEGER(index) || !istype(queue) || (index<1 || index>length(queue) || (busy && index == 1)))
		return
	queue -= queue[index]

UI_ACT(/obj/machinery/chemical_synthesizer, "clear_queue", ui_act_clear_queue)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_clear_queue)
	. = TRUE
	// Remove all entries from the queue except the currently processing recipe.
	var/confirm = act_ask(user, action, params, ui, "a1", /datum/om/prompt/choice/alert, message = "Are you sure you want to clear the running queue?", title = "Confirm", choices = list("No", "Yes"))
	if(isnull(confirm))
		return
	if(confirm == "Yes")
		if(busy)
			// Oh no, I've broken code convention to remove all entries but the first.
			for(var/i = queue.len, i >= 2, i--)
				queue -= queue[i]
		else
			queue = list()

UI_ACT(/obj/machinery/chemical_synthesizer, "eject_catalyst", ui_act_eject_catalyst)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_eject_catalyst)
	. = TRUE
	// Removes the catalyst bottle from the machine.
	if(!busy && catalyst)
		catalyst.forceMove(get_turf(src))
		own_take(src, nameof(/obj/machinery/chemical_synthesizer::catalyst))
		update_icon()

UI_ACT(/obj/machinery/chemical_synthesizer, "toggle_catalyst", ui_act_toggle_catalyst)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_toggle_catalyst)
	. = TRUE
	// Decides if the machine uses the catalyst.
	if(!busy)
		use_catalyst = !use_catalyst

UI_ACT(/obj/machinery/chemical_synthesizer, "emergency_stop", ui_act_emergency_stop)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_emergency_stop)
	. = TRUE
	// Stops everything if that's desirable for some reason.
	if(busy)
		var/confirm = act_ask(user, action, params, ui, "a2", /datum/om/prompt/choice/alert, message = "Are you sure you want to stall the machine?", title = "Confirm", choices = list("Yes", "No"))
		if(isnull(confirm))
			return
		if(confirm == "Yes")
			stalled = TRUE

UI_ACT(/obj/machinery/chemical_synthesizer, "bottle_product", ui_act_bottle_product)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_bottle_product)
	. = TRUE
	// Bottles the reaction mixture if stalled.
	if(!busy)
		bottle_product()

UI_ACT(/obj/machinery/chemical_synthesizer, "panel_toggle", ui_act_panel_toggle)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_panel_toggle)
	. = TRUE
	// Opens/closes the panel.
	if(!busy)
		set_panel_open(!panel_open)

UI_ACT(/obj/machinery/chemical_synthesizer, "mode_toggle", ui_act_mode_toggle)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_mode_toggle)
	. = TRUE
	// Toggles production mode.
	production_mode = !production_mode

UI_ACT(/obj/machinery/chemical_synthesizer, "add_recipe", ui_act_add_recipe)
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_add_recipe)
	. = TRUE
	// Allows the user to add a recipe. Kinda vital for this machine to do anything useful.
	if(recipes.len >= SYNTHESIZER_MAX_RECIPES)
		to_chat(user, span_warning("Maximum recipes exceeded!"))
		return
	if(!production_mode)
		babystep_recipe(user)
	else
		import_recipe(user)

UI_ACT(/obj/machinery/chemical_synthesizer, "rem_recipe", ui_act_rem_recipe, UI_ARG_TEXT("rm_index"))
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_rem_recipe)
	. = TRUE
	// Allows the user to remove recipes while the machine is idle.
	if(!busy)
		var/confirm = act_ask(user, action, params, ui, "a3", /datum/om/prompt/choice/alert, message = "Are you sure you want to remove this recipe?", title = "Confirm", choices = list("No", "Yes"))
		if(isnull(confirm))
			return
		if(confirm == "Yes")
			var/index = params["rm_index"]
			if(index in recipes)
				recipes.Remove(list(index)) // Fuck off Byond.
	else
		to_chat(user, span_warning("You cannot remove recipes while the machine is running!"))

UI_ACT(/obj/machinery/chemical_synthesizer, "exp_recipe", ui_act_exp_recipe, UI_ARG_TEXT("exp_index"))
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_exp_recipe)
	. = TRUE
	// Allows the user to export recipes to chat formatted for easy importing.
	var/index = params["exp_index"]
	export_recipe(user, index)

UI_ACT(/obj/machinery/chemical_synthesizer, "add_queue", ui_act_add_queue, UI_ARG_TEXT("qa_index"))
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_add_queue)
	. = TRUE
	// Adds recipes to the queue.
	if(queue.len >= SYNTHESIZER_MAX_QUEUE)
		to_chat(user, span_warning("Synthesizer queue full!"))
		return
	var/index = params["qa_index"]
	// If you forgot, this is a string returned by the user pressing the "add to queue" button on a recipe.
	if(index in recipes)
		queue[++queue.len] = index

UI_ACT(/obj/machinery/chemical_synthesizer, "drug_form", ui_act_drug_form, UI_ARG_NUM("drug_index"))
UI_ACT_PROC(/obj/machinery/chemical_synthesizer, ui_act_drug_form)
	. = TRUE
	// Toggles between bottles, pills, and patches.
	drug_substance = params["drug_index"]


/obj/machinery/chemical_synthesizer/ui_modal_opened(mob/user, id, list/arguments, datum/tgui/ui, datum/tgui_state/state)
	. = TRUE
	switch(id)
		if("change_pill_style")
			var/list/choices = list()
			for(var/i = 1 to MAX_PILL_SPRITE)
				choices += "chem_master32x32 pill[i]"
			tgui_modal_bento_spritesheet(src, id, "Please select the new style for pills:", null, arguments, pill_icon, choices)
		if("change_patch_style")
			var/list/choices = list()
			for(var/i = 1 to MAX_PATCH_SPRITE)
				choices += "chem_master32x32 patch[i]"
			tgui_modal_bento_spritesheet(src, id, "Please select the new style for patches:", null, arguments, patch_icon, choices)
		if("change_bottle_style")
			var/list/choices = list()
			for(var/i = 1 to MAX_BOTTLE_SPRITE)
				choices += "chem_master32x32 bottle-[i]"
			tgui_modal_bento_spritesheet(src, id, "Please select the new style for bottles:", null, arguments, bottle_icon, choices)
		else
			return FALSE

/obj/machinery/chemical_synthesizer/ui_modal_answered(mob/user, id, answer, list/arguments, datum/tgui/ui, datum/tgui_state/state)
	. = TRUE
	switch(id)
		if("change_pill_style")
			var/new_style = CLAMP(text2num(answer) || 0, 0, MAX_PILL_SPRITE)
			if(!new_style)
				return
			pill_icon = new_style
		if("change_patch_style")
			var/new_style = CLAMP(text2num(answer) || 0, 0, MAX_PATCH_SPRITE)
			if(!new_style)
				return
			patch_icon = new_style
		if("change_bottle_style")
			var/new_style = CLAMP(text2num(answer) || 0, 0, MAX_BOTTLE_SPRITE)
			if(!new_style)
				return
			bottle_icon = new_style
		else
			return FALSE
/// Old attack_ghost: view the interface while it works. Never fell through.
/obj/machinery/chemical_synthesizer/proc/chem_synthesizer_ghost_view(mob/user, obj/item/held, datum/interaction/interaction)
	if(operable())
		tgui_interact(user)
	return TRUE

/// Old attack_hand (never called ..()).
/datum/interaction/machine_hand/ungated/chem_synthesizer_use
	id = "chem_synthesizer_use"
	name = "Use"
	effect = /obj/machinery/chemical_synthesizer/proc/interaction_use

/obj/machinery/chemical_synthesizer/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/chemical_synthesizer/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet/chem_master),
	)

// This proc is lets users create recipes step-by-step and exports a comma delineated list to chat. It's intended to teach how to use the machine.
/obj/machinery/chemical_synthesizer/proc/babystep_recipe(mob/user)
	// Each answer re-runs this proc; steps are keyed by their number.
	var/answer = rerun_ask(user, "name", PROC_REF(babystep_recipe), args, /datum/om/prompt/text, message = "Name your recipe. Consider including the output volume.", title = "Recipe naming")
	if(isnull(answer))
		return
	var/rec_name = sanitizeSafe(answer)
	if(!rec_name || (rec_name in recipes)) // Code requires each recipe to have a unique name.
		to_chat(user, "Please provide a unique recipe name!")
		return

	var/step_count = rerun_ask(user, "steps", PROC_REF(babystep_recipe), args, /datum/om/prompt/number, message = "How many steps does your recipe contain ([RECIPE_MAX_STEPS] max)?", title = "Steps", default = 1, max = RECIPE_MAX_STEPS, min = 1)
	if(isnull(step_count))
		return
	var/steps = 2 * step_count
	if(!steps)
		to_chat(user, "Please input a valid number of steps!")
		return

	var/list/new_rec = list() // This holds the actual recipe.
	for(var/i = 1, i < steps, i += 2) // For the user, 1 step is both text and volume. For list arithmetic, that's 2 steps.
		var/label = rerun_ask(user, "label[i]", PROC_REF(babystep_recipe), args, /datum/om/prompt/choice, message = "Which chemical would you like to use?", title = "Chemical Synthesizer", choices = cartridges)
		if(isnull(label))
			return
		if(!label)
			to_chat(user, "Please select a chemical!")
			return
		new_rec[++new_rec.len] = label // Add the reagent ID.
		var/amount = rerun_ask(user, "amount[i]", PROC_REF(babystep_recipe), args, /datum/om/prompt/number, message = "How much of the chemical would you like to add?", title = "Volume", default = 1, max = src.reagents.maximum_volume, min = 1)
		if(isnull(amount))
			return
		if(!amount)
			to_chat(user, "Please select a volume!")
			return
		new_rec[++new_rec.len] = amount // Add the amount of reagent.
	if(recipes.len >= SYNTHESIZER_MAX_RECIPES || (rec_name in recipes))
		return

	recipes[rec_name] = new_rec
	SStgui.update_uis(src)
	export_recipe(user, rec_name) // Now export the recipe to the user's chatbox formatted for import_recipe().
	return

// This proc allows users to copy-paste a comma delineated list to create a recipe. The recipe will cause a stall() if formatted incorrectly.
/obj/machinery/chemical_synthesizer/proc/import_recipe(mob/user)
	var/_answer_a2 = rerun_ask(user, "a2", PROC_REF(import_recipe), args, /datum/om/prompt/text, message = "Name your recipe. Consider including the output volume.", title = "Recipe naming", max_length = MAX_NAME_LEN)
	if(isnull(_answer_a2))
		return
	var/rec_name = sanitizeSafe(_answer_a2, MAX_NAME_LEN)
	if(!rec_name || (rec_name in recipes)) // Code requires each recipe to have a unique name.
		to_chat(user, "Please provide a unique recipe name!")
		return

	var/rec_input = rerun_ask(user, "a3", PROC_REF(import_recipe), args, /datum/om/prompt/text, message = "Input your recipe as 'Chem1,vol1,Chem2,vol2,...'", title = "Import recipe")
	if(isnull(rec_input))
		return
	if(!rec_input || (length(rec_input) > RECIPE_MAX_STRING) || !findtext(rec_input, ",")) // The smallest possible recipe will contain 1 comma.
		to_chat(user, "Invalid input or recipe max length exceeded!")
		return

	rec_input = trim(rec_input) // Sanitize.
	var/list/new_rec = list() // This holds the actual recipe.
	var/vol = FALSE // This tracks if the next step is a chemical name or a volume.
	var/index = findtext(rec_input, ",") // This tracks the delineation index in the user-provided string. Should never be null at this point.
	var/i = 1 // This tracks the index for new_rec, the actual list which gets added to recipes[rec_name].
	while(index) // Alternates between text strings and numbers. When false, the rest of rec_input is the final step.
		new_rec[++new_rec.len] = copytext(rec_input, 1, index)
		if(vol)
			new_rec[i] = text2num(new_rec[i]) // If it's a volume step, convert to a number.
			vol = FALSE
		else
			vol = TRUE
		i++
		rec_input = copytext(rec_input, index + 1) // Trim previous substrings from rec_input.
		index = findtext(rec_input, ",")

	if(rec_input) // The remainder of rec_input should be the final volume step of the recipe. The if() is a sanity check.
		new_rec[++new_rec.len] = text2num(rec_input)

	recipes[rec_name] = new_rec // Finally, add the recipe to the recipes list.
	SStgui.update_uis(src)
	return

// This proc exports stored recipes to the user's chatbox formatted as a comma delineated list for use with import_recpe()
/obj/machinery/chemical_synthesizer/proc/export_recipe(mob/user, rec_name)
	var/list/export = recipes[rec_name]
	if(!export)
		return
	var/display_txt = export.Join(",") // This converts the entire list into a CSV string.
	to_chat(user, "[display_txt]")

// This proc handles adding the catalyst starting the synthesizer's queue.
/obj/machinery/chemical_synthesizer/proc/start_queue(mob/user)
	if(stalled) // Incase SOMEHOW this var is true when the machine isn't running.
		stalled = FALSE

	if(!operable())
		return

	if(!queue)
		to_chat(user, "You can't start an empty queue!")
		return

	if(!catalyst)
		to_chat(user, "Place a bottle in the catalyst slot before starting the queue!")
		return

	if(panel_open)
		to_chat(user, "Close the panel before starting the queue!")
		return

	if(reagents.total_volume)
		to_chat(user, "Empty the reaction vessel before starting the queue!")
		return

	busy = TRUE
	set_use_power(USE_POWER_ACTIVE)
	if(use_catalyst)
		// Populate the list of catalyst chems. This is important when it's time to bottle_product().
		for(var/datum/reagent/chem in catalyst.reagents.reagent_list)
			LAZYADD(catalyst_ids, chem.id)

		// Transfer the catalyst to the synthesizer's reagent holder.
		catalyst.reagents.trans_to_holder(src.reagents, catalyst.reagents.total_volume)

	// Start the first recipe in the queue, starting with step 1.
	update_icon()
	follow_recipe(queue[1], 1)


// This proc controls the timing for each step in a reaction. Step is the index for the current chem of our recipe, step + 1 is the volume of said chem.
/obj/machinery/chemical_synthesizer/proc/follow_recipe(r_id, step as num)
	if(stalled) // Emergency stop if() check.
		stalled = FALSE
		stall()
		return

	if(!operable())
		stall()
		return

	if(!step)
		step = 1

	// The time between each step is the volume required by a step multiplied by the delay_modifier (in ticks/deciseconds).
	om_after(src, recipes[r_id][step + 1] * delay_modifier, PROC_REF(perform_reaction), r_id, step)

// This proc carries out the actual steps in each reaction.
/obj/machinery/chemical_synthesizer/proc/perform_reaction(r_id, step as num)
	if(stalled) // Emergency stop if() check.
		stalled = FALSE
		stall()
		return

	if(!operable())
		stall()
		return

	//Let's store these as temporary variables to make the code more readable.
	var/label = recipes[r_id][step]
	var/quantity = recipes[r_id][step+1]

	// If we're missing a cartridge somehow or lack space for the next step, stall. It's now up to the chemist to fix this.
	if(!LAZYACCESS(cartridges, label))
		visible_message(span_warning("The [src] beeps loudly, flashing a 'cartridge missing' error!"), "You hear loud beeping!")
		play_sfx(src, SFX_WEAPONS_SMG_EMPTY_ALARM)
		stall()
		return

	if(quantity > reagents.get_free_space())
		visible_message(span_warning("The [src] beeps loudly, flashing a 'maximum volume exceeded' error!"), "You hear loud beeping!")
		play_sfx(src, SFX_WEAPONS_SMG_EMPTY_ALARM)
		stall()
		return

	// If there isn't enough reagent left for this step, try again in a minute.
	var/obj/item/reagent_containers/chem_disp_cartridge/C = LAZYACCESS(cartridges, label)
	if(quantity > C.reagents.total_volume)
		visible_message(span_notice("The [src] flashes an 'insufficient reagents' warning."))
		// ALLOW(sys_om_after_rearm): a one-minute retry of the current step of a finite recipe sequence (step advances further down this proc), not periodic work over a state
		om_after(src, 1 MINUTE, PROC_REF(perform_reaction), r_id, step)
		return

	// After all this mess of code, we reach the line where the magic happens.
	C.reagents.trans_to_holder(src.reagents, quantity)
	MACHINE_WAKE(src) // a cartridge to refill
	update_icon() // Update underlays.
	play_sfx(src, SFX_MACHINES_HPLC_BINARY_PUMP)

	// Advance to the next step in the recipe. If this is outside of the recipe's index, we're finished. Otherwise, proceed to next step.
	step += 2
	var/list/tmp = recipes[r_id]
	if(step > tmp.len)

		// First extract the catalyst(s), if any remain.
		if(use_catalyst)
			for(var/chem in catalyst_ids)
				var/amount = reagents.get_reagent_amount(chem)
				reagents.trans_id_to(catalyst, chem, amount)

		// Add a delay of 1 tick per unit of reagent. Clear the catalyst_ids.
		catalyst_ids = list()
		var/delay = reagents.total_volume
		update_icon() // Update the icon first to remove underlays, then switch to the new icon_state.
		icon_state = "synth_finished"
		om_after(src, delay, PROC_REF(bottle_product), r_id)

	else
		follow_recipe(r_id, step)

// Now that we're done, bottle up the product.
/obj/machinery/chemical_synthesizer/proc/bottle_product(r_id)
	if(!operable())
		stall()
		return

	if(!r_id)
		r_id = "[reagents.get_master_reagent_name()]"

	// Copy-pasta go brr
	switch(drug_substance)
		if(2) // Pills
			while(reagents.total_volume)
				var/obj/item/reagent_containers/pill/P= new(src.loc)
				P.name = "[r_id]"
				P.pixel_x = rand(-7, 7) // random position
				P.pixel_y = rand(-7, 7)
				P.icon_state = "pill[pill_icon]"
				reagents.trans_to_obj(P, min(reagents.total_volume, MAX_UNITS_PER_PILL))
				if(P.icon_state in list("pill1", "pill2", "pill3", "pill4")) // if using greyscale, take colour from reagent
					P.color = P.reagents.get_color()
				P.update_icon()

		if(3) // Patches
			while(reagents.total_volume)
				var/obj/item/reagent_containers/pill/patch/P= new(src.loc)
				P.name = "[r_id]"
				P.pixel_x = rand(-7, 7) // random position
				P.pixel_y = rand(-7, 7)
				P.icon_state = "patch[patch_icon]"
				reagents.trans_to_obj(P, min(reagents.total_volume, MAX_UNITS_PER_PATCH))
				if(P.icon_state in list("patch1", "patch2", "patch3", "patch4")) // if using greyscale, take colour from reagent
					P.color = P.reagents.get_color()
				P.update_icon()

		else // Bottles. Official value is 1, but this works as a sanity check.
			while(reagents.total_volume)
				var/obj/item/reagent_containers/glass/bottle/B = new(src.loc)
				B.name = "[r_id] bottle"
				B.pixel_x = rand(-7, 7) // random position
				B.pixel_y = rand(-7, 7)
				B.icon_state = "bottle-[bottle_icon]"
				reagents.trans_to_obj(B, min(reagents.total_volume, MAX_UNITS_PER_BOTTLE))
				B.update_icon()

	// Sanity check when manual bottling is triggered.
	if(queue.len)
		queue -= queue[1]

	// If the queue is now empty, we're done. Otherwise, re-add catalyst and proceed to the next recipe.
	if(queue.len)
		if(use_catalyst)
			for(var/datum/reagent/chem in catalyst.reagents.reagent_list)
				LAZYADD(catalyst_ids, chem.id)
			catalyst.reagents.trans_to_holder(src.reagents, catalyst.reagents.total_volume)
		update_icon()
		follow_recipe(queue[1], 1)

	else
		busy = FALSE
		set_use_power(USE_POWER_IDLE)
		queue = list()
		update_icon()


// What happens to the synthesizer if it breaks or loses power in the middle of running. Chemists must fix things manually.
/obj/machinery/chemical_synthesizer/proc/stall()
	busy = FALSE
	set_use_power(USE_POWER_IDLE)
	queue = list()
	catalyst_ids = list()
	update_icon()

#undef SYNTHESIZER_MAX_CARTRIDGES
#undef SYNTHESIZER_MAX_RECIPES
#undef SYNTHESIZER_MAX_QUEUE
#undef RECIPE_MAX_STRING
#undef RECIPE_MAX_STEPS

/obj/machinery/chemical_synthesizer/ownership()
	. = ..()
	. += owns(nameof(catalyst), policy = OWN_CONTAINED)
// Label -> installed cartridge (in contents); they go with the machine.
