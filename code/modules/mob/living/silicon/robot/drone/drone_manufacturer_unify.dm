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
		om_ask(player, /datum/om/prompt/choice, PROC_REF(dronetype_chosen), title = "Drone Type", message = "What module would you like to use?", choices = possible_drones, cancel_answer = "")
		return
	return ..(player)

/obj/machinery/drone_fabricator/unify/proc/dronetype_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		drone_type = possible_drones[ask.choice]
	create_drone(ask.answerer.client, TRUE)
//UNIFY end
