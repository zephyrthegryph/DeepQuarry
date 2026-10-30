/obj/effect/step_trigger/teleporter/roguemine_loop/north/proc/set_loop_target()
	teleport_x = x
	set_teleport_z(z)

CAPABILITIES(/obj/effect/step_trigger/teleporter/roguemine_loop/north)
	setup(PROC_REF(set_loop_target))

/obj/effect/step_trigger/teleporter/roguemine_loop/south/proc/set_loop_target()
	teleport_x = x
	teleport_y = world.maxy - 16
	set_teleport_z(z)

CAPABILITIES(/obj/effect/step_trigger/teleporter/roguemine_loop/south)
	setup(PROC_REF(set_loop_target))

/obj/effect/step_trigger/teleporter/roguemine_loop/west/proc/set_loop_target()
	teleport_x = world.maxx - 16
	teleport_y = y
	set_teleport_z(z)

CAPABILITIES(/obj/effect/step_trigger/teleporter/roguemine_loop/west)
	setup(PROC_REF(set_loop_target))

/obj/effect/step_trigger/teleporter/roguemine_loop/east/proc/set_loop_target()
	teleport_y = y
	set_teleport_z(z)

CAPABILITIES(/obj/effect/step_trigger/teleporter/roguemine_loop/east)
	setup(PROC_REF(set_loop_target))

//Sure, I could probably do this with math. But I'm tired.
/*
 *		    S1      300
 *  -----------------------------------
 *  |015/285  135/285|166/285  285/285|
 *  |                |                |S
 *  |       A3       |       A4       |2
 *  |                |                |
 * 0|015/166  135/166|166/166  285/166|3
 * 0|---------------------------------|0
 * 0|015/135  135/135|166/135  285/135|0
 *  |                |                |
 * S|       A1       |       A2       |
 * 4|                |                |
 *  |015/015  135/015|166/015  285/015|
 *  -----------------------------------
*					000      S3
*/
/*
//////////// AREA 1
/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A1S1
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A1S2
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A1S3
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A1S4
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

//////////// AREA 2
/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A2S1
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A2S2
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A2S3
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A2S4
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

//////////// AREA 3
/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A3S1
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A3S2
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A3S3
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A3S4
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

//////////// AREA 4
/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A4S1
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A4S2
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A4S3
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =

/obj/effect/step_trigger/teleporter/random/rogue/fourbyfour/A4S4
	teleport_x =
	teleport_y =
	teleport_x_offset =
	teleport_y_offset =
*/

/obj/effect/step_trigger/teleporter/roguemine_loop/north
	teleport_y = 16

/obj/effect/step_trigger/teleporter/roguemine_loop/east
	teleport_x = 16

