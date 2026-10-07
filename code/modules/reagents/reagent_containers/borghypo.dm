/obj/item/reagent_containers/borghypo
	name = "cyborg hypospray"
	desc = "An advanced chemical synthesizer and injection system, designed for heavy-duty medical equipment."
	icon = 'icons/obj/syringe.dmi'
	item_state = "hypo"
	icon_state = "borghypo"
	amount_per_transfer_from_this = 5
	min_transfer_amount = 1
	volume = 30
	max_transfer_amount = 10

	/// The single chemical we have currently selected. Used to index `reagent_volumes`, `reagent_names`, and `reagent_ids`.
	var/mode = 1
	/// Amount of power this hypo will remove from the robot user's internal cell when a reagent's stores are replenished.
	var/charge_cost = 325
	var/charge_tick = 0
	/// Time it takes for shots to recharge (in seconds)
	var/recharge_time = 5
	/// If true, can inject through things like spacesuits and armor.
	var/bypass_protection = FALSE
	/// Affects whether the TGUI will display itself as a chem or drink dispenser.
	var/is_dispensing_drinks = FALSE
	/// String contents in the TGUI search bar.
	var/ui_chemical_search
	/// Whether or not we're dispensing just a single reagent or are dispensing multiple reagents via a recipe
	var/is_dispensing_recipe = FALSE
	/// The recipe we will dispense if `is_dispensing_recipe` is `TRUE`
	var/selected_recipe_id
	var/hypo_sound = SFX_EFFECTS_HYPOSPRAY	// What sound do we play on use?

	var/list/reagent_volumes = list() // ALLOW(instance_list): d: filled in Initialize() with every reagent the hypo carries
	/// Associated list of the names of each of our reagents. Indexed via `mode`.
	var/list/reagent_names
	/// If we're currently recording a recipe, this will be set to a list containing the recipe's steps.
	var/list/recording_recipe
	/// Associated list of the recipes we have saved. Indexed via the string ID of the recipe.
	var/list/saved_recipes
	/// In the hypo's TGUI, this determines the amount buttons that will be available to change this hypo's transfer amount.

TYPE_TABLE_DECLARE(/obj/item/reagent_containers/borghypo, borghypo_transfer_amounts, list(5, 10))

TYPE_TABLE_DECLARE(/obj/item/reagent_containers/borghypo, borghypo_reagent_ids, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_INAPROVALINE, REAGENT_ID_BICARIDINE, REAGENT_ID_ANTITOXIN, REAGENT_ID_KELOTANE, REAGENT_ID_TRAMADOL, REAGENT_ID_DEXALIN, REAGENT_ID_SPACEACILLIN))

/obj/item/reagent_containers/borghypo/surgeon

TYPE_TABLE(/obj/item/reagent_containers/borghypo/surgeon, borghypo_reagent_ids, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_DEXALIN, REAGENT_ID_TRICORDRAZINE, REAGENT_ID_SPACEACILLIN, REAGENT_ID_OXYCODONE))

/obj/item/reagent_containers/borghypo/crisis

// Unifying chems with dogborg equivalent.
TYPE_TABLE(/obj/item/reagent_containers/borghypo/crisis, borghypo_reagent_ids, list(REAGENT_ID_INAPROVALINE, REAGENT_ID_TRICORDRAZINE, REAGENT_ID_DEXALIN, REAGENT_ID_BICARIDINE, REAGENT_ID_KELOTANE, REAGENT_ID_ANTITOXIN, REAGENT_ID_SPACEACILLIN, REAGENT_ID_TRAMADOL, REAGENT_ID_ADRANOL))

/obj/item/reagent_containers/borghypo/lost

TYPE_TABLE(/obj/item/reagent_containers/borghypo/lost, borghypo_reagent_ids, list(REAGENT_ID_TRICORDRAZINE, REAGENT_ID_BICARIDINE, REAGENT_ID_DEXALIN, REAGENT_ID_ANTITOXIN, REAGENT_ID_TRAMADOL, REAGENT_ID_SPACEACILLIN))

/obj/item/reagent_containers/borghypo/merc
	name = "advanced cyborg hypospray"
	desc = "An advanced nanite and chemical synthesizer and injection system, designed for heavy-duty medical equipment.  This type is capable of safely bypassing \
	thick materials that other hyposprays would struggle with."
	bypass_protection = TRUE // Because mercs tend to be in spacesuits.

