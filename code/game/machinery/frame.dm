GLOBAL_LIST(construction_frame_wall)
GLOBAL_LIST(construction_frame_floor)

/proc/populate_frame_types()
	//Create global frame type list if it hasn't been made already.
	GLOB.construction_frame_wall = list()
	GLOB.construction_frame_floor = list()
	for(var/R in subtypesof(/datum/frame/frame_types))
		var/datum/frame/frame_types/type = new R
		if(type.frame_style == FRAME_STYLE_WALL)
			GLOB.construction_frame_wall += type
		else
			GLOB.construction_frame_floor += type

//////////////////////////////
// Frame Type Datum - Describes the frame structures that can be created from a frame item.
//////////////////////////////
/datum/frame/frame_types
	var/icon_override		// Icon to set on frame object when building. If null icon is unchanged.
	var/name					// Name assigned to the frame object.
	var/frame_size = 5			// Sheets of metal required to build.
	var/frame_class				// Determines construction method.  "machine", "computer", "alarm", or "display"
	var/circuit					// Type path of the circuit board that comes built in with this frame. Null to require adding a circuit.
	var/frame_style = FRAME_STYLE_FLOOR	// "floor" or "wall"
	var/x_offset				// For wall frames: pixel_x
	var/y_offset				// For wall frames: pixel_y

/// A private copy of a frame type. A frame owns its frame_type, so a frame built from a shared
/// entry (GLOB.construction_frame_*) or from a board's board_type (which the board owns) takes a copy.
/// Some boards hold text ("other") instead of an instance: that passes through unchanged.
/proc/frame_type_copy(value)
	var/datum/frame/frame_types/source = value
	if(!istype(source))
		return value
	var/datum/frame/frame_types/copy = new source.type
	copy.icon_override = source.icon_override
	copy.name = source.name
	copy.frame_size = source.frame_size
	copy.frame_class = source.frame_class
	copy.circuit = source.circuit
	copy.frame_style = source.frame_style
	copy.x_offset = source.x_offset
	copy.y_offset = source.y_offset
	return copy

// Get the icon state to use at a given state.  Default implementation is based on the frame's name
/datum/frame/frame_types/proc/get_icon_state(state)
	var/type = lowertext(name)
	type = replacetext(type, " ", "_")
	return "[type]_[state]"

/datum/frame/frame_types/button
	name = "Button"
	frame_class = FRAME_CLASS_ALARM
	frame_size = 1
	frame_style = FRAME_STYLE_WALL
	x_offset = 24
	y_offset = 24

/datum/frame/frame_types/computer
	name = "Computer"
	icon_override = 'icons/obj/stock_parts_vr.dmi'
	frame_class = FRAME_CLASS_COMPUTER

/datum/frame/frame_types/machine
	name = "Machine"
	icon_override = 'icons/obj/stock_parts_vr.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/conveyor
	name = "Conveyor"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/conveyor

/datum/frame/frame_types/photocopier
	name = "Photocopier"
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/washing_machine
	name = "Washing Machine"
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/medical_console
	name = "Medical Console"
	frame_class = FRAME_CLASS_COMPUTER

/datum/frame/frame_types/medical_pod
	name = "Medical Pod"
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/dna_analyzer
	name = "DNA Analyzer"
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/mass_driver
	name = "Mass Driver"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/mass_driver

/datum/frame/frame_types/holopad
	name = "Holopad"
	frame_class = FRAME_CLASS_COMPUTER
	frame_size = 4

/datum/frame/frame_types/microwave
	name = "Microwave"
	frame_class = FRAME_CLASS_MACHINE
	frame_size = 4

/datum/frame/frame_types/fax
	name = "Fax"
	frame_class = FRAME_CLASS_MACHINE
	frame_size = 3

/datum/frame/frame_types/recharger
	name = "Recharger"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/recharger
	frame_size = 3

/datum/frame/frame_types/cell_charger
	name = "Heavy-Duty Cell Charger"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/cell_charger
	frame_size = 3

/datum/frame/frame_types/grinder
	name = "Grinder"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/grinder
	frame_size = 3

/datum/frame/frame_types/reagent_distillery
	name = "Distillery"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/distiller
	frame_size = 4

/datum/frame/frame_types/display
	name = "Display"
	frame_class = FRAME_CLASS_DISPLAY
	frame_style = FRAME_STYLE_WALL
	x_offset = 32
	y_offset = 32

/datum/frame/frame_types/supply_request_console
	name = "Supply Request Console"
	frame_class = FRAME_CLASS_DISPLAY
	frame_style = FRAME_STYLE_WALL
	x_offset = 32
	y_offset = 32

/datum/frame/frame_types/atm
	name = "ATM"
	frame_class = FRAME_CLASS_DISPLAY
	frame_size = 3
	frame_style = FRAME_STYLE_WALL
	x_offset = 32
	y_offset = 32

