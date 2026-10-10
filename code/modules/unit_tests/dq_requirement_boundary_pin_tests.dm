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

// OLD-code boundary pins: evaluate the actual compiled req_bool before conversion,
// and the same compiled req afterwards. No callback-result shape assertion.
/datum/unit_test/dq_requirement_fourth_boundary

/datum/unit_test/dq_requirement_fourth_boundary/proc/check(datum/holder, mob/actor, key, callback, expected, obj/held = null, atom/target = null)
	var/datum/op_plan/P = op_plan_for(holder, key)
	TEST_ASSERT_NOTNULL(P, "The real [holder.type] [key] op exists")
	var/datum/entry/part/req/selected
	var/matches = 0
	for(var/datum/entry/part/req/R as anything in P.needs)
		if(LAZYACCESS(R.args, "what") == callback)
			selected = R
			matches++
	TEST_ASSERT_EQUAL(matches, 1, "Exactly one real compiled requirement names [callback]")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder
	A.actor = actor
	A.held = held
	A.target = target || holder
	A.oplan = P
	var/actual = op_req_holds(A, selected) ? null : op_req_refusal(A, selected)
	A.release()
	TEST_ASSERT_EQUAL(actual, expected, "[key]/[callback] preserves exact allow/refusal")

/datum/unit_test/dq_requirement_fourth_boundary/tape/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/tape_roll/tape = allocate(/obj/item/tape_roll, H.loc)
	for(var/key in list("tape_eyes", "tape_mouth"))
		check(tape, H, key, "firm_grip", null, tape, H)
		check(tape, H, key, "firm_grip", /datum/msg/tape/no_grip, tape, other)
		check(tape, H, key, "face_free", null, tape, H)
	var/obj/item/clothing/head/hardhat/firefighter/helmet = allocate(/obj/item/clothing/head/hardhat/firefighter, H.loc)
	TEST_ASSERT(H.equip_to_slot_if_possible(helmet, SLOT_ID_HEAD, disable_warning = TRUE), "The actual face-covering helmet equips")
	TEST_ASSERT_EQUAL(H.get_equipped_item(SLOT_ID_HEAD), helmet, "The native equipped-item lookup sees the helmet")
	TEST_ASSERT(helmet.body_parts_covered & FACE, "The actual helmet covers the face")
	for(var/key in list("tape_eyes", "tape_mouth"))
		check(tape, H, key, "face_free", span_warning("Remove their [helmet] first."), tape, H)
	TEST_ASSERT(H.unEquip(helmet), "The helmet can actually be removed")
	TEST_ASSERT_NULL(H.get_equipped_item(SLOT_ID_HEAD), "The head slot is actually empty again")
	for(var/key in list("tape_eyes", "tape_mouth"))
		check(tape, H, key, "face_free", null, tape, H)

/datum/unit_test/dq_requirement_fourth_boundary/tray/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/portable_atmospherics/hydroponics/tray = allocate(/obj/machinery/portable_atmospherics/hydroponics, H.loc)
	tray.set_anchored(TRUE)
	check(tray, H, "freezer", "is_anchored", null)
	tray.set_anchored(FALSE)
	check(tray, H, "freezer", "is_anchored", /datum/msg/hydroponics/anchor_first)
	tray.set_anchored(TRUE)
	check(tray, H, "freezer", "is_anchored", null)
	tray.set_frozen(-1)
	check(tray, H, "freezer", "can_freeze", /datum/msg/hydroponics/no_freezer)
	tray.set_frozen(0)
	check(tray, H, "freezer", "can_freeze", null)
	tray.set_frozen(1)
	check(tray, H, "freezer", "can_freeze", null)
	for(var/key in list("toggle_lid", "remove_label", "set_light"))
		check(tray, H, key, "actor_can_act", null)
	// The legacy helper checks living actors with the default restraint flags;
	// it does not use the separate op-capable stun/consciousness requirement.
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, H.loc)
	for(var/key in list("toggle_lid", "remove_label", "set_light"))
		check(tray, ghost, key, "actor_can_act", /datum/msg/hydroponics/not_by_this)
	for(var/key in list("toggle_lid", "remove_label", "set_light"))
		check(tray, H, key, "actor_can_act", null)

