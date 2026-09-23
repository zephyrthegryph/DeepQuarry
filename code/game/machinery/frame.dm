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
	var/icon/icon_override		// Icon to set on frame object when building. If null icon is unchanged.
	var/name					// Name assigned to the frame object.
	var/frame_size = 5			// Sheets of metal required to build.
	var/frame_class				// Determines construction method.  "machine", "computer", "alarm", or "display"
	var/circuit					// Type path of the circuit board that comes built in with this frame. Null to require adding a circuit.
	var/frame_style = FRAME_STYLE_FLOOR	// "floor" or "wall"
	var/x_offset				// For wall frames: pixel_x
	var/y_offset				// For wall frames: pixel_y

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

/obj/structure/frame/update_icon()
	..()
	if(frame_type.icon_override)
		icon = frame_type.icon_override
	icon_state = frame_type.get_icon_state(state)

/obj/structure/frame/proc/check_components(mob/user as mob)
	components = list()
	req_components = circuit.req_components.Copy()
	for(var/A in circuit.req_components)
		req_components[A] = circuit.req_components[A]
	req_component_names = circuit.req_components.Copy()
	for(var/obj/ct as anything in req_components)
		req_component_names[ct] = initial(ct.name)

/obj/structure/frame/Initialize(mapload, dir, building = 0, datum/frame/frame_types/type, mob/user as mob)
	. = ..()
	if(building)
		frame_type = type
		state = FRAME_PLACED

		if(dir)
			set_dir(dir)

		if(frame_type.x_offset)
			pixel_x = (dir & 3)? 0 : (dir == EAST ? -frame_type.x_offset : frame_type.x_offset)

		if(frame_type.y_offset)
			pixel_y = (dir & 3)? (dir == NORTH ? -frame_type.y_offset : frame_type.y_offset) : 0

		if(frame_type.circuit)
			need_circuit = FALSE
			circuit = new frame_type.circuit(src)

	if(frame_type.name == "Computer")
		density = TRUE

	if(frame_type.frame_class == FRAME_CLASS_MACHINE)
		density = TRUE

	update_icon()

	AddElement(/datum/element/climbable)
	AddElement(/datum/element/rotatable)

// The board, cables, glass and tool steps are the frame's construction graph:
// frame_construction.dm. Stock parts still go in here until C6.
/obj/structure/frame/attackby(obj/item/P as obj, mob/user as mob)
	// A construction tool with no step here does nothing (it used to stop at its *_act hook).
	for(var/quality in list(TOOL_SCREWDRIVER, TOOL_CROWBAR, TOOL_WRENCH, TOOL_WIRECUTTER, TOOL_WELDER))
		if(P.has_tool_quality(quality))
			return
	if(istype(P, /obj/item/stack/cable_coil) && state == FRAME_WIRED && frame_type.frame_class == FRAME_CLASS_MACHINE)
		for(var/I in req_components)
			if(istype(P, I) && (req_components[I] > 0))
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				var/obj/item/stack/cable_coil/CP = P
				if(CP.get_amount() > 1)
					var/camt = min(CP.get_amount(), req_components[I]) // amount of cable to take, idealy amount required, but limited by amount provided
					var/obj/item/stack/cable_coil/CC = new /obj/item/stack/cable_coil(src, camt)
					CC.update_icon()
					CP.use(camt)
					components += CC
					req_components[I] -= camt
					update_desc()
				break
			user.drop_item()
			P.forceMove(src)
			components += P
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
				NS.update_icon()
				ST.use(camt)
				LAZYADD(components, NS)
				req_components[I] -= camt
				break

		if(istype(P.loc,/obj/item/storage))
			var/obj/item/storage/holder = P.loc
			holder.remove_from_storage(P, src)
		else
			user.drop_item()
			P.forceMove(src)
		LAZYADD(components, P)
		req_components[I]--
		break

	if(defer_feedback)
		return installed_part

	if(installed_part)
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		update_desc()
		to_chat(user, desc)
		return TRUE

	to_chat(user, span_warning("You cannot add that component to the machine!"))
	return FALSE

/obj/structure/frame/proc/mass_install_parts(mob/user, obj/item/storage/S)
	var/installed_part = FALSE
	for(var/obj/item/P in S.contents)
		installed_part |= install_part(user, P, TRUE)
	if(!installed_part)
		return FALSE
	playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
	update_desc()
	to_chat(user, desc)
	return TRUE
