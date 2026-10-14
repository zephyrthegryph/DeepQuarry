// A1 framework forms (doc/rewrite/reactions.md, state_and_relations.md): the one timer's key/clock/with and
// after_left(), the legacy slot wrappers, guards, on_change(when =), grant() of verbs and capabilities, the
// OWN_PRIVATE_COPY relation, flyweight leak exemption and the converted dry galoshes / spontaneous vore.

/datum/a1_fx
	var/hits = 0
	var/last
	var/gate = FALSE
	var/refuse = FALSE
	var/seen_key
	var/list/datum/species/proto_species

/datum/a1_fx/proc/hit(value)
	hits++
	last = value

/datum/a1_fx/reactions()
	. = ..()
	. += on_change(list("a1_fact"), PROC_REF(on_fact), when = nameof(gate))
	. += before_op(GUARD_STUMBLED_INTO, PROC_REF(on_stumble))

/datum/a1_fx/proc/on_fact(list/keys)
	hits++

/datum/a1_fx/proc/on_stumble(datum/guard_ctx/ctx)
	seen_key = ctx.key
	return refuse ? "refused" : null

/// after(owner, delay, handler, key =, clock =, with =): named arguments, no varargs; after_left() reads a keyed timer.
/datum/unit_test/dq_a1_after_named/Run()
	var/datum/a1_fx/F = allocate(/datum/a1_fx)
	TEST_ASSERT(after(F, 5 SECONDS, TYPE_PROC_REF(/datum/a1_fx, hit), key = "k", clock = CLOCK_WORLD, with = list(7)), "scheduled")
	TEST_ASSERT(after_pending(F, "k"), "pending under its key")
	var/left = after_left(F, "k")
	TEST_ASSERT(left > 0 && left <= 5 SECONDS, "after_left() reads the remaining time ([left])")
	TEST_ASSERT_EQUAL(after_left(F, "nothing"), 0, "no timer: 0 left")
	// The legacy slot wrappers are the keyed timer.
	TEST_ASSERT(after_slot(F, "slot", 3 SECONDS, TYPE_PROC_REF(/datum/a1_fx, hit), 1), "after_slot schedules")
	TEST_ASSERT(after_pending(F, "slot"), "a slot is an after() key")
	TEST_ASSERT(after_pending(F, "slot"), "and reads back through the legacy name")
	TEST_ASSERT(after_left(F, "slot") > 0, "with its time left")
	TEST_ASSERT(cancel_after(F, "slot"), "and cancels by its key")
	TEST_ASSERT(!after_pending(F, "slot"), "gone")

/// guard(E, GUARD_X, ...): before_op on a guard key; null lets it proceed, a reason refuses; nothing runs unguarded.
/datum/unit_test/dq_a1_guard/Run()
	var/datum/a1_fx/F = allocate(/datum/a1_fx)
	TEST_ASSERT(guarded(F, GUARD_STUMBLED_INTO), "the type guards the key")
	TEST_ASSERT(!guarded(F, GUARD_FALL), "and not another")
	TEST_ASSERT_NULL(guard(F, GUARD_STUMBLED_INTO, F), "no refusal: proceed")
	TEST_ASSERT_EQUAL(F.seen_key, GUARD_STUMBLED_INTO, "the handler saw the context")
	F.refuse = TRUE
	TEST_ASSERT_EQUAL(guard(F, GUARD_STUMBLED_INTO, F), "refused", "a reason refuses")
	TEST_ASSERT_NULL(guard(F, GUARD_FALL, F), "an unguarded key is never refused")
	// Every living mob guards its stumbles, falls, thrown hits and crossings (spontaneous vore).
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	for(var/key in list(GUARD_STUMBLED_INTO, GUARD_FALL, GUARD_THROWN_HIT, GUARD_CROSS))
		TEST_ASSERT(guarded(H, key), "a living mob guards [key]")
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NULL(guard(H, GUARD_STUMBLED_INTO, other), "with vore preferences off nobody is eaten: the stumble proceeds")

/// on_change(when =): a holder the gate excludes queues nothing when the key is published.
/datum/unit_test/dq_a1_on_change_when/Run()
	var/datum/a1_fx/F = allocate(/datum/a1_fx)
	rx_drain()
	PUBLISH_CHANGE(F, "a1_fact")
	rx_drain()
	TEST_ASSERT_EQUAL(F.hits, 0, "gate closed: nothing ran")
	F.gate = TRUE
	PUBLISH_CHANGE(F, "a1_fact")
	rx_drain()
	TEST_ASSERT_EQUAL(F.hits, 1, "gate open: it ran once")
	// The Life reactions are on_change over keys now (no channels).
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(READERS(H, MOB_KEY_STATUS), "a mob reads its status key")
	TEST_ASSERT(READERS(H, nameof(H.stat)), "and its tracked stat")

/// grant(): a granted_verb() goes to the verb store, a plain name is a ledger grant.
/datum/unit_test/dq_a1_grant_verbs/Run()
	var/obj/structure/S = allocate(/obj/structure)
	var/datum/a1_fx/source = allocate(/datum/a1_fx)
	TEST_ASSERT(!(/atom/movable/proc/turn_around in S.verbs), "no verb yet")
	grant(S, granted_verb(/atom/movable/proc/turn_around), source)
	TEST_ASSERT(/atom/movable/proc/turn_around in S.verbs, "grant() of a granted_verb gives the verb")
	TEST_ASSERT(granted(S, granted_verb(/atom/movable/proc/turn_around)), "and granted() says so")
	revoke(S, granted_verb(/atom/movable/proc/turn_around), source)
	TEST_ASSERT(!(/atom/movable/proc/turn_around in S.verbs), "revoke() takes it away")
	grant(S, "a1_permission", "a1")
	TEST_ASSERT(granted(S, "a1_permission"), "a plain grant is a ledger relation")
	TEST_ASSERT(rx_ledger_has(S, RELK_GRANT, "a1_permission"), "under RELK_GRANT")

/// rel_one(kind = RELK_OWNED, policy = OWN_PRIVATE_COPY) is the former proto(); flyweights are not leaks.
/datum/unit_test/dq_a1_private_copy_and_flyweights/Run()
	var/datum/own_entry/E = rel_one("x", kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)
	TEST_ASSERT_EQUAL(E.entry[OWNE_KIND], OWNK_PROTO, "OWN_PRIVATE_COPY declares a prototype var")
	var/datum/capability/C = caps_of(allocate(/obj/structure/dq_reflect_probe))[1] // REFLECTS: a legacy capability line
	TEST_ASSERT(is_flyweight(C), "an interned capability is a flyweight")
	TEST_ASSERT(!is_flyweight(allocate(/datum/a1_fx)), "an ordinary datum is not")

/// Dry galoshes hear a shoes_step notice (no om behaviour); squeaky shoes observe the same notice.
/datum/unit_test/dq_a1_dry_galoshes/Run()
	var/obj/item/clothing/shoes/dry_galoshes/G = allocate(/obj/item/clothing/shoes/dry_galoshes)
	TEST_ASSERT(WANTS(G, /datum/notice/shoes_step), "the galoshes listen for steps")
	var/turf/simulated/T = get_turf(G)
	if(istype(T))
		T.wet_floor(1)
		PUBLISH_LEGACY(G, /datum/notice/shoes_step, null, I_WALK)
		TEST_ASSERT(!T.wet, "a step dries the floor")
