#define SYNTH_REQUEST_GUIDED 1
#define SYNTH_REQUEST_IMPORT 2

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
	/// The reaction is done and the product is waiting to be bottled.
	var/finishing = FALSE
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

TRACKED(/obj/machinery/chemical_synthesizer, busy)
TRACKED(/obj/machinery/chemical_synthesizer, finishing)

/obj/machinery/chemical_synthesizer/var/_recharge_reagents = TRUE
TRACKED_BRIDGED(/obj/machinery/chemical_synthesizer, _recharge_reagents, CHANGE_MACHINE_SETTINGS)
/// Refills its cartridges while it recharges at all (full, it sleeps until a cartridge is drawn or added).
// The reagents datum acts as the machine's reaction vessel.

CAPABILITIES(/obj/machinery/chemical_synthesizer)
	owns_one(nameof(catalyst), /obj/item/reagent_containers/glass, starts = /obj/item/reagent_containers/glass/beaker)
	reagents(600)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(_recharge_reagents), wakes_on = list(nameof(_recharge_reagents)))
	owns_many(nameof(cartridges), /obj/item/reagent_containers/chem_disp_cartridge)
	op("add_cartridge", item(/obj/item/reagent_containers/chem_disp_cartridge), label("Insert cartridge"), then(PROC_REF(cartridge_added)))
	op("set_catalyst", item(/obj/item/reagent_containers/glass), label("Set catalyst"),
		needs(req(PROC_REF(no_catalyst), silent = TRUE), req(PROC_REF(clamp_works), because = MSG(chemical_synthesizer/machine_down)), req(PROC_REF(can_extract_from), because = MSG(chemical_synthesizer/not_open))),
		then(PROC_REF(catalyst_set)))
	interface("ChemSynthesizer", observe = TRUE)
	extend("ui_observe", needs(req_operable()))
	op("start_queue", ui_act("start_queue"), then(PROC_REF(ui_act_start_queue)))
	op("rem_queue", ui_act("rem_queue", arg("q_index", num())), then(PROC_REF(ui_act_rem_queue)))
	op("clear_queue", ui_act("clear_queue"),
		asks(/datum/prompt/choice, fields = list("question" = "Are you sure you want to clear the running queue?", "title" = "Confirm", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "a1"),
		then(PROC_REF(ui_act_clear_queue)))
	op("eject_catalyst", ui_act("eject_catalyst"), then(PROC_REF(ui_act_eject_catalyst)))
	op("toggle_catalyst", ui_act("toggle_catalyst"), then(PROC_REF(ui_act_toggle_catalyst)))
	// stalling asks only while it runs
	op("emergency_stop", ui_act("emergency_stop"),
		asks(/datum/prompt/choice, fields = list("question" = "Are you sure you want to stall the machine?", "title" = "Confirm", "choices" = list("Yes", "No"), "buttons" = TRUE, "timeout" = 0), step = "a2", when = PROC_REF(is_busy)),
		then(PROC_REF(ui_act_emergency_stop)))
	op("bottle_product", ui_act("bottle_product"), then(PROC_REF(ui_act_bottle_product)))
	op("panel_toggle", ui_act("panel_toggle"), then(PROC_REF(ui_act_panel_toggle)))
	op("mode_toggle", ui_act("mode_toggle"), then(PROC_REF(ui_act_mode_toggle)))
	op("add_recipe", ui_act("add_recipe"), then(PROC_REF(ui_act_add_recipe)))
	// removing asks only while idle (running, it says it cannot)
	op("rem_recipe", ui_act("rem_recipe", arg("rm_index", schema_text(4096))),
		asks(/datum/prompt/choice, fields = list("question" = "Are you sure you want to remove this recipe?", "title" = "Confirm", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "a3", when = PROC_REF(is_idle)),
		then(PROC_REF(ui_act_rem_recipe)))
	op("exp_recipe", ui_act("exp_recipe", arg("exp_index", schema_text(4096))), then(PROC_REF(ui_act_exp_recipe)))
	op("add_queue", ui_act("add_queue", arg("qa_index", schema_text(4096))), then(PROC_REF(ui_act_add_queue)))
	op("drug_form", ui_act("drug_form", arg("drug_index", num())), then(PROC_REF(ui_act_drug_form)))
	op("change_pill_style", ui_act("modal:change_pill_style", arg("arguments")),
		asks(/datum/prompt/choice, fields = list("question" = "Please select the new style for pills:", "choices" = computed(PROC_REF(pill_style_choices)), "default" = computed(PROC_REF(pill_style_current)), "bento" = "spritesheet", "inline" = TRUE, "timeout" = 0), step = "style"),
		then(PROC_REF(modal_change_pill_style)))
	op("change_patch_style", ui_act("modal:change_patch_style", arg("arguments")),
		asks(/datum/prompt/choice, fields = list("question" = "Please select the new style for patches:", "choices" = computed(PROC_REF(patch_style_choices)), "default" = computed(PROC_REF(patch_style_current)), "bento" = "spritesheet", "inline" = TRUE, "timeout" = 0), step = "style"),
		then(PROC_REF(modal_change_patch_style)))
	op("change_bottle_style", ui_act("modal:change_bottle_style", arg("arguments")),
		asks(/datum/prompt/choice, fields = list("question" = "Please select the new style for bottles:", "choices" = computed(PROC_REF(bottle_style_choices)), "default" = computed(PROC_REF(bottle_style_current)), "bento" = "spritesheet", "inline" = TRUE, "timeout" = 0), step = "style"),
		then(PROC_REF(modal_change_bottle_style)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	// ALLOW(door_gates): the legacy machine panel is the panel_open var, not a capability space an op could be placed in
	op("remove_cartridge", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), when(nameof(panel_open)), label("Remove cartridge"), asks(/datum/prompt/choice, fields = list("question" = "Which cartridge would you like to remove?", "title" = "Chemical Synthesizer", "choices" = computed(PROC_REF(cartridge_choices)), "timeout" = 0)), then(PROC_REF(cartridge_chosen)))

/obj/machinery/chemical_synthesizer/Initialize(mapload)
	. = ..()

	if(spawn_cartridges)
		for(var/type in spawn_cartridges)
			add_cartridge(new type(src))
		set_panel_open(FALSE)

	var/obj/item/paper/P = new /obj/item/paper(get_turf(src))
	P.name = "Synthesizer Instructions"
	P.desc = "A photocopy of a handwritten note."
	P.set_info({"Hello there! This device is a new NanoTrasen product currently being shipped to select facilities \
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
	<BR> Recipe string: Silicon,20,Nitrogen,20,Potassium,20"})

/obj/machinery/chemical_synthesizer/examine(mob/user)
	. = ..()
	if(panel_open)
		. += "It has [length(cartridges)] cartridges installed, and has space for [SYNTHESIZER_MAX_CARTRIDGES - length(cartridges)] more."

/// The machine: broken, off, idle (with or without its catalyst bottle), working, or done; the catalyst and the mix under it in the colour of each.
/obj/machinery/chemical_synthesizer/draw(datum/look/look)
	..()
	if(broken_now())
		look.state("synth_broken")
		return
	if(power_lost())
		look.state("synth_off")
		return
	look.watch(reagents)
	look.watch(catalyst)
	if(finishing)
		look.state("synth_finished")
	else if(busy)
		look.state("synth_working")
	else
		look.state(catalyst ? "synth_idle_bottle" : "synth_idle")
	if(catalyst) // All underlay icon_states requires the catalyst bottle to be present, so this works as a check.
		look.watch(catalyst.reagents)
		if(catalyst.reagents.master_id)
			look.underlay(look_overlay_image(icon, "synth_catalyst", layer = -1, color = catalyst.reagents.tint))
		if(reagents.master_id)
			look.underlay(look_overlay_image(icon, "synth_vessel", layer = -2, color = reagents.tint))

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

	if(!move_into(src, nameof(src.cartridges), C, user, key = C.label))
		return
	if(user)
		to_chat(user, span_notice("You add \the [C] to \the [src]."))

	sortTim(cartridges, GLOBAL_PROC_REF(cmp_text_asc)) // in place: the owned list keeps its identity
	work_start(src)
	SStgui.update_uis(src)

/obj/machinery/chemical_synthesizer/proc/remove_cartridge(label)
	. = rel_take(src, nameof(cartridges), key = label)
	SStgui.update_uis(src)

/// The old attackby: a cartridge goes into a free slot under its label.
/obj/machinery/chemical_synthesizer/proc/cartridge_added(datum/act/op/A)
	add_cartridge(A.held, A.actor)
	return OP_OK

MSG_DEF_SELF(chemical_synthesizer/machine_down, "The clamp will not secure the catalyst while the machine is down.")
MSG_DEF_SELF(chemical_synthesizer/not_open, "You don't see how it could extract reagents from %I%.")

/// No catalyst is set. (No busy check: the catalyst slot must be occupied for the machine to work.)
/obj/machinery/chemical_synthesizer/proc/no_catalyst(datum/act/op/A)
	return !catalyst

/// The machine works, so the clamp secures the catalyst.
/obj/machinery/chemical_synthesizer/proc/clamp_works(datum/act/op/A)
	return operable()

/// The held container must be open for reagents to be drawn from it.
/obj/machinery/chemical_synthesizer/proc/can_extract_from(datum/act/op/A)
	return A.held?.is_open_container()

/// The old attackby: the catalyst container is clamped on.
/obj/machinery/chemical_synthesizer/proc/catalyst_set(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/RC = A.held

	if(!move_into(src, nameof(src.catalyst), RC, user))
		return OP_OK
	to_chat(user, span_notice("You set \the [RC] on \the [src]."))
	return OP_OK

/obj/machinery/chemical_synthesizer/proc/wrench_used(datum/act/op/A)
	if(busy)
		return OP_OK
	return OP_DECLINE

// More stolen chemical_dispenser code.
/// Refills its cartridges every 15 frames while any is short; full (or not recharging) it sleeps
/// until a cartridge is drawn from or added.
/obj/machinery/chemical_synthesizer/proc/work_step(datum/act/timer/A)
	if(!operable())
		return work_wait_for_power(src)
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

/// The window's data.
/obj/machinery/chemical_synthesizer/ui_data(datum/act/eval/A)
	. = list()
	.["busy"] = busy
	.["production_mode"] = production_mode
	.["panel_open"] = panel_open
	.["use_catalyst"] = use_catalyst
	.["drug_substance"] = drug_substance
	.["bottle_icon"] = bottle_icon
	.["pill_icon"] = pill_icon
	.["patch_icon"] = patch_icon
	var/list/part = ui_data_part_chemical_synthesizer(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/chemical_synthesizer/proc/ui_data_part_chemical_synthesizer(datum/act/eval/A)
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

	// the window's modal (the engine adds it too; the key is always sent, as it was)
	data["modal"] = tgui_modal_data(src)

	return data

/obj/machinery/chemical_synthesizer/proc/ui_act_start_queue(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Start up the queue.
	if(!busy)
		start_queue(user)

/obj/machinery/chemical_synthesizer/proc/ui_act_rem_queue(datum/act/op/A, q_index)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Remove a single entry from the queue. Sanity checks also prevent removing the first entry if the machine is busy though UI should already prevent that.
	var/index = q_index
	if(!isnum(index) || !ISINTEGER(index) || !istype(queue) || (index<1 || index>length(queue) || (busy && index == 1)))
		return
	queue -= queue[index]

/obj/machinery/chemical_synthesizer/proc/ui_act_clear_queue(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Remove all entries from the queue except the currently processing recipe.
	if(A.step_value("a1") == "Yes")
		if(busy)
			// Oh no, I've broken code convention to remove all entries but the first.
			for(var/i = queue.len, i >= 2, i--)
				queue -= queue[i]
		else
			queue = list()

/obj/machinery/chemical_synthesizer/proc/ui_act_eject_catalyst(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Removes the catalyst bottle from the machine.
	if(!busy && catalyst)
		catalyst.forceMove(get_turf(src))
		rel_take(src, nameof(catalyst))

/obj/machinery/chemical_synthesizer/proc/ui_act_toggle_catalyst(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Decides if the machine uses the catalyst.
	if(!busy)
		use_catalyst = !use_catalyst

/obj/machinery/chemical_synthesizer/proc/ui_act_emergency_stop(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Stops everything if that's desirable for some reason.
	if(busy && A.step_value("a2") == "Yes")
		stalled = TRUE

/obj/machinery/chemical_synthesizer/proc/ui_act_bottle_product(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Bottles the reaction mixture if stalled.
	if(!busy)
		bottle_product()

/obj/machinery/chemical_synthesizer/proc/ui_act_panel_toggle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Opens/closes the panel.
	if(!busy)
		set_panel_open(!panel_open)

/obj/machinery/chemical_synthesizer/proc/ui_act_mode_toggle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Toggles production mode.
	production_mode = !production_mode

/obj/machinery/chemical_synthesizer/proc/ui_act_add_recipe(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Allows the user to add a recipe. Kinda vital for this machine to do anything useful.
	if(recipes.len >= SYNTHESIZER_MAX_RECIPES)
		to_chat(user, span_warning("Maximum recipes exceeded!"))
		return
	if(!production_mode)
		babystep_recipe(user)
	else
		import_recipe(user)

/obj/machinery/chemical_synthesizer/proc/ui_act_rem_recipe(datum/act/op/A, rm_index)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Allows the user to remove recipes while the machine is idle.
	if(!busy)
		if(A.step_value("a3") == "Yes")
			var/index = rm_index
			if(index in recipes)
				recipes.Remove(list(index)) // Fuck off Byond.
	else
		to_chat(user, span_warning("You cannot remove recipes while the machine is running!"))

/obj/machinery/chemical_synthesizer/proc/ui_act_exp_recipe(datum/act/op/A, exp_index)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Allows the user to export recipes to chat formatted for easy importing.
	var/index = exp_index
	export_recipe(user, index)

/obj/machinery/chemical_synthesizer/proc/ui_act_add_queue(datum/act/op/A, qa_index)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Adds recipes to the queue.
	if(queue.len >= SYNTHESIZER_MAX_QUEUE)
		to_chat(user, span_warning("Synthesizer queue full!"))
		return
	var/index = qa_index
	// If you forgot, this is a string returned by the user pressing the "add to queue" button on a recipe.
	if(index in recipes)
		queue[++queue.len] = index

/obj/machinery/chemical_synthesizer/proc/ui_act_drug_form(datum/act/op/A, drug_index)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	// Toggles between bottles, pills, and patches.
	drug_substance = drug_index


/// The sprite choices of a style modal: `count` spritesheet classes "chem_master32x32 <prefix><n>".
/obj/machinery/chemical_synthesizer/proc/style_choices(prefix, count)
	. = list()
	for(var/i = 1 to count)
		. += "chem_master32x32 [prefix][i]"

/obj/machinery/chemical_synthesizer/proc/pill_style_choices(datum/act/op/A)
	return style_choices("pill", MAX_PILL_SPRITE)

/obj/machinery/chemical_synthesizer/proc/patch_style_choices(datum/act/op/A)
	return style_choices("patch", MAX_PATCH_SPRITE)

/obj/machinery/chemical_synthesizer/proc/bottle_style_choices(datum/act/op/A)
	return style_choices("bottle-", MAX_BOTTLE_SPRITE)

/obj/machinery/chemical_synthesizer/proc/pill_style_current(datum/act/op/A)
	return "chem_master32x32 pill[pill_icon]"

/obj/machinery/chemical_synthesizer/proc/patch_style_current(datum/act/op/A)
	return "chem_master32x32 patch[patch_icon]"

/obj/machinery/chemical_synthesizer/proc/bottle_style_current(datum/act/op/A)
	return "chem_master32x32 bottle-[bottle_icon]"

/obj/machinery/chemical_synthesizer/proc/modal_change_pill_style(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	var/list/choices = pill_style_choices(A)
	var/new_style = CLAMP(choices.Find(A.step_value("style")), 0, MAX_PILL_SPRITE)
	if(new_style)
		pill_icon = new_style
	return TRUE

/obj/machinery/chemical_synthesizer/proc/modal_change_patch_style(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	var/list/choices = patch_style_choices(A)
	var/new_style = CLAMP(choices.Find(A.step_value("style")), 0, MAX_PATCH_SPRITE)
	if(new_style)
		patch_icon = new_style
	return TRUE

/obj/machinery/chemical_synthesizer/proc/modal_change_bottle_style(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	var/list/choices = bottle_style_choices(A)
	var/new_style = CLAMP(choices.Find(A.step_value("style")), 0, MAX_BOTTLE_SPRITE)
	if(new_style)
		bottle_icon = new_style
	return TRUE

/// Requirement: the machine is idle (the old handlers asked only while it was).
/obj/machinery/chemical_synthesizer/proc/is_busy(datum/act/op/A)
	return busy

/obj/machinery/chemical_synthesizer/proc/is_idle(datum/act/op/A)
	return !busy
/obj/machinery/chemical_synthesizer/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet/chem_master),
	)

// This proc is lets users create recipes step-by-step and exports a comma delineated list to chat. It's intended to teach how to use the machine.
/obj/machinery/chemical_synthesizer/proc/babystep_recipe(mob/user)
	return synth_babystep_recipe_stage(user, list())

/obj/machinery/chemical_synthesizer/proc/synth_babystep_recipe_stage(mob/user, list/synth_answers)
	// Each answer re-runs this proc; steps are keyed by their number.
	if(!("name" in synth_answers))
		open_request(src, /datum/prompt/text/synth_recipe_review, PROC_REF(synth_recipe_answered), answerer = user, synth_answers = synth_answers, synth_key = "name", synth_mode = SYNTH_REQUEST_GUIDED, question = "Name your recipe. Consider including the output volume.", title = "Recipe naming")
		return
	var/answer = synth_answers["name"]
	if(isnull(answer))
		return
	var/rec_name = sanitizeSafe(answer)
	if(!rec_name || (rec_name in recipes)) // Code requires each recipe to have a unique name.
		to_chat(user, "Please provide a unique recipe name!")
		return

	if(!("steps" in synth_answers))
		open_request(src, /datum/prompt/number/synth_recipe_review, PROC_REF(synth_recipe_answered), answerer = user, synth_answers = synth_answers, synth_key = "steps", synth_mode = SYNTH_REQUEST_GUIDED, question = "How many steps does your recipe contain ([RECIPE_MAX_STEPS] max)?", title = "Steps", default = 1, synth_max = RECIPE_MAX_STEPS, synth_min = 1)
		return
	var/step_count = synth_answers["steps"]
	if(isnull(step_count))
		return
	var/steps = 2 * step_count
	if(!steps)
		to_chat(user, "Please input a valid number of steps!")
		return

	var/list/new_rec = list() // This holds the actual recipe.
	for(var/i = 1, i < steps, i += 2) // For the user, 1 step is both text and volume. For list arithmetic, that's 2 steps.
		if(!("label[i]" in synth_answers))
			open_request(src, /datum/prompt/choice/synth_recipe_review, PROC_REF(synth_recipe_answered), answerer = user, synth_answers = synth_answers, synth_key = "label[i]", synth_mode = SYNTH_REQUEST_GUIDED, question = "Which chemical would you like to use?", title = "Chemical Synthesizer", choices = cartridges)
			return
		var/label = synth_answers["label[i]"]
		if(isnull(label))
			return
		if(!label)
			to_chat(user, "Please select a chemical!")
			return
		new_rec[++new_rec.len] = label // Add the reagent ID.
		if(!("amount[i]" in synth_answers))
			open_request(src, /datum/prompt/number/synth_recipe_review, PROC_REF(synth_recipe_answered), answerer = user, synth_answers = synth_answers, synth_key = "amount[i]", synth_mode = SYNTH_REQUEST_GUIDED, question = "How much of the chemical would you like to add?", title = "Volume", default = 1, synth_max = src.reagents.maximum_volume, synth_min = 1)
			return
		var/amount = synth_answers["amount[i]"]
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
	return synth_import_recipe_stage(user, list())

/obj/machinery/chemical_synthesizer/proc/synth_import_recipe_stage(mob/user, list/synth_answers)
	if(!("a2" in synth_answers))
		open_request(src, /datum/prompt/text/synth_recipe_review, PROC_REF(synth_recipe_answered), answerer = user, synth_answers = synth_answers, synth_key = "a2", synth_mode = SYNTH_REQUEST_IMPORT, question = "Name your recipe. Consider including the output volume.", title = "Recipe naming", max_len = MAX_NAME_LEN, name_text = TRUE)
		return
	var/_answer_a2 = synth_answers["a2"]
	if(isnull(_answer_a2))
		return
	var/rec_name = sanitizeSafe(_answer_a2, MAX_NAME_LEN)
	if(!rec_name || (rec_name in recipes)) // Code requires each recipe to have a unique name.
		to_chat(user, "Please provide a unique recipe name!")
		return

	if(!("a3" in synth_answers))
		open_request(src, /datum/prompt/text/synth_recipe_review, PROC_REF(synth_recipe_answered), answerer = user, synth_answers = synth_answers, synth_key = "a3", synth_mode = SYNTH_REQUEST_IMPORT, question = "Input your recipe as 'Chem1,vol1,Chem2,vol2,...'", title = "Import recipe")
		return
	var/rec_input = synth_answers["a3"]
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

	set_busy(TRUE)
	set_use_power(USE_POWER_ACTIVE)
	if(use_catalyst)
		// Populate the list of catalyst chems. This is important when it's time to bottle_product().
		for(var/datum/reagent/chem in catalyst.reagents.reagent_list)
			LAZYADD(catalyst_ids, chem.id)

		// Transfer the catalyst to the synthesizer's reagent holder.
		catalyst.reagents.trans_to_holder(src.reagents, catalyst.reagents.total_volume)

	// Start the first recipe in the queue, starting with step 1.
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
	after(src, recipes[r_id][step + 1] * delay_modifier, PROC_REF(perform_reaction), with = list(r_id, step))

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
		after(src, 1 MINUTE, PROC_REF(perform_reaction), with = list(r_id, step))
		return

	// After all this mess of code, we reach the line where the magic happens.
	C.reagents.trans_to_holder(src.reagents, quantity)
	work_start(src) // a cartridge to refill
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
		set_finishing(TRUE)
		after(src, delay, PROC_REF(bottle_product), with = list(r_id))

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

		else // Bottles. Official value is 1, but this works as a sanity check.
			while(reagents.total_volume)
				var/obj/item/reagent_containers/glass/bottle/B = new(src.loc)
				B.name = "[r_id] bottle"
				B.pixel_x = rand(-7, 7) // random position
				B.pixel_y = rand(-7, 7)
				B.icon_state = "bottle-[bottle_icon]"
				reagents.trans_to_obj(B, min(reagents.total_volume, MAX_UNITS_PER_BOTTLE))

	set_finishing(FALSE)

	// Sanity check when manual bottling is triggered.
	if(queue.len)
		queue -= queue[1]

	// If the queue is now empty, we're done. Otherwise, re-add catalyst and proceed to the next recipe.
	if(queue.len)
		if(use_catalyst)
			for(var/datum/reagent/chem in catalyst.reagents.reagent_list)
				LAZYADD(catalyst_ids, chem.id)
			catalyst.reagents.trans_to_holder(src.reagents, catalyst.reagents.total_volume)
		follow_recipe(queue[1], 1)

	else
		set_busy(FALSE)
		set_use_power(USE_POWER_IDLE)
		queue = list()


// What happens to the synthesizer if it breaks or loses power in the middle of running. Chemists must fix things manually.
/obj/machinery/chemical_synthesizer/proc/stall()
	set_busy(FALSE)
	set_finishing(FALSE)
	set_use_power(USE_POWER_IDLE)
	queue = list()
	catalyst_ids = list()

#undef SYNTHESIZER_MAX_CARTRIDGES
#undef SYNTHESIZER_MAX_RECIPES
#undef SYNTHESIZER_MAX_QUEUE
#undef RECIPE_MAX_STRING
#undef RECIPE_MAX_STEPS

// Label -> installed cartridge (in contents); they go with the machine.

/obj/machinery/chemical_synthesizer/proc/synth_recipe_answered(datum/act/request/context)
	if(!context.answer)
		return
	. = synth_recipe_apply(context)
	SStgui.update_uis(src)

/obj/machinery/chemical_synthesizer/proc/synth_recipe_apply(datum/act/request/context)
	var/list/synth_answers
	var/synth_key
	var/synth_mode
	if(istype(context.answer, /datum/prompt/text/synth_recipe_review))
		var/datum/prompt/text/synth_recipe_review/ask_text = context.answer
		synth_answers = ask_text.synth_answers.Copy()
		synth_key = ask_text.synth_key
		synth_mode = ask_text.synth_mode
	else if(istype(context.answer, /datum/prompt/choice/synth_recipe_review))
		var/datum/prompt/choice/synth_recipe_review/ask_choice = context.answer
		synth_answers = ask_choice.synth_answers.Copy()
		synth_key = ask_choice.synth_key
		synth_mode = ask_choice.synth_mode
	else
		var/datum/prompt/number/synth_recipe_review/ask_number = context.answer
		synth_answers = ask_number.synth_answers.Copy()
		synth_key = ask_number.synth_key
		synth_mode = ask_number.synth_mode
	synth_answers[synth_key] = context.answer.value
	if(synth_mode == SYNTH_REQUEST_GUIDED)
		return synth_babystep_recipe_stage(context.request.answerer, synth_answers)
	return synth_import_recipe_stage(context.request.answerer, synth_answers)

/datum/prompt/text/synth_recipe_review
	timeout = 0
	var/list/synth_answers
	var/synth_key
	var/synth_mode

/datum/prompt/choice/synth_recipe_review
	timeout = 0
	var/list/synth_answers
	var/synth_key
	var/synth_mode

/datum/prompt/number/synth_recipe_review
	timeout = 0
	var/list/synth_answers
	var/synth_key
	var/synth_mode
	var/synth_min = 0
	var/synth_max = INFINITY

/datum/prompt/number/synth_recipe_review/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, synth_max, synth_min, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

#undef SYNTH_REQUEST_GUIDED
#undef SYNTH_REQUEST_IMPORT

/// The cartridges the screwdriver's question offers, by label.
/obj/machinery/chemical_synthesizer/proc/cartridge_choices(datum/act/A)
	return cartridges

/// The screwdriver's answer: that cartridge comes out.
/obj/machinery/chemical_synthesizer/proc/cartridge_chosen(datum/act/op/A)
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
