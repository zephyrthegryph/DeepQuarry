	////////////
	//SECURITY//
	////////////

GLOBAL_LIST_INIT(blacklisted_builds, list(
	"1622" = "Bug breaking rendering can lead to wallhacks.",
	))

#define UPLOAD_LIMIT		10485760	//Restricts client uploads to the server to 10MB //Boosted this thing. What's the worst that can happen?
#define MIN_CLIENT_VERSION	0		//Just an ambiguously low version for now, I don't want to suddenly stop people playing.
									//I would just like the code ready should it ever need to be used.
#define LIMITER_SIZE 12
#define CURRENT_SECOND 1
#define SECOND_COUNT 2
#define CURRENT_MINUTE 3
#define MINUTE_COUNT 4
#define ADMINSWARNED_AT 5

//# define TOPIC_DEBUGGING 1

/client/proc/reduce_minute_count()
	if (!topiclimiter)
		topiclimiter = new(LIMITER_SIZE)
	if(topiclimiter[MINUTE_COUNT] > 0)
		topiclimiter[MINUTE_COUNT] -= 1

	/*
	When somebody clicks a link in game, this Topic is called first.
	It does the stuff in this proc and  then is redirected to the Topic() proc for the src=[0xWhatever]
	(if specified in the link). ie locate(hsrc).Topic()

	Such links can be spoofed.

	Because of this certain things MUST be considered whenever adding a Topic() for something:
		- Can it be fed harmful values which could cause runtimes?
		- Is the Topic call an admin-only thing?
		- If so, does it have checks to see if the person who called it (usr.client) is an admin?
		- Are the processes being called by Topic() particularly laggy?
		- If so, is there any protection against somebody spam-clicking a link?
	If you have any  questions about this stuff feel free to ask. ~Carn
	*/
// ALLOW(sys_topic_override): BYOND's href entry point: rate limits, tgui middleware and logging, then the TOPIC_ACTION dispatcher.
/client/Topic(href, href_list, hsrc)
	// asset_cache: the ack needs no mob, so it is handled before the usr gate (a body swap
	// between the send and the ack must not drop it)
	var/asset_cache_job
	// ALLOW(sys_topic_raw_dispatch): client/Topic is BYOND's href entry: transport-level keys (asset cache, rate limiter, statbrowser) are read before any datum dispatch.
	if(href_list["asset_cache_confirm_arrival"])
		asset_cache_job = asset_cache_confirm_arrival(href_list["asset_cache_confirm_arrival"])
		if (!asset_cache_job)
			return

	if(!usr || usr != mob)	//stops us calling Topic for somebody else's client. Also helps prevent usr=null
		return
	var/mob/user = mob

	#if defined(TOPIC_DEBUGGING)
	to_world("[src]'s Topic: [href] destined for [hsrc].")

	// ALLOW(sys_topic_raw_dispatch): client/Topic is BYOND's href entry: transport-level keys (asset cache, rate limiter, statbrowser) are read before any datum dispatch.
	if(href_list["nano_err"]) //nano throwing errors
		to_world("## NanoUI, Subject [src]: " + html_decode(href_list["nano_err")]) //NANO DEBUG HOOK

	#endif

	// Rate limiting
	var/mtl = CONFIG_GET(number/minute_topic_limit)
	if(!bypass_topic_limit(href_list))
		if (!check_rights_for(src, R_HOLDER) && mtl)
			var/minute = round(world.time, 600)
			if (!topiclimiter)
				topiclimiter = new(LIMITER_SIZE)
			if (minute != topiclimiter[CURRENT_MINUTE])
				topiclimiter[CURRENT_MINUTE] = minute
				topiclimiter[MINUTE_COUNT] = 0
			// ALLOW(sys_topic_raw_dispatch): client/Topic is BYOND's href entry: transport-level keys (asset cache, rate limiter, statbrowser) are read before any datum dispatch.
			if(href_list["window_id"] != SKIN_STAT_BROWSER)
				topiclimiter[MINUTE_COUNT] += 1
			if (topiclimiter[MINUTE_COUNT] > mtl)
				var/msg = "Your previous action was ignored because you've done too many in a minute."
				if (minute != topiclimiter[ADMINSWARNED_AT]) //only one admin message per-minute. (if they spam the admins can just boot/ban them)
					topiclimiter[ADMINSWARNED_AT] = minute
					msg += " Administrators have been informed."
					log_game("[key_name(src)] Has hit the per-minute topic limit of [mtl] topic calls in a given game minute")
					message_admins("[ADMIN_LOOKUPFLW(user)] [ADMIN_KICK(user)] Has hit the per-minute topic limit of [mtl] topic calls in a given game minute")
				to_chat(src, span_danger("[msg]"))
				return

		var/stl = CONFIG_GET(number/second_topic_limit)
		if (!check_rights_for(src, R_HOLDER) && stl)
			var/second = round(world.time, 10)
			if (!topiclimiter)
				topiclimiter = new(LIMITER_SIZE)
			if (second != topiclimiter[CURRENT_SECOND])
				topiclimiter[CURRENT_SECOND] = second
				topiclimiter[SECOND_COUNT] = 0
			topiclimiter[SECOND_COUNT] += 1
			if (topiclimiter[SECOND_COUNT] > stl)
				to_chat(src, span_danger("Your previous action was ignored because you've done too many in a second"))
				return

	//search the href for script injection
	if(findtext(href,"<script",1,0) )
		log_world("Attempted use of scripts within a topic call, by [src]")
		message_admins("Attempted use of scripts within a topic call, by [src]")
		return

	// Tgui Topic middleware
	if(tgui_Topic(href_list, mob))
		return

	//Logs all hrefs
	log_href("[src] (usr:[user]\[[COORD(user)]\]) : [hsrc ? "[hsrc] " : ""][href]")

	//byond bug ID:2256651
	if (asset_cache_job && session && (asset_cache_job in session.completed_asset_jobs))
		to_chat(src, span_danger("An error has been detected in how your client is receiving resources. Attempting to correct.... (If you keep seeing these messages you might want to close byond and reconnect)"))
		src << browse("...", "window=asset_cache_browser")
		return
	// The client's own href actions (TOPIC_ACTION rows on /client, below).
	if(!hsrc && topic_dispatch(src, user, href_list))
		return

	// ALLOW(sys_topic_raw_dispatch): client/Topic is BYOND's href entry: transport-level keys (asset cache, rate limiter, statbrowser) are read before any datum dispatch.
	switch(href_list["_src_"])
		if("holder")	hsrc = holder
		if("usr")		hsrc = mob
		if("vars")		return vv_topic(href_list)

	if (hsrc)
		var/datum/real_src = hsrc
		if(QDELETED(real_src))
			return

	//fun fact: Topic() acts like a verb and is executed at the end of the tick like other verbs. So it goes through the input
	//inbox, which resolves it on the spot while the tick has room and queues it for phase K if the server is overloaded
	if(hsrc && hsrc != holder)
		input_submit(new /datum/input_event/topic(user, hsrc, href, href_list))
		return
	..() //redirect to hsrc.Topic()

