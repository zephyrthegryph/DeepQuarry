//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32


/obj/machinery/computer/telecomms/traffic
	name = "Telecommunications Traffic Control"
	desc = "Used to upload code to telecommunication consoles for execution."
	icon_screen = "generic"

	var/screen = 0				// the screen number:
	var/list/servers	// the servers located by the computer
	var/mob/lasteditor
	var/list/viewingcode
	var/obj/machinery/telecomms/server/SelectedServer
	circuit = /obj/item/circuitboard/comm_traffic
	req_access = list(ACCESS_TCOMSAT)

	temp = ""

	var/storedcode = ""			// code stored

/// The mob typing in the IDE (a relation view), or null.
/obj/machinery/computer/telecomms/traffic/var/mob/editingcode
/// Refreshes the IDE every half second while someone is typing in it.


/// One half-second refresh of the IDE while someone is manning the keyboard.
/obj/machinery/computer/telecomms/traffic/proc/update_ide_tick(datum/act/timer/A)
	if(!editingcode() || !editingcode().client)
		pass_editor()
		return

	// For the typer, the input is enabled. Buffer the typed text
	if(editingcode())
		dx_winget(src, editingcode().client, "tcscode", "text", PROC_REF(ide_code_read), editingcode()) // DX-exec: a client round trip
	if(editingcode()) // double if's to work around a runtime error
		winset(editingcode(), "tcscode", "is-disabled=false")

	// If the player's not manning the keyboard anymore, adjust everything
	if( (!(editingcode() in range(1, src)) && !issilicon(editingcode())) || (!editingcode().check_current_machine(src) && !issilicon(editingcode())))
		if(editingcode())
			winshow(editingcode(), "Telecomms IDE", 0) // hide the window!
		pass_editor()
		return

	// For other people viewing the typer type code, the input is disabled and they can only view the code
	// (this is put in place so that there's not any magical shenanigans with 50 people inputting different code all at once)

	if(length(viewingcode))
		// This piece of code is very important - it escapes quotation marks so string aren't cut off by the input element
		var/showcode = replacetext(storedcode, "\\\"", "\\\\\"")
		showcode = replacetext(storedcode, "\"", "\\\"")

		for(var/mob/M in viewingcode)

			if( (M.check_current_machine(src) && (M in view(1, src)) ) || issilicon(M))
				winset(M, "tcscode", "is-disabled=true")
				winset(M, "tcscode", "text=\"[showcode]\"")
			else
				LAZYREMOVE(viewingcode, M)
				winshow(M, "Telecomms IDE", 0) // hide the window!

/// dx_winget() callback: buffers the typer's text, if they are still the one typing.
/obj/machinery/computer/telecomms/traffic/proc/ide_code_read(value, mob/typer)
	if(editingcode() != typer)
		return
	storedcode = "[value]"

/// The typer let go of the keyboard: a viewer (if any) takes over, else nobody is editing.
/obj/machinery/computer/telecomms/traffic/proc/pass_editor()
	if(length(viewingcode) > 0)
		rel_set(src, nameof(editingcode), DEFAULTPICK(viewingcode, null))
		LAZYREMOVE(viewingcode, editingcode())
	else
		rel_clear(src, nameof(editingcode))


// structured TGUI Traffic Control (see
// code/modules/admin/traffic_control_panel.dm).

/// Access gate shared by the traffic console's actions.
/obj/machinery/computer/telecomms/traffic/proc/traffic_access(mob/user)
	add_fingerprint(user)
	user.set_machine(src)
	if(!src.allowed(user) && !emagged())
		to_chat(user, span_warning("ACCESS DENIED."))
		return FALSE
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/traffic_view_server(mob/user, id)
	if(!traffic_access(user))
		return
	screen = 1
	for(var/obj/machinery/telecomms/T in servers)
		if(T.id == id)
			rel_set(src, nameof(SelectedServer), T)
			break
	updateUsrDialog(user)

