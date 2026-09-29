//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32


/obj/machinery/computer/telecomms/traffic
	name = "Telecommunications Traffic Control"
	desc = "Used to upload code to telecommunication consoles for execution."
	icon_screen = "generic"

	var/screen = 0				// the screen number:
	var/list/servers	// the servers located by the computer
	var/editingcode_handle
	var/lasteditor_handle
	var/list/viewingcode
	var/SelectedServer_handle
	circuit = /obj/item/circuitboard/comm_traffic
	req_access = list(ACCESS_TCOMSAT)

	var/network = "NULL"		// the network to probe
	var/temp = ""				// temporary feedback messages

	var/storedcode = ""			// code stored


/obj/machinery/computer/telecomms/traffic/proc/update_ide()
	if(ide_ticking)
		return
	ide_ticking = TRUE
	update_ide_tick()

/obj/machinery/computer/telecomms/traffic/var/tmp/ide_ticking = FALSE

/// One half-second refresh of the IDE while someone is manning the keyboard.
/obj/machinery/computer/telecomms/traffic/proc/update_ide_tick()
	if(!editingcode())
		update_ide_end()
		return
	if(!editingcode().client)
		editingcode_handle = null
		update_ide_end()
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
		editingcode_handle = null
		update_ide_end()
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
	om_after(src, 5, PROC_REF(update_ide_tick))

/// dx_winget() callback: buffers the typer's text, if they are still the one typing.
/obj/machinery/computer/telecomms/traffic/proc/ide_code_read(value, mob/typer)
	if(editingcode() != typer)
		return
	storedcode = "[value]"

/obj/machinery/computer/telecomms/traffic/proc/update_ide_end()
	ide_ticking = FALSE

	if(length(viewingcode) > 0)
		editingcode_handle = om_handle(DEFAULTPICK(viewingcode, null))
		LAZYREMOVE(viewingcode, editingcode())
		update_ide()


// structured TGUI Traffic Control (see
// code/modules/admin/traffic_control_panel.dm).

/// Access gate shared by the traffic console's actions.
/obj/machinery/computer/telecomms/traffic/proc/traffic_access(mob/user)
	add_fingerprint(user)
	user.set_machine(src)
	if(!src.allowed(user) && !emagged)
		to_chat(user, span_warning("ACCESS DENIED."))
		return FALSE
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/traffic_view_server(mob/user, id)
	if(!traffic_access(user))
		return
	screen = 1
	for(var/obj/machinery/telecomms/T in servers)
		if(T.id == id)
			SelectedServer_handle = om_handle(T)
			break
	updateUsrDialog(user)

/obj/machinery/computer/telecomms/traffic/proc/traffic_set_network(mob/user)
	if(!traffic_access(user))
		return
	om_ask(user, /datum/om/prompt/text, PROC_REF(network_entered), message = "Which network do you want to view?", title = "Comm Monitor", default = network, max_length = 15, requires = PROMPT_USABLE)
	updateUsrDialog(user)

/obj/machinery/computer/telecomms/traffic/proc/traffic_operation(mob/user, op)
	if(!traffic_access(user))
		return
	switch(op)

		if("release")
			servers = list()
			screen = 0

		if("mainmenu")
			screen = 0

		if("scan")
			if(length(servers) > 0)
				temp = span_red("- FAILED: CANNOT PROBE WHEN BUFFER FULL -")

			else
				for(var/obj/machinery/telecomms/server/T in range(25, src))
					if(T.network == network)
						LAZYADD(servers, T)

				if(!length(servers))
					temp = span_red("- FAILED: UNABLE TO LOCATE SERVERS IN \[[network]\] -")
				else
					temp = span_blue("- [length(servers)] SERVERS PROBED & BUFFERED -")

				screen = 0

		if("editcode")
			if(editingcode() == user) return
			if(user in viewingcode) return

			if(!editingcode())
				lasteditor_handle = om_handle(user)
				editingcode_handle = om_handle(user)
				winshow(editingcode(), "Telecomms IDE", 1) // show the IDE
				winset(editingcode(), "tcscode", "is-disabled=false")
				winset(editingcode(), "tcscode", "text=\"\"")
				var/showcode = replacetext(storedcode, "\\\"", "\\\\\"")
				showcode = replacetext(storedcode, "\"", "\\\"")
				winset(editingcode(), "tcscode", "text=\"[showcode]\"")
				update_ide()

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

/obj/machinery/computer/telecomms/traffic/proc/network_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	var/newnet = ask.text
	if(newnet && ((user in range(1, src)) || issilicon(user)))
		if(length(newnet) > 15)
			temp = span_red("- FAILED: NETWORK TAG STRING TOO LENGHTLY -")

		else

			network = newnet
			screen = 0
			servers = list()
			temp = span_blue("- NEW NETWORK TAG SET IN ADDRESS \[[network]\] -")

DECLARE_EMAG(/obj/machinery/computer/telecomms/traffic, PROC_REF(on_emag), null)
/obj/machinery/computer/telecomms/traffic/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(!emagged)
		play_sfx(src, SFX_EFFECTS_SPARKS4)
		set_emagged(1)
		to_chat(user, span_notice("You you disable the security protocols"))
		updateUsrDialog(user)
		return 1

/// LC-refs: editingcode -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/telecomms/traffic/proc/editingcode() as /mob
	return om_resolve(editingcode_handle)

/// LC-refs: lasteditor -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/telecomms/traffic/proc/lasteditor() as /mob
	return om_resolve(lasteditor_handle)

/// LC-refs: SelectedServer -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/telecomms/traffic/proc/SelectedServer() as /obj/machinery/telecomms/server
	return om_resolve(SelectedServer_handle)
