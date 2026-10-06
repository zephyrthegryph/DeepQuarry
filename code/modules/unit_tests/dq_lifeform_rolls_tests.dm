// rolls(target, generator, when =, from =) (code/engine/lifeforms/rolls.dm): seeded per-instance randomness rolled before init.

/obj/item/dq_roll_probe
	name = "roll probe"
	var/shade = "plain"
	var/size = 0
	var/lucky = null
	var/heavy = FALSE
	var/weight_class = null
	var/summary = null
	var/never = "kept"
	var/gated = "kept"
	var/gate_open = FALSE
	/// What Initialize() saw (the rolls run before the type's init code).
	var/seen_at_init = null

CAPABILITIES(/obj/item/dq_roll_probe)
	rolls(ROLL_PIXEL, PIXEL_JITTER(8))
	rolls(nameof(shade), pick_one(list("red", "green", "blue")))
	rolls(nameof(size), range_of(1, 6))
	rolls(nameof(lucky), chance(50))
	rolls(nameof(weight_class), pick_weighted(list("light" = 3, "heavy" = 1, "impossible" = 0)))
	rolls(nameof(summary), PROC_REF(roll_summary), from = list(nameof(size), nameof(shade)))
	rolls(nameof(never), chance(0))
	rolls(nameof(gated), pick_one(list("rolled")), when = nameof(gate_open))
	param(nameof(shade), schema_text())

/obj/item/dq_roll_probe/Initialize(mapload)
	. = ..()
	seen_at_init = shade

/// A dependent roll: reads the rolls it names in from =, which the engine rolls first.
/obj/item/dq_roll_probe/proc/roll_summary(datum/roller/R)
	return "[shade]:[size]:[R.number(1, 3)]"

/obj/item/dq_roll_probe/gate_open
	gate_open = TRUE

/datum/unit_test/dq_lifeform_rolls

/datum/unit_test/dq_lifeform_rolls/proc/snapshot(obj/item/dq_roll_probe/P)
	return "[P.pixel_x],[P.pixel_y],[P.shade],[P.size],[P.lucky],[P.weight_class],[P.summary]"

/datum/unit_test/dq_lifeform_rolls/Run()
	var/turf/T = dq_containment_floor()
	var/old_seed = GLOB.round_seed
	rolls_fix_seed(4242)
	var/obj/item/dq_roll_probe/first = allocate(/obj/item/dq_roll_probe, T)
	var/first_snapshot = snapshot(first)
	TEST_ASSERT_EQUAL(first.seen_at_init, first.shade, "Initialize() sees the rolled value: rolls run before the type's init code")
	TEST_ASSERT(first.shade in list("red", "green", "blue"), "pick_one() picks from its list ([first.shade])")
	TEST_ASSERT(first.size >= 1 && first.size <= 6 && first.size == round(first.size), "range_of(1, 6) is a whole number in range ([first.size])")
	TEST_ASSERT(abs(first.pixel_x) <= 8 && abs(first.pixel_y) <= 8, "PIXEL_JITTER(8) stays within 8 pixels")
	TEST_ASSERT(first.weight_class in list("light", "heavy"), "a zero weight is never picked ([first.weight_class])")
	TEST_ASSERT_EQUAL(copytext(first.summary, 1, length("[first.shade]:[first.size]:") + 1), "[first.shade]:[first.size]:", "a from = roll reads the rolls it depends on")
	TEST_ASSERT_EQUAL(first.never, FALSE, "chance(0) rolls FALSE")
	TEST_ASSERT_EQUAL(first.gated, "kept", "a when = that is false skips the roll")
	qdel(first)

	// The same seed at the same place rolls the same values.
	rolls_fix_seed(4242)
	var/obj/item/dq_roll_probe/again = allocate(/obj/item/dq_roll_probe, T)
	TEST_ASSERT_EQUAL(snapshot(again), first_snapshot, "the same round seed and position roll the same instance")
	qdel(again)

	// A different seed rolls differently somewhere across a handful of instances.
	var/list/seen = list()
	for(var/seed in list(1, 2, 3, 4, 5, 6))
		rolls_fix_seed(seed)
		var/obj/item/dq_roll_probe/probe = allocate(/obj/item/dq_roll_probe, T)
		seen[snapshot(probe)] = TRUE
		qdel(probe)
	TEST_ASSERT(length(seen) > 1, "different round seeds roll different instances")

	// A given value (a param, as a map edit would be) suppresses the roll.
	var/obj/item/dq_roll_probe/given = make(/obj/item/dq_roll_probe, at = T, shade = "mauve")
	own(given)
	TEST_ASSERT_EQUAL(given.shade, "mauve", "a value make() gave is not rolled over")
	TEST_ASSERT_EQUAL(given.seen_at_init, "mauve", "the given value is in place before init")

	var/obj/item/dq_roll_probe/gate_open/open = allocate(/obj/item/dq_roll_probe/gate_open, T)
	TEST_ASSERT_EQUAL(open.gated, "rolled", "a when = that holds lets the roll run")

	// What an instance creates while it initializes rolls from its stream.
	rolls_fix_seed(77)
	var/datum/roller/R = new("77/test")
	GLOB.roll_creators += R
	var/obj/item/dq_roll_probe/child_a = allocate(/obj/item/dq_roll_probe, null)
	var/obj/item/dq_roll_probe/child_b = allocate(/obj/item/dq_roll_probe, null)
	GLOB.roll_creators -= R
	TEST_ASSERT_EQUAL(R.children, 2, "two instances created under a creator took two child streams")
	// The rolls draw in declaration order: the two pixel offsets, the shade, then the size.
	var/datum/roller/replay = new("77/test/1")
	replay.number(-8, 8)
	replay.number(-8, 8)
	replay.number(1, 3)
	TEST_ASSERT_EQUAL(child_a.size, replay.number(1, 6), "the first child rolls from the creator's first child stream")
	TEST_ASSERT_NOTNULL(child_b.shade, "the second child rolled too")
	rolls_fix_seed(old_seed)
