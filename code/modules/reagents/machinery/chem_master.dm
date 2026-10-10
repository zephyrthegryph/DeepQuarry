/obj/machinery/chem_master
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS
	name = "ChemMaster 3000"
	desc = "Used to separate and package chemicals in to patches, pills, or bottles. Warranty void if used to create Space Drugs."
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	icon = 'icons/obj/chemical.dmi'
	icon_state = "mixer0"
	circuit = /obj/item/circuitboard/chem_master
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	var/obj/item/reagent_containers/beaker = null
	var/obj/item/storage/pill_bottle/loaded_pill_bottle = null
	var/list/pill_bottle_wrappers = null // Enable customizing pill bottle type
	mode = 0
	var/condi = 0
	var/useramount = 15 // Last used amount
	var/pillamount = 10
	var/list/bottle_styles
	var/bottlesprite = 1
	var/pillsprite = 1
	var/max_pill_count = 20
	var/printing = FALSE
	flags = OPENCONTAINER
	clicksound = SFX_BUTTON

/obj/machinery/chem_master/draw(datum/look/look)
	..()
	look.state(beaker ? "mixer1" : "mixer0")

/// A beaker slot is free.
/obj/machinery/chem_master/proc/chem_master_no_beaker(datum/act/op/A)
	return !beaker

/// The old attackby: a glass or a food container goes in.
/obj/machinery/chem_master/proc/beaker_loaded(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/B = A.held
	if(!move_into(src, nameof(src.beaker), B, user))
		return OP_OK
	to_chat(user, "You add \the [B] to the machine.")
	return OP_OK

/// The pill bottle slot is free.
/obj/machinery/chem_master/proc/chem_master_no_pill_bottle(datum/act/op/A)
	return !loaded_pill_bottle

/// The old attackby: a pill bottle goes in the dispenser slot.
/obj/machinery/chem_master/proc/pill_bottle_loaded(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/storage/pill_bottle/PB = A.held
	// The machine reads .contents directly below (C5); a bottle loaded
	// straight off a turf or out of a latent holder still holds its
	// pills as a declared generator until now.
	PB.make_contents_real()
	if(!move_into(src, nameof(src.loaded_pill_bottle), PB, user))
		return OP_OK
	to_chat(user, "You add \the [loaded_pill_bottle] into the dispenser slot.")
	return OP_OK

MSG_DEF_SELF(chem_master/beaker_loaded, "A beaker is already loaded into the machine.")
MSG_DEF_SELF(chem_master/pill_bottle_loaded, "A pill bottle is already loaded into the machine.")

/obj/machinery/chem_master/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet/chem_master),
	)

