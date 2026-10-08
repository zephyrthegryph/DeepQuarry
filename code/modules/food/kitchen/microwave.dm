#define MICROWAVE_FLAGS (OPENCONTAINER | NOREACT)
#define MICROWAVE_NORMAL 0
#define MICROWAVE_MUCK 1
#define MICROWAVE_PRE 2

#define NOT_BROKEN 0
#define KINDA_BROKEN 1
#define REALLY_BROKEN 2

#define MAX_MICROWAVE_DIRTINESS 100

/obj/machinery/microwave
	name = "microwave"
	desc = "Studies are inconclusive on whether pressing your face against the glass is harmful."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "mw"
	layer = 2.9
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 2000
	clicksound = SFX_BUTTON
	clickvol = 30
	flags = MICROWAVE_FLAGS
	circuit = /obj/item/circuitboard/microwave
	maintenance_flags = MACHINE_MAINT_PANEL | MACHINE_MAINT_FRAME
	var/operating = FALSE
	var/dirty = 0 // = {0..100} Does it need cleaning?
	var/broken = NOT_BROKEN // ={0,1,2} How broken is it???
	var/advanced_microwave = FALSE // is this an advanced microwave?
	var/always_advanced = FALSE // is this advanced no matter what?
	var/efficiency = 0
	/// The running cook loop (begin_cook_loop()): MICROWAVE_NORMAL/PRE/MUCK, cycles left, delay.
	var/loop_type = MICROWAVE_NORMAL
	var/loop_cycles = 0
	var/loop_wait = 1 SECOND

	var/item_capacity = 20
	var/appliancetype = MICROWAVE
	var/datum/looping_sound/microwave/soundloop

	var/visible_action = "turns on"
	var/audible_action = null

MSG_DEF(microwave/ejecting, span_notice("You try to open %T% and remove its contents."), span_notice("%U% tries to open %T% and remove its contents."))

