#define INTERIM_PDA_SIGNAL_FREQUENCY 32001

/// Observe real radio delivery without replacing the sender or radio service.
/obj/interim_pda_signal_receiver
	var/received_count = 0
	var/message_seen
	var/encryption_seen
	var/source_ref_seen
	var/datum/signal/last_signal

/obj/interim_pda_signal_receiver/receive_signal(datum/signal/signal, receive_method, receive_param)
	received_count++
	message_seen = signal.data["message"]
	encryption_seen = signal.encryption
	source_ref_seen = REF(signal.source())
	rel_set(src, nameof(last_signal), signal)

/obj/item/radio/integrated/signal/interim_actor_probe
	var/actor_ref_seen

/obj/item/radio/integrated/signal/interim_actor_probe/send_signal(message = "ACTIVATE", mob/user)
	actor_ref_seen = user ? REF(user) : null
	return ..()

/datum/data/pda/app/signaller/interim_actor_probe
	var/obj/item/radio/integrated/signal/test_radio

/datum/data/pda/app/signaller/interim_actor_probe/signal_radio()
	return test_radio

/datum/unit_test/interim_pda_signal_actor_cooldown/Run()
	test_driver_begin()
	set_global("lastsignalers", GLOB.lastsignalers.Copy())
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/radio/integrated/signal/interim_actor_probe/sender = allocate(/obj/item/radio/integrated/signal/interim_actor_probe, T)
	var/obj/interim_pda_signal_receiver/receiver = allocate(/obj/interim_pda_signal_receiver, T)
	sender.set_frequency(INTERIM_PDA_SIGNAL_FREQUENCY)
	SSradio.add_object(receiver, INTERIM_PDA_SIGNAL_FREQUENCY)
	var/before_logs = length(GLOB.lastsignalers)
	var/datum/data/pda/app/signaller/interim_actor_probe/app = allocate(/datum/data/pda/app/signaller/interim_actor_probe)
	rel_set(app, nameof(app.test_radio), sender)
	op_ui_act(user, app, "signal")
	TEST_ASSERT_EQUAL(sender.actor_ref_seen, REF(user), "the real UI handler forwards its supplied actor")
	own(receiver.last_signal)
	TEST_ASSERT_EQUAL(receiver.received_count, 1, "the actual radio service delivers the first transmission")
	TEST_ASSERT_EQUAL(receiver.message_seen, "ACTIVATE", "the transmitted packet preserves its message")
	TEST_ASSERT_EQUAL(receiver.encryption_seen, sender.code, "the packet preserves the sender's configured code")
	TEST_ASSERT_EQUAL(receiver.source_ref_seen, REF(sender), "the actual sender is the packet source")
	TEST_ASSERT_EQUAL(length(GLOB.lastsignalers), before_logs + 1, "the clientless transmission retains its audit entry")
	TEST_ASSERT(findtext(GLOB.lastsignalers[before_logs + 1], "[user?.key] used [sender]"), "the audit entry formats the supplied actor's actual key")
	sender.send_signal("BLOCKED", user)
	TEST_ASSERT_EQUAL(receiver.received_count, 1, "cooldown blocks a second immediate transmission")
	TEST_ASSERT_EQUAL(length(GLOB.lastsignalers), before_logs + 1, "blocked transmission adds no misleading audit entry")
	// Legacy radio cooldowns read world.time, not the injected entity clock.
	wait_ticks(round((1 SECOND) / world.tick_lag) + 1)
	TEST_ASSERT(COOLDOWN_FINISHED(sender, transmission_cooldown), "real world time exceeds the legacy radio cooldown")
	sender.send_signal("SECOND", user)
	own(receiver.last_signal)
	TEST_ASSERT_EQUAL(receiver.received_count, 2, "real world clock advancement permits the next transmission")
	TEST_ASSERT_EQUAL(receiver.message_seen, "SECOND", "the later packet carries its distinct message")
	TEST_ASSERT_EQUAL(length(GLOB.lastsignalers), before_logs + 2, "the later real transmission is logged")

#undef INTERIM_PDA_SIGNAL_FREQUENCY
