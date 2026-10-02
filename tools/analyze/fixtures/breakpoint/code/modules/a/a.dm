/obj/machinery/foo/proc/set_broken()
	stat |= BROKEN
/obj/machinery/foo/set_broken()
	return
/obj/machinery/foo/atom_break()
	. = ..()
/obj/machinery/foo/bar/atom_break()
	..()
	update_icon()
/obj/machinery/foo/baz/atom_break(damage_flag)
	. = ..()
	explode()
/obj/machinery/foo/atom_fix()
	stat &= ~BROKEN
	src.update_icon()
	return .
/obj/machinery/foo/qux/atom_fix()
	if(!.)
		return
	if(!(stat & BROKEN))
		return
	set_broken()
/obj/machinery/foo/atom_fix()
	// nothing but a comment
/obj/machinery/foo/empty/atom_break()

/obj/machinery/foo/gap/atom_break()

	. = ..()

	update_icon()
/obj/machinery/foo/spaces/atom_break()
    ..()
    src.stat ^= BROKEN
/obj/machinery/foo/verb/atom_fix()
	..()
/obj/machinery/foo/proc/atom_break(x)
	..() // trailing
	"just a string"
/atom/proc/atom_break()
	..()
/atom/atom_fix()
	..()
/obj/machinery/atom_break()
	..()
/obj/machinery/proc/atom_fix()
	..()
/obj/machinery/foo/atom_break ()
	..()
	../*c*/()
/obj/machinery/foo/set_broken_not()
	..()
/obj/machinery/foo/atom_break_x()
	..()
/obj/machinery/foo/atom_break()
	.  =  ..( a, b )
	(stat & BROKEN)
	if( ! (stat&BROKEN) )
global/proc/atom_break()
	..()
	return .
