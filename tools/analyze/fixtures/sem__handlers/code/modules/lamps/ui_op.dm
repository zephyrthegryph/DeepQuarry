// A UI op's handler also takes the declared args after A (section 9, "The one signature"): the clean case and a seeded violation.

/obj/ui_lamp
	var/level = 0
	var/label

CAPABILITIES(/obj/ui_lamp, \
	op("dim", ui_act(arg("level", int(0, 9))), then(PROC_REF(set_level))), \
	op("rename", ui_act("rename", arg("text", schema_text(8))), then(PROC_REF(set_label))), \
	op("blink", hand(), then(PROC_REF(blink_once))))

/// Clean: one declared arg, one parameter after A.
/obj/ui_lamp/proc/set_level(datum/act/op/A, level_value)
	level = level_value

/// Seeded: the op declares one arg, the handler takes none.
/obj/ui_lamp/proc/set_label(datum/act/op/A)
	label = "x"

/// Clean: a plain hand() op takes A alone.
/obj/ui_lamp/proc/blink_once(datum/act/op/A)
	level = 0
