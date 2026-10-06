
/**
 * ## nobody wants to learn matrix math!
 *
 * More than just a completely true statement, this datum is created as a tgui interface
 * allowing you to modify each vector until you know what you're doing.
 * Much like filteriffic, 'nobody wants to learn matrix math' is meant for developers like you and I
 * to implement interesting matrix transformations without the hassle if needing to know... algebra? Damn, i'm stupid.
 */
/datum/nobody_wants_to_learn_matrix_math
	var/tmp/atom/target
	var/matrix/testing_matrix

/datum/nobody_wants_to_learn_matrix_math/New(atom/target)
	rel_set(src, nameof(target), target)
	testing_matrix = matrix(target.transform)


/datum/nobody_wants_to_learn_matrix_math/tgui_close(mob/user)
	spent(src, user)

CAPABILITIES(/datum/nobody_wants_to_learn_matrix_math)
	interface("MatrixMathTester", rights = R_VAREDIT)
	op("change_var", ui_act("change_var", arg("var_name", schema_text(4096)), arg("var_value", num())), then(PROC_REF(ui_act_change_var)))
	op("scale", ui_act("scale", arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_scale)))
	op("translate", ui_act("translate", arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_translate)))
	op("shear", ui_act("shear", arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_shear)))
	op("turn", ui_act("turn", arg("angle", num())), then(PROC_REF(ui_act_turn)))
	op("toggle_pixel", ui_act("toggle_pixel"), then(PROC_REF(ui_act_toggle_pixel)))

/// /datum/nobody_wants_to_learn_matrix_math's window data.
/datum/nobody_wants_to_learn_matrix_math/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["matrix_a"] = testing_matrix.a
	data["matrix_b"] = testing_matrix.b
	data["matrix_c"] = testing_matrix.c
	data["matrix_d"] = testing_matrix.d
	data["matrix_e"] = testing_matrix.e
	data["matrix_f"] = testing_matrix.f
	data["pixelated"] = target().appearance_flags & PIXEL_SCALE
	return data

/datum/nobody_wants_to_learn_matrix_math/proc/ui_act_change_var(datum/act/op/A, var_name, var_value)
	var/matrix_var_name = var_name
	var/matrix_var_value = var_value
	if(testing_matrix.vv_edit_var(matrix_var_name, matrix_var_value) == FALSE)
		to_chat(src, "Your edit was rejected by the object. This is a bug with the matrix tester, not your fault, so report it on GitHub.", confidential = TRUE)
		return
	set_transform()

/datum/nobody_wants_to_learn_matrix_math/proc/ui_act_scale(datum/act/op/A, x, y)
	testing_matrix.Scale(x, y)
	set_transform()

/datum/nobody_wants_to_learn_matrix_math/proc/ui_act_translate(datum/act/op/A, x, y)
	testing_matrix.Translate(x, y)
	set_transform()

/datum/nobody_wants_to_learn_matrix_math/proc/ui_act_shear(datum/act/op/A, x, y)
	testing_matrix.Shear(x, y)
	set_transform()

/datum/nobody_wants_to_learn_matrix_math/proc/ui_act_turn(datum/act/op/A, angle)
	testing_matrix.Turn(angle)
	set_transform()

/datum/nobody_wants_to_learn_matrix_math/proc/ui_act_toggle_pixel(datum/act/op/A)
	target().appearance_flags ^= PIXEL_SCALE

/datum/nobody_wants_to_learn_matrix_math/proc/set_transform()
	animate(target(), transform = testing_matrix, time = 0.5 SECONDS)
	testing_matrix = matrix(target().transform)

/client/proc/open_matrix_tester(atom/in_atom)
	if(holder)
		var/datum/nobody_wants_to_learn_matrix_math/matrix_tester = new(in_atom)
		matrix_tester.tgui_interact(mob)

/// The target this refers to (a relation view: null once that is deleted).
/datum/nobody_wants_to_learn_matrix_math/proc/target() as /atom
	return target
