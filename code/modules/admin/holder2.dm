GLOBAL_LIST_EMPTY(admin_datums)
GLOBAL_PROTECT(admin_datums)
GLOBAL_LIST_EMPTY(protected_admins)
GLOBAL_PROTECT(protected_admins)

GLOBAL_VAR_INIT(href_token, GenerateToken())
GLOBAL_PROTECT(href_token)

/datum/admins
	/// Our ranks (a relation list: ranks live in GLOB.admin_ranks, or in custom_rank). Set with set_ranks().
	var/list/datum/admin_rank/ranks
	/// The client-level click intercept (a relation view); needs to implement InterceptClickOn(user,params,atom).
	var/tmp/datum/click_intercept
	/// A per-admin rank duplicated for this holder (change_admin_flags), owned.
	var/datum/admin_rank/custom_rank

	var/target
	var/name = "nobody's admin datum (no rank)" //Makes for better runtimes
	var/tmp/client/owner
	var/fakekey = null

	var/tmp/datum/marked_datum

	var/admincaster_screen = 0	//See newscaster.dm under machinery for a full description
	var/datum/feed_message/admincaster_feed_message = new /datum/feed_message   //These two will act as holders.
	/// The admin newscaster's working channel: a picked network channel (a relation view), or while
	/// none is picked its own scratch channel (admincaster_feed_channel() reads either).
	var/tmp/datum/feed_channel/admincaster_feed_channel
	var/datum/feed_channel/admincaster_scratch_channel = new /datum/feed_channel
	var/admincaster_signature	//What you'll sign the newsfeeds as
	/// Tracked mirrors of whether the channel and the Wanted draft can be sent (a requirement cannot read the draft or the network); admincaster_resync() sets them after every change.
	var/admincaster_channel_ready = FALSE
	var/admincaster_wanted_ready = FALSE

	/// Code security critcal token used for authorizing href topic calls
	var/href_token

	/// Link from the database pointing to the admin's feedback forum
	var/fetched_feedback_link
	/// The io_job job fetching fetched_feedback_link, while one is in flight.
	var/feedback_link_pending = 0

	var/deadmined

	var/datum/filter_editor/filteriffic
	var/datum/particle_editor/particle_test
	var/datum/whitelist_editor/whitelist_editor
	var/datum/spawn_menu/spawn_menu
	var/datum/spawnpanel/spawn_panel

	var/datum/access_viewer/access_view_menu

	/// A lazylist of tagged datums, for quick reference with the View Tags verb
	var/list/tagged_datums

	var/given_profiling = FALSE

TRACKED(/datum/admins, admincaster_channel_ready)
TRACKED(/datum/admins, admincaster_wanted_ready)

