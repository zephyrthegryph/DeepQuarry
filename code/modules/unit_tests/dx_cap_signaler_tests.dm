// cap_signaler() (code/datums/capabilities/library/signaler.dm).

/obj/cap_fixture/beacon
	var/list/received

/obj/cap_fixture/beacon/capabilities()
	. = ..()
	. += cap_signaler(frequency = 1451, code = 7, on_signal = PROC_REF(fx_signalled))

/obj/cap_fixture/beacon/proc/fx_signalled(datum/signal/signal)
	LAZYADD(received, signal.data["message"])

/// A mapped instance: its own vars override the type defaults (H1).
/obj/cap_fixture/beacon/mapped
	cap_signal_frequency = 1453
	cap_signal_code = 9

/proc/dx_listens_on(obj/O, frequency)
	var/datum/radio_frequency/channel = GLOB.radio_service.frequencies["[frequency]"]
	var/list/listeners = channel?.devices[RADIO_CHAT]
	return !!(O in listeners)

/datum/unit_test/dx_cap_signaler

/datum/unit_test/dx_cap_signaler/Run()
	var/turf/T = test_floor()
	var/obj/cap_fixture/beacon/F = allocate(/obj/cap_fixture/beacon, T)
	var/obj/cap_fixture/beacon/G = allocate(/obj/cap_fixture/beacon, T)
	var/obj/cap_fixture/beacon/mapped/M = allocate(/obj/cap_fixture/beacon/mapped, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)

	TEST_ASSERT_EQUAL(cap_signaler_frequency(F), 1451, "the type default frequency")
	TEST_ASSERT_EQUAL(cap_signaler_code(F), 7, "the type default code")
	TEST_ASSERT_EQUAL(cap_signaler_frequency(M), 1453, "a mapped frequency wins")
	TEST_ASSERT_EQUAL(cap_signaler_code(M), 9, "a mapped code wins")
	TEST_ASSERT(dx_listens_on(F, 1451), "it joined the radio on its frequency")
	TEST_ASSERT(dx_listens_on(M, 1453), "the mapped one on its own")
	TEST_ASSERT_EQUAL(caps_examine(F, H)[1], "It is set to 145.1, code 7.", "examine shows the setting")

	var/datum/interaction/capability/send = dx_cap_entry(F, "Send signal")
	var/datum/interaction/capability/set_freq = dx_cap_entry(F, "Set frequency")
	var/datum/interaction/capability/set_code = dx_cap_entry(F, "Set code")
	TEST_ASSERT_NOTNULL(send, "the Send signal entry")
	TEST_ASSERT_EQUAL(length(set_freq.form), 1, "Set frequency is a form")
	var/datum/form_field/number/freq_field = set_freq.form[1]
	TEST_ASSERT_EQUAL(freq_field.name, "frequency", "its answer arrives as frequency")
	TEST_ASSERT_EQUAL(freq_field.min_value, RADIO_LOW_FREQ, "bounded to the radio band")

	// Sending reaches a listener with the same frequency and code, and nothing else.
	send.perform(H, F, null)
	TEST_ASSERT_EQUAL(LAZYLEN(G.received), 1, "the other beacon got the signal")
	TEST_ASSERT_EQUAL(G.received[1], "ACTIVATE", "an activation")
	TEST_ASSERT_NULL(F.received, "the sender doesn't hear itself")
	TEST_ASSERT_NULL(M.received, "another frequency hears nothing")
	TEST_ASSERT_EQUAL(cap_signaler_signal(F), "it isn't ready yet", "the cooldown holds a second signal")

	G.cap_signal_code = 3 // a per-instance code
	var/datum/cap_signaler_data/D = cap_data(F, cap_signaler_cap(F))
	D.next_signal = 0
	TEST_ASSERT_NULL(cap_signaler_signal(F), "signals again after the cooldown")
	TEST_ASSERT_EQUAL(LAZYLEN(G.received), 1, "a different code ignores it")

	// The forms, answered without prompting.
	var/list/freq_form = set_freq.form
	var/list/code_form = set_code.form
	set_freq.form = list(dx_entries_canned_field(/datum/form_field/number/dx_canned, "frequency", 1456))
	set_freq.perform(H, F, null)
	TEST_ASSERT_EQUAL(cap_signaler_frequency(F), 1457, "retuned, to an odd frequency")
	TEST_ASSERT(dx_listens_on(F, 1457), "listening on the new frequency")
	TEST_ASSERT(!dx_listens_on(F, 1451), "and no longer on the old one")
	set_code.form = list(dx_entries_canned_field(/datum/form_field/number/dx_canned, "code", 150))
	set_code.perform(H, F, null)
	TEST_ASSERT_EQUAL(cap_signaler_code(F), 100, "the code is clamped to 100")
	set_freq.form = freq_form
	set_code.form = code_form

	var/list/data = dx_cap_ui_data(F, H, /datum/capability/signaler)
	TEST_ASSERT_EQUAL(data["frequency"], 1457, "ui_data frequency")
	TEST_ASSERT_EQUAL(data["code"], 100, "ui_data code")
	TEST_ASSERT_EQUAL(data["minFrequency"], RADIO_LOW_FREQ, "ui_data band")
