// Per-atom chat-tag color cache, formerly the chat_color, chat_color_name,
// and chat_color_darkened vars on /atom, then /datum/component/chat_color_cache.
//
// The cache is derived, so it is never saved. The global helpers stay as the one read/write API.
// Sparse slots (code/engine/declare/sparse_slots.dm): nothing on /atom until an atom speaks.
sparse(/atom, chat_color, type = color)
/// The name string the colors were computed for; reused as invalidation key.
sparse(/atom, chat_color_name, type = text)
sparse(/atom, chat_color_darkened, type = color)

/proc/dq_get_chat_color(atom/a)
	return sparse_get(a, chat_color)

/proc/dq_get_chat_color_name(atom/a)
	return sparse_get(a, chat_color_name)

/proc/dq_get_chat_color_darkened(atom/a)
	return sparse_get(a, chat_color_darkened)

/proc/dq_set_chat_color_cache(atom/a, color, color_name, darkened)
	sparse_set(a, chat_color, color)
	sparse_set(a, chat_color_name, color_name)
	sparse_set(a, chat_color_darkened, darkened)