/datum/unit_test/dq_requirement_fourth_boundary/seed_storage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/seed_storage/storage = allocate(/obj/machinery/seed_storage, H.loc)
	var/obj/item/seeds/tomatoseed/seed = allocate(/obj/item/seeds/tomatoseed, H.loc)
	var/obj/item/storage/bag/plants/bag = allocate(/obj/item/storage/bag/plants, H.loc)
	storage.lockdown = FALSE
	check(storage, H, "insert_seeds", "not_locked_down_holds", null, seed)
	check(storage, H, "insert_bag", "not_locked_down_holds", null, bag)
	storage.lockdown = TRUE
	check(storage, H, "insert_seeds", "not_locked_down_holds", "it's locked down", seed)
	check(storage, H, "insert_bag", "not_locked_down_holds", "it's locked down", bag)
	storage.lockdown = FALSE
	check(storage, H, "insert_seeds", "not_locked_down_holds", null, seed)
	check(storage, H, "insert_bag", "not_locked_down_holds", null, bag)

// No connected-ghost success test: candidate_refusal() requires a genuine client
// and ckey plus live respawn/ban eligibility. A clientless allocated observer
// can prove only a silent refusal; fabricating eligibility would hide that gap.

// Old/new compiled requirement boundary, not copied callback Boolean results.
/datum/unit_test/dq_requirement_boundary_pin/machines_d/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/space_heater/heater = allocate(/obj/machinery/space_heater, H.loc)
	heater.set_panel_open(FALSE)
	check(heater, H, "temp", "ui_gate", /datum/msg/req_silent)
	heater.set_panel_open(TRUE)
	check(heater, H, "temp", "ui_gate", null)
	heater.set_panel_open(FALSE)
	check(heater, H, "temp", "ui_gate", /datum/msg/req_silent)
	var/obj/machinery/suit_storage_unit/storage = allocate(/obj/machinery/suit_storage_unit, H.loc)
	storage.set_isbroken(FALSE)
	storage.set_isUV(FALSE)
	check(storage, H, "door", "ui_gate", null)
	storage.set_isUV(TRUE)
	check(storage, H, "door", "ui_gate", /datum/msg/req_silent)
	storage.set_isUV(FALSE)
	storage.set_isbroken(TRUE)
	check(storage, H, "door", "ui_gate", /datum/msg/req_silent)
	storage.set_isbroken(FALSE)
	check(storage, H, "door", "ui_gate", null)
	var/obj/structure/AIcore/core = allocate(/obj/structure/AIcore, H.loc)
	check(core, H, "wrench_wrong_stage", "construction_tool_blocked", /datum/msg/req_silent)
	check(core, H, "welder_wrong_stage", "construction_tool_blocked", /datum/msg/req_silent)

// Compiled requirement-only boundary. Does not bypass or claim admin UI authorization.
/datum/unit_test/dq_requirement_boundary_pin/player_effects/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, H.loc)
	var/datum/eventkit/player_effects/E = allocate(/datum/eventkit/player_effects)
	var/list/human_ops = list("damage_organ", "assist_organ", "robot_organ", "repair_organ", "drop_organ", "break_bone", "give_chem", "darksight", "lleill_energy", "drop_all", "drop_specific")
	check(E, H, "give_quest", "has_target", /datum/msg/req_silent)
	for(var/key in human_ops)
		check(E, H, key, "target_human", /datum/msg/req_silent)
	rel_set(E, nameof(/datum/eventkit/player_effects::target), R)
	check(E, H, "give_quest", "has_target", null)
	for(var/key in human_ops)
		check(E, H, key, "target_human", /datum/msg/req_silent)
	rel_set(E, nameof(/datum/eventkit/player_effects::target), H)
	check(E, H, "give_quest", "has_target", null)
	for(var/key in human_ops)
		check(E, H, key, "target_human", null)
	rel_set(E, nameof(/datum/eventkit/player_effects::target), null)
	check(E, H, "give_quest", "has_target", /datum/msg/req_silent)
	for(var/key in human_ops)
		check(E, H, key, "target_human", /datum/msg/req_silent)
	TEST_ASSERT_NULL(E.target(), "Compiled checks preserve the actual target relation")

