/obj/machinery/reagent_refinery/furnace
	name = "Industrial Chemical Furnace"
	desc = "Extracts specific chemicals, compressing and heating them until they solidify."
	icon_state = "furnace_l"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 500
	circuit = /obj/item/circuitboard/industrial_reagent_furnace
	VAR_PROTECTED/filter_side = -1 // L
	VAR_PRIVATE/filter_reagent_id = ""

	default_max_vol = 60
	VAR_PRIVATE/obj/item/reagent_containers/beaker = null // Safer than retooling all of reagent code to support a second reagent var inside this one object

TRACKED(/obj/machinery/reagent_refinery/furnace, filter_side)

/obj/machinery/reagent_refinery/furnace/alt
	filter_side = 1 // R
	icon_state = "furnace_r"

CAPABILITIES(/obj/machinery/reagent_refinery/furnace)
	without("reagent_refinery_set_transfer_amount")
	climb()
	owns_one(nameof(beaker), starts = /obj/item/reagent_containers/glass/beaker/bluespace)
	op("furnace_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(set_filter_question)), "title" = "Chemical Select", "choices" = computed(PROC_REF(set_filter_choices)), "timeout" = 0), step = "chemical"), then(PROC_REF(interaction_use)))
	op("furnace_set_filter", menu(), label("Set Sintering Chemical"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(set_filter_question)), "title" = "Chemical Select", "choices" = computed(PROC_REF(set_filter_choices)), "timeout" = 0), step = "chemical"), then(PROC_REF(interaction_set_filter)))
	op("furnace_flip", menu(), label("Flip Furnace Direction"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_flip)))

/obj/machinery/reagent_refinery/furnace/Initialize(mapload)
	. = ..()
	default_apply_parts()


/obj/machinery/reagent_refinery/furnace/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	// extract and filter side products
	if(filter_reagent_id == "")
		return // MUST BE SET
	if(amount_per_transfer_from_this <= 0)
		return
	if(filter_reagent_id != "-1") // disabled check, and "all" check
		var/check_dir = 0
		if(filter_side == 1)
			check_dir = turn(src.dir, 270)
		else
			check_dir = turn(src.dir, 90)
		var/turf/spawn_t = get_step(get_turf(src),check_dir)

		// Suck out the reagent we're looking for into temporary holding
		if(reagents.total_volume > 0)
			for(var/datum/reagent/R in reagents.reagent_list)
				if(R && R.id == filter_reagent_id)
					reagents.trans_id_to(beaker, R.id, R.volume)

		// while loop is sane here because the beaker should always be cleaned when changing filter type,
		// and it should never end up mixed with more than 1 type of reagent
		// For sanity, and if admemes break something, I will do a clearing anyway....
		if(beaker.reagents.reagent_list.len > 1)
			beaker.reagents.clear_reagents() // Highlander rules
		var/played_sound = FALSE
		while(beaker.reagents.total_volume >= REAGENTS_PER_SHEET) // at least enough reagents to bother checking
			var/datum/reagent/R = beaker.reagents.reagent_list[1]
			var/mat_id = GLOB.reagent_sheets[R.id]
			beaker.reagents.remove_reagent(R.id,REAGENTS_PER_SHEET)
			switch(mat_id)
				if(REFINERY_SINTERING_SMOKE)
					// Smoke em out sometimes
					if(prob(30))
						if(!played_sound)
							play_sfx(src, SFX_ITEMS_ELECTRONIC_ASSEMBLY_EMPTYING)
							play_sfx(src, SFX_EFFECTS_SMOKE, 0.4, extrarange = 0)
							played_sound = TRUE
						visible_message(span_notice("\The [src] vomits a gout of smoke!"))
						var/datum/effect/effect/system/smoke_spread/bad/smoke = new /datum/effect/effect/system/smoke_spread/bad
						smoke.attach(src)
						smoke.set_up(10, 0, get_turf(src), 300)
						smoke.start()
				if(REFINERY_SINTERING_EXPLODE)
					// Detonate
					if(!played_sound)
						visible_message(span_danger("\The [src] catches fire and violently explodes!"))
						played_sound = TRUE
					explosion(loc, 0, 1, 2, 4)
					visible_message("\The [src.name] detonates!")
				if(REFINERY_SINTERING_SPIDERS)
					// Spawns some spiders
					if(!played_sound)
						play_sfx(src, SFX_ITEMS_FULEXT_DEPLOY, 0.8, extrarange = 0)
						played_sound = TRUE
					var/i = rand(1,3)
					while(i-- > 0)
						new /obj/effect/spider/spiderling/non_growing(spawn_t)
					if(prob(20))
						i = rand(1,2)
						while(i-- > 0)
							new /obj/effect/spider/spiderling/varied(spawn_t)
				else
					var/datum/material/printing = get_material_by_name(mat_id)
					if(printing)
						// Place a sheet
						if(!played_sound)
							play_sfx(src, SFX_ITEMS_ELECTRONIC_ASSEMBLY_EMPTYING)
							played_sound = TRUE
						var/obj/item/stack/material/S = printing.place_sheet(src, 1) // One at a time
						S.forceMove(spawn_t) // autostack
						if(!istype(S))
							warning("[src] tried to eject material '[printing]', which didn't generate a proper stack when asked!")
	// dump reagents to next refinery machine if all of the target reagent has been filtered out
	var/obj/machinery/reagent_refinery/target = locate_within(get_step(get_turf(src),dir), /obj/machinery/reagent_refinery)
	if(target && reagents.total_volume > 0)
		transfer_tank( reagents, target, dir)