CAPABILITIES(/datum/admins)
	op("empty_ai_core_latejoin", ai(), needs(req(PROC_REF(empty_ai_core_latejoin_valid), because = "administrator rights required")), asks(/datum/prompt/choice, fields = list("title" = "Toggle AI Core Latejoin", "question" = "Which core?", "choices" = computed(PROC_REF(empty_ai_core_options)), "timeout" = 0), step = "core"), then(PROC_REF(empty_ai_core_latejoin_chosen)))
	owns_one(nameof(access_view_menu), /datum/access_viewer)
	owns_one(nameof(admincaster_feed_message), /datum/feed_message)
	owns_one(nameof(admincaster_scratch_channel), /datum/feed_channel)
	owns_one(nameof(custom_rank), /datum/admin_rank)
	owns_one(nameof(dq_newscaster_panel), /datum/newscaster_panel)
	owns_one(nameof(dq_permissions_panel), /datum/permissions_panel)
	owns_one(nameof(faxreply), /obj/item/paper/admin)
	owns_one(nameof(filteriffic), /datum/filter_editor)
	owns_one(nameof(particle_test), /datum/particle_editor)
	owns_one(nameof(round_status_panel), /datum/round_status_panel)
	owns_one(nameof(spawn_menu), /datum/spawn_menu)
	owns_one(nameof(spawn_panel), /datum/spawnpanel)
	owns_one(nameof(tgui_game_panel), /datum/game_panel)
	owns_one(nameof(tgui_player_panel), /datum/player_panel)
	op("unbanf", topic("unbanf", arg("unbanf", schema_text(), optional = TRUE)), needs(req_rights(R_BAN)), then(PROC_REF(topic_unbanf)))
	op("warn", topic("warn", arg("warn", schema_text(), optional = TRUE)), needs(req_rights(R_MOD|R_ADMIN)), then(PROC_REF(topic_warn)))
	op("unbane", topic("unbane", arg("unbane", schema_text(), optional = TRUE)), needs(req_rights(R_BAN)), then(PROC_REF(topic_unbane)))
	op("jobban2", topic("jobban2", arg("jobban2", schema_ref(/mob), optional = TRUE, among = PROC_REF(topic_registered_mobs))), needs(req_rights(R_BAN)), then(PROC_REF(topic_jobban2)))
	op("jobban3", topic("jobban3", arg("jobban3", schema_text(), optional = TRUE), arg("jobban4", schema_ref(/mob), optional = TRUE)), then(PROC_REF(topic_jobban3)))
	op("boot2", topic("boot2", arg("boot2", schema_ref(/mob), optional = TRUE)), then(PROC_REF(topic_boot2)))
	op("removejobban", topic("removejobban", arg("removejobban", schema_text(), optional = TRUE)), needs(req_rights(R_BAN)), then(PROC_REF(topic_removejobban)))
	op("newban", topic("newban", arg("newban", schema_ref(/mob), optional = TRUE)), then(PROC_REF(topic_newban)))
	op("mute", topic("mute", arg("mute", schema_ref(/mob), optional = TRUE), arg("mute_type", num(), optional = TRUE)), needs(req_rights(R_MOD|R_ADMIN)), then(PROC_REF(topic_mute)))
	op("CentComReply", topic("CentComReply", arg("CentComReply", schema_ref(/mob/living), optional = TRUE)), needs(req(PROC_REF(centcom_reply_possible), because = MSG(admin_topic/centcom_unreachable))), asks(/datum/prompt/text/admin_comms_topic, fields = list("question" = computed(PROC_REF(centcom_reply_question)), "title" = "Outgoing message from CentCom"), step = "message"), then(PROC_REF(topic_centcomreply)))
	op("SyndicateReply", topic("SyndicateReply", arg("SyndicateReply", schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req(PROC_REF(syndicate_reply_possible), because = MSG(admin_topic/syndicate_unreachable))), asks(/datum/prompt/text/admin_comms_topic, fields = list("question" = computed(PROC_REF(syndicate_reply_question)), "title" = "Outgoing message from a shadowy figure..."), step = "message"), then(PROC_REF(topic_syndicatereply)))
	op("AdminFaxView", topic("AdminFaxView", arg("AdminFaxView", schema_ref(/obj/item), optional = TRUE)), then(PROC_REF(topic_adminfaxview)))
	op("AdminFaxViewPage", topic("AdminFaxViewPage", arg("AdminFaxViewPage", num(), optional = TRUE), arg("paper_bundle", schema_ref(/obj/item/paper_bundle), optional = TRUE)), then(PROC_REF(topic_adminfaxviewpage)))
	op("FaxReply", topic("FaxReply", arg("FaxReply", schema_ref(/mob), optional = TRUE), arg("originfax", schema_ref(/obj/machinery/photocopier/faxmachine), optional = TRUE), arg("replyorigin", schema_text(), optional = TRUE)), then(PROC_REF(topic_faxreply)))
	op("simplemake", topic("simplemake", arg("simplemake", schema_text(), optional = TRUE), arg("mob", schema_ref(/mob), optional = TRUE), arg("species", schema_text(), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_simplemake)))
	op("turn_monkey", topic(VV_HK_TURN_MONKEY, arg(VV_HK_TURN_MONKEY, schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_turn_monkey)))
	op("corgione", topic("corgione", arg("corgione", schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_corgione)))
	op("forcespeech", topic("forcespeech", arg("forcespeech", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_FUN)), asks(/datum/prompt/text/admin_force_speech, fields = list("question" = computed(PROC_REF(force_speech_question)), "title" = "Force speech"), step = "speech"), then(PROC_REF(topic_forcespeech)))
	op("sendtoprison", topic("sendtoprison", arg("sendtoprison", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN)), then(PROC_REF(topic_sendtoprison)))
	op("sendbacktolobby", topic("sendbacktolobby", arg("sendbacktolobby", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN)), then(PROC_REF(topic_sendbacktolobby)))
	op("tdome1", topic("tdome1", arg("tdome1", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_FUN)), then(PROC_REF(topic_tdome1)))
	op("tdome2", topic("tdome2", arg("tdome2", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_FUN)), then(PROC_REF(topic_tdome2)))
	op("tdomeadmin", topic("tdomeadmin", arg("tdomeadmin", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_FUN)), then(PROC_REF(topic_tdomeadmin)))
	op("tdomeobserve", topic("tdomeobserve", arg("tdomeobserve", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_FUN)), then(PROC_REF(topic_tdomeobserve)))
	op("revive", topic("revive", arg("revive", schema_ref(/mob/living), optional = TRUE)), needs(req_rights(R_REJUVINATE)), then(PROC_REF(topic_revive)))
	op("turn_ai", topic(VK_HK_TURN_AI, arg(VK_HK_TURN_AI, schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_turn_ai)))
	op("turn_alien", topic(VV_HK_TURN_ALIEN, arg(VV_HK_TURN_ALIEN, schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_turn_alien)))
	op("turn_robot", topic(VK_HK_TURN_ROBOT, arg(VK_HK_TURN_ROBOT, schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_turn_robot)))
	op("makeanimal", topic("makeanimal", arg("makeanimal", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_makeanimal)))
	op("respawn", topic("respawn", arg("respawn", schema_ref(/client), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_respawn)))
	op("togmutate", topic("togmutate", arg("togmutate", schema_ref(/mob/living/carbon/human), optional = TRUE), arg("block", num(), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_togmutate)))
	op("adminplayeropts", topic("adminplayeropts", arg("adminplayeropts", schema_ref(/mob), optional = TRUE)), then(PROC_REF(topic_adminplayeropts)))
	op("adminplayerobservejump", topic("adminplayerobservejump", arg("adminplayerobservejump", schema_ref(/atom), optional = TRUE)), needs(req_rights(R_MOD|R_ADMIN|R_SERVER)), then(PROC_REF(topic_adminplayerobservejump)))
	op("adminplayerobservefollow", topic("adminplayerobservefollow", arg("adminplayerobservefollow", schema_ref(/atom/movable), optional = TRUE)), needs(req_rights(R_MOD|R_ADMIN|R_SERVER)), then(PROC_REF(topic_adminplayerobservefollow)))
	op("take_question", topic("take_question", arg("take_question", schema_ref(/mob), optional = TRUE)), then(PROC_REF(topic_take_question)))
	op("adminplayerobservecoodjump", topic("adminplayerobservecoodjump", arg("X", num(), optional = TRUE), arg("Y", num(), optional = TRUE), arg("Z", num(), optional = TRUE)), needs(req_rights(R_ADMIN|R_SERVER|R_MOD)), then(PROC_REF(topic_adminplayerobservecoodjump)))
	op("adminmoreinfo", topic("adminmoreinfo", arg("adminmoreinfo", schema_ref(/mob), optional = TRUE)), then(PROC_REF(topic_adminmoreinfo)))
	op("adminspawncookie", topic("adminspawncookie", arg("adminspawncookie", schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_ADMIN|R_FUN|R_EVENT)), then(PROC_REF(topic_adminspawncookie)))
	op("adminsmite", topic("adminsmite", arg("adminsmite", schema_ref(/mob/living/carbon/human), optional = TRUE)), needs(req_rights(R_ADMIN|R_FUN|R_EVENT)), then(PROC_REF(topic_adminsmite)))
	op("BlueSpaceArtillery", topic("BlueSpaceArtillery", arg("BlueSpaceArtillery", schema_ref(/mob/living), optional = TRUE)), needs(req_rights(R_ADMIN|R_FUN|R_EVENT)), then(PROC_REF(topic_bluespaceartillery)))
	op("jumpto", topic("jumpto", arg("jumpto", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT)), then(PROC_REF(topic_jumpto)))
	op("getmob", topic("getmob", arg("getmob", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT)), then(PROC_REF(topic_getmob)))
	op("sendmob", topic("sendmob", arg("sendmob", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT)), then(PROC_REF(topic_sendmob)))
	op("narrateto", topic("narrateto", arg("narrateto", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT|R_FUN)), then(PROC_REF(topic_narrateto)))
	op("subtlemessage", topic("subtlemessage", arg("subtlemessage", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_MOD|R_ADMIN|R_EVENT|R_FUN)), then(PROC_REF(topic_subtlemessage)))
	op("traitor", topic("traitor", arg("traitor", schema_ref(/mob), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD|R_EVENT)), then(PROC_REF(topic_traitor)))
	op("toglang", topic("toglang", arg("toglang", schema_ref(/mob), optional = TRUE), arg("lang", schema_text(), optional = TRUE)), needs(req_rights(R_SPAWN)), then(PROC_REF(topic_toglang)))
	op("cryoplayer", topic("cryoplayer", arg("cryoplayer", schema_ref(/mob/living/carbon), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT)), then(PROC_REF(topic_cryoplayer)))
	op("ac_view_wanted", topic("ac_view_wanted"), then(PROC_REF(topic_ac_view_wanted)))
	op("ac_set_channel_name", topic("ac_set_channel_name"), asks(/datum/prompt/text/admincaster_topic, fields = list("question" = "Provide a Feed Channel Name", "title" = "Network Channel Handler", "encode" = FALSE), step = "answer"), then(PROC_REF(topic_ac_set_channel_name)))
	op("ac_set_channel_lock", topic("ac_set_channel_lock"), then(PROC_REF(topic_ac_set_channel_lock)))
	op("ac_submit_new_channel", topic("ac_submit_new_channel"), needs(req(PROC_REF(ac_channel_ready), because = MSG(admin_topic/channel_unsubmittable))), asks(/datum/prompt/choice/admincaster_topic, fields = list("question" = "Please confirm Feed channel creation", "title" = "Network Channel Handler", "choices" = list("Confirm", "Cancel"), "buttons" = TRUE), step = "confirm"), then(PROC_REF(topic_ac_submit_new_channel)))
	op("ac_set_channel_receiving", topic("ac_set_channel_receiving"), asks(/datum/prompt/choice/admincaster_topic, fields = list("question" = "Choose receiving Feed Channel", "title" = "Network Channel Handler", "choices" = computed(PROC_REF(ac_channel_names))), step = "answer"), then(PROC_REF(topic_ac_set_channel_receiving)))
	op("ac_set_new_title", topic("ac_set_new_title"), asks(/datum/prompt/text/admincaster_topic, fields = list("question" = "Enter the Feed title", "title" = "Network Channel Handler"), step = "answer"), then(PROC_REF(topic_ac_set_new_title)))
	op("ac_set_new_message", topic("ac_set_new_message"), asks(/datum/prompt/text/admincaster_topic, fields = list("question" = "Write your Feed story", "title" = "Network Channel Handler", "multiline" = TRUE), step = "answer"), then(PROC_REF(topic_ac_set_new_message)))
	op("ac_submit_new_message", topic("ac_submit_new_message"), then(PROC_REF(topic_ac_submit_new_message)))
	op("ac_create_channel", topic("ac_create_channel"), then(PROC_REF(topic_ac_create_channel)))
	op("ac_create_feed_story", topic("ac_create_feed_story"), then(PROC_REF(topic_ac_create_feed_story)))
	op("ac_menu_censor_story", topic("ac_menu_censor_story"), then(PROC_REF(topic_ac_menu_censor_story)))
	op("ac_menu_censor_channel", topic("ac_menu_censor_channel"), then(PROC_REF(topic_ac_menu_censor_channel)))
	op("ac_menu_wanted", topic("ac_menu_wanted"), then(PROC_REF(topic_ac_menu_wanted)))
	op("ac_set_wanted_name", topic("ac_set_wanted_name"), asks(/datum/prompt/text/admincaster_topic, fields = list("question" = "Provide the name of the Wanted person", "title" = "Network Security Handler"), step = "answer"), then(PROC_REF(topic_ac_set_wanted_name)))
	op("ac_set_wanted_desc", topic("ac_set_wanted_desc"), asks(/datum/prompt/text/admincaster_topic, fields = list("question" = "Provide the a description of the Wanted person and any other details you deem important", "title" = "Network Security Handler"), step = "answer"), then(PROC_REF(topic_ac_set_wanted_desc)))
	op("ac_submit_wanted", topic("ac_submit_wanted", arg("ac_submit_wanted", num(), optional = TRUE)), needs(req(PROC_REF(ac_wanted_ready), because = MSG(admin_topic/wanted_unsubmittable))), asks(/datum/prompt/choice/admincaster_topic, fields = list("question" = computed(PROC_REF(ac_wanted_question)), "title" = "Network Security Handler", "choices" = list("Confirm", "Cancel"), "buttons" = TRUE), step = "confirm"), then(PROC_REF(topic_ac_submit_wanted)))
	op("ac_cancel_wanted", topic("ac_cancel_wanted"), asks(/datum/prompt/choice/admincaster_topic, fields = list("question" = "Please confirm Wanted Issue removal", "title" = "Network Security Handler", "choices" = list("Confirm", "Cancel"), "buttons" = TRUE), step = "confirm"), then(PROC_REF(topic_ac_cancel_wanted)))
	op("ac_censor_channel_author", topic("ac_censor_channel_author", arg("ac_censor_channel_author", schema_ref(/datum/feed_channel), optional = TRUE)), then(PROC_REF(topic_ac_censor_channel_author)))
	op("ac_censor_channel_story_author", topic("ac_censor_channel_story_author", arg("ac_censor_channel_story_author", schema_ref(/datum/feed_message), optional = TRUE)), then(PROC_REF(topic_ac_censor_channel_story_author)))
	op("ac_censor_channel_story_body", topic("ac_censor_channel_story_body", arg("ac_censor_channel_story_body", schema_ref(/datum/feed_message), optional = TRUE)), then(PROC_REF(topic_ac_censor_channel_story_body)))
	op("ac_pick_d_notice", topic("ac_pick_d_notice", arg("ac_pick_d_notice", schema_ref(/datum/feed_channel), optional = TRUE)), then(PROC_REF(topic_ac_pick_d_notice)))
	op("ac_toggle_d_notice", topic("ac_toggle_d_notice", arg("ac_toggle_d_notice", schema_ref(/datum/feed_channel), optional = TRUE)), then(PROC_REF(topic_ac_toggle_d_notice)))
	op("ac_view", topic("ac_view"), then(PROC_REF(topic_ac_view)))
	op("ac_setScreen", topic("ac_setScreen", arg("ac_setScreen", num(), optional = TRUE)), then(PROC_REF(topic_ac_setscreen)))
	op("ac_show_channel", topic("ac_show_channel", arg("ac_show_channel", schema_ref(/datum/feed_channel), optional = TRUE)), then(PROC_REF(topic_ac_show_channel)))
	op("ac_pick_censor_channel", topic("ac_pick_censor_channel", arg("ac_pick_censor_channel", schema_ref(/datum/feed_channel), optional = TRUE)), then(PROC_REF(topic_ac_pick_censor_channel)))
	op("ac_refresh", topic("ac_refresh"), then(PROC_REF(topic_ac_refresh)))
	op("ac_set_signature", topic("ac_set_signature"), asks(/datum/prompt/text/admincaster_topic, fields = list("question" = "Provide your desired signature", "title" = "Network Identity Handler"), step = "answer"), then(PROC_REF(topic_ac_set_signature)))
	op("ticket", topic("ticket", arg("ticket", schema_ref(/datum/ticket), optional = TRUE), arg("ticket_action", schema_text(), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD|R_DEBUG|R_EVENT|R_MENTOR)), then(PROC_REF(topic_ticket)))
	op("tickets", topic("tickets", arg("tickets", num(), optional = TRUE)), then(PROC_REF(topic_tickets)))
	op("editrightsbrowser", topic("editrightsbrowser"), needs(req_rights(R_PERMISSIONS)), then(PROC_REF(topic_editrightsbrowser)))
	op("editrightsbrowserranks", topic("editrightsbrowserranks", arg("editrightsaddrank", schema_text(), optional = TRUE), arg("editrightsremoverank", schema_text(), optional = TRUE), arg("editrightseditrank", schema_text(), optional = TRUE)), needs(req_rights(R_PERMISSIONS)), then(PROC_REF(topic_editrightsbrowserranks)))
	op("editrightsbrowserlogging", topic("editrightsbrowserlogging", arg("editrightslogtarget", schema_text(), optional = TRUE), arg("editrightslogactor", schema_text(), optional = TRUE), arg("editrightslogoperation", schema_text(), optional = TRUE), arg("editrightslogpage", schema_text(), optional = TRUE)), needs(req_rights(R_PERMISSIONS)), then(PROC_REF(topic_editrightsbrowserlogging)))
	op("editrightsbrowserhousekeep", topic("editrightsbrowserhousekeep", arg("editrightschange", schema_text(), optional = TRUE), arg("editrightsremove", schema_text(), optional = TRUE), arg("editrightsremoverank", schema_text(), optional = TRUE)), needs(req_rights(R_PERMISSIONS)), then(PROC_REF(topic_editrightsbrowserhousekeep)))
	op("editrights", topic("editrights", arg("editrights", schema_text(), optional = TRUE), arg("key", schema_text(), optional = TRUE)), needs(req_rights(R_PERMISSIONS)), then(PROC_REF(topic_editrights)))
	op("call_shuttle", topic("call_shuttle", arg("call_shuttle", schema_text(), optional = TRUE)), needs(req_rights(R_ADMIN|R_EVENT)), then(PROC_REF(topic_call_shuttle)))
	op("edit_shuttle_time", topic("edit_shuttle_time"), needs(req_rights(R_SERVER)), then(PROC_REF(topic_edit_shuttle_time)))
	op("delay_round_end", topic("delay_round_end"), needs(req_rights(R_SERVER)), then(PROC_REF(topic_delay_round_end)))
	op("c_mode", topic("c_mode"), needs(req_rights(R_ADMIN|R_EVENT), req(PROC_REF(round_not_started), because = MSG(admin_topic/round_started))), asks(/datum/prompt/choice/admin_round_mode_topic, fields = list("question" = computed(PROC_REF(c_mode_question)), "title" = "Game Mode", "choices" = computed(PROC_REF(c_mode_labels))), step = "mode"), then(PROC_REF(topic_c_mode)))
	op("f_secret", topic("f_secret"), needs(req_rights(R_ADMIN|R_EVENT), req(PROC_REF(round_not_started), because = MSG(admin_topic/round_started)), req(PROC_REF(round_is_secret), because = MSG(admin_topic/not_secret))), asks(/datum/prompt/choice/admin_round_mode_topic, fields = list("question" = computed(PROC_REF(f_secret_question)), "title" = "Force Secret", "choices" = computed(PROC_REF(f_secret_labels))), step = "mode"), then(PROC_REF(topic_f_secret)))
	op("c_mode2", topic("c_mode2", arg("c_mode2", schema_text(), optional = TRUE)), then(PROC_REF(topic_c_mode2)))
	op("f_secret2", topic("f_secret2", arg("f_secret2", schema_text(), optional = TRUE)), then(PROC_REF(topic_f_secret2)))
	op("check_antagonist", topic("check_antagonist"), then(PROC_REF(topic_check_antagonist)))
	op("secretsadmin_check_antagonist", topic("secretsadmin=check_antagonist"), then(PROC_REF(topic_check_antagonist)))
	op("viewruntime", topic("viewruntime", arg("viewruntime", schema_ref(/datum/error_viewer), optional = TRUE), arg("viewruntime_backto", schema_ref(/datum/error_viewer), optional = TRUE), arg("viewruntime_linear", schema_text(), optional = TRUE)), then(PROC_REF(topic_viewruntime)))
	op("adminchecklaws", topic("adminchecklaws"), then(PROC_REF(topic_adminchecklaws)))
	op("spawn_panel", topic("spawn_panel"), then(PROC_REF(topic_spawn_panel)))
	op("populate_inactive_customitems", topic("populate_inactive_customitems"), needs(req_rights(R_ADMIN|R_SERVER)), then(PROC_REF(topic_populate_inactive_customitems)))
	op("vsc", topic("vsc"), needs(req_rights(R_ADMIN|R_SERVER|R_EVENT)), then(PROC_REF(topic_vsc)))
	op("notes", topic("notes", arg("notes", schema_text(), optional = TRUE), arg("ckey", schema_text(), optional = TRUE), arg("mob", schema_ref(/mob), optional = TRUE), arg("index", num(), optional = TRUE)), then(PROC_REF(topic_notes)))
	op("add_player_info_legacy", topic("add_player_info_legacy", arg("add_player_info_legacy", schema_text(64), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD)), then(PROC_REF(topic_add_player_info_legacy)))
	op("remove_player_info_legacy", topic("remove_player_info_legacy", arg("remove_player_info_legacy", schema_text(64), optional = TRUE), arg("remove_index", num(), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD)), then(PROC_REF(topic_remove_player_info_legacy)))
	op("notes_legacy_show", topic("notes_legacy=show", arg("ckey", schema_text(64), optional = TRUE), arg("mob", schema_ref(/mob), optional = TRUE, among = TOPIC_IN_MOBS)), needs(req_rights(R_ADMIN|R_MOD)), then(PROC_REF(topic_notes_legacy_show)))
	op("notes_legacy_list", topic("notes_legacy=list", arg("index", num(), optional = TRUE), arg("filter", schema_text(256), optional = TRUE)), needs(req_rights(R_ADMIN|R_MOD)), then(PROC_REF(topic_notes_legacy_list)))
	op("notes_legacy_filter", topic("notes_legacy=filter"), needs(req_rights(R_ADMIN|R_MOD)), then(PROC_REF(topic_notes_legacy_filter)))
	op("vv_topic_vars", topic_in(VV_ADMIN_TOPIC, "Vars", arg("Vars", schema_ref(list(/datum, /client, /list)), optional = TRUE, among = TOPIC_ANY), arg("special_varname", schema_text(), optional = TRUE)), then(PROC_REF(vv_topic_vars)))
	op("vv_topic_rotate_left", topic_in(VV_ADMIN_TOPIC, "rotatedir=left", arg("rotatedatum", schema_ref(/atom), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_rotate_left)))
	op("vv_topic_rotate_right", topic_in(VV_ADMIN_TOPIC, "rotatedir=right", arg("rotatedatum", schema_ref(/atom), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_rotate_right)))
	op("vv_topic_adjust_body", topic_in(VV_ADMIN_TOPIC, "adjustBody", arg("mobToDamage", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS), arg("adjustBody", schema_text(16), optional = TRUE)), then(PROC_REF(vv_topic_adjust_body)))
	op("vv_topic_basic_edit", topic_in(VV_ADMIN_TOPIC, VV_HK_BASIC_EDIT, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY), arg(VV_HK_VARNAME, schema_text(), optional = TRUE)), then(PROC_REF(vv_topic_basic_edit)))
	op("vv_topic_basic_change", topic_in(VV_ADMIN_TOPIC, VV_HK_BASIC_CHANGE, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY), arg(VV_HK_VARNAME, schema_text(), optional = TRUE)), then(PROC_REF(vv_topic_basic_change)))
	op("vv_topic_basic_massedit", topic_in(VV_ADMIN_TOPIC, VV_HK_BASIC_MASSEDIT, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY), arg(VV_HK_VARNAME, schema_text(), optional = TRUE)), then(PROC_REF(vv_topic_basic_massedit)))
	op("vv_topic_expose", topic_in(VV_ADMIN_TOPIC, VV_HK_EXPOSE, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), needs(req_rights(R_ADMIN)), then(PROC_REF(vv_topic_expose)))
	op("vv_topic_delete", topic_in(VV_ADMIN_TOPIC, VV_HK_DELETE, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), needs(req_rights(R_DEBUG)), then(PROC_REF(vv_topic_delete)))
	op("vv_topic_mark", topic_in(VV_ADMIN_TOPIC, VV_HK_MARK, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_mark)))
	op("vv_topic_tag", topic_in(VV_ADMIN_TOPIC, VV_HK_TAG, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_tag)))
	op("vv_topic_add_behaviour", topic_in(VV_ADMIN_TOPIC, VV_HK_ADDCOMPONENT, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), needs(req_rights(R_DEBUG)), then(PROC_REF(vv_topic_add_behaviour)))
	op("vv_topic_remove_behaviour", topic_in(VV_ADMIN_TOPIC, VV_HK_REMOVECOMPONENT, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), needs(req_rights(R_DEBUG)), then(PROC_REF(vv_topic_remove_behaviour)))
	op("vv_topic_mass_remove_behaviour", topic_in(VV_ADMIN_TOPIC, VV_HK_MASS_REMOVECOMPONENT, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), needs(req_rights(R_DEBUG)), then(PROC_REF(vv_topic_mass_remove_behaviour)))
	op("vv_topic_call_proc", topic_in(VV_ADMIN_TOPIC, VV_HK_CALLPROC, arg(VV_HK_TARGET, schema_ref(list(/datum, /client)), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_call_proc)))
	op("vv_topic_list_edit", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_EDIT, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY), arg(VV_HK_VARNAME, num(), optional = TRUE)), then(PROC_REF(vv_topic_list_edit)))
	op("vv_topic_list_change", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_CHANGE, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY), arg(VV_HK_VARNAME, num(), optional = TRUE)), then(PROC_REF(vv_topic_list_change)))
	op("vv_topic_list_remove", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_REMOVE, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY), arg(VV_HK_VARNAME, num(), optional = TRUE)), then(PROC_REF(vv_topic_list_remove)))
	op("vv_topic_list_add", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_ADD, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_list_add)))
	op("vv_topic_list_dupes", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_ERASE_DUPES, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_list_dupes)))
	op("vv_topic_list_nulls", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_ERASE_NULLS, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_list_nulls)))
	op("vv_topic_list_length", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_SET_LENGTH, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_list_length)))
	op("vv_topic_list_shuffle", topic_in(VV_ADMIN_TOPIC, VV_HK_LIST_SHUFFLE, arg(VV_HK_TARGET, schema_ref(/list), optional = TRUE, among = TOPIC_ANY)), then(PROC_REF(vv_topic_list_shuffle)))

