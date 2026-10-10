/*CONTENTS
Buildable pipes
Buildable meters
*/

/obj/item/pipe
	material_template = /datum/material_template/pressure
	material_total = SHEET_MATERIAL_AMOUNT
	name = "pipe"
	desc = "A pipe."
	var/pipe_type
	var/pipename
	force = 7
	throwforce = 7
	icon = 'icons/obj/pipe-item.dmi'
	icon_state = "simple"
	item_state = "buildpipe"
	w_class = ITEMSIZE_NORMAL
	level = 2
	var/piping_layer = PIPING_LAYER_DEFAULT
	var/dispenser_class // Tells the dispenser what orientations we support, so RPD can show previews.
	var/material_liner_integrity = 100

// One subtype for each way components connect to neighbors
/obj/item/pipe/directional
	dispenser_class = PIPE_DIRECTIONAL
/obj/item/pipe/binary
	dispenser_class = PIPE_STRAIGHT
/obj/item/pipe/binary/bendable
	dispenser_class = PIPE_BENDABLE
/obj/item/pipe/trinary
	dispenser_class = PIPE_TRINARY
/obj/item/pipe/trinary/flippable
	dispenser_class = PIPE_TRIN_M
	var/mirrored = FALSE
/obj/item/pipe/quaternary
	dispenser_class = PIPE_ONEDIR

/**
 * Call constructor with:
 * @param loc Location
 * @pipe_type
 */
/// The device a pipe part is taken from (its constructor param, dropped after init).
/obj/item/pipe/var/tmp/obj/machinery/atmospherics/make_from

// ALLOW(init/INSTANCE_STATE): a pipe part takes the shape of the device it was taken from, or its blueprint's effects, and turns
/obj/item/pipe/Initialize(mapload)
	if(make_from)
		make_from_existing(make_from)
	else
		apply_blueprint_effects()

	update()
	warm_init_dirs()
	make_rotatable()
	. = ..()

/obj/item/pipe/proc/make_from_existing(obj/machinery/atmospherics/make_from)
	set_dir(make_from.dir)
	pipename = make_from.name
	if(make_from.req_access)
		src.req_access = make_from.req_access
	if(make_from.req_one_access)
		src.req_one_access = make_from.req_one_access
	color = make_from.pipe_color
	pipe_type = make_from.type
	material_engineered_id_set(src, make_from.engineered_material_id)
	material_liner_integrity = make_from.material_liner_integrity
	copy_material_construction_from(make_from)

/obj/item/pipe/trinary/flippable/make_from_existing(obj/machinery/atmospherics/trinary/make_from)
	..()
	if(make_from.mirrored)
		do_a_flip()

/obj/item/pipe/dropped(mob/user, equipping, slot)
	if(loc)
		setPipingLayer(piping_layer)
	return ..()

/obj/item/pipe/proc/setPipingLayer(new_layer = PIPING_LAYER_DEFAULT)
	var/obj/machinery/atmospherics/fakeA = pipe_type
	if(initial(fakeA.pipe_flags) & (PIPING_ALL_LAYER|PIPING_DEFAULT_LAYER_ONLY))
		new_layer = PIPING_LAYER_DEFAULT
	piping_layer = new_layer
	// Do it the Polaris way
	switch(piping_layer)
		if(PIPING_LAYER_SCRUBBER)
			color = PIPE_COLOR_RED
			name = "[initial(fakeA.name)] scrubber fitting"
		if(PIPING_LAYER_SUPPLY)
			color = PIPE_COLOR_BLUE
			name = "[initial(fakeA.name)] supply fitting"
		if(PIPING_LAYER_FUEL)
			color = PIPE_COLOR_YELLOW
			name = "[initial(fakeA.name)] fuel fitting"
		if(PIPING_LAYER_AUX)
			color = PIPE_COLOR_CYAN
			name = "[initial(fakeA.name)] aux fitting"

/obj/item/pipe/proc/update()
	var/obj/machinery/atmospherics/fakeA = pipe_type
	name = "[initial(fakeA.name)] fitting"
	icon_state = initial(fakeA.pipe_state)

/obj/item/pipe/proc/do_a_flip()
	set_dir(turn(dir, -180))
	fixdir()

/obj/item/pipe/trinary/flippable/do_a_flip()
	// set_dir(turn(dir, flipped ? 45 : -45))
	// TG has a magic icon set with the flipped versions in the diagonals.
	// We may switch to this later, but for now gotta do some magic.
	mirrored = !mirrored
	var/obj/machinery/atmospherics/fakeA = pipe_type
	icon_state = "[initial(fakeA.pipe_state)][mirrored ? "m" : ""]"

/obj/item/pipe/handle_rotation_verbs(angle, mob/user)
	. = ..()
	if(.)
		fixdir()

// Don't let pulling a pipe straighten it out.
/obj/item/pipe/binary/bendable/Move()
	var/old_bent = !IS_CARDINAL(dir)
	. = ..()
	if(old_bent && IS_CARDINAL(dir))
		set_dir(turn(src.dir, -45))

