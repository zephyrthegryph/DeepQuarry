// Control panel for the quarry freight elevator.
//
// Three roles, distinguished by is_call_panel and depth:
//   - Surface interior (is_call_panel = FALSE, depth = 0):
//       Opens the QuarryElevator TGUI window. The window shows every
//       unlocked depth, each depth's stabilization goal status, and
//       buttons to dispatch the car to a chosen depth.
//   - Layer interior (is_call_panel = FALSE, depth >= 1):
//       Simple one-button action — send the car back to the surface.
//       No UI needed; the only choice is "leave".
//   - Exterior (is_call_panel = TRUE): outside the bay on the wall.
//       Summons the car to this floor if it's parked elsewhere.

/obj/structure/quarry_elevator_panel
	name = "elevator control panel"
	desc = "An old industrial control panel for the freight elevator. The buttons stick a little."
	icon = 'icons/obj/turbolift.dmi'
	icon_state = "button"
	density = FALSE
	anchored = TRUE
	plane = MOB_PLANE
	light_range = 2
	light_power = 0.6

	// The depth this panel is on. Set at placement.
	var/depth = 0

	// TRUE for exterior call buttons (summon here); FALSE for interior
	// send buttons (dispatch this car).
	var/is_call_panel = FALSE

/obj/structure/quarry_elevator_panel/Initialize(mapload)
	. = ..()
	if(SSquarry?.elevator)
		SSquarry.elevator.panels += src

/obj/structure/quarry_elevator_panel/Destroy()
	if(SSquarry?.elevator)
		SSquarry.elevator.panels -= src
	return ..()

/obj/structure/quarry_elevator_panel/attack_hand(mob/user)
	if(!user.Adjacent(src))
		to_chat(user, span_warning("You need to be next to \the [src]."))
		return
	if(user.incapacitated())
		return

	var/datum/quarry_elevator/E = SSquarry?.elevator
	if(!E)
		to_chat(user, span_warning("\The [src] is dead. No power, no link."))
		return

	if(E.traveling)
		to_chat(user, span_warning("The elevator is in transit. Wait."))
		return

	if(is_call_panel)
		// Exterior call panel: open the TGUI showing this depth's
		// stability/danger/goals + a single Call button. Acting on the
		// call request happens via tgui_act("call").
		tgui_interact(user)
		return

	// Interior dispatch. Surface panel opens the TGUI window with all
	// the unlock state; layer panels just send the car back up.
	if(depth == 0)
		tgui_interact(user)
		return

	to_chat(user, span_notice("Sending the elevator back up to the surface…"))
	E.dispatch_from(depth, 0)


// --- TGUI ---------------------------------------------------------------
//
// Only the surface interior panel uses this. The window shows every
// unlocked depth as a card with goal name, progress bar, and a
// dispatch button.

/obj/structure/quarry_elevator_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "QuarryElevator", "Freight Elevator")
		ui.open()