// ---------------------------------------------------------------- the client's href actions

//Admin PM
TOPIC_ACTION(/client, "priv_msg", PROC_REF(topic_priv_msg), TOPIC_TEXT("priv_msg", 64))
TOPIC_ACTION(/client, "mentorhelp_msg", PROC_REF(topic_mentorhelp_msg), TOPIC_TEXT("mentorhelp_msg", 64))
TOPIC_ACTION(/client, "discord_reg", PROC_REF(topic_discord_reg), TOPIC_TEXT("discord_reg", 128))
TOPIC_ACTION(/client, "reload_statbrowser", PROC_REF(topic_reload_statbrowser))
TOPIC_ACTION(/client, "asset_cache_preload_data", PROC_REF(topic_asset_cache_preload_data), TOPIC_TEXT("asset_cache_preload_data"))
TOPIC_ACTION(/client, "commandbar_typing", PROC_REF(topic_commandbar_typing), TOPIC_TEXT("verb", 64), TOPIC_NUM("argument_length"))
TOPIC_ACTION(/client, "action=openLink", PROC_REF(topic_open_link), TOPIC_TEXT("link", 1024))

/// A client passed in an href as a client ref, a mob ref (older links) or a ckey.
/client/proc/topic_client_or_ckey(raw)
	var/client/C = topic_resolve_ref(src, raw, /client, TOPIC_IN_CLIENTS)
	if(!C)
		var/mob/M = topic_resolve_ref(src, raw, /mob, TOPIC_ANY)
		C = M?.client
	return C

/client/proc/topic_priv_msg(mob/user, list/args)
	var/passed_key = args["priv_msg"]
	var/C = topic_client_or_ckey(passed_key)
	if(!C && istext(passed_key))
		C = passed_key
	cmd_admin_pm(C, null)
	return TRUE

/client/proc/topic_mentorhelp_msg(mob/user, list/args)
	cmd_mentor_pm(topic_client_or_ckey(args["mentorhelp_msg"]), null)
	return TRUE

/client/proc/topic_discord_reg(mob/user, list/args)
	var/their_id = html_decode(args["discord_reg"])
	var/sane = FALSE
	for(var/list/L as anything in GLOB.pending_discord_registrations)
		if(!islist(L))
			GLOB.pending_discord_registrations -= L
			continue
		if(L["ckey"] == ckey && L["id"] == their_id)
			GLOB.pending_discord_registrations -= list(L)
			var/time = L["time"]
			if((world.realtime - time) > 10 MINUTES)
				to_chat(src, span_warning("Sorry, that link has expired. Please request another on Discord."))
				return TRUE
			sane = TRUE
			break

	if(!sane)
		to_chat(src, span_warning("Sorry, that link doesn't appear to be valid. Please try again."))
		return TRUE

	// om_io: the player hears back when the database answers.
	om_io(null, /datum/om/io/sql, "UPDATE erro_player SET discord_id = :discord_id WHERE ckey = :ckey", list("discord_id" = their_id, "ckey" = ckey), GLOBAL_PROC_REF(discord_registration_done), ckey, their_id)
	return TRUE

/client/proc/topic_reload_statbrowser(mob/user, list/args)
	stat_panel.reinitialize()
	return TRUE

/client/proc/topic_asset_cache_preload_data(mob/user, list/args)
	asset_cache_preload_data(args["asset_cache_preload_data"])
	return TRUE

/client/proc/topic_commandbar_typing(mob/user, list/args)
	handle_commandbar_typing(args["verb"], args["argument_length"])
	return TRUE

/client/proc/topic_open_link(mob/user, list/args)
	src << link(args["link"])
	return TRUE

///dumb workaround because byond doesnt seem to recognize the Topic() typepath for /datum/proc/Topic() from the client Topic,
///so we cant queue it without this
/client/proc/_Topic(datum/hsrc, href, list/href_list)
	return hsrc.Topic(href, href_list)

/client/proc/is_localhost()
	var/static/localhost_addresses = list(
		"127.0.0.1",
		"::1",
		null,
	)
	return address in localhost_addresses

//This stops files larger than UPLOAD_LIMIT being sent from client to server via input(), client.Import() etc.
/client/AllowUpload(filename, filelength)
	if(filelength > UPLOAD_LIMIT)
		to_chat(src, span_red("Error: AllowUpload(): File Upload too large. Upload Limit: [UPLOAD_LIMIT/1024]KiB."))
		return 0
	// Upload spam prevention is not needed at the moment: code/_helpers/files.dm has the timer if it is.
	return 1

	///////////
	//CONNECT//
	///////////
