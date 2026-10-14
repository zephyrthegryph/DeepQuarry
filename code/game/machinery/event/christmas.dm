/obj/structure/event/present
	name = "decorative present"
	desc = "A gift! What cou- oh, it's made of plastic.."
	icon = 'icons/obj/items_ch.dmi'
	icon_state = "gift1_g"

	var/chaos = "I can do anything!"
	anchored = 1.0
	density = 0

MSG_DEF_SELF(santa/present_unavailable, "only Santa can give presents (be nice or you might end up in Santa's sack)")

CAPABILITIES(/obj/structure/event/present)
	rolls(ROLL_PIXEL, PIXEL_JITTER(10))
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/event/present/proc/roll_icon_state(datum/roller/R)
	return "gift[R.choose(list("1", "2", "3"))]_[R.choose(list("g", "r", "b", "y", "p"))]"

/obj/structure/event/santa_sack

	name = "Santa's sack"
	desc = "A huge velvet sack full of presents! Only those who has been nice gets one from Santa!"
	icon = 'icons/obj/storage_ch.dmi'
	icon_state = "santasack"

	var/santa_ckey = null //The ckey set for the person acting as Santa, will be the only one able to anchor/unachor as well as retrieve presents.
	var/list/nice_list_log //The log that will contain all characters and their ckeys that the santa has given a gift to.
	var/list/ckey_log //The log that ensures nobody is naughty and tries to trick Santa into giving them twice!
	anchored = 1.0
	density = 1

/// Old verb "Bind/unbind sack".
/obj/structure/event/santa_sack/proc/santa_sack_setanchor(datum/act/op/A)
	var/mob/user = A.actor
	if(user.incapacitated())
		return
	if(user.ckey == santa_ckey)
		if(anchored == 0)
			set_anchored(1)
			to_chat(user,span_notice("You bind the sack, none can make off with it now!"))
		else
			set_anchored(0)
			to_chat(user,span_notice("You unbind the sack, you can now drag it off. But so can anyone else!"))
	else
		to_chat(user, span_warning("Only Santa can bind and unbind his sack!"))
	return



CAPABILITIES(/obj/structure/event/santa_sack)
	op("give_present", hand(), priority(OP_PRIORITY_DEFAULT - 1), needs(req(PROC_REF(santa_present_allowed))), asks(/datum/prompt/choice, fields = list("title" = "Give Present", "question" = "Choose who to give a present to.", "choices" = computed(PROC_REF(santa_present_receivers)), "timeout" = 0)), then(PROC_REF(present_receiver_chosen)))
	op("bind_sack", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Bind/unbind sack"), needs(req_adjacent(), req_capable()), then(PROC_REF(santa_sack_setanchor)))

/// Requirement: only Santa hands out presents.
/obj/structure/event/santa_sack/proc/can_give_present(mob/user, atom/target, obj/item/held)
	if(user.ckey != santa_ckey)
		return "only Santa can give presents (be nice or you might end up in Santa's sack)"
	return TRUE

/// Old attack_hand.
/obj/structure/event/santa_sack/proc/present_receiver_chosen(datum/act/op/A)
	if(!A.answer)
		return
	var/mob/user = A.actor
	var/mob/living/T = A.answer.value
	if(!T?.ckey)
		return

	if(LAZYACCESS(ckey_log, T.ckey))
		to_chat(user, span_warning("This one already got a present!"))
		return

	new /obj/item/a_gift/advanced(src.loc)
	for(var/mob/O in view(src, null))
		O.show_message(span_warning("Santa pulls out a present for [T.name]! \"Merry Christmas!"),1)

	var/santa_log = "[T.ckey] playing as [T.name] got a present!"
	LAZYSET(nice_list_log, ++length(nice_list_log), santa_log)
	LAZYSET(ckey_log, T.ckey, TRUE)
	//Currently doesnt have an ingame way to show. Can only be viewed through View-Variables, to ensure theres no chance of players ckeys exposed - Jack

/obj/structure/event/santa_sack/proc/santa_present_allowed(datum/act/op/A)
	// Recheck the answering actor identity while retaining the tracked sack owner.
	return (read_once(A.actor?.ckey) == santa_ckey) ? null : MSG(santa/present_unavailable)

/obj/structure/event/santa_sack/proc/santa_present_receivers(datum/act/op/A)
	return mobs_in_view(1, A.actor)
