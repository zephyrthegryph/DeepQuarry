// Reads through global state (tools/analyze/src/sem/reads.rs GlobalRead, code/engine/change/lookup_reads.dm rebind_global()): a window whose
// ui_data() reads `GLOB.news_network.wanted_issue().backup_author` is bound to the wanted issue the chain reaches, so a write of that field from
// anywhere (not the admin topic that used to refresh it by hand) pushes the window, and a new wanted issue re-binds the chain.

/// The window data of the admin newscaster panel follows the network's wanted issue: changing its backup author outside the admin topic pushes
/// the open window, and so does a new wanted issue, whose fields the chain then follows instead of the old one's.
/datum/unit_test/dq_global_read_wanted_issue_refreshes_window

/datum/unit_test/dq_global_read_wanted_issue_refreshes_window/Run()
	var/datum/feed_network/network = GLOB.news_network
	var/datum/feed_message/wanted = new
	wanted.set_author("Suspect")
	rel_set(network, nameof(/datum/feed_network::wanted_issue_owned), wanted)
	var/datum/newscaster_panel/panel = allocate(/datum/newscaster_panel)
	var/datum/tgui/dq_ui_probe/probe = allocate(/datum/tgui/dq_ui_probe)
	panel.add_open_tguis(probe)
	// What a real window does before its data push (/datum/tgui/prepare_lookup_reads()): bind the reads of its host under the window's scope.
	var/datum/lookup_read_scope/scope = allocate(/datum/lookup_read_scope)
	var/datum/act/eval/A = present_eval_context(panel, null)
	var/list/keys = lookup_reads_for(panel, null, A, scope)
	A.release()
	TEST_ASSERT(length(keys), "the panel's window data reads global chains: they are bound under the window's scope")
	dq_ui_frame()
	var/base = probe.pushes

	wanted.set_backup_author("Officer Ward")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, base + 1, "a write of the wanted issue's backup author outside the admin topic pushes the open window")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, base + 1, "a quiet frame pushes nothing")

	var/datum/feed_message/replacement = new
	rel_set(network, nameof(/datum/feed_network::wanted_issue_owned), replacement)
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, base + 2, "a new wanted issue pushes the window")
	replacement.set_backup_author("Officer Vale")
	dq_ui_frame()
	TEST_ASSERT_EQUAL(probe.pushes, base + 3, "the chain re-bound to the new wanted issue: its backup author pushes the window")

	panel.remove_open_tguis(probe)
	own_clear(network, nameof(/datum/feed_network::wanted_issue_owned), OWN_DELETE)

/// A draw that reads a global chain (the human's draw reads `GLOB.all_species[].race_key` for its icon key) binds it on the holder itself when the
/// holder attaches, with no window or op scope: a write of the field from anywhere redraws the holder. A chain through a var written per tick
/// (`GLOB.hair_styles_list[].flags`) is not bound for a draw (tools/analyze/src/gens/reads.rs draw_binds()), so no instance redraws each tick.
/datum/unit_test/dq_global_read_draw_binds_on_holder

/datum/unit_test/dq_global_read_draw_binds_on_holder/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/bound = list()
	var/list/unbound = list()
	for(var/list/spec as anything in H.generated_lookup_reads("draw"))
		if(!spec["global"])
			continue
		if(spec["static"])
			bound += list(spec)
		else
			unbound += list(spec)
	TEST_ASSERT(length(bound), "the human's draw reads a global chain the generator marks as bound on the holder")
	var/datum/lookup_read_scope/scope = lookup_static_scope(H)
	for(var/list/spec as anything in bound)
		var/key = "[handle_text(handle_of(H))]|[spec["key"]]|[handle_text(handle_of(H))]" // root "holder": the holder itself (lookup_read_scope/ensure())
		var/datum/lookup_read_binding/binding = scope.bindings?[key]
		TEST_ASSERT_NOTNULL(binding, "[spec["field"]] through [spec["global"]]: bound in the human's own scope from its attach, no window open")
		if(!binding)
			continue
		var/datum/species/S = GLOB.all_species[H.species.name]
		if(spec["field"] == "race_key" && S)
			var/list/readers = GLOB.lookup_read_index["[REF(S)]|race_key"]
			TEST_ASSERT(binding in readers, "the binding watches the registered species' race_key: a write of it redraws the human")
	for(var/list/spec as anything in unbound)
		TEST_ASSERT_NOTEQUAL(spec["field"], "race_key", "race_key is written by no per-tick path: it is bound")

/// Counts the re-checks a relation write of a system starts (a stand-in for a waiting op: GLOB.op_watchers names it).
/datum/pending_op/dq_rel_write_probe
	var/rechecks = 0

/datum/pending_op/dq_rel_write_probe/reads_changed()
	rechecks++

/// A requirement that reads a relation list of a system (the supply console's order_listed() reads SSsupply.order_history) reads it as a system
/// read: the analyzer counts rel_add / rel_remove as writes of the var (tools/analyze/src/sem/globals.rs), and the relation write publishes on the
/// system, so an op waiting on the requirement re-checks when an order is added or removed.
/datum/unit_test/dq_global_read_relation_write_rechecks_req

/datum/unit_test/dq_global_read_relation_write_rechecks_req/Run()
	var/list/row = GLOB.generated_reads_table["/obj/machinery/computer/supplycomp::order_listed"]
	TEST_ASSERT(islist(row), "the reads table has the supply console's order_listed requirement")
	var/found = FALSE
	for(var/i in 2 to length(row))
		var/list/read = row[i]
		if(read[2] == SREAD_KIND_SYSTEM && GLOB.generated_read_roots[read[1]] == "system:supply" && GLOB.generated_read_names[read[3]] == "order_history")
			found = TRUE
	TEST_ASSERT(found, "order_listed reads SSsupply.order_history as a system read")
	var/datum/pending_op/dq_rel_write_probe/probe = new
	var/index = "[REF(SSsupply)]|order_history"
	rx_watch_adjust(SSsupply, "order_history", 1)
	var/list/on = GLOB.op_watchers[index]
	if(!on)
		on = list()
		GLOB.op_watchers[index] = on
	on |= probe
	var/datum/supply_order/order = allocate(/datum/supply_order)
	rel_add(SSsupply, nameof(/datum/system/supply::order_history), order)
	var/after_add = probe.rechecks
	rel_take(SSsupply, nameof(/datum/system/supply::order_history), member = order)
	var/after_remove = probe.rechecks
	on -= probe
	if(!length(on))
		GLOB.op_watchers -= index
	rx_watch_adjust(SSsupply, "order_history", -1)
	TEST_ASSERT(after_add >= 1, "adding an order re-checks the waiting requirement (rechecks: [after_add])")
	TEST_ASSERT(after_remove > after_add, "taking it out re-checks it again (rechecks: [after_remove])")
