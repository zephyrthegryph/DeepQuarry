/obj/machinery/reagent_refinery/furnace
	name = "Industrial Chemical Furnace"
	desc = "Compresses and heats the whole mix it is fed. Whatever has a sheet form solidifies into sheets; the rest is burnt off."
	icon_state = "furnace_l"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	circuit = VARIANT(/obj/item/circuitboard/industrial_reagent_furnace)
	VAR_PROTECTED/filter_side = -1 // L

	default_max_vol = 60
	VAR_PRIVATE/obj/item/reagent_containers/beaker = null // Safer than retooling all of reagent code to support a second reagent var inside this one object


/obj/machinery/reagent_refinery/furnace/alt
	filter_side = 1 // R
	icon_state = "furnace_r"

CAPABILITIES(/obj/machinery/reagent_refinery/furnace)
	configure(uses_power(idle = 5, active = 500))
	after_init(0, then(PROC_REF(apply_default_parts)))
	without("reagent_refinery_set_transfer_amount")
	climb()
	owns_one(nameof(beaker), starts = /obj/item/reagent_containers/glass/beaker/bluespace)
	op("furnace_flip", menu(), label("Flip Furnace Direction"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_flip)))


/obj/machinery/reagent_refinery/furnace/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	sinter_mix()

/// Takes the whole mix in the tank. Every reagent with a sheet form goes into the mold and becomes sheets in proportion to its own amount
/// (REAGENTS_PER_SHEET each, the remainder waits in the mold for the next step); everything with no sheet form, contaminants included, is spent and gone.
/// Returns a list of material name -> sheets made.
/obj/machinery/reagent_refinery/furnace/proc/sinter_mix()
	var/list/made = list()
	if(!reagents || reagents.total_volume <= 0)
		return made
	var/check_dir = filter_side == 1 ? turn(src.dir, 270) : turn(src.dir, 90)
	var/turf/spawn_t = get_step(get_turf(src), check_dir)

	// Everything in the tank is processed: the sinterable part moves to the mold, the rest is spent.
	var/list/taken = list()
	var/list/spent = list()
	var/list/ids = list()
	for(var/datum/reagent/R in reagents.reagent_list)
		ids[R.id] = R.volume
	for(var/id in ids)
		var/amount = ids[id]
		if(GLOB.reagent_sheets[id])
			reagents.trans_id_to(beaker, id, amount)
			taken[id] = amount
		else
			reagents.remove_reagent(id, amount)
			spent[id] = amount

	var/played_sound = FALSE
	var/list/ready = list()
	for(var/datum/reagent/R in beaker.reagents.reagent_list)
		ready += R.id
	for(var/id in ready)
		var/mat_id = GLOB.reagent_sheets[id]
		while(beaker.reagents.get_reagent_amount(id) >= REAGENTS_PER_SHEET)
			beaker.reagents.remove_reagent(id, REAGENTS_PER_SHEET)
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
					made[mat_id] = (made[mat_id] || 0) + 1
				if(REFINERY_SINTERING_EXPLODE)
					// Detonate
					if(!played_sound)
						visible_message(span_danger("\The [src] catches fire and violently explodes!"))
						played_sound = TRUE
					explosion(loc, 0, 1, 2, 4)
					visible_message("\The [src.name] detonates!")
					made[mat_id] = (made[mat_id] || 0) + 1
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
					made[mat_id] = (made[mat_id] || 0) + 1
				else
					var/datum/material/printing = get_material_by_name(mat_id)
					if(printing)
						// Place a sheet
						if(!played_sound)
							play_sfx(src, SFX_ITEMS_ELECTRONIC_ASSEMBLY_EMPTYING)
							played_sound = TRUE
						var/obj/item/stack/material/S = printing.place_sheet(src, 1) // One at a time
						if(!istype(S))
							warning("[src] tried to eject material '[printing]', which didn't generate a proper stack when asked!")
							continue
						S.forceMove(spawn_t) // autostack
						made[mat_id] = (made[mat_id] || 0) + 1

	var/list/in_text = list()
	for(var/id in ids)
		in_text += "[id] [ids[id]]u"
	var/list/sheet_text = list()
	for(var/id in made)
		sheet_text += "[id] x[made[id]]"
	var/list/spent_text = list()
	for(var/id in spent)
		spent_text += "[id] [spent[id]]u"
	var/list/mold_text = list()
	for(var/datum/reagent/R in beaker.reagents.reagent_list)
		mold_text += "[R.id] [R.volume]u"
	log_world("CHEM: furnace [REF(src)] sintered [jointext(in_text, ", ")]; sheets [jointext(sheet_text, ", ") || "none"]; spent [jointext(spent_text, ", ") || "none"]; left in the mold [jointext(mold_text, ", ") || "none"]")
	return made

/// The furnace sintering to its side, with what it holds (its own, else its beaker's) shown in the colour of it. The beaker is watched: its level redraws the furnace.
/obj/machinery/reagent_refinery/furnace/draw(datum/look/look)
	..()
	look.watch(beaker)
	var/drawn_state = look.state("furnace_[filter_side == 1 ? "r" : "l"]")
	if(reagents && reagents.total_volume > 0)
		look.overlay(look_overlay_image(icon, "[drawn_state]_r", color = reagents.get_color(), dir = dir))
	else if(beaker && beaker.reagents && beaker.reagents.total_volume > 0)
		look.overlay(look_overlay_image(icon, "[drawn_state]_r", color = beaker.reagents.get_color(), dir = dir))

/obj/machinery/reagent_refinery/furnace/proc/interaction_flip(datum/act/op/A)
	var/mob/user = A.actor
	if (user.stat || user.restrained() || anchored)
		return OP_OK

	set_filter_side(-filter_side)
	return OP_OK

/obj/machinery/reagent_refinery/furnace/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate)
	// pumps, furnaces, splitters and filters can only be FED in a straight line
	if(source_forward_dir != dir)
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate)

/obj/machinery/reagent_refinery/furnace/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u."
	. += "The sintering mold is [ (beaker.reagents.total_volume / REAGENTS_PER_SHEET) * 100 ]% full."
	tutorial(REFINERY_TUTORIAL_INPUT, .)

