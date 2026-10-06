#define ATMOS_CATEGORY 0
#define DISPOSALS_CATEGORY 1
#define TRANSIT_CATEGORY 2

#define BUILD_MODE (1<<0)
#define WRENCH_MODE (1<<1)
#define DESTROY_MODE (1<<2)
#define PAINT_MODE (1<<3)

MATERIAL_MIX(/obj/item/pipe_dispenser, list(MAT_STEEL = 50000, MAT_GLASS = 25000))
/obj/item/pipe_dispenser
	name = "Rapid Piping Device (RPD)"
	desc = "A device used to rapidly pipe things."
	icon = 'icons/obj/tools_vr.dmi'
	icon_state = "rpd"
	item_state = "rpd"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
	)
	flags = NOBLUDGEON
	force = 10
	throwforce = 10
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	var/p_dir = NORTH 			// Next pipe will be built with this dir
	var/p_flipped = FALSE		// If the next pipe should be built flipped
	var/paint_color = "grey"	// Pipe color index for next pipe painted/built.
	var/category = ATMOS_CATEGORY
	var/piping_layer = PIPING_LAYER_DEFAULT
	var/obj/item/tool/wrench/tool
	var/datum/pipe_recipe/recipe_static	// pipe recipie selected for display/construction //, added = null
	var/static/datum/pipe_recipe/first_atmos
	var/static/datum/pipe_recipe/first_disposal
	var/mode = BUILD_MODE | DESTROY_MODE | WRENCH_MODE
	var/static/list/pipe_layers = list(
		"Regular" = PIPING_LAYER_REGULAR,
		"Supply" = PIPING_LAYER_SUPPLY,
		"Scrubber" = PIPING_LAYER_SCRUBBER,
		"Fuel" = PIPING_LAYER_FUEL,
		"Aux" = PIPING_LAYER_AUX
	)

/obj/item/pipe_dispenser/proc/SetupPipes()
	if(!first_atmos)
		first_atmos = GLOB.atmos_pipe_recipes[GLOB.atmos_pipe_recipes[1]][1]
	if(!first_disposal)
		first_disposal = GLOB.disposal_pipe_recipes[GLOB.disposal_pipe_recipes[1]][1]
	if(!recipe())
		recipe_static = first_atmos

// RPDs have wrenches inside of them, so that they can wrench down spawned pipes without being used as superior wrenches themselves.
CAPABILITIES(/obj/item/pipe_dispenser)
	owns_one(nameof(tool), /obj/item/tool/wrench/cyborg, starts = /obj/item/tool/wrench/cyborg)
	op("controls", in_hand(), label("Open pipe controls"), then(PROC_REF(rpd_controls_opened)))
	interface("RapidPipeDispenser", state = nameof(GLOB.tgui_inventory_state))
	without("ui_open")
	op("color", ui_act("color", arg("paint_color", schema_text(4096))), then(PROC_REF(ui_act_color)))
	op("category", ui_act("category", arg("category", num())), then(PROC_REF(ui_act_category)))
	op("piping_layer", ui_act("piping_layer", arg("piping_layer", num())), then(PROC_REF(ui_act_piping_layer)))
	op("pipe_type", ui_act("pipe_type", arg("category", schema_text(4096)), arg("pipe_type", num())), then(PROC_REF(ui_act_pipe_type)))
	op("setdir", ui_act("setdir", arg("dir", schema_text(4096)), arg("flipped", num())), then(PROC_REF(ui_act_setdir)))
	op("mode", ui_act("mode", arg("mode", num())), then(PROC_REF(ui_act_mode)))

/obj/item/pipe_dispenser/proc/rpd_controls_opened(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_OK

/obj/item/pipe_dispenser/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet/pipes),
	)

/obj/item/pipe_dispenser/ui_prepare(mob/user, datum/tgui/ui)
	SetupPipes()
	return TRUE