/datum/admins/New(list/datum/admin_rank/ranks, ckey, force_active = FALSE, protected)
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		if (!target) //only del if this is a true creation (and not just a New() proc call), other wise trialmins/coders could abuse this to deadmin other admins
			om_qdel_after(src, 0)
			CRASH("Admin proc call creation of admin datum")
		return
	if(!ckey)
		om_qdel_after(src, 0)
		CRASH("Admin datum created without a ckey")
	if(!istype(ranks))
		om_qdel_after(src, 0)
		CRASH("Admin datum created with invalid ranks: [ranks] ([json_encode(ranks)])")
	target = ckey
	name = "[ckey]'s admin datum ([join_admin_ranks(ranks)])"
	set_ranks(ranks)
	admincaster_signature = "[using_map.company_name] Officer #[rand(0,9)][rand(0,9)][rand(0,9)]"
	href_token = GenerateToken()
	if(protected)
		GLOB.protected_admins[target] = src // ALLOW(registry): the admin holder tables are keyed by ckey and outlive the client (deadmin, protected admins); clients are not datums, so the ckey is the identity
	activate()

// Refuses deletion from advanced proc calls (permission elevation).
/datum/admins/lifecycle_keep(force)
	if(!IsAdminAdvancedProcCall())
		return FALSE
	alert_to_permissions_elevation_attempt(usr)
	return TRUE

