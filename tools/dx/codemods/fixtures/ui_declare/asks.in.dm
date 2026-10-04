/obj/machinery/gap_dispenser
	var/list/saved_recipes = list()
	var/amount = 5

DECLARE_UI(/obj/machinery/gap_dispenser, "GapDispenser")

UI_ACT(/obj/machinery/gap_dispenser, "clear_recipes", ui_act_clear_recipes)
UI_ACT_PROC(/obj/machinery/gap_dispenser, ui_act_clear_recipes)
	var/_answer_a1 = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/choice/alert, message = "Clear all recipes?", title = "Clear?", choices = list("No", "Yes"))
	if(isnull(_answer_a1))
		return
	if(_answer_a1 == "Yes")
		saved_recipes = list()
	. = TRUE

UI_ACT(/obj/machinery/gap_dispenser, "set_amount", ui_act_set_amount)
UI_ACT_PROC(/obj/machinery/gap_dispenser, ui_act_set_amount)
	var/N = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/number, message = "Amount (max [MAX_AMOUNT])", title = "[src]", default = amount, min = 1, max = MAX_AMOUNT)
	if(isnull(N) || !Adjacent(ui.user))
		return
	amount = N
	return TRUE
