// Pin the actual compiled op requirement before and after callback conversion.
// This deliberately isolates the owner/token/UI-entry authorization layer; existing Topic authorization tests cover that layer.
// No copied callback logic, no Boolean callback return assertions, no holder gate override.
/datum/unit_test/dq_requirement_boundary_pin

/datum/unit_test/dq_requirement_boundary_pin/proc/check(datum/holder, mob/actor, key, callback, expected)
	var/datum/op_plan/P = op_plan_for(holder, key)
	TEST_ASSERT_NOTNULL(P, "the real [holder.type] [key] plan exists")
	var/datum/entry/part/req/selected
	var/matches = 0
	for(var/datum/entry/part/req/R as anything in P.needs)
		if(LAZYACCESS(R.args, "what") == callback)
			selected = R
			matches++
	TEST_ASSERT_EQUAL(matches, 1, "exactly one real compiled requirement names [callback]")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder
	A.actor = actor
	A.target = holder
	A.oplan = P
	A.authority = AUTH_ADMIN // the engine-supported authority, not fabricated client rights
	var/actual = op_req_holds(A, selected) ? null : op_req_refusal(A, selected)
	A.release()
	TEST_ASSERT_EQUAL(actual, expected, "the real compiled requirement returns the same null-or-refusal view")

/datum/unit_test/dq_requirement_boundary_pin/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.equip_to_slot_or_del(allocate(/obj/item/clothing/under/color/grey, H.loc), SLOT_ID_UNIFORM)
	var/obj/item/card/id/I = allocate(/obj/item/card/id, H.loc)
	var/datum/computer_file/program/digitalwarrant/W = allocate(/datum/computer_file/program/digitalwarrant)
	check(W, H, "addwarrant", "warrant_id_ok", MSG(digitalwarrant/no_id))
	I.registered_name = ""
	I.access = list(ACCESS_SECURITY)
	H.equip_to_slot(I, SLOT_ID_ID)
	TEST_ASSERT_EQUAL(H.GetIdCard(), I, "actual actor ID lookup sees the equipped card")
	check(W, H, "addwarrant", "warrant_id_ok", MSG(digitalwarrant/no_id))
	I.registered_name = "Boundary Tester"
	I.access = list()
	check(W, H, "addwarrant", "warrant_id_ok", MSG(digitalwarrant/no_id))
	I.access = list(ACCESS_SECURITY)
	check(W, H, "addwarrant", "warrant_id_ok", null)
	var/datum/computer_file/program/email_administration/E = allocate(/datum/computer_file/program/email_administration)
	check(E, H, "back", "network_admin_access", /datum/msg/req_silent)
	I.access = list(ACCESS_NETWORK)
	check(E, H, "back", "network_admin_access", null)
	check(E, H, "changepass", "has_account", /datum/msg/req_silent)
	var/datum/computer_file/data/email_account/account = allocate(/datum/computer_file/data/email_account, TRUE) // existing glob_load argument avoids registering this isolated account into the live network
	rel_set(E, nameof(/datum/computer_file/program/email_administration::current_account), account)
	check(E, H, "changepass", "has_account", null)
	TEST_ASSERT_EQUAL(E.current_account(), account, "requirement evaluation does not mutate account selection")
	var/datum/computer_file/program/ntnetmonitor/N = allocate(/datum/computer_file/program/ntnetmonitor)
	var/datum/ntnet = GLOB.ntnet_global
	TEST_ASSERT_NOTNULL(ntnet, "the real booted network provides allow-state coverage")
	set_global("ntnet_global", null)
	check(N, H, "ban_nid", "ntnet_present", /datum/msg/req_silent)
	GLOB.ntnet_global = ntnet
	check(N, H, "ban_nid", "ntnet_present", null)
	// Real rank and holder constructor, preserving the registry. No owner/token gate override.
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/datum/admin_rank/rank = allocate(/datum/admin_rank, "RequirementBoundaryRank", RANK_SOURCE_TXT, R_ADMIN|R_EVENT)
	var/datum/admins/admin = allocate(/datum/admins, list(rank), "dqreqboundaryadmin")
	defer_cleanup(src, PROC_REF(unregister_holder), admin)
	admin.set_admincaster_channel_ready(FALSE)
	check(admin, H, "ac_submit_new_channel", "ac_channel_ready", MSG(admin_topic/channel_unsubmittable))
	admin.set_admincaster_channel_ready(TRUE)
	check(admin, H, "ac_submit_new_channel", "ac_channel_ready", null)
	admin.set_admincaster_wanted_ready(FALSE)
	check(admin, H, "ac_submit_wanted", "ac_wanted_ready", MSG(admin_topic/wanted_unsubmittable))
	admin.set_admincaster_wanted_ready(TRUE)
	check(admin, H, "ac_submit_wanted", "ac_wanted_ready", null)
	set_config(/datum/config_entry/flag/allow_admin_jump, FALSE)
	check(admin, H, "getmob", "admin_jump_allowed", MSG(admin_topic/jump_disabled))
	set_config(/datum/config_entry/flag/allow_admin_jump, TRUE)
	check(admin, H, "getmob", "admin_jump_allowed", null)
	TEST_ASSERT_NOTNULL(SSticker, "the real booted ticker exists")
	var/datum/game_mode/real_mode = allocate(/datum/game_mode/extended)
	set_var(SSticker, "mode", real_mode)
	check(admin, H, "c_mode", "round_not_started", MSG(admin_topic/round_started))
	set_var(SSticker, "mode", null)
	check(admin, H, "c_mode", "round_not_started", null)
	set_global("master_mode", "extended")
	check(admin, H, "f_secret", "round_is_secret", MSG(admin_topic/not_secret))
	set_global("master_mode", "secret")
	check(admin, H, "f_secret", "round_is_secret", null)
	TEST_ASSERT_EQUAL(GLOB.master_mode, "secret", "the requirement did not mutate the real selection")