/datum/admins/proc/activate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	GLOB.deadmins -= target
	GLOB.admin_datums[target] = src // ALLOW(registry): the admin holder tables are keyed by ckey and outlive the client (deadmin, protected admins); clients are not datums, so the ckey is the identity
	deadmined = FALSE
	if (GLOB.directory[target])
		associate(GLOB.directory[target]) //find the client for a ckey if they are connected and associate them with us

/datum/admins/proc/deactivate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	GLOB.deadmins[target] = src // ALLOW(registry): the admin holder tables are keyed by ckey and outlive the client (deadmin, protected admins); clients are not datums, so the ckey is the identity
	GLOB.admin_datums -= target
	deadmined = TRUE

	var/client/client = owner() || GLOB.directory[target]

	if (!isnull(client))
		disassociate()
		grant(client, granted_verb(/client/proc/readmin), src)

/datum/admins/proc/associate(client/client)
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return

	if(!istype(client))
		return

	if(client?.ckey != target)
		var/msg = " has attempted to associate with [target]'s admin datum"
		message_admins("[key_name_admin(client)][msg]")
		log_admin("[key_name(client)][msg]")
		return

	if (deadmined)
		activate()

	rel_set(src, nameof(owner), client)
	owner().holder = src
	owner().add_admin_verbs()
	revoke(owner(), granted_verb(/client/proc/readmin), src)
	owner().init_verbs() //re-initialize the verb list
	GLOB.admins |= client

	try_give_profiling()

