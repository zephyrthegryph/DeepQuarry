/obj/machinery/a/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "A")
		ui.open()

/obj/machinery/b/proc/tgui_interact(mob/user)
	return

/datum/proc/tgui_interact(mob/user)
	return

/obj/c/proc/helper(mob/user)
	var/datum/tgui/W = new(user, src, "C")
	new /datum/tgui(user, src, "E")
	// ui = new(user, src, "F") in a comment is ignored
	to_chat(user, "ui = new(user) in a string is blanked")
	SStgui.try_update_ui(user, src)

/obj/d/tgui_data(mob/user)
	return list()

/obj/e/proc/tgui_data(mob/user)
	return list()

/datum/proc/tgui_data(mob/user)
	return list()

/obj/f/tgui_state(mob/user)
	return GLOB.default_state

/obj/g/proc/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/obj/h/tgui_state(mob/user)
	if(x)
		return GLOB.a
	return GLOB.b

/obj/i/tgui_state(mob/user)
	// only a comment, then the constant
	return GLOB.x

/obj/j/tgui_state(mob/user)
	return user.state

/datum/proc/tgui_state(mob/user)
	return GLOB.default_state

/obj/k/tgui_act(action, list/params)
	. = ..()
	var/x = params["a"]
	var/y = text2num(params["b"])
	return TRUE

/obj/k2/proc/tgui_act(action, list/params)
	return ..(action, params)

/datum/tgui_act(action, list/params)
	var/z = params["not an override"]

/datum/proc/tgui_act(action, list/params)
	var/z = params["not an override either"]

/obj/raw/proc/parse(list/params)
	var/a = text2num(params["n"])
	var/b = locate(params["ref"])
	var/c = text2path(params ?["p"])
	var/d = json_decode(params["j"])
	var/e = params2list(params["q"])
	var/f = locate_in_list(list, params["k"])
	var/g = locate_within(src, params["k"])
	var/h = round(text2num(params["n"]))
	var/i = text2num(params["x"]) // text2num(params["commented"])
	var/j = ok(params["fine"])

UI_ACT(/obj/machinery/m, "act1", on_act1, UI_ARG_NUM("amount", 0, 10), UI_ARG_TEXT("label"))
UI_ACT(/obj/machinery/m, "act2", on_act2)
UI_ACT(/obj/machinery/m, "ctl", "extra", on_act4, UI_ARG_TEXT("t"))
UI_SUBACT(/obj/machinery/m, "sub", ref, on_sub, UI_ARG_TEXT("deep"))
UI_ACT_PROC(/obj/machinery/m, on_act1)
	var/n = params["amount"]
	var/l = params["label"]
	var/z = params["other"]
	var/q = params[some_var]
	var/w = params["amount"]
	var/num = text2num(w)
	var/loc_val = locate(w)
	helper_unknown(params)
	act_ask(params)
	rerun_ask(list(params))
	var/v = params ? ["amount"]
	var/ok = text2num(params["amount"])
	return TRUE

UI_ACT_PROC(/obj/machinery/m, on_act2)
	var/a = params["amount"]
	typed_ok(params)
	typed_bad(params)
	return TRUE

UI_ACT_OVERRIDE(/obj/machinery/m, on_act4)
	var/a = params["t"]
	var/b = params["u"] // params["commented"]
	call_other(src, params, 3)

UI_ACT_PREF_PROC(/obj/machinery/m, on_sub)
	var/a = params["deep"]

UI_ACT_PROC(/obj/machinery/sub/child, on_act2)
	var/a = params["label"]

UI_ACT_PROC(/obj/machinery/m, on_unrow)
	var/a = params["whatever"]

/obj/machinery/m/proc/typed_ok(list/params)
	var/a = params["amount"]
	return other_typed(params)

/obj/machinery/m/proc/other_typed(list/params)
	return params["label"]

/obj/machinery/m/proc/typed_bad(list/params)
	var/a = params[idx]
	return a

/obj/machinery/m/proc/typed_bad(list/params, extra)
	return params["amount"]

/obj/machinery/m/proc/needs_missing(list/params)
	return nonexistent_helper(params)

#define MODAL_ROWS(x) UI_ACT(x, "mrow", TYPE_PROC_REF(/datum, modal_handler), UI_ARG_TEXT("mk"))
#define MODAL_FWD(x) TYPE_PROC_REF(/datum, modal_two), UI_ARG_NUM("m2", 1, 2) ) TYPE_PROC_REF(/datum, modal_three)

UI_ACT_PROC(/obj/modal_host, modal_handler)
	var/a = params["mk"]
	var/b = params["zz"]

UI_ACT_PROC(/obj/modal_host, modal_two)
	var/a = params["m2"]
