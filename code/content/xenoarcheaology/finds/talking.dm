/datum/talking_atom
	var/list/heard_words = list() // ALLOW(instance_list): d: speech memory of a talking item, filled as it hears
	COOLDOWN_DECLARE(talk_cooldown)
	var/talk_interval = 50
	var/talk_chance = 10
	/// Has it a holder to talk through? The talk every() below runs while it does.
	var/talking = FALSE


CAPABILITIES(/datum/talking_atom)
	every(2 SECONDS, then(PROC_REF(talk_step)), when = nameof(talking))

/// Speech state of a talking find: linked to the object that carries it by LK_TALKING_ATOM, gone with it.
/datum/talking_atom/New(obj/holder)
	link_make(holder, LK_TALKING_ATOM, src)
	init()

/datum/talking_atom/proc/init()
	if(holder_atom())
		set_talking(TRUE)

/datum/talking_atom/proc/talk_step(datum/act/A)
	if(!holder_atom())
		set_talking(FALSE)

	else if(heard_words.len >= 1 && COOLDOWN_FINISHED(src, talk_cooldown) && prob(talk_chance))
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

	if(prob(30))
		var/list/options = list("[holder_atom()] seems to be listening intently to [source]...",\
			"[holder_atom()] seems to be focusing on [source]...",\
			"[holder_atom()] seems to turn it's attention to [source]...")
		holder_atom().loc.visible_message(span_blue("[icon2html(holder_atom(),viewers(holder_atom().loc))] [pick(options)]"))

	if(prob(20))
		after(src, 0.2 SECONDS, PROC_REF(SaySomething), with = list(pick(seperate)))

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
	COOLDOWN_START(src, talk_cooldown, talk_interval)

/// The object this speech state belongs to (the other end of its LK_TALKING_ATOM link), null once it is gone.
/datum/talking_atom/proc/holder_atom() as /atom
	return link_get(src, LK_TALKING_ATOM_OF)

/// The object's speech state (LK_TALKING_ATOM), or null when it does not talk.
/obj/proc/talking_atom() as /datum/talking_atom
	return link_get(src, LK_TALKING_ATOM)