/datum/unit_test/dq_requirement_fourth_boundary/botany/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/botany/extractor/E = allocate(/obj/machinery/botany/extractor, H.loc)
	var/obj/machinery/botany/editor/editor = allocate(/obj/machinery/botany/editor, H.loc)
	var/obj/item/seeds/tomatoseed/S = allocate(/obj/item/seeds/tomatoseed, H.loc)
	var/obj/item/disk/botany/D = allocate(/obj/item/disk/botany, H.loc)
	check(E, H, "load_seed", "botany_no_seed_holds", null, S)
	rel_set(E, nameof(E.seed), S)
	check(E, H, "load_seed", "botany_no_seed_holds", "there is already a seed loaded", S)
	rel_set(E, nameof(E.seed), null)
	check(E, H, "load_seed", "botany_no_seed_holds", null, S)
	check(E, H, "load_disk", "botany_disk_slot_holds", null, D)
	check(editor, H, "load_disk", "botany_disk_slot_holds", "that disk does not have any gene data loaded", D)
	var/datum/plantgene/G = allocate(/datum/plantgene)
	rel_add(D, nameof(D.genes), G)
	check(E, H, "load_disk", "botany_disk_slot_holds", "that disk already has gene data loaded", D)
	check(editor, H, "load_disk", "botany_disk_slot_holds", null, D)
	rel_set(editor, nameof(editor.loaded_disk), D)
	check(editor, H, "load_disk", "botany_disk_slot_holds", "there is already a data disk loaded", D)
	rel_set(editor, nameof(editor.loaded_disk), null)
	check(editor, H, "load_disk", "botany_disk_slot_holds", null, D)
	rel_remove(D, nameof(D.genes), G)
	check(E, H, "load_disk", "botany_disk_slot_holds", null, D)

/datum/unit_test/dq_requirement_fourth_boundary/beehive/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/beehive/B = allocate(/obj/machinery/beehive, H.loc)
	var/obj/item/honey_frame/F = allocate(/obj/item/honey_frame, H.loc)
	var/obj/item/bee_pack/P = allocate(/obj/item/bee_pack, H.loc)
	B.set_closed(FALSE)
	check(B, H, "beehive_load_frame", "can_load_frame_holds", null, F)
	B.set_closed(TRUE)
	check(B, H, "beehive_load_frame", "can_load_frame_holds", "you need to open \the [B] with a crowbar before inserting \the [F]", F)
	B.set_closed(FALSE)
	F.set_honey(20)
	check(B, H, "beehive_load_frame", "can_load_frame_holds", "\The [F] is full with beeswax and honey, empty it in the extractor first", F)
	F.set_honey(0)
	check(B, H, "beehive_load_frame", "can_load_frame_holds", null, F)
	var/list/obj/item/honey_frame/capacity_frames
	for(var/i in 1 to B.maxFrames)
		var/obj/item/honey_frame/inside = allocate(/obj/item/honey_frame, B)
		LAZYADD(capacity_frames, inside)
		rel_add(B, nameof(B.frames), inside)
	check(B, H, "beehive_load_frame", "can_load_frame_holds", "there is no place for an another frame", F)
	for(var/obj/item/honey_frame/inside as anything in capacity_frames)
		rel_remove(B, nameof(B.frames), inside)
	check(B, H, "beehive_load_frame", "can_load_frame_holds", null, F)
	check(B, H, "use_screwdriver", "can_dismantle_holds", null)
	rel_add(B, nameof(B.frames), F)
	check(B, H, "use_screwdriver", "can_dismantle_holds", span_notice("You can't dismantle the hive with 1 frames still inside!"))
	rel_remove(B, nameof(B.frames), F)
	B.set_bee_count(20)
	check(B, H, "use_screwdriver", "can_dismantle_holds", span_notice("You can't dismantle the hive with these bees inside."))
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", "\The [B] already has bees inside", P)
	B.set_bee_count(0)
	check(B, H, "use_screwdriver", "can_dismantle_holds", null)
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", null, P)
	P.set_full(FALSE)
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", "\The [B] is not ready to split", P)
	B.set_bee_count(90)
	B.set_smoked(0)
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", "smoke \the [B] first", P)
	B.set_smoked(30)
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", null, P)
	B.set_closed(TRUE)
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", "you need to open \the [B] with a crowbar before moving the bees", P)
	B.set_closed(FALSE)
	check(B, H, "beehive_bee_pack", "can_move_bees_holds", null, P)

