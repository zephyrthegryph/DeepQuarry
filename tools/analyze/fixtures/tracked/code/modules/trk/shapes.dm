// #define lines, multi-line shapes, odd procs, drift and unicode for the tracked-var lint fixture.
#define WRITE_PRESSURE(x) target_pressure = x
	#define INDENTED_WRITE(x) target_pressure = x

/obj/machinery/pump/proc/with_macros()
	#define LOCAL_MACRO target_pressure = 1
	# target_pressure = 2
	target_pressure = 3
#define IN_PROC_MACRO target_pressure = 4
	target_pressure = 5

/obj/machinery/pump/proc/multi_line()
	target_pressure = (
		5)
	target_pressure = {"a
	b"}
	var/s = {"
	target_pressure = 5
	"}
	target_pressure += list(
		1,
		2)

/obj/machinery/pump/proc/one_liner() target_pressure = 5

/obj/machinery/pump/proc/comment_header(a) // target_pressure = 1
	target_pressure = 2 // trailing
	open = 3 /* c */

/obj/machinery/pump/proc/split_header(a,
	b)
	target_pressure = 2

/obj/machinery/pump/proc
	target_pressure = 2

/obj/machinery/pump
	target_pressure = 2
	open_state = 3

/obj/machinery/pump/proc/blank_lines()

	target_pressure = 1

	open = 2
	// comment only

	target_pressure = 3

/obj/machinery/pump/proc/Initialize()
	target_pressure = 1
	return ..()

/obj/machinery/pump/New()
	target_pressure = 1

/obj/machinery/pump/proc/drift()
	var/x = 'a
	target_pressure = 1
	var/y = b'
	target_pressure = 2
	target_pressure = 3 // ALLOW(tracked): drift moves which raw line the annotation is read from
	open = 4

/obj/machinery/pump/proc/unicode(P)
	target_pressure = "héllo ✓" // ünï
	open = "日本語" // 😀
	var/s = "日本語 [target_pressure]"
	var/obj/machinery/pump/U = P
	U.target_pressure = "✓" // ✓
	U.open_state = 1 // ALLOW(tracked): the fixture keeps this unicode write on purpose