/// /obj/item/pipe_dispenser's window data.
/obj/item/pipe_dispenser/ui_data(datum/act/eval/A)
	var/list/data = list(
		"category" = category,
		"piping_layer" = piping_layer,
		"pipe_layers" = pipe_layers,
		"preview_rows" = recipe().get_preview(p_dir),
		"categories" = list(),
		"selected_color" = paint_color,
		"paint_colors" = GLOB.pipe_colors,
		"mode" = mode
	)

	var/list/recipes
	switch(category)
		if(ATMOS_CATEGORY)
			recipes = GLOB.atmos_pipe_recipes
		if(DISPOSALS_CATEGORY)
			recipes = GLOB.disposal_pipe_recipes
	for(var/c in recipes)
		var/list/cat = recipes[c]
		var/list/r = list()
		for(var/i in 1 to cat.len)
			var/datum/pipe_recipe/info = cat[i]
			r += list(list("pipe_name" = info.name, "pipe_index" = i, "selected" = (info == recipe())))
		data["categories"] += list(list("cat_name" = c, "recipes" = r))

	return data

/obj/item/pipe_dispenser/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained() || !in_range(loc, user))
		return FALSE
	return TRUE

/obj/item/pipe_dispenser/proc/ui_act_color(datum/act/op/A, paint_color_arg)
	if(!ui_gate(A))
		return FALSE
	var/playeffect = TRUE
	paint_color = paint_color_arg
	if(playeffect)
		fx_sparks(src, 5, FALSE)
		play_sfx(get_turf(src), SFX_EFFECTS_POP)
	return TRUE

/obj/item/pipe_dispenser/proc/ui_act_category(datum/act/op/A, category_arg)
	if(!ui_gate(A))
		return FALSE
	var/playeffect = TRUE
	category = category_arg
	switch(category)
		if(DISPOSALS_CATEGORY)
			recipe_static = first_disposal
		if(ATMOS_CATEGORY)
			recipe_static = first_atmos
	p_dir = NORTH
	playeffect = FALSE
	if(playeffect)
		fx_sparks(src, 5, FALSE)
		play_sfx(get_turf(src), SFX_EFFECTS_POP)
	return TRUE

/obj/item/pipe_dispenser/proc/ui_act_piping_layer(datum/act/op/A, piping_layer_arg)
	if(!ui_gate(A))
		return FALSE
	var/playeffect = TRUE
	piping_layer = piping_layer_arg
	playeffect = FALSE
	if(playeffect)
		fx_sparks(src, 5, FALSE)
		play_sfx(get_turf(src), SFX_EFFECTS_POP)
	return TRUE

/obj/item/pipe_dispenser/proc/ui_act_pipe_type(datum/act/op/A, category, pipe_type)
	if(!ui_gate(A))
		return FALSE
	var/playeffect = TRUE
	var/static/list/recipes
	if(!recipes)
		recipes = GLOB.disposal_pipe_recipes + GLOB.atmos_pipe_recipes
	recipe_static = recipes[category][pipe_type]
	p_dir = NORTH
	if(playeffect)
		fx_sparks(src, 5, FALSE)
		play_sfx(get_turf(src), SFX_EFFECTS_POP)
	return TRUE

/obj/item/pipe_dispenser/proc/ui_act_setdir(datum/act/op/A, dir, flipped)
	if(!ui_gate(A))
		return FALSE
	var/playeffect = TRUE
	p_dir = text2dir(dir)
	p_flipped = flipped
	playeffect = FALSE
	if(playeffect)
		fx_sparks(src, 5, FALSE)
		play_sfx(get_turf(src), SFX_EFFECTS_POP)
	return TRUE

/obj/item/pipe_dispenser/proc/ui_act_mode(datum/act/op/A, mode_arg)
	if(!ui_gate(A))
		return FALSE
	var/playeffect = TRUE
	var/n = mode_arg
	if(mode & n)
		mode &= ~n
	else
		mode |= n
	if(playeffect)
		fx_sparks(src, 5, FALSE)
		play_sfx(get_turf(src), SFX_EFFECTS_POP)
	return TRUE

