// Per-atom chat-tag color cache, formerly the chat_color, chat_color_name,
// and chat_color_darkened vars on /atom.
//
// We store this in a component to keep memory sparse, but the helper procs
// are GLOBAL — adding instance methods to /atom would multiply against every
// /atom subtype's proc table, defeating the memory savings.
/datum/component/chat_color_cache
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/cached_color
	var/cached_name       // the name string the colors were computed for; reused as invalidation key
	var/cached_darkened

/proc/dq_get_chat_color(atom/a)
	var/datum/component/chat_color_cache/c = a.GetComponent(/datum/component/chat_color_cache)
	return c?.cached_color

/proc/dq_get_chat_color_name(atom/a)
	var/datum/component/chat_color_cache/c = a.GetComponent(/datum/component/chat_color_cache)
	return c?.cached_name

/proc/dq_get_chat_color_darkened(atom/a)
	var/datum/component/chat_color_cache/c = a.GetComponent(/datum/component/chat_color_cache)
	return c?.cached_darkened

/proc/dq_set_chat_color_cache(atom/a, color, color_name, darkened)
	var/datum/component/chat_color_cache/c = a.GetComponent(/datum/component/chat_color_cache)
	if(!c)
		c = a.AddComponent(/datum/component/chat_color_cache)
	c.cached_color = color
	c.cached_name = color_name
	c.cached_darkened = darkened
