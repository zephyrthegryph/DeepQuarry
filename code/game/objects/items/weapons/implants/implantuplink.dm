/obj/item/implant/uplink
	name = "uplink"
	desc = "Summon things."
	var/activation_emote = "chuckle"

/// It carries a hidden uplink from the start.
/obj/item/implant/uplink/ownership()
	. = ..()
	. += owns(nameof(hidden_uplink), policy = OWN_CONTAINED, starts = /obj/item/uplink/hidden)

/obj/item/implant/uplink/Initialize(mapload)
	activation_emote = pick("blink", "blink_r", "eyebrow", "chuckle", "twitch", "frown", "nod", "blush", "giggle", "grin", "groan", "shrug", "smile", "pale", "sniff", "whimper", "wink")
	//hidden_uplink.uses = 5
	//Code currently uses a mind var for telecrystals, balancing is currently an issue. Will investigate.
	. = ..()

/obj/item/implant/uplink/post_implant(mob/source, mob/user = null)
	var/choices = list("blink", "blink_r", "eyebrow", "chuckle", "twitch", "frown", "nod", "blush", "giggle", "grin", "groan", "shrug", "smile", "pale", "sniff", "whimper", "wink")
	activation_emote = pick(choices)
	announce_activation(source)
	if(user && !QDELETED(user))
		open_request(src, /datum/prompt/choice/implant_emote, PROC_REF(emote_chosen), answerer = user, choices = choices, source = source)

/obj/item/implant/uplink/proc/emote_chosen(datum/act/request/A)
	var/datum/prompt/choice/implant_emote/ask = A.request
	if(!A.answer || QDELETED(ask.answerer) || QDELETED(ask.source))
		return
	activation_emote = ask.value
	announce_activation(ask.source)

/obj/item/implant/uplink/proc/announce_activation(mob/source)
	source.mind?.store_memory("Uplink implant can be activated by using the [src.activation_emote] emote, <B>say *[src.activation_emote]</B> to attempt to activate.", 0, 0)
	to_chat(source, "The implanted uplink implant can be activated by using the [src.activation_emote] emote, <B>say *[src.activation_emote]</B> to attempt to activate.")

/obj/item/implant/uplink/trigger(emote, mob/source as mob, mob/actor)
	if(item_hidden_uplink(src) && actor == source) // Let's not have another people activate our uplink
		item_hidden_uplink(src).check_trigger(source, emote, activation_emote)