/client/New(TopicData)
	TopicData = null //Prevent calls to client.Topic from connect
	session = new /datum/client_session(src) // ALLOW(ownership): /client is not a datum; it holds this directly

	if(connection != "seeker" && connection != "web")//Invalid connection type.
		return null

	winset(src, null, "browser-options=[DEFAULT_CLIENT_BROWSER_OPTIONS]")

	if(!(connection in list("seeker", "web")))					//Invalid connection type.
		return null
	if(byond_version < MIN_CLIENT_VERSION)		//Out of date client.
		return null

	if(!CONFIG_GET(flag/guests_allowed) && IsGuestKey(key))
		alert(src,"This server doesn't allow guest accounts to play. Please go to https://www.byond.com/ and register for a key.","Guest") // ALLOW(scheduler): the client is deleted next, so the message must block until it's read
		del(src) // ALLOW(scheduler): client: disconnects the client
		return

	//Only show this if they are put into a new_player mob. Otherwise, "what title screen?"
	if(isnewplayer(src.mob))
		to_chat(src, span_red("If the title screen is black, resources are still downloading. Please be patient until the title screen appears."))

	GLOB.clients += src // ALLOW(registry): /client is not a datum: no qdel, no registry hooks
	GLOB.directory[ckey] = src // ALLOW(registry): GLOB.directory maps ckey -> client; clients are not datums
	SSinput.wake_work_item(TYPE_PROC_REF(/datum/system/input, key_step))

	if(persistent_client_for(ckey))
		persistent_client = persistent_client_for(ckey) // ALLOW(ownership): /client is not a datum; it holds these directly
	else
		persistent_client = new /datum/persistent_client(ckey) // ALLOW(ownership): /client is not a datum; it holds these directly
	persistent_client.set_client(src)

	if (CONFIG_GET(flag/chatlog_database_backend))
		chatlog_token = vchatlog_generate_token(ckey, GLOB.round_id)

	winset(src, null, list("browser-options" = "find,refresh"))
	// Instantiate stat panel
	stat_panel = new /datum/tgui_window(src, SKIN_STAT_BROWSER) // ALLOW(ownership): /client is not a datum; it holds these directly
	stat_panel.subscribe(src, PROC_REF(on_stat_panel_message))

	// Instantiate tgui panel
	tgui_say = new /datum/tgui_say(src, SKIN_TGUI_SAY) // ALLOW(ownership): /client is not a datum; it holds these directly
	tgui_shocker = new /datum/tgui_shock(src, SKIN_TGUI_SHOCK) // ALLOW(ownership): /client is not a datum; it holds these directly
	initialize_commandbar_spy()
	tgui_panel = new /datum/tgui_panel(src, SKIN_CHAT_BROWSER) // ALLOW(ownership): /client is not a datum; it holds these directly

	GLOB.tickets.ClientLogin(src)

	//preferences datum - also holds some persistant data for the client (because we may as well keep these datums to a minimum)
	prefs = GLOB.preferences_datums[ckey] // ALLOW(ownership): /client is not a datum; it holds these directly
	if(prefs)
		rel_set(prefs, nameof(prefs.client), src)
		// A reconnect keeps the in-memory savefile (saves write through it); re-reading it from
		// disk here was I/O inside client/New for nothing.
		if(!prefs.savefile)
			prefs.load_savefile()
		prefs.apply_all_client_preferences()
	else
		prefs = new /datum/preferences(src) // ALLOW(ownership): /client is not a datum; it holds these directly
		GLOB.preferences_datums[ckey] = prefs
	prefs.last_ip = address				//these are gonna be used for banning
	prefs.last_id = computer_id			//these are gonna be used for banning

	var/full_version = "[byond_version].[byond_build ? byond_build : "xxx"]"
	log_access("Login: [key_name(src)] from [address ? address : "localhost"]-[computer_id] || BYOND v[full_version]")

	prefs_vr = new/datum/vore_preferences(src) // ALLOW(ownership): /client is not a datum; it holds these directly

	. = ..()	//calls mob.Login()

	// Admin Verbs need the client's mob to exist. Must be after ..()
	var/connecting_admin = FALSE //because de-admined admins connecting should be treated like admins.
	//Admin Authorisation
	var/datum/admins/admin_datum = GLOB.admin_datums[ckey]
	if (!isnull(admin_datum))
		admin_datum.associate(src)
		connecting_admin = TRUE
	else if(GLOB.deadmins[ckey])
		grant(src, granted_verb(/client/proc/readmin), GLOB.deadmins[ckey])
		connecting_admin = TRUE

	if (byond_version >= 512)
		if (!byond_build || byond_build < 1386)
			message_admins(span_adminnotice("[key_name(src)] has been detected as spoofing their byond version. Connection rejected."))
			//add_system_note("Spoofed-Byond-Version", "Detected as using a spoofed byond version.")
			log_suspicious_login("Failed Login: [key] - Spoofed byond version")
			spent(src)
			return

		if (num2text(byond_build) in GLOB.blacklisted_builds)
			log_access("Failed login: [key] - blacklisted byond version")
			to_chat_immediate(src, span_userdanger("Your version of byond is blacklisted."))
			to_chat_immediate(src, span_danger("Byond build [byond_build] ([byond_version].[byond_build]) has been blacklisted for the following reason: [GLOB.blacklisted_builds[num2text(byond_build)]]."))
			to_chat_immediate(src, span_danger("Please download a new version of byond. If [byond_build] is the latest, you can go to <a href=\"https://secure.byond.com/download/build\">BYOND's website</a> to download other versions."))
			if(connecting_admin)
				to_chat_immediate(src, "As an admin, you are being allowed to continue using this version, but please consider changing byond versions")
			else
				spent(src)
				return

	// A runtime in preference sanitizing (preview icon rebuilds, trait re-application) must never
	// abort login: the stat panel and tgui below would never initialize and the client sits on a
	// white screen.
	try
		prefs.sanitize_preferences()
	catch(var/exception/prefs_error)
		stack_trace("client/New: sanitize_preferences runtimed for [key]: [prefs_error.name] at [prefs_error.file]:[prefs_error.line]; continuing login")
	if(prefs)
		prefs.selecting_slots = FALSE

	// Initialize stat panel
	stat_panel.initialize(
		inline_html = file2text('html/statbrowser.html'),
		inline_js = file2text('html/statbrowser.js'),
		inline_css = file2text('html/statbrowser.css'),
	)
	after(src, 30 SECONDS, PROC_REF(check_panel_loaded))

	acquire_dpi()

	tgui_panel.initialize()

	// Initialize tgui panel
	tgui_say.initialize()
	tgui_shocker.initialize()

	loot_panel = new /datum/lootpanel(src) // ALLOW(ownership): /client is not a datum; it holds these directly

	EXPIRY_STAMP(src, connection_time, CLOCK_WORLD)
	connection_realtime = world.realtime
	connection_timeofday = world.timeofday

	dx_winexists(src, src, SKIN_ASSET_CACHE_BROWSER, PROC_REF(asset_browser_checked)) // a client round trip

	if(holder)
		add_admin_verbs()
		admin_memo_show()
		message_admins("Staff login: [key_name(src)]") // Admin Login Notice //Edit2: This logs more than just admins so why not change it

	winset(src, null, "command=\".configure graphics-hwmode on\"")

	start_login_gate()

	send_resources()

	if(!void)
		void = new /atom/movable/screen/click_catcher() // ALLOW(ownership): /client is not a datum; it holds these directly
	screen += void

	attempt_auto_fit_viewport()
	fully_created = TRUE
	SStgui.reconcile_client_windows(src)
	SStgui.schedule_client_prewarm(src)

	// Now that we're fully initialized, use our prefs
	if(prefs?.read_preference(/datum/preference/toggle/browser_dev_tools))
		winset(src, null, "browser-options=[DEFAULT_CLIENT_BROWSER_OPTIONS],devtools")

	//////////////
	//DISCONNECT//
	//////////////