// The window: its buttons are ops, and every modal of the old ui_modal_opened()/ui_modal_answered() pair is an op bound to "modal:<id>" whose question
// is asked inline (a modal of the window); a modal that chained to another (a count, then the name) is one op with two steps.
CAPABILITIES(/obj/machinery/chem_master)
	reagents(900) // the buffer: a huge number so it should (probably) never dump your reagents
	owns_one(nameof(beaker), /obj/item/reagent_containers)
	owns_one(nameof(loaded_pill_bottle), /obj/item/storage/pill_bottle)
	op("load_beaker", item(/obj/item/reagent_containers), when(req(list(/obj/item/reagent_containers/glass, /obj/item/reagent_containers/food))), label("Load beaker"),
		needs(req(PROC_REF(chem_master_no_beaker), because = MSG(chem_master/beaker_loaded))), then(PROC_REF(beaker_loaded)))
	op("load_pill_bottle", item(/obj/item/storage/pill_bottle), label("Load pill bottle"),
		needs(req(PROC_REF(chem_master_no_pill_bottle), because = MSG(chem_master/pill_bottle_loaded))), then(PROC_REF(pill_bottle_loaded)))
	interface("ChemMaster")
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("ejectp", ui_act("ejectp"), then(PROC_REF(ui_act_ejectp)))
	op("print", ui_act("print", arg("beaker", num(default = 0)), arg("idx", num(default = 0))), then(PROC_REF(ui_act_print)))
	op("add", ui_act("add", arg("amount", num()), arg("id", schema_text(4096))), then(PROC_REF(ui_act_add)))
	op("remove", ui_act("remove", arg("amount", num()), arg("id")), then(PROC_REF(ui_act_remove)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("create_condi_bottle", ui_act("create_condi_bottle"), then(PROC_REF(ui_act_create_condi_bottle)))
	op("analyze", ui_act("modal:analyze", arg("arguments")), then(PROC_REF(modal_analyze)))
	op("change_pill_bottle_style", ui_act("modal:change_pill_bottle_style", arg("arguments")), needs(req(PROC_REF(has_pill_bottle), silent = TRUE)),
		asks(/datum/prompt/choice, fields = list("question" = "Please select a pill bottle wrapper:", "choices" = computed(PROC_REF(wrapper_names)), "default" = computed(PROC_REF(current_wrapper_name)), "inline" = TRUE, "timeout" = 0), step = "wrapper"),
		then(PROC_REF(modal_pill_bottle_style)))
	op("addcustom", ui_act("modal:addcustom", arg("arguments")), needs(req(PROC_REF(beaker_has_reagents), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = "Please enter the amount to transfer to buffer:", "default" = nameof(useramount), "inline" = TRUE, "timeout" = 0), step = "amount"),
		then(PROC_REF(modal_addcustom)))
	op("removecustom", ui_act("modal:removecustom", arg("arguments")), needs(req(PROC_REF(buffer_has_reagents), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(removecustom_question)), "default" = nameof(useramount), "inline" = TRUE, "timeout" = 0), step = "amount"),
		then(PROC_REF(modal_removecustom)))
	op("create_condi_pack", ui_act("modal:create_condi_pack", arg("arguments")), needs(req(PROC_REF(makes_condiments), silent = TRUE)),
		asks(/datum/prompt/text, fields = list("question" = "Please name your new condiment pack:", "default" = computed(PROC_REF(master_reagent_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_condi_pack)))
	op("create_pill", ui_act("modal:create_pill", arg("arguments")), needs(req(PROC_REF(makes_drugs_of_passed_count), silent = TRUE)),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(pill_name_question)), "default" = computed(PROC_REF(pill_default_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_pill)))
	op("create_pill_multiple", ui_act("modal:create_pill_multiple", arg("arguments")), needs(req(PROC_REF(makes_drugs), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = "Please enter the amount of pills to make (max [MAX_MULTI_AMOUNT] at a time):", "default" = nameof(pillamount), "min_value" = 1, "inline" = TRUE, "timeout" = 0), step = "count"),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(pill_name_question)), "default" = computed(PROC_REF(pill_default_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "modal_id" = "create_pill", "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_pill)))
	op("change_pill_style", ui_act("modal:change_pill_style", arg("arguments")),
		asks(/datum/prompt/choice, fields = list("question" = "Please select the new style for pills:", "choices" = computed(PROC_REF(pill_style_choices)), "default" = computed(PROC_REF(pill_style_current)), "bento" = "spritesheet", "inline" = TRUE, "timeout" = 0), step = "style"),
		then(PROC_REF(modal_change_pill_style)))
	op("create_patch", ui_act("modal:create_patch", arg("arguments")), needs(req(PROC_REF(makes_drugs_of_passed_count), silent = TRUE)),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(patch_name_question)), "default" = computed(PROC_REF(patch_default_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_patch)))
	op("create_patch_multiple", ui_act("modal:create_patch_multiple", arg("arguments")), needs(req(PROC_REF(makes_drugs), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = "Please enter the amount of patches to make (max [MAX_MULTI_AMOUNT] at a time):", "default" = nameof(pillamount), "min_value" = 1, "inline" = TRUE, "timeout" = 0), step = "count"),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(patch_name_question)), "default" = computed(PROC_REF(patch_default_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "modal_id" = "create_patch", "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_patch)))
	op("create_bottle", ui_act("modal:create_bottle", arg("arguments")), needs(req(PROC_REF(makes_drugs_of_passed_count), silent = TRUE)),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(bottle_name_question)), "default" = computed(PROC_REF(master_reagent_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_bottle)))
	op("create_bottle_two", ui_act("modal:create_bottle_two", arg("arguments")), needs(req(PROC_REF(makes_drugs), silent = TRUE)),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(bottle_name_question)), "default" = computed(PROC_REF(master_reagent_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_bottle)))
	op("create_bottle_multiple", ui_act("modal:create_bottle_multiple", arg("arguments")), needs(req(PROC_REF(makes_drugs), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("question" = "Please enter the amount of bottles to make (max [MAX_MULTI_AMOUNT] at a time):", "default" = computed(PROC_REF(bottle_default_count)), "min_value" = 1, "inline" = TRUE, "timeout" = 0), step = "count"),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(bottle_name_question)), "default" = computed(PROC_REF(master_reagent_name)), "max_len" = MAX_CUSTOM_NAME_LEN, "modal_id" = "create_bottle", "inline" = TRUE, "timeout" = 0), step = "name"),
		then(PROC_REF(modal_create_bottle)))
	op("change_bottle_style", ui_act("modal:change_bottle_style", arg("arguments")),
		asks(/datum/prompt/choice, fields = list("question" = "Please select the new style for bottles:", "choices" = computed(PROC_REF(bottle_style_choices)), "default" = computed(PROC_REF(bottle_style_current)), "bento" = "spritesheet", "inline" = TRUE, "timeout" = 0), step = "style"),
		then(PROC_REF(modal_change_bottle_style)))
	default_parts()

/// The window's data.
/obj/machinery/chem_master/ui_data(datum/act/eval/A)
	. = list()
	.["condi"] = condi
	.["pillsprite"] = pillsprite
	.["bottlesprite"] = bottlesprite
	.["printing"] = printing
	var/list/part = ui_data_part_chem_master(A)
	for(var/key in part)
		.[key] = part[key]

/// The computed part of the window's data.
/obj/machinery/chem_master/proc/ui_data_part_chem_master(datum/act/eval/A)
	var/list/data = list()


	data["loaded_pill_bottle"] = !!loaded_pill_bottle
	if(loaded_pill_bottle)
		data["loaded_pill_bottle_name"] = loaded_pill_bottle.name
		data["loaded_pill_bottle_contents_len"] = contents_count(loaded_pill_bottle)
		data["loaded_pill_bottle_storage_slots"] = loaded_pill_bottle.max_storage_space

	data["beaker"] = !!beaker
	if(beaker)
		var/list/beaker_reagents_list = list()
		data["beaker_reagents"] = beaker_reagents_list
		for(var/datum/reagent/R in beaker.reagents?.reagent_list)
			beaker_reagents_list[++beaker_reagents_list.len] = list("name" = R.name, "volume" = R.volume, "description" = R.description, "id" = R.id)

		var/list/buffer_reagents_list = list()
		data["buffer_reagents"] = buffer_reagents_list
		for(var/datum/reagent/R in reagents.reagent_list)
			buffer_reagents_list[++buffer_reagents_list.len] = list("name" = R.name, "volume" = R.volume, "id" = R.id, "description" = R.description)

	data["mode"] = mode

	// the window's modal (the engine adds it too; the key is always sent, as it was)
	data["modal"] = tgui_modal_data(src)

	return data


// ---- what the modals ask about (requirements read when the modal is opened and again when it is answered) ----

/obj/machinery/chem_master/proc/has_pill_bottle(datum/act/op/A)
	return !!loaded_pill_bottle

/obj/machinery/chem_master/proc/beaker_has_reagents(datum/act/op/A)
	return beaker?.reagents?.total_volume > 0

/obj/machinery/chem_master/proc/buffer_has_reagents(datum/act/op/A)
	return reagents.total_volume > 0

/obj/machinery/chem_master/proc/makes_condiments(datum/act/op/A)
	return condi && reagents.total_volume > 0

/obj/machinery/chem_master/proc/makes_drugs(datum/act/op/A)
	return !condi && reagents.total_volume > 0

/// The client passed a count (`arguments["num"]`, one by default) and there is something to make it from.
/obj/machinery/chem_master/proc/makes_drugs_of_passed_count(datum/act/op/A)
	return makes_drugs(A) && passed_count(A) > 0

/// The count the client passed with the modal (`arguments["num"]`), one when none.
/obj/machinery/chem_master/proc/passed_count(datum/act/op/A)
	var/list/arguments = A.args["arguments"]
	return round(text2num(islist(arguments) ? arguments["num"] : null) || 1)

/// The count of the thing to make: the answered count of a chained modal, else the passed one (two for the two-bottle button).
/obj/machinery/chem_master/proc/make_count(datum/act/op/A)
	if(A.key == "create_bottle_two")
		return 2
	var/answered = A.step_value("count")
	return isnull(answered) ? passed_count(A) : round(answered)

/obj/machinery/chem_master/proc/master_reagent_name(datum/act/op/A)
	return reagents.get_master_reagent_name()

/obj/machinery/chem_master/proc/removecustom_question(datum/act/op/A)
	return "Please enter the amount to transfer to [mode ? "beaker" : "disposal"]:"

/obj/machinery/chem_master/proc/pill_bottle_wrapper_list()
	if(!pill_bottle_wrappers)
		pill_bottle_wrappers = list(
			"CLEAR" = "Default",
			COLOR_RED = "Red",
			COLOR_GREEN = "Green",
			COLOR_PALE_BTL_GREEN = "Pale green",
			COLOR_BLUE = "Blue",
			COLOR_CYAN_BLUE = "Light blue",
			COLOR_TEAL = "Teal",
			COLOR_YELLOW = "Yellow",
			COLOR_ORANGE = "Orange",
			COLOR_PINK = "Pink",
			COLOR_MAROON = "Brown"
		)
	return pill_bottle_wrappers

/obj/machinery/chem_master/proc/wrapper_names(datum/act/op/A)
	. = list()
	var/list/wrappers = pill_bottle_wrapper_list()
	for(var/col in wrappers)
		. += wrappers[col]

/obj/machinery/chem_master/proc/current_wrapper_name(datum/act/op/A)
	var/list/wrappers = pill_bottle_wrapper_list()
	return wrappers[loaded_pill_bottle?.wrapper_color] || "Default"

/obj/machinery/chem_master/proc/pill_name_question(datum/act/op/A)
	var/num = make_count(A)
	return "Please name your [num == 1 ? "new pill" : "[num] new pills"]:"

/obj/machinery/chem_master/proc/pill_default_name(datum/act/op/A)
	return "[reagents.get_master_reagent_name()] ([CLAMP(reagents.total_volume / max(1, make_count(A)), 0, MAX_UNITS_PER_PILL)]u)"

/obj/machinery/chem_master/proc/patch_name_question(datum/act/op/A)
	var/num = make_count(A)
	return "Please name your [num == 1 ? "new patch" : "[num] new patches"]:"

/obj/machinery/chem_master/proc/patch_default_name(datum/act/op/A)
	return "[reagents.get_master_reagent_name()] ([CLAMP(reagents.total_volume / max(1, make_count(A)), 0, MAX_UNITS_PER_PATCH)]u)"

/obj/machinery/chem_master/proc/bottle_name_question(datum/act/op/A)
	var/num = make_count(A)
	return "Please name your [num == 1 ? "new bottle" : "[num] new bottles"] ([CLAMP(reagents.total_volume / max(1, num), 0, MAX_UNITS_PER_BOTTLE)]u in bottle):"

/obj/machinery/chem_master/proc/bottle_default_count(datum/act/op/A)
	return pillamount / 5

/obj/machinery/chem_master/proc/pill_style_choices(datum/act/op/A)
	. = list()
	for(var/i = 1 to MAX_PILL_SPRITE)
		. += "chem_master32x32 pill[i]"

/obj/machinery/chem_master/proc/pill_style_current(datum/act/op/A)
	return "chem_master32x32 pill[pillsprite]"

/obj/machinery/chem_master/proc/bottle_style_choices(datum/act/op/A)
	. = list()
	for(var/i = 1 to MAX_BOTTLE_SPRITE)
		. += "chem_master32x32 bottle-[i]"

/obj/machinery/chem_master/proc/bottle_style_current(datum/act/op/A)
	return "chem_master32x32 bottle-[bottlesprite]"

// ---- the modals' effects ----

/// The analysis of one reagent, shown as a message modal (no question: the client draws it from the arguments).
/obj/machinery/chem_master/proc/modal_analyze(datum/act/op/A, list/arguments)
	arguments = islist(arguments) ? arguments.Copy() : list()
	var/idx = text2num(arguments["idx"]) || 0
	var/from_beaker = text2num(arguments["beaker"]) || FALSE
	var/reagent_list = (from_beaker && beaker) ? beaker.reagents.reagent_list : reagents.reagent_list
	if(idx < 1 || idx > length(reagent_list))
		return
	var/datum/reagent/R = reagent_list[idx]
	var/list/result = list("idx" = idx, "name" = R.name, "desc" = R.description)
	if(!condi && istype(R, /datum/reagent/blood))
		var/datum/reagent/blood/B = R
		result["blood_type"] = B.data["blood_type"]
		result["blood_dna"] = B.data["blood_DNA"]
		result["changeling"] = B.data["changeling"]
	arguments["analysis"] = result
	tgui_modal_message(src, "analyze", "", null, arguments)
	return TRUE

/obj/machinery/chem_master/proc/modal_pill_bottle_style(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	if(!loaded_pill_bottle)
		return
	var/answer = A.step_value("wrapper")
	var/color = "CLEAR"
	var/list/wrappers = pill_bottle_wrapper_list()
	for(var/col in wrappers)
		if(wrappers[col] == answer)
			color = col
			break
	if(length(color) && color != "CLEAR")
		loaded_pill_bottle.set_wrapper_color(color)
	else
		loaded_pill_bottle.set_wrapper_color(null)
	return TRUE

/obj/machinery/chem_master/proc/modal_addcustom(datum/act/op/A, list/arguments)
	var/amount = isgoodnumber(A.step_value("amount"))
	var/id = islist(arguments) ? arguments["id"] : null
	if(!amount || !id)
		return
	return ui_act_add(A, amount, id)

/obj/machinery/chem_master/proc/modal_removecustom(datum/act/op/A, list/arguments)
	var/amount = isgoodnumber(A.step_value("amount"))
	var/id = islist(arguments) ? arguments["id"] : null
	if(!amount || !id)
		return
	return ui_act_remove(A, amount, id)

/obj/machinery/chem_master/proc/modal_create_condi_pack(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	if(!condi || !reagents.total_volume)
		return
	var/answer = A.step_value("name")
	if(!length(answer))
		answer = reagents.get_master_reagent_name()
	var/obj/item/reagent_containers/pill/P = new(loc)
	P.name = "[answer] pack"
	P.desc = "A small condiment pack. The label says it contains [answer]."
	P.icon_state = "bouilloncube"//Reskinned monkey cube
	reagents.trans_to_obj(P, 10)
	return TRUE

/obj/machinery/chem_master/proc/modal_create_pill(datum/act/op/A, list/arguments)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(condi || !reagents.total_volume)
		return
	var/count = CLAMP(make_count(A), 0, MAX_MULTI_AMOUNT)
	if(!count)
		return
	var/answer = A.step_value("name")
	if(!length(answer))
		answer = reagents.get_master_reagent_name()
	var/amount_per_pill = CLAMP(reagents.total_volume / count, 0, MAX_UNITS_PER_PILL)
	while(count--)
		if(reagents.total_volume <= 0)
			to_chat(user, span_notice("Not enough reagents to create these pills!"))
			return
		var/obj/item/reagent_containers/pill/P = new(loc)
		P.name = "[answer] pill"
		P.pixel_x = rand(-7, 7) // Random position
		P.pixel_y = rand(-7, 7)
		P.icon_state = "pill[pillsprite]"
		if(P.icon_state in list("pill1", "pill2", "pill3", "pill4")) // if using greyscale, take colour from reagent
			P.color = reagents.get_color()
		reagents.trans_to_obj(P, amount_per_pill)
		// Load the pills in the bottle if there's one loaded
		if(istype(loaded_pill_bottle) && length(loaded_pill_bottle.contents) < loaded_pill_bottle.max_storage_space)
			P.forceMove(loaded_pill_bottle)
	return TRUE

/obj/machinery/chem_master/proc/modal_change_pill_style(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	var/list/choices = pill_style_choices(A)
	var/new_style = CLAMP(choices.Find(A.step_value("style")), 0, MAX_PILL_SPRITE)
	if(!new_style)
		return
	pillsprite = new_style
	return TRUE

/obj/machinery/chem_master/proc/modal_create_patch(datum/act/op/A, list/arguments)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(condi || !reagents.total_volume)
		return
	var/count = CLAMP(make_count(A), 0, MAX_MULTI_AMOUNT)
	if(!count)
		return
	var/answer = A.step_value("name")
	if(!length(answer))
		answer = reagents.get_master_reagent_name()
	var/amount_per_patch = CLAMP(reagents.total_volume / count, 0, MAX_UNITS_PER_PATCH)
	while(count--)
		if(reagents.total_volume <= 0)
			to_chat(user, span_notice("Not enough reagents to create these patches!"))
			return
		var/obj/item/reagent_containers/pill/patch/P = new(loc)
		P.name = "[answer] patch"
		P.pixel_x = rand(-7, 7) // random position
		P.pixel_y = rand(-7, 7)
		reagents.trans_to_obj(P, amount_per_patch)
	return TRUE

/obj/machinery/chem_master/proc/modal_create_bottle(datum/act/op/A, list/arguments)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(condi || !reagents.total_volume)
		return
	var/count = CLAMP(make_count(A), 0, MAX_MULTI_AMOUNT)
	if(!count)
		return
	var/answer = A.step_value("name")
	if(!length(answer))
		answer = reagents.get_master_reagent_name()
	var/amount_per_bottle = CLAMP(reagents.total_volume / count, 0, MAX_UNITS_PER_BOTTLE)
	while(count--)
		if(reagents.total_volume <= 0)
			to_chat(user, span_notice("Not enough reagents to create these bottles!"))
			return
		var/obj/item/reagent_containers/glass/bottle/P = new(loc)
		P.name = "[answer] bottle"
		P.pixel_x = rand(-7, 7) // random position
		P.pixel_y = rand(-7, 7)
		P.icon_state = "bottle-[bottlesprite]" || "bottle-1"
		reagents.trans_to_obj(P, amount_per_bottle)
	return TRUE

/obj/machinery/chem_master/proc/modal_change_bottle_style(datum/act/op/A, list/arguments)
	add_fingerprint(A.actor)
	var/list/choices = bottle_style_choices(A)
	var/new_style = CLAMP(choices.Find(A.step_value("style")), 0, MAX_BOTTLE_SPRITE)
	if(!new_style)
		return
	bottlesprite = new_style
	return TRUE

// ---- the buttons ----

/obj/machinery/chem_master/proc/ui_act_toggle(datum/act/op/A)
	add_fingerprint(A.actor)
	. = TRUE
	set_mode(!mode)

/obj/machinery/chem_master/proc/ui_act_ejectp(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	if(loaded_pill_bottle)
		loaded_pill_bottle.forceMove(get_turf(src))
		if(Adjacent(user) && !(A.authority & AUTH_REMOTE_ACCESS))
			user.put_in_hands(loaded_pill_bottle)
		rel_take(src, nameof(loaded_pill_bottle))

/obj/machinery/chem_master/proc/ui_act_print(datum/act/op/A, from_beaker, idx)
	add_fingerprint(A.actor)
	. = TRUE
	if(printing || condi)
		return

	var/reagent_list = (from_beaker && beaker) ? beaker.reagents.reagent_list : reagents.reagent_list
	if(idx < 1 || idx > length(reagent_list))
		return

	var/datum/reagent/R = reagent_list[idx]

	printing = TRUE
	visible_message(span_notice("[src] rattles and prints out a sheet of paper."))

	var/obj/item/paper/P = new /obj/item/paper(loc)
	P.set_info("<center><b>Chemical Analysis</b></center><br>")
	P.set_info(P.info + (span_bold("Time of analysis:") + " [worldtime2stationtime(world.time)]<br><br>"))
	P.set_info(P.info + (span_bold("Chemical name:") + " [R.name]<br>"))
	if(istype(R, /datum/reagent/blood))
		var/datum/reagent/blood/B = R
		P.set_info(P.info + (span_bold("Description:") + " N/A<br><b>Blood Type:</b> [B.data["blood_type"]]<br><b>DNA:</b> [B.data["blood_DNA"]]"))
	else
		P.set_info(P.info + (span_bold("Description:") + " [R.description]"))
	P.set_info(P.info + ("<br><br><b>Notes:</b><br>"))
	P.name = "Chemical Analysis - [R.name]"
	after(src, 5 SECONDS, PROC_REF(printing_done))

/obj/machinery/chem_master/proc/ui_act_add(datum/act/op/A, amount, id)
	add_fingerprint(A.actor)
	. = TRUE
	if(!beaker)
		return
	var/datum/reagents/R = beaker.reagents
	if(!id || !amount || amount <= 0) // negative amounts pass a bare falsy check and reach trans_id_to
		return
	R.trans_id_to(src, id, amount)

/obj/machinery/chem_master/proc/ui_act_remove(datum/act/op/A, amount, id)
	add_fingerprint(A.actor)
	. = TRUE
	if(!beaker)
		return
	if(!id || !amount || amount <= 0) // see "add": reject crafted negative amounts
		return
	if(mode)
		reagents.trans_id_to(beaker, id, amount)
	else
		reagents.remove_reagent(id, amount)

/obj/machinery/chem_master/proc/ui_act_eject(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	. = TRUE
	if(!beaker)
		return
	beaker.forceMove(get_turf(src))
	if(Adjacent(user) && !(A.authority & AUTH_REMOTE_ACCESS))
		user.put_in_hands(beaker)
	rel_take(src, nameof(beaker))
	reagents.clear_reagents()

/obj/machinery/chem_master/proc/ui_act_create_condi_bottle(datum/act/op/A)
	add_fingerprint(A.actor)
	. = TRUE
	if(!beaker)
		return
	if(!condi || !reagents.total_volume)
		return
	var/obj/item/reagent_containers/food/condiment/P = new(loc)
	reagents.trans_to_obj(P, 50)

/obj/machinery/chem_master/proc/isgoodnumber(num)
	if(isnum(num))
		if(num > 200)
			num = 200
		else if(num < 0)
			num = 1
		return num
	else
		return FALSE

/obj/machinery/chem_master/condimaster
	name = "CondiMaster 3000"
	condi = 1

/obj/machinery/chem_master/proc/printing_done()
	printing = FALSE

