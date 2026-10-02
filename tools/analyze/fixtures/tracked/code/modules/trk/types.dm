// Declarations for the tracked-var lint fixture.
/obj/machinery/pump
	var/target_pressure = 100
	var/other = 1
	var/open_state = 0
	var/open = 0
	var/bridged_value = 0
	var/tmp/counter = 0
TRACKED(/obj/machinery/pump, target_pressure)
TRACKED(/obj/machinery/pump, open_state, CHANNEL_X)
	TRACKED(/obj/machinery/pump, open) // an indented declaration with a trailing comment
TRACKED_BRIDGED(/obj/machinery/pump, bridged_value, KEY)
TRACKED(/obj/machinery/pump, counter)

/obj/machinery/pump/bigger
	target_pressure = 200
	var/extra = 0

/obj/machinery/valve
	var/is_open = FALSE
	var/flow = 0
SETTER(/obj/machinery/valve, is_open)
SETTER( /obj/machinery/valve , flow )

// TRACKED(/obj/machinery/pump, commented_out)
#define TRACKED(T, V, C) /datum/tracked_define
	#define SETTER(T, V) /datum/setter_define
/*
TRACKED(/obj/machinery/pump, in_block_comment)
*/
var/doc = {"
TRACKED(/obj/quirk, quirk_var)
SETTER(/obj/quirk, quirk_setter_var)
"}
TRACKED(/obj/machinery/pump)
TRACKED(/obj/machinery/pump, )
TRACKED /obj/machinery/pump, nospace_var
TRACKED(obj/machinery/pump, relative_var)
TRACKED(/obj/trailing_slash/, slashed_var)

/obj/gadget
	var/total = 0
	var/level = 0
	var/other_total = 0

/obj/gadget/derived()
	. = ..()
	. += derive(nameof(total), nameof(level))
	. += derive(nameof(/obj/gadget::other_total), 3)
	. += derive( nameof( spaced_total ) )

/obj/gadget/sub/proc/derived()
	. += derive(nameof(sub_total))

/obj/gadget/not_derived()
	. += derive(nameof(ignored_total))

/obj/quirk
	var/quirk_var = 0
	var/quirk_setter_var = 0

/obj/other_thing
	var/target_pressure = 0