TYPE_TABLE(/obj/item/reagent_containers/borghypo/merc, borghypo_reagent_ids, list(REAGENT_ID_HEALINGNANITES, REAGENT_ID_HYPERZINE, REAGENT_ID_TRAMADOL, REAGENT_ID_OXYCODONE, REAGENT_ID_SPACEACILLIN, REAGENT_ID_PERIDAXON, REAGENT_ID_OSTEODAXON, REAGENT_ID_MYELAMINE, REAGENT_ID_SYNTHBLOOD))

/// Performs a single reagent addition. Returns its success (or error) status at doing so.
/obj/item/reagent_containers/borghypo/proc/try_add_reagent(datum/reagents/target_reagents, mob/user, reagent_id, amount)
	var/reagent_volume = reagent_volumes[reagent_id]
	if(!reagent_volume || reagent_volume < amount)
		return BORGHYPO_STATUS_NOCHARGE

	if(!target_reagents.get_free_space())
		return BORGHYPO_STATUS_CONTAINERFULL

	if(hypo_sound)
		playsound(src, hypo_sound, 25, TRUE)

	var/amount_to_add = min(amount, reagent_volumes[reagent_id])
	target_reagents.add_reagent(reagent_id, amount_to_add)
	reagent_volumes[reagent_id] -= amount_to_add
	set_refilling(TRUE) // refill what was used
	return BORGHYPO_STATUS_SUCCESS

/// Attempts to add one reagent or multiple reagents, depending on if this hypo is currently set to dispense a recipe, (see `is_dispensing_recipe`.) Returns its success (or error) status at doing so.
/obj/item/reagent_containers/borghypo/proc/try_injection(datum/reagents/target_reagents, mob/user)
	if(is_dispensing_recipe && selected_recipe_id)
		// Add reagents with our selected ID
		var/foundRecipe = LAZYACCESS(saved_recipes, selected_recipe_id)
		if(!foundRecipe)
			to_chat(user, span_warning("Couldn't find recipe ") + span_boldwarning(selected_recipe_id) + span_warning("! Contact a coder."))
			return BORGHYPO_STATUS_NORECIPE
		for(var/recipe_step in foundRecipe)
			var/step_reagent_id = recipe_step["id"]
			var/step_dispense_amount = recipe_step["amount"]
			var/result = try_add_reagent(target_reagents, user, step_reagent_id, step_dispense_amount)
			switch(result)
				if(BORGHYPO_STATUS_CONTAINERFULL)
					return result
				if(BORGHYPO_STATUS_NOCHARGE)
					var/datum/reagent/empty_reagent = SSchemistry.ready().chemical_reagents[step_reagent_id]
					to_chat(user, span_warning("[src] doesn't have enough ") + span_boldwarning(empty_reagent.name) + span_warning(" to complete this recipe!"))
					return result
		return BORGHYPO_STATUS_SUCCESS
	else
		// Just add reagents
		return try_add_reagent(target_reagents, user, TYPE_TABLE_GET(src, borghypo_reagent_ids)[mode], amount_per_transfer_from_this)

/obj/item/reagent_containers/borghypo/Initialize(mapload)
	. = ..()

	for(var/T in TYPE_TABLE_GET(src, borghypo_reagent_ids))
		reagent_volumes[T] = volume
		var/datum/reagent/hypo_reagent = SSchemistry.ready().chemical_reagents[T]
		LAZYADD(reagent_names, hypo_reagent.name)

/// TRUE while a reagent is short (a dose sets it): the slow step recharges from the cyborg; full, it parks.
/obj/item/reagent_containers/borghypo/var/tmp/refilling = FALSE
TRACKED(/obj/item/reagent_containers/borghypo, refilling)

