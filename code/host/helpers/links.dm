/proc/topic_link(datum/D, arglist, content)
	if(istype(arglist,/list))
		arglist = list2params(arglist)
	return "<a href='byond://?src=[REF(D)];[arglist]'>[content]</a>"

// \ref behaviour got changed in 512 so this is necesary to replicate old behaviour.
// If it ever becomes necesary to get a more performant REF(), this lies here in wait
// #define REF(thing) (thing && istype(thing, /datum) && (thing:datum_flags & DF_USE_TAG) && thing:tag ? "[thing:tag]" : "\ref[thing]")
// Painlessly creates an <a href=...> element.
// First argument is where to send the Topic call to when clicked. Should be a reference to an object. This is generally src, but not always.
// Second one is for all the params that will be sent. Uses an assoc list (e.g. "value" = "5").
// Note that object refs will be converted to text, as if \ref[thing] was done. To get the ref back on Topic() side, you will need to use locate().
// Third one is the text that will be clickable.
/proc/href(href_src, list/href_params, href_text)
	return "<a href='byond://?src=[REF(href_src)];[list2params(href_params)]'>[href_text]</a>"
