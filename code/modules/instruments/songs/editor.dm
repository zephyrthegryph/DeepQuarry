DECLARE_UI(/datum/song, "InstrumentEditor")

/datum/song/ui_title(mob/user)
	return parent().name

/datum/song/tgui_host(mob/user)
	return parent()

UI_DATA(/datum/song, "id", "note_shift:num", "sustain_mode", "volume:num", "volume_dropoff_threshold=sustain_dropoff_volume:num", "sustain_indefinitely=full_sustain_held_note:num", "playing:num", "repeat:num", "merge:ui_data_datum_song{using_instrument:unknown,octaves:num,sustain_mode_button:text,sustain_mode_duration:num,sustain_mode_min:num,sustain_mode_max:unknown,instrument_ready:unknown,bpm:num,lines:list}")

/// The computed part of /datum/song's window data (declared on its UI_DATA row).
/datum/song/proc/ui_data_datum_song(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["using_instrument"] = using_instrument()?.name || "No instrument loaded!"
	data["octaves"] = round(note_shift / 12, 0.01)
	switch(sustain_mode)
		if(SUSTAIN_LINEAR)
			data["sustain_mode_button"] = "Linear Sustain Duration (in seconds)"
			data["sustain_mode_duration"] = sustain_linear_duration / 10
			data["sustain_mode_min"] = INSTRUMENT_MIN_TOTAL_SUSTAIN
			data["sustain_mode_max"] = INSTRUMENT_MAX_TOTAL_SUSTAIN
		if(SUSTAIN_EXPONENTIAL)
			data["sustain_mode_button"] = "Exponential Falloff Factor (% per decisecond)"
			data["sustain_mode_duration"] = sustain_exponential_dropoff
			data["sustain_mode_min"] = INSTRUMENT_EXP_FALLOFF_MIN
			data["sustain_mode_max"] = INSTRUMENT_EXP_FALLOFF_MAX
	data["instrument_ready"] = using_instrument()?.ready()
	data["bpm"] = round(60 SECONDS / tempo)
	data["lines"] = list()
	var/linecount
	for(var/line in lines)
		linecount++
		data["lines"] += list(list(
			"line_count" = linecount,
			"line_text" = line,
		))
	return data

/datum/song/tgui_static_data(mob/user)
	var/list/data = ..()
	data["can_switch_instrument"] = (length(allowed_instrument_ids) > 1)
	data["possible_instruments"] = list()
	for(var/instrument in allowed_instrument_ids)
		UNTYPED_LIST_ADD(data["possible_instruments"], list("name" = SSinstruments.ready().instrument_data[instrument], "id" = instrument))
	data["sustain_modes"] = SSinstruments.ready().note_sustain_modes
	data["max_repeats"] = max_repeats
	data["min_volume"] = min_volume
	data["max_volume"] = max_volume
	data["note_shift_min"] = note_shift_min
	data["note_shift_max"] = note_shift_max
	data["max_line_chars"] = MUSIC_MAXLINECHARS
	data["max_lines"] = MUSIC_MAXLINES
	return data

/datum/song/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!istype(user))
		return FALSE
	return TRUE

UI_ACT(/datum/song, "play_music", ui_act_play_music)
UI_ACT_PROC(/datum/song, ui_act_play_music)
	if(!playing)
		start_playing(user)
	else
		stop_playing()
	return TRUE

UI_ACT(/datum/song, "set_instrument_id", ui_act_set_instrument_id, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/song, ui_act_set_instrument_id)
	var/new_id = reject_bad_name(LOWER_TEXT(params["id"]), max_length = 20, allow_numbers = TRUE, cap_after_symbols = FALSE)
	if(new_id)
		id = new_id
	return TRUE

UI_ACT(/datum/song, "change_instrument", ui_act_change_instrument, UI_ARG_TEXT("new_instrument"))
UI_ACT_PROC(/datum/song, ui_act_change_instrument)
	var/new_instrument = params["new_instrument"]
	//only one instrument, so no need to bother changing it.
	if(!length(allowed_instrument_ids))
		return FALSE
	if(!(new_instrument in allowed_instrument_ids))
		return FALSE
	set_instrument(new_instrument)
	return TRUE

UI_ACT(/datum/song, "tempo", ui_act_tempo, UI_ARG_TEXT("tempo_change"))
UI_ACT_PROC(/datum/song, ui_act_tempo)
	var/move_direction = params["tempo_change"]
	var/tempo_diff
	if(move_direction == "increase_speed")
		tempo_diff = world.tick_lag
	else
		tempo_diff = -world.tick_lag
	tempo = sanitize_tempo(tempo + tempo_diff)
	return TRUE

//SONG MAKING

