/obj/item/stack/hose/get_mechanics_info(list/additional_information)
	return ..(list("Neutral sockets can link to all socket types; Input and Output sockets link to anything but their own type.", \
		span_warning("The hose does not stretch: the two ends disconnect if moved further apart than they were when connected.")) + additional_information)

/obj/item/stack/hose
	name = "plastic tubing"
	singular_name = "plastic tube"
	desc = "A plastic tube for moving reagents to and fro. Stretching it too far will cause it to disconnect."

	icon = 'icons/obj/machines/reagent.dmi'
	icon_state = "hose"
	amount = 1
	max_amount = HOSE_MAX_DISTANCE
	w_class = ITEMSIZE_SMALL
	no_variants = TRUE
	stacktype = /obj/item/stack/hose

	/// The connector the loose end is fixed to: a relation view.
	var/datum/hose_connector/remembered = null

/obj/item/stack/hose/item_ctrl_click(mob/user)
	if(remembered)
		to_chat(user, span_notice("You wind \the [src] back up."))
		rel_clear(src, nameof(remembered))
	return

/obj/item/stack/hose/afterattack(atom/target, mob/living/user, proximity, params)
	if(!proximity)
		return
	if(in_use)
		to_chat(user, span_danger("You must choose which connector this hose will connect to before you can attach the hose to something else."))
		return

	var/datum/hose_connector/REMB = remembered
	var/list/available_sockets = list()
	var/atom/movable/target_movable = target
	var/list/target_connectors = istype(target_movable) ? target_movable.get_hose_connectors() : list()
	for(var/datum/hose_connector/HC as anything in target_connectors)
		if(!HC.get_hose())
			if(REMB)
				if(HC.get_flow_direction() == HOSE_NEUTRAL || HC.get_flow_direction() != REMB.get_flow_direction())
					available_sockets[HC.get_id()] = HC
			else
				available_sockets[HC.get_id()] = HC

	if(LAZYLEN(available_sockets))
		if(available_sockets.len == 1)
			var/key = available_sockets[1]
			var/datum/hose_connector/AC = available_sockets[key]
			if(REMB && REMB.get_carrier() == AC.get_carrier())
				to_chat(user, span_notice("Connecting \the [REMB.get_carrier()] to itself seems like a bad idea. You wind \the [src] back up."))
				rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state

			else if(REMB && REMB.valid_connection(AC))
				var/distancetonode = get_dist(REMB.get_carrier(),AC.get_carrier())
				if(distancetonode > HOSE_MAX_DISTANCE)
					to_chat(user, span_notice("\The [src] would probably burst if it were this long. You wind \the [src] back up."))
					rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state

				else if(distancetonode <= amount)
					REMB.setup_hoses(AC,distancetonode,user,src)
					rel_clear(src, nameof(remembered))

				else
					to_chat(user, span_notice("You do not have enough tubing to connect the sockets. You wind \the [src] back up."))
					rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state

			else
				rel_set(src, nameof(remembered), AC)
				to_chat(user, span_notice("You connect one end of tubing to \the [AC]."))

		else
			in_use = TRUE // Prevent opening a million uis
			var/choice = rerun_ask(user, "a1", PROC_REF(afterattack), args, /datum/om/prompt/choice, message = "Select a target hose connector.", title = "Socket Selection", choices = available_sockets)
			if(isnull(choice))
				return TRUE
			in_use = FALSE

			if(choice && user.Adjacent(target))
				var/datum/hose_connector/CC = available_sockets[choice]
				if(REMB)
					if(REMB.get_carrier() == CC.get_carrier())
						to_chat(user, span_notice("Connecting \the [REMB.get_carrier()] to itself seems like a bad idea. You wind \the [src] back up."))
						rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state

					else if(REMB.valid_connection(CC))
						var/distancetonode = get_dist(REMB.get_carrier(), CC.get_carrier())
						if(distancetonode > HOSE_MAX_DISTANCE)
							to_chat(user, span_notice("\The [src] would probably burst if it were this long. You wind \the [src] back up."))
							rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state

						else if(distancetonode <= amount)
							REMB.setup_hoses(CC,distancetonode,user,src)
							rel_clear(src, nameof(remembered))

						else
							to_chat(user, span_notice("You do not have enough tubing to connect the sockets. You wind \the [src] back up."))
							rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state

				else
					rel_set(src, nameof(remembered), CC)
					to_chat(user, span_notice("You connect one end of tubing to \the [CC]."))

		return

	else
		if(remembered)
			to_chat(user, span_notice("There are no available connectors on \the [target]. You wind \the [src] back up."))
		rel_clear(src, nameof(remembered)) // Unintuitive if it does not reset state
		..()
