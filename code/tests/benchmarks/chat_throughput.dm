// Chat message throughput on the server: what each message to a client costs before it leaves (its payload with the sequence number and the
// resend/history record, and its encoded message). Chat must never get slower as it moves into the window system
// (doc/rewrite/proposals/window_system.md section 12): run this before and after a change to the chat path.
//
// Run: tools/build/build.sh bench --scenario=chat_throughput [--bench_messages=20000]

/// A stand-in client for the bench: the chat path reads the target's ckey and keeps its recent messages on it.
/datum/chat_bench_target
	var/ckey = "chatbench"
	var/datum/chat_history/chat_history

/// As /client/proc/make_chat_history(), for the stand-in (no declared relation: this type exists only in the bench build).
/datum/chat_bench_target/proc/make_chat_history()
	chat_history = new
	return chat_history

/datum/benchmark/chat_throughput
	id = "chat_throughput"
	description = "Server cost per chat message: payload, sequence, history record and the encoded message"

/// The path before the chat history ring, kept here so both run in the same world and the same load: the payload, its JSON, and the old
/// reliability history (an associative list of the last 5 payloads, its oldest found by a scan and dropped), with the placeholder check.
/datum/chat_bench_target/proc/old_generate(list/message_data)
	// The admin-link placeholder check every message had then too (generate_payload()).
	for(var/field in list("html", "text"))
		var/original = message_data[field]
		if(!istext(original) || !findtext(original, HREF_TOKEN_PLACEHOLDER))
			continue
	var/static/list/sequences = list()
	var/static/list/histories = list()
	var/sequence = sequences[ckey]
	sequences[ckey] += 1
	var/datum/chat_payload/payload = new
	payload.sequence = sequence
	payload.content = message_data
	if(!(ckey in histories))
		histories[ckey] = list()
	var/list/client_history = histories[ckey]
	client_history["[sequence]"] = payload
	if(length(client_history) > 5)
		var/oldest = text2num(client_history[1])
		for(var/index in 2 to length(client_history))
			var/test = text2num(client_history[index])
			if(test < oldest)
				oldest = test
		client_history -= "[oldest]"
	return payload.into_message()

/datum/benchmark/chat_throughput/Run()
	var/messages = param("messages", 20000)
	var/rounds = param("rounds", 4)
	var/datum/chat_bench_target/target = new
	SSchat.forget(target.ckey)
	var/old_ms = 0
	var/new_ms = 0
	var/bytes = 0
	begin_window()
	// Alternating rounds: whatever else the machine does lands on both paths alike.
	for(var/round in 1 to rounds)
		var/started = REALTIMEOFDAY
		for(var/i in 1 to messages)
			bytes += length(target.old_generate(list(
				"type" = MESSAGE_TYPE_LOCALCHAT,
				"html" = "<span class='game say'><span class='name'>Nick Price</span> says, \"Message number [i] on the bench.\"</span>",
			)))
		old_ms += (REALTIMEOFDAY - started) * 100
		started = REALTIMEOFDAY
		for(var/i in 1 to messages)
			var/datum/chat_payload/payload = SSchat.generate_payload(target, list(
				"type" = MESSAGE_TYPE_LOCALCHAT,
				"html" = "<span class='game say'><span class='name'>Nick Price</span> says, \"Message number [i] on the bench.\"</span>",
			))
			bytes += length(payload.encoded)
		new_ms += (REALTIMEOFDAY - started) * 100
	end_window("chat")
	var/total = messages * rounds
	metric("chat_per_message_us", round(new_ms * 1000 / max(1, total), 0.01), "us")
	metric("chat_old_per_message_us", round(old_ms * 1000 / max(1, total), 0.01), "us")
	metric("chat_new_over_old", round(new_ms / max(0.001, old_ms), 0.001), "ratio")
	count_metric("chat_history_kept", length(target.chat_history?.since(-1)), "messages", better = "higher")
	detail("messages", total)
	detail("encoded_bytes", bytes)
	SSchat.forget(target.ckey)
	target.chat_history = null