/client/Del()
	if(!gc_destroyed)
		gc_destroyed = EXPIRY_AT(null, CLOCK_WORLD, 0) // ALLOW(sys_world_time_write): gc_destroyed doubles as the QDELETED flag, a raw stamp by contract (garbage.dm)
		if (!QDELING(src))
			stack_trace("Client does not purport to be QDELING, this is going to cause bugs in other places!")

		Destroy() //Clean up signals and timers.
	return ..()

// A client logs out of the directory, admins and tickets.
/client/Destroy()
	// A client is not a datum: it is the one owner of its panels, windows and screens by design,
	// so they are plain vars, deleted here by hand.
	GLOB.directory -= ckey
	GLOB.clients -= src
	persistent_client?.set_client(null)

	log_access("Logout: [key_name(src)]")
	GLOB.tickets.ClientLogout(src)
	if(holder)
		rel_clear(holder, nameof(holder.owner))
		GLOB.admins -= src
	if(skybox)
		ended_with(skybox, src)
		skybox = null // ALLOW(ownership): /client is not a datum; it holds these directly
	if(fakeConversations)
		ended_with(fakeConversations, src)
		fakeConversations = null // ALLOW(ownership): /client is not a datum; it holds these directly
	// Every connection-scoped datum (panels, tgui windows, say/shock, tooltips, media, loot
	// panel, interaction menu, keybind editor, ...) is owned by the session.
	ended_with(session, src)
	session = null // ALLOW(ownership): /client is not a datum; it holds this directly
	..()
	return QDEL_HINT_HARDDEL_NOW

// ---------------------------------------------------------------- the login gate
//
// A connecting client is held (login_pending) until its login checks have answered: the
// database ban check (world/IsBanned() can't wait on a query, so it runs here), the player
// record, the BYOND join date and the IP reputation lookups. Nothing waits: the checks run as
// a prompt flow on the client (flow_io.dm) and each answer re-runs them. While held, the lobby
// refuses to join or observe (login_hold_refuses()); the client is then admitted
// (login_admit()) or disconnected. A client that reconnects into a body it already has keeps
// it meanwhile, but is disconnected all the same if the ban check says so. If the answers
// never come (the I/O lane abandons a job after five minutes, or a check errors),
// LOGIN_GATE_TIMEOUT admits the client, as a failed check always has: the gate fails open.

#define LOGIN_GATE_TIMEOUT (90 SECONDS)

/// TRUE while the login checks are outstanding.
/client/var/login_pending = FALSE

/// Holds the client and starts its login checks. Called once, from client/New().
/client/proc/start_login_gate()
	login_pending = TRUE
	log_access("Login gate: holding [key_name(src)] for its login checks")
	after(LOGIN_GATE_TIMEOUT, GLOBAL_PROC_REF(login_gate_timeout), ckey, clock = CLOCK_WORLD, with = list(computer_id))
	log_client_to_db()

/// A gate still closed after LOGIN_GATE_TIMEOUT fails open.
/proc/login_gate_timeout(ckey, computer_id)
	var/client/C = GLOB.directory[ckey]
	if(!C || !C.login_pending || C.computer_id != computer_id)
		return
	log_access("Login gate: checks for [key_name(C)] did not answer in [LOGIN_GATE_TIMEOUT / 10]s; admitting")
	message_admins("Login checks for [key_name_admin(C)] did not answer in time; they were admitted unchecked.")
	C.login_admit()

/// Opens the gate: the client may join or observe.
/client/proc/login_admit()
	if(!login_pending)
		return
	login_pending = FALSE
	log_access("Login gate: admitted [key_name(src)]")
	if(CONFIG_GET(flag/paranoia_logging))
		var/alert = FALSE // start.
		if(isnum(player_age) && player_age == 0)
			log_and_message_admins("PARANOIA: [key_name(src)] has connected here for the first time.")
			alert = TRUE
		if(isnum(account_age) && account_age <= 2)
			log_and_message_admins("PARANOIA: [key_name(src)] has a very new BYOND account ([account_age] days).")
			alert = TRUE
		if(alert)
			for(var/client/X in GLOB.admins)
				if(!check_rights_for(X, R_HOLDER))
					continue
				if(X.prefs?.read_preference(/datum/preference/toggle/holder/play_adminhelp_ping))
					X << 'sound/voice/bcriminal.ogg' // back to beepsky
				window_flash(X)
		// end.
	if(isnewplayer(mob))
		to_chat(src, span_notice("Your connection has been verified."))

/// Lobby actions (join, observe, ready) call this: TRUE, and it says why, while the client is held.
/client/proc/login_hold_refuses()
	if(!login_pending)
		return FALSE
	to_chat(src, span_warning("Your connection is still being verified. Please wait a moment and try again."))
	return TRUE

/// The login checks, run as a prompt flow on the client: every read and lookup re-runs it when
/// it answers, and the writes go out at the end. Admits the client when it finishes, or
/// disconnects it (bans, the panic bunker, IP reputation).
/client/proc/log_client_to_db()
	if(!GLOB.prompt_flow)
		return prompt_flow(src, PROC_REF(log_client_to_db), args)
	if(IsGuestKey(src.key) || !SSdbcore.IsConnected())
		if(!IsGuestKey(src.key) && !CONFIG_GET(flag/ban_legacy_system))
			var/msg = "Ban database connection failure. Key [ckey] not checked"
			log_world(msg)
			message_admins(msg)
		login_admit()
		return
	if(!login_checks())
		return // disconnected
	login_admit()

