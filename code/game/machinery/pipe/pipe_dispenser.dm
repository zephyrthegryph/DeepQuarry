/obj/machinery/pipedispenser
	name = "Pipe Dispenser"
	desc = "A large machine that can rapidly dispense pipes."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	var/unwrenched = 0
	COOLDOWN_DECLARE(wait)
	var/p_layer = PIPING_LAYER_REGULAR
	var/static/list/pipe_layers = list(
		"Regular" = PIPING_LAYER_REGULAR,
		"Supply" = PIPING_LAYER_SUPPLY,
		"Scrubber" = PIPING_LAYER_SCRUBBER,
		"Fuel" = PIPING_LAYER_FUEL,
		"Aux" = PIPING_LAYER_AUX
	)
	var/disposals = FALSE

TRACKED(/obj/machinery/pipedispenser, unwrenched)

/obj/machinery/pipedispenser/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet/pipes),
	)

CAPABILITIES(/obj/machinery/pipedispenser)
	interface("PipeDispenser")
	op("p_layer", ui_act("p_layer", arg("p_layer", num())), then(PROC_REF(ui_act_p_layer)))
	op("dispense_pipe", ui_act("dispense_pipe", arg("bent"), arg("ref")), then(PROC_REF(ui_act_dispense_pipe)))
	extend(TAG_UI, needs(req(PROC_REF(dispenser_usable), because = MSG(pipedispenser/cannot_use))))
	op("put_back", item(/obj/item/pipe), label("Put back"), wait(0), says(MSG(pipedispenser/put_back)), then(PROC_REF(put_back)))
	op("put_back_meter", item(/obj/item/pipe_meter), label("Put back"), wait(0), says(MSG(pipedispenser/put_back)), then(PROC_REF(put_back)))
	op("anchor", tool(TOOL_WRENCH), label("Wrench"), wait(PROC_REF(anchor_wait)), says(PROC_REF(anchor_message)), then(PROC_REF(anchor_toggled)))

MSG_DEF(pipedispenser/put_back, "You put %I% back in %T%.", "%U% puts %I% back in %T%.")
MSG_DEF(pipedispenser/fastened, "You have fastened %T%. Now it can dispense pipes.", "%U% fastens %T%.")
MSG_DEF(pipedispenser/unfastened, "You have unfastened %T%. Now it can be pulled somewhere else.", "%U% unfastens %T%.")

MSG_DEF_SELF(pipedispenser/cannot_use, "You can't work the dispenser.")

/// The dispenser answers someone next to it who can move and act, and only while it is bolted down.
/obj/machinery/pipedispenser/proc/dispenser_usable(datum/act/op/A)
	var/mob/user = A.actor
	return !unwrenched && user.canmove && !user.stat && !user.restrained() && get_dist(loc, user) <= 1 // ALLOW(reads): the bolts and the person are read when a button is pressed, never from a cached menu

/obj/machinery/pipedispenser/ui_data(datum/act/eval/A)
	var/list/data = list(
		"disposals" = disposals,
		"p_layer" = p_layer,
		"pipe_layers" = pipe_layers,
	)

	var/list/recipes
	if(disposals)
		recipes = GLOB.disposal_pipe_recipes
	else
		recipes = GLOB.atmos_pipe_recipes

	for(var/c in recipes)
		var/list/cat = recipes[c]
		var/list/r = list()
		for(var/i in 1 to cat.len)
			var/datum/pipe_recipe/info = cat[i]
			r += list(list("pipe_name" = info.name, "ref" = "\ref[info]"))
			// Stationary pipe dispensers don't allow you to pre-select pipe directions.
			// This makes it impossble to spawn bent versions of bendable pipes.
			// We add a "Bent" pipe type with a special param to work around it.
			if(info.dirtype == PIPE_BENDABLE)
				r += list(list(
					"pipe_name" = ("Bent " + info.name),
					"ref" = "\ref[info]",
					"bent" = TRUE
				))
		data["categories"] += list(list("cat_name" = c, "recipes" = r))

	return data


/obj/machinery/pipedispenser/proc/ui_act_p_layer(datum/act/op/A, raw_p_layer)
	. = TRUE
	p_layer = raw_p_layer

