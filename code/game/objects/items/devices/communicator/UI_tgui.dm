// Etc UI-only vars
/obj/item/communicator
	// Stuff for moving cameras
	var/last_camera_turf_handle
	// Stuff needed to render the map
	var/map_name
	var/atom/movable/screen/map_view/cam_screen
	var/list/cam_plane_masters
	var/atom/movable/screen/background/cam_background
	var/atom/movable/screen/skybox/local_skybox

DECLARE_REF(/obj/item/communicator, "cam_screen", OWNED, null)
DECLARE_REF(/obj/item/communicator, "cam_background", OWNED, null)
DECLARE_REF(/obj/item/communicator, "local_skybox", OWNED, null)
DECLARE_REF(/obj/item/communicator, "cam_plane_masters", OWNED_LIST, null)

// Proc: setup_tgui_camera()
// Parameters: None
// Description: This sets up all of the variables above to handle in-UI map windows.
/obj/item/communicator/proc/setup_tgui_camera()
	map_name = "communicator_[REF(src)]_map"

	// Initialize map objects
	cam_screen = new
	cam_screen.name = "screen"
	cam_screen.assigned_map = map_name
	cam_screen.del_on_map_removal = FALSE
	cam_screen.screen_loc = "[map_name]:1,1"

	cam_plane_masters = get_tgui_plane_masters()

	for(var/atom/movable/screen/instance as anything in cam_plane_masters)
		instance.assigned_map = map_name
		instance.del_on_map_removal = FALSE
		instance.screen_loc = "[map_name]:CENTER"

	local_skybox = new()
	local_skybox.assigned_map = map_name
	local_skybox.del_on_map_removal = FALSE
	local_skybox.screen_loc = "[map_name]:CENTER,CENTER"
	cam_plane_masters += local_skybox

	cam_background = new
	cam_background.assigned_map = map_name
	cam_background.del_on_map_removal = FALSE

// Proc: update_active_camera_screen()
// Parameters: None
// Description: This refreshes the camera location
/obj/item/communicator/proc/update_active_camera_screen()
	EVENT_HANDLER
	if(!video_source?.can_use())
		show_static()
		return

	var/newturf = get_turf(video_source)
	if(!is_on_same_plane_or_station(get_z(newturf), get_z(src)))
		show_static()
		return

	var/obj/item/communicator/communicator = video_source.loc
	if(istype(communicator))
		if(communicator.selfie_mode)
			var/mob/target = get(communicator, /mob)
			if(istype(target))
				cam_screen.vis_contents = list(target)
			else
				cam_screen.vis_contents = list(communicator)
			cam_background.fill_rect(1, 1, 1, 1)
			cam_background.icon_state = "clear"
			local_skybox.cut_overlays()
			return

	// If we're not forcing an update for some reason and the cameras are in the same location,
	// we don't need to update anything.
	if(last_camera_turf() == newturf)
		return

	// We get a new turf in case they've moved in the last half decisecond (it's BYOND, it might happen)
	last_camera_turf_handle = om_handle(get_turf(video_source))

	if(!is_on_same_plane_or_station(get_z(last_camera_turf()), get_z(src)))
		show_static()
		return

	var/list/visible_turfs = list()
	var/list/visible_things = view(video_range, last_camera_turf())
	for(var/turf/visible_turf in visible_things)
		visible_turfs += visible_turf

	cam_screen.vis_contents = visible_turfs
	cam_background.icon_state = "clear"
	cam_background.fill_rect(1, 1, (video_range * 2), (video_range * 2))

	local_skybox.cut_overlays()
	local_skybox.add_overlay(skybox_service().get_skybox(get_z(last_camera_turf())))
	local_skybox.scale_to_view(video_range * 2)
	local_skybox.set_position("CENTER", "CENTER", (world.maxx>>1) - last_camera_turf().x, (world.maxy>>1) - last_camera_turf().y)

/obj/item/communicator/proc/show_static()
	cam_screen.vis_contents.Cut()
	cam_background.icon_state = "scanline2"
	cam_background.fill_rect(1, 1, (video_range * 2), (video_range * 2))
	local_skybox.cut_overlays()

// Proc: tgui_state()
// Parameters: User
// Description: This tells TGUI to only allow us to be interacted with while in a mob inventory.
DECLARE_UI_STATE(/obj/item/communicator, GLOB.tgui_inventory_state)

// Proc: tgui_interact()
// Parameters: User, UI, Parent UI
// Description: This proc handles opening the UI. It's basically just a standard stub.
DECLARE_UI(/obj/item/communicator, "Communicator")