/// The furnace sintering to its side, with what it holds (its own, else its beaker's) shown in the colour of it. The beaker is watched: its level redraws the furnace.
/obj/machinery/reagent_refinery/furnace/draw(datum/look/look)
	..()
	look.watch(beaker)
	var/drawn_state = look.state("furnace_[filter_side == 1 ? "r" : "l"]")
	if(reagents && reagents.total_volume > 0)
		look.overlay(look_overlay_image(icon, "[drawn_state]_r", color = reagents.get_color(), dir = dir))
	else if(beaker && beaker.reagents && beaker.reagents.total_volume > 0)
		look.overlay(look_overlay_image(icon, "[drawn_state]_r", color = beaker.reagents.get_color(), dir = dir))

/// The touch sets the sintering chemical.
/obj/machinery/reagent_refinery/furnace/proc/interaction_use(datum/act/op/A)
	return interaction_set_filter(A)

/// What the question says the furnace is doing now.
/obj/machinery/reagent_refinery/furnace/proc/filter_description()
	var/filter = "disabled"
	if(filter_reagent_id == "-1")
		filter = "sintering out nothing"
	else if(filter_reagent_id != "")
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[filter_reagent_id]
		filter = "sintering [R.name]"
	return filter

/obj/machinery/reagent_refinery/furnace/proc/set_filter_question(datum/act/op/A)
	return "Select chemical to sinter. It is currently [filter_description()]."

/// The names of what can be selected, in the order of the sintering table.
/obj/machinery/reagent_refinery/furnace/proc/set_filter_choices(datum/act/op/A)
	var/list/names = list()
	for(var/choice in filter_choice_table())
		names += choice
	return names

/// Name -> reagent id of what can be selected: the reagents currently inside that sinter into something.
/obj/machinery/reagent_refinery/furnace/proc/filter_choice_table()
	// Get a list of reagents currently inside!
	var/list/tgui_list = list("Disabled" = "","Bypass" = "-1")
	for(var/datum/reagent/R in reagents.reagent_list)
		if(R)
			var/mat_id = GLOB.reagent_sheets[R.id]
			if(!mat_id) // No reaction
				continue
			var/id_string = "[R.name] - ???"
			switch(mat_id)
				if(REFINERY_SINTERING_SMOKE)
					id_string = "[R.name] - DANGER"
				if(REFINERY_SINTERING_EXPLODE)
					id_string = "[R.name] - DANGER"
				if(REFINERY_SINTERING_SPIDERS)
					id_string = "[R.name] - DANGER"
				else
					var/datum/material/C = get_material_by_name(mat_id)
					if(C)
						id_string = "[R.name] - [C.display_name] [C.sheet_plural_name]"
			tgui_list[id_string] = R.id
	return tgui_list

/obj/machinery/reagent_refinery/furnace/proc/interaction_set_filter(datum/act/op/A)
	var/mob/user = A.actor
	if (user.stat || user.restrained())
		return OP_OK

	var/select = A.step_value("chemical")
	var/list/tgui_list = filter_choice_table()

	// Select if possible
	if(select && select != "")
		filter_reagent_id = tgui_list[select]
		beaker.reagents.clear_reagents()
	return OP_OK

/obj/machinery/reagent_refinery/furnace/proc/interaction_flip(datum/act/op/A)
	var/mob/user = A.actor
	if (user.stat || user.restrained() || anchored)
		return OP_OK

	set_filter_side(-filter_side)
	return OP_OK

/obj/machinery/reagent_refinery/furnace/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// pumps, furnaces, splitters and filters can only be FED in a straight line
	if(source_forward_dir != dir)
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/obj/machinery/reagent_refinery/furnace/examine(mob/user, infix, suffix)
	. = ..()
	var/filter = "disabled"
	if(filter_reagent_id == "-1")
		filter = "sintering out nothing"
	else if(filter_reagent_id != "")
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[filter_reagent_id]
		filter = "sintering [R.name]"
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is currently [filter]."
	. += "The sintering mold is [ (beaker.reagents.total_volume / REAGENTS_PER_SHEET) * 100 ]% full."
	tutorial(REFINERY_TUTORIAL_INPUT, .)

