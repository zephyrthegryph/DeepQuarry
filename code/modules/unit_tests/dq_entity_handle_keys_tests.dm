// Lists that named an entity by a REF() text or a counter now key it by its handle, ref_token() (relations.md D9a, lint entity_ids).

/// The per-host panel index is keyed by the host's handle: opening twice finds the same panel, and the panel leaving drops its row.
/datum/unit_test/dq_entity_handle_panel_index/Run()
	var/mob/living/carbon/human/host = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/viewer = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	dq_open_languages_panel(host, viewer)
	var/key = ref_token(host)
	var/datum/languages_panel/panel = resolve_token(GLOB.dq_languages_panels[key])
	TEST_ASSERT_NOTNULL(panel, "the panel is indexed by the host's handle")
	dq_open_languages_panel(host, viewer)
	TEST_ASSERT_EQUAL(resolve_token(GLOB.dq_languages_panels[key]), panel, "a second open finds the same panel")
	qdel(panel)
	TEST_ASSERT(!(key in GLOB.dq_languages_panels), "the panel leaving drops its row")

/// The missed-wake audit holds its members by handle: a deleted member drops out at its next sample.
/datum/unit_test/dq_entity_handle_sleep_audit/Run()
	var/datum/member = new /datum
	sleep_audit_join(member)
	var/key = ref_token(member)
	TEST_ASSERT(GLOB.sleep_audited[key], "a member joins under its handle")
	qdel(member)
	sleep_audit(100000, FALSE)
	TEST_ASSERT(!(key in GLOB.sleep_audited), "a deleted member drops out at the next sample")

/// An NTNet transfer server is named to the window by its handle; a download names it back as the server itself.
/datum/unit_test/dq_entity_handle_nttransfer_server/Run()
	var/datum/computer_file/program/nttransfer/server = allocate(/datum/computer_file/program/nttransfer)
	var/datum/computer_file/program/nttransfer/client = allocate(/datum/computer_file/program/nttransfer)
	TEST_ASSERT_NULL(client.server_with_uid(server), "a program that serves nothing is not a server")
	rel_add(GLOB.ntnet_global, nameof(/datum/ntnet::fileservers), server)
	TEST_ASSERT_EQUAL(client.server_with_uid(server), server, "a listed server is found")
	TEST_ASSERT_EQUAL(resolve_window_ref(ref_token(server)), server, "the handle the window holds resolves to the server")
	rel_remove(GLOB.ntnet_global, nameof(/datum/ntnet::fileservers), server)