/datum/admins/proc/disassociate()
	if(IsAdminAdvancedProcCall())
		alert_to_permissions_elevation_attempt(usr)
		return
	if(owner())
		GLOB.admins -= owner()
		owner().remove_admin_verbs()
		// owner.init_verbs() //re-initialize the verb list
		owner().holder = null
		rel_clear(src, nameof(owner))

/// Returns the feedback forum thread for the admin holder's owner, as according to DB.
/datum/admins/proc/feedback_link()
	// This intentionally does not follow the 10-second maximum TTL rule,
	// as this can be reloaded through the Reload-Admins verb.
	if (fetched_feedback_link == NO_FEEDBACK_LINK)
		return null

	if (!isnull(fetched_feedback_link))
		return fetched_feedback_link

	if (!SSdbcore.IsConnected())
		return FALSE

	// Not known yet: ask (io_job, nothing waits). The answer fills the cache for the next call.
	if(!feedback_link_pending)
		feedback_link_pending = io_job(src, /datum/io_backend/sql, "SELECT feedback FROM [format_table_name("admin")] WHERE ckey = :ckey", list("ckey" = owner()?.ckey), PROC_REF(feedback_link_arrived))
	return null

/// io_job() callback: caches the admin's feedback link (or that there is none).
/datum/admins/proc/feedback_link_arrived(list/result, error)
	feedback_link_pending = 0
	if(error)
		log_sql("Error retrieving feedback link for [src]: [error]")
		return
	var/list/rows = result["rows"]
	if(!length(rows))
		fetched_feedback_link = NO_FEEDBACK_LINK
		return
	var/list/row = rows[1]
	fetched_feedback_link = row[1] || NO_FEEDBACK_LINK

