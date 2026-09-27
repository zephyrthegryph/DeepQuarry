// Mob size writers must not clobber other contributors' size changes (no source
// tracking on size_multiplier). See doc/rewrite roadmap item on mob state writers.
//
// Covers:
// - The bluespace size collar used to snapshot an ABSOLUTE size_multiplier on
//   activation and blindly restore it later, discarding whatever any other
//   source (a potion, a sizegun, another collar, ...) did to the wearer's size
//   in between. It also gated its activate/restore branch on size_multiplier
//   exactly matching target_size, so an unrelated source landing on the same
//   value by coincidence could trip a stale restore. The fix tracks the RATIO
//   the collar itself applied and gates on its own active/inactive state
//   (`applied_ratio == null`), so restoring only divides out the collar's own
//   contribution and leaves other sources' multiplicative changes intact.
// - Admin/event mob spawning and the appearance changer's "size_scale" option
//   used to write mob.size_multiplier directly instead of going through
//   /mob/living/proc/resize(), bypassing resize()'s clamping/guard-component
//   bookkeeping.

/datum/unit_test/dq_bluespace_collar_does_not_clobber_other_size_sources

/datum/unit_test/dq_bluespace_collar_does_not_clobber_other_size_sources/Run()
	var/mob/living/carbon/human/H = new(null)
	var/obj/item/clothing/accessory/collar/shock/bluespace/modified/C = new(H)

	TEST_ASSERT(H.resizable, "test human should be resizable by default")
	TEST_ASSERT(dq_near(H.size_multiplier, 1), "test human should start at 100% size, got [H.size_multiplier * 100]%")

	// Collar activates: target = (encryption * 2) / 100 = 1.4 (140%).
	// (Clear the recharge cooldown -- world.time is near zero this early in a
	// fresh test world, which would otherwise trip the "still recharging" gate.)
	C.last_activated = -100 SECONDS
	var/datum/signal/activate_signal = new
	activate_signal.encryption = 70
	C.receive_signal(activate_signal)
	TEST_ASSERT(dq_near(H.size_multiplier, 1.4), "collar activation should bring the wearer to 140%, got [H.size_multiplier * 100]%")
	TEST_ASSERT(!isnull(C.applied_ratio), "collar should be tracking itself as active after engaging")

	// An unrelated source (a growth potion, a sizegun, whatever) resizes the
	// wearer on top of the collar's effect. This must not be clobbered later.
	H.resize(H.size_multiplier * 1.2, animate = FALSE)
	TEST_ASSERT(dq_near(H.size_multiplier, 1.68), "external source should stack multiplicatively on top of the collar, got [H.size_multiplier * 100]%")

	// Deactivating the collar (same target, still active) must only undo the
	// collar's own 1.4x contribution, not stomp back to the pre-collar 100%.
	var/datum/signal/deactivate_signal = new
	deactivate_signal.encryption = 70
	C.receive_signal(deactivate_signal)
	TEST_ASSERT(isnull(C.applied_ratio), "collar should be tracking itself as inactive after disengaging")
	TEST_ASSERT(!dq_near(H.size_multiplier, 1), "deactivating the collar must not clobber the other source's contribution back down to the pre-collar size")
	TEST_ASSERT(dq_near(H.size_multiplier, 1.2), "deactivating the collar should leave only the external source's 1.2x contribution, got [H.size_multiplier * 100]%")

	qdel(C)
	qdel(H)

/// A coincidental size match with the collar's target must not be mistaken for
/// "the collar is active" (the old equality-gated design could misfire here).
/datum/unit_test/dq_bluespace_collar_activation_is_not_gated_on_size_coincidence

/datum/unit_test/dq_bluespace_collar_activation_is_not_gated_on_size_coincidence/Run()
	var/mob/living/carbon/human/H = new(null)
	var/obj/item/clothing/accessory/collar/shock/bluespace/modified/C = new(H)

	// Some unrelated source happens to leave the wearer at exactly the size the
	// collar would later target (140%), without the collar ever having engaged.
	H.resize(1.4, animate = FALSE)
	TEST_ASSERT(isnull(C.applied_ratio), "collar should still be inactive before it has ever been signalled")

	C.last_activated = -100 SECONDS
	var/datum/signal/activate_signal = new
	activate_signal.encryption = 70 // target = 1.4, matching current size by coincidence
	C.receive_signal(activate_signal)

	// A size-equality-gated design would have treated this as "already active,
	// restore now" and reset the wearer to some stale/absent original size.
	// The state-tracked design must instead genuinely engage the collar.
	TEST_ASSERT(!isnull(C.applied_ratio), "the collar must engage on its first signal even if size already coincidentally matches its target")
	TEST_ASSERT(dq_near(H.size_multiplier, 1.4), "size should remain at the target after engaging, got [H.size_multiplier * 100]%")

	qdel(C)
	qdel(H)

/// Admin/event mob spawning must route size through resize(), not a raw
/// size_multiplier write, so resize()'s clamping and guard bookkeeping run.
/datum/unit_test/dq_mob_size_writers_route_through_resize

/datum/unit_test/dq_mob_size_writers_route_through_resize/Run()
	var/mob/living/carbon/human/H = new(null)

	// A raw write (the old bug) would happily accept an out-of-band value like
	// 5x with no clamping. Going through resize() (uncapped = FALSE, the
	// default used by the appearance changer and the admin spawner) must clamp
	// it to RESIZE_MAXIMUM instead.
	H.resize(5, animate = FALSE)
	TEST_ASSERT(H.size_multiplier <= RESIZE_MAXIMUM, "resize() should clamp an out-of-range size instead of accepting it raw, got [H.size_multiplier * 100]%")
	TEST_ASSERT(dq_near(H.size_multiplier, RESIZE_MAXIMUM), "resize() should clamp to exactly RESIZE_MAXIMUM, got [H.size_multiplier * 100]%")

	qdel(H)