/datum/unit_test/dq_requirement_boundary_pin/proc/unregister_holder(datum/admins/holder)
	if(holder)
		GLOB.admin_datums -= holder.target
		GLOB.deadmins -= holder.target

// Old/new behavior pins at actual compiled native needs boundary.
// Host-window auth/effects also covered by existing dq_hc_tgui communications tests.
/datum/unit_test/dq_hc_tgui/proc/cbp(datum/host, mob/actor, key, callback, expected, list/values, authority = 0)
	var/datum/op_plan/P = op_plan_for(host, key)
	TEST_ASSERT_NOTNULL(P, "real [key] op exists")
	var/datum/entry/part/req/R
	var/found = 0
	for(var/datum/entry/part/req/candidate as anything in P.needs)
		if(LAZYACCESS(candidate.args, "what") == callback)
			R = candidate
			found++
	TEST_ASSERT_EQUAL(found, 1, "exact real compiled [callback] gate exists")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = host
	A.target = host
	A.actor = actor
	A.oplan = P
	A.args = values || list()
	A.authority = authority
	var/answer = op_req_holds(A, R) ? null : op_req_refusal(A, R)
	A.release()
	TEST_ASSERT_EQUAL(answer, expected, "[callback] preserves exact allow/refusal")

/datum/unit_test/dq_hc_tgui/comms_requirement_boundaries
/datum/unit_test/dq_hc_tgui/comms_requirement_boundaries/Run()
	set_global(nameof(GLOB.test_prompts), list())
	..()