/datum/admins/proc/check_for_rights(rights_required)
	if(rights_required && !(rights_required & rank_flags()))
		return FALSE
	return TRUE

/datum/admins/proc/check_if_greater_rights_than_holder(datum/admins/other)
	if(!other)
		return TRUE //they have no rights
	if(rank_flags() == R_EVERYTHING)
		return TRUE //we have all the rights
	if(src == other)
		return TRUE //you always have more rights than yourself
	if(rank_flags() != other.rank_flags())
		if( (rank_flags() & other.rank_flags()) == other.rank_flags() )
			return TRUE //we have all the rights they have and more
	return FALSE

/// Get the rank name of the admin
/datum/admins/proc/rank_names()
	return join_admin_ranks(ranks)

/// Get the rank flags of the admin
/datum/admins/proc/rank_flags()
	var/combined_flags = NONE

	for (var/datum/admin_rank/rank as anything in ranks)
		combined_flags |= rank.rights

	return combined_flags

/// Get the permissions this admin is allowed to edit on other ranks
/datum/admins/proc/can_edit_rights_flags()
	var/combined_flags = NONE

	for (var/datum/admin_rank/rank as anything in ranks)
		combined_flags |= rank.can_edit_rights

	return combined_flags

/datum/admins/proc/try_give_profiling()
	if (CONFIG_GET(flag/forbid_admin_profiling))
		return

	if (given_profiling)
		return

	if (!(rank_flags() & R_DEBUG))
		return

	given_profiling = TRUE
	world.SetConfig("APP/admin", owner().ckey, "role=admin")

