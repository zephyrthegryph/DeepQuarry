// Examine lines (doc/rewrite/dx_conventions.md §2): /atom/examine() shows the name line, the
// description and the damage band, then examine_lines(). The base collects every capability's
// examine() in declaration order; bespoke text is a plain override:
//
//	/obj/machinery/iv_drip/examine_lines(mob/user)
//		. = ..()
//		if(get_dist(user, src) <= 2)
//			. += "The IV drip is [mode ? "injecting" : "taking blood"]."

/// The state lines after the description. Override with `. = ..()` then `. += "..."`.
/atom/proc/examine_lines(mob/user)
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	. = caps_examine(src, user)
	. += examine_collect(src, user)