/obj/item/communicator/ui_prepare(mob/user, datum/tgui/ui)
	// Update the camera every SStgui tick in case it moves
	update_active_camera_screen()
	return TRUE

/obj/item/communicator/ui_opening(mob/user, datum/tgui/ui)
	// Register map objects
	user.client.register_map_obj(cam_screen)
	for(var/plane in cam_plane_masters)
		user.client.register_map_obj(plane)
	user.client.register_map_obj(cam_background)

// Proc: tgui_data()
// Parameters: User, UI, State
// Description: Uses a bunch of for loops to turn lists into lists of lists, so they can be displayed in nanoUI, then displays various buttons to the user.
UI_DATA_REPLACE(/obj/item/communicator, "visible=network_visibility:num", "targetAddress=target_address:text", "targetAddressName=target_address_name:text", "currentTab=selected_tab", "ring=ringer:num", "note:text", "flashlight=fon:num", "selfie_mode:num", "merge:ui_data_obj_item_communicator{user:text,owner:text,occupation:text,connectionStatus:unknown,address:text,knownDevices:list,invitesSent:list,requestsReceived:list,voice_mobs:list,communicating:list,video_comm:text,imContacts:list,imList:list,time:text,homeScreen:list,weather:list,aircontents:unknown,feeds:unknown,latest_news:unknown,target_feed:unknown}")

