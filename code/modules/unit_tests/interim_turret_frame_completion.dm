/// The actual final weld callback must prepare one configured, disabled floor turret.
/datum/unit_test/interim_turret_frame_completion/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/porta_turret_construct/frame = allocate(/obj/machinery/porta_turret_construct, T)
	frame.set_anchored(TRUE)
	frame.build_step = 7
	frame.finish_name = "Configured test turret"
	frame.installation = /obj/item/gun/energy/gun
	frame.gun_charge = 123
	var/frame_handle = om_handle(frame)
	var/list/before = turf_contents_of_type(T, /obj/machinery/porta_turret)
	frame.welder_act_tool_done2(actor)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(frame), "The actual final weld must remove the construction frame")
	var/list/created = turf_contents_of_type(T, /obj/machinery/porta_turret) - before
	TEST_ASSERT_EQUAL(length(created), 1, "The final weld must create exactly one turret")
	var/obj/machinery/porta_turret/turret = created[1]
	TEST_ASSERT_EQUAL(turret.type, /obj/machinery/porta_turret, "The configured target type must be created")
	TEST_ASSERT_EQUAL(turret.loc, T, "The successor must remain on the actual frame floor")
	TEST_ASSERT_EQUAL(turret.name, "Configured test turret", "The configured name must survive construction")
	TEST_ASSERT_EQUAL(turret.installation, /obj/item/gun/energy/gun, "The installed gun type must survive construction")
	TEST_ASSERT_EQUAL(turret.gun_charge, 123, "The installed gun's actual charge must survive construction")
	TEST_ASSERT_EQUAL(turret.enabled, FALSE, "A newly completed turret must remain disabled")
	TEST_ASSERT_EQUAL(turret.lethal_projectile, /obj/item/projectile/beam, "The actual gun-specific setup must configure laser fire")
	TEST_ASSERT_EQUAL(turret.lethal_shot_sound, SFX_WEAPONS_LASER, "The actual gun-specific setup must configure laser sound")
	TEST_ASSERT_NULL(om_resolve(frame_handle), "A turret-construction handle must terminate for its cross-family turret successor")