/// Every [recharge_time] steps, recharges some reagents from its cyborg while any is short.
/obj/item/reagent_containers/borghypo/proc/refill_step(datum/act/A)
	var/short = FALSE
	for(var/T in TYPE_TABLE_GET(src, borghypo_reagent_ids))
		if(reagent_volumes[T] < volume)
			short = TRUE
			break
	if(!short)
		charge_tick = 0
		set_refilling(FALSE)
		return
	if(++charge_tick < recharge_time)
		return
	charge_tick = 0

	var/mob/living/silicon/robot/robot_user = loc
	if(istype(robot_user))
		if(robot_user.cell)
			for(var/T in TYPE_TABLE_GET(src, borghypo_reagent_ids))
				if(reagent_volumes[T] < volume)
					if(!robot_user.draw_power(ROBOT_CELL_JOULES(charge_cost), src, ROBOT_CELL_JOULES(800)))
						return
					reagent_volumes[T] = min(reagent_volumes[T] + 5, volume)

// A cyborg hypospray makes the chosen reagent (or recipe) from its store and puts it into a person by a click (synthesizer(), code/library/reagents/synthesizer.dm);
// a limb that is not there, or thick material over it, refuses it (unless it bypasses protection). Its store is filled again from its cyborg's cell.
CAPABILITIES(/obj/item/reagent_containers/borghypo)
	every(2 SECONDS, then(PROC_REF(refill_step)), when = nameof(refilling))
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this))
	synthesizer()
	extend("synthesizer.inject", then(PROC_REF(injected)))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	interface("BorgHypo")
	without("ui_open")
	op("select_reagent", ui_act("select_reagent", arg("selectedReagentId", schema_text(4096))), then(PROC_REF(ui_act_select_reagent)))
	op("set_amount", ui_act("set_amount", arg("amount", num())), then(PROC_REF(ui_act_set_amount)))
	op("import_config", ui_act("import_config", arg("config")), then(PROC_REF(ui_act_import_config)))
	op("record_recipe", ui_act("record_recipe"), then(PROC_REF(ui_act_record_recipe)))
	op("cancel_recording", ui_act("cancel_recording"), then(PROC_REF(ui_act_cancel_recording)))
	op("clear_recipes", ui_act("clear_recipes"), then(PROC_REF(ui_act_clear_recipes)))
	op("save_recording", ui_act("save_recording"), asks(/datum/prompt/text, fields = list("question" = "What do you want to name this recipe?", "title" = "Recipe Name?", "default" = "Recipe Name", "max_len" = MAX_NAME_LEN, "timeout" = 0), step = "a1"), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(recipe_overwrite_question)), "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "a2", when = PROC_REF(recipe_name_taken)), then(PROC_REF(ui_act_save_recording)))
	op("remove_recipe", ui_act("remove_recipe", arg("recipe", schema_text(4096))), then(PROC_REF(ui_act_remove_recipe)))
	op("select_recipe", ui_act("select_recipe", arg("recipe", schema_text(4096))), then(PROC_REF(ui_act_select_recipe)))
	op("set_chemical_search", ui_act("set_chemical_search", arg("uiChemicalSearch", schema_text(4096))), then(PROC_REF(ui_act_set_chemical_search)))

/// The click on a person (the old attack handler).
/obj/item/reagent_containers/borghypo/proc/injected(datum/act/op/A)
	var/mob/living/M = A.target
	var/mob/living/user = A.actor
	return injection_result(M, user)

