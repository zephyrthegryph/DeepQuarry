// Window-data pin drivers for the admin panels (dq_ui_pins.dm).
//
// No client exists in the unit-test world, so the rights checks and the Topic dispatch behind most buttons cannot run. Where a
// window button forwards into code that needs a client (a prompt, a rights check, admincaster_refresh), the driver changes the
// state that handler changes, the way it would, and says so in a comment; the handlers that work without a client are called.

/// Shared pieces of the admin-window drivers: an op context for the handlers and an admin holder.
/datum/ui_pin/admin_host
	var/datum/admins/holder
	var/datum/act/op/op_ctx

/// A fabricated op context with `user` as the actor, for calling a window's ui_act_* handler.
/datum/ui_pin/admin_host/proc/make_op()
	op_ctx = take(/datum/act/op)
	op_ctx.actor = user
	return op_ctx

/// An admin holder with a made-up rank; not tied to any client.
/datum/ui_pin/admin_host/proc/make_holder()
	var/datum/admin_rank/pin_rank = test.allocate(/datum/admin_rank, "DqPinRank", RANK_SOURCE_TXT, R_ADMIN|R_EVENT)
	holder = test.allocate(/datum/admins, list(pin_rank), "dqpinadmin")
	holder.admincaster_signature = "Pin Officer"
	return holder

/// Drops what the pin registered globally, and the op context.
/datum/ui_pin/admin_host/proc/cleanup_admin()
	if(holder)
		GLOB.admin_datums -= holder.target
		GLOB.deadmins -= holder.target
	if(op_ctx)
		op_ctx.release()
		op_ctx = null

// ---- Admin newscaster -----------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/newscaster_panel
	host_type = /datum/newscaster_panel

/datum/ui_pin/admin_host/newscaster_panel/script(turf/T)
	make_user(T)
	make_holder()
	host = test.allocate(/datum/newscaster_panel, holder)
	watch_host()
	snap("initial")
	// The ac_* buttons forward into the admin Topic, which needs a client; the state they change is set here directly.
	holder.admincaster_screen = 2 // create_channel
	snap("create_channel_screen")
	var/datum/feed_channel/draft = holder.admincaster_feed_channel()
	draft.channel_name = "Dq Pin Channel" // set_channel_name
	draft.locked = TRUE // set_channel_lock
	holder.admincaster_resync()
	snap("channel_draft")
	GLOB.news_network.CreateFeedChannel(draft.channel_name, holder.admincaster_signature, draft.locked, 1) // submit_new_channel
	holder.admincaster_screen = 5
	holder.admincaster_resync()
	snap("channel_created")
	var/datum/feed_channel/made
	for(var/datum/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == "Dq Pin Channel")
			made = FC
	holder.admincaster_screen = 3 // create_story
	holder.admincaster_feed_message.title = "Pin Story" // set_new_title
	holder.admincaster_feed_message.body = "Pin story body." // set_new_message
	snap("story_draft")
	GLOB.news_network.SubmitArticle(holder.admincaster_feed_message.body, holder.admincaster_signature, "Dq Pin Channel", null, 1, "", holder.admincaster_feed_message.title) // submit_new_message
	holder.admincaster_screen = 4
	var/datum/feed_message/story
	if(made)
		for(var/datum/feed_message/posted in made.messages)
			posted.time_stamp = "00:00" // the story stamps the station clock
			story = posted
	snap("story_posted")
	if(made)
		rel_set(holder, nameof(/datum/admins::admincaster_feed_channel), made) // show_channel
	holder.admincaster_screen = 9
	snap("channel_shown")
	if(made)
		made.censored = TRUE // toggle_d_notice
	if(story)
		story.backup_author = story.author // censor_story_author
		story.author = "REDACTED"
	snap("censored")
	var/datum/feed_message/wanted = new /datum/feed_message
	wanted.author = "Pin Fugitive" // set_wanted_name
	wanted.body = "Wanted for pinning." // set_wanted_desc
	wanted.backup_author = holder.admincaster_signature
	wanted.is_admin_message = 1
	rel_set(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), wanted) // submit_wanted
	holder.admincaster_screen = 18
	snap("wanted_issued")
	own_clear(GLOB.news_network, nameof(/datum/feed_network::wanted_issue_owned), OWN_DELETE) // cancel_wanted
	holder.admincaster_screen = 17
	snap("wanted_cancelled")
	if(made)
		rel_clear(holder, nameof(/datum/admins::admincaster_feed_channel))
		own_remove(GLOB.news_network, nameof(/datum/feed_network::network_channels), made)
	cleanup_admin()