/obj/structure/quarry_elevator_panel/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/datum/quarry_elevator/E = SSquarry?.elevator
	data["traveling"] = E ? E.traveling : FALSE
	data["current_depth"] = E ? E.current_depth : 0
	data["unlocked_depth"] = SSquarry?.unlocked_depth || 1
	data["deepest_visited"] = SSquarry?.deepest_visited || 0
	// Panel role: "surface" surfaces the full dispatch list, "call" is
	// an exterior in-mine panel that only shows its own depth and a
	// Call button.
	data["panel_role"] = is_call_panel ? "call" : "surface"
	data["panel_depth"] = depth

	var/list/depths = list()
	// Surface panel: one card per unlocked depth. Exterior call panel:
	// just one card for the depth it lives on.
	var/list/depths_to_show = list()
	if(is_call_panel)
		depths_to_show += depth
	else
		for(var/d in 1 to SSquarry?.unlocked_depth || 0)
			depths_to_show += d
	for(var/d in depths_to_show)
		var/datum/quarry_layer/L = SSquarry.layers["[d]"]
		var/list/card = list("depth" = d)
		card["loaded"] = L?.loaded ? TRUE : FALSE
		card["snapshot"] = SSquarry.has_snapshot(d)
		// Danger: live for loaded layers, snapshot-frozen otherwise.
		card["danger"] = 0
		card["danger_label"] = "Quiet"
		if(L?.loaded)
			card["danger"] = round(L.danger)
			card["danger_label"] = quarry_danger_label(L.danger)
		else
			var/list/doc = SSquarry.read_snapshot_doc(d)
			if(islist(doc))
				var/snap_danger = doc["danger"] || 0
				card["danger"] = round(snap_danger)
				card["danger_label"] = quarry_danger_label(snap_danger)
		// Goal source: live layer if loaded, otherwise the snapshot's
		// frozen copy. Either way the UI sees a uniform goals[] array
		// of {name, description, progress, target, percent, satisfied}.
		var/list/goals_out = null
		if(L?.loaded && length(L.goals))
			goals_out = list()
			for(var/datum/quarry_goal/G as anything in L.goals)
				goals_out += list(list(
					"name" = G.name,
					"description" = G.description,
					"progress" = G.progress,
					"target" = G.target,
					"percent" = G.percent_complete(),
					"satisfied" = G.is_satisfied() ? TRUE : FALSE,
				))
		else
			var/list/snap_goals = SSquarry.read_snapshot_goals(d)
			if(islist(snap_goals) && length(snap_goals))
				goals_out = list()
				for(var/list/g in snap_goals)
					if(!islist(g))
						continue
					var/progress = g["progress"] || 0
					var/target = g["target"] || 1
					var/percent = target > 0 ? round(100 * progress / target) : 0
					goals_out += list(list(
						"name" = g["name"],
						"description" = g["description"],
						"progress" = progress,
						"target" = target,
						"percent" = percent,
						"satisfied" = progress >= target ? TRUE : FALSE,
					))
		if(goals_out)
			card["goals"] = goals_out
			// Stability is mean of per-goal percent_complete (matches
			// SSquarry.layer_stability_percent).
			var/sum_percent = 0
			for(var/list/g in goals_out)
				sum_percent += g["percent"]
			card["stability"] = round(sum_percent / length(goals_out))
			card["stability_threshold"] = QUARRY_STABILITY_THRESHOLD
		depths += list(card)
	data["depths"] = depths

	// Frontier card: only emit if there's a deeper depth a player could
	// push toward (i.e. the deepest unlocked depth has been visited and
	// stabilised, or no depth has been visited yet). Exterior call
	// panels don't show the frontier — they're not dispatch-capable.
	var/list/frontier = null
	if(SSquarry && !is_call_panel)
		if(SSquarry.unlocked_depth > SSquarry.deepest_visited)
			frontier = null
		else
			frontier = list("depth" = SSquarry.deepest_visited + 1, "unreachable" = TRUE)
	data["frontier"] = frontier

	return data

/obj/structure/quarry_elevator_panel/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	if(!user?.Adjacent(src))
		return
	if(user.incapacitated())
		return
	var/datum/quarry_elevator/E = SSquarry?.elevator
	if(!E || E.traveling)
		return
	switch(action)
		if("call")
			// Exterior call panel: summon the car to this depth.
			if(E.current_depth == depth)
				to_chat(user, span_notice("The elevator is already here."))
				return TRUE
			if(!E.summon_to(depth))
				to_chat(user, span_warning("The elevator can't be called right now — it's in transit."))
				return TRUE
			to_chat(user, span_notice("Calling the elevator…"))
			SStgui.close_uis(src)
			return TRUE
		if("dispatch")
			var/target = text2num(params["depth"])
			if(!isnum(target))
				return
			if(target < 1 || target > SSquarry.unlocked_depth)
				to_chat(user, span_warning("The elevator's shaft monitor refuses that destination."))
				return
			if(target > SSquarry.deepest_visited)
				SSquarry.deepest_visited = target
			to_chat(user, span_notice("Sending the elevator to depth [target]…"))
			E.dispatch_from(depth, target)
			SStgui.close_uis(src)
			return TRUE