/datum/frame/frame_types/newscaster
	name = "Newscaster"
	frame_class = FRAME_CLASS_DISPLAY
	frame_size = 3
	frame_style = FRAME_STYLE_WALL
	x_offset = 28
	y_offset = 30

/datum/frame/frame_types/wall_charger
	name = "Wall Charger"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/recharger/wrecharger
	frame_size = 3
	frame_style = FRAME_STYLE_WALL
	x_offset = 32
	y_offset = 32

/datum/frame/frame_types/fire_alarm
	name = "Fire Alarm"
	frame_class = FRAME_CLASS_ALARM
	frame_size = 2
	frame_style = FRAME_STYLE_WALL
	x_offset = 24
	y_offset = 24

/datum/frame/frame_types/air_alarm
	name = "Air Alarm"
	icon_override = 'icons/obj/monitors_vr.dmi' // Matching frame.
	frame_class = FRAME_CLASS_ALARM
	frame_size = 2
	frame_style = FRAME_STYLE_WALL
	x_offset = 24
	y_offset = 24

/datum/frame/frame_types/guest_pass_console
	name = "Guest Pass Console"
	frame_class = FRAME_CLASS_DISPLAY
	frame_size = 2
	frame_style = FRAME_STYLE_WALL
	x_offset = 30
	y_offset = 30

/datum/frame/frame_types/intercom
	name = "Intercom"
	frame_class = FRAME_CLASS_ALARM
	frame_size = 2
	frame_style = FRAME_STYLE_WALL
	x_offset = 28
	y_offset = 28

/datum/frame/frame_types/keycard_authenticator
	name = "Keycard Authenticator"
	frame_class = FRAME_CLASS_ALARM
	frame_size = 1
	frame_style = FRAME_STYLE_WALL
	x_offset = 24
	y_offset = 24

/datum/frame/frame_types/geiger
	name = "Geiger Counter"
	frame_class = FRAME_CLASS_ALARM
	frame_size = 2
	frame_style = FRAME_STYLE_WALL
	x_offset = 28
	y_offset = 28

/datum/frame/frame_types/arfgs
	name = "ARF Generator"
	frame_class = FRAME_CLASS_MACHINE
	frame_size = 3

/datum/frame/frame_types/injector_maker
	name = "Ready-to-Use Medicine 3000"
	frame_class = FRAME_CLASS_MACHINE
	circuit = /obj/item/circuitboard/injector_maker
	frame_size = 3

// Refinery machines
/datum/frame/frame_types/industrial_reagent_grinder
	name = "Industrial Chemical Grinder"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_pump
	name = "Industrial Chemical Pump"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_filter
	name = "Industrial Chemical Filter"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_vat
	name = "Industrial Chemical Vat"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_mixer
	name = "Industrial Chemical Mixer"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_pipe
	name = "Industrial Chemical Pipe"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_splitter
	name = "Industrial Chemical Splitter"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_waste_processor
	name = "Industrial Chemical Waste Processor"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_hub
	name = "Industrial Chemical Hub"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_reactor
	name = "Industrial Chemical Reactor"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

/datum/frame/frame_types/industrial_reagent_furnace
	name = "Industrial Chemical Sintering Furnace"
	icon_override = 'icons/obj/stock_parts_refinery.dmi'
	frame_class = FRAME_CLASS_MACHINE

//////////////////////////////
// Frame Object (Structure)
//////////////////////////////

/obj/structure/frame
	material_template = /datum/material_template/machine_part
	material_total = 5 * SHEET_MATERIAL_AMOUNT
	anchored = FALSE
	name = "frame"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "machine_0"
	flags = WALL_ITEM
	var/state = FRAME_PLACED
	var/obj/item/circuitboard/circuit = null
	var/need_circuit = TRUE
	var/datum/frame/frame_types/frame_type = new /datum/frame/frame_types/machine

	var/list/components
	var/list/req_components = null
	var/list/req_component_names = null

CAPABILITIES(/obj/structure/frame)
	rotatable()
	construction(native_frame_graph())
	owns_many(nameof(components))
	climb()
	param(nameof(dir), pos = 1)
	param(nameof(building), pos = 2)
	param(nameof(type_at_make), pos = 3)
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_item)))

/obj/structure/frame/computer //used for maps
	frame_type = new /datum/frame/frame_types/computer
	anchored = TRUE
	density = TRUE

/obj/structure/frame/examine(mob/user)
	. = ..()
	if(circuit)
		. += "It has \a [circuit] installed."

/obj/structure/frame/proc/update_desc()
	var/D
	if(req_components)
		var/list/component_list = list()
		for(var/I in req_components)
			if(req_components[I] > 0)
				component_list += "[num2text(req_components[I])] [req_component_names[I]]"
		D = "Requires [english_list(component_list)]."
	desc = D