/datum/unit_test/dq_requirement_fourth_boundary/honey_extractor/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/honey_extractor/E = allocate(/obj/machinery/honey_extractor, H.loc)
	var/obj/item/honey_frame/F = allocate(/obj/item/honey_frame, H.loc)
	E.set_powered(TRUE)
	E.set_panel_open(FALSE)
	E.set_processing(0)
	check(E, H, "honey_extractor_load_frame", "ready_for_item_holds", null, F)
	E.set_processing(20)
	check(E, H, "honey_extractor_load_frame", "ready_for_item_holds", "it's currently spinning, wait until it's finished", F)
	E.set_processing(0)
	E.set_powered(FALSE)
	TEST_ASSERT(E.power_lost(), "The actual machine power stat becomes unavailable")
	check(E, H, "honey_extractor_load_frame", "ready_for_item_holds", "it's powerless and can't grant your wishes", F)
	E.set_powered(TRUE)
	E.set_panel_open(TRUE)
	check(E, H, "honey_extractor_load_frame", "ready_for_item_holds", "its maintenance panel is open, it would not be safe to turn it on", F)
	E.set_panel_open(FALSE)
	check(E, H, "honey_extractor_load_frame", "ready_for_item_holds", null, F)
	check(E, H, "honey_extractor_load_frame", "can_extract_frame_holds", "\The [F] is empty, put it into a beehive", F)
	F.set_honey(20)
	check(E, H, "honey_extractor_load_frame", "can_extract_frame_holds", null, F)
	F.set_honey(0)
	check(E, H, "honey_extractor_load_frame", "can_extract_frame_holds", "\The [F] is empty, put it into a beehive", F)

// Scoped old/new snapshot comparison for the fourth requirement cohort.
/datum/unit_test/dq_requirement_fourth_pin
	parent_type = /datum/unit_test/dq_conversion_pin
	capture_roots = list(/obj/item/beehive_assembly, /obj/item/bodybag, /obj/item/card/id/guest, /obj/item/disk/botany, /obj/item/ducttape, /obj/item/reagent_containers/food/snacks/bun, /obj/item/reagent_containers/food/snacks/customizable, /obj/item/reagent_containers/food/snacks/customizable/sandwich, /obj/item/reagent_containers/food/snacks/slice/bread, /obj/item/reagent_containers/food/snacks/sliceable/flatdough, /obj/item/reagent_containers/food/snacks/spagetti, /obj/item/tape_roll, /obj/item/trash/bowl, /obj/machinery/alarm, /obj/machinery/atmospherics/binary/passive_gate, /obj/machinery/atmospherics/binary/pump, /obj/machinery/atmospherics/binary/volume_pump, /obj/machinery/atmospherics/omni, /obj/machinery/atmospherics/pipe, /obj/machinery/atmospherics/portables_connector, /obj/machinery/atmospherics/trinary, /obj/machinery/atmospherics/tvalve, /obj/machinery/atmospherics/unary/heat_exchanger, /obj/machinery/atmospherics/unary/outlet_injector, /obj/machinery/atmospherics/unary/vent_pump, /obj/machinery/atmospherics/unary/vent_scrubber, /obj/machinery/atmospherics/valve, /obj/machinery/beehive, /obj/machinery/botany, /obj/machinery/botany/editor, /obj/machinery/botany/extractor, /obj/machinery/computer/atmoscontrol, /obj/machinery/computer/cloning, /obj/machinery/computer/pandemic, /obj/machinery/computer/secure_data, /obj/machinery/computer/skills, /obj/machinery/computer/telecomms, /obj/machinery/computer/telecomms/server, /obj/machinery/door/unpowered, /obj/machinery/embedded_controller, /obj/machinery/embedded_controller/radio/airlock, /obj/machinery/field_generator, /obj/machinery/firealarm, /obj/machinery/holoposter, /obj/machinery/honey_extractor, /obj/machinery/particle_smasher, /obj/machinery/partyalarm, /obj/machinery/portable_atmospherics/hydroponics, /obj/machinery/power/emitter, /obj/machinery/power/generator, /obj/machinery/power/smes, /obj/machinery/recharge_station, /obj/machinery/seed_storage, /obj/machinery/space_heater, /obj/machinery/suit_storage_unit, /obj/machinery/telecomms, /obj/machinery/telecomms/relay, /obj/machinery/washing_machine, /obj/structure/AIcore, /obj/structure/closet, /obj/structure/closet/bluespace, /obj/structure/closet/body_bag, /obj/structure/closet/body_bag/cryobag, /obj/structure/closet/crate, /obj/structure/closet/crate/secure, /obj/structure/closet/secure_closet, /obj/structure/closet/secure_closet/mind, /obj/structure/closet/secure_closet/personal, /obj/structure/closet/walllocker/emerglocker)