/obj/item/pipe_dispenser/afterattack(atom/A, mob/user as mob, proximity)
	if(!user.IsAdvancedToolUser() || istype(A, /turf/space/transit) || !proximity)
		return ..()

	//So that changing the menu settings doesn't affect the pipes already being built.
	var/queued_piping_layer = piping_layer
	var/queued_p_dir = p_dir
	var/queued_p_flipped = p_flipped

	//make sure what we're clicking is valid for the current mode
	var/static/list/make_pipe_whitelist // This should probably be changed to be in line with polaris standards. Oh well.
	if(!make_pipe_whitelist)
		make_pipe_whitelist = typecacheof(list(/obj/structure/lattice, /obj/structure/girder, /obj/item/pipe))
	var/can_make_pipe = (isturf(A) || is_type_in_typecache(A, make_pipe_whitelist))

	var/can_destroy_pipe = istype(A, /obj/item/pipe) || istype(A, /obj/item/pipe_meter) || istype(A, /obj/structure/disposalconstruct) || istype(A, /obj/item/pipe_gsensor)

	. = TRUE
	if((mode & DESTROY_MODE) && can_destroy_pipe)
		to_chat(user, span_notice("You start destroying a pipe..."))
		play_sfx(src, SFX_MACHINES_CLICK)
		task_timed(user, 2, target = A, receiver = src, on_done = PROC_REF(afterattack_timed_done), done_args = list(A))
		return

	if((mode & PAINT_MODE)) //Paint pipes
		if(!istype(A, /obj/machinery/atmospherics/pipe/simple/heat_exchanging) && istype(A, /obj/machinery/atmospherics/pipe))
			var/obj/machinery/atmospherics/pipe/P = A
			play_sfx(src, SFX_MACHINES_CLICK)
			P.change_color(GLOB.pipe_colors[paint_color])
			act_message(user, null, MSG_SELF(span_notice("You paint \the [P] [paint_color].")), MSG_OTHERS(span_notice("%U% paints \the [P] [paint_color].")))
			return

	if(mode & BUILD_MODE) //Making pipes
		switch(category)
			if(ATMOS_CATEGORY)
				if(!can_make_pipe)
					return ..()
				play_sfx(src, SFX_MACHINES_CLICK)
				if(istype(recipe(), /datum/pipe_recipe/meter))
					to_chat(user, span_notice("You start building a meter..."))
					task_start(/datum/task/timed/pipe_dispenser_afterattack, user, A, queued_piping_layer = queued_piping_layer)
				else if(istype(recipe(), /datum/pipe_recipe/air_sensor))
					to_chat(user, span_notice("You start building an air sensor..."))
					task_timed(user, 2, target = A, receiver = src, on_done = PROC_REF(afterattack_timed_done3), done_args = list(A, user))
				else if(istype(recipe(), /datum/pipe_recipe/pipe))
					var/datum/pipe_recipe/pipe/R = recipe()
					to_chat(user, span_notice("You start building a pipe..."))
					task_start(/datum/task/timed/pipe_dispenser_afterattack2, user, A, queued_piping_layer = queued_piping_layer, queued_p_dir = queued_p_dir, queued_p_flipped = queued_p_flipped, R = R)

			if(DISPOSALS_CATEGORY) //Making disposals pipes
				var/datum/pipe_recipe/disposal/R = recipe()
				if(!istype(R) || !can_make_pipe)
					return ..()
				A = get_turf(A)
				if(istype(A, /turf/unsimulated))
					to_chat(user, span_warning("[src]'s error light flickers; there's something in the way!"))
					return
				to_chat(user, span_notice("You start building a disposals pipe..."))
				play_sfx(src, SFX_MACHINES_CLICK)
				task_start(/datum/task/timed/pipe_dispenser_afterattack3, user, A, queued_p_dir = queued_p_dir, queued_p_flipped = queued_p_flipped, R = R)

			else
				return ..()

/obj/item/pipe_dispenser/proc/afterattack_timed_done(atom/A)
	activate()
	animate_deletion(A)
/datum/task/timed/pipe_dispenser_afterattack
	duration = 2
	complete_proc = /obj/item/pipe_dispenser/proc/afterattack_timed_done2
	var/queued_piping_layer

/obj/item/pipe_dispenser/proc/afterattack_timed_done2(datum/task/timed/pipe_dispenser_afterattack/task)
	var/atom/A = task.target
	var/mob/user = task.actor
	var/queued_piping_layer = task.queued_piping_layer
	activate()
	var/obj/item/pipe_meter/PM = new /obj/item/pipe_meter(get_turf(A))
	PM.setAttachLayer(queued_piping_layer)
	if(mode & WRENCH_MODE)
		do_wrench(PM, user)
