//UNIFY start
/obj/machinery/drone_fabricator/unify	//Non-Specific dronetype
	drone_type = null //var filled by drone choice.
	fabricator_tag = "Unified Drone Fabricator"

	var/static/list/possible_drones = list("Construction Module" = /mob/living/silicon/robot/drone/construction,
									"Maintenance Module" = /mob/living/silicon/robot/drone,
									) //List of drone types to choose from.//Changeable in mapping.

/// The player picks the drone type first; `chosen` is set once they have (or had no say).
/obj/machinery/drone_fabricator/unify/create_drone(client/player, chosen = FALSE)
	if(!chosen && player)
		// A cancel answers "": the drone is made with the current type.
		open_request(src, /datum/prompt/choice, PROC_REF(dronetype_chosen), answerer = player.mob, title = "Drone Type", question = "What module would you like to use?", choices = possible_drones, timeout = 0)
		return
	return ..(player)

/obj/machinery/drone_fabricator/unify/proc/dronetype_chosen(datum/act/request/A)
	var/mob/answerer = A.request.answerer
	if(QDELETED(answerer))
		return
	var/choice = A.answer ? A.answer.answer_value : ""
	if(choice)
		drone_type = possible_drones[choice]
	create_drone(answerer.client, TRUE)
//UNIFY end