// ---- Edit Player ----------------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/edit_player_panel
	host_type = /datum/edit_player_panel

/datum/ui_pin/admin_host/edit_player_panel/script(turf/T)
	make_user(T)
	make_holder()
	var/mob/living/carbon/human/subject = test.allocate(/mob/living/carbon/human, T)
	subject.real_name = "Pin Subject"
	subject.name = "Pin Subject"
	host = test.allocate(/datum/edit_player_panel, holder, subject)
	watch_host()
	snap("initial")
	subject.name = "Renamed Subject" // the panel buttons forward to Topic, which needs a client; the body is changed directly
	snap("renamed")
	var/list/lang_keys = GLOBAL_TABLE_GET(non_innate_language_keys)
	var/lang_key = length(lang_keys) ? lang_keys[1] : null
	if(lang_key)
		subject.add_language(lang_key) // toglang
		snap("language_added")
		subject.remove_language(lang_key)
		snap("language_removed")
	subject.dna.SetSEState(5, TRUE) // togmutate
	snap("gene_toggled")
	var/mob/living/carbon/human/monkey/ape = test.allocate(/mob/living/carbon/human/monkey, T) // turn_monkey: the panel is now about another body
	ape.name = "Pin Ape"
	rel_set(host, nameof(/datum/edit_player_panel::target), ape)
	snap("retargeted_monkey")
	var/mob/living/simple_mob/animal/passive/dog/corgi/pup = test.allocate(/mob/living/simple_mob/animal/passive/dog/corgi, T) // corgione
	pup.name = "Pin Pup"
	rel_set(host, nameof(/datum/edit_player_panel::target), pup)
	snap("retargeted_corgi")
	cleanup_admin()

// ---- Tag menu -------------------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/tag_menu_panel
	host_type = /datum/tag_menu_panel

/datum/ui_pin/admin_host/tag_menu_panel/script(turf/T)
	make_user(T)
	make_holder()
	host = test.allocate(/datum/tag_menu_panel, holder)
	watch_host()
	snap("initial")
	var/obj/item/paper/first = test.allocate(/obj/item/paper, T)
	first.name = "pin paper one"
	var/obj/item/paper/second = test.allocate(/obj/item/paper, T)
	second.name = "pin paper two"
	LAZYADD(holder.tagged_datums, first) // tagging happens through Topic (rights check), so the list is edited the way it does
	snap("one_tagged")
	LAZYADD(holder.tagged_datums, second)
	LAZYADD(holder.tagged_datums, user)
	snap("three_tagged")
	rel_set(holder, nameof(/datum/admins::marked_datum), second) // mark
	snap("marked")
	var/datum/act/op/A = make_op()
	var/datum/tag_menu_panel/panel = host
	panel.ui_act_refresh(A)
	snap("refreshed")
	LAZYREMOVE(holder.tagged_datums, first) // untag
	snap("untagged")
	rel_clear(holder, nameof(/datum/admins::marked_datum))
	holder.tagged_datums = null
	cleanup_admin()

// ---- Unban ----------------------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/unban_panel
	host_type = /datum/unban_panel

/datum/ui_pin/admin_host/unban_panel/script(turf/T)
	make_user(T)
	make_holder()
	host = test.allocate(/datum/unban_panel, holder)
	watch_host()
	snap("initial")
	var/datum/act/op/A = make_op()
	var/datum/unban_panel/panel = host
	panel.ui_act_refresh(A) // reads the ban savefile, which holds nothing here
	snap("refreshed_empty")
	// The ban savefile is a shared cursor the test must not write, so the snapshot a savefile read leaves is set the way it would be.
	var/list/ban_one = list("key_id" = "pinkeyone1", "key" = "pinkeyone", "id" = "1", "ip" = "10.0.0.1", "reason" = "Pin reason one", "by" = "PinAdmin", "expiry" = "Permaban")
	var/list/ban_two = list("key_id" = "pinkeytwo2", "key" = "pinkeytwo", "id" = "2", "ip" = "10.0.0.2", "reason" = "Pin reason two", "by" = "PinAdmin", "expiry" = "2.0 Hours")
	panel.shown_rows = list(ban_one)
	snap("one_ban")
	panel.shown_rows = list(ban_one, ban_two)
	snap("two_bans")
	panel.shown_rows = list(ban_two) // unban
	snap("one_unbanned")
	panel.shown_rows = null
	cleanup_admin()