/obj/item/reagent_containers/borghypo/proc/injection_result(mob/living/M, mob/living/user)
	if(!istype(M))
		return OP_REFUSED

	var/mob/living/carbon/human/H = M
	if(istype(H))
		var/obj/item/organ/external/affected = H.get_organ(user.zone_sel.selecting)
		if(!affected)
			balloon_alert(user, "\the [H] is missing that limb!")
			return OP_REFUSED

	if(M.can_inject(user, 1, ignore_thickness = bypass_protection))

		if(M.reagents)
			var/reagent_id = TYPE_TABLE_GET(src, borghypo_reagent_ids)[mode]
			var/amount_to_add = min(amount_per_transfer_from_this, reagent_volumes[reagent_id])
			var/result = try_injection(M.reagents, user)
			if(is_dispensing_recipe)
				// Log every reagent injected in the recipe
				var/foundRecipe = LAZYACCESS(saved_recipes, selected_recipe_id)
				for(var/recipe_step in foundRecipe)
					var/step_reagent_id = recipe_step["id"]
					var/step_dispense_amount = recipe_step["amount"]
					add_attack_logs(user, M, "Borg injected with [step_dispense_amount] units of '[step_reagent_id]'")
			else
				add_attack_logs(user, M, "Borg injected with [amount_to_add] units of '[reagent_id]'")
			switch(result)
				if(BORGHYPO_STATUS_CONTAINERFULL)
					balloon_alert(user, "\the [M] has too many reagents in [M.p_their()] system!")
					return OP_REFUSED
				if(BORGHYPO_STATUS_NOCHARGE)
					if(is_dispensing_recipe)
						balloon_alert(user, "not enough reagents to inject full recipe!")
						balloon_alert(M, "you feel multiple tiny pricks in quick succession!")
					else
						var/datum/reagent/empty_reagent = SSchemistry.ready().chemical_reagents[reagent_id]
						balloon_alert(user, "\the [src] doesn't have enough [empty_reagent.name]!")
					return OP_REFUSED
				if(BORGHYPO_STATUS_NORECIPE)
					balloon_alert(user, "recipe '[selected_recipe_id]' not found!")
					return OP_REFUSED
				else
					if(is_dispensing_recipe)
						balloon_alert(user, "recipe '[selected_recipe_id]' injected into \the [M].")
						balloon_alert(M, "you feel multiple tiny pricks in quick succession!")
					else
						balloon_alert(user, "[amount_to_add] units injected into \the [M].")
						balloon_alert(M, "you feel a tiny prick!")
					return OP_OK
	return OP_REFUSED

/// Old attack_self.
/obj/item/reagent_containers/borghypo/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/item/reagent_containers/borghypo/ui_opening(mob/user, datum/tgui/ui)
	// Assuming the user is opening the UI, empty the chem search preemptively.
	ui_chemical_search = null

/obj/item/reagent_containers/borghypo/ui_title(mob/user)
	return "Integrated [is_dispensing_drinks ? "Drink Dispenser" : "Chemical Hypo"]"

/obj/item/reagent_containers/borghypo/tgui_static_data(mob/user)
	var/list/static_data = list()
	static_data["isDispensingDrinks"] = is_dispensing_drinks
	static_data["minTransferAmount"] = min_transfer_amount
	static_data["maxTransferAmount"] = max_transfer_amount
	return static_data