// Append to the included dq_requirement_boundary_pin_tests.dm.
/datum/unit_test/dq_requirement_fifth_machinery
	parent_type = /datum/unit_test/dq_requirement_fourth_boundary

/datum/unit_test/dq_requirement_fifth_machinery/pipelayer/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/machinery/pipelayer/P = allocate(/obj/machinery/pipelayer, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	P.set_on(FALSE)
	P.metal = 0
	check(P, H, "toggle", "can_run", /datum/msg/pipelayer/no_metal)
	P.metal = 1
	check(P, H, "toggle", "can_run", null)
	P.metal = 0
	P.set_on(TRUE)
	check(P, H, "toggle", "can_run", null)
	P.set_on(FALSE)
	check(P, H, "toggle", "can_run", /datum/msg/pipelayer/no_metal)

/datum/unit_test/dq_requirement_fifth_machinery/generators/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/power/port_gen/pacman/P = allocate(/obj/machinery/power/port_gen/pacman, run_loc_floor_bottom_left)
	P.set_sheets(P.max_sheets)
	check(P, H, "add_fuel", "has_room", /datum/msg/pacman/full)
	P.set_sheets(P.max_sheets - 1)
	check(P, H, "add_fuel", "has_room", null)
	P.set_sheets(P.max_sheets)
	check(P, H, "add_fuel", "has_room", /datum/msg/pacman/full)
	var/obj/machinery/power/port_gen/large_altevian/L = allocate(/obj/machinery/power/port_gen/large_altevian, run_loc_floor_bottom_left)
	L.set_sheets(L.max_sheets)
	check(L, H, "add_fuel", "has_room", /datum/msg/pacman/full)
	L.set_sheets(L.max_sheets - 1)
	check(L, H, "add_fuel", "has_room", null)
	L.set_sheets(L.max_sheets)
	check(L, H, "add_fuel", "has_room", /datum/msg/pacman/full)

/datum/unit_test/dq_requirement_fifth_machinery/portable/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/portable_atmospherics/powered/pump/P = allocate(/obj/machinery/portable_atmospherics/powered/pump, run_loc_floor_bottom_left)
	P.set_destroyed(TRUE)
	check(P, H, "port", "not_destroyed", /datum/msg/portable/wrecked)
	P.set_destroyed(FALSE)
	check(P, H, "port", "not_destroyed", null)
	P.set_destroyed(TRUE)
	check(P, H, "port", "not_destroyed", /datum/msg/portable/wrecked)

// Old-code boundary proof for the industrial requirement cohort; the same
// compiled clause is checked after its null-or-reason conversion.
/datum/unit_test/dq_requirement_industry_boundary
	parent_type = /datum/unit_test/dq_requirement_fourth_boundary

/datum/unit_test/dq_requirement_industry_boundary/pump/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/pump/P = allocate(/obj/machinery/pump, H.loc)
	var/obj/item/cell/C = allocate(/obj/item/cell, H.loc)
	P.open = FALSE
	P.unlocked = FALSE
	check(P, H, "insert_cell", "battery_panel_open", MSG(pump/panel_watertight), C)
	P.unlocked = TRUE
	check(P, H, "insert_cell", "battery_panel_open", MSG(pump/panel_screwed), C)
	P.open = TRUE
	check(P, H, "insert_cell", "battery_panel_open", null, C)
	var/obj/item/cell/initial_cell = P.cell
	TEST_ASSERT_NOTNULL(initial_cell, "The default parts initialize their real cell view")
	check(P, H, "insert_cell", "no_cell", MSG(pump/has_cell), C)
	rel_take(P, nameof(P.cell), initial_cell)
	check(P, H, "insert_cell", "no_cell", null, C)
	rel_set(P, nameof(P.cell), C)
	check(P, H, "insert_cell", "no_cell", MSG(pump/has_cell), C)
	rel_take(P, nameof(P.cell), C)
	check(P, H, "insert_cell", "no_cell", null, C)

/datum/unit_test/dq_requirement_industry_boundary/syringe/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe, H.loc)
	var/obj/item/reagent_containers/syringe/ld50_syringe/L = allocate(/obj/item/reagent_containers/syringe/ld50_syringe, H.loc)
	check(S, H, "stab", "may_stab", null, null, H)
	check(L, H, "stab", "may_stab", MSG(syringe/too_big), null, H)
	check(S, H, "stab", "may_stab", null, null, H)

