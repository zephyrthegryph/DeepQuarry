#define INTERIM_IC_INPUT_SELECTOR "input"

/// Observe actual audible delivery while retaining the real mob message implementation.
/mob/living/carbon/human/interim_ic_beep_listener
	var/beeps_heard = 0

/mob/living/carbon/human/interim_ic_beep_listener/show_message(msg, type, alt, alt_type)
	if(istext(msg) && findtext(msg, "*beep* *beep*"))
		beeps_heard++
	return ..()

/// Automatic radio reception has recipients, not an ambient clicking actor.
/datum/unit_test/interim_ic_signal_recipient/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/interim_ic_beep_listener/listener = allocate(/mob/living/carbon/human/interim_ic_beep_listener, T)
	var/obj/item/integrated_circuit/input/signaler/circuit = allocate(/obj/item/integrated_circuit/input/signaler, T)
	var/obj/item/binoculars/source = allocate(/obj/item/binoculars, T)
	var/datum/signal/packet = allocate(/datum/signal)
	rel_set(packet, nameof(packet.source), source)
	packet.encryption = circuit.get_pin_data(INTERIM_IC_INPUT_SELECTOR, 2) + 1
	circuit.receive_signal(packet)
	TEST_ASSERT_EQUAL(listener.beeps_heard, 0, "incorrect encryption produces no audible receive notification")
	packet.encryption = circuit.get_pin_data(INTERIM_IC_INPUT_SELECTOR, 2)
	circuit.receive_signal(packet)
	TEST_ASSERT_EQUAL(listener.beeps_heard, 1, "a real clientless recipient receives the accepted signal's beep")
	rel_set(packet, nameof(packet.source), circuit)
	circuit.receive_signal(packet)
	TEST_ASSERT_EQUAL(listener.beeps_heard, 1, "the circuit ignores its own signal without another beep")

#undef INTERIM_IC_INPUT_SELECTOR