/// The body of log_client_to_db()'s flow. FALSE if the client was disconnected.
/client/proc/login_checks()
	var/sql_ckey = src.ckey

	if(!CONFIG_GET(flag/ban_legacy_system) && !(ckey in GLOB.admin_datums))
		var/list/ban = login_ban_check()
		if(ban)
			log_suspicious_login("Failed Login: [key] [computer_id] [address] - Banned [ban["reason"]]")
			message_admins(span_blue("Failed Login: [key] id:[computer_id] ip:[address] - Banned [ban["reason"]]"))
			disconnect_with_message("You have been banned.[ban["desc"]]")
			return FALSE

	var/list/player_rows = flow_select("SELECT id, datediff(Now(),firstseen) as age FROM erro_player WHERE ckey = :ckey", list("ckey" = sql_ckey))
	if(isnull(player_rows))
		return TRUE
	var/sql_id = 0
	player_age = 0	// New players won't have an entry so knowing we have a connection we set this to zero to be updated if their is a record.
	if(length(player_rows))
		var/list/player_row = player_rows[1]
		sql_id = player_row[1]
		player_age = text2num(player_row[2])

	account_join_date = findJoinDate()
	if(account_join_date)
		var/list/datediff_rows = flow_select("SELECT DATEDIFF(Now(), :join_date)", list("join_date" = account_join_date))
		if(isnull(datediff_rows))
			return TRUE
		if(length(datediff_rows))
			var/list/datediff_row = datediff_rows[1]
			account_age = text2num(datediff_row[1])

	var/list/ip_rows = flow_select("SELECT ckey FROM erro_player WHERE ip = :ip", list("ip" = address))
	if(isnull(ip_rows))
		return TRUE
	related_accounts_ip = ""
	if(length(ip_rows))
		var/list/ip_row = ip_rows[1]
		related_accounts_ip += "[ip_row[1]], "

	var/list/cid_rows = flow_select("SELECT ckey FROM erro_player WHERE computerid = :computerid", list("computerid" = computer_id))
	if(isnull(cid_rows))
		return TRUE
	related_accounts_cid = ""
	if(length(cid_rows))
		var/list/cid_row = cid_rows[1]
		related_accounts_cid += "[cid_row[1]], "

	//Just the standard check to see if it's actually a number
	if(sql_id)
		if(istext(sql_id))
			sql_id = text2num(sql_id)
		if(!isnum(sql_id))
			return TRUE

	var/admin_rank = "Player"
	if(src.holder)
		admin_rank = src.holder.rank_names()

	var/sql_ip = src.address
	var/sql_computerid = src.computer_id
	var/sql_admin_rank = admin_rank

	// If you're about to disconnect the player, you have to use to_chat_immediate otherwise they won't get the message (SSchat will queue it)

	//Panic bunker code
	if (isnum(player_age) && player_age == 0) //first connection
		if (CONFIG_GET(flag/panic_bunker) && !holder && !GLOB.deadmins[key])
			log_admin_private("Failed Login: [key] - New account attempting to connect during panic bunker")
			message_admins(span_adminnotice("Failed Login: [key] - New account attempting to connect during panic bunker"))
			disconnect_with_message("Sorry but the server is currently not accepting connections from never before seen players.")
			return FALSE

	// IP Reputation Check
	if(CONFIG_GET(flag/ip_reputation))
		if(CONFIG_GET(flag/ipr_allow_existing) && player_age >= CONFIG_GET(number/ipr_minimum_age))
			log_admin("Skipping IP reputation check on [key] with [address] because of player age")
		else if(update_ip_reputation()) //It is set now
			if(ip_reputation >= CONFIG_GET(number/ipr_bad_score)) //It's bad

				//Log it
				if(CONFIG_GET(flag/paranoia_logging)) //We don't block, but we want paranoia log messages
					log_and_message_admins("[key] at [address] has bad IP reputation: [ip_reputation]. Will be kicked if enabled in config.", null)
				else //We just log it
					log_admin("[key] at [address] has bad IP reputation: [ip_reputation]. Will be kicked if enabled in config.")

				//Take action if required
				if(CONFIG_GET(flag/ipr_block_bad_ips) && CONFIG_GET(flag/ipr_allow_existing)) //We allow players of an age, but you don't meet it
					disconnect_with_message("Sorry, we only allow VPN/Proxy/Tor usage for players who have spent at least [CONFIG_GET(number/ipr_minimum_age)] days on the server. If you are unable to use the internet without your VPN/Proxy/Tor, please contact an admin out-of-game to let them know so we can accommodate this.")
					return FALSE
				else if(CONFIG_GET(flag/ipr_block_bad_ips)) //We don't allow players of any particular age
					disconnect_with_message("Sorry, we do not accept connections from users via VPN/Proxy/Tor connections. If you believe this is in error, contact an admin out-of-game.")
					return FALSE
		else
			log_admin("Couldn't perform IP check on [key] with [address]")

	var/list/hours_rows = flow_select("SELECT department, hours, total_hours FROM vr_player_hours WHERE ckey = :ckey", list("ckey" = sql_ckey))
	if(!isnull(hours_rows))
		for(var/list/hours_row as anything in hours_rows)
			department_hours[hours_row[1]] = text2num(hours_row[2])
			play_hours[hours_row[1]] = text2num(hours_row[3])
	else
		var/error_message = flow_sql_error()
		log_sql("Error loading play hours for [ckey]: [error_message]")
		tgui_alert_async(src, "The query to load your existing playtime failed. Screenshot this, give the screenshot to a developer, and reconnect, otherwise you may lose any recorded play hours (which may limit access to jobs). ERROR: [error_message]", "PROBLEMS!!")

	// The writes: nothing reads them back, so they go out without holding the gate.
	if(sql_id)
		//Player already identified previously, we need to just update the 'lastseen', 'ip' and 'computer_id' variables
		sql_write("UPDATE erro_player SET lastseen = Now(), ip = :ip, computerid = :computerid, lastadminrank = :admin_rank WHERE id = :id", list("ip" = sql_ip, "computerid" = sql_computerid, "admin_rank" = sql_admin_rank, "id" = sql_id))
	else
		//New player!! Need to insert all the stuff
		sql_write("INSERT INTO erro_player (id, ckey, firstseen, lastseen, ip, computerid, lastadminrank) VALUES (null, :ckey, Now(), Now(), :ip, :computerid, :admin_rank)", list("ckey" = sql_ckey, "ip" = sql_ip, "computerid" = sql_computerid, "admin_rank" = sql_admin_rank))

	//Logging player access
	var/serverip = "[world.internet_address]:[world.port]"
	sql_write("INSERT INTO `erro_connection_log`(`id`,`datetime`,`serverip`,`ckey`,`ip`,`computerid`) VALUES(null,Now(),:serverip,:ckey,:ip,:computerid)", list("serverip" = serverip, "ckey" = sql_ckey, "ip" = sql_ip, "computerid" = sql_computerid))
	return TRUE

