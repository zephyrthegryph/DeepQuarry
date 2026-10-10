// A lamp whose declaration names handlers: clean ones and one seeded violation per rule.
/obj/machinery/lamp
	name = "lamp"
	var/lit = FALSE
	var/power = 0
	var/range = 3
	var/obj/item/cell/cell
	var/list/queue
	var/saved

TRACKED(/obj/machinery/lamp, lit)
TRACKED(/obj/machinery/lamp, power)

CAPABILITIES(/obj/machinery/lamp,
	when(PROC_REF(is_lit)),
	when(PROC_REF(actor_is_near)),
	needs(PROC_REF(has_power), because = PROC_REF(no_power_reason)),
	needs(PROC_REF(wrong_dt)),
	needs(req_bool(PROC_REF(text_return))),
	needs(req_bool(PROC_REF(bool_returns))),
	when(PROC_REF(sets_stuff)),
	when(PROC_REF(follows_writer)),
	when(PROC_REF(two_params)),
	when(PROC_REF(no_params)),
	when(PROC_REF(untyped)),
	when(PROC_REF(ghost_proc)),
	when(TYPE_PROC_REF(/obj/machinery/lamp, is_lit)),
	contributes(STAT_RANGE, PROC_REF(lit_range)),
	then(PROC_REF(toggle)),
	then(PROC_REF(toggle_and_say)),
	every(5 SECONDS, PROC_REF(tick_work), when = PROC_REF(is_lit)))

/obj/machinery/lamp/proc/is_lit(datum/act/eval/A)
	return lit

/// A condition runs with an eval context: no actor.
/obj/machinery/lamp/proc/actor_is_near(datum/act/eval/A)
	return A.actor != null

/obj/machinery/lamp/proc/has_power(datum/act/op/A)
	return power > 0 && A.actor != null

/obj/machinery/lamp/proc/no_power_reason(datum/act/op/A)
	return "no power"

/// A requirement runs in the op context: no dt.
/obj/machinery/lamp/proc/wrong_dt(datum/act/op/A)
	return A.dt > 0

/obj/machinery/lamp/proc/text_return(datum/act/op/A)
	if(power > 5)
		return "too much power"
	if(power < 0)
		return
	return TRUE

/obj/machinery/lamp/proc/bool_returns(datum/act/op/A)
	if(power > 5)
		return FALSE
	if(!lit)
		return !!cell
	return power > 0 || lit

/obj/machinery/lamp/proc/sets_stuff(datum/act/eval/A)
	set_lit(TRUE)
	lit = FALSE
	to_chat(world, "lit")
	return lit

/obj/machinery/lamp/proc/follows_writer(datum/act/eval/A)
	return writes_power() > 0

/obj/machinery/lamp/proc/writes_power()
	power = 4
	return power

/obj/machinery/lamp/proc/two_params(datum/act/eval/A, extra)
	return lit

/obj/machinery/lamp/proc/no_params()
	return lit

/obj/machinery/lamp/proc/untyped(A)
	return lit

/obj/machinery/lamp/proc/lit_range(datum/act/eval/A)
	return lit ? range : 0

/// An effect may write.
/obj/machinery/lamp/proc/toggle(datum/act/op/A)
	set_lit(!lit)
	power = 1
	return TRUE

/obj/machinery/lamp/proc/toggle_and_say(datum/act/op/A)
	to_chat(A.actor, "click")
	return TRUE

/obj/machinery/lamp/proc/tick_work(datum/act/timer/A)
	return A.dt

// ---- ACT_TRY pairing ----

/obj/machinery/lamp/proc/fall_clean(turf/T)
	var/datum/act/fall/F = ACT_TRY(src, fall, T)
	if(!F)
		return
	if(F == ACT_PASS)
		return
	act_done(F)

/obj/machinery/lamp/proc/fall_branches(turf/T, cancel)
	var/datum/act/fall/F = ACT_TRY(src, fall, T)
	if(isnull(F))
		return FALSE
	if(cancel)
		act_cancel(F)
		return FALSE
	act_done(F)
	return TRUE

/obj/machinery/lamp/proc/fall_return_done(turf/T)
	var/datum/act/fall/F = ACT_TRY(src, fall, T)
	if(!F)
		return FALSE
	return act_done(F)

/obj/machinery/lamp/proc/fall_leaks(turf/T, quick)
	var/datum/act/fall/F = ACT_TRY(src, fall, T)
	if(!F)
		return
	if(quick)
		return
	act_done(F)

/obj/machinery/lamp/proc/fall_never_closed(turf/T)
	var/datum/act/fall/F = ACT_TRY(src, fall, T)
	if(!F)
		return
	lit = FALSE

/obj/machinery/lamp/proc/fall_dropped(turf/T)
	ACT_TRY(src, fall, T)
	return TRUE

/obj/machinery/lamp/proc/fall_assigned_late(turf/T)
	var/datum/act/hit/H
	H = ACT_TRY(src, hit)
	if(!H)
		return
	for(var/i in 1 to 3)
		power += i
	act_cancel(H)

/obj/machinery/lamp/proc/fall_loop_leak(turf/T, list/many)
	var/datum/act/fall/F = ACT_TRY(src, fall, T)
	if(!F)
		return
	for(var/x in many)
		if(x)
			act_done(F)

// ACT_TRY of a declared ACTION expands to act_<name>(): the pairing check follows the generated call too.
ACTION(spark, atom/target)

/obj/machinery/lamp/proc/spark_clean(turf/T)
	var/datum/act/spark/S = act_spark(src, T)
	if(!S)
		return
	act_done(S)

/obj/machinery/lamp/proc/spark_leaks(turf/T, quick)
	var/datum/act/spark/S = act_spark(src, T)
	if(!S)
		return
	if(quick)
		return
	act_done(S)

// then() inside instead() runs in the action's context (its typed fields); inside on_notice() in the notice's (and its typed fields).
/datum/notice/sparked
	var/atom/target_thing

/obj/machinery/lamp_b

CAPABILITIES(/obj/machinery/lamp_b, 	extend(/datum/act/spark, instead(then(PROC_REF(takes_over)))), 	on_notice(/datum/notice/sparked, then(PROC_REF(heard_spark))))

/obj/machinery/lamp_b/proc/takes_over(datum/act/A)
	var/datum/act/spark/S = A
	return S.target

/obj/machinery/lamp_b/proc/heard_spark(datum/act/A)
	var/datum/notice/sparked/N = A
	return N.target_thing + A.dt
