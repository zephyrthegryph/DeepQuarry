// The shared portrait cache (code/content/appearance/portrait_cache.dm): a picture is rendered off the tick once per look, served from the cache
// after (a look is its key: two mobs that look the same share one picture), and lands for whoever asked. PORTRAIT_COST lines compare the old synchronous path with the new one.

/datum/unit_test/dq_portrait_cache
	var/landed = 0
	var/datum/portrait/landed_portrait

/datum/unit_test/dq_portrait_cache/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(H), SLOT_ID_SHOES)
	H.ImmediateOverlayUpdate()
	var/started = TICK_USAGE_REAL
	getFlatIcon(H, defdir = SOUTH, no_anim = TRUE)
	var/old_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	var/datum/portrait/P = portrait_request(H, SOUTH, src, PROC_REF(portrait_landed))
	var/request_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	if(!P)
		// Asking again while it renders (a window pushed twice) still calls the asker back once.
		portrait_request(H, SOUTH, src, PROC_REF(portrait_landed))
		for(var/i in 1 to 40)
			test_time(0.25 SECONDS)
			if(landed)
				break
		TEST_ASSERT(landed, "the portrait landed and the asker was called back")
		TEST_ASSERT_EQUAL(landed, 1, "an asker that asked twice is called back once")
		P = landed_portrait
	TEST_ASSERT(P?.picture, "the portrait is ready")
	if(!P?.picture)
		test_driver_end()
		return
	// The mob may have redrawn while the picture rendered (its look then has a new key): ask twice now, in one tick, for the cache hit.
	var/datum/portrait/first = portrait_request(H, SOUTH)
	for(var/i in 1 to 40)
		if(first?.b64)
			break
		test_time(0.25 SECONDS)
		first = portrait_request(H, SOUTH)
	started = TICK_USAGE_REAL
	var/datum/portrait/again = portrait_request(H, SOUTH)
	var/hit_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT(again && again == first, "the same look is served from the cache")
	// Exactness is the translation's, checked pixel by pixel against getFlatIcon by dq_preview_async_matches_getflaticon.
	TEST_ASSERT(again?.picture?.Width() > 0, "the portrait has a picture")
	// A second, different look: the translation's metadata reads are warm now, as they are on a server that has been up a while.
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	other.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(other), SLOT_ID_UNIFORM)
	other.equip_to_slot_or_del(new /obj/item/clothing/gloves/black(other), SLOT_ID_GLOVES)
	draw_now(other)
	started = TICK_USAGE_REAL
	getFlatIcon(other, defdir = SOUTH, no_anim = TRUE)
	var/old_warm_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	portrait_request(other, SOUTH)
	var/request_warm_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_NOTICE(src, "PORTRAIT_COST a second look: getFlatIcon [round(old_warm_ms, 0.01)] ms, portrait request [round(request_warm_ms, 0.01)] ms")
	TEST_NOTICE(src, "PORTRAIT_COST getFlatIcon on the tick [round(old_ms, 0.01)] ms; portrait request on the tick [round(request_ms, 0.01)] ms (composited off-thread), a cached one [round(hit_ms, 0.01)] ms")
	test_driver_end()

/datum/unit_test/dq_portrait_cache/proc/portrait_landed(datum/portrait/P)
	landed++
	landed_portrait = P