/obj/item/pipe_dispenser/proc/afterattack_timed_done3(atom/A, mob/user)
	activate()
	var/obj/item/pipe_gsensor/GS = new /obj/item/pipe_gsensor(get_turf(A))
	if(mode & WRENCH_MODE)
		do_wrench(GS, user)
/datum/task/timed/pipe_dispenser_afterattack2
	duration = 2
	complete_proc = /obj/item/pipe_dispenser/proc/afterattack_timed_done4
	var/queued_piping_layer
	var/queued_p_dir
	var/queued_p_flipped
	var/datum/pipe_recipe/pipe/R

/obj/item/pipe_dispenser/proc/afterattack_timed_done4(datum/task/timed/pipe_dispenser_afterattack2/task)
	var/atom/A = task.target
	var/mob/user = task.actor
	var/queued_piping_layer = task.queued_piping_layer
	var/queued_p_dir = task.queued_p_dir
	var/queued_p_flipped = task.queued_p_flipped
	var/datum/pipe_recipe/pipe/R = task.R
	activate()
	var/obj/machinery/atmospherics/path = R.pipe_type
	var/pipe_item_type = initial(path.construction_type) || /obj/item/pipe
	var/obj/item/pipe/P = new pipe_item_type(get_turf(A), path, queued_p_dir)

	P.update()
	P.add_fingerprint(user)
	if(R.paintable)
		P.color = GLOB.pipe_colors[paint_color]
	P.setPipingLayer(queued_piping_layer)
	if(queued_p_flipped)
		P.do_a_flip()
	if(mode & WRENCH_MODE)
		do_wrench(P, user)
	else
		build_effect(P)
/datum/task/timed/pipe_dispenser_afterattack3
	duration = 4
	complete_proc = /obj/item/pipe_dispenser/proc/afterattack_timed_done5
	var/queued_p_dir
	var/queued_p_flipped
	var/datum/pipe_recipe/disposal/R

/obj/item/pipe_dispenser/proc/afterattack_timed_done5(datum/task/timed/pipe_dispenser_afterattack3/task)
	var/atom/A = task.target
	var/mob/user = task.actor
	var/queued_p_dir = task.queued_p_dir
	var/queued_p_flipped = task.queued_p_flipped
	var/datum/pipe_recipe/disposal/R = task.R
	var/obj/structure/disposalconstruct/C = new(A, R.pipe_type, queued_p_dir, queued_p_flipped, R.subtype)

	if(!C.can_place())
		to_chat(user, span_warning("There's not enough room to build that here!"))
		consume(C)
		return

	activate()

	C.add_fingerprint(user)
	if(mode & WRENCH_MODE)
		do_wrench(C, user)
	else
		build_effect(C)

/obj/item/pipe_dispenser/proc/build_effect(obj/P, time = 1.5)
	P.filters += filter(type = "angular_blur", size = 30)
	animate(P.filters[P.filters.len], size = 0, time = time)
	var/outline = filter(type = "outline", size = 1, color = "#22AAFF")
	P.filters += outline
	after(P, time, GLOBAL_PROC_REF(rpd_build_effect_end), with = list(P, outline))

/proc/rpd_build_effect_end(obj/P, outline)
	P.filters -= outline
	P.filters -= filter(type = "angular_blur", size = 0)

/obj/item/pipe_dispenser/proc/animate_deletion(obj/P, time = 1.5)
	P.filters += filter(type = "angular_blur", size = 0)
	animate(P.filters[P.filters.len], size = 30, time = time)
	after(P, time, GLOBAL_PROC_REF(rpd_deletion_end), with = list(P))

/proc/rpd_deletion_end(obj/P)
	P.filters -= filter(type = "angular_blur", size = 30)
	spent(P)

/obj/item/pipe_dispenser/proc/activate()
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)

/obj/item/pipe_dispenser/proc/do_wrench(atom/target, mob/user)
	var/resolved = target.attackby(tool,user)
	if(!resolved && tool && target)
		tool.afterattack(target,user,1)

#undef ATMOS_CATEGORY
#undef DISPOSALS_CATEGORY
#undef TRANSIT_CATEGORY

#undef BUILD_MODE
#undef WRENCH_MODE
#undef DESTROY_MODE
#undef PAINT_MODE

/// A shared definition (registered: never owned or cleared).
/obj/item/pipe_dispenser/proc/recipe() as /datum/pipe_recipe
	return recipe_static