UI_ACT(/datum/song, "import_song", ui_act_import_song)
UI_ACT_PROC(/datum/song, ui_act_import_song)
	var/song_text = ""
	do
		var/_answer_k103 = act_ask(user, action, params, ui, "k103", /datum/om/prompt/text, message = "Please paste the entire song, formatted:", title = name, max_length = (MUSIC_MAXLINES * MUSIC_MAXLINECHARS), multiline = TRUE)
		if(isnull(_answer_k103))
			return
		song_text = _answer_k103
		if(!in_range(parent(), user))
			return

		if(length_char(song_text) >= MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
			var/should_continue = act_ask(user, action, params, ui, "k108", /datum/om/prompt/choice/alert, message = "Your message is too long! Would you like to continue editing it?", title = "Warning", choices = list("Yes", "No"))
			if(isnull(should_continue))
				return
			if(should_continue != "Yes")
				break
	while(length_char(song_text) > MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
	ParseSong(user, song_text)
	return TRUE

/datum/song/proc/native_ui_act_start_new_song(datum/act/op/A)
	name = ""
	lines = new()
	tempo = sanitize_tempo(5) // default 120 BPM
	return OP_OK

UI_ACT(/datum/song, "add_new_line", ui_act_add_new_line)
UI_ACT_PROC(/datum/song, ui_act_add_new_line)
	var/newline = act_ask(user, action, params, ui, "k120", /datum/om/prompt/text, message = "Enter your line", title = parent().name, max_length = MUSIC_MAXLINECHARS)
	if(isnull(newline))
		return
	if(!newline || !in_range(parent(), user))
		return
	if(lines.len > MUSIC_MAXLINES)
		return
	if(length(newline) > MUSIC_MAXLINECHARS)
		newline = copytext(newline, 1, MUSIC_MAXLINECHARS)
	lines.Add(newline)

UI_ACT(/datum/song, "delete_line", ui_act_delete_line, UI_ARG_NUM("line_deleted"))
UI_ACT_PROC(/datum/song, ui_act_delete_line)
	var/line_to_delete = params["line_deleted"]
	if(line_to_delete > lines.len || line_to_delete < 1)
		return FALSE
	lines.Cut(line_to_delete, line_to_delete + 1)
	return TRUE

UI_ACT(/datum/song, "modify_line", ui_act_modify_line, UI_ARG_NUM("line_editing"))
UI_ACT_PROC(/datum/song, ui_act_modify_line)
	var/line_to_edit = params["line_editing"]
	if(line_to_edit > lines.len || line_to_edit < 1)
		return FALSE
	var/new_line_text = act_ask(user, action, params, ui, "k138", /datum/om/prompt/text, message = "Enter your line ", title = parent().name, default = lines[line_to_edit], max_length = MUSIC_MAXLINECHARS)
	if(isnull(new_line_text))
		return
	if(isnull(new_line_text) || !in_range(parent(), user))
		return FALSE
	lines[line_to_edit] = new_line_text
	return TRUE

//MODE STUFF

UI_ACT(/datum/song, "set_sustain_mode", ui_act_set_sustain_mode, UI_ARG_VALUE("new_mode"))
UI_ACT_PROC(/datum/song, ui_act_set_sustain_mode)
	var/new_mode = params["new_mode"]
	if(isnull(new_mode) || !(new_mode in SSinstruments.ready().note_sustain_modes))
		return FALSE
	sustain_mode = new_mode
	return TRUE

UI_ACT(/datum/song, "set_note_shift", ui_act_set_note_shift, UI_ARG_NUM("amount"))
UI_ACT_PROC(/datum/song, ui_act_set_note_shift)
	var/amount = params["amount"]
	if(!isnum(amount))
		return FALSE
	note_shift = clamp(amount, note_shift_min, note_shift_max)
	return TRUE

UI_ACT(/datum/song, "set_volume", ui_act_set_volume, UI_ARG_NUM("amount"))
UI_ACT_PROC(/datum/song, ui_act_set_volume)
	var/new_volume = params["amount"]
	if(!isnum(new_volume))
		return FALSE
	set_volume(new_volume)
	return TRUE

UI_ACT(/datum/song, "set_dropoff_volume", ui_act_set_dropoff_volume, UI_ARG_NUM("amount"))
UI_ACT_PROC(/datum/song, ui_act_set_dropoff_volume)
	var/dropoff_threshold = params["amount"]
	if(!isnum(dropoff_threshold))
		return FALSE
	set_dropoff_volume(dropoff_threshold)
	return TRUE

/datum/song/proc/native_ui_act_toggle_sustain_hold_indefinitely(datum/act/op/A)
	full_sustain_held_note = !full_sustain_held_note
	return OP_OK

UI_ACT(/datum/song, "set_repeat_amount", ui_act_set_repeat_amount, UI_ARG_NUM("amount"))
UI_ACT_PROC(/datum/song, ui_act_set_repeat_amount)
	if(playing)
		return
	var/repeat_amount = params["amount"]
	if(!isnum(repeat_amount))
		return FALSE
	set_repeats(repeat_amount)
	return TRUE

UI_ACT(/datum/song, "edit_sustain_mode", ui_act_edit_sustain_mode, UI_ARG_NUM("amount"))
UI_ACT_PROC(/datum/song, ui_act_edit_sustain_mode)
	var/sustain_amount = params["amount"]
	if(isnull(sustain_amount) || !isnum(sustain_amount))
		return
	switch(sustain_mode)
		if(SUSTAIN_LINEAR)
			set_linear_falloff_duration(sustain_amount)
		if(SUSTAIN_EXPONENTIAL)
			set_exponential_drop_rate(sustain_amount)

/**
 * Parses a song the user has input into lines and stores them.
 */
/datum/song/proc/ParseSong(mob/user, new_song)
	//split into lines
	lines = islist(new_song) ? new_song : splittext(new_song, "\n")
	if(lines.len)
		var/bpm_string = "BPM: "
		if(findtext(lines[1], bpm_string, 1, length(bpm_string) + 1))
			var/divisor = text2num(copytext(lines[1], length(bpm_string) + 1)) || 120 // default
			tempo = sanitize_tempo(BPM_TO_TEMPO_SETTING(divisor))
			lines.Cut(1, 2)
		else
			tempo = sanitize_tempo(5) // default 120 BPM
		if(lines.len > MUSIC_MAXLINES)
			if(user)
				to_chat(user, "Too many lines!")
			lines.Cut(MUSIC_MAXLINES + 1)
		var/linenum = 1
		for(var/l in lines)
			if(length_char(l) > MUSIC_MAXLINECHARS)
				if(user)
					to_chat(user, "Line [linenum] too long!")
				lines.Remove(l)
			else
				linenum++
