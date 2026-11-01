// The content half of code/base/helpers/_lists.dm: what names content, so the layer the engine calls cannot hold it.

//Mergsort: does the actual sorting and returns the results back to sortAtom
//Mergesort: Specifically for record datums in a list.
/proc/sortRecord(list/datum/data/record/L, field = "name", order = 1)
	if(isnull(L))
		return list()
	if(L.len < 2)
		return L
	var/middle = L.len / 2 + 1
	return mergeRecordLists(sortRecord(L.Copy(0, middle), field, order), sortRecord(L.Copy(middle), field, order), field, order)

//Mergsort: does the actual sorting and returns the results back to sortRecord
/proc/mergeRecordLists(list/datum/data/record/L, list/datum/data/record/R, field = "name", order = 1)
	var/Li=1
	var/Ri=1
	var/list/result = new()
	if(!isnull(L) && !isnull(R))
		while(Li <= L.len && Ri <= R.len)
			var/datum/data/record/rL = L[Li]
			if(isnull(rL))
				L -= rL
				continue
			var/datum/data/record/rR = R[Ri]
			if(isnull(rR))
				R -= rR
				continue
			if(sorttext(rL.fields[field], rR.fields[field]) == order)
				result += L[Li++]
			else
				result += R[Ri++]

		if(Li <= L.len)
			return (result + L.Copy(Li, 0))
	return (result + R.Copy(Ri, 0))

/obj/machinery/dd_SortValue()
	return "[sanitize_old(name)]"

/obj/machinery/camera/dd_SortValue()
	return "[c_tag]"

/datum/alarm/dd_SortValue()
	return "[sanitize_old(last_name)]"

//Returns a newline-separated list that counts equal-ish items, outputting count and item names, optionally with icons and specific determiners
/proc/counting_english_list(client/viewer, list/input, output_icons = TRUE, determiners = DET_NONE, nothing_text = "nothing", line_prefix = "\t", first_item_prefix = "\n", last_item_suffix = "\n", and_text = "\n", comma_text = "\n", final_comma_text = ",")
	var/list/counts = list() // counted input items
	var/list/items = list() // actual objects for later reference (for icons and formatting)

	// count items
	for(var/item in input)
		var/name = "[item]" // index items by name; usually works fairly well for loose equality
		if(name in counts)
			counts[name]++
		else
			counts[name] = 1
			items.Add(item)

	// assemble the output list
	var/list/out = list()
	var/i = 0
	for(var/item in items)
		var/name = "[item]"
		var/count = counts[name]
		var/item_str = line_prefix
		if(count > 1)
			item_str += "[count]x&nbsp;"

		if(isatom(item))
			// atoms/items/objects can be pretty and whatnot
			var/atom/A = item
			if(output_icons && isicon(A.icon) && !ismob(A)) // mobs tend to have unusable icons
				item_str += "[icon2html(A, viewer)]&nbsp;"
			switch(determiners)
				if(DET_NONE) item_str += A.name
				if(DET_DEFINITE) item_str += "\the [A]"
				if(DET_INDEFINITE) item_str += "\a [A]"
				else item_str += name
		else
			// non-atoms use plain string conversion
			item_str += name

		if(i == 0)
			item_str = first_item_prefix + item_str
		if(i == items.len - 1)
			item_str = item_str + last_item_suffix

		out.Add(item_str)
		i++

	// finally return the list using regular english_list builder
	return english_list(out, nothing_text, and_text, comma_text, final_comma_text)

//A "preset" for counting_english_list that displays the list "inline" (comma separated)
/proc/inline_counting_english_list(client/viewer, list/input, output_icons = TRUE, determiners = DET_NONE, nothing_text = "nothing", and_text = " and ", comma_text = ", ", final_comma_text = "", line_prefix = "", first_item_prefix = "", last_item_suffix = "")
	return counting_english_list(viewer, input, output_icons, determiners, nothing_text, and_text, comma_text, final_comma_text)

