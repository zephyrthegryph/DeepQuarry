/obj/machinery/gap_dispenser
	var/list/saved_recipes = list()
	var/amount = 5

CAPABILITIES(/obj/machinery/gap_dispenser)
	interface("GapDispenser")
	op("clear_recipes", ui_act("clear_recipes"), asks(/datum/prompt/choice, fields = list("question" = "Clear all recipes?", "title" = "Clear?", "choices" = list("No", "Yes"), "buttons" = TRUE, "timeout" = 0), step = "a1"), then(PROC_REF(ui_act_clear_recipes)))
	op("set_amount", ui_act("set_amount"), asks(/datum/prompt/number, fields = list("question" = computed(PROC_REF(ui_act_set_amount_a2_question)), "title" = computed(PROC_REF(ui_act_set_amount_a2_title)), "default" = nameof(amount), "min_value" = 1, "max_value" = MAX_AMOUNT, "timeout" = 0), step = "a2"), then(PROC_REF(ui_act_set_amount)))

/obj/machinery/gap_dispenser/proc/ui_act_clear_recipes(datum/act/op/A)
	var/_answer_a1 = A.step_answer("a1").answer_value
	if(_answer_a1 == "Yes")
		saved_recipes = list()
	. = TRUE

/obj/machinery/gap_dispenser/proc/ui_act_set_amount_a2_question(datum/act/op/A)
	return "Amount (max [MAX_AMOUNT])"

/obj/machinery/gap_dispenser/proc/ui_act_set_amount_a2_title(datum/act/op/A)
	return "[src]"

/obj/machinery/gap_dispenser/proc/ui_act_set_amount(datum/act/op/A)
	var/mob/user = A.actor
	var/N = A.step_answer("a2").answer_value
	if(!Adjacent(user))
		return
	amount = N
	return TRUE
