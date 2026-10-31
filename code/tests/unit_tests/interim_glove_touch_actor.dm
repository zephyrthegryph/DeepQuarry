/// Observe the actual actor/stance reaching the ring, then execute its real zap.
/obj/item/clothing/gloves/ring/buzzer/interim_touch_probe
	var/zap_actor_ref
	var/zap_stance
	var/zap_count = 0
	var/touch_actor_ref
	var/touch_proximity

/obj/item/clothing/gloves/ring/buzzer/interim_touch_probe/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	touch_actor_ref = user ? REF(user) : null
	touch_proximity = proximity
	return ..()

/obj/item/clothing/gloves/ring/buzzer/interim_touch_probe/zap(mob/living/carbon/human/user, atom/movable/target, proximity, stance = I_HURT)
	zap_actor_ref = REF(user)
	zap_stance = stance
	zap_count++
	return ..()

/datum/unit_test/interim_glove_touch_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	dq_give_zone_sel(actor)
	dq_give_zone_sel(target)
	var/obj/item/clothing/gloves/ring/buzzer/interim_touch_probe/ring = allocate(/obj/item/clothing/gloves/ring/buzzer/interim_touch_probe, T)
	TEST_ASSERT(actor.equip_to_slot(ring, SLOT_ID_GLOVES), "the actor wears the actual buzzer ring")
	TEST_ASSERT(ring.battery, "the ring has its initialized battery")
	TEST_ASSERT(ring.battery.fully_charged(), "the initialized ring battery starts fully charged")
	var/charge_before = ring.battery.charge
	actor.UnarmedAttack(target, TRUE, I_HELP)
	TEST_ASSERT_EQUAL(ring.zap_count, 1, "the real unarmed attack invokes the glove")
	TEST_ASSERT_EQUAL(ring.zap_actor_ref, REF(actor), "unarmed attack forwards its actual actor")
	TEST_ASSERT_EQUAL(ring.zap_stance, I_HELP, "unarmed attack preserves the help stance")
	TEST_ASSERT_EQUAL(ring.battery.charge, charge_before, "the real buzzer does not spend charge on help")
	actor.UnarmedAttack(target, TRUE, I_HURT)
	own_turf_contents(T)
	TEST_ASSERT_EQUAL(ring.zap_count, 2, "the harm attack invokes the glove again")
	TEST_ASSERT_EQUAL(ring.zap_stance, I_HURT, "unarmed attack preserves the harm stance")
	TEST_ASSERT(ring.battery.charge < charge_before, "the real harm zap consumes battery charge")
	var/charge_after = ring.battery.charge
	actor.RangedAttack(target, null, I_HURT)
	TEST_ASSERT_EQUAL(ring.touch_actor_ref, REF(actor), "the ranged attack also forwards its actual actor")
	TEST_ASSERT_EQUAL(ring.touch_proximity, 0, "ranged attack preserves the nonadjacent glove exposure")
	TEST_ASSERT_EQUAL(ring.zap_count, 2, "ranged attack does not activate a proximity-only buzzer")
	TEST_ASSERT_EQUAL(ring.battery.charge, charge_after, "ranged refusal preserves charge")