// ---- Job-ban panel --------------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/jobban_panel
	host_type = /datum/jobban_panel

/datum/ui_pin/admin_host/jobban_panel/script(turf/T)
	make_user(T)
	make_holder()
	var/mob/living/carbon/human/subject = test.allocate(/mob/living/carbon/human, T)
	subject.real_name = "Pin Banned"
	subject.name = "Pin Banned"
	host = test.allocate(/datum/jobban_panel, holder, subject)
	watch_host()
	var/list/saved_bans = GLOB.jobban_keylist.Copy()
	snap("initial")
	// The toggle buttons go through the holder Topic (a rights check) and save a file; the ban list is edited the way jobban_fullban does (the subject has no key, so the entry has an empty ckey).
	GLOB.jobban_keylist += " - [JOB_INTERNAL_AFFAIRS_AGENT] ## pin reason"
	snap("one_job_banned")
	GLOB.jobban_keylist += " - commanddept"
	snap("department_banned")
	var/datum/act/op/A = make_op()
	var/datum/jobban_panel/panel = host
	panel.ui_act_refresh(A)
	snap("refreshed")
	GLOB.jobban_keylist -= " - [JOB_INTERNAL_AFFAIRS_AGENT] ## pin reason"
	snap("job_unbanned")
	GLOB.jobban_keylist.Cut()
	GLOB.jobban_keylist += saved_bans
	cleanup_admin()

// ---- Delete book ----------------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/dq_delete_book_panel
	host_type = /datum/dq_delete_book_panel

/datum/ui_pin/admin_host/dq_delete_book_panel/script(turf/T)
	make_user(T)
	var/obj/machinery/librarycomp/comp = test.allocate(/obj/machinery/librarycomp, T)
	var/list/book_one = list("author" = "Pin Author A", "title" = "Pin Book One", "category" = "Fiction", "id" = "1")
	var/list/book_two = list("author" = "Pin Author B", "title" = "Pin Book Two", "category" = "Reference", "id" = "2")
	host = test.allocate(/datum/dq_delete_book_panel, comp, list(book_one, book_two), "")
	watch_host()
	snap("initial")
	var/datum/dq_delete_book_panel/panel = host
	// The sort / order / delete buttons call the library computer's tgui_act with the open window, which needs a client; they change these.
	comp.sortby = "title" // sort
	snap("sorted_by_title")
	panel.books = list(book_two, book_one) // order_by_id
	snap("ordered_by_id")
	panel.books = list(book_two) // delete
	snap("book_deleted")
	panel.error_msg = "Pin query failed"
	snap("error_shown")
	panel.error_msg = ""
	panel.books = list()
	snap("empty")

// ---- Syndicate beacon (the other window host in misc_admin_panels.dm) -----------------------------------------------------

/datum/ui_pin/admin_host/syndicate_beacon_virgo
	host_type = /obj/machinery/syndicate_beacon/virgo

/datum/ui_pin/admin_host/syndicate_beacon_virgo/script(turf/T)
	make_user(T)
	var/obj/machinery/syndicate_beacon/virgo/beacon = test.allocate(/obj/machinery/syndicate_beacon/virgo, T)
	host = beacon
	watch_host()
	snap("initial")
	beacon.temptext = "Pin greeting" // the beacon's own dialogue text
	snap("text_set")
	beacon.selfdestructing = TRUE
	snap("selfdestructing")
	beacon.selfdestructing = FALSE
	beacon.charges = 0 // transfer_supplies spends the charge
	snap("charges_spent")

// ---- Magnetic control console ---------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/magnetic_controller
	host_type = /obj/machinery/magnetic_controller

