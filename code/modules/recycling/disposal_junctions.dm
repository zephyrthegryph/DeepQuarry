/obj/structure/disposalpipe/junction/yjunction
	icon_state = "pipe-y"

//a three-way junction with dir being the dominant direction
/obj/structure/disposalpipe/junction
	icon_state = "pipe-j1"

// ALLOW(init/INSTANCE_STATE): its pipe directions follow the way it was placed
/obj/structure/disposalpipe/junction/Initialize(mapload)
	. = ..()
	if(icon_state == "pipe-j1")
		dpdir = dir | turn(dir, -90) | turn(dir,180)
	else if(icon_state == "pipe-j2")
		dpdir = dir | turn(dir, 90) | turn(dir,180)
	else // pipe-y
		dpdir = dir | turn(dir,90) | turn(dir, -90)
	update()
	return

// next direction to move
// if coming in from secondary dirs, then next is primary dir
// if coming in from primary dir, then next is equal chance of other dirs

/obj/structure/disposalpipe/junction/nextdir(fromdir)
	var/flipdir = turn(fromdir, 180)
	if(flipdir != dir)	// came from secondary dir
		return dir		// so exit through primary
						// came from primary
						// so need to choose either secondary exit
	var/mask = ..(fromdir)

	// find a bit which is set
	var/setbit = 0
	if(mask & NORTH)
		setbit = NORTH
	else if(mask & SOUTH)
		setbit = SOUTH
	else if(mask & EAST)
		setbit = EAST
	else
		setbit = WEST

	if(prob(50))	// 50% chance to choose the found bit or the other one
		return setbit

	return mask & (~setbit)

//a three-way junction that sorts objects
/obj/structure/disposalpipe/sortjunction
	name = "sorting junction"
	icon_state = "pipe-j1s"
	desc = "An underfloor disposal pipe with a package sorting mechanism."

	var/sortdir = 0

	var/last_sort = FALSE
	var/sort_scan = TRUE
	var/panel_open = FALSE
TRACKED(/obj/structure/disposalpipe/sortjunction, panel_open)

/obj/structure/disposalpipe/sortjunction/proc/updatedesc()
	desc = initial(desc)
	if(sortType)
		desc += "\nIt's filtering objects with the '[sortType]' tag."

/obj/structure/disposalpipe/sortjunction/proc/updatename()
	if(sortType)
		name = "[initial(name)] ([sortType])"
		return
	name = initial(name)

/// Phase 2: leaves the tagger index.
/obj/structure/disposalpipe/sortjunction/lifecycle_dematerialize()
	. = ..()
	if(sortType)
		LAZYREMOVE(GLOB.tagger_locations["[sortType]"], get_z(src))

/obj/structure/disposalpipe/sortjunction/proc/updatedir()
	var/negdir = turn(dir, 180)

	if(icon_state == "pipe-j1s")
		sortdir = turn(dir, -90)
	else if(icon_state == "pipe-j2s")
		sortdir = turn(dir, 90)

	dpdir = sortdir | dir | negdir

/obj/structure/disposalpipe/sortjunction/Initialize(mapload)
	. = ..()
	if(sortType)
		LAZYADD(GLOB.tagger_locations["[sortType]"], get_z(src))


	updatedir()
	updatename()
	updatedesc()
	update()

/// Old attackby.
/obj/structure/disposalpipe/sortjunction/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held

	if(istype(I, /obj/item/destTagger))
		var/obj/item/destTagger/O = I

		if(O.currTag)// Tag set
			var/current_z = get_z(src)
			if(sortType)
				LAZYREMOVE(GLOB.tagger_locations["[sortType]"], current_z)
			sortType = O.currTag
			LAZYADD(GLOB.tagger_locations["[sortType]"], current_z)
			play_sfx(src, SFX_MACHINES_TWOBEEP, 2)
			to_chat(user, span_blue("Changed filter to '[sortType]'."))
			updatename()
			updatedesc()
	return OP_PASS

