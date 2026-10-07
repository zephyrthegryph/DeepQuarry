#define FONT_SIZE "5pt"
#define FONT_COLOR "#09f"
#define FONT_STYLE "Arial Black"
#define SCROLL_SPEED 2

// Status display
// (formerly Countdown timer display)

// Use to show shuttle ETA/ETD times
// Alert status
// And arbitrary messages set by comms computer

/obj/machinery/status_display
	icon = 'icons/obj/status_display.dmi'
	icon_state = "frame"
	plane = TURF_PLANE
	layer = ABOVE_WINDOW_LAYER
	name = "status display"
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	circuit =  /obj/item/circuitboard/status_display
	flags = WALL_ITEM
	mode = 1	// 0 = Blank
					// 1 = Shuttle timer
					// 2 = Arbitrary message(s)
					// 3 = alert picture
					// 4 = Supply shuttle timer

	var/picture_state	// icon_state of alert picture
	var/message1 = ""	// message line 1
	var/message2 = ""	// message line 2
	var/index1			// display index for scrolling messages or 0 if non-scrolling
	var/index2
	var/picture = null

	var/frequency = DISPLAY_FREQ		// radio frequency

	var/friendc = 0      // track if Friend Computer mode
	var/ignore_friendc = 0

	maptext_height = 26
	maptext_width = 32

	var/const/CHARS_PER_LINE = 5
	var/const/STATUS_DISPLAY_BLANK = 0
	var/const/STATUS_DISPLAY_TRANSFER_SHUTTLE_TIME = 1
	var/const/STATUS_DISPLAY_MESSAGE = 2
	var/const/STATUS_DISPLAY_ALERT = 3
	var/const/STATUS_DISPLAY_TIME = 4
	var/const/STATUS_DISPLAY_CUSTOM = 99

	var/seclevel = "green"

	/// When the next redraw in the `refresh_token` timer slot is due (a countdown, the clock or a
	/// scrolling message); the shuttle schedule watched in shuttle modes (SHUTTLE_SCHEDULE_*, 0
	/// for none) and the entity whose shuttle_schedule_changed notice it observes.
	var/tmp/refresh_at = 0
	var/tmp/shuttle_key_token
	var/tmp/shuttle_key_id = 0

/obj/machinery/status_display/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	attack_hand(user)
	return TRUE

// register for radio system
/obj/machinery/status_display/Initialize(mapload)
	. = ..()
	if(SSradio)
		SSradio.add_object(src, frequency)
	refresh()

// A status display redraws only when its input changes: a signal, an alert, power, the
// shuttle key, or an after() timer for content that moves on its own (a countdown, the clock,
// a scrolling message). It never polls.

/// Deciseconds until the display must redraw with no new input, or 0 while it is static.
/obj/machinery/status_display/proc/next_refresh_delay()
	if(friendc && !ignore_friendc)
		return 0
	switch(mode)
		if(STATUS_DISPLAY_TRANSFER_SHUTTLE_TIME)
			if(SSemergency_shuttle?.shuttle && SSemergency_shuttle.has_eta())
				return 2 SECONDS
		if(STATUS_DISPLAY_MESSAGE)
			if(index1 || index2)
				return 2 SECONDS
		if(STATUS_DISPLAY_TIME)
			// The clock shows hh:mm: redraw at the next station minute.
			var/now = station_time_in_ds + GLOB.timezoneOffset
			return max(1, 1 MINUTE - (now - FLOOR(now, 1 MINUTE)))
	return 0

/// The SHUTTLE_SCHEDULE_* schedule this display shows, or 0.
/obj/machinery/status_display/proc/watched_shuttle()
	return mode == STATUS_DISPLAY_TRANSFER_SHUTTLE_TIME ? SHUTTLE_SCHEDULE_EVAC : 0

/// The entity that publishes shuttle_schedule_changed for schedule `id`.
/proc/shuttle_schedule_source(id)
	switch(id)
		if(SHUTTLE_SCHEDULE_EVAC)
			return SSemergency_shuttle
		if(SHUTTLE_SCHEDULE_SUPPLY)
			return SSsupply
	return null

/// A watched shuttle schedule changed.
/obj/machinery/status_display/proc/shuttle_schedule_seen(datum/act/A)
	if(!QDELETED(src))
		refresh()

/// Redraws now and schedules the next redraw.
/obj/machinery/status_display/proc/refresh()
	if(power_lost())
		remove_display()
	else
		update()
	schedule_refresh()