/// The computed part of /obj/item/communicator's window data (declared on its UI_DATA row).
/obj/item/communicator/proc/ui_data_obj_item_communicator(mob/user, datum/tgui/ui, datum/tgui_state/state)
	// this is the data which will be sent to the ui
	var/list/data = list()						//General nanoUI information
	var/list/communicators = list()			    //List of communicators
	var/list/invites = list()					//Communicators and ghosts we've invited to our communicator.
	var/list/requests = list()					//Communicators and ghosts wanting to go in our communicator.
	var/list/voices = list()					//Current /mob/living/voice s inside the device.
	var/list/connected_communicators = list()	//Current communicators connected to the device.

	var/list/im_contacts_ui = list()			//List of communicators that have been messaged.
	var/list/im_list_ui = list()				//List of messages.

	var/list/weather = list()
	var/list/modules_ui = list()				//Home screen info.

	//First we add other 'local' communicators.
	for(var/obj/item/communicator/comm in known_devices)
		if(comm.network_visibility && comm.exonet)
			communicators.Add(list(list(
				"name" = sanitize(comm.name),
				"address" = comm.exonet.address
			)))

	//Now for ghosts who we pretend have communicators.
	for(var/mob/observer/dead/O in known_devices)
		if(O.client && O.client.prefs.read_preference(/datum/preference/toggle/human/communicator_visibility) && O.exonet) // migrated pref
			communicators.Add(list(list(
				"name" = sanitize("[O.client.prefs.read_preference(/datum/preference/name/real_name)]'s communicator"),
				"address" = O.exonet.address,
				"ref" = "\ref[O]"
			)))

	//Lists all the other communicators that we invited.
	for(var/obj/item/communicator/comm in voice_invites)
		if(comm.exonet)
			invites.Add(list(list(
				"name" = sanitize(comm.name),
				"address" = comm.exonet.address,
				"ref" = "\ref[comm]"
			)))

	//Ghosts we invited.
	for(var/mob/observer/dead/O in voice_invites)
		if(O.exonet && O.client)
			invites.Add(list(list(
				"name" = sanitize("[O.client.prefs.read_preference(/datum/preference/name/real_name)]'s communicator"),
				"address" = O.exonet.address,
				"ref" = "\ref[O]"
			)))

	//Communicators that want to talk to us.
	for(var/obj/item/communicator/comm in voice_requests)
		if(comm.exonet)
			requests.Add(list(list(
				"name" = sanitize(comm.name),
				"address" = comm.exonet.address,
				"ref" = "\ref[comm]"
			)))

	//Ghosts that want to talk to us.
	for(var/mob/observer/dead/O in voice_requests)
		if(O.exonet && O.client)
			requests.Add(list(list(
				"name" = sanitize("[O.client.prefs.read_preference(/datum/preference/name/real_name)]'s communicator"),
				"address" = O.exonet.address,
				"ref" = "\ref[O]"
			)))

	//Now for all the voice mobs inside the communicator.
	FOR_REAL_CONTENTS(var/mob/living/voice/voice, src)
		voices.Add(list(list(
			"name" = sanitize("[voice.name]'s communicator"),
			"true_name" = sanitize(voice.name),
		)))

	//Finally, all the communicators linked to this one.
	for(var/obj/item/communicator/comm in communicating)
		connected_communicators.Add(list(list(
			"name" = sanitize(comm.name),
			"true_name" = sanitize(comm.name),
			"ref" = "\ref[comm]",
		)))

	//Devices that have been messaged or recieved messages from.
	for(var/obj/item/communicator/comm in im_contacts)
		if(comm.exonet)
			im_contacts_ui.Add(list(list(
				"name" = sanitize(comm.name),
				"address" = comm.exonet.address,
				"ref" = "\ref[comm]"
			)))

	for(var/mob/observer/dead/ghost in im_contacts)
		if(ghost.exonet)
			im_contacts_ui.Add(list(list(
				"name" = sanitize(ghost.name),
				"address" = ghost.exonet.address,
				"ref" = "\ref[ghost]"
			)))

	for(var/obj/item/integrated_circuit/input/EPv2/CIRC in im_contacts)
		if(CIRC.exonet && CIRC.assembly())
			im_contacts_ui.Add(list(list(
				"name" = sanitize(CIRC.assembly().name),
				"address" = CIRC.exonet.address,
				"ref" = "\ref[CIRC]"
			)))

	//Actual messages.
	for(var/I in im_list)
		im_list_ui.Add(list(list(
			"address" = I["address"],
			"to_address" = I["to_address"],
			"im" = I["im"]
		)))

	//Weather reports.
	for(var/datum/planet/planet in GLOB.planet_service.planets)
		if(planet.weather_holder && planet.weather_holder.current_weather)
			var/list/W = list(
				"Planet" = planet.name,
				"Time" = planet.current_time.show_time("hh:mm"),
				"Weather" = planet.weather_holder.current_weather.name,
				"Temperature" = planet.weather_holder.temperature - T0C,
				"High" = planet.weather_holder.current_weather.temp_high - T0C,
				"Low" = planet.weather_holder.current_weather.temp_low - T0C,
				"WindDir" = planet.weather_holder.wind_dir ? dir2text(planet.weather_holder.wind_dir) : "None",
				"WindSpeed" = planet.weather_holder.wind_speed ? "[planet.weather_holder.wind_speed > 2 ? "Severe" : "Normal"]" : "None",
				"Forecast" = english_list(planet.weather_holder.forecast, and_text = "&#8594;", comma_text = "&#8594;", final_comma_text = "&#8594;") // Unicode RIGHTWARDS ARROW.
				)
			weather.Add(list(W))

	//Modules for homescreen.
	for(var/list/R in modules)
		modules_ui.Add(list(R))

	data["user"] = "\ref[user]"	// For receiving input() via topic, because input(usr,...) wasn't working on cartridges
	data["owner"] = owner ? owner : "Unset"
	data["occupation"] = occupation ? occupation : "Swipe ID to set."
	data["connectionStatus"] = get_connection_to_tcomms()
	data["address"] = exonet.address ? exonet.address : "Unallocated"
	data["knownDevices"] = communicators
	data["invitesSent"] = invites
	data["requestsReceived"] = requests
	data["voice_mobs"] = voices
	data["communicating"] = connected_communicators
	data["video_comm"] = video_source ? "\ref[video_source.loc]" : null
	data["imContacts"] = im_contacts_ui
	data["imList"] = im_list_ui
	data["time"] = stationtime2text()
	data["homeScreen"] = modules_ui
	data["weather"] = weather
	data["aircontents"] = src.analyze_air()
	data["feeds"] = compile_news()
	data["latest_news"] = get_recent_news()
	if(newsfeed_channel)
		data["target_feed"] = data["feeds"][newsfeed_channel]
	else
		data["target_feed"] = null

	return data

// Proc: tgui_static_data()
// Parameters: User, UI, State
// Description: Just like tgui_data, except it only gets called once when the user opens the UI, not every tick.
/obj/item/communicator/tgui_static_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()
	// Update manifest'
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	data["mapRef"] = map_name
	return data

// Proc: tgui-act()
// Parameters: 4 (standard tgui_act arguments)
// Description: Responds to UI button presses.
/// Communicator text entry: re-checked on the answer, the communicator is still usable.
/datum/om/prompt/text/communicator
	requires = PROMPT_USABLE

/datum/om/prompt/text/communicator/name
	title = "Communicator"
	message = "Please enter your name."
	encode = FALSE

/datum/om/prompt/text/communicator/ringtone
	title = "Ringer"
	message = "Set Ringer Tone"

/datum/om/prompt/text/communicator/text_message
	title = "Text Message"
	message = "Enter your message."
	encode = FALSE
	var/address

