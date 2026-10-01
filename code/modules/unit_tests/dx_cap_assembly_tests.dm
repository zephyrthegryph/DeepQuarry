// cap_assembly() (code/datums/capabilities/library/assembly.dm).

/obj/cap_fixture/rigged
	var/list/pulses

/obj/cap_fixture/rigged/capabilities()
	. = ..()
	. += cap_assembly(attach_types = list(/obj/item/assembly/signaler, /obj/item/assembly/timer), on_pulse = PROC_REF(fx_pulsed), attached_state = "rigged")

/obj/cap_fixture/rigged/proc/fx_pulsed(obj/item/assembly/source)
	LAZYADD(pulses, source)

/datum/unit_test/dx_cap_assembly

/datum/unit_test/dx_cap_assembly/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/rigged/F = allocate(/obj/cap_fixture/rigged, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/assembly/signaler/A = allocate(/obj/item/assembly/signaler, T)
	var/obj/item/assembly/signaler/B = allocate(/obj/item/assembly/signaler, T)
	var/obj/item/assembly/igniter/igniter = allocate(/obj/item/assembly/igniter, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_zero_speed(allocate(/obj/item/tool/screwdriver, T))

	var/datum/interaction/capability/attach = dx_cap_entry(F, "Attach")
	var/datum/interaction/capability/detach = dx_cap_entry(F, "Detach assembly")
	var/datum/interaction/capability/trigger = dx_cap_entry(F, "Trigger")
	TEST_ASSERT_NOTNULL(attach, "the Attach entry")
	TEST_ASSERT_NOTNULL(detach, "the Detach entry")
	TEST_ASSERT_NOTNULL(trigger, "the Trigger entry")
	TEST_ASSERT_EQUAL(detach.tool, TOOL_SCREWDRIVER, "a screwdriver detaches by default")
	TEST_ASSERT_NULL(trigger.default_action, "Trigger is Menu only")
	TEST_ASSERT(attach.is_meant(H, F, A), "a signaler fits")
	TEST_ASSERT(!attach.is_meant(H, F, igniter), "an igniter isn't in attach_types")
	TEST_ASSERT_EQUAL(trigger.why_not(H, F, null), "nothing is attached to it", "nothing to trigger yet")
	TEST_ASSERT_EQUAL(detach.why_not(H, F, screwdriver), "nothing is attached to it", "nothing to detach yet")

	TEST_ASSERT(A.secured, "a signaler starts secured")
	TEST_ASSERT_EQUAL(attach.why_not(H, F, A), "unsecure \the [A] first", "a secured assembly won't attach")
	A.set_secured(FALSE)
	TEST_ASSERT_NULL(attach.why_not(H, F, A), "an unsecured one will")
	attach.perform(H, F, A)
	TEST_ASSERT_EQUAL(F.attached_assembly, A, "attached (owned in attached_assembly)")
	TEST_ASSERT_EQUAL(A.loc, F, "inside the holder")
	TEST_ASSERT(A.secured, "secured once attached")
	TEST_ASSERT_EQUAL(caps_examine(F, H)[1], "\A [A] is attached to it.", "examine names it")
	refresh_flush()
	TEST_ASSERT(dx_look_shows(F, "rigged"), "draw shows the attached overlay")

	B.set_secured(FALSE)
	TEST_ASSERT_EQUAL(attach.why_not(H, F, B), "something is already attached to it", "one assembly at a time")

	// The attached assembly pulsing runs on_pulse on the holder.
	A.pulse(0)
	TEST_ASSERT_EQUAL(LAZYLEN(F.pulses), 1, "the pulse reached the holder")
	TEST_ASSERT_EQUAL(F.pulses[1], A, "with its source")

	// Trigger activates it (its own cooldown then holds it).
	TEST_ASSERT_NULL(trigger.why_not(H, F, null), "something to trigger")
	trigger.perform(H, F, null)
	TEST_ASSERT(!COOLDOWN_FINISHED(A, next_activate), "the signaler went off")

	detach.perform(H, F, screwdriver)
	TEST_ASSERT_NULL(F.attached_assembly, "detached")
	TEST_ASSERT(A.loc != F, "it left the holder")
	TEST_ASSERT(!A.secured, "unsecured again, ready to attach elsewhere")
	refresh_flush()
	TEST_ASSERT(!dx_look_shows(F, "rigged"), "the overlay is gone")
	A.pulse(0)
	TEST_ASSERT_EQUAL(LAZYLEN(F.pulses), 1, "a detached assembly no longer pulses the holder")

	var/list/data = list()
	caps_ui_data(F, H, data)
	TEST_ASSERT_NULL(data["attached_assembly"], "ui_data: nothing attached")