/datum/unit_test/dq_requirement_industry_boundary/chem_master/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, H.loc)
	for(var/key in list("create_pill_multiple", "create_patch_multiple", "create_bottle_two", "create_bottle_multiple"))
		check(M, H, key, "makes_drugs", /datum/msg/req_silent)
	M.reagents.add_reagent(REAGENT_ID_WATER, 5)
	for(var/key in list("create_pill_multiple", "create_patch_multiple", "create_bottle_two", "create_bottle_multiple"))
		check(M, H, key, "makes_drugs", null)
	M.condi = TRUE
	check(M, H, "create_pill_multiple", "makes_drugs", /datum/msg/req_silent)
	M.condi = FALSE
	check(M, H, "create_pill_multiple", "makes_drugs", null)
	M.reagents.clear_reagents()
	check(M, H, "create_pill_multiple", "makes_drugs", /datum/msg/req_silent)

/datum/unit_test/dq_requirement_industry_boundary/mixer/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/appliance/mixer/candy/M = allocate(/obj/machinery/appliance/mixer/candy, H.loc)
	var/datum/cooking_item/CI = LAZYACCESS(M.cooking_objs, 1)
	TEST_ASSERT_NOTNULL(CI, "A real mixer initializes its owned cooking container")
	var/obj/item/reagent_containers/cooking_container/C = CI.container()
	TEST_ASSERT_NOTNULL(C, "The cooking slot contains its real container")
	check(M, H, "appliance_toggle_power_effect", "can_toggle_power_verb_holds", "there's nothing in it, add ingredients before turning [M] on")
	C.reagents.add_reagent(REAGENT_ID_WATER, 5)
	check(M, H, "appliance_toggle_power_effect", "can_toggle_power_verb_holds", null)
	C.reagents.clear_reagents()
	check(M, H, "appliance_toggle_power_effect", "can_toggle_power_verb_holds", "there's nothing in it, add ingredients before turning [M] on")

/datum/unit_test/dq_requirement_industry_boundary/furnace/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/machinery/material_furnace/F = allocate(/obj/machinery/material_furnace, H.loc)
	var/obj/item/stack/material/steel/S = allocate(/obj/item/stack/material/steel, H.loc)
	check(F, H, "eject_contents", "can_eject_contents_holds", "the furnace is empty")
	check(F, H, "use", "can_use_furnace_holds", "the furnace is empty; load material sheets before firing it")
	check(F, H, "load_stock", "can_load_stock_holds", null, S)
	F.set_firing(TRUE)
	check(F, H, "load_stock", "can_load_stock_holds", "the furnace must be idle and its output removed first", S)
	check(F, H, "use", "can_use_furnace_holds", "the furnace is still firing")
	F.set_firing(FALSE)
	check(F, H, "load_stock", "can_load_stock_holds", null, S)

/datum/unit_test/dq_requirement_industry_boundary/food/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/snacks/bun/B = allocate(/obj/item/reagent_containers/food/snacks/bun, H.loc)
	B.package = FALSE
	B.canned = FALSE
	check(B, H, "stuff", "stuffing_free", null)
	B.package = TRUE
	check(B, H, "stuff", "stuffing_free", MSG(food/closed_to_micros))
	B.package = FALSE
	B.canned = TRUE
	check(B, H, "stuff", "stuffing_free", MSG(food/closed_to_micros))
	B.canned = FALSE
	check(B, H, "stuff", "stuffing_free", null)
	var/obj/item/reagent_containers/food/drinks/coffee/C = allocate(/obj/item/reagent_containers/food/drinks/coffee, H.loc)
	cap_key_set(C, REAGENT_CONTAINER_LID_OPEN, TRUE)
	check(C, H, "stuff", "stuffing_free", null)
	cap_key_set(C, REAGENT_CONTAINER_LID_OPEN, FALSE)
	check(C, H, "stuff", "stuffing_free", MSG(food/closed_to_micros))
	cap_key_set(C, REAGENT_CONTAINER_LID_OPEN, TRUE)
	check(C, H, "stuff", "stuffing_free", null)

