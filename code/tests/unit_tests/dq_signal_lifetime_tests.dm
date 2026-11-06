// One lifetime rule for /datum/signal: the sender hands a signal to a delivery and the delivery ends it (signal_release()); a holder that
// needs it later keeps a copy it owns. Nothing in a delivery may leave a signal that only the slot table holds (slot_leak_report()).

/// A listener on a frequency: reads the signal while it is delivered.
/obj/dq_signal_probe
	var/heard_command

/obj/dq_signal_probe/receive_signal(datum/signal/signal, receive_method, receive_param)
	heard_command = signal.data["command"]

/// A listener that must keep the signal past its delivery: it takes it into a relation it owns.
/obj/dq_signal_probe/keeper
	var/list/datum/signal/kept_signals

CAPABILITIES(/obj/dq_signal_probe/keeper)
	owns_many(nameof(kept_signals), /datum/signal)

/obj/dq_signal_probe/keeper/receive_signal(datum/signal/signal, receive_method, receive_param)
	signal_keep(src, nameof(kept_signals), signal)

/proc/dq_signal_leaks()
	return slot_leak_report(log = FALSE)["/datum/signal"] || 0

/// A signal posted on a frequency is read by its listeners and then ended: no slot is left holding it.
/datum/unit_test/dq_signal_post_ends_the_signal

/datum/unit_test/dq_signal_post_ends_the_signal/Run()
	var/turf/T = test_floor()
	var/obj/dq_signal_probe/listener = allocate(/obj/dq_signal_probe, T)
	var/datum/radio_frequency/F = SSradio.add_object(listener, 1479)
	var/leaks_before = dq_signal_leaks()
	var/datum/signal/signal = new
	rel_set(signal, nameof(signal.source), listener)
	signal.data["command"] = "ping"
	F.post_signal(null, signal)
	TEST_ASSERT_EQUAL(listener.heard_command, "ping", "the listener read the signal while it was delivered")
	TEST_ASSERT(QDELETED(signal), "the delivery ended the signal")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "no signal slot is left holding it")
	var/datum/signal/ranged = new
	rel_set(ranged, nameof(ranged.source), listener)
	F.post_signal(null, ranged, range = 5)
	TEST_ASSERT(QDELETED(ranged), "a ranged post from nowhere ends the signal too")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "and leaves no slot")

/// A listener that takes the signal keeps it past the delivery, and ends it itself.
/datum/unit_test/dq_signal_post_keeps_what_a_receiver_takes

/datum/unit_test/dq_signal_post_keeps_what_a_receiver_takes/Run()
	var/turf/T = test_floor()
	var/obj/dq_signal_probe/keeper/listener = allocate(/obj/dq_signal_probe/keeper, T)
	var/datum/radio_frequency/F = SSradio.add_object(listener, 1481)
	var/leaks_before = dq_signal_leaks()
	var/datum/signal/signal = new
	signal.data["command"] = "stay"
	F.post_signal(null, signal)
	TEST_ASSERT(!QDELETED(signal), "a signal a receiver owns is not ended by the delivery")
	TEST_ASSERT_EQUAL(owner_of(signal), listener, "the receiver owns it")
	spent(signal)
	TEST_ASSERT_EQUAL(length(listener.kept_signals), 0, "ending it takes it out of the receiver")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "nothing is left holding a signal")

/// A telecomms machine that delays a signal keeps a copy of its own and ends it when the delay is done; the delivery ends the original.
/datum/unit_test/dq_signal_telecomms_defers_on_a_copy

/datum/unit_test/dq_signal_telecomms_defers_on_a_copy/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/machinery/telecomms/hub/source = allocate(/obj/machinery/telecomms/hub, T)
	var/obj/machinery/telecomms/broadcaster/out = allocate(/obj/machinery/telecomms/broadcaster, T)
	for(var/obj/machinery/telecomms/M as anything in list(source, out))
		M.set_grid_power(TRUE)
		M.set_broken_condition(FALSE)
		M.set_listening_level(T.z)
	rel_add(source, nameof(/obj/machinery/telecomms::links), out)
	var/leaks_before = dq_signal_leaks()
	var/datum/signal/original = new
	original.transmission_method = TRANSMISSION_SUBSPACE
	original.data = list("message" = "lifetime probe", "realname" = "probe", "type" = SIGNAL_TEST, "slow" = 20, "level" = list(T.z), "compression" = 0)
	original.frequency = PUB_FREQ
	var/sent = source.relay_information(original, /obj/machinery/telecomms/broadcaster, TRUE)
	TEST_ASSERT_EQUAL(sent, 1, "the broadcaster was sent the signal")
	TEST_ASSERT_EQUAL(length(out.held_signals), 1, "the broadcaster keeps one copy while it waits")
	signal_release(original)
	TEST_ASSERT(QDELETED(original), "the sender's delivery ended the original")
	TEST_ASSERT(!QDELETED(out.held_signals[1]), "the waiting copy outlives it")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "no signal is left holding a slot while it waits")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(length(out.held_signals), 0, "the delayed broadcast ended its copy")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "and nothing leaked")
	test_driver_end()

/// A voice through a radio, and a telecomms test signal, end their signals.
/datum/unit_test/dq_signal_voice_through_telecomms_ends_the_signal

/datum/unit_test/dq_signal_voice_through_telecomms_ends_the_signal/Run()
	var/turf/T = test_floor()
	var/obj/item/radio/headset/R = allocate(/obj/item/radio/headset, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/leaks_before = dq_signal_leaks()
	R.talk_into(H, message_to_multilingual("probe"), null, "says")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "talking into a radio leaves no signal slot behind")
	var/datum/signal/test_signal = H.telecomms_process()
	TEST_ASSERT(test_signal, "the test signal is answered to the caller")
	signal_release(test_signal)
	TEST_ASSERT(QDELETED(test_signal), "and the caller ends it")
	TEST_ASSERT_EQUAL(dq_signal_leaks(), leaks_before, "leaving no signal slot")
