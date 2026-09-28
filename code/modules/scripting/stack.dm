/datum/stack
	var/list/items=new
/datum/stack/proc/Push(value)
	items+=value

/datum/stack/proc/Pop()
	if(!items.len) return null
	. = items[items.len]
	items.len--

/datum/stack/proc/Top() //returns the item on the top of the stack without removing it
	if(!items.len) return null
	return items[items.len]

/datum/stack/proc/Copy()
	var/datum/stack/S=new()
	S.items=src.items.Copy()
	return S

/datum/stack/proc/Clear()
	items.Cut()