/obj/structure/disposalpipe/sortjunction/screwdriver_act(mob/user, obj/item/I)
	set_panel_open(!panel_open)
	playsound(src, I.usesound, 100, 1)
	to_chat(user, span_notice("You [panel_open ? "open" : "close"] the wire panel."))
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposalpipe/sortjunction/multitool_act(mob/user, obj/item/I)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	wires_open(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposalpipe/sortjunction/wirecutter_act(mob/user, obj/item/I)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	wires_open(src, user)
	return ITEM_INTERACT_SUCCESS

/obj/structure/disposalpipe/sortjunction/proc/divert_check(checkTag)
	return sortType == checkTag

// next direction to move
// if coming in from negdir then next is primary dir or sortdir
// if coming in from dir, Then next is negdir or sortdir
// if coming in from sortdir, always go to posdir

/obj/structure/disposalpipe/sortjunction/nextdir(fromdir, sortTag)
	if(sort_scan)
		if(divert_check(sortTag))
			if(!wire_is_cut(src, WIRE_SORT_SIDE))
				last_sort = TRUE
		else
			if(!wire_is_cut(src, WIRE_SORT_FORWARD))
				last_sort = FALSE
	if(fromdir != sortdir && last_sort)
		return sortdir
		// so go with the flow to positive direction
	return dir

/obj/structure/disposalpipe/sortjunction/proc/reset_scan()
	if(!wire_is_cut(src, WIRE_SORT_SCAN))
		sort_scan = TRUE

/obj/structure/disposalpipe/sortjunction/transfer(obj/structure/disposalholder/H)
	var/nextdir = nextdir(H.dir, H.destinationTag)
	H.set_dir(nextdir)
	var/turf/T = H.nextloc()
	var/obj/structure/disposalpipe/P = H.findpipe(T)

	if(P)
		// find other holder in next loc, if inactive merge it with current
		var/obj/structure/disposalholder/H2 = locate_within(P, /obj/structure/disposalholder)
		if(H2 && !H2.active)
			H.merge(H2)

		H.forceMove(P)
	else			// if wasn't a pipe, then set loc to turf
		H.forceMove(T)
		return null

	return P

/obj/structure/disposalpipe/sortjunction/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(panel_open)
		look.overlay("[drawn_state]-open")

//a three-way junction that filters all wrapped and tagged items
/obj/structure/disposalpipe/sortjunction/wildcard
	name = "wildcard sorting junction"
	desc = "An underfloor disposal pipe which filters all wrapped and tagged items."
	subtype = DISPOSAL_SORT_WILDCARD

/obj/structure/disposalpipe/sortjunction/wildcard/divert_check(checkTag)
	return checkTag != ""

//junction that filters all untagged items
/obj/structure/disposalpipe/sortjunction/untagged
	name = "untagged sorting junction"
	desc = "An underfloor disposal pipe which filters all untagged items."
	subtype = DISPOSAL_SORT_UNTAGGED

/obj/structure/disposalpipe/sortjunction/untagged/divert_check(checkTag)
	return checkTag == ""

/obj/structure/disposalpipe/sortjunction/flipped //for easier and cleaner mapping
	icon_state = "pipe-j2s"

/obj/structure/disposalpipe/sortjunction/wildcard/flipped
	icon_state = "pipe-j2s"

/obj/structure/disposalpipe/sortjunction/untagged/flipped
	icon_state = "pipe-j2s"

//junction that filters bodies and IDs
#define CORPSE_SORT_TAG "corpse"

/obj/structure/disposalpipe/sortjunction/bodies
	name = "body recovery junction"
	desc = "An underfloor disposal pipe which filters out detectable bodies, living or soon to be dead. Also diverts anything containing an ID."
	subtype = DISPOSAL_SORT_BODIES

/obj/structure/disposalpipe/sortjunction/bodies/transfer(obj/structure/disposalholder/H)
	if(H.destinationTag == "")
		// If the package isn't mail and we're a body sorter, check if it has a body/ID, and divert it if so.
		H.destinationTag = check_for_corpse_or_id(H)
	. = ..()

/obj/structure/disposalpipe/sortjunction/bodies/divert_check(checkTag)
	return checkTag == CORPSE_SORT_TAG

/obj/structure/disposalpipe/sortjunction/bodies/flipped
	icon_state = "pipe-j2s"

/obj/structure/disposalpipe/sortjunction/bodies/proc/check_for_corpse_or_id(obj/structure/disposalholder/H)
	for(var/mob/living/L in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
		if(iscarbon(L)) // only living carbons count not silicons, drones can control their own mailing destination...
			return CORPSE_SORT_TAG

	// Check for microholders, you can't skip the system this way either!
	for(var/obj/item/holder/hl in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
		if(isliving(hl.held_mob))
			return CORPSE_SORT_TAG

	// find an ID in items
	for(var/obj/item/card/id in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
		if(!istype(id,/obj/item/card/id/guest))
			return CORPSE_SORT_TAG
	for(var/obj/item/pda/P in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
		if(!istype(P.id,/obj/item/card/id/guest))
			return CORPSE_SORT_TAG

	// Check in bags, only one level deep. Need to check for pda again too
	for(var/obj/item/storage/bag in H.slot_contents(CONTAINER_SLOT_DISPOSAL))
		for(var/obj/item/pda/P in bag.slot_contents())
			if(!istype(P.id,/obj/item/card/id/guest))
				return CORPSE_SORT_TAG
		for(var/obj/item/card/id in bag.slot_contents())
			if(!istype(id,/obj/item/card/id/guest))
				return CORPSE_SORT_TAG

	return H.destinationTag

#undef CORPSE_SORT_TAG

// ---- the wires ----

CAPABILITIES(/obj/structure/disposalpipe/sortjunction)
	space(SPACE_PANEL, door = nameof(panel_open))
	wires(name = "Disposals Sorting Pipe", count = 6, tools = FALSE, status_lines = PROC_REF(wire_lights))
	on_wire(WIRE_SORT_SCAN, cut = PROC_REF(scan_wire_cut), pulse = PROC_REF(scan_wire_pulsed))
	on_wire(WIRE_SORT_FORWARD, pulse = PROC_REF(forward_wire_pulsed))
	on_wire(WIRE_SORT_SIDE, pulse = PROC_REF(side_wire_pulsed))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))


/obj/structure/disposalpipe/sortjunction/proc/wire_lights()
	return list(
		"The sorting light is [last_sort ? "green" : "red"].",
		"The scan light is [sort_scan ? "lit" : "off"].")

/// The scan wire cut freezes the sorter for good; mended, it scans again.
/obj/structure/disposalpipe/sortjunction/proc/scan_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	sort_scan = N.mended

/// The scan wire pulsed freezes sorting for ten seconds.
/obj/structure/disposalpipe/sortjunction/proc/scan_wire_pulsed(datum/act/A)
	if(sort_scan)
		sort_scan = FALSE
	after(src, 10 SECONDS, PROC_REF(reset_scan))

/// A frozen sorter sends things forward.
/obj/structure/disposalpipe/sortjunction/proc/forward_wire_pulsed(datum/act/A)
	last_sort = FALSE

/// A frozen sorter sends things aside.
/obj/structure/disposalpipe/sortjunction/proc/side_wire_pulsed(datum/act/A)
	last_sort = TRUE