/// The database ban check (moved here from world/IsBanned(), which can't wait on a query).
/// Runs inside the login flow; returns list("reason", "desc") for a ban, else null.
/client/proc/login_ban_check()
	var/failedcid = 1
	var/failedip = 1

	var/ipquery = ""
	var/cidquery = ""
	var/list/ban_params = list("ckeytext" = ckey)
	if(address)
		failedip = 0
		ipquery = " OR ip = :address "
		ban_params["address"] = address

	if(computer_id)
		failedcid = 0
		if(isnum(text2num(computer_id)))
			cidquery = " OR computerid = :computer_id "
			ban_params["computer_id"] = computer_id
		else
			log_world("Key [ckey] cid not checked. Non-Numeric: [computer_id]")
			failedcid = 1

	var/list/ban_rows = flow_select("SELECT ckey, ip, computerid, a_ckey, reason, expiration_time, duration, bantime, bantype FROM erro_ban WHERE (ckey = :ckeytext [ipquery] [cidquery]) AND (bantype = 'PERMABAN'  OR (bantype = 'TEMPBAN' AND expiration_time > Now())) AND isnull(unbanned)", ban_params)

	for(var/list/ban_row as anything in ban_rows)
		var/pckey = ban_row[1]
		var/ackey = ban_row[4]
		var/reason = ban_row[5]
		var/expiration = ban_row[6]
		var/duration = ban_row[7]
		var/bantime = ban_row[8]
		var/bantype = ban_row[9]

		var/expires = ""
		if(text2num(duration) > 0)
			expires = " The ban is for [duration] minutes and expires on [expiration] (server time)."

		var/desc = "\nReason: You, or another user of this computer or connection ([pckey]) is banned from playing here. The ban reason is:\n[reason]\nThis ban was applied by [ackey] on [bantime], [expires]"
		return list("reason" = "[bantype]", "desc" = "[desc]")
	if (failedcid)
		message_admins("[key] has logged in with a blank computer id in the ban check.")
	if (failedip)
		message_admins("[key] has logged in with a blank ip in the ban check.")
	return null

#undef LOGIN_GATE_TIMEOUT

#undef UPLOAD_LIMIT
#undef MIN_CLIENT_VERSION

//checks if a client is afk
//3000 frames = 5 minutes
/// om_io() callback for the Discord registration link.
/proc/discord_registration_done(list/result, error, ckey, their_id)
	var/client/C = GLOB.directory[ckey]
	if(error)
		if(C)
			to_chat(C, span_warning("There was an error registering your Discord ID in the database. Contact an administrator."))
		log_and_message_admins("[ckey] failed to register their Discord ID. Their Discord snowflake ID is: [their_id]. Is the database connected?", C)
		return
	if(C)
		to_chat(C, span_notice("Registration complete! Thank you for taking the time to register your Discord ID."))
	log_and_message_admins("[ckey] has registered their Discord ID. Their Discord snowflake ID is: [their_id]", C)
	admin_chat_message(message = "[ckey] has registered their Discord ID. Their Discord is: <@[their_id]>", color = "#4eff22")
	notes_add(ckey, "Discord ID: [their_id]")
	var/port = CONFIG_GET(number/register_server_port)
	if(port)
		// Designed to be used with `tools/registration`
		om_http_get("http://127.0.0.1:[port]?member=[url_encode(json_encode(their_id))]")

/// dx_winexists() callback: a client on a custom skin is told why assets may misbehave.
/client/proc/asset_browser_checked(control_type)
	if(!control_type)
		to_chat(src, span_warning("Unable to access asset cache browser, if you are using a custom skin file, please allow DS to download the updated version, if you are not, then make a bug report. This is not a critical issue but can cause issues with resource downloading, as it is impossible to know when extra resources arrived to you."))

/client/proc/is_afk(duration=3000)
	if(inactivity > duration)	return inactivity
	return 0

//Called when the client performs a drag-and-drop operation.
/client/MouseDrop(start_object,end_object,start_location,end_location,start_control,end_control,params)
	if(buildmode && start_control == SKIN_MAP && start_control == end_control)
		build_drag(src,buildmode,start_object,end_object,start_location,end_location,start_control,end_control,params)
	else
		. = ..()

/client/proc/last_activity_seconds()
	return inactivity / 10

//send resources to the client. It's here in its own proc so we can move it around easiliy if need be
/client/proc/send_resources()
	spawn (10) //removing this spawn causes all clients to not get verbs. // ALLOW(scheduler): login-ordering hack: the delay lets the client's verb delivery finish first, and without it no client gets its verbs (a login hook replaces it)

		//load info on what assets the client has
		src << browse('code/modules/asset_cache/validate_assets.html', "window=asset_cache_browser")

		//Precache the client with all other assets slowly, so as to not block other browse() calls
		if (CONFIG_GET(flag/asset_simple_preload))
			after(5 SECONDS, TYPE_PROC_REF(/datum/asset_transport, send_assets_slow), SSassets.transport, clock = CLOCK_WORLD, with = list(src, SSassets.transport.preload))

/mob/proc/MayRespawn()
	return FALSE

/client/proc/MayRespawn()
	if(mob)
		return mob.MayRespawn()

	// Something went wrong, client is usually kicked or transfered to a new mob at this point
	return FALSE

/client/verb/character_setup()
	set name = "Character Setup"
	set category = VERB_CAT_PREFERENCES_CHARACTER

	prefs.current_window = PREFERENCE_TAB_CHARACTER_PREFERENCES
	prefs.update_tgui_static_data(mob)
	prefs.tgui_interact(mob)