DECLARE_APPEARANCE_PROC(/obj/structure/frame, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/frame/appearance_overlays()
	. = list()
	. += ..()
	if(frame_type.icon_override)
		icon = frame_type.icon_override
	icon_state = frame_type.get_icon_state(state)

/obj/structure/frame/proc/check_components(mob/user as mob)
	rel_take_all(src, nameof(components))
	req_components = circuit.req_components.Copy()
	for(var/A in circuit.req_components)
		req_components[A] = circuit.req_components[A]
	req_component_names = circuit.req_components.Copy()
	for(var/ct_path in req_components)
		var/obj/ct = ct_path
		req_component_names[ct_path] = initial(ct.name)

/// Whether the frame is being placed, and its frame type (its constructor params).
/obj/structure/frame/var/building = FALSE
/obj/structure/frame/var/datum/frame/frame_types/type_at_make

// ALLOW(init/INSTANCE_STATE): a placed frame takes its frame type's offsets and circuit, and a machine or computer frame is dense
/obj/structure/frame/Initialize(mapload)
	. = ..()
	if(building)
		rel_set(src, nameof(frame_type), frame_type_copy(type_at_make))
		state = FRAME_PLACED

		if(frame_type.x_offset)
			pixel_x = (dir & 3)? 0 : (dir == EAST ? -frame_type.x_offset : frame_type.x_offset)

		if(frame_type.y_offset)
			pixel_y = (dir & 3)? (dir == NORTH ? -frame_type.y_offset : frame_type.y_offset) : 0

		if(frame_type.circuit)
			need_circuit = FALSE
			rel_set(src, nameof(circuit), new frame_type.circuit(src))

	if(frame_type.name == "Computer")
		set_density(TRUE)

	if(frame_type.frame_class == FRAME_CLASS_MACHINE)
		set_density(TRUE)

	seed_native_frame_graph()
	update_icon()

// The board, cables, glass and tool steps are the frame's construction graph:
// frame_construction.dm. Stock parts still go in here until C6.

/// Old attackby.
/obj/structure/frame/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/P = A.held
	// A construction tool with no step here does nothing (it used to stop at its *_act hook).
	for(var/quality in list(TOOL_SCREWDRIVER, TOOL_CROWBAR, TOOL_WRENCH, TOOL_WIRECUTTER, TOOL_WELDER))
		if(P.has_tool_quality(quality))
			return OP_PASS
	if(istype(P, /obj/item/stack/cable_coil) && state == FRAME_WIRED && frame_type.frame_class == FRAME_CLASS_MACHINE)
		for(var/I in req_components)
			if(istype(P, I) && (req_components[I] > 0))
				play_sfx(src, SFX_ITEMS_DECONSTRUCT)
				var/obj/item/stack/cable_coil/CP = P
				if(CP.get_amount() > 1)
					var/camt = min(CP.get_amount(), req_components[I]) // amount of cable to take, idealy amount required, but limited by amount provided
					var/obj/item/stack/cable_coil/CC = new /obj/item/stack/cable_coil(src, camt)
					CP.use(camt)
					rel_add(src, nameof(components), CC)
					req_components[I] -= camt
					update_desc()
					break
				if(!move_into(src, nameof(components), P, user))
					break
				req_components[I]--
				update_desc()
				break
		to_chat(user, desc)

	else if(istype(P, /obj/item))
		if(state == FRAME_WIRED)
			if(frame_type.frame_class == FRAME_CLASS_MACHINE)
				if(istype(P, /obj/item/storage))
					mass_install_parts(user,P)
				else
					install_part(user,P)

	update_icon()
	return OP_PASS

/obj/structure/frame/proc/install_part(mob/user, obj/item/P, defer_feedback = FALSE)
	var/installed_part = FALSE
	for(var/I in req_components)
		if(!istype(P, I) || (req_components[I] == 0))
			continue

		installed_part = TRUE
		if(istype(P, /obj/item/stack))
			var/obj/item/stack/ST = P
			if(ST.get_amount() > 1)
				var/camt = min(ST.get_amount(), req_components[I]) // amount of stack to take, idealy amount required, but limited by amount provided
				var/obj/item/stack/NS = new ST.stacktype(src, camt)
				ST.use(camt)
				rel_add(src, nameof(components), NS)
				req_components[I] -= camt
				break

		if(!move_into(src, nameof(components), P, user))
			installed_part = FALSE
			break
		req_components[I]--
		break

	if(defer_feedback)
		return installed_part

	if(installed_part)
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		update_desc()
		to_chat(user, desc)
		return TRUE

	to_chat(user, span_warning("You cannot add that component to the machine!"))
	return FALSE

/obj/structure/frame/proc/mass_install_parts(mob/user, obj/item/storage/S)
	var/installed_part = FALSE
	for(var/obj/item/P in contents_of(S))
		installed_part |= install_part(user, P, TRUE)
	if(!installed_part)
		return FALSE
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	update_desc()
	to_chat(user, desc)
	return TRUE

/obj/structure/frame/ownership()
	. = ..()
	. += owns(nameof(circuit), policy = OWN_CONTAINED)
	// The frame owns its frame type (its own default instance, or a copy: frame_type_copy()).
	. += owns(nameof(frame_type), policy = OWN_DELETE)

