
///////////
// EASEL //
///////////

/obj/structure/easel
	name = "easel"
	desc = "Only for the finest of art!"
	icon = 'icons/obj/artstuff.dmi'
	icon_state = "easel"
	density = TRUE
	var/obj/item/canvas/painting = null

CAPABILITIES(/obj/structure/easel)
	climb()
	op("item", item(/obj/item/canvas), label("Use"), then(PROC_REF(interaction_item)))

/obj/structure/easel/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/canvas/canvas = A.held
	user.drop_from_inventory(canvas)
	rel_set(src, nameof(painting), canvas) // the canvas sits on our turf: a view, not owned
	canvas.forceMove(get_turf(src))
	canvas.layer = layer+0.1
	act_message(user, src, MSG_SELF(span_notice("You place %I% on %T%.")), MSG_OTHERS(span_notice("%U% puts %I% on %T%.")), item = canvas)
	return TRUE

//Stick to the easel like glue
/obj/structure/easel/Move()
	var/turf/T = get_turf(src)
	. = ..()
	if(painting && painting.loc == T) //Only move if it's near us.
		painting.forceMove(get_turf(src))
	else
		rel_clear(src, nameof(painting))

/obj/item/canvas
	name = "canvas"
	desc = "Draw out your soul on this canvas!"
	icon = 'icons/obj/artstuff.dmi'
	icon_state = "11x11"
	var/width = 11
	var/height = 11
	var/list/grid
	var/canvas_color = "#ffffff" //empty canvas color
	var/used = FALSE
	var/painting_name = "Untitled Artwork" //Painting name, this is set after framing.
	var/finalized = FALSE //Blocks edits
	var/author_name
	var/author_ckey
	var/icon_generated = FALSE
	var/icon/generated_icon
	///boolean that blocks persistence from saving it. enabled from printing copies, because we do not want to save copies.
	var/no_save = FALSE

	/// From the origin of the turf we're on, where should the left of the canvas pixel be
	var/framed_offset_x = 11
	/// From the origin of the turf we're on, where should the bottom of the canvas be
	var/framed_offset_y = 10
	/// The frame takes the painting's offset, then moves this X offset
	var/frame_offset_x = -1
	/// The frame takes the painting's offset, then moves this Y offset
	var/frame_offset_y = -1

	pixel_x = 10
	pixel_y = 9

/obj/item/canvas/Initialize(mapload)
	. = ..()
	reset_grid()
	desc += " (Canvas size is [width]x[height].)"

/obj/item/canvas/proc/reset_grid()
	grid = new/list(width,height)
	for(var/x in 1 to width)
		for(var/y in 1 to height)
			grid[x][y] = canvas_color

/// Old attack_self: look at the canvas.
/obj/item/canvas/proc/interaction_self(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_OK

/obj/item/canvas/dropped(mob/user, equipping, slot)
	pixel_x = initial(pixel_x)
	pixel_y = initial(pixel_y)
	return ..()

/obj/item/canvas/tgui_state(mob/user)
	if(finalized)
		return GLOB.tgui_physical_obscured_state
	else
		return GLOB.tgui_default_state

CAPABILITIES(/obj/item/canvas)
	interface("Canvas")
	op("paint", ui_act("paint", arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_paint)))
	op("finalize", ui_act("finalize"), then(PROC_REF(ui_act_finalize)))
	extend(TAG_UI, needs(req(PROC_REF(canvas_open), because = MSG(canvas/finished))))
	op("view", in_hand(), then(PROC_REF(interaction_self)))
	op("base_color", item(/obj/item/paint_palette), label("Fill"),
		asks(/datum/prompt/yes_no, fields = list("title" = "Confirm Color Fill", "question" = "Adjusting the base color of this canvas will replace ALL pixels with the selected color. Are you sure?", "timeout" = 0), step = "sure"),
		asks(/datum/prompt/color, fields = list("title" = "Base Color", "question" = "Select a base color for the canvas:", "default" = "canvas_color", "timeout" = 0), step = "colour", when = PROC_REF(fill_confirmed)),
		then(PROC_REF(base_color_chosen)))
	op("paint_open", item(/obj/item), stance(I_HELP), label("Paint"), then(PROC_REF(interaction_paint)))

MSG_DEF_SELF(canvas/finished, "The painting is finished.")

