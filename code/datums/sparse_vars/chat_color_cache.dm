// Per-atom chat-tag color cache, formerly the chat_color, chat_color_name,
// and chat_color_darkened vars on /atom, then /datum/component/chat_color_cache.
//
// Plain tmp vars on /atom again: an unset var costs an instance nothing (BYOND
// stores only vars that differ from the type default), and the cache is derived,
// so it is never saved. The global helpers stay as the one read/write API.
/atom
	var/tmp/chat_color_cached
	/// The name string the colors were computed for; reused as invalidation key.
	var/tmp/chat_color_cached_name
	var/tmp/chat_color_cached_darkened

/proc/dq_get_chat_color(atom/a)
	return a.chat_color_cached

/proc/dq_get_chat_color_name(atom/a)
	return a.chat_color_cached_name

/proc/dq_get_chat_color_darkened(atom/a)
	return a.chat_color_cached_darkened

/proc/dq_set_chat_color_cache(atom/a, color, color_name, darkened)
	a.chat_color_cached = color
	a.chat_color_cached_name = color_name
	a.chat_color_cached_darkened = darkened