// Actual compiled clauses: no duplicated predicate logic or fake client eligibility.
/datum/unit_test/dq_requirement_fifth_boundary
	parent_type = /datum/unit_test/dq_requirement_fourth_boundary

/datum/unit_test/dq_requirement_fifth_boundary/void_components/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	for(var/suit_type in list(/obj/item/clothing/suit/space/void, /obj/item/clothing/suit/space/void/autolok, /obj/item/clothing/suit/space/void/responseteam))
		var/obj/item/clothing/suit/space/void/S = allocate(suit_type, H.loc)
		// Strip real starting components through their declared relations before each boundary.
		rel_clear(S, nameof(S.hood))
		rel_clear(S, nameof(S.boots))
		rel_clear(S, nameof(S.tank))
		rel_clear(S, nameof(S.cooler))
		check(S, H, "voidsuit_remove_component", "has_removable_component", MSG(void/nothing_installed))
		var/obj/item/suit_cooling_unit/C = allocate(/obj/item/suit_cooling_unit, S)
		rel_set(S, nameof(S.cooler), C)
		check(S, H, "voidsuit_remove_component", "has_removable_component", suit_type == /obj/item/clothing/suit/space/void ? MSG(void/nothing_installed) : null)
		rel_set(S, nameof(S.cooler), null)
		var/obj/item/tank/T = allocate(/obj/item/tank, S)
		rel_set(S, nameof(S.tank), T)
		check(S, H, "voidsuit_remove_component", "has_removable_component", null)
		rel_set(S, nameof(S.tank), null)
		check(S, H, "voidsuit_remove_component", "has_removable_component", MSG(void/nothing_installed))

/datum/unit_test/dq_requirement_fifth_boundary/tongue_and_lightreplacer/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/robot_tongue/L = allocate(/obj/item/robot_tongue, H.loc)
	L.water = allocate(/datum/matter_synth, 500)
	check(L, H, "tongue_drink_sink", "tongue_thirsty", /datum/msg/req_silent)
	check(L, H, "tongue_drink_toilet", "tongue_thirsty", MSG(tongue/full))
	TEST_ASSERT(L.water.use_charge(1), "The real matter reservoir spends one unit")
	check(L, H, "tongue_drink_sink", "tongue_thirsty", null)
	check(L, H, "tongue_drink_toilet", "tongue_thirsty", null)
	L.water.add_charge(1)
	check(L, H, "tongue_drink_sink", "tongue_thirsty", /datum/msg/req_silent)
	check(L, H, "tongue_drink_toilet", "tongue_thirsty", MSG(tongue/full))
	var/obj/item/lightreplacer/dogborg/R = allocate(/obj/item/lightreplacer/dogborg, H.loc)
	R.set_uses(R.max_uses)
	check(R, H, "fabricate", "has_room", MSG(lightreplacer/full))
	R.set_uses(R.max_uses - 1)
	check(R, H, "fabricate", "has_room", null)
	R.set_uses(R.max_uses)
	check(R, H, "fabricate", "has_room", MSG(lightreplacer/full))