//Helper to clean up dir
/obj/item/pipe/proc/fixdir()
	return

/obj/item/pipe/binary/fixdir()
	if(dir == SOUTH)
		set_dir(NORTH)
	else if(dir == WEST)
		set_dir(EAST)

/obj/item/pipe/trinary/flippable/fixdir()
	if(dir in GLOB.cornerdirs)
		set_dir(turn(dir, 45))

MSG_DEF_SELF(pipe_item/lined, "It already has a material liner and shell.")
MSG_DEF_SELF(pipe_item/not_on_floor, "Put it down first.")
MSG_DEF_SELF(pipe_item/hogged, "Something is hogging the tile!")
MSG_DEF_SELF(pipe_item/occupied, "There is already a pipe at that location!")
MSG_DEF_SELF(pipe_item/cannot_flip, "You can't do that now.")
MSG_DEF(pipe_item/fastened, "You fasten %T%.", "%U% fastens %T%.")

CAPABILITIES(/obj/item/pipe)
	op("rotate", in_hand(), label("Rotate"), wait(0), then(PROC_REF(rotated)))
	op("flip", menu(), label("Flip Pipe"), wait(0), needs(req_bool(PROC_REF(actor_able), because = MSG(pipe_item/cannot_flip))), then(PROC_REF(flipped)))
	op("line", stack(/obj/item/stack/material, 1), label("Form material"), wait(0), needs(req_bool(PROC_REF(unlined), because = MSG(pipe_item/lined))), then(PROC_REF(lined)))
	op("fasten", tool(TOOL_WRENCH), label("Fasten"), wait(0),
		needs(req_bool(PROC_REF(on_floor), because = MSG(pipe_item/not_on_floor)), req_bool(PROC_REF(tile_free), because = PROC_REF(tile_refusal))),
		says(MSG(pipe_item/fastened)), then(PROC_REF(fastened)))
	param(nameof(pipe_type), pos = 1)
	param(nameof(dir), pos = 2)
	param(nameof(make_from), pos = 3, keep = FALSE)
	rolls(ROLL_PIXEL, PIXEL_JITTER(5))

/obj/item/pipe/proc/rotated(datum/act/op/A)
	set_dir(turn(dir,-90))
	fixdir()
	return OP_OK

/obj/item/pipe/proc/actor_able(datum/act/op/A)
	var/mob/user = A.actor
	return !user.stat && !user.restrained() && user.canmove // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look

/obj/item/pipe/proc/flipped(datum/act/op/A)
	do_a_flip()
	return OP_OK

/obj/item/pipe/proc/unlined(datum/act/A)
	return !material_engineered_id(src)

/// The sheet (the op's cost) becomes the fitting's liner and shell.
/obj/item/pipe/proc/lined(datum/act/op/A)
	var/obj/item/stack/material/stock = A.held
	var/datum/material/material = stock?.material
	if(!material)
		return OP_FAILED
	material_engineered_id_set(src, material.name)
	apply_material_construction(list(MATERIAL_ROLE_STRUCTURE = material.name, MATERIAL_ROLE_LINER = material.name), /datum/material_template/pressure, SHEET_MATERIAL_AMOUNT)
	color = material.icon_colour
	to_chat(A.actor, span_notice("You form [material.display_name] around [src]. Its installed geometry will determine pressure strength, heat transfer, and chemical exposure."))
	return OP_OK

/obj/item/pipe/proc/on_floor(datum/act/A)
	return isturf(loc) // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look

/// What stands in the way of building it here (null: nothing): a dense device's tile, or a pipe already on its layer and directions.
/obj/item/pipe/proc/tile_blocker()
	var/obj/machinery/atmospherics/fakeA = pipe_type // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look
	var/flags = initial(fakeA.pipe_flags)
	for(var/obj/machinery/atmospherics/M in contents_of(loc)) // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look
		if((M.pipe_flags & flags & PIPING_ONE_PER_TURF))	//Only one dense/requires density object per tile, eg connectors/cryo/heater/coolers.
			return /datum/msg/pipe_item/hogged
		if((M.piping_layer != piping_layer) && !((M.pipe_flags | flags) & PIPING_ALL_LAYER)) // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look
			continue
		if(M.get_init_dirs() & SSmachines.get_init_dirs(pipe_type, dir))
			return /datum/msg/pipe_item/occupied
	return null

/// Fills the shared cache of its device's directions for every way it can face, so the wrench's check only reads it (the cache builds an entry
/// by making a probe device, which a requirement may not do).
/obj/item/pipe/proc/warm_init_dirs()
	if(!pipe_type)
		return
	for(var/d in GLOB.alldirs)
		SSmachines.get_init_dirs(pipe_type, d)

/obj/item/pipe/proc/tile_free(datum/act/A)
	return isnull(tile_blocker())

/obj/item/pipe/proc/tile_refusal(datum/act/A)
	return tile_blocker()