/obj/item/reagent_containers/borghypo/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["amount"] = amount_per_transfer_from_this
	data["uiChemicalSearch"] = ui_chemical_search
	data["recordingRecipe"] = recording_recipe
	data["isDispensingRecipe"] = is_dispensing_recipe
	data["selectedRecipeId"] = selected_recipe_id
	var/list/merged_1 = ui_data_obj_item_reagent_containers_borghypo(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/reagent_containers/borghypo's window data.
/obj/item/reagent_containers/borghypo/proc/ui_data_obj_item_reagent_containers_borghypo(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(!isrobot(user))
		return data
	var/mob/living/silicon/robot/robot_user = user
	data["theme"] = robot_user.get_ui_theme()
	data["transferAmounts"] = TYPE_TABLE_GET(src, borghypo_transfer_amounts)

	var/list/chemicals = list()
	for(var/key, value in reagent_volumes)
		var/datum/reagent/available_reagent = SSchemistry.ready().chemical_reagents[key]
		// If the user is searching for a particular chemical by name, only add this one if its name matches their search!
		if((ui_chemical_search && findtext(available_reagent.name, ui_chemical_search)) || !ui_chemical_search)
			UNTYPED_LIST_ADD(chemicals, list("name" = available_reagent.name, "id" = key, "volume" = value))
	data["chemicals"] = chemicals
	data["selectedReagentId"] = TYPE_TABLE_GET(src, borghypo_reagent_ids)[mode]
	data["recipes"] = (saved_recipes || list())

	return data

/obj/item/reagent_containers/borghypo/proc/ui_act_select_reagent(datum/act/op/A, selectedReagentId)
	var/mob/user = A.actor
	var/list/ids = TYPE_TABLE_GET(src, borghypo_reagent_ids)
	var/new_mode = ids.Find(selectedReagentId)
	if(new_mode)
		var/datum/reagent/selected_reagent = SSchemistry.ready().chemical_reagents[TYPE_TABLE_GET(src, borghypo_reagent_ids)[new_mode]]
		play_sfx(src, SFX_EFFECTS_POP)
		if(recording_recipe)
			UNTYPED_LIST_ADD(recording_recipe, list("id" = selected_reagent.id, "amount" = amount_per_transfer_from_this))
		else
			mode = new_mode
			balloon_alert(user, "synthesizer is now producing '[selected_reagent.name]'")
			is_dispensing_recipe = FALSE
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_set_amount(datum/act/op/A, amount)
	amount_per_transfer_from_this = clamp(round(amount, 1), min_transfer_amount, max_transfer_amount) // Round to nearest 1, clamp between min and max transfer amount
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_import_config(datum/act/op/A, config)
	if(!isnull(config) && !islist(config))
		return FALSE
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

/obj/item/reagent_containers/borghypo/proc/ui_act_record_recipe(datum/act/op/A)
	recording_recipe = list()
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_cancel_recording(datum/act/op/A)
	recording_recipe = null
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_clear_recipes(datum/act/op/A)
	saved_recipes = list()
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_save_recording(datum/act/op/A)
	var/mob/user = A.actor
	var/name = A.step_value("a1")
	if(isnull(name))
		return
	if(LAZYACCESS(saved_recipes, name) && A.step_value("a2") != "Yes")
		return
	if(name && recording_recipe)
		for(var/list/L in recording_recipe)
			var/label = L["id"]
			// Verify this hypo can dispense every chemical
			if(!(label in TYPE_TABLE_GET(src, borghypo_reagent_ids)))
				to_chat(user, span_warning("\The [src] cannot find ") + span_boldwarning(label) + span_warning("!"))
				return
		LAZYSET(saved_recipes, name, recording_recipe)
		recording_recipe = null
		. = TRUE

/// The overwrite question opens only for a name already saved.
/obj/item/reagent_containers/borghypo/proc/recipe_name_taken(datum/act/op/A)
	return !isnull(LAZYACCESS(saved_recipes, A.step_value("a1"))) // ALLOW(reads): asked once, when the button is pressed, to decide whether its question opens

/obj/item/reagent_containers/borghypo/proc/recipe_overwrite_question(datum/act/op/A)
	return "\"[A.step_value("a1")]\" already exists, do you want to overwrite it?"

/obj/item/reagent_containers/borghypo/proc/ui_act_remove_recipe(datum/act/op/A, recipe)
	var/recipe_name = recipe
	// If we've selected the recipe we're deleting, un-select it!
	if(selected_recipe_id == recipe_name)
		selected_recipe_id = null
		is_dispensing_recipe = FALSE
	LAZYREMOVE(saved_recipes, recipe_name)
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_select_recipe(datum/act/op/A, recipe)
	var/mob/user = A.actor
	// Make sure we actually have a recipe saved with the given name before setting it!
	var/recipe_name = recipe
	var/selectedRecipe = LAZYACCESS(saved_recipes, recipe_name)
	if(!selectedRecipe)
		to_chat(user, span_warning("\The [src] cannot find the recipe ") + span_boldwarning(recipe_name) + span_warning("!"))
		return
	play_sfx(user, SFX_EFFECTS_POP)
	balloon_alert(user, "synthesizer is using macro: '[recipe_name]'")
	is_dispensing_recipe = TRUE
	selected_recipe_id = recipe_name
	. = TRUE

/obj/item/reagent_containers/borghypo/proc/ui_act_set_chemical_search(datum/act/op/A, uiChemicalSearch)
	ui_chemical_search = uiChemicalSearch
	. = TRUE

/obj/item/reagent_containers/borghypo/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		var/datum/reagent/current_reagent = SSchemistry.ready().chemical_reagents[TYPE_TABLE_GET(src, borghypo_reagent_ids)[mode]]
		. += span_notice("It is currently producing [current_reagent.name] and has [reagent_volumes[TYPE_TABLE_GET(src, borghypo_reagent_ids)[mode]]] out of [volume] units left.")

/obj/item/reagent_containers/borghypo/service
	name = "integrated drink synthesizer"
	desc = "An inbuilt synthesizer capable of fabricating a broad variety of drinks."
	icon = 'icons/obj/drinks.dmi'
	icon_state = "shaker"
	charge_cost = 20
	recharge_time = 3
	volume = 60
	max_transfer_amount = 30
	is_dispensing_drinks = TRUE
	hypo_sound = SFX_MACHINES_REAGENT_DISPENSE

TYPE_TABLE(/obj/item/reagent_containers/borghypo/service, borghypo_transfer_amounts, list(5, 10, 20, 30))

// it has literally every other type of juice..
TYPE_TABLE(/obj/item/reagent_containers/borghypo/service, borghypo_reagent_ids, list(REAGENT_ID_ALE, \
	REAGENT_ID_APPLEJUICE, \
	REAGENT_ID_BEER, \
	REAGENT_ID_BERRYJUICE, \
	REAGENT_ID_BITTERS, \
	REAGENT_ID_BLUECURACAO, \
	REAGENT_ID_CIDER, \
	REAGENT_ID_COFFEE, \
	REAGENT_ID_COGNAC, \
	REAGENT_ID_COLA, \
	REAGENT_ID_CREAM, \
	REAGENT_ID_DRGIBB, \
	REAGENT_ID_EGG, \
	REAGENT_ID_GIN, \
	REAGENT_ID_GINGERALE, \
	REAGENT_ID_HOTCOCO, \
	REAGENT_ID_ICE, \
	REAGENT_ID_ICETEA, \
	REAGENT_ID_KAHLUA, \
	REAGENT_ID_LEMONJUICE, \
	REAGENT_ID_LEMONLIME, \
	REAGENT_ID_LIMEJUICE, \
	REAGENT_ID_MEAD, \
	REAGENT_ID_MELONLIQUOR, \
	REAGENT_ID_MILK, \
	REAGENT_ID_MINT, \
	REAGENT_ID_ORANGEJUICE, \
	REAGENT_ID_REDWINE, \
	REAGENT_ID_RUM, \
	REAGENT_ID_SAKE, \
	REAGENT_ID_SODAWATER, \
	REAGENT_ID_SOYMILK, \
	REAGENT_ID_SPACEUP, \
	REAGENT_ID_SPACEMOUNTAINWIND, \
	REAGENT_ID_SPACESPICE, \
	REAGENT_ID_SPECIALWHISKEY, \
	REAGENT_ID_SUGAR, \
	REAGENT_ID_TEA, \
	REAGENT_ID_TEQUILA, \
	REAGENT_ID_TOMATOJUICE, \
	REAGENT_ID_TONIC, \
	REAGENT_ID_VERMOUTH, \
	REAGENT_ID_VODKA, \
	REAGENT_ID_WATER, \
	REAGENT_ID_WATERMELONJUICE, \
REAGENT_ID_WHISKEY))

// The drink synthesizer puts drinks into open containers and never into a person.
CAPABILITIES(/obj/item/reagent_containers/borghypo/service)
	configure(synthesizer(containers = TRUE))
	extend("synthesizer.dispense", then(PROC_REF(dispensed)))

/obj/item/reagent_containers/borghypo/service/injection_result(mob/living/M, mob/living/user)
	return OP_REFUSED

/obj/item/reagent_containers/borghypo/proc/dispensed(datum/act/op/A)
	var/atom/target = A.target
	var/mob/user = A.actor
	var/result = try_injection(target.reagents, user)
	switch(result)
		if(BORGHYPO_STATUS_CONTAINERFULL)
			if(is_dispensing_recipe)
				balloon_alert(user, "\the [target] is too full to finish the recipe!")
			else
				balloon_alert(user, "\the [target] is full!")
		if(BORGHYPO_STATUS_NOCHARGE)
			if(is_dispensing_recipe)
				balloon_alert(user, "not enough reagents to finish recipe '[selected_recipe_id]'!")
			else
				var/datum/reagent/empty_reagent = SSchemistry.ready().chemical_reagents[TYPE_TABLE_GET(src, borghypo_reagent_ids)[mode]]
				balloon_alert(user, "not enough of reagent '[empty_reagent.name]'!")
		if(BORGHYPO_STATUS_NORECIPE)
			balloon_alert(user, "recipe '[selected_recipe_id]' not found!")
		else
			if(is_dispensing_recipe)
				balloon_alert(user, "recipe '[selected_recipe_id]' dispensed to \the [target].")
			else
				balloon_alert(user, "[amount_per_transfer_from_this] units dispensed to \the [target].")
	return OP_OK
