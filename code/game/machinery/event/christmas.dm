/obj/structure/event/present
	name = "decorative present"
	desc = "A gift! What cou- oh, it's made of plastic.."
	icon = 'icons/obj/items_ch.dmi'
	icon_state = "gift1_g"

	var/chaos = "I can do anything!"
	anchored = 1.0
	density = 0

/obj/structure/event/present/Initialize(mapload)
	. = ..()
	pixel_x = rand(-10,10)
	pixel_y = rand(-10,10)
	icon_state = "gift[pick("1", "2", "3")]_[pick("g", "r", "b", "y", "p")]"

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
/obj/structure/event/santa_sack/proc/santa_sack_setanchor(mob/user, obj/item/held, datum/interaction/interaction)
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

DECLARE_INTERACTIONS(/obj/structure/event/santa_sack, \
	INTERACT_HAND(null, PROC_REF(interaction_hand), REQ_TARGET_STATE(/obj/structure/event/santa_sack/proc/can_give_present)), \
	INTERACT_VERB("Bind/unbind sack", PROC_REF(santa_sack_setanchor)), \
)

/// Requirement: only Santa hands out presents.
/obj/structure/event/santa_sack/proc/can_give_present(mob/user, atom/target, obj/item/held)
	if(user.ckey != santa_ckey)
		return "only Santa can give presents (be nice or you might end up in Santa's sack)"
	return TRUE

/// Old attack_hand.
/obj/structure/event/santa_sack/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/receivers = list()
	for(var/mob/living/R in oview(user.loc,1))
		receivers += R

	open_request(src, /datum/prompt/choice, PROC_REF(present_receiver_chosen), answerer = user, question = "Choose who to give a present to.", title = "Give Present", choices = mobs_in_view(1, user), ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/structure/event/santa_sack/proc/present_receiver_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/mob/living/T = A.answer.value
	if(!T.ckey)
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
