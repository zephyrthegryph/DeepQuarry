// Comments, strings, #define lines, ALLOW annotations, multi-line constructs.
/obj/thing/proc/comments_and_strings()
	// spawn(1) in a comment
	/* spawn(1) in a block comment */
	var/a = "spawn(1) in a string"
	var/b = {"spawn(1)
	sleep(1) in a multi-line string"}
	var/c = 'spawn(1).dmi'
	var/d = "x [spawn(1)] y"
	spawn(0) // trailing comment with spawn(1) and sleep(1)
	to_chat(usr, "sleep(1)") ; sleep(2)

#define SPAWN_MACRO spawn(1)
	#define INDENTED_MACRO spawn(1)
#define MULTI_MACRO(x) \
	spawn(1) \
	sleep(2)
#undef SPAWN_MACRO
#if defined(spawn(1))
#endif
#define BLOCK_MACRO(x) /* ALLOW(scheduler): the fixture keeps this macro body */ spawn(1) \
	sleep(1)

/obj/thing/proc/allow_cases()
	spawn(0) // ALLOW(scheduler): the fixture keeps this spawn on purpose
	// ALLOW(scheduler): the comment line above keeps the next sleep
	sleep(1)
	spawn(0) // ALLOW(scheduler)
	// ALLOW(scheduler)
	sleep(1)
	spawn(0) // ALLOW(lifecycle): a different lint's annotation keeps nothing here
	spawn(0) // ALLOW(cache, scheduler): both names, one reason
	spawn(1) spawn(2) // ALLOW(scheduler): one annotation keeps every match on the line
	spawn(1) sleep(2) INVOKE_ASYNC(src) // ALLOW(scheduler): and every rule
	/* ALLOW(scheduler): the block form keeps its own line */ spawn(1)
	spawn(1) /* ALLOW(scheduler): the block form after the code */
	// ALLOW(scheduler): above a blank line keeps nothing next to it

	sleep(1)
	var/x = 1 // ALLOW(scheduler): an annotation on a line with no site is unused
	// ALLOW(scheduler): two comment lines above
	// a second comment line
	spawn(0)
	do_after(usr, 5) // ALLOW (scheduler): a space before the paren is not an annotation
	do_after(usr, 5) //ALLOW(scheduler): no space after the slashes is fine
	do_after(usr, 5) //// ALLOW(scheduler): extra slashes are fine
	do_after(usr, 5) // allow(scheduler): lower case is not an annotation
	do_after(usr, 5) // ALLOW( scheduler ): spaces inside the parens are fine
	do_after(usr, 5) // ALLOW(scheduler) : a space before the colon
	do_after(usr, 5) // ALLOW(scheduler):x

/obj/thing/proc/multi_line()
	spawn(
		0)
	var/a = alert(
		usr,
		"q")
	INVOKE_ASYNC(
		src, PROC_REF(multi_line))
	del(
		src)