CAPABILITIES(/obj/machinery/microwave)
	owns_one(nameof(soundloop), /datum/looping_sound/microwave)
	every(PROC_REF(loop_delay), then(PROC_REF(cook_loop_step)), when = nameof(loop_running))
	interface("Microwave")
	without("ui_open")
	op("cook", ui_act("cook"), then(PROC_REF(ui_act_cook)))
	op("dispose", ui_act("dispose"), then(PROC_REF(ui_act_dispose)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("microwave_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(microwave_interaction_item)))
	op("microwave_interaction_eject_pai", hand(), ungated(), stance(I_GRAB), priority(OP_PRIORITY_DEFAULT - 1), label("Eject pAI"), then(PROC_REF(microwave_interaction_eject_pai)))
	op("microwave_interaction_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), then(PROC_REF(microwave_interaction_hand)))
	op("microwave_verb_eject", menu(), label("Eject content"), needs(req_adjacent(), req_capable()), begins(MSG(microwave/ejecting)), wait(1 SECOND), then(PROC_REF(eject_done)))

/obj/machinery/microwave/advanced
	name = "deluxe microwave"
	icon = 'icons/obj/deluxemicrowave.dmi'
	always_advanced = TRUE
	advanced_microwave = TRUE

//see code/modules/food/recipes_microwave.dm for recipes

/*******************
*   Initialising
********************/

/obj/machinery/microwave/RefreshParts()
	var/smrating = get_part_rating(/obj/item/stock_parts/scanning_module)
	var/mbrating = get_part_rating(/obj/item/stock_parts/matter_bin)
	var/mlrating = get_part_rating(/obj/item/stock_parts/micro_laser)
	var/caprating = get_part_rating(/obj/item/stock_parts/capacitor)

	// If it's advanced
	if(smrating >= 3 || always_advanced)
		advanced_microwave = TRUE
		name = "deluxe microwave"
		icon = 'icons/obj/deluxemicrowave.dmi'
	else
		advanced_microwave = FALSE
		name = "microwave"
		icon = 'icons/obj/kitchen.dmi'

	// Upgrade the microwave based on the ratings of its components
	item_capacity = (advanced_microwave ? 40 : 10) * mbrating
	reagents.maximum_volume = (advanced_microwave ? 200 : 40) * mbrating
	efficiency = mlrating
	set_active_power_usage(max(100, 2000 / caprating))

/obj/machinery/microwave/Initialize(mapload)
	. = ..()

	create_reagents(100)
	rel_set(reagents, nameof(reagents.my_atom), src)

	default_apply_parts()

	rel_set(src, nameof(soundloop), new /datum/looping_sound/microwave(list(src), FALSE))

// its contents are disposed and a pAI inside is ejected.
/obj/machinery/microwave/on_destroy(force)
	dispose(FALSE)
	if(paicard)
		ejectpai()
	..()

/*******************
*   Item Adding
********************/

/// Appearance reader: broken, bloody or clean.
/obj/machinery/microwave/proc/appearance_mw_condition()
	if(broken)
		return "b"
	if(dirty >= MAX_MICROWAVE_DIRTINESS)
		return "bloody"
	return "clean"

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/microwave/draw(datum/look/look)
	..()
	look.state("mw[operating ? "1" : ""]")
	switch("[appearance_mw_condition()]")
		if("b")
			look.state("mwb")
		if("bloody")
			look.state("mwbloody0")
	if(appearance_mw_bloody_operating() == 1)
		look.state("mwbloody1")

// The cooking pot keeps its own procedural icon override (fantasy_items.dm) that never calls the parent.

/// Appearance reader: bloody (not broken) and running.
/obj/machinery/microwave/proc/appearance_mw_bloody_operating()
	return !broken && dirty >= MAX_MICROWAVE_DIRTINESS && operating ? 1 : 0

/obj/machinery/microwave/proc/post_state_change()
	update_static_data_for_all_viewers()
	changed(src)
	SStgui.update_uis(src)

/// Old attackby.
/obj/machinery/microwave/proc/microwave_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(handle_broken(O, user)) return OP_OK
	if(handle_dirty(O, user)) return OP_OK
	if(default_part_replacement(user, O)) return OP_OK
	if(try_insert_item(O, user)) return OP_OK
	if(try_insert_reagent(O, user)) return OP_PASS // the container's afterattack pours
	if(istype(O,/obj/item/grab))
		var/obj/item/grab/G = O
		to_chat(user, span_warning("Unfortunately, the laws of physics prevent you from inserting \the [G?.grab_target()] into \the [src]."))
		return OP_OK
	if(istype(O, /obj/item/paicard))
		if(!paicard)
			insertpai(user, O)
			return OP_OK
		to_chat(user, span_warning("There is already a pAI inserted, and you don't feel like cooking \the [O]."))
		return OP_OK
	if(istype(O, /obj/item/gripper)) //Grippers count as 'attacking' before the thing they're holding. Don't send a message.
		return OP_PASS
	to_chat(user, span_warning("You have no idea what you can cook with \the [O]."))
	post_state_change()
	return OP_DECLINE

/obj/machinery/microwave/proc/handle_broken(obj/item/O, mob/user)
	if(src.broken <= NOT_BROKEN)
		return FALSE

	to_chat(user, span_warning("It's broken!"))
	return TRUE

/obj/machinery/microwave/proc/do_repair_step(mob/user, obj/item/tool, full_repair = FALSE)
	use_tool(user, tool, src, delay = 2 SECONDS, volume = 50, start_self = "You start to fix part of \the [src].", start_others = "\The [user] starts to fix part of \the [src].", receiver = src, on_done = PROC_REF(do_repair_step_tool_done), done_args = list(user, full_repair))
	return TRUE

/obj/machinery/microwave/proc/do_repair_step_tool_done(mob/user, full_repair)

	act_message(user, src, MSG_SELF(span_notice(full_repair ? "You have fixed %T%." : "You have fixed part of %T%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + (full_repair ? " fixes %T%." : " fixes part of %T%."))))

	broken = full_repair ? NOT_BROKEN : KINDA_BROKEN
	flags |= MICROWAVE_FLAGS

	post_state_change()
	return TRUE

/obj/machinery/microwave/proc/handle_dirty(obj/item/O, mob/user)
	if(dirty < MAX_MICROWAVE_DIRTINESS)
		return FALSE

	if(!is_type_in_list(O, list(/obj/item/soap, /obj/item/reagent_containers/spray/cleaner, /obj/item/reagent_containers/glass/rag)))
		to_chat(user, span_warning("It's dirty!"))
		return TRUE

	act_message(user, src, MSG_SELF(span_notice("You start to clean %T%.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " starts to clean %T%.")))

	task_timed(user, 2 SECONDS, src, src, PROC_REF(clean_done), list(user))
	return TRUE

/obj/machinery/microwave/proc/clean_done(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You have cleaned %T%.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " has cleaned %T%.")))

	dirty = 0
	flags |= MICROWAVE_FLAGS
	post_state_change()

/obj/machinery/microwave/proc/try_insert_item(obj/item/O, mob/user)
	if(is_type_in_list(O, GLOB.acceptable_items))
		if(length(cookingContents()) >= (item_capacity))
			to_chat(user, span_warning("\The [src] is full of ingredients, you cannot put more."))
			return TRUE
		var/obj/item/stack/our_stack = O
		if(istype(our_stack) && our_stack.get_amount() > 0)
			var/obj/item/stack/St = our_stack.split(1)
			St.forceMove(src)
			act_message(user, src, MSG_SELF(span_notice("You add one [O] to %T%.")), MSG_OTHERS(span_notice(span_bold("%U%") + " has added one [O] to %T%.")))
			return TRUE
		if(!own_bring_in(src, nameof(contents), O, null, user, TRUE, null, FALSE))
			return TRUE
		act_message(user, src, MSG_SELF(span_notice("You add %I% to %T%.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " has added %I% to %T%.")), item = O)
		return TRUE
	if(istype(O, /obj/item/storage/bag/plants)) // There might be a better way about making plant bags dump their contents into a microwave, but it works.
		var/obj/item/storage/bag/plants/bag = O
		var/failed = 1
		for(var/obj/item/G in contents_of(O))
			if(!G.reagents || !G.reagents.total_volume)
				continue
			failed = 0
			if(length(cookingContents()) >= (item_capacity))
				to_chat(user, span_warning("\The [src] is full of ingredients, you cannot put more."))
				return TRUE
			bag.remove_from_storage(G, src)
			if(length(cookingContents()) >= (item_capacity))
				break

		if(failed)
			to_chat(user, "Nothing in \the [O] can be used for cooking.")
			return TRUE

		to_chat(user, !length(O.contents) ? "You empty \the [O] into \the [src]." : "You fill \the [src] from \the [O].")
		return TRUE
	return FALSE

/obj/machinery/microwave/proc/try_insert_reagent(obj/item/O, mob/user)
	if(is_type_in_list(O, list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food/drinks, /obj/item/reagent_containers/food/condiment)))
		if (!O.reagents)
			to_chat(user, span_warning("\The [O] is empty!"))
			return TRUE
		for (var/datum/reagent/R in O.reagents.reagent_list)
			if (!(R.id in GLOB.acceptable_reagents))
				to_chat(user, span_warning("\The [O] contains components unsuitable for cooking."))
				return TRUE
		// gotta let afterattack resolve
		after(src, 1 SECOND, TYPE_PROC_REF(/datum, update_static_data_for_all_viewers))
		return TRUE
	return FALSE

/obj/machinery/microwave/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(broken == REALLY_BROKEN)
		do_repair_step(user, tool, FALSE)
		return OP_OK
	return OP_DECLINE

/obj/machinery/microwave/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(broken == KINDA_BROKEN)
		do_repair_step(user, tool, TRUE)
		return OP_OK
	return OP_DECLINE

/obj/machinery/microwave/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(panel_open)
		return OP_DECLINE
	act_message(user, src, MSG_SELF(span_notice("You attempt to [anchored ? "unsecure" : "secure"] %T%.")), \
		MSG_OTHERS(span_notice("%U% begins [anchored ? "unsecuring" : "securing"] %T%.")))
	task_start(/datum/task/timed/microwave_secure, user, src, duration = (2 SECONDS) / tool.toolspeed)
	return OP_OK

/datum/task/timed/microwave_secure
	complete_proc = /obj/machinery/microwave/proc/secure_done
	fail_message = span_notice("You decide not to do that.")

/obj/machinery/microwave/proc/secure_done(datum/task/timed/microwave_secure/task)
	var/mob/user = task.actor
	act_message(user, src, MSG_SELF(span_notice("You [anchored ? "unsecure" : "secure"] %T%.")), \
		MSG_OTHERS(span_notice("%U% [anchored ? "unsecures" : "secures"] %T%.")))
	set_anchored(!anchored)

/obj/machinery/microwave/tgui_status(mob/user)
	if(user == paicard?.pai)
		return STATUS_INTERACTIVE
	. = ..()

/// Old attack_hand with Grab held: pull the pAI out. Without one, the ordinary touch.
/obj/machinery/microwave/proc/microwave_interaction_eject_pai(datum/act/op/A)
	var/mob/user = A.actor
	if(!paicard)
		return OP_DECLINE
	ejectpai(user)
	return OP_OK

/// Old attack_hand.
/obj/machinery/microwave/proc/microwave_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return OP_OK

/*******************
*   Microwave Menu
********************/

/obj/machinery/microwave/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/kitchen_recipes),
		get_asset_datum(/datum/asset/simple/microwave)
	)

/obj/machinery/microwave/tgui_static_data(mob/user)
	var/list/data = ..()

	var/datum/recipe/recipe = select_recipe(GLOB.available_recipes[appliancetype], src)
	data["recipe"] = recipe ? sanitize_css_class_name("[recipe.type]") : null
	data["recipe_name"] = recipe ? initial(recipe.result:name) : null

	return data

/obj/machinery/microwave/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["broken"] = broken
	data["operating"] = operating
	var/list/merged_1 = ui_data_obj_machinery_microwave(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/microwave's window data.
/obj/machinery/microwave/proc/ui_data_obj_machinery_microwave(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["dirty"] = dirty == MAX_MICROWAVE_DIRTINESS
	data["items"] = get_items_list()

	var/list/reagents_data = list()
	for(var/datum/reagent/R in reagents.reagent_list)
		var/display_name = R.name
		if(R.id == REAGENT_ID_CAPSAICIN)
			display_name = "Hotsauce"
		if(R.id == REAGENT_ID_FROSTOIL)
			display_name = "Coldsauce"
		UNTYPED_LIST_ADD(reagents_data, list(
			"name" = display_name,
			"amt" = R.volume,
			"extra" = "unit[R.volume > 1 ? "s" : ""]",
			"color" = R.color,
		))
	data["reagents"] = reagents_data

	return data

/obj/machinery/microwave/proc/get_items_list()
	var/list/data = list()

	var/list/item_count = list()
	var/list/icons = list()

	for(var/obj/ingredient in cookingContents())
		item_count[ingredient.name]++
		if(!icons[ingredient.name])
			icons[ingredient.name] = list("icon" = ingredient.icon, "icon_state" = ingredient.icon_state)

	for(var/item in item_count)
		var/display_name = item
		var/plural_name = display_name + plural_s(src, display_name)
		var/ingredient_amt = item_count[item]
		data.Add(list(list(
			"name" = capitalize(display_name),
			"amt" = ingredient_amt,
			"extra" = ingredient_amt == 1 ? display_name : plural_name,
			"icon" = icons[item],
		)))

	return data

/obj/machinery/microwave/proc/ui_gate(datum/act/op/A)
	if(operating)
		return FALSE
	return TRUE

/obj/machinery/microwave/proc/ui_act_cook(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	cook()
	return TRUE

/obj/machinery/microwave/proc/ui_act_dispose(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	dispose(user = user)
	return TRUE

/***********************************
*   Microwave Menu Handling/Cooking
************************************/

/obj/machinery/microwave/proc/cook()
	if(!operable())
		return

	if(operating || broken > NOT_BROKEN || panel_open || !anchored || dirty >= MAX_MICROWAVE_DIRTINESS)
		return

	if(prob(max((5 / efficiency) - 5, dirty * 5)))
		muck()
		return

	if(prob(min(dirty * 5, 100)))
		start_can_fail()

	start()

/// A cook loop is running: cook_loop() every loop_wait until its cycles run out.
/obj/machinery/microwave/var/loop_running = FALSE
TRACKED_BRIDGED(/obj/machinery/microwave, loop_running, CHANGE_MACHINE_SETTINGS)

/// The cook loop's cadence.
/obj/machinery/microwave/proc/loop_delay(datum/act/A)
	return loop_wait

/// One scheduled cook-loop cycle.
/obj/machinery/microwave/proc/cook_loop_step(datum/act/timer/A)
	cook_loop()

/obj/machinery/microwave/proc/start()
	wzhzhzh()
	begin_cook_loop()

/obj/machinery/microwave/proc/start_can_fail()
	wzhzhzh()
	begin_cook_loop(MICROWAVE_PRE, 4)

/obj/machinery/microwave/proc/muck()
	wzhzhzh()
	play_sfx(src, SFX_EFFECTS_SPLAT) // Play a splat sound
	src.dirty = MAX_MICROWAVE_DIRTINESS // Make it dirty so it can't be used util cleaned
	post_state_change()
	begin_cook_loop(MICROWAVE_MUCK, 4)

/// Starts (or restarts) the cook loop: the first cook_loop() runs now, the rest every loop_wait.
/obj/machinery/microwave/proc/begin_cook_loop(type = MICROWAVE_NORMAL, cycles = 10)
	loop_type = type
	loop_cycles = cycles
	loop_wait = max(12 - 2 * efficiency, 2)
	if(cook_loop() != REPEAT_STOP)
		set_loop_running(TRUE)

/// One cook-loop cycle (every() while loop_running).
/obj/machinery/microwave/proc/cook_loop()
	if((broken_now()) && loop_type == MICROWAVE_PRE)
		set_loop_running(FALSE)
		broke()
		return REPEAT_STOP

	if(loop_cycles <= 0 || !length(cookingContents()))
		switch(loop_type)
			if(MICROWAVE_NORMAL)
				set_loop_running(FALSE)
				loop_finish() // may muck(), which begins a new loop
			if(MICROWAVE_MUCK)
				set_loop_running(FALSE)
				muck_finish()
				stop(FALSE)
			if(MICROWAVE_PRE)
				begin_cook_loop(MICROWAVE_NORMAL, 10)
				return
		return REPEAT_STOP

	loop_cycles--

/obj/machinery/microwave/power_change()
	. = ..()
	if((power_lost()) && operating)
		broke()
		dispose(FALSE)

/obj/machinery/microwave/proc/loop_finish()
	var/datum/recipe/recipe = select_recipe(GLOB.available_recipes[appliancetype], src)
	if(!recipe)
		if(length(cookingContents()) >= 1)
			dirty += 1
			var/obj/item/cooked = fail()
			cooked.forceMove(loc)
			if(prob(max(10,dirty*5)))
				muck()
			if(has_extra_item())
				broke()
		stop()
		return

	var/result = recipe.result
	var/valid = TRUE
	var/list/cooked_items = list()
	var/obj/temp = new /obj(src) //To prevent infinite loops, all results will be moved into a temporary location so they're not considered as inputs for other recipes
	while(valid)
		var/list/things = list()
		things.Add(recipe.make_food(src))
		cooked_items += things
		//Move cooked things to the buffer so they're not considered as ingredients
		for(var/atom/movable/AM in things)
			AM.forceMove(temp)

		valid = FALSE
		recipe.after_cook(src)
		recipe = select_recipe(GLOB.available_recipes[appliancetype], src)
		if(recipe && recipe.result == result)
			valid = TRUE

	for(var/atom/movable/R as anything in cooked_items)
		R.forceMove(src) //Move everything from the buffer back to the container

	QDEL_NULL(temp)//Delete buffer object

	//Any leftover reagents are divided amongst the foods
	var/total = reagents.total_volume
	for(var/obj/item/reagent_containers/food/snacks/S in cooked_items)
		reagents.trans_to_holder(S.reagents, total/cooked_items.len)

	for(var/obj/item/reagent_containers/food/snacks/S in cookingContents())
		S.cook()

	dispose(FALSE) //clear out anything left
	stop(TRUE)

	return

/obj/machinery/microwave/proc/wzhzhzh() // Whoever named this proc is fucking literally Satan. ~ Z
	visible_message(span_notice("\The [src] [visible_action]."), span_notice("You hear a [audible_action ? audible_action : "[src]"]."))
	operating = TRUE
	set_use_power(USE_POWER_ACTIVE)
	post_state_change()
	soundloop.start()

/obj/machinery/microwave/proc/has_extra_item() //- coded to have different microwaves be able to handle different items
	var/basic_microwave_types = list(/obj/item/reagent_containers/food, /obj/item/grown)
	var/advanced_microwave_types = list(/obj/item/slime_extract, /obj/item/organ, /obj/item/stack/material)
	for (var/obj/O in cookingContents())
		if(!is_type_in_list(O, basic_microwave_types) && (!advanced_microwave || !is_type_in_list(O, advanced_microwave_types)))
			return TRUE
	return FALSE

/obj/machinery/microwave/proc/stop(success = TRUE)
	if(success)
		play_sfx(src.loc, SFX_MACHINES_DING)
	operating = FALSE // Turn it off again aferwards
	if(broken)
		set_use_power(USE_POWER_OFF)
	else
		set_use_power(USE_POWER_IDLE)
	post_state_change()
	soundloop.stop()

/obj/machinery/microwave/proc/dispose(message = TRUE, mob/user)
	for (var/atom/movable/A in cookingContents())
		A.forceMove(loc)
	if (src.reagents.total_volume)
		src.dirty++
	src.reagents.clear_reagents()
	if(message)
		to_chat(user, span_notice("You dispose of \the [src]'s contents."))
	SStgui.update_uis(src)

/obj/machinery/microwave/proc/muck_finish()
	src.visible_message(span_warning("\The [src] gets covered in muck!"))
	src.flags &= ~MICROWAVE_FLAGS //So you can't add condiments

/obj/machinery/microwave/proc/broke(spark = TRUE)
	if(spark)
		fx_sparks(src, 2)
	src.visible_message(span_warning("\The [src] breaks!")) //Let them know they're stupid
	src.broken = REALLY_BROKEN // Make it broken so it can't be used util fixed
	src.flags &= ~MICROWAVE_FLAGS //So you can't add condiments
	src.ejectpai() // If it broke, time to yeet the PAI.

/obj/machinery/microwave/proc/fail()
	var/obj/item/reagent_containers/food/snacks/badrecipe/ffuu = new(src)
	var/amount = 0
	for (var/obj/O in cookingContents() - ffuu)
		amount++
		if(O.reagents)
			var/id = O.reagents.get_master_reagent_id()
			if(id)
				amount+=O.reagents.get_reagent_amount(id)
		if(istype(O, /obj/item/holder))
			var/obj/item/holder/H = O
			if(H.held_mob)
				spent(H.held_mob)
		consume(O)
	src.reagents.clear_reagents()
	ffuu.reagents.add_reagent(REAGENT_ID_CARBON, amount)
	ffuu.reagents.add_reagent(REAGENT_ID_TOXIN, amount/10)
	return ffuu

/obj/machinery/microwave/proc/eject_done(datum/act/op/A)
	var/mob/user = A.actor
	if(operating)
		to_chat(user, span_warning("You can't do that, [src] door is locked!"))
		return

	act_message(user, src, MSG_SELF(span_notice("You have opened %T% and taken out [english_list(cookingContents())].")), \
		MSG_OTHERS(span_notice("%U% opened %T% and has taken out [english_list(cookingContents())].")))
	dispose(user = user)

/obj/machinery/microwave/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(!mover)
		return TRUE
	if(mover.checkpass(PASSTABLE))
	//Animals can run under them, lots of empty space
		return TRUE
	return ..()

/datum/recipe/splat // We use this to handle cooking micros (or mice, etc) in a microwave. Janky but it works better than snowflake code to handle the same thing.
	items = list(
		/obj/item/holder
	)
	result = /obj/effect/decal/cleanable/blood/gibs
	wiki_flag = WIKI_SPOILER

/datum/recipe/splat/before_cook(obj/container)
	if(istype(container, /obj/machinery/microwave))
		var/obj/machinery/microwave/M = container
		M.muck()
		play_sfx(container.loc, SFX_ITEMS_DROP_FLESH)
	. = ..()

/datum/recipe/splat/make_food(obj/container)
	for(var/obj/item/holder/H in contents_of(container))
		if(H.held_mob)
			to_chat(H.held_mob, span_danger("You hear an earsplitting humming and your head aches!"))
			destroyed(H.held_mob, src, BURN)
			rel_clear(H, nameof(H.held_mob))
			spent(H)

	. = ..()

/obj/machinery/microwave/proc/cookingContents() // this is a better way to deal with the contents of a microwave, since the previous method is stupid.
	var/list/workingList = contents.Copy() // Using the copy proc because otherwise the two lists seem to become soul bonded.
	if(component_parts)
		workingList -= component_parts
	workingList -= circuit
	if(paicard)
		workingList -= paicard
	for(var/M in workingList)
		if(istype(M, circuit)) // Yes, we remove circuit twice. Yes, it's necessary. Yes, it's stupid.
			workingList -= M
	return workingList

#undef MICROWAVE_FLAGS
#undef MICROWAVE_NORMAL
#undef MICROWAVE_MUCK
#undef MICROWAVE_PRE

#undef NOT_BROKEN
#undef KINDA_BROKEN
#undef REALLY_BROKEN

#undef MAX_MICROWAVE_DIRTINESS
