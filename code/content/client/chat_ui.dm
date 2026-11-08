// The chat as a tgui interface (doc/rewrite/proposals/window_system.md section 12): one per client, the "Chat" window. It docks in the
// right-hand column by default and floats like any other window, through the same dock model. Docked, it is part of the column page, so
// its messages keep going to the page itself (client.chat_window() is the panel's window); floating, they go to its own window. Each new
// window asks for what it has not shown (chat/ready), answered from the client's history ring (SSchat.replay), and the input draft lives
// here (chat/draft), so moving the chat loses neither. Everything else its page sends goes to the panel, as the column page's chat does.

/datum/chat_ui
	/// The client whose chat this is: a one-sided back view (the client owns it).
	var/client/owner
	/// What the input row held last (chat/draft): a new window starts with it.
	var/draft = ""

/datum/chat_ui/New(client/owner)
	rel_set(src, nameof(owner), owner)

CAPABILITIES(/datum/chat_ui)
	ref_one(nameof(owner))
	interface("Chat", title = "Chat", state = nameof(GLOB.tgui_always_state), pinned = TRUE)
	ui_shape(draft = schema_text())

/// The client using the chat.
/datum/chat_ui/proc/owner() as /client
	return owner

/datum/chat_ui/ui_prepare(mob/user, datum/tgui/ui)
	return !!owner() && user?.client == owner()

/datum/chat_ui/ui_data(datum/act/eval/A)
	return list("draft" = draft)

/// Its window is where the chat goes while it floats; docked, the column page has it (chat_window()).
/datum/chat_ui/ui_opened(mob/user, datum/tgui/ui)
	var/client/player = owner()
	var/datum/tgui_window/window = ui?.window()
	if(!player || !window)
		return
	rel_set(player, nameof(/client::chat_ui_window), window)
	log_tgui(player, "Chat opened in [window.id] ([ui.docked ? "docked" : "floating"]).", context = "chat")
	if(ui.docked)
		return
	// A floating chat is a page of its own: it gets the panel's connect messages and the input row's state.
	player.tgui_panel?.send_chat_config(window, "chat/config")
	player.chat_send_input_state()

/// The chat page's messages: its own two, then speech, resends and the rest as the panel takes them.
/datum/chat_ui/ui_raw_message(mob/user, type, list/payload)
	var/client/player = owner()
	if(!player || user?.client != player)
		return FALSE
	switch(type)
		if("chat/ready")
			var/after = text2num("[payload?["after"]]")
			SSchat.replay(player, isnull(after) ? -1 : after)
			return TRUE
		if("chat/draft")
			var/text = payload?["draft"]
			set_draft(istext(text) ? copytext(text, 1, MAX_MESSAGE_LEN + 1) : "")
			return TRUE
	return player.tgui_panel?.on_message(type, payload, list())

/// Opens (or re-opens) the client's chat window: docked unless the player floated it.
/proc/chat_ui_open(client/player)
	if(!player?.mob)
		return null
	if(!player.chat_ui)
		rel_set(player, nameof(/client::chat_ui), new /datum/chat_ui(player))
	return player.chat_ui.tgui_interact(player.mob)

/// The client's chat interface (its window is `chat_ui_window`).
/client/var/tmp/datum/chat_ui/chat_ui