/datum/admins/vv_edit_var(var_name, var_value)
	return FALSE //nice try trialmin

/**
 * The one admin rights primitive: does `subject` hold at least ONE of `rights`? (rights 0 = "is an admin").
 * It never reads usr and never logs, so it is safe in polling (tgui state), callbacks and prompt flows.
 * Declare rights once at the entry point (ADMIN_VERB, ADMIN_STATE, TOPIC_RIGHTS) instead of re-checking inside.
 */
/proc/admin_can(client/subject, rights)
	READS_FROM()
	if(subject?.holder)
		return subject.holder.check_for_rights(rights)
	return FALSE

/// The admin holder of a client (null for a player): what the View Variables dispatch hands its VV_ADMIN_TOPIC ops.
/proc/admin_holder_of(client/subject)
	return subject?.holder

/**
 * admin_can() that audits a denial: one log line with the key, the entry point and the rights required.
 * Use it where an entry point cannot declare the rights itself (per-action rights inside one UI).
 * `show_msg` also tells the client why.
 */
/proc/admin_require(client/subject, rights, entry, show_msg = TRUE)
	if(admin_can(subject, rights))
		return TRUE
	admin_log_denial(subject, entry, rights, show_msg)
	return FALSE

/// The single denial audit line: "ADMIN DENIED: key entry=<entry> requires=<flags>".
/proc/admin_log_denial(client/subject, entry, rights, show_msg = FALSE)
	log_admin_private("ADMIN DENIED: [subject ? key_name(subject) : "(no client)"] entry=[entry] requires=[rights2text(rights, " ")]")
	if(show_msg && subject)
		to_chat(subject, span_red("Error: You do not have sufficient rights to do that. You require one of the following flags:[rights2text(rights," ")]."), confidential = TRUE)

