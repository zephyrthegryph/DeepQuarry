// Behaviour tests for the telecommunications machines and their two consoles (rewrite/machines-full): what a person with a multitool, the world
// (power, damage) and the consoles observe, written against the legacy code first. Where the legacy code had a bug the test pins it as it was and
// the commit that fixes it edits the assertion (doc/rewrite/intended_changes.md). Fixture: the structure behaviour block (dq_hc_struct_behaviour.dm).

// ---- adapters: today's accessors (only these bodies change with the conversion) ----

/// The node passes signals now: switched on and working.
/proc/mftc_running(obj/machinery/telecomms/T)
	return !!T.running

/// The node is brought up to date with its power (a stat: nothing to do).
/proc/mftc_sync(obj/machinery/telecomms/T)
	return

// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/mftc
	abstract_type = /datum/unit_test/dq_hc_struct/mftc

/// A person at the machine with a multitool in hand.
/datum/unit_test/dq_hc_struct/mftc/proc/tech(turf/T)
	var/mob/living/carbon/human/H = person(T)
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	return H

/datum/unit_test/dq_hc_struct/mftc/proc/node(type = /obj/machinery/telecomms/relay, turf/T)
	return mach(type, T || tile(3, 2))

/// The power button switches the node off and on; switched off it passes nothing and shows it.
/datum/unit_test/dq_hc_struct/mftc/toggle_switches_the_node
/datum/unit_test/dq_hc_struct/mftc/toggle_switches_the_node/run_gate()
	var/mob/living/carbon/human/H = tech()
	var/obj/machinery/telecomms/relay/R = node()
	mftc_sync(R)
	TEST_ASSERT(mftc_running(R), "(a powered node runs)")
	press(H, R, "toggle")
	mftc_sync(R)
	TEST_ASSERT(!mftc_running(R), "switched off it stops")
	TEST_ASSERT(findtext(R.icon_state, "_off"), "and shows it")
	press(H, R, "toggle")
	mftc_sync(R)
	TEST_ASSERT(mftc_running(R), "switched on it runs again")

/// A node that loses its power stops, and runs again when the power is back.
/datum/unit_test/dq_hc_struct/mftc/a_node_follows_its_power
/datum/unit_test/dq_hc_struct/mftc/a_node_follows_its_power/run_gate()
	var/obj/machinery/telecomms/relay/R = node()
	mftc_sync(R)
	dq_machine_clear(R)
	R.set_grid_power(FALSE)
	mftc_sync(R)
	TEST_ASSERT(!mftc_running(R), "an unpowered node stops")
	R.set_grid_power(TRUE)
	mftc_sync(R)
	TEST_ASSERT(mftc_running(R), "and runs again with power")

/// The relay's receive and broadcast switches flip.
/datum/unit_test/dq_hc_struct/mftc/relay_switches
/datum/unit_test/dq_hc_struct/mftc/relay_switches/run_gate()
	var/mob/living/carbon/human/H = tech()
	var/obj/machinery/telecomms/relay/R = node()
	var/receiving = R.receiving
	var/broadcasting = R.broadcasting
	press(H, R, "receive")
	press(H, R, "broadcast")
	TEST_ASSERT_NOTEQUAL(!!R.receiving, !!receiving, "receiving flips")
	TEST_ASSERT_NOTEQUAL(!!R.broadcasting, !!broadcasting, "broadcasting flips")

/// The multitool's buffer: store a node, link another to it (both list each other), unlink, flush.
/datum/unit_test/dq_hc_struct/mftc/link_through_the_buffer
/datum/unit_test/dq_hc_struct/mftc/link_through_the_buffer/run_gate()
	var/mob/living/carbon/human/H = tech()
	var/obj/item/multitool/M = H.get_active_hand()
	var/obj/machinery/telecomms/relay/A = node()
	var/obj/machinery/telecomms/hub/B = node(/obj/machinery/telecomms/hub, tile(4, 2))
	press(H, B, "buffer")
	TEST_ASSERT_EQUAL(M.buffer(), B, "the buffer holds the hub")
	press(H, A, "link")
	TEST_ASSERT(B in A.links, "the relay links the buffered hub")
	TEST_ASSERT(A in B.links, "and the hub lists the relay")
	press(H, A, "unlink", list("unlink" = 1))
	TEST_ASSERT(!(B in A.links) && !(A in B.links), "unlinked, neither lists the other")
	press(H, A, "flush")
	TEST_ASSERT_NULL(M.buffer(), "the buffer is flushed")

