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
		om_prompt(src, player, list("kind" = "list", "message" = "What module would you like to use?", "title" = "Drone Type", "choices" = possible_drones, "on_cancel" = PROC_REF(dronetype_default)), PROC_REF(dronetype_chosen))
		return
	return ..(player)

/obj/machinery/drone_fabricator/unify/proc/dronetype_default(mob/user, datum/om/prompt/ask)
	create_drone(user.client, TRUE)

/obj/machinery/drone_fabricator/unify/proc/dronetype_chosen(mob/user, choice, datum/om/prompt/ask)
	drone_type = possible_drones[choice]
	create_drone(user.client, TRUE)
//UNIFY end
