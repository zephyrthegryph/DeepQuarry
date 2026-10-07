/// The real generic pulse endpoint survives its last pulse and deletes on exhaustion.
/datum/unit_test/interim_pulse_exhaustion/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/effect/temporary_effect/pulse/effect = allocate(/obj/effect/temporary_effect/pulse, T)
	TEST_ASSERT(!QDELETED(effect), "actual generic pulse initializes alive")
	TEST_ASSERT_EQUAL(effect.pulses_remaining, 2, "actual late initialization executes exactly the first of three pulses")
	TEST_ASSERT(om_timer_count(effect) > 0, "actual temporary pulse schedules its expiration")
	effect.pulse_step()
	TEST_ASSERT(!QDELETED(effect), "actual second pulse preserves its source")
	TEST_ASSERT_EQUAL(effect.pulses_remaining, 1, "actual second pulse debits exactly one remaining pulse")
	effect.pulse_step()
	TEST_ASSERT(!QDELETED(effect), "actual last pulse preserves source until the exhaustion step")
	TEST_ASSERT_EQUAL(effect.pulses_remaining, 0, "actual last pulse spends its remaining count")
	effect.pulse_step()
	TEST_ASSERT(QDELETED(effect), "actual exhaustion consumes the original pulse effect")
	TEST_ASSERT_EQUAL(om_timer_count(effect), 0, "actual pulse exhaustion cancels owned deadlines")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/effect/temporary_effect/pulse)), 0, "actual exhaustion leaves no original pulse effect")

/// Snake exhaustion follows actual timer-driven movement and preserves its linked actors.
/datum/unit_test/interim_pulse_exhaustion/snake/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/pen/creator = allocate(/obj/item/pen, T)
	var/obj/effect/temporary_effect/pulse/snake/snake = allocate(/obj/effect/temporary_effect/pulse/snake, T, creator, creator)
	TEST_ASSERT(!QDELETED(snake), "actual snake initializes alive")
	TEST_ASSERT_EQUAL(snake.pulses_remaining, 20, "actual snake schedules its first pulse without immediate movement")
	TEST_ASSERT_EQUAL(snake.hunting(), creator, "actual snake initialization links its real hunt target")
	TEST_ASSERT_EQUAL(snake.creator(), creator, "actual snake initialization links its real creator")
	TEST_ASSERT_EQUAL(snake.loc, T, "actual snake remains at its initial floor before its first deadline")
	TEST_ASSERT_EQUAL(snake.pulse_delay, 0.5 SECONDS, "actual snake uses the declared half-second pulse delay")
	// The public pulse budget limits this actual effect to two real scheduled movements.
	snake.pulses_remaining = 2
	// Hunting an item on the origin would constrain movement to no farther away.
	// Clear only the hunt constraint through its real relation API, retaining the creator.
	rel_clear(snake, nameof(snake.hunting))
	test_time(0.5 SECONDS)
	TEST_ASSERT(!QDELETED(snake), "actual first timed movement preserves the two-pulse snake")
	TEST_ASSERT_EQUAL(snake.pulses_remaining, 1, "actual first timed movement spends exactly one pulse")
	TEST_ASSERT(isturf(snake.loc) && snake.loc != T, "actual first pulse moves the snake onto a different real turf")
	TEST_ASSERT_EQUAL(length(snake.iterated_turfs), 1, "actual first movement records exactly one traversed turf")
	TEST_ASSERT_EQUAL(snake.iterated_turfs[1], snake.loc, "actual movement memory records the real destination turf")
	TEST_ASSERT_EQUAL(snake.creator(), creator, "actual first movement preserves its creator relation")
	test_time(0.5 SECONDS)
	TEST_ASSERT(QDELETED(snake), "actual second scheduled movement consumes the exhausted snake")
	TEST_ASSERT_EQUAL(om_timer_count(snake), 0, "actual snake exhaustion cancels its owned expiration and pulse deadlines")
	TEST_ASSERT(!QDELETED(creator), "actual snake exhaustion preserves its original creator item")
	TEST_ASSERT_EQUAL(creator.loc, T, "actual snake movement and exhaustion preserve its creator floor")