/// A cancel clears the note.
/datum/om/prompt/text/communicator/note
	message = "Please enter message"
	multiline = TRUE
	cancel_answer = ""

/obj/item/communicator/proc/name_entered(datum/om/prompt/text/communicator/name/ask)
	var/new_name = sanitizeSafe(ask.text)
	if(new_name)
		register_device(new_name)

/obj/item/communicator/proc/ringtone_entered(datum/om/prompt/text/communicator/ringtone/ask)
	if(ask.text)
		ttone = ask.text

/obj/item/communicator/proc/note_entered(datum/om/prompt/text/communicator/note/ask)
	var/n = sanitizeSafe(ask.text, extra = 0)
	if(n)
		note = html_decode(n)
		notehtml = note
		note = replacetext(note, "\n", "<br>")
	else
		note = ""
		notehtml = note

/obj/item/communicator/proc/text_message_entered(datum/om/prompt/text/communicator/text_message/ask)
	var/mob/user = ask.answerer
	var/their_address = ask.address
	var/text = sanitizeSafe(ask.text)
	if(!text || !get_connection_to_tcomms())
		return
	exonet.send_message(their_address, "text", text)
	LAZYADD(im_list, list(list("address" = exonet.address, "to_address" = their_address, "im" = text)))
	user.log_talk("(COMM: [src]) sent \"[text]\" to [exonet.get_atom_from_address(their_address)]", LOG_PDA)
	var/obj/item/communicator/comm = exonet.get_atom_from_address(their_address)
	to_chat(user, span_notice("[icon2html(src, user.client)] Sent message to [istype(comm, /obj/item/communicator) ? comm.owner : comm.name], <b>\"[text]\"</b> (<a href='byond://?src=\ref[src];action=Reply;target=\ref[exonet.get_atom_from_address(comm.exonet.address)]'>Reply</a>)"))
	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.stat == DEAD && M.client?.prefs?.read_preference(/datum/preference/toggle/ghost_ears))
			if(isnewplayer(M) || M.forbid_seeing_deadchat)
				continue
			if(exonet.get_atom_from_address(their_address) == M)
				continue
			M.show_message("Comm IM - [src] -> [exonet.get_atom_from_address(their_address)]: [text]")

/obj/item/communicator/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/item/communicator, "rename", ui_act_rename)
UI_ACT_PROC(/obj/item/communicator, ui_act_rename)
	. = TRUE
	om_ask(ui.user, /datum/om/prompt/text/communicator/name, PROC_REF(name_entered), default = ui.user.name)

UI_ACT(/obj/item/communicator, "toggle_visibility", ui_act_toggle_visibility)
UI_ACT_PROC(/obj/item/communicator, ui_act_toggle_visibility)
	. = TRUE
	switch(network_visibility)
		if(1) //Visible, becoming invisbile
			network_visibility = 0
			if(camera)
				camera.remove_network(NETWORK_COMMUNICATORS)
		if(0) //Invisible, becoming visible
			network_visibility = 1
			if(camera)
				camera.add_network(NETWORK_COMMUNICATORS)

UI_ACT(/obj/item/communicator, "toggle_ringer", ui_act_toggle_ringer)
UI_ACT_PROC(/obj/item/communicator, ui_act_toggle_ringer)
	. = TRUE
	ringer = !ringer

UI_ACT(/obj/item/communicator, "set_ringer_tone", ui_act_set_ringer_tone)
UI_ACT_PROC(/obj/item/communicator, ui_act_set_ringer_tone)
	. = TRUE
	om_ask(ui.user, /datum/om/prompt/text/communicator/ringtone, PROC_REF(ringtone_entered))

UI_ACT(/obj/item/communicator, "selfie_mode", ui_act_selfie_mode)
UI_ACT_PROC(/obj/item/communicator, ui_act_selfie_mode)
	. = TRUE
	selfie_mode = !selfie_mode

UI_ACT(/obj/item/communicator, "add_hex", ui_act_add_hex, UI_ARG_TEXT("add_hex"))
UI_ACT_PROC(/obj/item/communicator, ui_act_add_hex)
	. = TRUE
	var/hex = params["add_hex"]
	add_to_EPv2(hex)

UI_ACT(/obj/item/communicator, "write_target_address", ui_act_write_target_address, UI_ARG_TEXT("val"))
UI_ACT_PROC(/obj/item/communicator, ui_act_write_target_address)
	. = TRUE
	target_address = sanitizeSafe(params["val"])

UI_ACT(/obj/item/communicator, "clear_target_address", ui_act_clear_target_address)
UI_ACT_PROC(/obj/item/communicator, ui_act_clear_target_address)
	. = TRUE
	target_address = ""