/obj/item/pipe/proc/fastened(datum/act/op/A)
	fasten(A.actor)
	return OP_OK

/// Builds the fitting into its device where it lies (a pipe layer calls this too). Returns the device, or null when nothing held it in place.
/obj/item/pipe/proc/fasten(mob/user)
	fixdir()
	var/obj/machinery/atmospherics/M = new pipe_type(loc)
	build_pipe(M)
	// With how the pipe code works, at least one end needs to be connected to something, otherwise the game deletes the segment.
	if(QDELETED(M))
		if(user)
			to_chat(user, span_warning("There's nothing to connect this pipe section to!"))
		return null
	transfer_fingerprints_to(M)
	spent(src, user)
	return M

//called when a turf is attacked with a pipe item
/obj/item/pipe/afterattack(turf/simulated/floor/target, mob/user, proximity)
	if(!proximity) return
	if(istype(target) && user.canUnEquip(src))
		user.drop_from_inventory(src, target)
	else
		return ..()

/obj/item/pipe/proc/build_pipe(obj/machinery/atmospherics/A)
	A.engineered_material_id = material_engineered_id(src)
	A.material_liner_integrity = material_liner_integrity
	A.copy_material_construction_from(src)
	A.set_dir(dir)
	A.init_dir()
	if(pipename)
		A.name = pipename
	if(req_access)
		A.req_access = req_access
	if(req_one_access)
		A.req_one_access = req_one_access
	A.on_construction(color, piping_layer)

/obj/item/pipe/trinary/flippable/build_pipe(obj/machinery/atmospherics/trinary/T)
	T.mirrored = mirrored
	. = ..()

// Lookup the initialize_directions for a given atmos machinery instance facing dir.
// TODO - Right now this determines the answer by instantiating an instance and checking!
// There has to be a better way... ~Leshana
/datum/system/machines/proc/get_init_dirs(type, dir)
	return CACHED2(pipe_init_dirs, type, dir)

DECLARE_SHARED_CACHE(pipe_init_dirs, GLOBAL_PROC_REF(build_pipe_init_dirs), SC_NEVER)

/// Builder for pipe_init_dirs: instantiates a probe of `type` facing `dir`.
/proc/build_pipe_init_dirs(type, dir)
	var/obj/machinery/atmospherics/temp = new type(null, dir)
	. = temp.get_init_dirs()
	spent(temp)

//
// Meters are special - not like any other pipes or components
//

/obj/item/pipe_meter
	name = "meter"
	desc = "A meter that can be laid on pipes."
	icon = 'icons/obj/pipe-item.dmi'
	icon_state = "meter"
	item_state = "buildpipe"
	w_class = ITEMSIZE_LARGE
	var/piping_layer = PIPING_LAYER_DEFAULT

MSG_DEF_SELF(pipe_meter/no_pipe, "You need to fasten it to a pipe!")
MSG_DEF_SELF(pipe_meter/fastened, "You fasten the meter to the pipe.")

CAPABILITIES(/obj/item/pipe_meter)
	op("fasten", tool(TOOL_WRENCH), label("Fasten"), wait(0), needs(req_bool(PROC_REF(pipe_here), because = MSG(pipe_meter/no_pipe))), says(MSG(pipe_meter/fastened)), then(PROC_REF(fastened)))

/obj/item/pipe_meter/proc/pipe_here(datum/act/A)
	for(var/obj/machinery/atmospherics/pipe/P in contents_of(loc)) // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look
		if(P.piping_layer == piping_layer) // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look
			return TRUE
	return FALSE

/obj/item/pipe_meter/proc/fastened(datum/act/op/A)
	replace_with(src, /obj/machinery/meter, piping_layer)
	return OP_OK

/obj/item/pipe_meter/dropped(mob/user, equipping, slot)
	. = ..()
	if(loc)
		setAttachLayer(piping_layer)

/obj/item/pipe_meter/proc/setAttachLayer(new_layer = PIPING_LAYER_DEFAULT)
	piping_layer = new_layer

/obj/item/pipe_gsensor
	name = "gas sensor"
	desc = "A sensor that can be hooked to a computer."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "gsensor0"
	item_state = "buildpipe"
	w_class = ITEMSIZE_LARGE
	var/label = null
	var/id_tag
	var/output = 3

MSG_DEF_SELF(pipe_gsensor/fastened, "You fasten the sensor down.")

CAPABILITIES(/obj/item/pipe_gsensor)
	op("fasten", tool(TOOL_WRENCH), label("Fasten"), wait(0), says(MSG(pipe_gsensor/fastened)), then(PROC_REF(fastened)))

/obj/item/pipe_gsensor/proc/fastened(datum/act/op/A)
	var/obj/machinery/air_sensor/air_sensor = new /obj/machinery/air_sensor(loc)
	air_sensor.id_tag = id_tag
	air_sensor.set_output(output)
	replace_with(src, air_sensor)
	return OP_OK