/obj/machinery/status_display/proc/schedule_refresh()
	var/powered = !power_lost()
	var/want_shuttle = powered ? watched_shuttle() : 0
	if(want_shuttle != shuttle_key_id)
		if(!isnull(shuttle_key_token))
			unobserve(shuttle_key_token, /datum/notice/shuttle_schedule_changed, src)
			shuttle_key_token = null
		shuttle_key_id = want_shuttle
		var/datum/source = shuttle_schedule_source(want_shuttle)
		if(source)
			sleep_audit_join(src)
			observe(source, /datum/notice/shuttle_schedule_changed, src, then(PROC_REF(shuttle_schedule_seen)))
			shuttle_key_token = source
	var/delay = powered ? next_refresh_delay() : 0
	var/at = delay ? world.time + delay : 0
	if(after_pending(src, "refresh_token"))
		if(at && at == refresh_at)
			return
		cancel_after(src, "refresh_token")
	refresh_at = at
	if(at)
		sleep_audit_join(src)
		after(src, delay, PROC_REF(refresh_timer_fired), key = "refresh_token")

/obj/machinery/status_display/proc/refresh_timer_fired()
	refresh_at = 0
	refresh()

/obj/machinery/status_display/sleep_violation()
	if(power_lost())
		return null
	if(next_refresh_delay() && !after_pending(src, "refresh_token"))
		return "mode [mode] needs redrawing but has no timer"
	if(watched_shuttle() != shuttle_key_id || (shuttle_key_id && isnull(shuttle_key_token)))
		return "mode [mode] is not watching its shuttle"
	return null

/obj/machinery/status_display/power_change()
	. = ..()
	if(.)
		refresh()

