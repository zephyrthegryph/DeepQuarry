// The wires capability (code/datums/capabilities/library/wires.dm).

/datum/wires/cap_fixture
	holder_type = /obj/cap_fixture/wires
	proper_name = "Capability fixture"
	wire_count = 4

/datum/wires/cap_fixture/New(atom/_holder)
	wires = list(WIRE_MAIN_POWER1)
	return ..()

/obj/cap_fixture/wires/capabilities()
	. = ..()
	. += cap_panel()
	. += cap_wires(/datum/wires/cap_fixture)

/// The wires are behind the panel, made on first use in cap_data, drawn while exposed and freed with the holder.
/datum/unit_test/dx_cap_wires_owned/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/wires/A = allocate(/obj/cap_fixture/wires, T)
	var/obj/item/multitool/multitool = allocate(/obj/item/multitool, T)
	var/datum/interaction/capability/pulse = cap_test_entry(A, "wires:multitool")
	var/datum/interaction/capability/cut = cap_test_entry(A, "wires:wirecutter")
	TEST_ASSERT_NOTNULL(pulse, "a multitool entry")
	TEST_ASSERT_NOTNULL(cut, "a wirecutter entry")
	TEST_ASSERT_NULL(A.cap_data, "no wires datum before first use")
	TEST_ASSERT(!wires_exposed(A), "the wires are hidden behind the closed panel")
	TEST_ASSERT_EQUAL(pulse.why_not(H, A, multitool), "open the maintenance panel first", "the wires refuse behind the panel")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "wires"), "no wires layer while hidden")
	cap_set(A, CAP_PANEL_OPEN, TRUE)
	TEST_ASSERT(wires_exposed(A), "the wires are exposed with the panel open")
	TEST_ASSERT(H.put_in_active_hand(multitool), "the human holds a multitool")
	TEST_ASSERT(pulse.perform(H, A, multitool), "the multitool opens the wires")
	var/datum/wires/W = wires_of(A)
	TEST_ASSERT(istype(W, /datum/wires/cap_fixture), "the wires datum is the declared type")
	TEST_ASSERT_EQUAL(W.holder, A, "its holder is the fixture")
	TEST_ASSERT_EQUAL(wires_of(A), W, "one datum per holder")
	TEST_ASSERT_EQUAL(A.cap_data[/datum/capability/wires], W, "kept in cap_data under the capability's key")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "wires"), "the wires layer shows while exposed")
	qdel(A)
	TEST_ASSERT(QDELETED(W), "the wires datum is freed with its holder")
