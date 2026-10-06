// Etc UI-only vars
/obj/item/communicator
	// Stuff for moving cameras
	var/turf/last_camera_turf
	// Stuff needed to render the map
	var/map_name
	var/atom/movable/screen/map_view/cam_screen
	var/list/cam_plane_masters
	var/atom/movable/screen/background/cam_background
	var/atom/movable/screen/skybox/local_skybox

CAPABILITIES(/obj/item/communicator)
	after_init(5 SECONDS, then(PROC_REF(register_to_holder)))
	// alt-click ejects the loaded ID (a silicon's alt-click goes on to its own)
	op("remove_id", hand(), ungated(), gesture(GESTURE_ALT), label("Remove ID"), when(cond_not(req(/mob/living/silicon, of = ON_ACTOR))), then(PROC_REF(interaction_alt)))
	// an ID updates the occupation, or goes into the slot
	op("scan_id", item(/obj/item/card/id), label("Scan ID"), then(PROC_REF(interaction_item)))
	// the old attack_self: the communicator's window
	op("open", in_hand(), label("Open"), then(PROC_REF(interaction_self)))
	// a ghost's view refreshes the device list, then the ghost's own click goes on
	op("view", observer(), label("View"), then(PROC_REF(communicator_observer_use)))
	owns_one(nameof(id), on_destroy = ON_DESTROY_SPILL)
	owns_one(nameof(cam_background), /atom/movable/screen/background)
	owns_one(nameof(cam_screen), /atom/movable/screen/map_view)
	owns_one(nameof(exonet), /datum/exonet_protocol)
	owns_one(nameof(local_skybox), /atom/movable/screen/skybox)
	owns_many(nameof(cam_plane_masters))
	owns_many(nameof(voice_mobs))
	owns_one(nameof(camera), starts = /obj/machinery/camera/communicator)
	interface("Communicator", state = nameof(GLOB.tgui_inventory_state))
	without("ui_open")
	op("rename", ui_act("rename"), asks(/datum/prompt/text/communicator/name, fields = list("default" = computed(PROC_REF(actor_name))), step = "name"), then(PROC_REF(ui_act_rename)))
	op("set_ringer_tone", ui_act("set_ringer_tone"), asks(/datum/prompt/text/communicator/ringtone, step = "tone"), then(PROC_REF(ui_act_set_ringer_tone)))
	op("add_hex", ui_act("add_hex", arg("add_hex", schema_text(4096))), then(PROC_REF(ui_act_add_hex)))
	op("write_target_address", ui_act("write_target_address", arg("val", schema_text(4096))), then(PROC_REF(ui_act_write_target_address)))
	op("dial", ui_act("dial", arg("dial", schema_text(4096))), then(PROC_REF(ui_act_dial)))
	op("decline", ui_act("decline", arg("decline", schema_ref(/atom))), then(PROC_REF(ui_act_decline)))
	op("message", ui_act("message", arg("message", schema_text(4096))), asks(/datum/prompt/text/communicator/text_message, step = "text"), then(PROC_REF(ui_act_message)))
	op("disconnect", ui_act("disconnect", arg("disconnect", schema_text(4096))), then(PROC_REF(ui_act_disconnect)))
	op("startvideo", ui_act("startvideo", arg("startvideo", schema_ref(/obj/item/communicator))), then(PROC_REF(ui_act_startvideo)))
	op("copy", ui_act("copy", arg("copy", schema_text(4096))), then(PROC_REF(ui_act_copy)))
	op("copy_name", ui_act("copy_name", arg("copy_name", schema_text(4096))), then(PROC_REF(ui_act_copy_name)))
	op("switch_tab", ui_act("switch_tab", arg("switch_tab", num())), then(PROC_REF(ui_act_switch_tab)))
	op("edit", ui_act("edit"), asks(/datum/prompt/text/communicator/note, fields = list("title" = computed(PROC_REF(device_name)), "default" = computed(PROC_REF(note_default))), step = "note"), then(PROC_REF(ui_act_edit)))
	op("Light", ui_act("Light"), then(PROC_REF(ui_act_light)))
	op("newsfeed", ui_act("newsfeed", arg("newsfeed", num())), then(PROC_REF(ui_act_newsfeed)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(communicator_emp)))


