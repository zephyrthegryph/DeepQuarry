// Per-atom chat-tag color cache, formerly the chat_color, chat_color_name,
// and chat_color_darkened vars on /atom, then /datum/component/chat_color_cache.
//
// The cache is derived, so it is never saved. The global helpers stay as the one read/write API.
// Lazy state (the chat_tint row, doc/rewrite/storage_contract.md): nothing on /atom until an atom speaks.

/proc/dq_get_chat_color(atom/a)
	return STATE_PEEK(a, chat_tint, chat_color)

/proc/dq_get_chat_color_name(atom/a)
	return STATE_PEEK(a, chat_tint, chat_color_name)

/proc/dq_get_chat_color_darkened(atom/a)
	return STATE_PEEK(a, chat_tint, chat_color_darkened)

/proc/dq_set_chat_color_cache(atom/a, color, color_name, darkened)
	STATE_SET(a, chat_tint, chat_color, color)
	STATE_SET(a, chat_tint, chat_color_name, color_name)
	STATE_SET(a, chat_tint, chat_color_darkened, darkened)
