// Disposal pipe construction
// This is the pipe that you drag around, not the attached ones.

/obj/structure/disposalconstruct

	name = "disposal pipe segment"
	desc = "A huge pipe segment used for constructing disposal systems."
	icon = 'icons/obj/pipes/disposal.dmi'
	icon_state = "conpipe-s"
	anchored = FALSE
	density = FALSE
	level = 2
	var/sortType = ""
	var/ptype = 0
	var/subtype = 0
	var/dpdir = 0	// directions as disposalpipe
	var/base_state = "pipe-s"

CAPABILITIES(/obj/structure/disposalconstruct)
	configure(pressure_response(pressure = 5*ONE_ATMOSPHERE))
	rotatable()
	param(nameof(ptype), pos = 1)
	param(nameof(dir), pos = 2)
	param(nameof(flipped_at_make), pos = 3)
	param(nameof(subtype_at_make), pos = 4)
	op("flip", menu(), label("Flip Pipe"), needs(req_adjacent(), req_capable(), req_is(nameof(anchored), FALSE, because = MSG(disposalconstruct/unfasten_first))), then(PROC_REF(disposalconstruct_verb_flip)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("use_welder", lit_welder(fuel = 0), label("Weld in place"), needs(req(PROC_REF(weld_refusal))), starts(PROC_REF(weld_started)), begins(PROC_REF(weld_begins)), wait(2 SECONDS), then(PROC_REF(welder_act_tool_done)))

MSG_DEF_SELF(disposalconstruct/unfasten_first, "you must unfasten the pipe before flipping it")

/// Whether the part is made flipped, and its sort type (its constructor params).
/obj/structure/disposalconstruct/var/flipped_at_make = FALSE
/obj/structure/disposalconstruct/var/subtype_at_make = 0

// ALLOW(init/INSTANCE_STATE): a pipe part normalises a bent straight into a corner, its facing to a cardinal, and its density and sort type to its kind
/obj/structure/disposalconstruct/Initialize(mapload)
	. = ..()
	// Disposals handle "bent"/"corner" strangely, handle this specially.
	if(ptype == DISPOSAL_PIPE_STRAIGHT && (dir in GLOB.cornerdirs))
		ptype = DISPOSAL_PIPE_CORNER
	switch(dir)
		if(NORTHWEST)
			dir = WEST
		if(NORTHEAST)
			dir = NORTH
		if(SOUTHWEST)
			dir = SOUTH
		if(SOUTHEAST)
			dir = EAST

	switch(ptype)
		if(DISPOSAL_PIPE_BIN, DISPOSAL_PIPE_OUTLET, DISPOSAL_PIPE_CHUTE)
			set_density(TRUE)
		if(DISPOSAL_PIPE_SORTER, DISPOSAL_PIPE_SORTER_FLIPPED)
			subtype = subtype_at_make

	if(flipped_at_make)
		do_a_flip()
	else
		update() // do_a_flip() calls update anyway, so, lazy way of catching unupdated pipe!

// update iconstate and dpdir due to dir and type
/obj/structure/disposalconstruct/proc/update()
	var/flip = turn(dir, 180)
	var/left = turn(dir, 90)
	var/right = turn(dir, -90)

	switch(ptype)
		if(DISPOSAL_PIPE_STRAIGHT)
			base_state = "pipe-s"
			dpdir = dir | flip
		if(DISPOSAL_PIPE_CORNER)
			base_state = "pipe-c"
			dpdir = dir | right
		if(DISPOSAL_PIPE_JUNCTION)
			base_state = "pipe-j1"
			dpdir = dir | right | flip
		if(DISPOSAL_PIPE_JUNCTION_FLIPPED)
			base_state = "pipe-j2"
			dpdir = dir | left | flip
		if(DISPOSAL_PIPE_JUNCTION_Y)
			base_state = "pipe-y"
			dpdir = dir | left | right
		if(DISPOSAL_PIPE_TRUNK)
			base_state = "pipe-t"
			dpdir = dir
		// disposal bin has only one dir, thus we don't need to care about setting it
		if(DISPOSAL_PIPE_BIN)
			if(anchored)
				base_state = "disposal"
			else
				base_state = "condisposal"
		if(DISPOSAL_PIPE_OUTLET)
			base_state = "outlet"
			dpdir = dir
		if(DISPOSAL_PIPE_CHUTE)
			base_state = "intake"
			dpdir = dir
		if(DISPOSAL_PIPE_SORTER)
			base_state = "pipe-j1s"
			dpdir = dir | right | flip
		if(DISPOSAL_PIPE_SORTER_FLIPPED)
			base_state = "pipe-j2s"
			dpdir = dir | left | flip
		if(DISPOSAL_PIPE_UPWARD)
			base_state = "pipe-u"
			dpdir = dir
		if(DISPOSAL_PIPE_DOWNWARD)
			base_state = "pipe-d"
			dpdir = dir
		if(DISPOSAL_PIPE_TAGGER)
			base_state = "pipe-tagger"
			dpdir = dir | flip
		if(DISPOSAL_PIPE_TAGGER_PARTIAL)
			base_state = "pipe-tagger-partial"
			dpdir = dir | flip

	if(!(ptype in list(DISPOSAL_PIPE_BIN, DISPOSAL_PIPE_OUTLET, DISPOSAL_PIPE_CHUTE, DISPOSAL_PIPE_UPWARD, DISPOSAL_PIPE_DOWNWARD, DISPOSAL_PIPE_TAGGER, DISPOSAL_PIPE_TAGGER_PARTIAL)))
		set_icon_state("con[base_state]")
	else
		set_icon_state(base_state)

	if(invisibility)				// if invisible, fade icon
		set_alpha(128)
	else
		set_alpha(255)
		//otherwise burying half-finished pipes under floors causes them to half-fade

// hide called by levelupdate if turf intact status changes
// change visibility status and force update of icon
/obj/structure/disposalconstruct/hide(intact)
	hide_under_floor(src, intact && level == 1)	// hide if floor is intact
	update()

/// Old Flip Pipe verb.
/obj/structure/disposalconstruct/proc/disposalconstruct_verb_flip(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat)
		return OP_DECLINE

	do_a_flip()
	return OP_OK

/obj/structure/disposalconstruct/proc/do_a_flip()
	switch(ptype)
		if(DISPOSAL_PIPE_JUNCTION)
			set_ptype(DISPOSAL_PIPE_JUNCTION_FLIPPED)
		if(DISPOSAL_PIPE_JUNCTION_FLIPPED)
			set_ptype(DISPOSAL_PIPE_JUNCTION)
		if(DISPOSAL_PIPE_SORTER)
			set_ptype(DISPOSAL_PIPE_SORTER_FLIPPED)
		if(DISPOSAL_PIPE_SORTER_FLIPPED)
			set_ptype(DISPOSAL_PIPE_SORTER)

	update()

// returns the type path of disposalpipe corresponding to this item dtype
/obj/structure/disposalconstruct/proc/dpipetype()
	switch(ptype)
		if(DISPOSAL_PIPE_STRAIGHT,DISPOSAL_PIPE_CORNER)
			return /obj/structure/disposalpipe/segment
		if(DISPOSAL_PIPE_JUNCTION,DISPOSAL_PIPE_JUNCTION_FLIPPED,DISPOSAL_PIPE_JUNCTION_Y)
			return /obj/structure/disposalpipe/junction
		if(DISPOSAL_PIPE_TRUNK)
			return /obj/structure/disposalpipe/trunk
		if(DISPOSAL_PIPE_BIN)
			return /obj/machinery/disposal
		if(DISPOSAL_PIPE_OUTLET)
			return /obj/structure/disposaloutlet
		if(DISPOSAL_PIPE_CHUTE)
			return /obj/machinery/disposal/deliveryChute
		if(DISPOSAL_PIPE_SORTER)
			switch(subtype)
				if(DISPOSAL_SORT_NORMAL)
					return /obj/structure/disposalpipe/sortjunction
				if(DISPOSAL_SORT_WILDCARD)
					return /obj/structure/disposalpipe/sortjunction/wildcard
				if(DISPOSAL_SORT_UNTAGGED)
					return /obj/structure/disposalpipe/sortjunction/untagged
				if(DISPOSAL_SORT_BODIES)
					return /obj/structure/disposalpipe/sortjunction/bodies
		if(DISPOSAL_PIPE_SORTER_FLIPPED)
			switch(subtype)
				if(DISPOSAL_SORT_NORMAL)
					return /obj/structure/disposalpipe/sortjunction/flipped
				if(DISPOSAL_SORT_WILDCARD)
					return /obj/structure/disposalpipe/sortjunction/wildcard/flipped
				if(DISPOSAL_SORT_UNTAGGED)
					return /obj/structure/disposalpipe/sortjunction/untagged/flipped
				if(DISPOSAL_SORT_BODIES)
					return /obj/structure/disposalpipe/sortjunction/bodies/flipped
		if(DISPOSAL_PIPE_UPWARD)
			return /obj/structure/disposalpipe/up
		if(DISPOSAL_PIPE_DOWNWARD)
			return /obj/structure/disposalpipe/down
		if(DISPOSAL_PIPE_TAGGER)
			return /obj/structure/disposalpipe/tagger
		if(DISPOSAL_PIPE_TAGGER_PARTIAL)
			return /obj/structure/disposalpipe/tagger/partial
	return

// attackby item
// wrench: (un)anchor
// weldingtool: convert to real pipe
/obj/structure/disposalconstruct/proc/construction_name()
	var/nicetype = "pipe"
	switch(ptype)
		if(DISPOSAL_PIPE_BIN)
			nicetype = "disposal bin"
		if(DISPOSAL_PIPE_OUTLET)
			nicetype = "disposal outlet"
		if(DISPOSAL_PIPE_CHUTE)
			nicetype = "delivery chute"
		if(DISPOSAL_PIPE_SORTER, DISPOSAL_PIPE_SORTER_FLIPPED)
			switch(subtype)
				if(DISPOSAL_SORT_NORMAL)
					nicetype = "sorting pipe"
				if(DISPOSAL_SORT_WILDCARD)
					nicetype = "wildcard sorting pipe"
				if(DISPOSAL_SORT_UNTAGGED)
					nicetype = "untagged sorting pipe"
				if(DISPOSAL_SORT_BODIES)
					nicetype = "body recovery sorting pipe"
		if(DISPOSAL_PIPE_TAGGER)
			nicetype = "tagging pipe"
		if(DISPOSAL_PIPE_TAGGER_PARTIAL)
			nicetype = "partial tagging pipe"
	return nicetype

/obj/structure/disposalconstruct/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/nicetype = construction_name()
	var/ispipe = is_pipe()
	add_fingerprint(user)
	var/turf/T = src.loc
	if(!T.is_plating())
		to_chat(user, "You can only attach the [nicetype] if the floor plating is removed.")
		return OP_OK

	var/obj/structure/disposalpipe/CP = locate_on(T, /obj/structure/disposalpipe)

	if(anchored)
		set_anchored(FALSE)
		if(ispipe)
			set_level(2)
			set_density(FALSE)
		else
			set_density(TRUE)
		to_chat(user, "You detach the [nicetype] from the underfloor.")
	else
		if(!ispipe)
			if(!istype(CP, /obj/structure/disposalpipe/trunk))
				to_chat(user, "The [nicetype] requires a trunk underneath it in order to work.")
				return OP_OK
		else if(CP)
			update()
			var/pdir = CP.dpdir
			if(istype(CP, /obj/structure/disposalpipe/broken))
				pdir = CP.dir
			if(pdir & dpdir)
				to_chat(user, "There is already a [nicetype] at that location.")
				return OP_OK

		set_anchored(TRUE)
		if(ispipe)
			set_level(1)
			set_density(FALSE)
		else
			set_density(TRUE)
		to_chat(user, "You attach the [nicetype] to the underfloor.")
	playsound(src, sounds_of(I).use, 100, 1)
	update()
	return OP_OK

/// A segment is welded only on bare plating, and only once it is fastened to it.
/obj/structure/disposalconstruct/proc/weld_refusal(datum/act/op/A)
	var/turf/T = read_once(loc)
	if(!istype(T) || !read_once(T.is_plating()))
		return "you can only attach the [read_once(construction_name())] if the floor plating is removed"
	if(!read_once(anchored))
		return "you need to attach it to the plating first"

/obj/structure/disposalconstruct/proc/weld_started(datum/act/op/A)
	add_fingerprint(A.actor)
	playsound(src, sounds_of(A.held).use, 100, TRUE)

/obj/structure/disposalconstruct/proc/weld_begins(datum/act/op/A)
	return msg_text("Welding the [construction_name()] in place.")

/obj/structure/disposalconstruct/proc/welder_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	var/nicetype = construction_name()
	var/ispipe = is_pipe()
	to_chat(user, "The [nicetype] has been welded in place!")
	update()
	if(ispipe)
		var/pipetype = dpipetype()
		var/obj/structure/disposalpipe/P = new pipetype(src.loc)
		transfer_fingerprints_to(P)
		P.set_base_icon_state(base_state)
		P.set_dir(dir)
		P.set_dpdir(dpdir)
		if(ptype == DISPOSAL_PIPE_SORTER || ptype == DISPOSAL_PIPE_SORTER_FLIPPED)
			var/obj/structure/disposalpipe/sortjunction/SortP = P
			SortP.sortType = sortType
			SortP.updatedir()
			SortP.updatedesc()
			SortP.updatename()
	else if(ptype == DISPOSAL_PIPE_BIN)
		var/obj/machinery/disposal/P = new(src.loc)
		transfer_fingerprints_to(P)
		P.set_mode(0)
	else if(ptype == DISPOSAL_PIPE_OUTLET)
		var/obj/structure/disposaloutlet/P = new(src.loc)
		transfer_fingerprints_to(P)
		P.set_dir(dir)
	else if(ptype == DISPOSAL_PIPE_CHUTE)
		var/obj/machinery/disposal/deliveryChute/P = new(src.loc)
		transfer_fingerprints_to(P)
		P.set_dir(dir)
	destroyed(src, user, "deconstructed")
	return OP_OK

/obj/structure/disposalconstruct/hides_under_flooring()
	if(anchored)
		return 1
	else
		return 0

// Helper procs for RCD
/obj/structure/disposalconstruct/proc/is_pipe()
	return (ptype != DISPOSAL_PIPE_BIN && ptype != DISPOSAL_PIPE_OUTLET && ptype != DISPOSAL_PIPE_CHUTE)

//helper proc that makes sure you can place the construct (i.e no dense objects stacking)
/obj/structure/disposalconstruct/proc/can_place()
	if(is_pipe())
		return TRUE

	for(var/obj/structure/disposalconstruct/DC in get_turf(src))
		if(DC == src)
			continue

		if(!DC.is_pipe()) //there's already a chute/outlet/bin there
			return FALSE

	return TRUE
