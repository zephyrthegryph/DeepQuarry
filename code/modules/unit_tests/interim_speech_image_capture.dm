/// Real speech captures its actual image as a value and removes it at the original deadline.
/datum/unit_test/interim_speech_image_capture/Run()
	test_driver_begin()
	var/mob/living/carbon/human/speaker = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/om/global_owner/owner = timer_global_owner()
	var/datum/om/rec/rec = scheduler_record_of(owner)
	var/before = time_scheduler().timer_count(owner)
	var/previous_id = rec.timer_seq
	speaker.say("A real speech image needs deferred cleanup.")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(owner), before + 1, "actual speech schedules exactly one global image cleanup timer")
	var/list/pairs
	var/timer_id
	for(var/i = 1, i <= length(rec.timers), i += OM_TIMER_STRIDE)
		if(rec.timers[i] > previous_id && rec.timers[i + 2] == GLOBAL_PROC_REF(remove_speech_images))
			var/list/captured = rec.timers[i + 3]
			var/list/resolved = resolve_captured_value(captured[1], FALSE)
			TEST_ASSERT(resolved, "actual speech timer resolves its nested image values")
			pairs = resolved[1]
			timer_id = rec.timers[i]
	TEST_ASSERT(timer_id, "the actual speech schedules the real global remover")
	TEST_ASSERT_EQUAL(length(pairs), 1, "clientless actual speech records its one generated bubble")
	var/list/pair = pairs[1]
	var/image/bubble = pair[1]
	TEST_ASSERT(istype(bubble), "the actual speech timer contains the real generated image")
	TEST_ASSERT(bubble in owner.pending_speech_images, "production ownership retains the actual generated bubble independently of test ownership")
	TEST_ASSERT(!QDELETED(bubble), "the real speech bubble survives initial scheduling")
	TEST_ASSERT_EQUAL(timer_left(owner, timer_id), 3 SECONDS, "actual speech keeps the original cleanup delay")
	TEST_ASSERT(consume(speaker), "the actual speaker can disappear before global image cleanup")
	TEST_ASSERT(QDELETED(speaker), "the actual speaker is gone before its bubble deadline")
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(bubble), "the actual speech image survives before its deadline")
	TEST_ASSERT(timer_pending(owner, timer_id), "the actual cleanup remains scheduled before its deadline")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(bubble), "the actual global timer deletes the generated speech image at three seconds")
	TEST_ASSERT(!(bubble in owner.pending_speech_images), "actual cleanup releases its production image ownership")
	TEST_ASSERT(!timer_pending(owner, timer_id), "the fired actual speech cleanup leaves no pending timer")

/// Two real image values share one actual global cleanup timer without datum association keys.
/datum/unit_test/interim_speech_image_batch/Run()
	test_driver_begin()
	var/image/first = image(null)
	var/image/second = image(null)
	var/list/images_to_clients = list()
	images_to_clients[first] = list()
	images_to_clients[second] = list()
	var/datum/om/global_owner/owner = timer_global_owner()
	var/before = time_scheduler().timer_count(owner)
	var/timer_id = queue_speech_images(images_to_clients)
	TEST_ASSERT(timer_id, "the real timer accepts two sequential image and recipient pairs")
	TEST_ASSERT((first in owner.pending_speech_images) && (second in owner.pending_speech_images), "the production helper owns both exact generated images")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(owner), before + 1, "two actual images use one global cleanup timer")
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(first) && !QDELETED(second), "both exact image values remain alive before their shared deadline")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(first) && QDELETED(second), "the actual shared remover deletes both exact images at the deadline")
	TEST_ASSERT(!(first in owner.pending_speech_images) && !(second in owner.pending_speech_images), "actual shared cleanup drains both production ownership entries")
	TEST_ASSERT(!timer_pending(owner, timer_id), "the shared actual timer finishes once")