// Proc: setup_tgui_camera()
// Parameters: None
// Description: This sets up all of the variables above to handle in-UI map windows.
/obj/item/communicator/proc/setup_tgui_camera()
	map_name = "communicator_[REF(src)]_map"

	// Initialize map objects
	rel_set(src, nameof(cam_screen), new /atom/movable/screen/map_view)
	cam_screen.name = "screen"
	cam_screen.assigned_map = map_name
	cam_screen.del_on_map_removal = FALSE
	cam_screen.screen_loc = "[map_name]:1,1"

	for(var/atom/movable/screen/plane_master as anything in get_tgui_plane_masters())
		rel_add(src, nameof(cam_plane_masters), plane_master)

	for(var/atom/movable/screen/instance as anything in cam_plane_masters)
		instance.assigned_map = map_name
		instance.del_on_map_removal = FALSE
		instance.screen_loc = "[map_name]:CENTER"

	rel_set(src, nameof(local_skybox), new /atom/movable/screen/skybox())
	local_skybox.assigned_map = map_name
	local_skybox.del_on_map_removal = FALSE
	local_skybox.screen_loc = "[map_name]:CENTER,CENTER"

	rel_set(src, nameof(cam_background), new /atom/movable/screen/background)
	cam_background.assigned_map = map_name
	cam_background.del_on_map_removal = FALSE

