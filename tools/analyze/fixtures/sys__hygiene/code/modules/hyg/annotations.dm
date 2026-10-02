/obj/machinery/thing/proc/a()
	qdel(src) // ALLOW(lifecycle): baseline when CI was wired
	qdel(src) // ALLOW(lifecycle): Convert or give a real reason
	qdel(src) // ALLOW(lifecycle): 15 mobs at boot
	qdel(src) // ALLOW(lifecycle): see audit
	qdel(src) // ALLOW(lifecycle): a real reason that is fine
	qdel(src) // ALLOW(lifecycle)
	qdel(src) // ALLOW(lifecycle):
	qdel(src) // ALLOW(lifecycle):    see AUDIT of things
	qdel(src) /* ALLOW(lifecycle): baseline when ci was wired */
	qdel(src) /* ALLOW(lifecycle): fine */ more code
	qdel(src) //// ALLOW ( lifecycle , cache ): see audit
	qdel(src) // ALLOW(lifecycle): mob: this is the machine's own sweep
	qdel(src) // ALLOW(lifecycle): obj: this is a machine so obj is fine
	qdel(src) // ALLOW(lifecycle): machine: matches
	qdel(src) // ALLOW(lifecycle): machines: matches with plural
	qdel(src) // ALLOW(lifecycle): item: the machine is not an item
	qdel(src) // ALLOW(lifecycle): turf: not a turf
	qdel(src) // ALLOW(lifecycle): area: not an area
	qdel(src) // ALLOW(lifecycle): objs: a machine is an obj
	qdel(src) // ALLOW(lifecycle): mobx: unknown kind prefix
	qdel(src) // ALLOW(lifecycle): the mob: later in the text is fine

/mob/living/proc/b()
	qdel(src) // ALLOW(lifecycle): mob: living mob
	qdel(src) // ALLOW(lifecycle): mobs: plural
	qdel(src) // ALLOW(lifecycle): obj: not an obj

/obj/item/thing/proc/c()
	qdel(src) // ALLOW(lifecycle): item: an item
	qdel(src) // ALLOW(lifecycle): obj: an item is an obj
	qdel(src) // ALLOW(lifecycle): machine: an item is not a machine

/turf/open/proc/d()
	qdel(src) // ALLOW(lifecycle): turf: a turf
	qdel(src) // ALLOW(lifecycle): area: not an area

/area/proc/e()
	qdel(src) // ALLOW(lifecycle): area: an area

/proc/free_proc()
	qdel(src) // ALLOW(lifecycle): mob: free procs have no type

/obj/machinery/thing/proc/f()
	// ALLOW(lifecycle): mob: comment-only line above
	qdel(src)
	// ALLOW(lifecycle): SEE AUDIT
	qdel(src)

#define SOMETHING(x) qdel(x) /* ALLOW(lifecycle): see audit */ \
	foo()

/obj/machinery/thing/verb/g()
	qdel(src) // ALLOW(lifecycle): mob: the verb of a machine
