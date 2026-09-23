/// Used to check for a specific tool quality on an item.
/// Returns TRUE or FALSE depending on whether `tool_quality` is found.
/obj/item/proc/has_tool_quality(tool_quality)
	return !!LAZYFIND(tool_qualities, tool_quality)