// Proc: update_active_camera_screen()
// Parameters: None
// Description: This refreshes the camera location
/obj/item/communicator/proc/update_active_camera_screen(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
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
	rel_set(src, nameof(last_camera_turf), get_turf(video_source))

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
	local_skybox.add_overlay(SSskybox.ready().get_skybox(get_z(last_camera_turf())))
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

// Proc: tgui_interact()
// Parameters: User, UI, Parent UI
// Description: This proc handles opening the UI. It's basically just a standard stub.

/obj/item/communicator/ui_prepare(mob/user, datum/tgui/ui)
	// Update the camera every SStgui tick in case it moves
	update_active_camera_screen()
	return TRUE

/obj/item/communicator/ui_opening(mob/user, datum/tgui/ui)
	// Register map objects
	user.client.register_map_obj(cam_screen)
	for(var/plane in cam_plane_masters)
		user.client.register_map_obj(plane)
	user.client.register_map_obj(local_skybox) // owned via local_skybox, not the plane list
	user.client.register_map_obj(cam_background)

// Proc: tgui_data()
// Parameters: User, UI, State
// Description: Uses a bunch of for loops to turn lists into lists of lists, so they can be displayed in nanoUI, then displays various buttons to the user.
/obj/item/communicator/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["visible"] = network_visibility
	data["targetAddress"] = target_address
	data["targetAddressName"] = target_address_name
	data["currentTab"] = selected_tab
	data["ring"] = ringer
	data["note"] = note
	data["flashlight"] = fon
	data["selfie_mode"] = selfie_mode
	var/list/merged_1 = ui_data_obj_item_communicator(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/communicator's window data.
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
	for(var/datum/planet/planet in SSplanets.planets)
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
	data["feeds"] = compile_news(user)
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
/datum/prompt/text/communicator
	usable_state = "default"
	timeout = 0

/datum/prompt/text/communicator/name
	name_text = TRUE
	title = "Communicator"
	question = "Please enter your name."
	encode = FALSE

/datum/prompt/text/communicator/ringtone
	title = "Ringer"
	question = "Set Ringer Tone"

/datum/prompt/text/communicator/text_message
	title = "Text Message"
	question = "Enter your message."
	encode = FALSE

/// The note's text (an empty answer clears it).
/datum/prompt/text/communicator/note
	question = "Please enter message"
	multiline = TRUE

/obj/item/communicator/proc/actor_name(datum/act/op/A)
	return A.actor?.name

/obj/item/communicator/proc/device_name(datum/act/op/A)
	return name

/obj/item/communicator/proc/note_default(datum/act/op/A)
	return notehtml

/obj/item/communicator/proc/ui_act_rename(datum/act/op/A)
	add_fingerprint(A.actor)
	var/new_name = sanitizeSafe(A.step_value("name"))
	if(new_name)
		register_device(new_name)
	return TRUE

/obj/item/communicator/proc/ui_act_toggle_visibility(datum/act/op/A)
	add_fingerprint(A.actor)
	switch(network_visibility)
		if(1) //Visible, becoming invisbile
			network_visibility = 0
			if(camera)
				camera.remove_network(NETWORK_COMMUNICATORS)
		if(0) //Invisible, becoming visible
			network_visibility = 1
			if(camera)
				camera.add_network(NETWORK_COMMUNICATORS)
	return OP_OK

/obj/item/communicator/proc/ui_act_toggle_ringer(datum/act/op/A)
	add_fingerprint(A.actor)
	ringer = !ringer
	return OP_OK

/obj/item/communicator/proc/ui_act_set_ringer_tone(datum/act/op/A)
	add_fingerprint(A.actor)
	var/tone = A.step_value("tone")
	if(tone)
		ttone = tone
	return TRUE

/obj/item/communicator/proc/ui_act_selfie_mode(datum/act/op/A)
	add_fingerprint(A.actor)
	selfie_mode = !selfie_mode
	return OP_OK

/obj/item/communicator/proc/ui_act_add_hex(datum/act/op/A, add_hex)
	add_fingerprint(A.actor)
	. = TRUE
	var/hex = add_hex
	add_to_EPv2(hex)

/obj/item/communicator/proc/ui_act_write_target_address(datum/act/op/A, val)
	add_fingerprint(A.actor)
	. = TRUE
	target_address = sanitizeSafe(val)

/obj/item/communicator/proc/ui_act_clear_target_address(datum/act/op/A)
	add_fingerprint(A.actor)
	target_address = ""
	return OP_OK

/obj/item/communicator/proc/ui_act_dial(datum/act/op/A, dial)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	. = TRUE
	if(!get_connection_to_tcomms())
		to_chat(user, span_danger("Error: Cannot connect to Exonet node."))
		return FALSE
	var/their_address = dial
	exonet.send_message(their_address, "voice")

/obj/item/communicator/proc/ui_act_decline(datum/act/op/A, decline_arg)
	add_fingerprint(A.actor)
	. = TRUE
	var/atom/decline = decline_arg
	if(decline)
		del_request(decline)

/obj/item/communicator/proc/ui_act_message(datum/act/op/A, message)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	if(!get_connection_to_tcomms())
		to_chat(user, span_danger("Error: Cannot connect to Exonet node."))
		return FALSE
	var/their_address = message
	var/text = sanitizeSafe(A.step_value("text"))
	if(!text)
		return TRUE
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
	return TRUE

/obj/item/communicator/proc/ui_act_disconnect(datum/act/op/A, disconnect)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	. = TRUE
	var/name_to_disconnect = disconnect
	for(var/mob/living/voice/V in contents)
		if(name_to_disconnect == sanitize(V.name))
			close_connection(user, V, "[user] hung up")
	for(var/obj/item/communicator/comm in communicating)
		if(name_to_disconnect == sanitize(comm.name))
			close_connection(user, comm, "[user] hung up")

/obj/item/communicator/proc/ui_act_startvideo(datum/act/op/A, startvideo)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	. = TRUE
	var/obj/item/communicator/comm = startvideo
	if(comm)
		connect_video(user, comm)

/obj/item/communicator/proc/ui_act_endvideo(datum/act/op/A)
	add_fingerprint(A.actor)
	if(video_source)
		end_video()
	return OP_OK

/obj/item/communicator/proc/ui_act_copy(datum/act/op/A, copy)
	add_fingerprint(A.actor)
	. = TRUE
	target_address = copy

/obj/item/communicator/proc/ui_act_copy_name(datum/act/op/A, copy_name)
	add_fingerprint(A.actor)
	. = TRUE
	target_address_name = copy_name

/obj/item/communicator/proc/ui_act_hang_up(datum/act/op/A)
	add_fingerprint(A.actor)
	for(var/mob/living/voice/V in contents)
		close_connection(A.actor, V, "[A.actor] hung up")
	for(var/obj/item/communicator/comm in communicating)
		close_connection(A.actor, comm, "[A.actor] hung up")
	return OP_OK

/obj/item/communicator/proc/ui_act_switch_tab(datum/act/op/A, switch_tab)
	add_fingerprint(A.actor)
	. = TRUE
	selected_tab = switch_tab

/obj/item/communicator/proc/ui_act_edit(datum/act/op/A)
	add_fingerprint(A.actor)
	var/n = sanitizeSafe(A.step_value("note"), extra = 0)
	if(n)
		note = html_decode(n)
		notehtml = note
		note = replacetext(note, "\n", "<br>")
	else
		note = ""
		notehtml = note
	return TRUE

/obj/item/communicator/proc/ui_act_light(datum/act/op/A)
	add_fingerprint(A.actor)
	. = TRUE
	fon = !fon
	set_light(fon * flum)

/obj/item/communicator/proc/ui_act_newsfeed(datum/act/op/A, newsfeed)
	add_fingerprint(A.actor)
	. = TRUE
	newsfeed_channel = newsfeed

/// Relation view: last camera turf (reads null once it is gone).
/obj/item/communicator/proc/last_camera_turf() as /turf
	return last_camera_turf