/// A finished painting takes no more strokes.
/obj/item/canvas/proc/canvas_open(datum/act/op/A)
	return !finalized // ALLOW(reads): a finished painting is read when a stroke is made, never from a cached menu

/// Old attackby outside combat mode: open the canvas to paint on it (the click goes on).
/obj/item/canvas/proc/interaction_paint(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_PASS

/obj/item/canvas/ui_data(datum/act/eval/A)
	return list("grid" = grid, "name" = painting_name, "finalized" = finalized)

/obj/item/canvas/examine(mob/user)
	. = ..()
	tgui_interact(user)

/obj/item/canvas/proc/ui_act_paint(datum/act/op/A, x, y)
	var/mob/user = A.actor
	var/obj/item/I = user.get_active_hand()
	var/color = get_paint_tool_color(I)
	if(!color)
		return FALSE
	if(grid?[x]?[y])
		grid[x][y] = color
	used = TRUE
	update_appearance()
	. = TRUE

/obj/item/canvas/proc/ui_act_finalize(datum/act/op/A)
	. = TRUE
	if(!finalized)
		finalize(A.actor)

/obj/item/canvas/proc/finalize(mob/user)
	finalized = TRUE
	author_name = user.real_name
	author_ckey = user.ckey
	generate_proper_overlay()
	try_rename(user)

/obj/item/canvas/proc/update_appearance()
	cut_overlays()
	if(icon_generated)
		var/mutable_appearance/detail = mutable_appearance(generated_icon)
		detail.pixel_x = 1
		detail.pixel_y = 1
		add_overlay(detail)
		return
	if(!used)
		return

	var/mutable_appearance/detail = mutable_appearance(icon, "[icon_state]wip")
	detail.pixel_x = 1
	detail.pixel_y = 1
	add_overlay(detail)

/obj/item/canvas/proc/generate_proper_overlay()
	if(icon_generated)
		return
	var/png_filename = "data/persistent/paintings/temp_painting.png"
	var/result = rustg_dmi_create_png(png_filename,"[width]","[height]",get_data_string())
	if(result)
		CRASH("Error generating painting png : [result]")
	generated_icon = new(png_filename)
	icon_generated = TRUE
	update_appearance()

/obj/item/canvas/proc/get_data_string()
	var/list/data = list()
	for(var/y in 1 to height)
		for(var/x in 1 to width)
			data += grid[x][y]
	return data.Join("")

//Todo make this element ?
/obj/item/canvas/proc/get_paint_tool_color(obj/item/I)
	if(!I)
		return
	if(istype(I, /obj/item/paint_brush))
		var/obj/item/paint_brush/P = I
		return P.selected_color
	else if(istype(I, /obj/item/pen/crayon))
		var/obj/item/pen/crayon/crayon = I
		return crayon.colour
	else if(istype(I, /obj/item/pen))
		var/obj/item/pen/P = I
		switch(P.colour)
			if("black")
				return "#000000"
			if("blue")
				return "#0000ff"
			if("red")
				return "#ff0000"
		return P.colour
	else if(istype(I, /obj/item/soap) || istype(I, /obj/item/reagent_containers/glass/rag))
		return canvas_color

/// The palette's fill: asked only after a yes.
/obj/item/canvas/proc/fill_confirmed(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["sure"]
	return !!R?.value

/// Old attackby with a paint palette: after a yes, the whole canvas takes the chosen base colour (the click goes on).
/obj/item/canvas/proc/base_color_chosen(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["colour"]
	if(!R)
		return OP_PASS
	var/mob/living/user = A.actor
	var/basecolor = R.value
	if(basecolor)
		canvas_color = basecolor
		reset_grid()
		act_message(user, src, MSG_SELF("You smear paint on %T%, changing the color of the entire thing."), MSG_OTHERS("%U% smears paint on %T%, covering the entire thing in paint."), runemessage = "smears paint")
		update_appearance()
	return OP_PASS

/obj/item/canvas/proc/try_rename(mob/user)
	open_request(src, /datum/prompt/text, PROC_REF(renamed), answerer = user, question = "What do you want to name the painting?", max_len = 250, usable_state = "physical", timeout = 0)

/obj/item/canvas/proc/renamed(datum/act/request/A)
	if(!A.answer)
		return
	var/new_name = A.answer.value
	if(new_name != painting_name && new_name)
		painting_name = new_name
		SStgui.update_uis(src)

/obj/item/canvas/nineteen_nineteen
	icon_state = "19x19"
	width = 19
	height = 19
	pixel_x = 5
	pixel_y = 10
	framed_offset_x = 8
	framed_offset_y = 9

/obj/item/canvas/twentythree_nineteen
	icon_state = "23x19"
	width = 23
	height = 19
	pixel_x = 4
	pixel_y = 10
	framed_offset_x = 6
	framed_offset_y = 8

/obj/item/canvas/twentythree_twentythree
	icon_state = "23x23"
	width = 23
	height = 23
	pixel_x = 5
	pixel_y = 9
	framed_offset_x = 5
	framed_offset_y = 6

/obj/item/canvas/twentyfour_twentyfour
	//name = "ai universal standard canvas"					// Uncomment this when AI can actually
	//desc = "Besides being very large, the AI can accept these as a display from their internal database after you've hung it up." // Not yet
	icon_state = "24x24"
	width = 24
	height = 24
	pixel_x = 2
	pixel_y = 2
	framed_offset_x = 4
	framed_offset_y = 4
	frame_offset_x = -2
	frame_offset_y = -2

/obj/item/paint_brush
	name = "artist's paintbrush"
	desc = "When you really want to put together a masterpiece!"
	icon = 'icons/obj/artstuff.dmi'
	icon_state = "brush"
	var/selected_color = "#000000"
	var/image/color_drop
	var/hud_level = FALSE

/obj/item/paint_brush/Initialize(mapload)
	. = ..()
	color_drop = image(icon, null, "brush_color")
	color_drop.color = selected_color

// When picked up
/obj/item/paint_brush/hud_layerise()
	. = ..()
	hud_level = TRUE
	update_paint()

// When put down
/obj/item/paint_brush/reset_plane_and_layer()
	. = ..()
	hud_level = FALSE
	update_paint()

/obj/item/paint_brush/proc/update_paint(new_color)
	if(new_color)
		selected_color = new_color
		color_drop.color = new_color

	cut_overlays()
	if(hud_level)
		add_overlay(color_drop)

/obj/item/paint_palette
	name = "artist's palette"
	desc = "Helps to have a paintbrush, too."
	icon = 'icons/obj/artstuff.dmi'
	icon_state = "palette"

CAPABILITIES(/obj/item/paint_palette)
	// a brush dipped in the palette picks its new colour (the click goes on)
	op("pick_color", item(/obj/item/paint_brush), label("Pick a colour"),
		asks(/datum/prompt/color, fields = list("title" = "Paint Palette", "question" = "Select a new paint color:", "default" = computed(PROC_REF(brush_colour)), "timeout" = 0)),
		then(PROC_REF(brush_color_picked)))

/// The brush's colour now: the question's default.
/obj/item/paint_palette/proc/brush_colour(datum/act/op/A)
	var/obj/item/paint_brush/P = A.held
	return P?.selected_color

/datum/prompt/color/paint_palette
	var/obj/item/paint_brush/brush

/// Old attackby with a brush: the brush takes the picked colour.
/obj/item/paint_palette/proc/brush_color_picked(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/obj/item/paint_brush/P = A.held
	if(R && istype(P))
		P.update_paint(R.value)
	return OP_PASS

/obj/item/frame/painting
	name = "painting frame"
	desc = "The perfect showcase for your favorite deathtrap memories."
	icon = 'icons/obj/decals.dmi'
	refund_amt = 5
	refund_type = /obj/item/stack/material/wood
	icon_state = "frame-empty"
	build_machine_type = /obj/structure/sign/painting

/obj/structure/sign/painting
	name = "Painting"
	desc = "Art or \"Art\"? You decide."
	icon = 'icons/obj/decals.dmi'
	icon_state = "frame-empty"
	var/base_icon_state = "frame"
	//custom_materials = list(/datum/material/wood = 2000)
	//buildable_sign = FALSE
	///Canvas we're currently displaying.
	var/obj/item/canvas/current_canvas
	///Description set when canvas is added.
	var/desc_with_canvas
	var/persistence_id
	var/loaded = FALSE
	var/curator = "nobody! Report bug if you see this."
	var/static/list/art_appreciators = list()

//Presets for art gallery mapping, for paintings to be shared across stations
/obj/structure/sign/painting/public
	name = "\improper Public Painting Exhibit mounting"
	desc = "For art pieces hung by the public."
	desc_with_canvas = "A piece of art (or \"art\"). Anyone could've hung it."
	persistence_id = "public"

/obj/structure/sign/painting/public/north
	pixel_y = 30

/obj/structure/sign/painting/public/south
	pixel_y = -30

/obj/structure/sign/painting/public/east
	pixel_x = 30

/obj/structure/sign/painting/public/west
	pixel_x = -30

/obj/structure/sign/painting/library_secure
	name = "\improper Curated Painting Exhibit mounting"
	desc = "For masterpieces hand-picked by the librarian."
	desc_with_canvas = "A masterpiece hand-picked by the librarian, supposedly."
	persistence_id = "library"
	req_one_access = list(ACCESS_LIBRARY)
	curator = JOB_LIBRARIAN

/obj/structure/sign/painting/chapel_secure
	name = "\improper Religious Painting Exhibit mounting"
	desc = "For masterpieces hand-picked by the chaplain."
	desc_with_canvas = "A masterpiece hand-picked by the chaplain, supposedly."
	persistence_id = "chapel"
	req_one_access = list(ACCESS_CHAPEL_OFFICE)
	curator = JOB_CHAPLAIN

/obj/structure/sign/painting/library_private // keep your smut away from prying eyes, or non-librarians at least
	name = "\improper Private Painting Exhibit mounting"
	desc = "For art pieces deemed too subversive or too illegal to be shared outside of librarians."
	desc_with_canvas = "A painting hung away from lesser minds."
	persistence_id = "library_private"
	req_one_access = list(ACCESS_LIBRARY)
	curator = JOB_LIBRARIAN

/obj/structure/sign/painting/away_areas // for very hard-to-get-to areas
	name = "\improper Remote Painting Exhibit mounting"
	desc = "For art pieces made in the depths of space."
	desc_with_canvas = "A painting hung where only the determined can reach it."
	persistence_id = "away_area"

/// A frame built on a wall (its constructor param).
/obj/structure/sign/painting/var/building = FALSE

// ALLOW(init/INSTANCE_STATE): a persistent painting frame joins the persistence system's frames, and a built one sits on its wall
/obj/structure/sign/painting/Initialize(mapload)
	. = ..()
	if(persistence_id)
		SSpersistence.painting_frames += src // ALLOW(ownership): the persistence system's list of painting frames, joined and left by the frame itself
	if(building)
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -30 : 30)
		pixel_y = (dir & 3)? (dir ==1 ? -30 : 30) : 0

/// Phase 2: leaves the persistent painting frames.
/obj/structure/sign/painting/lifecycle_dematerialize()
	. = ..()
	SSpersistence.painting_frames -= src // ALLOW(ownership): the persistence system's list of painting frames, joined and left by the frame itself

CAPABILITIES(/obj/structure/sign/painting)
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	param(nameof(dir), pos = 1)
	param(nameof(building), pos = 2)

/obj/structure/sign/painting/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!current_canvas && istype(I, /obj/item/canvas))
		frame_canvas(user, I)
	else if(current_canvas && current_canvas.painting_name == initial(current_canvas.painting_name) && istype(I,/obj/item/pen))
		try_rename(user)
	return TRUE

/obj/structure/sign/painting/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	if(current_canvas)
		unframe_canvas(user)
		return OP_OK
	return OP_DECLINE

/obj/structure/sign/painting/examine(mob/user)
	. = ..()
	if(persistence_id)
		. += span_notice("Any painting placed here will be archived at the end of the shift.")

	if(current_canvas)
		current_canvas.tgui_interact(user)
		. += span_notice("Use wirecutters to remove the painting.")
		. += span_notice("Paintings hung here are curated based on interest. The more often someone EXAMINEs the painting, the longer it will stay in rotation.")
		// Painting loaded and persistent frame, give a hint about removal safety
		if(persistence_id)
			if(loaded)
				. += span_warning("Don't worry, the currently framed painting has already been entered into the archives and can be safely removed. It will still be used on future shifts.")
				back_of_the_line(user)
			else
				. += span_warning("This painting has not been entered into the archives yet. Removing it will prevent that from happening.")

/obj/structure/sign/painting/proc/frame_canvas(mob/user,obj/item/canvas/new_canvas)
	if(!allowed(user))
		to_chat(user, span_notice("Access lock prevents you from putting a painting into this frame. Ask [curator] for help!"))
		return
	if(move_into(src, nameof(src.current_canvas), new_canvas, user))
		if(!current_canvas.finalized)
			current_canvas.finalize(user)
		to_chat(user,span_notice("You frame [current_canvas]."))
		update_appearance()

/obj/structure/sign/painting/proc/unframe_canvas(mob/living/user)
	if(!allowed(user))
		to_chat(user, span_notice("Access lock prevents you from removing paintings from this frame. Ask [curator] ((or admins)) for help!"))
		return
	if(current_canvas)
		current_canvas.forceMove(drop_location())
		rel_take(src, nameof(current_canvas))
		loaded = FALSE
		to_chat(user, span_notice("You remove the painting from the frame."))
		update_appearance()

/obj/structure/sign/painting/proc/try_rename(mob/user)
	if(current_canvas.painting_name == initial(current_canvas.painting_name))
		current_canvas.try_rename(user)

/obj/structure/sign/painting/proc/update_appearance()
	name = current_canvas ? "painting - [current_canvas.painting_name]" : initial(name)
	desc = current_canvas ? desc_with_canvas : initial(desc)
	icon_state = "[base_icon_state]-[current_canvas?.generated_icon ? "hidden" : "empty"]"

	cut_overlays()

	if(!current_canvas?.generated_icon)
		return

	. = list()
	var/mutable_appearance/MA = mutable_appearance(current_canvas.generated_icon)
	MA.pixel_x = current_canvas.framed_offset_x
	MA.pixel_y = current_canvas.framed_offset_y
	. += MA
	var/mutable_appearance/frame = mutable_appearance(current_canvas.icon,"[current_canvas.icon_state]frame")
	frame.pixel_x = current_canvas.framed_offset_x + current_canvas.frame_offset_x
	frame.pixel_y = current_canvas.framed_offset_y + current_canvas.frame_offset_y
	. += frame

	add_overlay(.)

/obj/item/canvas/proc/fill_grid_from_icon(icon/I)
	var/h = I.Height() + 1
	for(var/x in 1 to width)
		for(var/y in 1 to height)
			grid[x][y] = I.GetPixel(x,h-y)

/**
 * Loads a painting from SSpersistence. Called globally by said subsystem when it inits
 *
 * Deleting paintings leaves their json, so this proc will remove the json and try again if it finds one of those.
 */
/obj/structure/sign/painting/proc/load_persistent()
	if(!persistence_id || !LAZYLEN(SSpersistence.unpicked_paintings))
		return

	var/list/painting_category = list()
	for (var/list/P in SSpersistence.unpicked_paintings)
		if(P["persistence_id"] == persistence_id)
			painting_category[++painting_category.len] = P

	var/list/painting
	while(!painting)
		if(!length(painting_category))
			return //aborts loading anything this category has no usable paintings
		var/list/chosen = pick(painting_category)
		if(!fexists("data/persistent/paintings/[persistence_id]/[chosen["md5"]].png")) //shitmin deleted this art, lets remove json entry to avoid errors
			painting_category -= list(chosen)
			SSpersistence.unpicked_paintings -= list(chosen)
			continue //and try again
		painting = chosen
		SSpersistence.unpicked_paintings -= list(chosen)

	var/title = painting["title"]
	var/author_name = painting["author"]
	var/author_ckey = painting["ckey"]
	var/png = "data/persistent/paintings/[persistence_id]/[painting["md5"]].png"
	var/icon/I = new(png)
	var/obj/item/canvas/new_canvas
	var/w = I.Width()
	var/h = I.Height()

	for(var/T in typesof(/obj/item/canvas))
		new_canvas = T
		if(initial(new_canvas.width) == w && initial(new_canvas.height) == h)
			new_canvas = new T(src)
			break

	if(!new_canvas)
		WARNING("Couldn't find a canvas to match [w]x[h] of painting")
		return

	new_canvas.fill_grid_from_icon(I)
	new_canvas.generated_icon = I
	new_canvas.icon_generated = TRUE
	new_canvas.finalized = TRUE
	new_canvas.painting_name = title
	new_canvas.author_name = author_name
	new_canvas.author_ckey = author_ckey
	new_canvas.name = "painting - [title]"
	rel_set(src, nameof(current_canvas), new_canvas)
	loaded = TRUE
	update_appearance()

/*
 * Recursive Proc. If given no arguments, requests user to input arguments with warning that generating the list may be res intensive
 * Upon generating arguments, calls itself and spawns the painting
 * Ideally called using the vvar dropdown admin verb and used using debugging the SSpersistence list to minimize lag
 * usr must have an admin holder (ergo: only staff may use this)
 * TODO: create a machine in the library for curators to spawn canvases and refactor this to use the proc used there.
 * For now, we do it this way because calling this on a canvas itself might cause issues due to the whole dimension thing.
*/
/obj/structure/sign/painting/proc/admin_lateload_painting(spawn_specific = 0, which_painting = 0)
	var/mob/admin = usr // ALLOW(sys_usr_outside_verb): called from the vvar dropdown, which is a verb: the admin who chose it is usr
	if(!check_rights_for(admin.client, R_HOLDER))
		return 0
	if(spawn_specific && isnum(which_painting))
		var/list/painting = SSpersistence.all_paintings[which_painting]
		var/title = painting["title"]
		var/author_name = painting["author"]
		var/author_ckey = painting["ckey"]
		to_chat(admin, span_notice("The chosen painting is the following \n\n \
		Title: [title] \n \
		Author's Name: [author_name]. \n \
		Author's CKey: [author_ckey]"))
		open_request(src, /datum/prompt/yes_no/painting_lateload, PROC_REF(lateload_confirmed), answerer = admin, rights = R_HOLDER, which = which_painting, title = "Is this the painting you want?", question = "Check your chat log (if filtering for notices, check where you don't) for painting details.", timeout = 0)
	else
		open_request(src, /datum/prompt/yes_no, PROC_REF(lateload_list_confirmed), answerer = admin, rights = R_HOLDER, title = "Generate list?", question = "No painting list ID was given. You may obtain such by debugging SSPersistence and checking the all_paintings entry. \
			If you do not wish to do that, you may request a list to be generated of painting titles. This might be resource intensive. \
			Proceed? It will likely have over 500 entries", yes_text = "Proceed!", no_text = "Cancel", timeout = 0)

/// The admin's pick of a painting to spawn: the index of the painting is kept on the question.
/datum/prompt/yes_no/painting_lateload
	var/which

/// The paintings an admin can pick from, by the name the list shows them under (the value is the painting's index).
/obj/structure/sign/painting/proc/lateload_choices()
	var/list/paintings = list()
	var/current = 1
	for(var/entry in SSpersistence.all_paintings)
		var/key = "[entry["title"]] by [entry["author"]]"
		paintings[key] = current
		current += 1
	return paintings

/obj/structure/sign/painting/proc/lateload_list_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	open_request(src, /datum/prompt/choice, PROC_REF(lateload_picked), answerer = A.request.answerer, rights = R_HOLDER, choices = assoc_to_keys(lateload_choices()), title = "Spawn painting", question = "Choose which painting to spawn!", timeout = 0)

/obj/structure/sign/painting/proc/lateload_picked(datum/act/request/A)
	if(!A.answer)
		return
	admin_lateload_painting(1, lateload_choices()[A.answer.value])

/obj/structure/sign/painting/proc/lateload_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/yes_no/painting_lateload/R = A.request
	var/which_painting = R.which
	var/list/painting = SSpersistence.all_paintings[which_painting]
	var/title = painting["title"]
	var/author_name = painting["author"]
	var/author_ckey = painting["ckey"]
	var/persistence_id = painting["persistence_id"]
	var/png = "data/persistent/paintings/[persistence_id]/[painting["md5"]].png"
	if(!fexists("data/persistent/paintings/[persistence_id]/[painting["md5"]].png"))
		to_chat(R.answerer, span_warning("Chosen painting could not be loaded! Incident was logged, but no action taken at this time"))
		log_runtime("[R.answerer] tried to spawn painting of list id [which_painting] in all_paintings list and associated file could not be found. \n \
		Painting was titled [title] by [author_ckey] of [persistence_id]")
		return 0

	var/icon/I = new(png)
	var/obj/item/canvas/new_canvas
	var/w = I.Width()
	var/h = I.Height()
	for(var/T in typesof(/obj/item/canvas))
		new_canvas = T
		if(initial(new_canvas.width) == w && initial(new_canvas.height) == h)
			new_canvas = new T(src)
			break

	if(!new_canvas)
		WARNING("Couldn't find a canvas to match [w]x[h] of painting")
		return 0

	new_canvas.fill_grid_from_icon(I)
	new_canvas.generated_icon = I
	new_canvas.icon_generated = TRUE
	new_canvas.finalized = TRUE
	new_canvas.painting_name = title
	new_canvas.author_name = author_name
	new_canvas.author_ckey = author_ckey
	new_canvas.name = "painting - [title]"
	rel_set(src, nameof(current_canvas), new_canvas)
	loaded = TRUE
	update_appearance()
	log_and_message_admins("spawned painting from [author_ckey] with title [title]", R.answerer)

/obj/structure/sign/painting/proc/save_persistent()
	if(!persistence_id || !current_canvas || current_canvas.no_save)
		return
	if(sanitize_filename(persistence_id) != persistence_id)
		stack_trace("Invalid persistence_id - [persistence_id]")
		return
	if(!current_canvas.painting_name)
		current_canvas.painting_name = "Untitled Artwork"

	var/data = current_canvas.get_data_string()
	var/md5 = md5(lowertext(data))
	for(var/list/entry in SSpersistence.all_paintings)
		if(entry["md5"] == md5 && entry["persistence_id"] == persistence_id)
			return
	var/png_directory = "data/persistent/paintings/[persistence_id]/"
	var/png_path = png_directory + "[md5].png"
	var/result = rustg_dmi_create_png(png_path,"[current_canvas.width]","[current_canvas.height]",data)

	if(result)
		CRASH("Error saving persistent painting: [result]")

	SSpersistence.all_paintings += list(list(
		"persistence_id" = persistence_id,
		"title" = current_canvas.painting_name,
		"md5" = md5,
		"author" = current_canvas.author_name,
		"ckey" = current_canvas.author_ckey
	))

/obj/structure/sign/painting/proc/back_of_the_line(mob/user)
	if(user.ckey in art_appreciators)
		return
	if(!persistence_id || !current_canvas || current_canvas.no_save)
		return
	var/data = current_canvas.get_data_string()
	var/md5 = md5(lowertext(data))
	for(var/list/entry in SSpersistence.all_paintings)
		if(entry["md5"] == md5 && entry["persistence_id"] == persistence_id)
			SSpersistence.all_paintings.Remove(list(entry))
			SSpersistence.all_paintings.Add(list(entry))
			art_appreciators += user.ckey
			to_chat(user, span_notice("Showing interest in this painting renews its position in the curator database."))

/obj/structure/sign/painting/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("removepainting", "Remove Persistent Painting")

VV_TOPIC_ACTION(/obj/structure/sign/painting, "removepainting", PROC_REF(vv_topic_remove_painting))

/obj/structure/sign/painting/proc/vv_topic_remove_painting(mob/user, list/args)
	if(!persistence_id || !current_canvas)
		to_chat(user,span_warning("This is not a persistent painting."))
		return
	var/md5 = md5(lowertext(current_canvas.get_data_string()))
	var/author = current_canvas.author_ckey
	var/list/filenames_found = list()
	for(var/list/entry in SSpersistence.all_paintings)
		if(entry["md5"] == md5)
			filenames_found += "data/persistent/paintings/[entry["persistence_id"]]/[entry["md5"]].png"
			SSpersistence.all_paintings -= list(entry)
	for(var/png in filenames_found)
		if(fexists(png))
			fdel(png)
	for(var/obj/structure/sign/painting/P in SSpersistence.painting_frames)
		if(P.current_canvas && md5(P.current_canvas.get_data_string()) == md5)
			own_clear(P, nameof(P.current_canvas), OWN_DELETE)
			P.update_appearance()
	loaded = FALSE
	log_and_message_admins(span_notice("[key_name_admin(user)] has deleted persistent painting made by [author]."))
	return TRUE

// The easel's painting sits on its turf (one-sided REL view).
/obj/structure/sign/painting/ownership()
	. = ..()
	. += owns(nameof(current_canvas), policy = OWN_CONTAINED)
