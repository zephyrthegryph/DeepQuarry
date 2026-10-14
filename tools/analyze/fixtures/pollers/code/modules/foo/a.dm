/obj/machinery/foo
/obj/machinery/foo/process()
/obj/machinery/foo/proc/process()
/obj/machinery/foo/process ()
/obj/machinery/foo/processing()
/obj/machinery/foo/process_extra()
/mob/living/simple_animal/hostile/process()
/datum/process()
/process()
/obj/foo
	process()
	proc/process()
	 process()
		process()
	process ()
	processing()
	var/x = 1
	process()

/obj/bar // a trailing comment keeps the type block open
	process()
/obj/baz
	var/z = 1

	process()
/proc/foo()
	process()
var/y
/obj/after_var
	process() // ALLOW(pollers): the legacy pump has no pipeline yet
	// ALLOW(pollers): the legacy pump has no pipeline yet
	process()
	// ALLOW(pollers): the legacy pump has no pipeline yet
	proc/process()
	process() // ALLOW(pollers)
	process() // ALLOW(other): a reason for some other lint entirely
	process() // ALLOW(other, pollers): a reason that names two lints at once
	x = 1 // ALLOW(pollers): not a comment-only line so it keeps nothing below
	process()
	/* ALLOW(pollers): block form of the annotation */ process()
	// process()
	process() // process()
/obj/starts
	START_PROCESSING(SSobj, src)
	START_MACHINE_PROCESSING(src)
	START_PROCESSING (SSobj, src)
	MY_START_PROCESSING(SSobj, src)
	x.START_PROCESSING(SSobj, src)
	/START_PROCESSING(x)
	#define START_PROCESSING(x) foo
	# define START_PROCESSING(x) foo
	 #define X START_PROCESSING(a)
	#undef START_PROCESSING(
	#if defined(START_PROCESSING(
	var/s = "START_PROCESSING("
	// START_PROCESSING(SSobj, src)
	START_PROCESSING(SSobj, src) // a trailing comment
	START_PROCESSING(a) START_PROCESSING(b)
	var/t = "a // not a comment" START_PROCESSING(c)
	var/u = "a \" // still a string" START_PROCESSING(d)
	START_PROCESSING(SSobj, src) // ALLOW(pollers): the legacy pump has no pipeline yet
	// ALLOW(pollers): the legacy pump has no pipeline yet
	START_PROCESSING(SSobj, src)
	START_PROCESSING(x) // ALLOW(pollers)
	START_PROCESSING(x) // ALLOW(other): a reason for some other lint entirely
	/* ALLOW(pollers): block form of the annotation */ START_PROCESSING(x)
/obj/both
	process() START_PROCESSING(SSobj, src)
	process() START_PROCESSING(SSobj, src) // ALLOW(pollers): one answer covers both on the line