CAPABILITIES(/obj/machinery/status_display)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(status_display_emp))))
	op("attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_attackby)))
	display_disconnect_op()

/// An EMP blue-screens a working display.
/obj/machinery/status_display/proc/status_display_emp(datum/act/hit/emp/A)
	if(!operable())
		return HOOK_DECLINE
	set_picture("ai_bsod")
	return HOOK_DECLINE

// set what is displayed
/obj/machinery/status_display/proc/update()
	remove_display()
	if(friendc && !ignore_friendc)
		set_picture("ai_friend")
		return 1

	switch(mode)
		if(STATUS_DISPLAY_BLANK)	//blank
			return 1
		if(STATUS_DISPLAY_TRANSFER_SHUTTLE_TIME)				//emergency shuttle timer
			if(!SSemergency_shuttle?.shuttle)
				message1 = "-ETA-"
				message2 = "Never" // You're here forever.
				return 1
			if(SSemergency_shuttle.waiting_to_leave())
				message1 = "-ETD-"
				if(SSemergency_shuttle.shuttle.is_launching())
					message2 = "Launch"
				else
					message2 = get_shuttle_timer_departure()
					if(length(message2) > CHARS_PER_LINE)
						message2 = "Error"
				update_display(message1, message2)
			else if(SSemergency_shuttle.has_eta())
				message1 = "-ETA-"
				message2 = get_shuttle_timer_arrival()
				if(length(message2) > CHARS_PER_LINE)
					message2 = "Error"
				update_display(message1, message2)
			return 1
		if(STATUS_DISPLAY_MESSAGE)	//custom messages
			var/line1
			var/line2

			if(!index1)
				line1 = message1
			else
				line1 = copytext(message1+"|"+message1, index1, index1+CHARS_PER_LINE)
				var/message1_len = length(message1)
				index1 += SCROLL_SPEED
				if(index1 > message1_len)
					index1 -= message1_len

			if(!index2)
				line2 = message2
			else
				line2 = copytext(message2+"|"+message2, index2, index2+CHARS_PER_LINE)
				var/message2_len = length(message2)
				index2 += SCROLL_SPEED
				if(index2 > message2_len)
					index2 -= message2_len
			update_display(line1, line2)
			return 1
		if(STATUS_DISPLAY_ALERT)
			display_alert(seclevel)
			return 1
		if(STATUS_DISPLAY_TIME)
			message1 = "TIME"
			message2 = stationtime2text()
			update_display(message1, message2)
			return 1
	return 0

/obj/machinery/status_display/examine(mob/user)
	. = ..()
	if(mode != STATUS_DISPLAY_BLANK && mode != STATUS_DISPLAY_ALERT)
		. += "The display says:<br>\t[sanitize(message1)]<br>\t[sanitize(message2)]"

/obj/machinery/status_display/proc/set_message(m1, m2)
	if(m1)
		index1 = (length(m1) > CHARS_PER_LINE)
		message1 = m1
	else
		message1 = ""
		index1 = 0

	if(m2)
		index2 = (length(m2) > CHARS_PER_LINE)
		message2 = m2
	else
		message2 = ""
		index2 = 0

/obj/machinery/status_display/proc/display_alert(newlevel)
	remove_display()
	if(seclevel != newlevel)
		seclevel = newlevel
	switch(seclevel)
		if("green")	set_light(l_range = 2, l_power = 0.25, l_color = "#00ff00")
		if("yellow")	set_light(l_range = 2, l_power = 0.25, l_color = "#ffff00")
		if("violet")	set_light(l_range = 2, l_power = 0.25, l_color = "#9933ff")
		if("orange")	set_light(l_range = 2, l_power = 0.25, l_color = "#ff9900")
		if("blue")	set_light(l_range = 2, l_power = 0.25, l_color = "#1024A9")
		if("red")	set_light(l_range = 4, l_power = 0.9, l_color = "#ff0000")
		if("delta")	set_light(l_range = 4, l_power = 0.9, l_color = "#FF6633")
	set_picture("status_display_[seclevel]")

// Called when the alert level is changed.
/obj/machinery/status_display/proc/on_alert_changed(new_level)
	// On most alerts, this will change to a flashing alert picture in a specific color.
	// Doing that for green alert automatically doesn't really make sense, but it is still available on the comm consoles/PDAs.
	if(seclevel2num(new_level) == SEC_LEVEL_GREEN)
		set_mode(STATUS_DISPLAY_TIME)
		set_light(0) // Remove any glow we had from the alert previously.
		refresh()
		return
	set_mode(STATUS_DISPLAY_ALERT)
	display_alert(new_level)
	schedule_refresh()

/obj/machinery/status_display/proc/set_picture(state)
	remove_display()
	if(!picture || picture_state != state)
		picture_state = state
		picture = image('icons/obj/status_display.dmi', icon_state=picture_state)
	add_overlay(picture)

/obj/machinery/status_display/proc/update_display(line1, line2)
	var/new_text = {"<div style="font-size:[FONT_SIZE];color:[FONT_COLOR];font:'[FONT_STYLE]';text-align:center;" valign="top">[line1]<br>[line2]</div>"}
	if(maptext != new_text)
		maptext = new_text

/obj/machinery/status_display/proc/get_shuttle_timer_arrival()
	if(!SSemergency_shuttle)
		return "Error"
	var/timeleft = SSemergency_shuttle.estimate_arrival_time()
	if(timeleft < 0)
		return ""
	return "[add_zero(num2text((timeleft / 60) % 60),2)]:[add_zero(num2text(timeleft % 60), 2)]"

/obj/machinery/status_display/proc/get_shuttle_timer_departure()
	if(!SSemergency_shuttle)
		return "Error"
	var/timeleft = SSemergency_shuttle.estimate_launch_time()
	if(timeleft < 0)
		return ""
	return "[add_zero(num2text((timeleft / 60) % 60),2)]:[add_zero(num2text(timeleft % 60), 2)]"

/obj/machinery/status_display/proc/get_supply_shuttle_timer()
	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.shuttle
	if(!shuttle)
		return "Error"

	if(shuttle.has_arrive_time())
		var/timeleft = round((shuttle.arrive_time - world.time) / 10,1)
		if(timeleft < 0)
			return "Late"
		return "[add_zero(num2text((timeleft / 60) % 60),2)]:[add_zero(num2text(timeleft % 60), 2)]"
	return ""

/obj/machinery/status_display/proc/remove_display()
	cut_overlays()
	if(maptext)
		maptext = ""

/obj/machinery/status_display/receive_signal(datum/signal/signal)
	switch(signal.data["command"])
		if("blank")
			set_mode(STATUS_DISPLAY_BLANK)
			set_light(0)

		if("shuttle")
			set_mode(STATUS_DISPLAY_TRANSFER_SHUTTLE_TIME)
			set_light(0)

		if("message")
			set_mode(STATUS_DISPLAY_MESSAGE)
			set_message(signal.data["msg1"], signal.data["msg2"])
			set_light(0)

		if("alert")
			set_mode(STATUS_DISPLAY_ALERT)
			set_picture(signal.data["picture_state"])

		if("time")
			set_mode(STATUS_DISPLAY_TIME)
			set_light(0)
	refresh()

#undef FONT_SIZE
#undef FONT_COLOR
#undef FONT_STYLE
#undef SCROLL_SPEED
