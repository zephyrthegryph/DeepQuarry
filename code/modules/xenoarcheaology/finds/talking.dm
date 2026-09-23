/obj/var/datum/talking_atom/talking_atom

/datum/talking_atom
	var/list/heard_words = list()
	var/last_talk_time = 0
	var/atom/holder_atom
	var/talk_interval = 50
	var/talk_chance = 10
	/// REACT_AT token of the next spontaneous talk (null: none).
	var/tmp/talk_timer

/datum/talking_atom/New(atom/holder)
	holder_atom = holder
	init()

/datum/talking_atom/proc/init()
	schedule_talk()

/// The old poll tried every 2 s (SSobj) with talk_chance% once talk_interval had passed since the
/// last talk. That is a geometric number of tries: draw it once and set one REACT_AT.
#define TALK_TRY_PERIOD (2 SECONDS)

/datum/talking_atom/proc/schedule_talk()
	if(!holder_atom || !length(heard_words))
		talk_timer = REACT_REARM(src, talk_timer, null)
		return
	var/tries = 1
	if(talk_chance < 100)
		tries = max(1, CEILING(log(max(rand(), 0.0001)) / log(1 - max(talk_chance, 1) / 100), 1))
	var/start = max(world.time, last_talk_time + talk_interval)
	talk_timer = REACT_REARM(src, talk_timer, start + tries * TALK_TRY_PERIOD)

#undef TALK_TRY_PERIOD

/datum/talking_atom/on_react(reason, source, source_kind)
	talk_timer = null
	if(!holder_atom || !length(heard_words))
		return
	SaySomething() // sets last_talk_time and schedules the next talk

/datum/talking_atom/proc/catchMessage(msg, mob/source)
	if(!holder_atom)
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

	if(isnull(talk_timer))
		schedule_talk()

	if(prob(30))
		var/list/options = list("[holder_atom] seems to be listening intently to [source]...",\
			"[holder_atom] seems to be focusing on [source]...",\
			"[holder_atom] seems to turn it's attention to [source]...")
		holder_atom.loc.visible_message(span_blue("[icon2html(holder_atom,viewers(holder_atom.loc))] [pick(options)]"))

	if(prob(20))
		spawn(2)
			SaySomething(pick(seperate))

/datum/talking_atom/proc/SaySomething(word = null)
	if(!holder_atom)
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

	var/list/listening = viewers(holder_atom)

	for(var/mob/M in listening)
		to_chat(M, "[icon2html(holder_atom,M.client)] " + span_bold("[holder_atom] reverberates") +" , \"[span_blue(msg)]\"")
	last_talk_time = world.time
	schedule_talk()