/obj/machinery/pipedispenser/proc/ui_act_dispense_pipe(datum/act/op/A, bent, raw_ref)
	var/mob/user = A.actor
	. = TRUE
	if(COOLDOWN_FINISHED(src, wait))
		var/datum/pipe_recipe/recipe = ui_ref(raw_ref, null, /datum/pipe_recipe)
		if(!istype(recipe))
			return

		var/target_dir = NORTH
		if(bent)
			target_dir = NORTHEAST

		var/obj/created_object = null
		if(istype(recipe, /datum/pipe_recipe/pipe))
			var/datum/pipe_recipe/pipe/R = recipe
			created_object = new R.construction_type(loc, recipe.pipe_type, target_dir)
			var/obj/item/pipe/P = created_object
			P.setPipingLayer(p_layer)
		else if(istype(recipe, /datum/pipe_recipe/disposal))
			var/datum/pipe_recipe/disposal/D = recipe
			var/obj/structure/disposalconstruct/C = new(loc, D.pipe_type, target_dir, 0, D.subtype ? D.subtype : 0)
			C.update()
			created_object = C
		else if(istype(recipe, /datum/pipe_recipe/meter))
			created_object = new recipe.pipe_type(loc)
		else
			log_runtime(EXCEPTION("Warning: [user] attempted to spawn pipe recipe type by ref [ui_ref(raw_ref, null, /datum/pipe_recipe)] ([recipe] [recipe?.type]), but it was not allowed by this machine ([src] [type])"))
			return

		created_object.add_fingerprint(user)
		COOLDOWN_START(src, wait, 1.5 SECONDS)


/obj/machinery/pipedispenser/proc/put_back(datum/act/op/A)
	var/mob/user = A.actor
	user.drop_item()
	consume(A.held, user)
	return OP_OK

/// Bolting it down is quicker than unbolting it.
/obj/machinery/pipedispenser/proc/anchor_wait(datum/act/A)
	return unwrenched ? 2 SECONDS : 4 SECONDS

/obj/machinery/pipedispenser/proc/anchor_message(datum/act/A)
	return unwrenched ? /datum/msg/pipedispenser/unfastened : /datum/msg/pipedispenser/fastened

/obj/machinery/pipedispenser/proc/anchor_toggled(datum/act/op/A)
	set_unwrenched(!unwrenched)
	set_anchored(!unwrenched)
	if(unwrenched)
		set_maintenance(TRUE)
		SStgui.close_uis(src)
	else
		set_maintenance(FALSE)
		power_change()
	return OP_OK

/obj/machinery/pipedispenser/disposal
	name = "Disposal Pipe Dispenser"
	desc = "A large machine that can rapidly dispense pipes. This one seems to dispsense disposal pipes."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	anchored = TRUE
	disposals = TRUE

MSG_DEF(pipedispenser/shoved_back, "You shove %I% back in %T%.", "%U% shoves %I% back in %T%.")

/// Disposal pipes are dragged back into it.
CAPABILITIES(/obj/machinery/pipedispenser/disposal)
	op("shove_back", item(/obj/structure/disposalconstruct), gesture(GESTURE_DRAG), label("Put back"), wait(0),
		needs(req(PROC_REF(loose_and_near), because = MSG(op/not_available))), says(MSG(pipedispenser/shoved_back)), then(PROC_REF(shoved_back)))

/// The dragger can act, and the loose pipe and the dragger are both beside it.
/obj/machinery/pipedispenser/disposal/proc/loose_and_near(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/disposalconstruct/pipe = A.held
	return istype(pipe) && !pipe.anchored && user.canmove && !user.stat && !user.restrained() && get_dist(user, src) <= 1 && get_dist(src, pipe) <= 1 // ALLOW(reads): read when the pipe is dragged, never from a cached menu

/obj/machinery/pipedispenser/disposal/proc/shoved_back(datum/act/op/A)
	consume(A.held, A.actor)
	return OP_OK

// adding a pipe dispensers that spawn unhooked from the ground
/obj/machinery/pipedispenser/orderable
	anchored = FALSE
	unwrenched = 1

/obj/machinery/pipedispenser/disposal/orderable
	anchored = FALSE
	unwrenched = 1
