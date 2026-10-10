
/// The silk the weaver can spend; the weave buttons read it, so it is written through its setter.
/datum/trait_state/weaver/var/silk_reserve = 100
TRACKED(/datum/trait_state/weaver, silk_reserve)

/datum/trait_state/weaver
	var/silk_max_reserve = 500
	var/silk_color = "#FFFFFF"
	var/silk_production = FALSE
	var/silk_generation_amount = 2
	var/nutrtion_per_silk = 0.2

/datum/trait_state/weaver/setup()
	if (!isliving(owner))
		return FALSE

	grant(owner, granted_verb(/mob/living/proc/weaver_control_panel), src)
	if(ishuman(owner))
		grant(owner, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), src)
	return TRUE

	//Processing
/datum/trait_state/weaver/life_tick()
	if (QDELETED(owner))
		return
	process_weaver_silk()

/// The owner loses the weaver verbs.
/datum/trait_state/weaver/detach()
	revoke(owner, granted_verb(/mob/living/proc/weaver_control_panel), src)
	if(ishuman(owner))
		revoke(owner, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), src)
	..()

/datum/trait_state/weaver/proc/process_weaver_silk()
	if(silk_reserve < silk_max_reserve && silk_production == TRUE && owner.nutrition > 100)
		set_silk_reserve(min(silk_reserve + silk_generation_amount, silk_max_reserve))
		owner.adjust_nutrition(-(nutrtion_per_silk*silk_generation_amount))

/datum/trait_state/weaver/proc/silk_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/ask = A.answer
	if(ask.value)
		silk_color = ask.value
	SStgui.update_uis(src)

//TGUI Weaver Panel
CAPABILITIES(/datum/trait_state/weaver)
	interface("WeaverConfig", title = "Weaver Config")
	op("new_silk_color", ui_act("new_silk_color"), then(PROC_REF(ui_act_new_silk_color)))
	op("toggle_silk_production", ui_act("toggle_silk_production"), then(PROC_REF(ui_act_toggle_silk_production)))
	op("check_silk_amount", ui_act("check_silk_amount"), then(PROC_REF(ui_act_check_silk_amount)))
	op("weave_binding", ui_act("weave_binding"), needs(req(PROC_REF(weave_silk_binding)), req_conscious(), req(PROC_REF(weave_site_free))), wait(PROC_REF(weave_time)), then(PROC_REF(weave_done)))
	op("weave_floor", ui_act("weave_floor"), needs(req(PROC_REF(weave_silk_floor)), req_conscious(), req(PROC_REF(weave_site_free))), wait(PROC_REF(weave_time)), then(PROC_REF(weave_done)))
	op("weave_wall", ui_act("weave_wall"), needs(req(PROC_REF(weave_silk_wall)), req_conscious(), req(PROC_REF(weave_site_free))), wait(PROC_REF(weave_time)), then(PROC_REF(weave_done)))
	op("weave_nest", ui_act("weave_nest"), needs(req(PROC_REF(weave_silk_nest)), req_conscious(), req(PROC_REF(weave_site_free))), wait(PROC_REF(weave_time)), then(PROC_REF(weave_done)))
	op("weave_trap", ui_act("weave_trap"), needs(req(PROC_REF(weave_silk_trap)), req_conscious(), req(PROC_REF(weave_site_free))), wait(PROC_REF(weave_time)), then(PROC_REF(weave_done)))

/mob/living/proc/weaver_control_panel()
	set name = "Weaver Control Panel"
	set desc = "Allows you to adjust the settings of various weaver settings!"
	set category = VERB_CAT_ABILITIES_WEAVER

	var/datum/trait_state/weaver/weave = get_weaver_state()
	if(!weave)
		to_chat(src, span_warning("Only a weaver can use that!"))
		return FALSE

	weave.tgui_interact(src)

/mob/living/proc/get_weaver_state()
	RETURN_TYPE(/datum/trait_state/weaver)
	return get_trait_state(/datum/trait_state/weaver)

/// /datum/trait_state/weaver's window data.
/datum/trait_state/weaver/ui_data(datum/act/eval/A)
	var/data = list(
		"silk_reserve" = silk_reserve,
		"silk_max_reserve" = silk_max_reserve,
		"silk_color" = silk_color,
		"silk_production" = silk_production,
		"savefile_selected" = correct_savefile_selected()
	)

	return data