/**
 * DEPRECATED: reads usr, so it is wrong in a callback or proc chain. Use admin_can(client, rights), or declare
 * the rights on the entry point. Kept as a thin usr wrapper; a shrink-only lint baseline tracks the remaining calls.
 */
/proc/check_rights(rights_required, show_msg=1)
	if(usr?.client && admin_can(usr.client, rights_required))
		return TRUE
	admin_log_denial(usr?.client, "check_rights in [caller?.proc]", rights_required, show_msg)
	return FALSE

//probably a bit iffy - will hopefully figure out a better solution
/proc/check_if_greater_rights_than(client/other)
	if(usr?.client)
		if(check_rights_for(usr.client, R_HOLDER))
			if(!other || !other.holder)
				return TRUE
			return usr.client.holder.check_if_greater_rights_than_holder(other.holder)
	return FALSE

/// Alias of admin_can(): whether subject has at least ONE of the rights specified in rights_required.
/proc/check_rights_for(client/subject, rights_required)
	READS_FROM()
	return admin_can(subject, rights_required)

/proc/GenerateToken()
	. = ""
	for(var/I in 1 to 32)
		. += "[rand(10)]"

/proc/RawHrefToken(forceGlobal = FALSE)
	var/tok = GLOB.href_token
	if(!forceGlobal && usr)
		var/client/C = usr.client
		return RawHrefTokenFor(C)
	return tok

/// Resolve the same admin token for an explicitly supplied current client.
/proc/RawHrefTokenFor(client/C)
	if(!C)
		log_runtime("Attempted to retrieve a HrefToken of an entity with no client.")
		return 0
	var/datum/admins/holder = C.holder
	return holder ? holder.href_token : GLOB.href_token

/// An ordinary synchronous caller supplies its actual actor instead of ambient usr.
/proc/HrefTokenFor(mob/actor)
	return "admin_token=[RawHrefTokenFor(actor?.client)]"

/proc/HrefToken(forceGlobal = FALSE)
	return "admin_token=[RawHrefToken(forceGlobal)]"

/proc/HrefTokenFormField(forceGlobal = FALSE)
	return "<input type='hidden' name='admin_token' value='[RawHrefToken(forceGlobal)]'>"

// Shared admin_rank registry entries.

/// The marked_datum this refers to (a relation view: null once that is deleted).
/datum/admins/proc/marked_datum() as /datum
	return marked_datum

/// The owner this refers to (a relation view: null once that is deleted).
/datum/admins/proc/owner() as /client
	return owner

/// The channel the admin newscaster is working on: a picked network channel (a relation view) or the scratch one.
/datum/admins/proc/admincaster_feed_channel() as /datum/feed_channel
	return admincaster_feed_channel || admincaster_scratch_channel

/// Replaces our ranks (a relation list) with `new_ranks`.
/datum/admins/proc/set_ranks(list/datum/admin_rank/new_ranks)
	rel_clear(src, nameof(ranks))
	for(var/datum/admin_rank/rank as anything in new_ranks)
		rel_add(src, nameof(ranks), rank)

/// The client's admin datum (null for a non-admin). The one read accessor outside modules/admin/holder*; rights
/// questions go through admin_can().
/client/proc/admin_datum() as /datum/admins
	return holder
