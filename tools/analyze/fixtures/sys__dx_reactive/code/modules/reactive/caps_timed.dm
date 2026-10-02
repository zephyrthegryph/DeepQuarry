/obj/machinery/capper
	var/level = 1
	var/mode = 0
	var/obj/item/cell/battery

/obj/machinery/capper/capabilities()
	. = ..()
	. += cap_gauge(level = level)
	. += cap_slot(nameof(battery), /obj/item/cell)
	. += cap_x(src.mode)
	. += cap_y(src.get_thing())
	var/localvar = 3
	. += cap_z(localvar)
	. += cap_w(name)
	. += cap_v(x = 1)
	var/mode2 = mode
	. += cap_u(TYPE_PROC_REF(/obj/machinery/capper, mode))
	. += cap_t(GLOBAL_PROC_REF(level))
	. += cap_s(VERB_REF(level), TYPE_VERB_REF(/obj/x, mode))
	. += cap_r(mode(1))
	. += cap_q(mode == 1)
	. += cap_p("level [mode]")
	. += cap_o(cap_slot(nameof(mode)), level)
	. += cap_n(thing.level, A.mode)
	// level and mode in a comment
	return .

/obj/machinery/capper/sub/capabilities()
	. = ..()
	. += cap_gauge(level = 3)
	. += cap_m(level)
	. += cap_l(layer)

/atom/capabilities()
	. = ..()
	. += cap_gauge(level = level)
	. += cap_k(name)

/obj/machinery/capper/proc/capabilities(extra)
	return level + extra

/obj/machinery/timer_thing
	var/boosted = FALSE
	var/other_flag = FALSE
	var/counter = 0

/obj/machinery/timer_thing/proc/start()
	timed_set(src, nameof(boosted), TRUE, for_time = 5 SECONDS)
	timed_set(src, "other_flag", TRUE, for_time = 5 SECONDS)
	timed_set(src, nameof(src.counter), 1, for_time = 5 SECONDS)
	timed_set(src, nameof(/obj/machinery/timer_thing::boosted), 1, 1)
	timed_set(src)
	timed_set(src, "[x]", 2)
	timed_set(src, nameof(a.b.c), 1, 1)

/obj/machinery/timer_thing/proc/bad()
	boosted = TRUE
	other_flag += 1
	++counter
	counter++
	src.boosted = FALSE
	src?.boosted = FALSE
	var/boosted = 1
	if(boosted == 2)
		return
	boosted |= 2
	boosted = timed_set(src, nameof(boosted), 1, 1)
	boosted = 7 // ALLOW(sys_dx_timed_write): fixture keeps this one
	// ALLOW(sys_dx_timed_write): fixture keeps the next one
	other_flag = 8

/obj/machinery/timer_thing/proc/set_boosted(value)
	boosted = value
	other_flag = value

/obj/machinery/timer_thing/proc/param(boosted)
	boosted = 2

/obj/item/unrelated/proc/poke(obj/machinery/timer_thing/T)
	boosted = 1
	T.boosted = 1
	T . other_flag = 3
	var/x = 2
	x = T.counter

/obj/machinery/proc/ancestor_poke()
	other_flag = 1

/obj/machinery/timer_thing/sub/proc/sub_poke()
	counter = 3
	counter == 4

/proc/global_poke()
	boosted = 1
