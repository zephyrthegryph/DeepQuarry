// chat_tint: lazy state of /atom (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, chat_tint, field), write with STATE_SET(A, chat_tint, field, value), end it with chat_tint_clear(A).

/datum/chat_tint_state
	parent_type = /datum/lazy_state
	/// Per-atom chat-tag color cache, formerly the chat_color, chat_color_name, and chat_color_darkened vars on /atom, then /datum/component/chat_color_cache.  The cache is derived, so it is never saved. The global helpers stay as the one read/write API. Sparse slots (code/engine/declare/sparse_slots.dm): nothing on /atom until an atom speaks.
	var/chat_color
	var/chat_color_darkened
	/// / The name string the colors were computed for; reused as invalidation key.
	var/chat_color_name
