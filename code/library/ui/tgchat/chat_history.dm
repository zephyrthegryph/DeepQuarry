// A client's recent chat messages (doc/rewrite/proposals/window_system.md section 12): a fixed ring, slot `sequence % size`, of each message's
// encoded text (what the chat page is sent), so a message is kept, found again for a resend and replayed in order at O(1) a message, and the
// ring holds only text and numbers. The chat window replays it when it moves between the right-hand column and a floating window.

/datum/chat_history
	/// Per slot: the sequence kept there, or -1.
	var/list/sequences
	/// Per slot: that message's encoded text (chat_payload into_message()).
	var/list/messages
	/// Per slot: how many times it was resent (CHAT_RELIABILITY_MAX_RESENDS).
	var/list/resends
	/// The newest sequence kept, or -1 before the first.
	var/newest = -1

/datum/chat_history/New()
	sequences = new /list(CHAT_HISTORY_SIZE)
	messages = new /list(CHAT_HISTORY_SIZE)
	resends = new /list(CHAT_HISTORY_SIZE)

/// Keeps message `sequence` (its encoded `text`); the slot's older message goes.
/datum/chat_history/proc/keep(sequence, text)
	var/slot = (sequence % CHAT_HISTORY_SIZE) + 1
	sequences[slot] = sequence
	messages[slot] = text
	resends[slot] = 0
	if(sequence > newest)
		newest = sequence

/// The slot of kept message `sequence`, or 0 when it has been overwritten or was never kept.
/datum/chat_history/proc/slot_of(sequence)
	if(!isnum(sequence) || sequence < 0)
		return 0
	var/slot = (sequence % CHAT_HISTORY_SIZE) + 1
	return sequences[slot] == sequence ? slot : 0

/// The encoded text of kept message `sequence`, or null.
/datum/chat_history/proc/find(sequence)
	var/slot = slot_of(sequence)
	return slot ? messages[slot] : null

/// Counts one resend of `sequence`; FALSE when it is not kept or was resent CHAT_RELIABILITY_MAX_RESENDS times already.
/datum/chat_history/proc/take_resend(sequence)
	var/slot = slot_of(sequence)
	if(!slot || resends[slot] > CHAT_RELIABILITY_MAX_RESENDS)
		return FALSE
	resends[slot]++
	return TRUE

/// The encoded texts of the kept messages newer than `after` (a sequence; -1 for all), oldest first.
/datum/chat_history/proc/since(after = -1)
	. = list()
	if(newest < 0)
		return
	for(var/sequence in max(after + 1, newest - CHAT_HISTORY_SIZE + 1, 0) to newest)
		var/text = find(sequence)
		if(text)
			. += text
