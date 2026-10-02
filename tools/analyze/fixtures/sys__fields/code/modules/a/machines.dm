/obj/machinery/widget
	var/obj/machinery/widget/partner
	var/mob/living/pilot
	var/obj/item/thing/held

/obj/machinery/proc/set_on(v)
	on = v

/obj/machinery/widget/proc/set_on(v)
	on = v

/obj/machinery/widget/proc/tick(mob/living/M, obj/machinery/other/O, obj/vehicle/V)
	if(stat & BROKEN)
		return
	if(stat)
		return
	stat |= X
	stat &= ~X
	stat = 0
	var/s = stat
	src.stat = 1
	M.stat = DEAD
	M.stat & X
	O.stat
	V.stat
	unknown.stat
	unknown.stat & BROKEN
	if(X & unknown.stat)
	if(X | unknown.stat)
	unknown.stat == 1
	unknown.stat |= 4
	unknown.stat ^= 4
	stat()
	stat ()
	unknown.stat(1)
	to_chat(M, "stat & BROKEN")
	// stat & BROKEN
	stat & X // ALLOW(sys_stat_bits): fixture keep on the line
	// ALLOW(sys_stat_bits): fixture keep from above
	stat & X
	partner.stat
	pilot.stat
	pilot.stat & 1
	held.stat & 1
	held.stat
	var/obj/machinery/widget/W = x
	W.stat
	var/mob/living/L = x
	L.stat
	L.stat & 1
	var/obj/item/I = x
	I.stat & 1
	I.stat
	I?.stat & 1
	W?.stat
	stat_add(BROKEN)
	stat_remove(NOPOWER)
	set_stat(BROKEN | NOPOWER)
	stat_add(OTHER)
	stat_add(BROKEN) // ALLOW(sys_stat_owned): fixture keep
	// ALLOW(sys_stat_owned): fixture keep above
	stat_add(NOPOWER)
	stat_add(BROKEN, "x")
	stat_add (NOPOWER)
	to_chat(M, "stat_add(BROKEN)")
	inoperable()
	if(inoperable(MAINT))
	is_operational()
	x.is_operational ()
	not_inoperable()
	operable()
	// inoperable()

/obj/machinery/widget/proc/shadow_param(stat, other)
	stat |= 1
	stat & 2
	unknown.stat & 3

/obj/machinery/widget/proc/shadow_var()
	stat = 1
	var/stat = 2
	stat = 3
	var/obj/machinery/thing/stat
	stat |= 4
	unknown.stat & 5

/obj/machinery/widget/proc/shadow_tmp()
	var/tmp/stat
	stat = 1

/obj/item/proc/not_machine()
	stat = 1
	stat & BROKEN
	src.stat = 2
	src.stat & 1
	O.stat
	other.stat & 1

/mob/living/proc/mob_proc()
	stat = 1
	src.stat = 2
	src.stat & 1
	M.stat
	var/obj/machinery/widget/W = x
	W.stat

/obj/vehicle/car/proc/drive()
	stat = 1
	src.stat
	if(stat & 2)

/obj/vehicle/car/proc/drive2(stat)
	stat = 1
	src.stat

/proc/global_proc()
	stat = 1
	src.stat

#define MACRO stat & BROKEN
/obj/machinery/widget/proc/after_define()
	stat = 1

junk_line
	stat = 1

/obj/machinery/widget/proc/field_writes(v)
	on = TRUE
	src.on = FALSE
	anchored = 1
	use_power |= 2
	use_power++
	noncore = 1
	state = 1
	locked = 1
	density = 1
	emagged = 1
	active = 1
	unknown.on = 1
	unknown.noncore = 1
	partner.on = 1
	pilot.on = 1
	held.state = 1
	held.locked = 1
	foo(on = 1)
	on = 1 // ALLOW(sys_field_write): fixture keep
	on == 1
	var/on_local = 1
	var/on = 2
	on = 3

/obj/machinery/special/proc/special_writes()
	emagged = 1
	on = 2

/obj/item/thing/proc/thing_writes()
	state = 1
	locked = 1
	on = 1
	density = 1

/obj/item/thing/proc/set_state(v)
	state = v

/obj/item/thing/proc/locked_add(v)
	locked |= v

/obj/item/thing/sub/proc/locked_add(v)
	locked |= v

/obj/vehicle/car/proc/car_writes()
	density = 0
	on = 1

/obj/testthing/proc/ut_declared_write()
	mode = 1
	on = 1

/mob/living/proc/mob_writes()
	active = 1
	on = 1

/obj/machinery/widget/Initialize(mapload)
	on = TRUE
	stat = 0
	return ..()
