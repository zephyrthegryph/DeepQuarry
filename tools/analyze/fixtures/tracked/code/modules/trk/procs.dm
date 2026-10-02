// Writes for the tracked-var lint fixture.
/obj/machinery/pump/proc/bad_direct()
	target_pressure = 5
	src.target_pressure += 1
	target_pressure++
	--target_pressure
	target_pressure--
	++target_pressure
	target_pressure -= 1
	target_pressure *= 2
	target_pressure /= 2
	target_pressure |= 4
	target_pressure &= 4
	target_pressure ^= 4
	target_pressure <<= 1
	target_pressure >>= 1
	target_pressure=5
	target_pressure   =   5
	if(target_pressure = 3)
		return
	++ target_pressure
	-- target_pressure
	src.target_pressure++
	++src.target_pressure
	open_state = 1
	open = 1
	bridged_value = 2
	counter = 0

/obj/machinery/pump/proc/good_read()
	if(target_pressure == 5)
		other = target_pressure
	var/x = target_pressure + 1
	var/y = target_pressure
	if(target_pressure != 5 && target_pressure <= 3 && target_pressure >= 2)
		return
	set_target_pressure(7)
	other = 3
	other += 2
	open_state_extra = 1
	my_target_pressure = 1
	x.target_pressure_other = 1
	target_pressures = 1

/obj/machinery/pump/proc/shadowed()
	var/target_pressure = 3
	target_pressure -= 1
	src.target_pressure = 4
	var/obj/thing/open_state
	open_state = 1
	var/tmp/open
	open++

/obj/machinery/pump/proc/arg_shadow(target_pressure, obj/thing/open_state, list/open = list())
	target_pressure = 2
	open_state = 2
	open = 2
	bridged_value = 3

/obj/machinery/pump/proc/prefixed_names()
	var/cached_target_pressure = 1
	cached_target_pressure = 2
	xtarget_pressure = 3
	target_pressure_x = 4

/obj/machinery/pump/proc/allowed_write()
	target_pressure = 1 // ALLOW(tracked): fixture keep
	// ALLOW(tracked): the comment line above keeps the next write
	target_pressure = 2
	target_pressure = 3 // ALLOW(tracked)
	target_pressure = 4 // ALLOW(other): not the tracked lint
	target_pressure = 5 // ALLOW(cache, tracked): both names
	target_pressure++ target_pressure++ // ALLOW(tracked): one annotation keeps the whole line
	open = 1 // ALLOW(tracked): kept
	open = 2

/obj/machinery/pump/bigger/proc/subtype_write()
	target_pressure = 9
	src.target_pressure = 9
	extra = 1

/obj/machinery/pump/bigger/set_target_pressure(value)
	target_pressure = value * 2
	src.target_pressure = value
	open = 1
	return TRUE

/obj/machinery/pump/proc/set_open(value)
	open = value
	open_state = value
	target_pressure = value
	return TRUE

/obj/machinery/pump/verb/set_open_state(value)
	open_state = value
	open = value

/obj/other_thing/proc/unrelated()
	target_pressure = 4
	open = 1

/obj/other_thing/set_target_pressure(value)
	target_pressure = value

/proc/set_target_pressure(value)
	target_pressure = value

/proc/external(obj/machinery/pump/P, obj/other_thing/Q, list/L, R, var/obj/machinery/pump/bigger/S as obj)
	P.target_pressure = 3
	Q.target_pressure = 3
	L.target_pressure = 3
	R.target_pressure = 3
	S.target_pressure = 3
	P.open_state += 1
	P?.open = 1
	P.target_pressure++
	++P.target_pressure
	--P.target_pressure
	P.target_pressure == 3
	P.target_pressure != 3
	var/obj/machinery/pump/bigger/B = P
	B.target_pressure -= 2
	B.other = 2
	unknown.target_pressure = 1
	src.target_pressure = 1
	P.sub.target_pressure = 1
	P.a.b.open = 1
	var/V
	V.target_pressure = 1
	var/obj/other_thing/W = Q
	W.target_pressure = 1
	P.target_pressure = (
		5)
	P.target_pressure = 1 // ALLOW(tracked): the fixture keeps this dotted write
	// ALLOW(tracked): the comment line above keeps the next dotted write
	P.target_pressure = 2
	// P.target_pressure = 8 in a comment
	var/s = "P.target_pressure = 8"
	var/t = "x [P.target_pressure = 8] y"
	/* P.target_pressure = 8 */
	var/u = 'P.target_pressure = 8'

/proc/external_valve(obj/machinery/valve/V, obj/machinery/valve/W)
	V.is_open = FALSE
	W.flow = 3
	if(V.is_open == TRUE)
		return

/obj/machinery/valve/proc/set_is_open(value)
	is_open = value
	flow = value
	update_pipes()

/obj/machinery/valve/proc/set_flow(value)
	flow = value
	is_open = value

/obj/machinery/valve/proc/bad_is_open()
	is_open = TRUE
	src.flow = 1

/obj/machinery/valve/proc/set_(value)
	is_open = value

/obj/machinery/valve/proc/set_missing(value)
	is_open = value

/obj/gadget/proc/oops()
	total = 5
	level = 1
	other_total = 2
	spaced_total = 3
	sub_total = 4
	ignored_total = 5

/obj/gadget/sub/proc/oops_sub()
	sub_total = 4
	total = 1

/obj/quirk/proc/quirk_writes()
	quirk_var = 1
	quirk_setter_var = 2

/obj/quirk/proc/set_quirk_setter_var(value)
	quirk_setter_var = value
	quirk_var = value

/obj/thing/proc/untracked_type()
	target_pressure = 1
	open = 1
	commented_out = 1
	in_block_comment = 1
	relative_var = 1
	slashed_var = 1
	nospace_var = 1
