/// Tier of `quality` on `I`: its value in an associative tool_qualities list, else 1.
/proc/dq_tool_tier(obj/item/I, quality)
	if(!I.has_tool_quality(quality))
		return 0
	var/tier = I.tool_qualities[quality]
	return isnum(tier) ? tier : 1
