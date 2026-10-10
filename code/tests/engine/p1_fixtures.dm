// The fixtures of the phase-1 close (doc/rewrite/final_api.html, section 19 "The E0 proofs"; the E2 gaps the close made good): a capability with an
// every(), conditions that break the purity guard, a wait on a tracked read, and a type whose own procs are named like part constructors.
// Test-only types, compiled under UNIT_TESTS only (code/modules/unit_tests/dq_p1_close_tests.dm drives them).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_DEF_SELF(p1/not_ready, "It is not ready.")
MSG_DEF_SELF(p1/unreachable_at_all, "It is out of reach.")

// ---- every() of a capability ----

/// Counts its runs on the holder: BEST(power) shows that a shadowed activation keeps its clock and skips its handler.
CAPABILITY_TYPE(p1_ticker, CAP_P1_TICKER, /datum/capability/p1_ticker, key = NONE, stacks = BEST(power), power = 1)

/datum/capability/p1_ticker

/datum/capability/p1_ticker/entries()
	return list(every(1 SECOND, then(CAP_PROC(tick))))

/datum/capability/p1_ticker/proc/tick(datum/act/timer/A)
	var/mob/living/simple_mob/e0_fixture/M = A.holder
	M.p1_ticks++
	M.p1_last_dt = A.dt
	M.p1_last_source = A.source

/mob/living/simple_mob/e0_fixture
	var/p1_ticks = 0
	var/p1_last_dt
	var/p1_last_source

// ---- the purity guard ----

/// Conditions and requirements that write, publish and message, one each, and one that does none of them.
/obj/e0_fixture/p1_impure
	name = "p1 impure"
	var/touched = FALSE
	var/locked = FALSE
	var/steady = TRUE
	var/runs = 0

TRACKED(/obj/e0_fixture/p1_impure, touched)
TRACKED(/obj/e0_fixture/p1_impure, locked)
TRACKED(/obj/e0_fixture/p1_impure, steady)

CAPABILITIES(/obj/e0_fixture/p1_impure)
	op("writes", hand(), when(PROC_REF(writes_in_condition)), then(PROC_REF(ran)))
	op("touches", menu(), needs(req_bool(PROC_REF(writes_in_requirement), because = MSG(p1/not_ready))), then(PROC_REF(ran)))
	op("clean", item(/obj/item/e2_key), when(PROC_REF(reads_only)), then(PROC_REF(ran)))

/obj/e0_fixture/p1_impure/proc/writes_in_condition(datum/act/A)
	set_touched(!touched) // ALLOW(handlers): a condition that writes, on purpose: the purity guard must report it
	return TRUE

/obj/e0_fixture/p1_impure/proc/writes_in_requirement(datum/act/A)
	set_locked(!locked) // ALLOW(handlers): a requirement that writes, on purpose: the purity guard must report it
	return TRUE

/obj/e0_fixture/p1_impure/proc/reads_only(datum/act/A)
	return steady

/obj/e0_fixture/p1_impure/proc/ran(datum/act/op/A)
	runs++
	return OP_OK

// ---- a wait that re-checks on a published read ----

/// The press waits five seconds and needs `ready` the whole time; clearing `ready` cancels it the moment the write publishes, with no time passing.
/obj/e0_fixture/p1_waiter
	name = "p1 waiter"
	var/ready = TRUE
	var/finished = 0

TRACKED(/obj/e0_fixture/p1_waiter, ready)

CAPABILITIES(/obj/e0_fixture/p1_waiter)
	op("press", hand(), needs(req_is(nameof(ready), because = MSG(p1/not_ready))), wait(5 SECONDS), then(PROC_REF(done)))

/obj/e0_fixture/p1_waiter/proc/done(datum/act/op/A)
	finished++
	return OP_OK

// ---- a type whose own procs are named like part constructors ----

/// A type with a proc named like each of these part constructors: its CAPABILITIES list must still build the engine's parts.
/obj/item/p1_telecube
	name = "p1 telecube"
	var/captured = 0

CAPABILITIES(/obj/item/p1_telecube)
	op("zap", hand(), cooldown(5 SECONDS), flash("p1"), says(MSG(p1/not_ready)), label("Zap"))
	op("stash", item(/obj/item/e2_key), put_in("p1_slot"), menu())

/obj/item/p1_telecube/proc/cooldown(...)
	captured++
	return null

/obj/item/p1_telecube/proc/flash(...)
	captured++
	return null

/obj/item/p1_telecube/proc/put_in(...)
	captured++
	return null

/obj/item/p1_telecube/proc/menu(...)
	captured++
	return null

/obj/item/p1_telecube/proc/says(...)
	captured++
	return null

/obj/item/p1_telecube/proc/label(...)
	captured++
	return null

#endif
