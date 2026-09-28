/obj/var/datum/talking_atom/talking_atom

/datum/talking_atom
	var/list/heard_words = list()
	var/last_talk_time = 0
	var/tmp/holder_atom_handle
	var/talk_interval = 50
	var/talk_chance = 10

/datum/talking_atom/New(atom/holder)
	holder_atom_handle = om_handle(holder)
	init()

/datum/talking_atom/proc/init()
	if(holder_atom())
		PERIODIC_START(src, PERIODIC_SLOW)

/datum/talking_atom/periodic_step()
	if(!holder_atom())
		PERIODIC_STOP(src)

	else if(heard_words.len >= 1 && world.time > last_talk_time + talk_interval && prob(talk_chance))
		SaySomething()

/datum/talking_atom/proc/catchMessage(msg, mob/source)
	if(!holder_atom())
		return

	var/list/seperate = list()
	if(findtext(msg,"(("))
		return
	else if(findtext(msg,"))"))
		return
	else if(findtext(msg," ")==0)
		return
	else
		/*var/l = length(msg)
		if(findtext(msg," ",l,l+1)==0)
			msg+=" "*/
		seperate = splittext(msg, " ")

	for(var/Xa = 1,Xa<seperate.len,Xa++)
		var/next = Xa + 1
		if(heard_words.len > 20 + rand(10,20))
			heard_words.Remove(heard_words[1])
		if(!heard_words["[lowertext(seperate[Xa])]"])
			heard_words["[lowertext(seperate[Xa])]"] = list()
		var/list/w = heard_words["[lowertext(seperate[Xa])]"]
		if(w)
			w.Add("[lowertext(seperate[next])]")
		//to_world("Adding [lowertext(seperate[next])] to [lowertext(seperate[Xa])]")

	if(prob(30))
		var/list/options = list("[holder_atom()] seems to be listening intently to [source]...",\
			"[holder_atom()] seems to be focusing on [source]...",\
			"[holder_atom()] seems to turn it's attention to [source]...")
		holder_atom().loc.visible_message(span_blue("[icon2html(holder_atom(),viewers(holder_atom().loc))] [pick(options)]"))

	if(prob(20))
		om_after(src, 2, PROC_REF(SaySomething), pick(seperate))

/datum/talking_atom/proc/SaySomething(word = null)
	if(!holder_atom())
		return

	var/msg
	var/limit = rand(max(5,heard_words.len/2))+3
	var/text
	if(!word)
		text = "[pick(heard_words)]"
	else
		text = pick(splittext(word, " "))
	if(length(text)==1)
		text=uppertext(text)
	else
		var/cap = copytext(text,1,2)
		cap = uppertext(cap)
		cap += copytext(text,2,length(text)+1)
		text=cap
	var/q = 0
	msg+=text
	if(msg=="What" | msg == "Who" | msg == "How" | msg == "Why" | msg == "Are")
		q=1

	text=lowertext(text)
	for(var/ya,ya <= limit,ya++)

		if(heard_words.Find("[text]"))
			var/list/w = heard_words["[text]"]
			text=pick(w)
		else
			text = "[pick(heard_words)]"
		msg+=" [text]"
	if(q)
		msg+="?"
	else
		if(rand(0,10))
			msg+="."
		else
			msg+="!"

	var/list/listening = viewers(holder_atom())

	for(var/mob/M in listening)
		to_chat(M, "[icon2html(holder_atom(),M.client)] " + span_bold("[holder_atom()] reverberates") +" , \"[span_blue(msg)]\"")
	last_talk_time = world.time

REF_OWNED(/obj, "talking_atom")

/// LC-refs: the holder_atom this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/talking_atom/proc/holder_atom() as /atom
	return om_resolve(holder_atom_handle)