/datum/ui_pin/admin_host/magnetic_controller/script(turf/T)
	make_user(T)
	var/obj/machinery/magnetic_controller/console = test.allocate(/obj/machinery/magnetic_controller, T)
	host = console
	var/turf/beside = locate(T.x + 1, T.y, T.z)
	var/obj/machinery/magnetic_module/magnet = test.allocate(/obj/machinery/magnetic_module, beside)
	magnet.freq = console.frequency
	magnet.code = console.code
	rel_add(console, nameof(/obj/machinery/magnetic_controller::magnets), magnet)
	watch_host()
	snap("initial")
	var/datum/act/op/A = make_op()
	console.ui_act_speed_plus(A)
	snap("speed_plus")
	console.ui_act_speed_minus(A)
	console.ui_act_speed_minus(A)
	snap("speed_minus_twice")
	console.path = "NSEW" // set_path: the path is asked for with a prompt, whose answer sets these (magnet_path_entered)
	console.pathpos = 1
	console.filter_path()
	snap("path_set")
	console.ui_act_toggle_moving(A)
	snap("moving")
	console.ui_act_toggle_moving(A)
	snap("stopped")
	console.ui_act_toggle_power(A)
	snap("power_toggled")
	console.ui_act_elec_plus(A)
	console.ui_act_mag_plus(A)
	snap("levels_raised")
	console.autolink = FALSE
	snap("autolink_off")
	cleanup_admin()

// ---- Telecomms traffic control --------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/telecomms_traffic
	host_type = /obj/machinery/computer/telecomms/traffic

/datum/ui_pin/admin_host/telecomms_traffic/script(turf/T)
	make_user(T)
	var/obj/machinery/computer/telecomms/traffic/console = test.allocate(/obj/machinery/computer/telecomms/traffic, T)
	console.req_access = null // the access gate is not what is pinned
	console.network = "dqpin_net"
	var/turf/beside = locate(T.x + 1, T.y, T.z)
	var/obj/machinery/telecomms/server/box = test.allocate(/obj/machinery/telecomms/server, beside)
	box.id = "dqpin_server"
	box.network = "dqpin_net"
	host = console
	watch_host()
	snap("initial")
	var/datum/act/op/A = make_op()
	console.ui_act_scan(A)
	snap("scanned")
	console.ui_act_scan(A)
	snap("scan_refused_buffer_full")
	console.ui_act_view_server(A, "dqpin_server")
	snap("server_viewed")
	console.ui_act_toggle_run(A)
	snap("autorun_on")
	console.ui_act_toggle_run(A)
	snap("autorun_off")
	console.ui_act_main_menu(A)
	snap("main_menu")
	console.ui_act_clear_temp(A)
	snap("temp_cleared")
	console.ui_act_flush_buffer(A)
	snap("buffer_flushed")
	cleanup_admin()

// ---- Edit memory ----------------------------------------------------------------------------------------------------------

/datum/ui_pin/admin_host/edit_memory_panel
	host_type = /datum/edit_memory_panel

/datum/ui_pin/admin_host/edit_memory_panel/script(turf/T)
	make_user(T)
	var/datum/mind/subject = test.allocate(/datum/mind, "dqpinkey")
	subject.name = "Pin Mind"
	subject.assigned_role = "Assistant"
	var/datum/edit_memory_panel/panel = test.allocate(/datum/edit_memory_panel, subject, user)
	host = panel
	watch_host()
	snap("initial")
	// The buttons check the admin's client for rights first and ask with prompts, so the mind is changed the way their handlers change it.
	subject.assigned_role = "Captain" // edit_role
	snap("role_set")
	subject.memory = "Pin memory text" // edit_memory
	snap("memory_set")
	subject.ambitions = "Pin ambition" // edit_ambitions
	snap("ambitions_set")
	var/datum/objective/first = test.allocate(/datum/objective, "Pin objective one")
	rel_add(subject, nameof(/datum/mind::objectives), first) // obj_add
	snap("objective_added")
	var/datum/objective/second = test.allocate(/datum/objective, "Pin objective two")
	rel_add(subject, nameof(/datum/mind::objectives), second)
	first.completed = TRUE // obj_toggle_complete
	snap("objective_completed")
	rel_remove(subject, nameof(/datum/mind::objectives), first) // obj_delete
	snap("objective_deleted")
	panel.snapshot_antag_blocks() // refresh_antags
	snap("antags_refreshed")
	rel_remove(subject, nameof(/datum/mind::objectives), second)
	cleanup_admin()
