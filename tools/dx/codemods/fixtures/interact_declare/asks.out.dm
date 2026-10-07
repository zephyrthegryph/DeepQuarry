/obj/item/gap_card
	var/list/possible_amounts = list(5, 10)

CAPABILITIES(/obj/item/gap_card)
	op("label_effect", in_hand(), label("Label effect"), asks(/datum/prompt/text, fields = list("question" = "Enter a label.", "title" = "Label", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "label"), then(PROC_REF(label_effect)))
	op("change_verb", menu(), label("Change Look"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = computed(PROC_REF(change_verb_a1_title)), "choices" = computed(PROC_REF(change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(change_verb)))
	op("amount_verb", menu(), label("Set amount"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/choice, fields = list("question" = "Amount:", "choices" = nameof(possible_amounts), "timeout" = 0), step = "a1"), then(PROC_REF(amount_verb)))

/obj/item/gap_card/proc/label_effect(datum/act/op/A)
	var/t = A.step_value("label")
	name = "card - [t]"
	return TRUE

/obj/item/gap_card/proc/change_verb_a1_title(datum/act/op/A)
	return "[src]"

/obj/item/gap_card/proc/change_verb_a1_choices(datum/act/op/A)
	return GLOB.gap_choices

/obj/item/gap_card/proc/change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	disguise(GLOB.gap_choices[picked])

/obj/item/gap_card/proc/amount_verb(datum/act/op/A)
	var/N = A.step_value("a1")
	if(N)
		amount = N
