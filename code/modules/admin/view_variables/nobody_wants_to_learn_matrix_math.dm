
/**
 * ## nobody wants to learn matrix math!
 *
 * More than just a completely true statement, this datum is created as a tgui interface
 * allowing you to modify each vector until you know what you're doing.
 * Much like filteriffic, 'nobody wants to learn matrix math' is meant for developers like you and I
 * to implement interesting matrix transformations without the hassle if needing to know... algebra? Damn, i'm stupid.
 */
/datum/nobody_wants_to_learn_matrix_math
	var/tmp/target_handle
	var/matrix/testing_matrix

/datum/nobody_wants_to_learn_matrix_math/New(atom/target)
	src.target_handle = om_handle(target)
	testing_matrix = matrix(target.transform)

DECLARE_REF(/datum/nobody_wants_to_learn_matrix_math, "testing_matrix", OWNED, null)

DECLARE_UI_STATE(/datum/nobody_wants_to_learn_matrix_math, ADMIN_STATE(R_VAREDIT))

/datum/nobody_wants_to_learn_matrix_math/tgui_close(mob/user)
	qdel(src)

DECLARE_UI(/datum/nobody_wants_to_learn_matrix_math, "MatrixMathTester")

UI_DATA_REPLACE(/datum/nobody_wants_to_learn_matrix_math, "merge:ui_data_datum_nobody_wants_to_learn_matrix_math{matrix_a:unknown,matrix_b:unknown,matrix_c:unknown,matrix_d:unknown,matrix_e:unknown,matrix_f:unknown,pixelated:num}")

/// The computed part of /datum/nobody_wants_to_learn_matrix_math's window data (declared on its UI_DATA row).
/datum/nobody_wants_to_learn_matrix_math/proc/ui_data_datum_nobody_wants_to_learn_matrix_math(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["matrix_a"] = testing_matrix.a
	data["matrix_b"] = testing_matrix.b
	data["matrix_c"] = testing_matrix.c
	data["matrix_d"] = testing_matrix.d
	data["matrix_e"] = testing_matrix.e
	data["matrix_f"] = testing_matrix.f
	data["pixelated"] = target().appearance_flags & PIXEL_SCALE
	return data

UI_ACT(/datum/nobody_wants_to_learn_matrix_math, "change_var", ui_act_change_var, UI_ARG_TEXT("var_name"), UI_ARG_NUM("var_value"))
UI_ACT_PROC(/datum/nobody_wants_to_learn_matrix_math, ui_act_change_var)
	var/matrix_var_name = params["var_name"]
	var/matrix_var_value = params["var_value"]
	if(testing_matrix.vv_edit_var(matrix_var_name, matrix_var_value) == FALSE)
		to_chat(src, "Your edit was rejected by the object. This is a bug with the matrix tester, not your fault, so report it on GitHub.", confidential = TRUE)
		return
	set_transform()

UI_ACT(/datum/nobody_wants_to_learn_matrix_math, "scale", ui_act_scale, UI_ARG_NUM("x"), UI_ARG_NUM("y"))
UI_ACT_PROC(/datum/nobody_wants_to_learn_matrix_math, ui_act_scale)
	testing_matrix.Scale(params["x"], params["y"])
	set_transform()

UI_ACT(/datum/nobody_wants_to_learn_matrix_math, "translate", ui_act_translate, UI_ARG_NUM("x"), UI_ARG_NUM("y"))
UI_ACT_PROC(/datum/nobody_wants_to_learn_matrix_math, ui_act_translate)
	testing_matrix.Translate(params["x"], params["y"])
	set_transform()

UI_ACT(/datum/nobody_wants_to_learn_matrix_math, "shear", ui_act_shear, UI_ARG_NUM("x"), UI_ARG_NUM("y"))
UI_ACT_PROC(/datum/nobody_wants_to_learn_matrix_math, ui_act_shear)
	testing_matrix.Shear(params["x"], params["y"])
	set_transform()

UI_ACT(/datum/nobody_wants_to_learn_matrix_math, "turn", ui_act_turn, UI_ARG_NUM("angle"))
UI_ACT_PROC(/datum/nobody_wants_to_learn_matrix_math, ui_act_turn)
	testing_matrix.Turn(params["angle"])
	set_transform()

UI_ACT(/datum/nobody_wants_to_learn_matrix_math, "toggle_pixel", ui_act_toggle_pixel)
UI_ACT_PROC(/datum/nobody_wants_to_learn_matrix_math, ui_act_toggle_pixel)
	target().appearance_flags ^= PIXEL_SCALE

/datum/nobody_wants_to_learn_matrix_math/proc/set_transform()
	animate(target(), transform = testing_matrix, time = 0.5 SECONDS)
	testing_matrix = matrix(target().transform)

/client/proc/open_matrix_tester(atom/in_atom)
	if(holder)
		var/datum/nobody_wants_to_learn_matrix_math/matrix_tester = new(in_atom)
		matrix_tester.tgui_interact(mob)

/// LC-refs: the target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/nobody_wants_to_learn_matrix_math/proc/target() as /atom
	return om_resolve(target_handle)