/client/verb/game_options()
	set name = "Game Options"
	set category = VERB_CAT_PREFERENCES_GAME

	prefs.current_window = PREFERENCE_TAB_GAME_PREFERENCES
	prefs.update_tgui_static_data(mob)
	prefs.tgui_interact(mob)

/// The BYOND account's join date, looked up inside the login flow (flow_http_get()).
/client/proc/findJoinDate()
	var/list/http = flow_http_get("http://byond.com/members/[ckey]?format=text")
	if(http["error"])
		log_world("Failed to connect to byond age check for [ckey]")
		return
	var/F = http["body"]
	if(F)
		var/regex/R = regex("joined = \"(\\d{4}-\\d{2}-\\d{2})\"")
		if(R.Find(F))
			. = R.group[1]
		else
			CRASH("Age check regex failed for [src.ckey]")

/client/vv_edit_var(var_name, var_value)
	if(var_name == NAMEOF(src, holder))
		return FALSE
	return ..()

//This is for getipintel.net.
//You're welcome to replace this proc with your own that does your own cool stuff.
//Just set the client's ip_reputation var and make sure it makes sense with your config settings (higher numbers are worse results)
/client/proc/disconnect_with_message(message = "You have been intentionally disconnected by the server.<br>This may be for security or administrative reasons.")
	// disconnect overlay via to_chat + window_flash (no browse).
	// Pre-disconnect popup windows can't reliably use TGUI: the qdel(src)
	// below tears down the client before any TGUI window has time to
	// render, and TGUI windows are owned by the client that's about to
	// die. Plain chat survives, and the window_flash grabs attention.
	window_flash(src)
	to_chat(src, span_userdanger("You have been disconnected from the server."))
	to_chat(src, span_warning(message))
	to_chat(src, span_warning("If you feel this is in error, you can contact an administrator out-of-game (for example, on Discord)."))
	spent(src)

/client/verb/toggle_fullscreen()
	set name = "Toggle Fullscreen"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS

	fullscreen = !fullscreen

	if (fullscreen)
		winset(usr, SKIN_MAINWINDOW, "on-size=")
		winset(usr, SKIN_MAINWINDOW, "titlebar=false")
		winset(usr, SKIN_MAINWINDOW, "can-resize=false")
		winset(usr, SKIN_MAINWINDOW, "menu=")
		winset(usr, SKIN_MAINWINDOW, "is-maximized=false")
		winset(usr, SKIN_MAINWINDOW, "is-maximized=true")
	else
		winset(usr, SKIN_MAINWINDOW, "menu=menu")
		winset(usr, SKIN_MAINWINDOW, "titlebar=true")
		winset(usr, SKIN_MAINWINDOW, "can-resize=true")
		winset(usr, SKIN_MAINWINDOW, "is-maximized=false")
		winset(usr, SKIN_MAINWINDOW, "on-size=attempt_auto_fit_viewport") // The attempt_auto_fit_viewport() proc is not implemented yet
	attempt_auto_fit_viewport()

/*we use TGPanel
/client/verb/toggle_verb_panel()
	set name = "Toggle Verbs"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS

	show_verb_panel = !show_verb_panel

	to_chat(src, "Your verbs are now [show_verb_panel ? "on" : "off. To turn them back on, type 'toggle-verbs' into the command bar."].")
*/

/*
/client/verb/toggle_status_bar()
	set name = "Toggle Status Bar"
	set category = VERB_CAT_OOC_CLIENT_SETTINGS

	show_status_bar = !show_status_bar

	if (show_status_bar)
		winset(usr, "input", "is-visible=true")
	else
		winset(usr, "input", "is-visible=false")
*/

/client/verb/show_active_playtime()
	set name = "Active Playtime"
	set category = VERB_CAT_OOC_GAME

	if(!play_hours.len)
		to_chat(src, span_warning("Persistent playtime disabled!"))
		return

	var/department_hours = ""
	for(var/play_hour in play_hours)
		if(!isnum(play_hour) && isnum(play_hours[play_hour]))
			department_hours += "<br>\t[capitalize(play_hour)]: [play_hours[play_hour]]"
	if(!department_hours)
		to_chat(src, span_warning("No recorded playtime found!"))
		return
	to_chat(src, span_info("Your department hours:" + department_hours))

/// compiles a full list of verbs and sends it to the browser
/client/proc/init_verbs()
	if(IsAdminAdvancedProcCall())
		return
	var/list/verblist = list()
	panel_tabs.Cut()
	for(var/thing in (verbs + mob?.verbs))
		var/procpath/verb_to_init = thing
		if(!verb_to_init)
			continue
		if(verb_to_init.hidden)
			continue
		if(!istext(verb_to_init.category))
			continue
		panel_tabs |= verb_to_init.category
		verblist[++verblist.len] = list(verb_to_init.category, verb_to_init.name, verb_to_init.desc)
	src.stat_panel.send_message("init_verbs", list(panel_tabs = panel_tabs, verblist = verblist))

/client/proc/check_panel_loaded()
	if(stat_panel && stat_panel.is_ready())
		return
	to_chat(src, span_danger("Statpanel failed to load, click <a href='byond://?src=[REF(src)];reload_statbrowser=1'>here</a> to reload the panel. If this does not work, reconnecting will reassign a new panel."))

/**
 * Handles incoming messages from the stat-panel TGUI.
 */
/client/proc/on_stat_panel_message(type, payload)
	switch(type)
		if("Update-Verbs")
			init_verbs()
		if("Remove-Tabs")
			panel_tabs -= payload["tab"]
		if("Send-Tabs")
			panel_tabs |= payload["tab"]
		if("Reset-Tabs")
			panel_tabs = list()
		if("Set-Tab")
			stat_tab = payload["tab"]
			SSstatpanels.immediate_send_stat_data(src)

