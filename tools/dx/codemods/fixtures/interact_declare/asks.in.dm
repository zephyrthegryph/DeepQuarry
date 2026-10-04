/obj/item/gap_card
	var/list/possible_amounts = list(5, 10)

EXTEND_INTERACTIONS(/obj/item/gap_card, \
	INTERACT_USE(null, PROC_REF(label_effect)), \
	INTERACT_VERB("Change Look", PROC_REF(change_verb), REQ_IN_INVENTORY), \
	INTERACT_VERB("Set amount", PROC_REF(amount_verb)), \
)

/obj/item/gap_card/proc/label_effect(mob/user, obj/item/held, datum/interaction/interaction)
	var/t = rerun_ask(user, "label", PROC_REF(label_effect), args, /datum/om/prompt/text, message = "Enter a label.", title = "Label", max_length = MAX_NAME_LEN)
	if(isnull(t))
		return
	name = "card - [t]"
	return TRUE

/obj/item/gap_card/proc/change_verb(mob/user, obj/item/held, datum/interaction/interaction)
	var/picked = rerun_ask(user, "a1", PROC_REF(change_verb), list(user), /datum/om/prompt/choice, message = "Choose an appearance.", title = "[src]", choices = GLOB.gap_choices)
	if(isnull(picked) || get(src, /mob) != user)
		return
	disguise(GLOB.gap_choices[picked])

/obj/item/gap_card/proc/amount_verb(mob/user, obj/item/held, datum/interaction/interaction)
	var/N = rerun_ask(user, "a1", PROC_REF(amount_verb), args, /datum/om/prompt/choice, message = "Amount:", choices = possible_amounts)
	if(isnull(N))
		return
	if(N)
		amount = N