/datum/trait_state/weaver/tgui_close(mob/user)
	SScharacter_setup.queue_preferences_save(user?.client?.prefs)
	. = ..()

/datum/trait_state/weaver/proc/correct_savefile_selected()
	if(owner.client.prefs.default_slot == owner.mind.loaded_from_slot)
		return TRUE
	return FALSE

/datum/trait_state/weaver/proc/ui_act_new_silk_color(datum/act/op/A)
	var/mob/user = A.actor
	open_request(src, /datum/prompt/color, PROC_REF(silk_color_picked), answerer = user, question = "Select a color you wish your silk to be!", default = silk_color, title = "Color Selector", timeout = 0)
	return FALSE

/datum/trait_state/weaver/proc/ui_act_toggle_silk_production(datum/act/op/A)
	silk_production = !(silk_production)
	to_chat(owner, span_info("You are [silk_production ? "now" : "no longer"] producing silk."))
	return FALSE

/datum/trait_state/weaver/proc/ui_act_check_silk_amount(datum/act/op/A)
	to_chat(owner, span_info("Your silk reserves are at [silk_reserve]/[silk_max_reserve]."))
	return FALSE

/// What each weave button costs in silk and makes, by op key.
TYPE_TABLE_DECLARE(/datum/trait_state/weaver, recipes, list(
	"weave_binding" = list(50, /obj/item/clothing/suit/weaversilk_bindings),
	"weave_floor" = list(25, /obj/effect/weaversilk/floor),
	"weave_wall" = list(100, /obj/effect/weaversilk/wall),
	"weave_nest" = list(100, /obj/structure/bed/double/weaversilk_nest),
	"weave_trap" = list(250, /obj/effect/weaversilk/trap)))

/// The silk cost of the button pressed.
/datum/trait_state/weaver/proc/weave_cost(datum/act/op/A)
	var/list/recipe = TYPE_TABLE_GET(src, recipes)[A.oplan.key]
	return recipe[1]

/// The thing the button pressed makes.
/datum/trait_state/weaver/proc/weave_product(datum/act/op/A)
	var/list/recipe = TYPE_TABLE_GET(src, recipes)[A.oplan.key]
	return recipe[2]

/// Enough silk for a weave of `cost`; one requirement proc per button so each reads a constant cost.
/datum/trait_state/weaver/proc/weave_silk_for(cost)
	return cost <= silk_reserve ? null : /datum/msg/weaver/no_silk

/datum/trait_state/weaver/proc/weave_silk_binding(datum/act/op/A)
	return weave_silk_for(50)

/datum/trait_state/weaver/proc/weave_silk_floor(datum/act/op/A)
	return weave_silk_for(25)

/datum/trait_state/weaver/proc/weave_silk_wall(datum/act/op/A)
	return weave_silk_for(100)

/datum/trait_state/weaver/proc/weave_silk_nest(datum/act/op/A)
	return weave_silk_for(100)

/datum/trait_state/weaver/proc/weave_silk_trap(datum/act/op/A)
	return weave_silk_for(250)

/// The weaver stands on a turf with none of the product on it (where they stand is fixed while a weave is open: moving ends it).
/datum/trait_state/weaver/proc/weave_site_free(datum/act/op/A)
	return read_once(weave_site_text(A))

/datum/trait_state/weaver/proc/weave_site_text(datum/act/op/A)
	var/mob/M = A.actor
	if(!isturf(M?.loc))
		return /datum/msg/weaver/no_room
	if(locate_within(M.loc, weave_product(A)))
		return /datum/msg/weaver/already_there
	return null

MSG_DEF_SELF(weaver/no_silk, span_warning("You don't have enough silk to weave that!"))
MSG_DEF_SELF(weaver/no_room, span_warning("You can't weave here!"))
MSG_DEF_SELF(weaver/already_there, span_warning("You can't create another one in the same tile here!"))

/// A weave takes one second per 25 silk it costs.
/datum/trait_state/weaver/proc/weave_time(datum/act/op/A)
	return (weave_cost(A) / 25) SECONDS

/datum/trait_state/weaver/proc/weave_done(datum/act/op/A)
	set_silk_reserve(max(silk_reserve - weave_cost(A), 0))
	var/product = weave_product(A)
	var/atom/object = new product(owner.loc)
	object.color = silk_color

/// Trait system: silk production.
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/weaver/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_weaver"))