/datum/unit_test/dq_hc_tgui/comms_requirement_boundaries/run_gate()
	var/datum/tgui_module/communications/M = hct_comms()
	var/mob/living/carbon/human/H = hct_actor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	cbp(M, H, "auth", "ui_is_human", null)
	cbp(M, R, "auth", "ui_is_human", MSG(communications/access_denied))
	cbp(M, H, "cancelshuttle", "ui_not_silicon", null)
	cbp(M, R, "cancelshuttle", "ui_not_silicon", MSG(communications/no_recall), null, AUTH_REMOTE_ACCESS)
	cbp(M, R, "cancelshuttle", "ui_not_silicon", null)
	M.set_login(H, 0)
	cbp(M, H, "status", "ui_logged_in", MSG(communications/access_denied))
	M.set_login(H, 1)
	cbp(M, H, "status", "ui_logged_in", null)
	cbp(M, H, "announce", "ui_captain", /datum/msg/req_silent)
	M.set_login(H, 2)
	cbp(M, H, "announce", "ui_captain", null)
	cbp(M, H, "auth", "ui_in_contact", null)
	using_map.contact_levels = list()
	cbp(M, H, "auth", "ui_in_contact", MSG(communications/out_of_range))
	using_map.contact_levels = list(H.z)
	COOLDOWN_START(M, message_cooldown, 1 SECOND)
	cbp(M, H, "announce", "announce_ready", MSG(communications/announce_cooldown))
	COOLDOWN_RESET(M, message_cooldown)
	cbp(M, H, "announce", "announce_ready", null)
	COOLDOWN_START(M, centcomm_message_cooldown, 1 SECOND)
	cbp(M, H, "MessageCentCom", "centcom_ready", MSG(communications/arrays_recycling))
	COOLDOWN_RESET(M, centcomm_message_cooldown)
	cbp(M, H, "MessageCentCom", "centcom_ready", null)
	cbp(M, H, "delmessage", "message_deletable", MSG(communications/cannot_delete), list("msgid" = 9001))
	var/obj/item/modular_computer/laptop/L = allocate(/obj/item/modular_computer/laptop, hct_spot())
	var/datum/computer_file/program/comm/program = hct_track(new /datum/computer_file/program/comm(L))
	var/datum/tgui_module/communications/local = hct_track(new /datum/tgui_module/communications(program))
	program.message_core.Add(list("id" = 9001, "title" = "Boundary", "contents" = "unchanged"))
	cbp(local, H, "delmessage", "message_deletable", null, list("msgid" = 9001))
	cbp(local, H, "delmessage", "message_deletable", MSG(communications/cannot_delete), list("msgid" = 9002))
	TEST_ASSERT(local.message_by_id(9001), "gate checks do not delete the message")
	var/obj/machinery/computer/communications/C = allocate(/obj/machinery/computer/communications, hct_spot())
	var/datum/tgui_module/communications/wired = C.communications
	wired.set_login(H, 2)
	cbp(wired, H, "MessageSyndicate", "ui_captain_emagged", /datum/msg/req_silent)
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, hct_spot())
	E.uses = 3
	H.put_in_active_hand(E)
	hci_click(H, C, E)
	test_time(1 SECOND)
	TEST_ASSERT(wired.routing_scrambled(), "real emag operation scrambled routing")
	cbp(wired, H, "MessageSyndicate", "ui_captain_emagged", null)
	wired.set_login(H, 1)
	cbp(wired, H, "MessageSyndicate", "ui_captain_emagged", /datum/msg/req_silent)

/datum/unit_test/dq_hc_tgui/appearance_cooldown_boundary
/datum/unit_test/dq_hc_tgui/appearance_cooldown_boundary/Run()
	set_global(nameof(GLOB.test_prompts), list())
	..()
/datum/unit_test/dq_hc_tgui/appearance_cooldown_boundary/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/tgui_module/appearance_changer/M = hct_track(new /datum/tgui_module/appearance_changer(hct_host(), H))
	COOLDOWN_START(M, cooldown, 1 SECOND)
	cbp(M, H, "blood_color", "ui_cooled", MSG(appearance_changer/too_fast))
	COOLDOWN_RESET(M, cooldown)
	cbp(M, H, "blood_color", "ui_cooled", null)

// Compare this sweep's affected trees against their old-code snapshots.
/datum/unit_test/dq_requirement_third_pin
	parent_type = /datum/unit_test/dq_conversion_pin
	capture_roots = list(/obj/item/airlock_electronics, /obj/machinery/computer/card, /obj/machinery/light/flamp, /obj/machinery/sleeper, /obj/machinery/vending, /obj/machinery/computer/scan_consolenew, /obj/machinery/oxygen_pump, /obj/machinery/computer/aifixer, /obj/machinery/computer/communications, /obj/machinery/autolathe, /obj/machinery/camera, /obj/machinery/suit_cycler, /obj/structure/bed, /obj/structure/bed/chair)
