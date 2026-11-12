/datum/pai_software/door_jack
	name = "Door Jack"
	ram_cost = 30
	id = "door_jack"
	toggle = 0

CAPABILITIES(/datum/pai_software/door_jack)
	interface("pAIDoorjack", title = "Door Jack", state = nameof(GLOB.tgui_always_state))
	ui_shape(cable = bool(), machine = bool(), inprogress = bool(), progress_a = int(), progress_b = int(), aborted = bool())
	op("jack", ui_act("jack"), then(PROC_REF(ui_act_jack)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))
	op("cable", ui_act("cable"), then(PROC_REF(ui_act_cable)))

/datum/pai_software/door_jack/ui_data(datum/act/eval/A)
	var/mob/living/silicon/pai/user = A.actor
	var/list/data = list()

	data["cable"] = user.cable != null
	data["machine"] = !!user.cable?.machine()
	data["inprogress"] = user.hackdoor != null
	data["progress_a"] = round(user.hackprogress / 10)
	data["progress_b"] = user.hackprogress % 10
	data["aborted"] = user.hack_aborted

	return data

/datum/pai_software/door_jack/proc/ui_act_jack(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/P = user
	if(P.cable && P.cable.machine())
		rel_set(P, nameof(/mob/living/silicon/pai::hackdoor), P.cable.machine())
		P.hackloop()
	return 1

/datum/pai_software/door_jack/proc/ui_act_cancel(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/P = user
	rel_clear(P, nameof(/mob/living/silicon/pai::hackdoor))
	return 1

/datum/pai_software/door_jack/proc/ui_act_cable(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/silicon/pai/P = user
	var/turf/T = get_turf(P)
	P.set_hack_aborted(0)
	rel_set(P, nameof(/mob/living/silicon/pai::cable), new /obj/item/pai_cable(T))
	for(var/mob/M in viewers(T))
		M.show_message(span_warning("A port on [P] opens to reveal [P.cable], which promptly falls to the floor."), 3,
						span_warning("You hear the soft click of something light and hard falling to the ground."), 2)
	return 1
