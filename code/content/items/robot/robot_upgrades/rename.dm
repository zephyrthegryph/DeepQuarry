/obj/item/borg/upgrade/utility/rename
	name = "robot reclassification board"
	desc = "Used to rename a cyborg."
	icon_state = "cyborg_upgrade1"
	item_state = "cyborg_upgrade"
	var/heldname = "default name"

CAPABILITIES(/obj/item/borg/upgrade/utility/rename)
	op("self", in_hand(), asks(/datum/prompt/text, fields = list("title" = "Robot Reclassification", "question" = "Enter new robot name", "default" = computed(PROC_REF(name_default)), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "subject" = computed(PROC_REF(name_subject)), "ask_flags" = ASK_CARRIED | ASK_CAPABLE, "timeout" = REQUEST_NO_TIMEOUT)), then(PROC_REF(name_entered)))

/// The prompt's starting text: the board's current name.
/obj/item/borg/upgrade/utility/rename/proc/name_default(datum/act/A)
	return heldname

/// The question's subject, for the carried recheck of an answer: the board itself.
/obj/item/borg/upgrade/utility/rename/proc/name_subject(datum/act/A)
	return src

/// Old attack_self's question was answered: the board takes the name.
/obj/item/borg/upgrade/utility/rename/proc/name_entered(datum/act/op/A)
	if(A.answer?.value)
		heldname = A.answer.value
	return OP_OK

/obj/item/borg/upgrade/utility/rename/action(mob/user, mob/living/silicon/robot/R)
	if(..()) return FALSE
	if(isshell(R)) return FALSE
	R.notify_ai(ROBOT_NOTIFICATION_NEW_NAME, R.name, heldname)
	R.name = heldname
	R.set_custom_name(heldname)
	R.set_real_name(heldname)

	return TRUE