/obj/machinery/computer/telecomms/traffic/proc/traffic_operation(mob/user, op)
	if(!traffic_access(user))
		return
	switch(op)

		if("release")
			rel_clear(src, nameof(servers))
			screen = 0

		if("mainmenu")
			screen = 0

		if("scan")
			if(length(servers) > 0)
				set_temp(span_red("- FAILED: CANNOT PROBE WHEN BUFFER FULL -"))

			else
				for(var/obj/machinery/telecomms/server/T in range(25, src))
					if(T.network == network)
						rel_add(src, nameof(servers), T)

				if(!length(servers))
					set_temp(span_red("- FAILED: UNABLE TO LOCATE SERVERS IN \[[network]\] -"))
				else
					set_temp(span_blue("- [length(servers)] SERVERS PROBED & BUFFERED -"))

				screen = 0

		if("editcode")
			if(editingcode() == user) return
			if(user in viewingcode) return

			if(!editingcode())
				rel_set(src, nameof(lasteditor), user)
				rel_set(src, nameof(editingcode), user)
				winshow(editingcode(), "Telecomms IDE", 1) // show the IDE
				winset(editingcode(), "tcscode", "is-disabled=false")
				winset(editingcode(), "tcscode", "text=\"\"")
				var/showcode = replacetext(storedcode, "\\\"", "\\\\\"")
				showcode = replacetext(storedcode, "\"", "\\\"")
				winset(editingcode(), "tcscode", "text=\"[showcode]\"")

			else
				LAZYADD(viewingcode, user)
				winshow(user, "Telecomms IDE", 1) // show the IDE
				winset(user, "tcscode", "is-disabled=true")
				winset(editingcode(), "tcscode", "text=\"\"")
				var/showcode = replacetext(storedcode, "\"", "\\\"")
				winset(user, "tcscode", "text=\"[showcode]\"")

		if("togglerun")
			SelectedServer()?.autoruncode = !(SelectedServer()?.autoruncode)

	updateUsrDialog(user)

/obj/machinery/computer/telecomms/traffic/proc/network_entered(datum/act/op/A)
	var/mob/user = A.actor
	var/newnet = A.step_value("network")
	if(newnet && ((user in range(1, src)) || issilicon(user)))
		if(length(newnet) > 15)
			set_temp(span_red("- FAILED: NETWORK TAG STRING TOO LENGHTLY -"))

		else

			network = newnet
			screen = 0
			rel_clear(src, nameof(servers))
			set_temp(span_blue("- NEW NETWORK TAG SET IN ADDRESS \[[network]\] -"))

CAPABILITIES(/obj/machinery/computer/telecomms/traffic)
	every(0.5 SECONDS, then(PROC_REF(update_ide_tick)), when = nameof(editingcode))
	emag(then(PROC_REF(on_emag)))
	op("clear_temp", ui_act(), then(PROC_REF(ui_act_clear_temp)))
	interface("TrafficControl", title = "Telecommunications Traffic Control", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("set_network", ui_act("set_network"), needs(req(PROC_REF(network_prompt_access))), asks(/datum/prompt/text, step = "network", fields = list("title" = "Comm Monitor", "question" = "Which network do you want to view?", "default" = computed(PROC_REF(network_prompt_default)), "max_len" = 15, "ask_flags" = ASK_CAPABLE, "timeout" = 0)), then(PROC_REF(ui_act_set_network)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("flush_buffer", ui_act("flush_buffer"), then(PROC_REF(ui_act_flush_buffer)))
	op("view_server", ui_act("view_server", arg("id", schema_text(4096))), then(PROC_REF(ui_act_view_server)))
	op("main_menu", ui_act("main_menu"), then(PROC_REF(ui_act_main_menu)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("edit_code", ui_act("edit_code"), then(PROC_REF(ui_act_edit_code)))
	op("toggle_run", ui_act("toggle_run"), then(PROC_REF(ui_act_toggle_run)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/computer/telecomms/traffic/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(src, SFX_EFFECTS_SPARKS4)
	set_emagged(1)
	to_chat(user, span_notice("You you disable the security protocols"))
	updateUsrDialog(user)
	return OP_OK

/// editingcode (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/traffic/proc/editingcode() as /mob
	return editingcode

/// lasteditor (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/traffic/proc/lasteditor() as /mob
	return lasteditor

/// SelectedServer (a relation view: it reads null once the target is deleted).
/obj/machinery/computer/telecomms/traffic/proc/SelectedServer() as /obj/machinery/telecomms/server
	return SelectedServer

MSG_DEF_SELF(traffic/access_denied, "ACCESS DENIED.")

/obj/machinery/computer/telecomms/traffic/proc/network_prompt_access(datum/act/op/A)
	return (allowed(A.actor) || emagged()) ? null : MSG(traffic/access_denied)

/obj/machinery/computer/telecomms/traffic/proc/network_prompt_default(datum/act/op/A)
	return network
