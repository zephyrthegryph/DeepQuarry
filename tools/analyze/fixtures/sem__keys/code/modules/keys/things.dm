// A type whose declaration names ids and keys: some resolve, some are seeded typos.
/obj/machinery/thing
	name = "thing"

CAPABILITIES(/obj/machinery/thing,
	cover("hatch"),
	op("toggle", needs(PROC_REF(ok))),
	when(COVER_OPEN, contributes(STAT_DENSITY, FALSE)),
	contributes(STAT_DENSTY, TRUE),
	extend("cover.open"),
	extend("cover.opne"),
	without("toggle"),
	holds(SRC_AI_CONTROL, STAGE_DOOR_WIRED),
	holds(SRC_AI_CONTROLL, STAGE_DOOR_BOLTED),
	contributes(STAT_CLOCK_RATE, 2),
	when(COVER_REMOVED, then(PROC_REF(ok))),
	when(COVER_LOST, then(PROC_REF(ok))),
	// contributes(STAT_IN_A_COMMENT, 1),
	extend("[dynamic]"),
	shares_effects("cover.close"))

/obj/machinery/thing/proc/ok(datum/act/A)
	return TRUE

/obj/machinery/thing/proc/poke(mob/user)
	perform_op(user, src, "cover.open")
	perform_op(user, src, "cover.close")
	perform_op(user, src, "cover.opne")
	perform_op(user, src, "[user.name]")
	perform_op(user, src, "legacy.thing") // ALLOW(keys): a legacy op key kept until its capability converts
	perform_op(user, src, "construction.build:door_wired")
	configure("cover", open = TRUE)
	configure("lid", open = TRUE)
	hold(src, STAT_DENSITY, 1, source = "text")
	hold(src, STAT_DENSITY, 1, source = null)
	hold(src, STAT_DENSITY, 1, source = SRC_STATUS)
	hold_until(src, STAT_DENSITY, 1, 5 SECONDS)
	grant(src, CAP_COVER, source = "grant")
	release(src, STAT_DENSITY)
	// perform_op(user, src, "nope.nope")

/obj/machinery/thing/proc/define_proc()
	return null

/proc/grant(datum/target, what, source = "grant", duration)
	return TRUE