// Mouse stuff
/client/Click(atom/object, atom/location, control, params)
	var/mcl = CONFIG_GET(number/minute_click_limit)
	if (!check_rights_for(src, R_HOLDER) && mcl)
		var/minute = round(world.time, 600)

		if (!clicklimiter)
			clicklimiter = new(LIMITER_SIZE)

		if (minute != clicklimiter[CURRENT_MINUTE])
			clicklimiter[CURRENT_MINUTE] = minute
			clicklimiter[MINUTE_COUNT] = 0

		clicklimiter[MINUTE_COUNT] += 1

		if (clicklimiter[MINUTE_COUNT] > mcl)
			var/msg = "Your previous click was ignored because you've done too many in a minute."
			if (minute != clicklimiter[ADMINSWARNED_AT]) //only one admin message per-minute. (if they spam the admins can just boot/ban them)
				clicklimiter[ADMINSWARNED_AT] = minute

				msg += " Administrators have been informed."
				log_and_message_admins("Has hit the per-minute click limit of [mcl] clicks in a given game minute", src)
			to_chat(src, span_danger("[msg]"))
			return

	var/scl = CONFIG_GET(number/second_click_limit)
	if (!check_rights_for(src, R_HOLDER) && scl)
		var/second = round(world.time, 10)
		if (!clicklimiter)
			clicklimiter = new(LIMITER_SIZE)

		if (second != clicklimiter[CURRENT_SECOND])
			clicklimiter[CURRENT_SECOND] = second
			clicklimiter[SECOND_COUNT] = 0

		clicklimiter[SECOND_COUNT] += 1

		if (clicklimiter[SECOND_COUNT] > scl)
			to_chat(src, span_danger("Your previous click was ignored because you've done too many in a second"))
			return
	// Clients cannot be hooked: the click event is emitted on the client's mob.
	if(mob)
		PUBLISH_LEGACY(mob, /datum/notice/client_click, object, location, control, params, usr)
	. = ..()

/// This grabs the DPI of the user per their skin (a winget round trip, through DX-exec)
/client/proc/acquire_dpi()
	dx_winget(src, src, null, "dpi", PROC_REF(dpi_acquired))

/// dx_winget() callback for acquire_dpi().
/client/proc/dpi_acquired(dpi)
	window_scaling = text2num(dpi)

/client/proc/open_filter_editor(atom/in_atom)
	if(check_rights_for(src, R_HOLDER))
		rel_set(holder, nameof(holder.filteriffic), new /datum/filter_editor(in_atom))
		holder.filteriffic.tgui_interact(mob)

///opens the particle editor UI for the in_atom object for this client
/client/proc/open_particle_editor(atom/movable/in_atom)
	if(check_rights_for(src, R_HOLDER))
		rel_set(holder, nameof(holder.particle_test), new /datum/particle_editor(in_atom))
		holder.particle_test.tgui_interact(mob)

/client/proc/set_eye(new_eye)
	if(new_eye == eye)
		return
	eye = new_eye

/mob/proc/is_remote_viewing()
	if(!client || !client.mob || !client.eye)
		return FALSE
	if(isturf(client.mob.loc) && get_turf(client.eye) == get_turf(client.mob))
		return FALSE
	if(ismecha(client.mob.loc) && client.eye == client.mob.loc)
		return FALSE
	return (client.eye != client.mob)

#undef ADMINSWARNED_AT
#undef CURRENT_MINUTE
#undef CURRENT_SECOND
#undef LIMITER_SIZE
#undef MINUTE_COUNT
#undef SECOND_COUNT

//Uses a couple different services
/client/proc/update_ip_reputation()
	var/scores[] = list("GII" = ipr_getipintel(), "IPQS" = ipr_ipqualityscore())

	var/log_output = "IP Reputation [key] from [address]"
	var/worst = 0

	for(var/service in scores)
		var/score = scores[service]
		if(score > worst)
			worst = score
		log_output += " - [service] ([num2text(score)])"

	log_admin(log_output)
	ip_reputation = worst
	return TRUE

//Service returns a single float in html body
/client/proc/ipr_getipintel()
	if(!CONFIG_GET(string/ipr_email))
		return -1

	var/request = "https://check.getipintel.net/check.php?ip=[address]&contact=[CONFIG_GET(string/ipr_email)]"
	var/list/http = flow_http_get(request) // inside the login flow

	if(http["error"]) //If we couldn't check, the service might be down, fail-safe.
		log_admin("Couldn't connect to getipintel.net to check [address] for [key]")
		return -1

	//429 is rate limit exceeded
	if(text2num("[http["status"]]") == 429)
		log_and_message_admins("getipintel.net reports HTTP status 429. IP reputation checking is now disabled. If you see this, let a developer know.")
		CONFIG_SET(flag/ip_reputation, FALSE)
		return -1

	var/content = http["body"]
	var/score = text2num(content)
	if(isnull(score))
		return -1

	//Error handling
	if(score < 0)
		var/fatal = TRUE
		var/ipr_error = "getipintel.net IP reputation check error while checking [address] for [key]: "
		switch(score)
			if(-1)
				ipr_error += "No input provided"
			if(-2)
				fatal = FALSE
				ipr_error += "Invalid IP provided"
			if(-3)
				fatal = FALSE
				ipr_error += "Unroutable/private IP (spoofing?)"
			if(-4)
				fatal = FALSE
				ipr_error += "Unable to reach database"
			if(-5)
				ipr_error += "Our IP is banned or otherwise forbidden"
			if(-6)
				ipr_error += "Missing contact info"

		log_and_message_admins(ipr_error)
		if(fatal)
			CONFIG_SET(flag/ip_reputation, FALSE)
			log_and_message_admins("With this error, IP reputation checking is disabled for this shift. Let a developer know.")
		return -1

	//Went fine
	else
		return score

//Service returns JSON in html body
/client/proc/ipr_ipqualityscore()
	if(!CONFIG_GET(string/ipqualityscore_apikey))
		return -1

	var/request = "https://www.ipqualityscore.com/api/json/ip/[CONFIG_GET(string/ipqualityscore_apikey)]/[address]?strictness=1&fast=true&byond_key=[key]"
	var/list/http = flow_http_get(request) // inside the login flow

	if(http["error"]) //If we couldn't check, the service might be down, fail-safe.
		log_admin("Couldn't connect to ipqualityscore.com to check [address] for [key]")
		return -1

	var/content = http["body"]
	var/response = json_decode(content)
	if(isnull(response))
		return -1

	//Error handling
	if(!response["success"])
		log_admin("IPQualityscore.com returned an error while processing [key] from [address]: " + response["message"])
		return -1

	var/score = 0
	if(response["proxy"])
		score = 100
	else
		score = response["fraud_score"]

	return score/100 //To normalize with the 0.0 to 1.0 scores.