/// A frequency filter is added through a question and removed by its button.
/datum/unit_test/dq_hc_struct/mftc/frequency_filters
/datum/unit_test/dq_hc_struct/mftc/frequency_filters/run_gate()
	var/mob/living/carbon/human/H = tech()
	var/obj/machinery/telecomms/relay/R = node()
	press(H, R, "freq")
	TEST_ASSERT(asked(H), "the filter is asked for")
	hci_answer(H, 145.9)
	settle()
	TEST_ASSERT(1459 in R.freq_listening, "the frequency is filtered (in tenths)")
	press(H, R, "delete", list("delete" = 1459))
	TEST_ASSERT(!(1459 in R.freq_listening), "and the filter comes off")

/// The bus's frequency changer is set through a question.
/datum/unit_test/dq_hc_struct/mftc/bus_changes_frequencies
/datum/unit_test/dq_hc_struct/mftc/bus_changes_frequencies/run_gate()
	var/mob/living/carbon/human/H = tech()
	var/obj/machinery/telecomms/bus/B = node(/obj/machinery/telecomms/bus)
	press(H, B, "change_freq")
	TEST_ASSERT(asked(H), "the new frequency is asked for")
	hci_answer(H, 135.7)
	settle()
	TEST_ASSERT_EQUAL(B.change_frequency, 1357, "signals are moved to that frequency")

/// The broadcaster's range is clamped to what it can do.
/datum/unit_test/dq_hc_struct/mftc/broadcaster_range
/datum/unit_test/dq_hc_struct/mftc/broadcaster_range/run_gate()
	var/mob/living/carbon/human/H = tech()
	var/obj/machinery/telecomms/broadcaster/B = node(/obj/machinery/telecomms/broadcaster)
	press(H, B, "range", list("range" = 99))
	TEST_ASSERT_EQUAL(B.overmap_range, B.overmap_range_max, "a range past the top is the top")
	press(H, B, "range", list("range" = 1))
	TEST_ASSERT_EQUAL(B.overmap_range, 1, "a range in reach is taken")

/// Nanopaste repairs a damaged node and is used up; on a whole node nothing is spent.
/datum/unit_test/dq_hc_struct/mftc/nanopaste_repairs
/datum/unit_test/dq_hc_struct/mftc/nanopaste_repairs/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/telecomms/relay/R = node()
	var/obj/item/stack/nanopaste/N = allocate(/obj/item/stack/nanopaste, tile(2, 2))
	N.set_amount(5)
	H.put_in_active_hand(N)
	hci_click(H, R, N)
	settle()
	TEST_ASSERT_EQUAL(N.get_amount(), 5, "a whole node takes no paste")
	R.take_damage(50)
	var/damaged = R.get_integrity()
	hci_click(H, R, N)
	settle()
	TEST_ASSERT(R.get_integrity() > damaged, "a damaged node is repaired")
	TEST_ASSERT_EQUAL(N.get_amount(), 4, "with one use of the paste")

/// The log browser probes the servers of its network, shows one, and deletes a log entry for someone with the access.
/datum/unit_test/dq_hc_struct/mftc/log_browser_probes_and_deletes
/datum/unit_test/dq_hc_struct/mftc/log_browser_probes_and_deletes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/telecomms/server/S = node(/obj/machinery/telecomms/server, tile(5, 2))
	S.network = "mftc"
	S.id = "mftc server"
	S.add_entry("hello", "Test File")
	S.add_entry("again", "Test File")
	var/obj/machinery/computer/telecomms/server/C = mach(/obj/machinery/computer/telecomms/server, tile(3, 2))
	C.network = "mftc"
	press(H, C, "scan")
	TEST_ASSERT(S in C.servers, "the probe finds the network's server")
	press(H, C, "view", list("id" = "mftc server"))
	TEST_ASSERT_EQUAL(C.SelectedServer(), S, "the server is shown")
	var/before = length(S.log_entries)
	press(H, C, "delete", list("id" = 1))
	TEST_ASSERT_EQUAL(length(S.log_entries), before, "without the access nothing is deleted")
	C.req_access = list()
	press(H, C, "delete", list("id" = 1))
	TEST_ASSERT_EQUAL(length(S.log_entries), before - 1, "with it the entry is deleted")

/// The network monitor probes the machines of its network and shows one with its links.
/datum/unit_test/dq_hc_struct/mftc/monitor_probes
/datum/unit_test/dq_hc_struct/mftc/monitor_probes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/telecomms/relay/R = node()
	R.network = "mftc"
	R.id = "mftc relay"
	var/obj/machinery/computer/telecomms/monitor/C = mach(/obj/machinery/computer/telecomms/monitor, tile(5, 2))
	C.network = "mftc"
	press(H, C, "scan")
	TEST_ASSERT(R in C.machinelist, "the probe finds the network's node")
	press(H, C, "view", list("id" = "mftc relay"))
	TEST_ASSERT_EQUAL(C.SelectedMachine(), R, "the node is shown")
	press(H, C, "release")
	TEST_ASSERT(!length(C.machinelist), "release empties the buffer")
