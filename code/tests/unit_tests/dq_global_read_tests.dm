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