UI_ACT(/obj/item/communicator, "dial", ui_act_dial, UI_ARG_TEXT("dial"))
UI_ACT_PROC(/obj/item/communicator, ui_act_dial)
	. = TRUE
	if(!get_connection_to_tcomms())
		to_chat(ui.user, span_danger("Error: Cannot connect to Exonet node."))
		return FALSE
	var/their_address = params["dial"]
	exonet.send_message(their_address, "voice")

UI_ACT(/obj/item/communicator, "decline", ui_act_decline, UI_ARG_REF("decline", null, /atom))
UI_ACT_PROC(/obj/item/communicator, ui_act_decline)
	. = TRUE
	var/atom/decline = params["decline"]
	if(decline)
		del_request(decline)

UI_ACT(/obj/item/communicator, "message", ui_act_message, UI_ARG_TEXT("message"))
UI_ACT_PROC(/obj/item/communicator, ui_act_message)
	. = TRUE
	if(!get_connection_to_tcomms())
		to_chat(ui.user, span_danger("Error: Cannot connect to Exonet node."))
		return FALSE
	om_ask(ui.user, /datum/om/prompt/text/communicator/text_message, PROC_REF(text_message_entered), address = params["message"])

UI_ACT(/obj/item/communicator, "disconnect", ui_act_disconnect, UI_ARG_TEXT("disconnect"))
UI_ACT_PROC(/obj/item/communicator, ui_act_disconnect)
	. = TRUE
	var/name_to_disconnect = params["disconnect"]
	for(var/mob/living/voice/V in contents)
		if(name_to_disconnect == sanitize(V.name))
			close_connection(ui.user, V, "[ui.user] hung up")
	for(var/obj/item/communicator/comm in communicating)
		if(name_to_disconnect == sanitize(comm.name))
			close_connection(ui.user, comm, "[ui.user] hung up")

UI_ACT(/obj/item/communicator, "startvideo", ui_act_startvideo, UI_ARG_REF("startvideo", null, /obj/item/communicator))
UI_ACT_PROC(/obj/item/communicator, ui_act_startvideo)
	. = TRUE
	var/obj/item/communicator/comm = params["startvideo"]
	if(comm)
		connect_video(ui.user, comm)

UI_ACT(/obj/item/communicator, "endvideo", ui_act_endvideo)
UI_ACT_PROC(/obj/item/communicator, ui_act_endvideo)
	. = TRUE
	if(video_source)
		end_video()

UI_ACT(/obj/item/communicator, "copy", ui_act_copy, UI_ARG_TEXT("copy"))
UI_ACT_PROC(/obj/item/communicator, ui_act_copy)
	. = TRUE
	target_address = params["copy"]

UI_ACT(/obj/item/communicator, "copy_name", ui_act_copy_name, UI_ARG_TEXT("copy_name"))
UI_ACT_PROC(/obj/item/communicator, ui_act_copy_name)
	. = TRUE
	target_address_name = params["copy_name"]

UI_ACT(/obj/item/communicator, "hang_up", ui_act_hang_up)
UI_ACT_PROC(/obj/item/communicator, ui_act_hang_up)
	. = TRUE
	for(var/mob/living/voice/V in contents)
		close_connection(ui.user, V, "[ui.user] hung up")
	for(var/obj/item/communicator/comm in communicating)
		close_connection(ui.user, comm, "[ui.user] hung up")

UI_ACT(/obj/item/communicator, "switch_tab", ui_act_switch_tab, UI_ARG_NUM("switch_tab"))
UI_ACT_PROC(/obj/item/communicator, ui_act_switch_tab)
	. = TRUE
	selected_tab = params["switch_tab"]

UI_ACT(/obj/item/communicator, "edit", ui_act_edit)
UI_ACT_PROC(/obj/item/communicator, ui_act_edit)
	. = TRUE
	om_ask(ui.user, /datum/om/prompt/text/communicator/note, PROC_REF(note_entered), title = name, default = notehtml)

UI_ACT(/obj/item/communicator, "Light", ui_act_light)
UI_ACT_PROC(/obj/item/communicator, ui_act_light)
	. = TRUE
	fon = !fon
	set_light(fon * flum)

UI_ACT(/obj/item/communicator, "newsfeed", ui_act_newsfeed, UI_ARG_NUM("newsfeed"))
UI_ACT_PROC(/obj/item/communicator, ui_act_newsfeed)
	. = TRUE
	newsfeed_channel = params["newsfeed"]

/// LC-refs: last camera turf -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/communicator/proc/last_camera_turf() as /turf
	return om_resolve(last_camera_turf_handle)