/datum/unit_test/dq_requirement_fifth_boundary/weaver/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/trait_state/weaver/W = H.add_trait_state(/datum/trait_state/weaver)
	TEST_ASSERT_NOTNULL(W, "The real trait attaches to the human")
	var/list/costs = list("binding" = 50, "floor" = 25, "wall" = 100, "nest" = 100, "trap" = 250)
	for(var/product in costs)
		var/cost = costs[product]
		W.set_silk_reserve(cost - 1)
		check(W, H, "weave_[product]", "weave_silk_[product]", /datum/msg/weaver/no_silk)
		W.set_silk_reserve(cost)
		check(W, H, "weave_[product]", "weave_silk_[product]", null)
		W.set_silk_reserve(cost - 1)
		check(W, H, "weave_[product]", "weave_silk_[product]", /datum/msg/weaver/no_silk)
	check(W, H, "weave_floor", "weave_site_free", null)
	var/obj/effect/weaversilk/floor/F = allocate(/obj/effect/weaversilk/floor, H.loc)
	check(W, H, "weave_floor", "weave_site_free", /datum/msg/weaver/already_there)
	qdel(F)
	check(W, H, "weave_floor", "weave_site_free", null)
/datum/unit_test/dq_requirement_fifth_boundary/vv_remote/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, H.loc)
	check(target, H, "vv_give_ai", "vv_not_remote_driven", null)
	rel_set(target, nameof(target.teleop), H)
	check(target, H, "vv_give_ai", "vv_not_remote_driven", MSG(vv/player_mob))
	rel_set(target, nameof(target.teleop), null)
	check(target, H, "vv_give_ai", "vv_not_remote_driven", null)
// Record and compare concrete old-code types for requirement batch E.
/datum/unit_test/dq_requirement_fifth_pin
	parent_type = /datum/unit_test/dq_conversion_pin
	capture_roots = list(/obj/item/assembly/signaler/anomaly, /obj/item/clamp, /obj/item/clothing/accessory/badge/holo, /obj/item/clothing/glasses/hud/health/eyepatch, /obj/item/clothing/glasses/hud/security/eyepatch, /obj/item/clothing/glasses/hud/security/eyepatch2, /obj/item/clothing/shoes/black, /obj/item/clothing/suit/space/void, /obj/item/clothing/suit/space/void/autolok, /obj/item/clothing/suit/space/void/responseteam, /obj/item/clothing/under/color/grey, /obj/item/dogborg/sleeper, /obj/item/frame, /obj/item/glamour_face, /obj/item/lightreplacer, /obj/item/lightreplacer/dogborg, /obj/item/pipe, /obj/item/pipe_meter, /obj/item/reagent_containers/cooking_container, /obj/item/reagent_containers/food/drinks/coffee, /obj/item/reagent_containers/food/snacks/bun, /obj/item/reagent_containers/food/snacks/csandwich, /obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/syringe, /obj/item/reagent_containers/syringe/ld50_syringe, /obj/item/resonator, /obj/item/rig, /obj/item/robot_tongue, /obj/item/solar_assembly, /obj/item/stack/cable_coil/alien, /obj/item/stack/flag, /obj/item/stack/lightpole, /obj/item/storage/firstaid, /obj/machinery/appliance/mixer/candy, /obj/machinery/atmospherics/unary/cryo_cell, /obj/machinery/beehive, /obj/machinery/chem_master, /obj/machinery/chemical_dispenser, /obj/machinery/clamp, /obj/machinery/door/airlock, /obj/machinery/door/blast, /obj/machinery/door/firedoor, /obj/machinery/door/window, /obj/machinery/honey_extractor, /obj/machinery/material_furnace, /obj/machinery/meter, /obj/machinery/mineral/processing_unit_console, /obj/machinery/mining/brace, /obj/machinery/mining/drill, /obj/machinery/nuclearbomb, /obj/machinery/pipedispenser, /obj/machinery/pipedispenser/disposal, /obj/machinery/pipelayer, /obj/machinery/porta_turret, /obj/machinery/portable_atmospherics/canister, /obj/machinery/portable_atmospherics/powered/pump, /obj/machinery/portable_atmospherics/powered/pump/huge, /obj/machinery/portable_atmospherics/powered/scrubber/huge, /obj/machinery/power/apc, /obj/machinery/power/port_gen/large_altevian, /obj/machinery/power/port_gen/pacman, /obj/machinery/power/thermoregulator, /obj/machinery/pump, /obj/machinery/reagent_refinery/filter, /obj/machinery/reagent_refinery/grinder, /obj/machinery/recharger, /obj/machinery/rnd/destructive_analyzer, /obj/machinery/seed_storage, /obj/machinery/smartfridge, /obj/machinery/smartfridge/secure, /obj/machinery/vr_sleeper, /obj/structure/glamour_ring)
