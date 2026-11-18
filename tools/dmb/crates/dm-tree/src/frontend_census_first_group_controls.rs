// Actual Source57 census first-group fixtures; these test only Original syntax
// availability. Source text and needed macro definitions are copied byte-content
// from the physical production producers, then preprocessed by the SAME Host.
fn census_first_group_receipt(source:&str)->bool{
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();let mut issued=false;
 raw.with_declaration_admission(&mut|a|{(||{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let parsed=syntax.statements.parsed();assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty(),"actual syntax diagnostics/pending: {:?}",parsed.diagnostics);let bound=input.bind_original_product_checked(syntax,a)?;match bound.original_code_disposition(){Ok(crate::frontend::OriginalBodyDisposition::Available(_))=>issued=true,Err(crate::frontend::BodySyntaxFailure::Operational(error))if crate::frontend::CurrentBodySyntax::is_unissued_original_grammar(&error)=>{
  // Diagnostic only: the same actual producer still refuses this body.
  // No alternative parse, compatibility result, or readiness flag is used.
  eprintln!("ACTUAL_CENSUS_UNISSUED source={source:?} grammar={:?} canonical_headers={:?} statements={:#?}",parsed.original_grammar,syntax.item.children.iter().map(|item|(&item.header,item.header_span)).collect::<Vec<_>>(),parsed.statements);
 },Ok(crate::frontend::OriginalBodyDisposition::Skipped(_))=>panic!("actual valid fixture cannot be skipped"),Err(other)=>panic!("actual source failure must not be reclassified as missing witness: {other:?}")};Ok(())})().map_err(|original|{
  // Preserve the SAME first operational cause from either parse or bind
  // before this test admission dies. No retry/limit/refund/waiver occurs.
  if matches!(&original,crate::frontend::BodySyntaxFailure::Operational(_)){
   if let Some(actual)=a.take_operational_error(){return crate::frontend::BodySyntaxFailure::Operational(actual)}
  }
  original
 })}).unwrap();issued
}
#[test]fn actual_original_census_first_group_full_translate_turf_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/translate_turf(turf/T, turf/B, turftoleave = null)

	//You can stay, though.
	if(istype(T,/turf/space))
		log_world("## ERROR Tried to translate a space turf: src=[log_info_line(T)] dst=[log_info_line(B)]")
		return FALSE // TODO - Is this really okay to do nothing?

	var/turf/X //New Destination Turf

	//Are we doing shuttlework? Just to save another type check later.
	var/shuttlework = 0

	T.pre_translate_A(B)
	B.pre_translate_B(T)

	//Shuttle turfs handle their own fancy moving.
	if(istype(T,/turf/simulated/shuttle))
		shuttlework = 1
		var/turf/simulated/shuttle/SS = T
		if(!SS.landed_holder()) rel_set(SS, nameof(SS.landed_holder_ref), new /datum/landed_holder(SS))
		X = SS.landed_holder().land_on(B)

	//Generic non-shuttle turf move.
	else
		var/old_dir1 = T.dir
		var/old_icon_state1 = T.icon_state
		var/old_icon1 = T.icon
		var/old_decals = T.decals ? T.decals.Copy() : null

		X = B.ChangeTurf(T.type)
		X.set_dir(old_dir1)
		X.set_icon_state(old_icon_state1)
		X.set_icon(old_icon1)
		X.copy_overlays(T, TRUE)
		X.set_decals(old_decals)

	// air-transfer used ZAS zone.air. Under LINDA each turf has its own
	// air via return_air(); copy from source-turf's air to dest-turf's air directly.
	var/datum/gas_mixture/source_air = T.return_air()
	if(source_air)
		var/datum/gas_mixture/dest_air = X.return_air()
		if(dest_air)
			dest_air.copy_from(source_air)

	var/z_level_change = FALSE
	if(T.z != X.z)
		z_level_change = TRUE

	//Move the objects. Not forceMove because the object isn't "moving" really, it's supposed to be on the "same" turf.
	for(var/obj/O in turf_contents_of_type(T, /obj))
		if(atom_rules_of(O).simulated)
			O.forceMove(X)
			if(atom_rules_of(O).light_system == STATIC_LIGHT)
				O.update_light()
			if(z_level_change) // The objects still need to know if their z-level changed.
				O.onTransitZ(T.z, X.z)

	//Move the mobs unless it's an AI eye or other eye type.
	for(var/mob/M in turf_contents_of_type(T, /mob))
		if(isEye(M)) continue // If we need to check for more mobs, I'll add a variable
		M.forceMove(X)

		if(z_level_change) // Same goes for mobs.
			M.onTransitZ(T.z, X.z)

	if(shuttlework)
		var/turf/simulated/shuttle/SS = T
		SS.landed_holder().leave_turf(turftoleave)
	else if(turftoleave)
		T.ChangeTurf(turftoleave)
	else
		T.ChangeTurf(get_base_turf_by_area(T))

	T.post_translate_A(B)
	B.post_translate_B(T)

	return X

//Used for border objects. This returns true if this atom is on the border between the two specified turfs
//This assumes that the atom is located inside the target turf
"####),"actual translate_turf body remains unissued");}
#[test]fn actual_original_census_first_group_full_spiral_range_turfs_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/spiral_range_turfs(dist = 0, atom/center = null, orange = FALSE, list/outlist = list(), tick_checked)
	outlist.Cut()
	if(!dist)
		outlist += center
		return outlist

	var/turf/t_center = get_turf(center)
	if(!t_center)
		return outlist

	var/list/turf_list = outlist
	var/turf/checked_turf
	var/y
	var/x
	var/c_dist = 1

	if(!orange)
		turf_list += t_center

	while( c_dist <= dist )
		y = t_center.y + c_dist
		x = t_center.x - c_dist + 1
		for(x in x to t_center.x + c_dist)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				turf_list += checked_turf

		y = t_center.y + c_dist - 1
		x = t_center.x + c_dist
		for(y in t_center.y - c_dist to y)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				turf_list += checked_turf

		y = t_center.y - c_dist
		x = t_center.x + c_dist - 1
		for(x in t_center.x - c_dist to x)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				turf_list += checked_turf

		y = t_center.y - c_dist + 1
		x = t_center.x - c_dist
		for(y in y to t_center.y + c_dist)
			checked_turf = locate(x, y, t_center.z)
			if(checked_turf)
				turf_list += checked_turf
		c_dist++
		if(tick_checked)
			CHECK_TICK

	return turf_list
"####),"actual spiral_range_turfs body remains unissued");}
#[test]fn actual_original_census_first_group_full_typelist_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/typelist(datum/owner, key, list/values = list())
	var/type = owner.type
	var/list/mytypelist = GLOB.typelists[type] || (GLOB.typelists[type] = list())
	return mytypelist[key] || (mytypelist[key] = values.Copy())

"####),"actual typelist body remains unissued");}
#[test]fn actual_original_census_first_group_full_graph_astar_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/graph_astar(start, end, adjacent, dist, max_nodes, max_node_depth = 30, min_target_dist = 0, min_node_dist, id, datum/exclude)
	var/datum/priority_queue/open = new /datum/priority_queue(/proc/cmp_graph_astar_node)
	var/list/closed = list()
	var/list/path
	var/list/path_node_by_position = list()
	start = get_turf(start)
	if(!start)
		return 0

	open.enqueue(ASTAR_GRAPHA_NEW(start, null, 0, call(start, dist)(end), 0))

	while(!open.is_empty() && !path)
		var/list/current = open.dequeue()
		closed.Add(current[ASTAR_GRAPHA_POS])

		if(current[ASTAR_GRAPHA_POS] == end || call(current[ASTAR_GRAPHA_POS], dist)(end) <= min_target_dist)
			path = new /list(current[ASTAR_GRAPHA_DEPTH] + 1)
			path[path.len] = current[ASTAR_GRAPHA_POS]
			var/index = path.len - 1

			while(current[ASTAR_GRAPHA_PREV])
				current = current[ASTAR_GRAPHA_PREV]
				path[index--] = current[ASTAR_GRAPHA_POS]
			break

		if(min_node_dist && max_node_depth)
			if(call(current[ASTAR_GRAPHA_POS], min_node_dist)(end) + current[ASTAR_GRAPHA_DEPTH] >= max_node_depth)
				continue

		if(max_node_depth)
			if(current[ASTAR_GRAPHA_DEPTH] >= max_node_depth)
				continue

		for(var/datum/datum in call(current[ASTAR_GRAPHA_POS], adjacent)(id))
			if(datum == exclude)
				continue

			var/best_estimated_cost = current[ASTAR_GRAPHA_EST] + call(current[ASTAR_GRAPHA_POS], dist)(datum)

			//handle removal of sub-par positions
			if(datum in path_node_by_position)
				var/list/target = path_node_by_position[datum]
				if(target[ASTAR_GRAPHA_BEST])
					if(best_estimated_cost + call(datum, dist)(end) < target[ASTAR_GRAPHA_BEST])
						open.remove_entry(target)
					else
						continue

			var/list/next_node = ASTAR_GRAPHA_NEW(datum, current, best_estimated_cost, call(datum, dist)(end), current[ASTAR_GRAPHA_DEPTH] + 1)
			path_node_by_position[datum] = next_node
			open.enqueue(next_node)

			if(max_nodes && length(open.array) > max_nodes)
				open.remove_index(length(open.array))

	return path

"####),"actual graph_astar body remains unissued");}
#[test]fn actual_original_census_first_group_isolated_translate_call_result_assignment_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(SS,B)
    var/X
    X=SS.landed_holder().land_on(B)
"####),"actual translate_call_result_assignment cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_translate_call_result_conditions_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(O,SS,B)
    if(atom_rules_of(O).simulated)
        if(atom_rules_of(O).light_system==STATIC_LIGHT)
            O.update_light()
    if(!SS.landed_holder()) rel_set(SS, nameof(SS.landed_holder_ref), new /datum/landed_holder(SS))
"####),"actual translate_call_result_conditions cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_spiral_reused_range_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(x,y,t_center,c_dist)
    for(x in x to t_center.x+c_dist)
        y=x
    for(y in t_center.y-c_dist to y)
        x=y
"####),"actual spiral_reused_range cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_spiral_tick_expression_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(tick_checked)
    if(tick_checked)
        CHECK_TICK
"####),"actual spiral_tick_expression cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_typelist_grouped_index_assignment_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(type,key,values)
    var/list/mytypelist=GLOB.typelists[type] || (GLOB.typelists[type]=list())
    return mytypelist[key] || (mytypelist[key]=values.Copy())
"####),"actual typelist_grouped_index_assignment cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_astar_dynamic_argument_roster_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(open,start,dist,end)
    open.enqueue(ASTAR_GRAPHA_NEW(start,null,0,call(start,dist)(end),0))
"####),"actual astar_dynamic_argument_roster cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_astar_dynamic_iterable_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(current,adjacent,id)
    for(var/datum/datum in call(current[ASTAR_GRAPHA_POS],adjacent)(id))
        return datum
"####),"actual astar_dynamic_iterable cohort remains unissued");}
#[test]fn actual_original_census_first_group_isolated_astar_indexed_postfix_has_native_receipt(){assert!(census_first_group_receipt(r####"#define get_turf(A) get_step(A,0)
#define isEye(A)		istype(A, /mob/observer/eye)
#define STATIC_LIGHT 1
#define TICK_USAGE world.tick_usage
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define ASTAR_GRAPHA_POS 1
#define ASTAR_GRAPHA_PREV 2
#define ASTAR_GRAPHA_BEST 3
#define ASTAR_GRAPHA_EST 4
#define ASTAR_GRAPHA_DEPTH 5
#define ASTAR_GRAPHA_NEW(pos, prev, known, cost, depth) list(pos, prev, (cost) + (known), (cost) + (known), depth)
/proc/probe(path,index,current)
    path[index--]=current[ASTAR_GRAPHA_POS]
"####),"actual astar_indexed_postfix cohort remains unissued");}

#[test]
fn actual_original_parenthesized_statement_routing_requires_conditional_value_receipt(){
 for source in[
  "/proc/probe(value)\n    (value)\n",
  "/proc/probe(value)\n    (lookup().field=value)\n",
 ]{
  assert!(!census_first_group_receipt(source),"routing a parenthesized leaf must not issue grammar without the actual effect-statement receipt: {source}");
 }
}

// Exact later-frontier bodies from actual Source63 observed Raw.
#[test]
fn actual_original_apc_report_full_body_has_native_receipt(){
 assert!(census_first_group_receipt(r####"#define TICK_USAGE world.tick_usage
#define TICK_DELTA_TO_MS(percent_of_tick_used) ((percent_of_tick_used) * world.tick_lag)
#define TICK_USAGE_TO_MS(starting_tickusage) (TICK_DELTA_TO_MS(world.tick_usage - starting_tickusage))
#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define CLOCK_WORLD 0
#define TIME_NOW(clock, owner...) ((clock) ? own_clock_now(owner) : world.time)
#define SECONDS *10
#define APC_REPORT_LOG_INTERVAL (30 SECONDS)
#define COOLDOWN_FINISHED(cd_source, cd_index) (cd_source.cd_index < TIME_NOW(CLOCK_WORLD))
#define COOLDOWN_START(cd_source, cd_index, cd_time) (cd_source.cd_index = TIME_NOW(CLOCK_WORLD) + (cd_time))
/obj/machinery/power/apc/on_apc_report(new_equipment, new_lighting, new_environ, new_charging, alarm, new_status, charge)
	if(QDELETED(src))
		return
	// A report that moved only the cell's charge and the charging lamp (every APC's cell crosses a percent together and the lamps flip together, so ~380 of
	// these arrive in one frame every ten seconds and again when the station starts charging): applying one is the cost of the report, and what it moves may
	// reach the APC a few ticks later without anything noticing (apc_cosmetic_report()).
	if(new_equipment == equipment && new_lighting == lighting && new_environ == environ && new_status == main_status && !!alarm == power_alarm_raised)
		power_event_count++ // reports heard (tests: a settled APC hears nothing)
		apc_cosmetic_report(src, new_charging, cell && pushed_cell_ref == REF(cell) ? clamp(charge, 0, cell.maxcharge) : null)
		return
	pending_report_charge = null // a report that moves more than the charge and the lamp applies at once, and is the newer
	pending_report_charging = null
	var/cost_start = TICK_USAGE
	if(cell && pushed_cell_ref == REF(cell))
		cell.set_charge(clamp(charge, 0, cell.maxcharge))
		cell_charge_mirror = cell.charge
	var/cell_ms = TICK_USAGE_TO_MS(cost_start)
	var/channels_changed = new_equipment != equipment || new_lighting != lighting || new_environ != environ
	var/structural_changed = channels_changed || new_status != main_status || !!alarm != power_alarm_raised
	var/shown_changed = structural_changed || new_charging != charging
	var/setters_start = TICK_USAGE
	set_equipment(new_equipment)
	set_lighting(new_lighting)
	set_environ(new_environ)
	var/charging_start = TICK_USAGE
	set_charging(new_charging)
	var/charging_ms = TICK_USAGE_TO_MS(charging_start)
	var/status_start = TICK_USAGE
	set_main_status(new_status)
	var/status_ms = TICK_USAGE_TO_MS(status_start)
	apc_report_cost_note(shown_changed, cell_ms, TICK_USAGE_TO_MS(setters_start))
	power_event_count++ // reports heard (tests: a settled APC hears nothing)
	alarm = !!alarm
	var/alarm_start = TICK_USAGE
	if(alarm != power_alarm_raised)
		power_alarm_raised = alarm
		if(alarm)
			GLOB.power_alarm.triggerAlarm(loc, src, hidden = alarms_hidden)
		else
			GLOB.power_alarm.clearAlarm(loc, src)
	var/alarm_ms = TICK_USAGE_TO_MS(alarm_start)
	if(shown_changed)
		// A channel, status or alarm change is always logged. The charging lamp flips back and forth on a settled station (about 18 reports a second over
		// 310 APCs), so a charging-only report is logged once per APC_REPORT_LOG_INTERVAL and the line says how many it stands for.
		if(structural_changed || COOLDOWN_FINISHED(src, report_log_cooldown))
			log_world("APC_REPORT: [src] ([area]) channels [equipment]/[lighting]/[environ] charging [charging] status [main_status] alarm [alarm] charge [charge][report_log_skipped ? " ([report_log_skipped] charging-only reports since the last line)" : ""]")
			report_log_skipped = 0
			COOLDOWN_START(src, report_log_cooldown, APC_REPORT_LOG_INTERVAL)
		else
			report_log_skipped++
	var/apply_start = TICK_USAGE
	if(channels_changed)
		apply_area_power()
	var/apply_ms = TICK_USAGE_TO_MS(apply_start)
	var/report_ms = TICK_USAGE_TO_MS(cost_start)
	if(report_ms >= 50)
		log_world("APC_REPORT_SLOW: [src] ([area]) took [round(report_ms, 0.1)] ms: charge write [round(cell_ms, 0.1)], charging setter [round(charging_ms, 0.1)], status setter [round(status_ms, 0.1)], alarm [round(alarm_ms, 0.1)], channel apply [round(apply_ms, 0.1)] (channels changed [channels_changed], structural [structural_changed], alarm raised [power_alarm_raised]) at charge [charge]")
"####),"actual Source63 actual_original_apc_report_full_body_has_native_receipt remains unissued");
}
#[test]
fn actual_original_load_admins_full_body_has_native_receipt(){
 assert!(census_first_group_receipt(r####"#define CONFIG_GET(X) global.config.Get(/datum/config_entry/##X)
#define NO_FEEDBACK_LINK "no_feedback_link"
/proc/load_admins(no_update, initial = FALSE, list/prefetched, mob/user)
	if(!initial)
		if(!global.config.PreConfigReload(user))
			return

	var/dbfail
	if(!CONFIG_GET(flag/admin_legacy_system) && !SSdbcore.Connect())
		message_admins("Failed to connect to database while loading admins. Loading from backup.")
		log_sql("Failed to connect to database while loading admins. Loading from backup.")
		dbfail = TRUE
	// Detach every live holder the way a deadmin does: verbs removed, the client unlinked and the datum's owner relation dropped
	// (unlinking the client by hand left each old datum still pointing at it).
	for(var/admin_ckey in GLOB.admin_datums)
		var/datum/admins/old = GLOB.admin_datums[admin_ckey]
		old?.disassociate()
	GLOB.admin_datums.Cut()
	for(var/client/current_client in GLOB.admins) // a client admitted without a datum still loses its verbs
		current_client.remove_admin_verbs()
	GLOB.admins.Cut()
	GLOB.protected_admins.Cut()
	GLOB.deadmins.Cut()
	var/list/backup_file_json = load_admin_ranks(dbfail, no_update, prefetched, user)
	dbfail = backup_file_json != null
	//Clear profile access
	for(var/A in world.GetConfig("admin"))
		world.SetConfig("APP/admin", A, null)
	var/list/rank_names = list()
	for(var/datum/admin_rank/R in GLOB.admin_ranks)
		rank_names[R.name] = R
	//ckeys listed in admins.txt are always made admins before sql loading is attempted
	var/admins_text = file2text("[global.config.directory]/admins.txt")
	var/regex/admins_regex = new(@"^(?!#)(.+?)\s+=\s+(.+)", "gm")

	while(admins_regex.Find(admins_text))
		var/admin_key = admins_regex.group[1]
		var/admin_rank = admins_regex.group[2]
		new /datum/admins(ranks_from_rank_name(admin_rank), ckey(admin_key), force_active = FALSE, protected = TRUE)

	if(!CONFIG_GET(flag/admin_legacy_system) && !dbfail)
		var/list/admin_rows
		if(prefetched)
			admin_rows = prefetched["admins"]
		else
			admin_rows = db_query_now("SELECT ckey, `rank`, feedback FROM [format_table_name("admin")] ORDER BY `rank`") // boot only: the admins load before the kernel ticks, so nothing can wait on an io_job query yet
		if(isnull(admin_rows))
			message_admins("Error loading admins from database. Loading from backup.")
			log_sql("Error loading admins from database. Loading from backup.")
			dbfail = 1
		else
			for(var/list/row as anything in admin_rows)
				var/admin_ckey = ckey(row[1])
				var/admin_rank = row[2]
				var/admin_feedback = row[3]
				var/skip

				var/list/admin_ranks = ranks_from_rank_name(admin_rank)

				if(admin_ranks.len == 0)
					message_admins("[admin_ckey] loaded with invalid admin rank [admin_rank].")
					skip = 1
				if(GLOB.admin_datums[admin_ckey] || GLOB.deadmins[admin_ckey])
					skip = 1
				if(!skip)
					var/datum/admins/admin_holder = new(admin_ranks, admin_ckey)
					admin_holder.fetched_feedback_link = admin_feedback || NO_FEEDBACK_LINK
		if (!no_update)
			save_admin_backup(user)
			sync_admins_with_db(user)
	//load admins from backup file
	if(dbfail)
		if(!backup_file_json)
			if(backup_file_json != null)
				//already tried
				return
			var/backup_file = file2text("data/admins_backup.json")
			if(backup_file == null)
				log_world("Unable to locate admins backup file.")
				return
			backup_file_json = json_decode(backup_file)
		for(var/backup_admin_ckey in backup_file_json["admins"])
			var/skip
			for(var/admin_ckey in GLOB.admin_datums + GLOB.deadmins)
				if(ckey(admin_ckey) == ckey("[backup_admin_ckey]")) //this admin was already loaded from txt override
					skip = TRUE
					break
			if(skip)
				continue
			new /datum/admins(ranks_from_rank_name(backup_file_json["admins"]["[backup_admin_ckey]"]), ckey("[backup_admin_ckey]"))
	#ifdef TESTING
	var/msg = "Admins Built:\n"
	for(var/ckey in GLOB.admin_datums)
		var/datum/admins/D = GLOB.admin_datums[ckey]
		msg += "\t[ckey] - [D.rank_names()]\n"
	testing(msg)
	#endif
	return dbfail
"####),"actual Source63 actual_original_load_admins_full_body_has_native_receipt remains unissued");
}
#[test]
fn actual_original_apc_cooldown_start_statement_has_native_receipt(){
 assert!(census_first_group_receipt(r####"#define TICK_USAGE world.tick_usage
#define TICK_DELTA_TO_MS(percent_of_tick_used) ((percent_of_tick_used) * world.tick_lag)
#define TICK_USAGE_TO_MS(starting_tickusage) (TICK_DELTA_TO_MS(world.tick_usage - starting_tickusage))
#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define CLOCK_WORLD 0
#define TIME_NOW(clock, owner...) ((clock) ? own_clock_now(owner) : world.time)
#define SECONDS *10
#define APC_REPORT_LOG_INTERVAL (30 SECONDS)
#define COOLDOWN_FINISHED(cd_source, cd_index) (cd_source.cd_index < TIME_NOW(CLOCK_WORLD))
#define COOLDOWN_START(cd_source, cd_index, cd_time) (cd_source.cd_index = TIME_NOW(CLOCK_WORLD) + (cd_time))
/proc/probe()
    COOLDOWN_START(src,report_log_cooldown,APC_REPORT_LOG_INTERVAL)
"####),"actual Source63 actual_original_apc_cooldown_start_statement_has_native_receipt remains unissued");
}

#[test]
fn actual_original_grouped_assignment_statement_keeps_consumed_target_and_effect_role(){
 for source in[
  "/proc/probe(value,other)\n    (value=other)\n",
  "/proc/probe(owner,value)\n    (owner.field=value)\n",
  "/proc/probe(table,key,value)\n    (table[key]=value)\n",
 ]{
  assert!(census_first_group_receipt(source),"an actual consumed grouped assignment can be an effect statement: {source}");
 }
}

#[test]
fn actual_original_for_iterable_value_combination_requires_real_child_and_header_receipts(){
 for source in[
  "/proc/probe()\n    for(var/admin_ckey in GLOB.admin_datums+GLOB.deadmins)\n        return admin_ckey\n",
  "/proc/probe(left)\n    for(var/item in left+choose())\n        return item\n",
 ]{assert!(census_first_group_receipt(source),"an actual complete iterable value keeps its separate real ForList head: {source}");}
 for source in[
  "/proc/probe(index,limit)\n    for(var/item in ++index<limit)\n        return item\n",
  "/proc/probe(total,delta)\n    for(var/item in total+=delta)\n        return item\n",
 ]{assert!(!census_first_group_receipt(source),"a statement/control-only receipt cannot become an iterable value: {source}");}
}

// Actual Source66 next-frontier physical functions, including their real macros.
#[test]
fn actual_original_save_admin_backup_full_body_has_native_receipt(){
 assert!(census_first_group_receipt(r####"#define CONFIG_GET(X) global.config.Get(/datum/config_entry/##X)
#define span_adminprefix(str) ("<span class='admin prefix'>" + str + "</span>")
#define DIRECT_OUTPUT(A, B) A << B
#define WRITE_FILE(file, text) DIRECT_OUTPUT(file, text)
/proc/save_admin_backup(mob/user)
	if(IsAdminAdvancedProcCall())
		to_chat(user, span_adminprefix("Admin rank DB Sync blocked: Advanced ProcCall detected."))
		return

	if(CONFIG_GET(flag/admin_legacy_system)) //we're already using legacy system so there's nothing to save
		return

	//json format backup file generation stored per server
	var/json_file = file("data/admins_backup.json")
	var/list/file_data = list(
		"ranks" = list(),
		"admins" = list()
	)
	for(var/datum/admin_rank/R as anything in GLOB.admin_ranks)
		file_data["ranks"]["[R.name]"] = list()
		file_data["ranks"]["[R.name]"]["include rights"] = R.include_rights
		file_data["ranks"]["[R.name]"]["exclude rights"] = R.exclude_rights
		file_data["ranks"]["[R.name]"]["can edit rights"] = R.can_edit_rights

	for(var/admin_ckey in GLOB.admin_datums + GLOB.deadmins)
		var/datum/admins/admin = GLOB.admin_datums[admin_ckey]

		if(!admin)
			admin = GLOB.deadmins[admin_ckey]
			if (!admin)
				continue

		file_data["admins"][admin_ckey] = admin.rank_names()


	fdel(json_file)
	WRITE_FILE(json_file, json_encode(file_data, JSON_PRETTY_PRINT))
"####),"actual Source66 actual_original_save_admin_backup_full_body_has_native_receipt remains unissued");
}
#[test]
fn actual_original_xgm_id_for_gas_full_body_has_native_receipt(){
 assert!(census_first_group_receipt(r####"/datum/gas_mixture/proc/get_xgm_id_for_gas(gas_id_string)
	var/static/list/xgm_id_to_type
	if (isnull(xgm_id_to_type))
		xgm_id_to_type = list()
		for (var/gas_path in subtypesof(/datum/gas))
			var/datum/gas/gas_type = gas_path // typed only to read initial(); the list holds the path
			xgm_id_to_type[initial(gas_type.id)] = gas_path
	return xgm_id_to_type[gas_id_string]
"####),"actual Source66 actual_original_xgm_id_for_gas_full_body_has_native_receipt remains unissued");
}

#[test]
fn actual_original_torban_autoupdate_full_body_preserves_implicit_new_and_savefile_read_scope(){
 assert!(census_first_group_receipt(r####"#define TORFILE "data/ToR_ban.bdb"
#define TOR_UPDATE_INTERVAL 216000	//~6 hours
/proc/ToRban_autoupdate()
	var/savefile/F = new(TORFILE)
	if(F)
		var/last_update
		F["last_update"] >> last_update
		if((last_update + TOR_UPDATE_INTERVAL) < world.realtime)	//we haven't updated for a while
			ToRban_update()
	return
"####),"actual Source69 ToRban_autoupdate native grammar remains unissued; real implicit constructor and savefile >> kept intact");
}

const ACTUAL_LIST2TEXT_FULL_PHYSICAL_SOURCE:&str=r####"/proc/list2text(list/ls, sep)
	if (ls.len <= 1) // Early-out code for empty or singleton lists.
		return ls.len ? ls[1] : ""

	var/l = ls.len // Made local for sanic speed.
	var/i = 0      // Incremented every time a list index is accessed.

	if (sep != null)
		// Macros expand to long argument lists like so: sep, ls[++i], sep, ls[++i], sep, ls[++i], etc...
		#define S1  sep, ls[++i]
		#define S4  S1,  S1,  S1,  S1
		#define S16 S4,  S4,  S4,  S4
		#define S64 S16, S16, S16, S16

		. = "[ls[++i]]" // Make sure the initial element is converted to text.

		// Having the small concatenations come before the large ones boosted speed by an average of at least 5%.
		if (l-1 & 0x01) // 'i' will always be 1 here.
			. = text("[][][]", ., S1) // Append 1 element if the remaining elements are not a multiple of 2.
		if (l-i & 0x02)
			. = text("[][][][][]", ., S1, S1) // Append 2 elements if the remaining elements are not a multiple of 4.
		if (l-i & 0x04)
			. = text("[][][][][][][][][]", ., S4) // And so on....
		if (l-i & 0x08)
			. = text("[][][][][][][][][][][][][][][][][]", ., S4, S4)
		if (l-i & 0x10)
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S16)
		if (l-i & 0x20)
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S16, S16)
		if (l-i & 0x40)
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S64)
		while (l > i) // Chomp through the rest of the list, 128 elements at a time.
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S64, S64)

		#undef S64
		#undef S16
		#undef S4
		#undef S1
	else
		// Macros expand to long argument lists like so: ls[++i], ls[++i], ls[++i], etc...
		#define S1  ls[++i]
		#define S4  S1,  S1,  S1,  S1
		#define S16 S4,  S4,  S4,  S4
		#define S64 S16, S16, S16, S16

		. = "[ls[++i]]" // Make sure the initial element is converted to text.

		if (l-1 & 0x01) // 'i' will always be 1 here.
			. += S1 // Append 1 element if the remaining elements are not a multiple of 2.
		if (l-i & 0x02)
			. = text("[][][]", ., S1, S1) // Append 2 elements if the remaining elements are not a multiple of 4.
		if (l-i & 0x04)
			. = text("[][][][][]", ., S4) // And so on...
		if (l-i & 0x08)
			. = text("[][][][][][][][][]", ., S4, S4)
		if (l-i & 0x10)
			. = text("[][][][][][][][][][][][][][][][][]", ., S16)
		if (l-i & 0x20)
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S16, S16)
		if (l-i & 0x40)
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S64)
		while (l > i) // Chomp through the rest of the list, 128 elements at a time.
			. = text("[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]\
						[][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][][]", ., S64, S64)

		#undef S64
		#undef S16
		#undef S4
		#undef S1

// Converts a string into a list by splitting the string at each delimiter found. (discarding the seperator)
"####;
#[test]fn actual_original_list2text_full_body_keeps_actual_empty_template_placeholders_and_macros(){assert!(census_first_group_receipt(ACTUAL_LIST2TEXT_FULL_PHYSICAL_SOURCE),"actual full list2text native body remains unissued; real empty placeholders and nested macro rosters retained");}

#[test]fn actual_original_set_icon_full_body_preserves_authored_current_optional_index_and_macro_calls(){assert!(census_first_group_receipt(r####"#define READERS(E, KEY) rx_readers(E, KEY)
/atom/proc/set_icon(new_icon)
	if(icon == new_icon)
		return
	icon = new_icon
	if(GLOB.stat_input_keys?[nameof(icon)] || GLOB.derived_read_vars?[nameof(icon)] || (length(GLOB.generated_reads_table) && READERS(src, nameof(icon))) || draw_hop_reads_var(nameof(icon)))
		tracked_changed(src, nameof(icon))
"####),"actual complete set_icon original grammar remains unissued; physical body and READERS macro retained for real firstleaf diagnosis");}

#[test]fn actual_original_shared_cache_assign_uid_full_body_keeps_template_prefix_update_and_member_write(){assert!(census_first_group_receipt(r####"/proc/shared_cache_assign_uid(datum/D)
	D.shared_cache_uid = "#[++shared_cache_uid_counter]"
	return D.shared_cache_uid
"####),"actual physical shared_cache_assign_uid grammar must be Available; retain genuine firstleaf before any prefix/value attribution");}

#[test]fn actual_original_landed_holder_land_on_full_body_keeps_real_arguments_and_followers(){assert!(census_first_group_receipt(r####"/datum/landed_holder/proc/land_on(turf/T)
	//Gather destination information
	var/datum/landed_holder/new_holder = new()
	new_holder.turf_type = T.type
	new_holder.saved_dir = T.dir
	new_holder.saved_icon = T.icon
	new_holder.saved_icon_state = T.icon_state
	new_holder.saved_overlays = T.overlays.Copy()
	new_holder.saved_underlays = T.underlays_without_lighting()
	new_holder.decals = T.decals ? T.decals.Copy() : null

	//Set the destination to be like us
	// ChangeTurf() keeps the lighting object of a dynamic turf and makes or ends one when the type's dynamic lighting differs; the source keeps its own until it changes.
	var/turf/simulated/shuttle/new_dest = T.ChangeTurf(my_turf().type,,1)
	new_dest.set_dir(my_turf().dir)
	new_dest.set_icon_state(my_turf().icon_state)
	new_dest.set_icon(my_turf().icon)
	new_dest.copy_overlays(my_turf(), TRUE)
	new_dest.set_underlays_keeping_lighting(my_turf().underlays_without_lighting())
	var/turf/simulated/shuttle/held_turf = my_turf()
	new_dest.set_decals(held_turf.decals)
	//Shuttle specific stuff
	new_dest.interior_corner = my_turf().interior_corner
	new_dest.takes_underlays = my_turf().takes_underlays
	new_dest.under_turf = my_turf().under_turf
	new_dest.set_join_flags(my_turf().join_flags)
	new_dest.join_group = my_turf().join_group
	if(!new_dest.lighting_object)
		new_dest.lighting_build_overlay()

	// Associate the holder with the new turf.
	rel_set(new_holder, nameof(new_holder.my_turf), new_dest)
	rel_set(new_dest, nameof(new_dest.landed_holder_ref), new_holder)

	//Update underlays if necessary (interior corners won't have changed).
	if(new_dest.takes_underlays && !new_dest.interior_corner)
		new_dest.underlay_update()
		new_dest.lighting_object?.addtoturf() // underlay_update() rewrites the underlays

	return new_dest
"####),"actual entire physical land_on body remains unissued; use genuine firstleaf before grammar attribution");}

#[test]fn actual_original_icon_state_has_directions_full_body_preserves_real_cache_macro_and_recursive_calls(){assert!(census_first_group_receipt(r####"#ifdef SHARED_CACHE_STATS
#define CACHED_FAST(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) (++_sch_##N && (I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K, ##A))
#else
#define CACHED_FAST(N, K) (_scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) ((I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (_scs_##N[K] || _sc_##N.miss(K, ##A))
#endif
/// The counted form, whatever the build (the benchmark's comparison arm).
#define CACHED_COUNTED(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))

#if (defined(UNIT_TESTS) && !defined(BENCHMARK)) || defined(SPACEMAN_DMM)
// Test builds: every hit is verified against the snapshot taken at build time. A benchmark build measures the release path instead.
#define CACHED(N, K) _sc_##N.guarded(K)
#define CACHED_KEY(N, K, A...) _sc_##N.guarded(K, ##A)
#define CACHED_INT(N, I) _sc_##N.guarded_int(I)
#else
#define CACHED(N, K) CACHED_FAST(N, K)
#define CACHED_KEY(N, K, A...) _CACHED_KEY_FAST(N, K, ##A)
#define CACHED_INT(N, I) CACHED_INT_FAST(N, I)
#endif
/proc/icon_state_has_directions(file, state)
	if(icon_has_stable_key(file))
		var/list/dir_counts = CACHED_KEY(icon_state_dir_counts, "[file]", file)
		var/dirs = dir_counts?[state]
		if(!isnull(dirs))
			return dirs != 1
	return length(icon_states_fast(icon(file, state, NORTH))) || length(icon_states_fast(icon(file, state, EAST))) || length(icon_states_fast(icon(file, state, WEST)))
"####),"actual whole icon_state_has_directions grammar must be Available; this small-host baseline does not pretend to reproduce the whole-project retained-pressure OOM");}

#[test]fn actual_original_io_job_full_body_preserves_variadic_arguments_cache_handles_and_clock_macro(){assert!(census_first_group_receipt(r####"#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define REALTIMEOFDAY (world.timeofday + (MIDNIGHT_ROLLOVER * MIDNIGHT_ROLLOVER_CHECK))
#define MIDNIGHT_ROLLOVER_CHECK ( wall_clock().last_timeofday != world.timeofday ? update_midnight_rollover() : wall_clock().rollovers )
#define MIDNIGHT_ROLLOVER		864000	//number of deciseconds in a day
/proc/io_job(owner, backend_type, ...)
	var/datum/E = owner
	var/datum/io_backend/K = io_backend(backend_type)
	if(!K)
		CRASH("io_job: [backend_type] is not an I/O backend")
	if(length(args) < 3 + K.arg_count)
		CRASH("io_job: [backend_type] takes [K.arg_count] request args and a callback")
	var/owner_h = null
	if(!isnull(E))
		if(QDELETED(E))
			return 0
		owner_h = handle_of(E) // the IO lane keeps its own queue and a deletion-safe handle to the job owner
		if(!owner_h)
			return 0
	var/datum/io_job/J = new
	J.owner_h = owner_h
	J.backend_type = backend_type
	J.request = K.arg_count ? args.Copy(3, 3 + K.arg_count) : list()
	J.on_done = args[3 + K.arg_count]
	if(length(args) > 3 + K.arg_count)
		var/list/capture = capture_args(args.Copy(4 + K.arg_count))
		if(!capture)
			return 0
		J.context = capture[1]
		J.positions = capture[2]
	var/datum/io_lane/lane = GLOB.io_lane
	J.id = ++lane.seq
	J.queued_at = REALTIMEOFDAY
	rel_add(lane, nameof(lane.jobs), J)
	io_try_start(lane, K, J)
	io_lane_wake(lane)
	return J.id
"####),"actual complete physical io_job remains unissued; genuine firstleaf must precede any grammar attribution");}

#[test]fn actual_original_generated_latency_declaration_keeps_real_proc_ref_time_and_member_keywords(){assert!(census_first_group_receipt(r####"#define PROC_REF(X) (nameof(.proc/##X))
#define SECONDS *10
/datum/latency_sweep/declared_entries(list/into)
	..(into)
	into += entry_block("code/library/containers/containment/latency_policy.dm", 43, /datum/latency_sweep)
	if(declare_block_skipped(into, /datum/latency_sweep))
		return
	into += entry_line(44)
	into += list(global.every(2 SECONDS, global.then(PROC_REF(sweep_step)), when = nameof(sweeping)))
"####),"actual generated complete declaration must retain its real current macro forms and closed call receipts");}
#[test]fn actual_original_generated_lookup_declaration_keeps_real_named_member_arguments(){assert!(census_first_group_receipt(r####"#define OTHER_DELETE_ME 2
/datum/lookup_read_scope/declared_entries(list/into)
	..(into)
	into += entry_block("code/engine/change/lookup_reads.dm", 22, /datum/lookup_read_scope)
	if(declare_block_skipped(into, /datum/lookup_read_scope))
		return
	into += entry_line(23)
	into += list(global.owns_many(nameof(bindings), /datum/lookup_read_binding))
	into += entry_line(24)
	into += list(global.ref_many(nameof(participants), /datum, on_other_deleted = OTHER_DELETE_ME))
"####),"actual generated complete declaration must retain its real current macro forms and closed call receipts");}

#[test]fn actual_original_census_observed_member_postfix_full_function_keeps_actual_producer_inputs(){assert!(census_first_group_receipt(r####"#define LAZYLEN(L) length(L)
#define UNSETEMPTY(L) do { if (L && !length(L)) L = null } while(0)
#define SLOT_OCCUPANCY_KEY "slot_occupancy"
#define PUBLISH_CHANGE(E, KEY) publish_key_changed(E, KEY)
/datum/ledger/proc/latent_set_count(datum/latent_entry/entry, n)
	// Fewer things than parked identities: the surplus things are gone for good.
	while(LAZYLEN(entry.handles) > max(0, n))
		entity_handle_release_parked(entry.handles[length(entry.handles)])
		entry.handles.len--
	used[entry.slot] -= entry.unit_cost * entry.count
	latent_total -= entry.count
	entry.count = max(0, n)
	entry.generation++
	if(entry.count)
		entry.snapshot = dq_latent_scale_snapshot(dq_latent_type_snapshot(entry.path), entry.count)
		used[entry.slot] += entry.unit_cost * entry.count
		latent_total += entry.count
	else
		var/list/group = latent?[entry.slot]
		group -= entry
		if(!length(group))
			latent -= entry.slot
		UNSETEMPTY(latent)
		spent(entry)
	PUBLISH_CHANGE(holder(), SLOT_OCCUPANCY_KEY)
"####),"actual observed member_postfix whole function requires genuine completed Original receipt");}

#[test]fn actual_original_census_observed_unary_call_key_full_function_keeps_actual_producer_inputs(){assert!(census_first_group_receipt(r####"/datum/ledger/proc/sync()
	if(length(holder().contents) == tracked)
		return
	for(var/atom/movable/thing as anything in entry_things())
		if(thing.loc != holder())
			note_exit(thing)
	for(var/atom/movable/thing as anything in holder().contents)
		// A thing being deleted left its slot in destroy phase 4 (it keeps its loc until phase 7):
		// note_enter()'s teardown guard never re-adopts it.
		if(!entries[slot_known(thing)])
			note_enter(thing)
"####),"actual observed unary_call_key whole function requires genuine completed Original receipt");}

#[test]fn actual_original_census_observed_right_conditional_full_function_keeps_actual_producer_inputs(){assert!(census_first_group_receipt(r####"#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define CONSCIOUS   0
/datum/lleill_contact_review/proc/why_not()
	return QDELETED(actor) ? "gone" : actor.stat != CONSCIOUS ? "not conscious" : null
"####),"actual observed right_conditional whole function requires genuine completed Original receipt");}

#[test]fn actual_original_census_observed_implicit_new_named_full_function_keeps_actual_producer_inputs(){assert!(census_first_group_receipt(r####"#define CONFIG_MAX_CACHED_LOG_ENTRIES 1000
/datum/log_category/proc/create_entry(message, list/data, list/semver_store)
	var/datum/log_entry/entry = new(
		// world state contains raw timestamp
		timestamp = logger.human_readable_timestamp(),
		category = category,
		message = message,
		flags = entry_flags,
		data = data,
		semver_store = semver_store,
	)

	write_entry(entry)
	set_entry_count(entry_count + 1)

	if(entry_count <= CONFIG_MAX_CACHED_LOG_ENTRIES)
		rel_add(src, nameof(log_ring), entry)
	else
		rel_add(src, nameof(log_ring), entry, ring_write_index)
	ring_write_index++
	if(ring_write_index > CONFIG_MAX_CACHED_LOG_ENTRIES)
		ring_write_index = 1
"####),"actual observed implicit_new_named whole function requires genuine completed Original receipt");}

#[test]fn actual_original_type_trait_of_full_body_preserves_real_return_marker_and_nested_safe_index(){assert!(census_first_group_receipt(r####"#define READS_FROM(args...)
#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
#else
	#define RETURN_TYPE(X)
#endif
/proc/type_trait_of(datum/holder, kind)
	READS_FROM() // the domain's reader names the key it reads as (READS_AS), and its setters publish it
	RETURN_TYPE(/datum/type_trait)
	if(isnull(holder))
		return type_trait_default(kind) // a read through an empty slot (worn?.x): the kind's defaults
	var/datum/type_trait/own = per_type_copy_peek(holder, kind)
	if(own)
		return own
	if(!SSstatic_entries.ready)
		static_entries_ensure("type_trait_of([holder.type], [kind])")
	var/datum/type_trait/shared = GLOB.type_trait_tables[kind]?[holder.type]
	if(shared)
		return shared
	return type_trait_default(kind)

"####),"actual type_trait_of whole producer requires Original Available receipt");}

#[test]fn actual_original_dynamic_new_map_new_full_function_keeps_actual_constructor_effect(){assert!(census_first_group_receipt(r####"/datum/map/New()
	..()
	if(zlevel_datum_type)
		for(var/type in subtypesof(zlevel_datum_type))
			new type(src)
	if(!map_levels?.len)
		map_levels = station_levels.Copy()
	if(!mappable_levels?.len)
		mappable_levels = station_levels.Copy()
	if(!persist_levels?.len)
		persist_levels = station_levels.Copy()
	if(!mappable_levels?.len)
		mappable_levels = station_levels.Copy()
	if(!allowed_jobs || !allowed_jobs.len)
		allowed_jobs = subtypesof(/datum/job)
	if(default_skybox) //Type was specified
		default_skybox = new default_skybox()
	else
		default_skybox = new()

"####),"actual full map_new producer requires Original constructor effect receipt");}

#[test]fn actual_original_dynamic_new_map_stub_full_function_keeps_actual_constructor_effect(){assert!(census_first_group_receipt(r####"/datum/map_template/common_lateload/on_map_loaded(z)
	if(!associated_map_datum || !ispath(associated_map_datum))
		return
	new associated_map_datum(using_map, z)

"####),"actual full map_stub producer requires Original constructor effect receipt");}

#[test]fn actual_original_dynamic_new_glass_build_full_function_keeps_actual_constructor_effect(){assert!(census_first_group_receipt(r####"#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))
#define isrobot(A)		istype(A, /mob/living/silicon/robot)
#define PROC_REF(X) (nameof(.proc/##X))
#define span_warning(str) ("<span class='warning'>" + str + "</span>")
#define LAZYACCESS(L, I) ((L) ? (isnum(I) ? ((I) > 0 && (I) <= length(L) ? (L)[I] : null) : (L)[I]) : null)
/datum/material/glass/proc/window_build_stage(mob/living/user, obj/item/stack/used_stack, answered, choice)

	if(!user || !used_stack || !created_window || !created_fulltile_window || !length(window_options))
		return 0

	if(!user.IsAdvancedToolUser())
		to_chat(user, span_warning("This task is too complex for your clumsy hands."))
		return 1

	var/turf/T = user.loc
	if(!istype(T))
		to_chat(user, span_warning("You must be standing on open flooring to build a window."))
		return 1

	var/message = "Sheet-[used_stack.name] ([used_stack.get_amount()] sheet\s left)"
	if(!answered)
		open_request(src, /datum/prompt/choice/glass_window_build, PROC_REF(window_choice_entered), answerer = user, subject = used_stack, question = message, choices = window_options)
		return

	if(!choice || !used_stack || !user || (used_stack.loc != user && !isrobot(user)) || user.stat || user.loc != T)
		return 1

	// Get data for building windows here.
	var/list/possible_directions = GLOB.cardinal.Copy()
	var/window_count = 0
	for (var/obj/structure/window/check_window in user.loc)
		window_count++
		possible_directions  -= check_window.dir
	for (var/obj/structure/windoor_assembly/check_assembly in user.loc)
		window_count++
		possible_directions -= check_assembly.dir
	for (var/obj/machinery/door/window/check_windoor in user.loc)
		window_count++
		possible_directions -= check_windoor.dir

	// Get the closest available dir to the user's current facing.
	var/build_dir = SOUTHWEST //Default to southwest for fulltile windows.
	var/failed_to_build

	if(window_count >= 4)
		failed_to_build = 1
	else
		if(choice in list("One Direction","Windoor"))
			if(possible_directions.len)
				for(var/direction in list(user.dir, turn(user.dir,90), turn(user.dir,270), turn(user.dir,180)))
					if(direction in possible_directions)
						build_dir = direction
						break
			else
				failed_to_build = 1
	if(failed_to_build)
		to_chat(user, span_warning("There is no room in this location."))
		return 1

	var/build_path = /obj/structure/windoor_assembly
	var/sheets_needed = LAZYACCESS(window_options, choice)
	if(choice == "Windoor")
		if(is_reinforced())
			build_path = /obj/structure/windoor_assembly/secure
	else if(choice == "Full Window")
		build_path = created_fulltile_window
	else
		build_path = created_window

	if(used_stack.get_amount() < sheets_needed)
		to_chat(user, span_warning("You need at least [sheets_needed] sheets to build this."))
		return 1

	// Build the structure and update sheet count etc.
	used_stack.use(sheets_needed)
	new build_path(T, build_dir, 1)
	return 1

"####),"actual full glass_build producer requires Original constructor effect receipt");}

#[test]fn actual_original_associative_call_key_base_map_full_function(){assert!(census_first_group_receipt(r####"#define ACCESS_ATMOSPHERICS 24
#define ACCESS_BAR 25
#define ACCESS_CARGO 31
#define ACCESS_CENT_SPECOPS 103 //Special Ops.
#define ACCESS_ENGINE_EQUIP 11
#define ACCESS_EXPLORER 43
#define ACCESS_HEADS 19
#define ACCESS_HYDROPONICS 35
#define ACCESS_JANITOR 26
#define ACCESS_KITCHEN 28
#define ACCESS_LIBRARY 37
#define ACCESS_MEDICAL_EQUIP 66
#define ACCESS_MINING_STATION 54
#define ACCESS_ROBOTICS 29
#define ACCESS_SECURITY 1
#define ACCESS_SYNTH 199
#define ACCESS_TOX 7
#define ACCESS_XENOBIOLOGY 55
#define AI_FREQ 1343
#define BDCM_FREQ 1483
#define COMM_FREQ 1353
#define ENG_FREQ 1357
#define ENT_FREQ 1461 //entertainment frequency. This is not a diona exclusive frequency.
#define ERT_FREQ 1345
#define EXP_FREQ 1361
#define MED_FREQ 1355
#define MED_I_FREQ 1485
#define PUB_FREQ 1459
#define SCI_FREQ 1351
#define SEC_FREQ 1359
#define SEC_I_FREQ 1475
#define SRV_FREQ 1349
#define SUP_FREQ 1347
/datum/map/proc/default_internal_channels()
	return list(
		num2text(PUB_FREQ)   = list(),
		num2text(AI_FREQ)  = list(ACCESS_SYNTH),
		num2text(ENT_FREQ)   = list(),
		num2text(ERT_FREQ) = list(ACCESS_CENT_SPECOPS),
		num2text(COMM_FREQ)= list(ACCESS_HEADS),
		num2text(ENG_FREQ) = list(ACCESS_ENGINE_EQUIP, ACCESS_ATMOSPHERICS),
		num2text(MED_FREQ) = list(ACCESS_MEDICAL_EQUIP),
		num2text(MED_I_FREQ)=list(ACCESS_MEDICAL_EQUIP),
		num2text(BDCM_FREQ) =list(ACCESS_SECURITY),
		num2text(SEC_FREQ) = list(ACCESS_SECURITY),
		num2text(SEC_I_FREQ)=list(ACCESS_SECURITY),
		num2text(SCI_FREQ) = list(ACCESS_TOX,ACCESS_ROBOTICS,ACCESS_XENOBIOLOGY),
		num2text(SUP_FREQ) = list(ACCESS_CARGO, ACCESS_MINING_STATION),
		num2text(SRV_FREQ) = list(ACCESS_JANITOR, ACCESS_LIBRARY, ACCESS_HYDROPONICS, ACCESS_BAR, ACCESS_KITCHEN),
		num2text(EXP_FREQ) = list(ACCESS_EXPLORER)
	)
"####),"same actual full function requires current completed Original receipt");}

#[test]fn actual_original_associative_call_key_common_preset_full_function(){assert!(census_first_group_receipt(r####"#define ACCESS_ATMOSPHERICS 24
#define ACCESS_BAR 25
#define ACCESS_CARGO 31
#define ACCESS_CENT_SPECOPS 103 //Special Ops.
#define ACCESS_ENGINE_EQUIP 11
#define ACCESS_EXPLORER 43
#define ACCESS_HEADS 19
#define ACCESS_HYDROPONICS 35
#define ACCESS_JANITOR 26
#define ACCESS_KITCHEN 28
#define ACCESS_LIBRARY 37
#define ACCESS_MEDICAL_EQUIP 66
#define ACCESS_MINING_STATION 54
#define ACCESS_ROBOTICS 29
#define ACCESS_SECURITY 1
#define ACCESS_SYNTH 199
#define ACCESS_TOX 7
#define ACCESS_XENOBIOLOGY 55
#define AI_FREQ 1343
#define BDCM_FREQ 1483
#define COMM_FREQ 1353
#define ENG_FREQ 1357
#define ENT_FREQ 1461 //entertainment frequency. This is not a diona exclusive frequency.
#define ERT_FREQ 1345
#define EXP_FREQ 1361
#define MED_FREQ 1355
#define MED_I_FREQ 1485
#define PUB_FREQ 1459
#define SCI_FREQ 1351
#define SEC_FREQ 1359
#define SEC_I_FREQ 1475
#define SRV_FREQ 1349
#define SUP_FREQ 1347
/datum/map/southern_cross/default_internal_channels()
	return list(
		num2text(PUB_FREQ) = list(),
		num2text(AI_FREQ)  = list(ACCESS_SYNTH),
		num2text(ENT_FREQ) = list(),
		num2text(ERT_FREQ) = list(ACCESS_CENT_SPECOPS),
		num2text(COMM_FREQ)= list(ACCESS_HEADS),
		num2text(ENG_FREQ) = list(ACCESS_ENGINE_EQUIP, ACCESS_ATMOSPHERICS),
		num2text(MED_FREQ) = list(ACCESS_MEDICAL_EQUIP),
		num2text(MED_I_FREQ)=list(ACCESS_MEDICAL_EQUIP),
		num2text(BDCM_FREQ) =list(ACCESS_SECURITY),
		num2text(SEC_FREQ) = list(ACCESS_SECURITY),
		num2text(SEC_I_FREQ)=list(ACCESS_SECURITY),
		num2text(SCI_FREQ) = list(ACCESS_TOX,ACCESS_ROBOTICS,ACCESS_XENOBIOLOGY),
		num2text(SUP_FREQ) = list(ACCESS_CARGO, ACCESS_MINING_STATION),
		num2text(SRV_FREQ) = list(ACCESS_JANITOR, ACCESS_LIBRARY, ACCESS_HYDROPONICS, ACCESS_BAR, ACCESS_KITCHEN),
		num2text(EXP_FREQ) = list(ACCESS_EXPLORER)
	)
"####),"same actual full function requires current completed Original receipt");}

#[test]fn actual_original_associative_call_key_station_preset_full_function(){assert!(census_first_group_receipt(r####"#define ACCESS_ATMOSPHERICS 24
#define ACCESS_CARGO 31
#define ACCESS_CENT_SPECOPS 103 //Special Ops.
#define ACCESS_ENGINE_EQUIP 11
#define ACCESS_EXPLORER 43
#define ACCESS_HEADS 19
#define ACCESS_HYDROPONICS 35
#define ACCESS_JANITOR 26
#define ACCESS_MEDICAL_EQUIP 66
#define ACCESS_ROBOTICS 29
#define ACCESS_SECURITY 1
#define ACCESS_SYNTH 199
#define ACCESS_TOX 7
#define ACCESS_XENOBIOLOGY 55
#define AI_FREQ 1343
#define COMM_FREQ 1353
#define ENG_FREQ 1357
#define ENT_FREQ 1461 //entertainment frequency. This is not a diona exclusive frequency.
#define ERT_FREQ 1345
#define EXP_FREQ 1361
#define MED_FREQ 1355
#define MED_I_FREQ 1485
#define PUB_FREQ 1459
#define SCI_FREQ 1351
#define SEC_FREQ 1359
#define SEC_I_FREQ 1475
#define SRV_FREQ 1349
#define SUP_FREQ 1347
/datum/map/southern_cross/default_internal_channels()
	return list(
		num2text(PUB_FREQ) = list(),
		num2text(AI_FREQ)  = list(ACCESS_SYNTH),
		num2text(ENT_FREQ) = list(),
		num2text(ERT_FREQ) = list(ACCESS_CENT_SPECOPS),
		num2text(COMM_FREQ)= list(ACCESS_HEADS),
		num2text(ENG_FREQ) = list(ACCESS_ENGINE_EQUIP, ACCESS_ATMOSPHERICS),
		num2text(MED_FREQ) = list(ACCESS_MEDICAL_EQUIP),
		num2text(MED_I_FREQ)=list(ACCESS_MEDICAL_EQUIP),
		num2text(SEC_FREQ) = list(ACCESS_SECURITY),
		num2text(SEC_I_FREQ)=list(ACCESS_SECURITY),
		num2text(SCI_FREQ) = list(ACCESS_TOX,ACCESS_ROBOTICS,ACCESS_XENOBIOLOGY),
		num2text(SUP_FREQ) = list(ACCESS_CARGO),
		num2text(SRV_FREQ) = list(ACCESS_JANITOR, ACCESS_HYDROPONICS),
		num2text(EXP_FREQ) = list(ACCESS_EXPLORER)
	)
"####),"same actual full function requires current completed Original receipt");}

#[test]fn actual_original_try_switch_catch_full_map_load_advance(){assert!(census_first_group_receipt(r####"#define JOB_MORE 1
#define MAP_LOAD_BEGIN 4
#define MAP_LOAD_CACHE 3
#define MAP_LOAD_INIT 6
#define MAP_LOAD_PARSE 2
#define MAP_LOAD_PLACE 5
#define MAP_LOAD_POST 7
#define MAP_LOAD_PREPARE 1
#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
/datum/map_load/proc/advance(sync)
	steps++
	var/datum/map_template/T = template
	if(!istype(T) || QDELETED(T))
		log_mapping("map load: its template was deleted; dropping the load.")
		return abandon()
	var/more = JOB_MORE
	// A runtime in a step must not leave the load (and SSatoms' load state) half open, or every later load would wait on it.
	try
		switch(phase)
			if(MAP_LOAD_PREPARE)
				more = do_prepare(T, sync)
			if(MAP_LOAD_PARSE)
				more = do_parse(sync)
			if(MAP_LOAD_CACHE)
				more = do_cache(sync)
			if(MAP_LOAD_BEGIN)
				more = do_begin(T, sync)
			if(MAP_LOAD_PLACE)
				more = do_place(sync)
			if(MAP_LOAD_INIT)
				more = do_init(T, sync)
			if(MAP_LOAD_POST)
				more = do_post(T)
	catch(var/exception/e)
		dq_report_caught(e, "map load ([T.name], phase [phase])")
		return abandon()
	return more
"####),"same actual full function requires current completed Original receipt");}

#[test]fn actual_original_try_switch_catch_close_isolation_requires_real_provider(){assert!(census_first_group_receipt(r####"/proc/probe(phase)
    try
        switch(phase)
            if(1)
                return 1
    catch(var/exception/e)
        return 0
"####),"try, switch, case and catch must independently earn genuine source receipts");}

#[test]
fn actual_original_generated_member_index_postfix_first_leaf_has_native_receipt(){
 assert!(census_first_group_receipt(r####"/proc/generated_member_index_postfix_leaf()
	GLOB.boot_phase_counts["cow list: first write copied the starting list"]++
"####),"actual census91 generated first leaf requires Original Available receipt");
}

#[test]fn actual_original_generated_tracked_list_full_adder_keeps_real_boot_count_indexed_update(){assert!(census_first_group_receipt(r####"#define BOOT_PHASE_COUNT(what) if(GLOB.boot_phase_on) GLOB.boot_phase_counts[what]++
/datum/lore/organization/proc/add_ship_names(x)
	if(!ship_names_version && ship_names && ship_names == cow_table(src, "ship_names"))
		ship_names = ship_names.Copy()
		BOOT_PHASE_COUNT("cow list: first write copied the starting list")
	if(isnull(ship_names))
		ship_names = list()
	ship_names += x
	ship_names_version++
	tracked_changed(src, "ship_names")
	return TRUE
"####),"actual whole generated tracked list adder and boot macro must retain original grammar receipts");}

#[test]fn actual_original_pair_for_whole_auto_org_constructor_keeps_both_local_names(){assert!(census_first_group_receipt(r######"#define LAZYLEN(L) length(L)
/datum/lore/codex/category/auto_org/New(new_holder, new_parent)
	..(new_holder, new_parent)
	if(LAZYLEN(auto_keywords))
		keywords += auto_keywords
	for(var/path, value in GLOB.loremaster.organizations)
		var/datum/lore/organization/O = value
		if(!(istype(O, desired_type)))
			continue
		var/datum/lore/codex/page/P = new(holder(), src)
		if(!O.name) // Probably the base type, don't make a page for it.
			continue
		P.name = O.name
		P.keywords.Add(O.name, O.short_name)
		if(O.acronym)
			P.keywords.Add(O.acronym)
		P.data = O.desc
		rel_add(src, nameof(children), P)
"######),"same actual whole For function requires current Original body proof");}

#[test]fn actual_original_untyped_anything_for_whole_material_user_insert_keeps_actual_macros(){assert!(census_first_group_receipt(r######"#define MATCONTAINER_SILENT (1<<3)
#define MATERIAL_INSERT_ITEM_FAILURE 0
#define MATERIAL_INSERT_ITEM_NO_MATS -1
#define MATERIAL_INSERT_ITEM_NO_SPACE -2
#define MATERIAL_INSERT_ITEM_SUCCESS 1
#define PROC_REF(X) (nameof(.proc/##X))
#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))
#define span_warning(str) ("<span class='warning'>" + str + "</span>")
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
#define QDELING(X) (X.gc_destroyed)
#define SHEET_MATERIAL_AMOUNT 2000
#define QDELETED(X) (isnull(X) || QDELING(X))
/datum/material_container/proc/user_insert(obj/item/held_item, mob/living/user, atom/context = owner, requested_amount)
	set waitfor = FALSE // ALLOW(scheduler): waits on a prompt (tgui_input_number)
	. = 0

	//a stack to insert by a precise amount asks first; the answer runs this proc again with `requested_amount`
	if(isnull(requested_amount) && precise_insertion && istype(held_item, /obj/item/stack) && !item_rules_of(held_item).abstract && (!allowed_item_typecache || is_type_in_typecache(held_item, allowed_item_typecache)))
		var/obj/item/stack/asked_stack = held_item
		open_request(src, /datum/prompt/number/material_insert, PROC_REF(insert_amount_answered), answerer = user, question = "How much do you want to insert?", title = "Inserting [asked_stack.singular_name]s", default = asked_stack.amount, max_value = asked_stack.amount, timeout = 0, held_item = held_item, context = context)
		return

	//All items that do not have any contents
	var/list/obj/item/items = list(held_item)
	//is this the first item we are ever processing
	var/first_checks = TRUE
	//list of items to delete
	var/list/obj/item/to_delete = list()
	//The status of the last insert attempt
	var/inserted = 0
	//All messages to be displayed to chat
	var/list/chat_msgs = list()
	//differs from held_item when using TK
	var/obj/item/active_held = user.get_active_hand()

	while(items.len)
		//no point inserting more items
		if(inserted == MATERIAL_INSERT_ITEM_NO_SPACE)
			break

		//Pop the 1st item out from the list
		var/obj/item/target_item = items[1]
		items -= target_item

		//e.g. projectiles inside bullets are not objects
		if(!istype(target_item))
			continue
		//can't allow abstract items
		if(item_rules_of(target_item).abstract)
			continue
		// user defined conditions
		//item is either indestructible, not allowed for redemption or not in the allowed types
		if(allowed_item_typecache && !is_type_in_typecache(target_item, allowed_item_typecache))
			if(!(mat_container_flags & MATCONTAINER_SILENT))
				var/list/status_data = chat_msgs["[MATERIAL_INSERT_ITEM_FAILURE]"] || list()
				var/list/item_data = status_data[target_item.name] || list()
				item_data["count"] += 1
				status_data[target_item.name] = item_data
				chat_msgs["[MATERIAL_INSERT_ITEM_FAILURE]"] = status_data

			//storage items usually come here
			//this is so players can insert items from their bags into machines for convinience
			if(!contents_count(target_item))
				continue
		//at this point we can check if we have enough for all items & other stuff
		if(first_checks)

			//anything that isn't a stack cannot be split so find out if we have enough space, we don't want to consume half the contents of an object & leave it in a broken state
			//for duffle bags and other storage items we can check for space 1 item at a time
			if(!istype(target_item, /obj/item/stack))
				var/total_amount = 0
				for(var/obj/item/weapon as anything in target_item.get_all_contents_type(/obj/item))
					total_amount += get_item_material_amount(weapon)
				if(!has_space(total_amount))
					if(!(mat_container_flags & MATCONTAINER_SILENT))
						to_chat(user, span_warning("[owner] does not have enough space for [target_item]!"))
					return

			first_checks = FALSE

		//if stack, check if we want to read precise amount of sheets to insert
		var/obj/item/stack/item_stack = null
		if(istype(target_item, /obj/item/stack) && target_item == held_item && !isnull(requested_amount))
			var/atom/current_parent = owner
			item_stack = target_item
			if(!requested_amount || QDELETED(target_item) || QDELETED(user) || QDELETED(src))
				continue
			if(owner != current_parent || user.get_active_hand() != active_held)
				continue
			if(requested_amount != item_stack.amount) //only split if its not the whole amount
				target_item = fast_split_stack(item_stack, requested_amount) //split off the requested amount
			requested_amount = 0

		//is this item a stack and was it split by the player?
		var/was_stack_split = !isnull(item_stack) && item_stack != target_item
		//if it was split then item_stack has the reference to the original stack/item
		var/obj/item/original_item = was_stack_split ? item_stack : target_item
		//if this item is not the one the player is holding then don't remove it from their hand
		if(original_item != active_held)
			original_item = null
		if(!isnull(original_item) && !user.temporarilyRemoveItemFromInventory(original_item)) //remove from hand(if split remove the original stack else the target)
			return

		//insert the item
		var/item_name = target_item.name
		var/item_count = 1
		var/is_stack = FALSE
		var/obj/item/stack/the_stack
		if(istype(target_item, /obj/item/stack))
			the_stack = target_item
			item_name = the_stack.singular_name
			item_count = the_stack.amount
			is_stack = TRUE

		//we typically don't want to consume bags, boxes but only their contents. so we skip processing
		inserted = !istype(target_item, /obj/item/storage) ? insert_item(target_item, 1, context, is_stack) : 0
		if(inserted > 0)
			. += inserted
			inserted /= SHEET_MATERIAL_AMOUNT // display units inserted as sheets for improved readability

			//collect all messages to print later
			var/list/status_data = chat_msgs["[MATERIAL_INSERT_ITEM_SUCCESS]"] || list()
			var/list/item_data = status_data[item_name] || list()
			item_data["count"] += item_count
			item_data["amount"] += inserted
			item_data["stack"] = is_stack
			status_data[item_name] = item_data
			chat_msgs["[MATERIAL_INSERT_ITEM_SUCCESS]"] = status_data

			//delete the item or merge stacks if any left over
			if(is_stack)
				//player split it & machine further split that due to lack of space? merge with remaining stack
				if(!QDELETED(target_item) && was_stack_split)
					var/obj/item/stack/inserting_stack = target_item
					item_stack.add(inserting_stack.amount)
					consumed(inserting_stack, src)

				//was this the original item in the players hand? put what's left back in the player's hand
				if(!QDELETED(original_item))
					user.put_in_active_hand(original_item)

				//skip processing children & other stuff. irrelevant for stacks
				continue

			//queue the object for deletion
			to_delete += target_item
		else
			//collect all messages to print later
			var/list/status_data = chat_msgs["[inserted]"] || list()
			var/list/item_data = status_data[item_name] || list()
			item_data["count"] += item_count
			status_data[item_name] = item_data
			chat_msgs["[inserted]"] = status_data

			//player split the stack by the requested amount but even that split amount could not be salvaged. merge it back with the original
			if(was_stack_split)
				var/obj/item/stack/inserting_stack = target_item
				item_stack.add(inserting_stack.amount)
				consumed(inserting_stack, src)

			//was this the original item in the players hand? put it back because we coudn't salvage it
			if(!QDELETED(original_item))
				user.put_in_active_hand(original_item)

			//we can stop here as remaining items will fail to insert as well
			if(inserted == MATERIAL_INSERT_ITEM_NO_SPACE)
				break

			//we failed to process the item so don't bother going into its contents
			//but if we are dealing with storage items like bags, boxes etc then we make a exception
			if(!istype(target_item, /obj/item/storage))
				continue

		//If any mats were consumed we can proceed to delete the parent
		//If it has children then we will process them first in the 2nd round
		//This is done so we don't delete the children when the parent is consumed
		//We only do this on the 1st iteration so we don't re-iterate through its children again
		if(contents_count(target_item))
			//process children
			items += target_item.contents

	//we now summarize the chat msgs collected
	if(!(mat_container_flags & MATCONTAINER_SILENT))

		for(var/status as anything in chat_msgs)
			var/list/status_data = chat_msgs[status]

			for(var/item_name as anything in status_data)
				//read the params
				var/list/chat_data = status_data[item_name]
				var/count = chat_data["count"]
				var/amount = chat_data["amount"]

				//decode the message
				switch(text2num(status))
					if(MATERIAL_INSERT_ITEM_SUCCESS) //no problems full item was consumed
						if(chat_data["stack"])
							var/sheets = min(count, amount) //minimum between sheets inserted vs sheets consumed(values differ for alloys)
							to_chat(user, span_notice("[sheets > 1 ? "[sheets] " : ""][item_name][sheets > 1 ? "s were" : " was"] added to [owner]."))
						else
							to_chat(user, span_notice("[count > 1 ? "[count] " : ""][item_name][count > 1 ? "s" : ""], worth [amount] sheets, [count > 1 ? "were" : "was"] added to [owner]."))
					if(MATERIAL_INSERT_ITEM_NO_SPACE) //no space
						to_chat(user, span_warning("[owner] has no space to accept [item_name]!"))
					if(MATERIAL_INSERT_ITEM_NO_MATS) //no materials inside these items
						to_chat(user, span_warning("[item_name][count > 1 ? "s have" : " has"] no materials that can be accepted by [owner]!"))
					if(MATERIAL_INSERT_ITEM_FAILURE) //could be because the material type was not accepted or other stuff
						to_chat(user, span_warning("[item_name][count > 1 ? "s were" : " was"] rejected by [owner]!"))

	//finally delete the items
	for(var/obj/item/deleting as anything in to_delete)
		if(!QDELETED(deleting)) //deleting parents also delete their children so we check
			consumed(deleting, src)
"######),"same actual whole For function requires current Original body proof");}

#[test]fn actual_original_pair_for_source_provider_and_iterable_are_both_required(){assert!(census_first_group_receipt(r####"/proc/probe(entries)
    for(var/key,value in entries)
        consume(key,value)
"####),"same actual pair names and Original iterable");}
#[test]fn actual_original_untyped_declared_anything_for_keeps_real_local_and_iterable(){assert!(census_first_group_receipt(r####"/proc/probe(entries)
    for(var/status as anything in entries)
        consume(status)
"####),"same actual var/name/as/anything/In and Original iterable");}

#[test]fn actual_original_pair_break_continue_require_witnessed_loop_and_do_not_escape_scope(){
 assert!(census_first_group_receipt(r####"/proc/probe(entries)
    for(var/key,value in entries)
        if(key)
            continue
        break
    return
"####),"actual pair head, iterable and block lend their own break/continue context");
 assert!(!census_first_group_receipt(r####"/proc/probe(entries)
    for(var/key,value in entries)
        consume(key,value)
    continue
"####),"leaving the actual pair block restores the prior unproved loop context");
}

#[test]fn actual_original_set_dir_whole_function_requires_same_real_producer_receipt(){assert!(census_first_group_receipt(r####"/atom/movable/set_dir(newdir)
	. = ..(newdir)
	if(rx?.look_key || rel_watchers)
		rx_of(src).look_seen_dir = dir
	if(riding_datum)
		riding_datum.handle_vehicle_offsets()
"####),"actual whole movable set_dir requires genuine Original body receipt");}

#[test]fn actual_original_set_dir_call_result_member_target_isolated_source(){assert!(census_first_group_receipt(r####"/proc/probe()
    rx_of(src).look_seen_dir = dir
"####),"isolated exact production member write must be proven by actual producer");}

#[test]fn actual_original_safe_call_chain_write_whole_pull_released(){assert!(census_first_group_receipt(r####"#define PUBLISH_CHANGE(E, KEY) publish_key_changed(E, KEY)
#define MOB_KEY_STATUS "mob_status"
/atom/movable/proc/pull_released(atom/movable/was_pulled)
	if(!ismob(src))
		return
	var/mob/M = src
	PUBLISH_CHANGE(M, MOB_KEY_STATUS)
	if(hud_of(M)?.pullin)
		hud_of(M)?.pullin?.icon_state = "pull0"
"####),"actual whole pull_released and exact publication macros require genuine receipt");}
#[test]fn actual_original_safe_call_chain_write_real_hud_assignment_isolates(){
 for source in [r####"/proc/probe(M)
    hud_of(M)?.pullin?.icon_state = "pull1"
"####,r####"/proc/probe(M)
    hud_of(M)?.pullin?.icon_state = "pull0"
"####,r####"/proc/probe(C)
    hud_of(C)?.internals?.icon_state = "internal0"
"####]{assert!(census_first_group_receipt(source),"actual observed safe-call chain: {source}");}
}

#[test]fn actual_original_click_router_inspect_whole_function_keeps_current_table_receiver(){assert!(census_first_group_receipt(r######"#ifdef SHARED_CACHE_STATS
#define CACHED_FAST(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) (++_sch_##N && (I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K, ##A))
#else
#define CACHED_FAST(N, K) (_scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) ((I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (_scs_##N[K] || _sc_##N.miss(K, ##A))
#endif
/// The counted form, whatever the build (the benchmark's comparison arm).
#define CACHED_COUNTED(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))

#if (defined(UNIT_TESTS) && !defined(BENCHMARK)) || defined(SPACEMAN_DMM)
// Test builds: every hit is verified against the snapshot taken at build time. A benchmark build measures the release path instead.
#define CACHED(N, K) _sc_##N.guarded(K)
#define CACHED_KEY(N, K, A...) _sc_##N.guarded(K, ##A)
#define CACHED_INT(N, I) _sc_##N.guarded_int(I)
#else
#define CACHED(N, K) CACHED_FAST(N, K)
#define CACHED_KEY(N, K, A...) _CACHED_KEY_FAST(N, K, ##A)
#define CACHED_INT(N, I) CACHED_INT_FAST(N, I)
#endif

#define TYPE_TABLE_GET(I, N) CACHED_KEY(tt_##N, (I).type, I)
#define INPUT_ACTION_INSPECT "inspect"
#define INPUT_ACTION_ALTERNATE "alternate"
#define INPUT_ACTION_SWAP_HANDS "swap_hands"
#define span_boldnotice(str) ("<span class='boldnotice'>" + str + "</span>")
#define span_info(str) ("<span class='info'>" + str + "</span>")
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
#define SCRN_OBJ_DEFAULT "default"
#define SCREEN_LOC "screen-loc"
#define get_turf(A) get_step(A,0)
/atom/movable/screen/alert/proc/prepare_alert_click(mob/user, params)
	if(GLOB.input_router.click_is(params, TYPE_TABLE_GET(GLOB.input_router, shift_table), INPUT_ACTION_INSPECT)) // screen objects don't do the normal Click() stuff so we'll cheat
		to_chat(user,span_boldnotice(name) + " - " + span_info(desc))
		return TRUE
	var/obj/master = master_ref
	if(master)
		return master
"######),"whole actual click router producer must retain Original Available receipt");}
#[test]fn actual_original_click_router_alternate_whole_function_keeps_current_table_receiver(){assert!(census_first_group_receipt(r######"#ifdef SHARED_CACHE_STATS
#define CACHED_FAST(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) (++_sch_##N && (I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K, ##A))
#else
#define CACHED_FAST(N, K) (_scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) ((I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (_scs_##N[K] || _sc_##N.miss(K, ##A))
#endif
/// The counted form, whatever the build (the benchmark's comparison arm).
#define CACHED_COUNTED(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))

#if (defined(UNIT_TESTS) && !defined(BENCHMARK)) || defined(SPACEMAN_DMM)
// Test builds: every hit is verified against the snapshot taken at build time. A benchmark build measures the release path instead.
#define CACHED(N, K) _sc_##N.guarded(K)
#define CACHED_KEY(N, K, A...) _sc_##N.guarded(K, ##A)
#define CACHED_INT(N, I) _sc_##N.guarded_int(I)
#else
#define CACHED(N, K) CACHED_FAST(N, K)
#define CACHED_KEY(N, K, A...) _CACHED_KEY_FAST(N, K, ##A)
#define CACHED_INT(N, I) CACHED_INT_FAST(N, I)
#endif

#define TYPE_TABLE_GET(I, N) CACHED_KEY(tt_##N, (I).type, I)
#define INPUT_ACTION_INSPECT "inspect"
#define INPUT_ACTION_ALTERNATE "alternate"
#define INPUT_ACTION_SWAP_HANDS "swap_hands"
#define span_boldnotice(str) ("<span class='boldnotice'>" + str + "</span>")
#define span_info(str) ("<span class='info'>" + str + "</span>")
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
#define SCRN_OBJ_DEFAULT "default"
#define SCREEN_LOC "screen-loc"
#define get_turf(A) get_step(A,0)
/atom/movable/screen/button_palette/click_with_actor(mob/user, location, control, params)
	if(!can_use(user))
		return

	if(GLOB.input_router.click_is(params, TYPE_TABLE_GET(GLOB.input_router, alternate_table), INPUT_ACTION_ALTERNATE))
		for(var/datum/action/action as anything in user.actions) // Reset action positions to default
			for(var/atom/movable/screen/movable/action_button/button as anything in action.viewers)
				var/datum/hud/hud = button.our_hud
				hud?.position_action(button, SCRN_OBJ_DEFAULT)
		to_chat(user, span_notice("Action button positions have been reset."))
		return TRUE

	set_expanded(!expanded)
"######),"whole actual click router producer must retain Original Available receipt");}
#[test]fn actual_original_click_router_classify_whole_function_keeps_current_table_receiver(){assert!(census_first_group_receipt(r######"#ifdef SHARED_CACHE_STATS
#define CACHED_FAST(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) (++_sch_##N && (I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K, ##A))
#else
#define CACHED_FAST(N, K) (_scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) ((I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (_scs_##N[K] || _sc_##N.miss(K, ##A))
#endif
/// The counted form, whatever the build (the benchmark's comparison arm).
#define CACHED_COUNTED(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))

#if (defined(UNIT_TESTS) && !defined(BENCHMARK)) || defined(SPACEMAN_DMM)
// Test builds: every hit is verified against the snapshot taken at build time. A benchmark build measures the release path instead.
#define CACHED(N, K) _sc_##N.guarded(K)
#define CACHED_KEY(N, K, A...) _sc_##N.guarded(K, ##A)
#define CACHED_INT(N, I) _sc_##N.guarded_int(I)
#else
#define CACHED(N, K) CACHED_FAST(N, K)
#define CACHED_KEY(N, K, A...) _CACHED_KEY_FAST(N, K, ##A)
#define CACHED_INT(N, I) CACHED_INT_FAST(N, I)
#endif

#define TYPE_TABLE_GET(I, N) CACHED_KEY(tt_##N, (I).type, I)
#define INPUT_ACTION_INSPECT "inspect"
#define INPUT_ACTION_ALTERNATE "alternate"
#define INPUT_ACTION_SWAP_HANDS "swap_hands"
#define span_boldnotice(str) ("<span class='boldnotice'>" + str + "</span>")
#define span_info(str) ("<span class='info'>" + str + "</span>")
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
#define SCRN_OBJ_DEFAULT "default"
#define SCREEN_LOC "screen-loc"
#define get_turf(A) get_step(A,0)
/atom/movable/screen/click_catcher/proc/resolve_click_with_actor(mob/user, params)
	var/list/P = params2list(params)
	switch(GLOB.input_router.classify(P, TYPE_TABLE_GET(GLOB.input_router, click_catcher_table)))
		if(INPUT_ACTION_SWAP_HANDS)
			if(istype(user, /mob/living/carbon))
				var/mob/living/carbon/C = user
				C.swap_hand()
				return 1
	var/turf/T = get_turf(user)
	if(T)
		T = screen_loc2turf(P[SCREEN_LOC], T)
		if(T)
			if(GLOB.input_router.classify(P, TYPE_TABLE_GET(GLOB.input_router, shift_table)) == INPUT_ACTION_INSPECT)
				user.face_atom(T)
				return 1
			return T
	return 1
"######),"whole actual click router producer must retain Original Available receipt");}

#[test]fn actual_original_whole_get_ability_by_instance_keeps_authentic_trailing_parameter_path(){assert!(census_first_group_receipt(r####"/atom/movable/screen/movable/ability_master/proc/get_ability_by_instance(obj/instance/)
	for(var/atom/movable/screen/ability/obj_based/O in ability_objects)
		if(O.object() == instance)
			return O
	return null
"####));}

#[test]
fn actual_original_setupgenetics_whole_physical_function_keeps_real_warning_unlint_macros(){assert!(census_first_group_receipt(r########"/**
* SpacemanDMM dreamchecker extensions for suite 1.7
* <https://github.com/SpaceManiac/SpacemanDMM/tree/suite-1.7/src/dreamchecker>
*/

#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
	#define SHOULD_CALL_PARENT(X) set SpacemanDMM_should_call_parent = X
	#define UNLINT(X) SpacemanDMM_unlint(X)
	#define SHOULD_NOT_OVERRIDE(X) set SpacemanDMM_should_not_override = X
	#define SHOULD_NOT_SLEEP(X) set SpacemanDMM_should_not_sleep = X
	#define SHOULD_BE_PURE(X) set SpacemanDMM_should_be_pure = X
	#define PRIVATE_PROC(X) set SpacemanDMM_private_proc = X
	#define PROTECTED_PROC(X) set SpacemanDMM_protected_proc = X
	#define CAN_BE_REDEFINED(X) set SpacemanDMM_can_be_redefined = X
	#define VAR_FINAL var/SpacemanDMM_final
	#define VAR_PRIVATE var/SpacemanDMM_private
	#define VAR_PROTECTED var/SpacemanDMM_protected
#else
	#define RETURN_TYPE(X)
	#define SHOULD_CALL_PARENT(X)
	#define UNLINT(X) X
	#define SHOULD_NOT_OVERRIDE(X)
	#define SHOULD_NOT_SLEEP(X)
	#define SHOULD_BE_PURE(X)
	#define PRIVATE_PROC(X)
	#define PROTECTED_PROC(X)
	#define CAN_BE_REDEFINED(X)
	#define VAR_FINAL var
	#define VAR_PRIVATE var
	#define VAR_PROTECTED var
#endif

#define WARNING(MSG) warning("[MSG] in [__FILE__] at line [__LINE__] src: [UNLINT(src)] usr: [usr].")
#define LAZYLEN(L) length(L)
#define DNA_SE_LENGTH 93 // Traitgenes (Expanded from 49 to 84, there have been a considerable expansion of genes. // Upped to 93. NOTE: Ensure it's increased when there is a conflict here! Thanks!
/proc/setupgenetics(list/trait_list)
	if(!trait_list)
		return
	var/list/blocks_remaining = dna_assignable_blocks()
	for(var/I in blocks_remaining)
		GLOB.assigned_blocks[I] = "" // setup a clean list
	for(var/TI in trait_list)
		var/datum/trait/T = trait_list[TI]
		if(T.is_genetrait)
			if(blocks_remaining.len <= 0)
				CRASH("DNA2: Ran out of usable blocks! DNA_SE_LENGTH limit is [DNA_SE_LENGTH]. Raise it if you need more!")
			// Init
			var/datum/gene/trait/G = new /datum/gene/trait()
			G.block = pick(blocks_remaining)
			var/tex = uppertext(T.name)
			G.name = "[copytext(tex,1,min( 8, length(tex)+1 ))]:[G.block]"
			rel_set(T, nameof(T.linked_gene), G)
			GLOB.dna_activity_bounds[G.block] = T.activity_bounds
			// Handle global block data
			log_world("DNA2: Assigned [G.name] - Linked to trait [T.name].")
			GLOB.assigned_blocks[G.block] = G.name
			GLOB.trait_to_dna_genes[T.type] = G
			GLOB.dna_genes.Add(G)
			blocks_remaining.Remove(G.block)
			// Add traitgenes to good/bad gene lists for randomized mutation procs!
			if(istype(T,/datum/trait/neutral))
				GLOB.dna_genes_neutral.Add(G)
			else if(istype(T,/datum/trait/negative))
				GLOB.dna_genes_bad.Add(G)
			else
				GLOB.dna_genes_good.Add(G)
	log_world("DNA2: Created traitgenes with [blocks_remaining.len] remaining blocks. Used [DNA_SE_LENGTH - blocks_remaining.len] out of [DNA_SE_LENGTH] ")
	if(blocks_remaining.len < 10)
		WARNING("DNA2: Blocks remaining is less than 10. The DNA_SE_LENGTH should be raised in dna.dm.")
	// Run conflict-o-tron on each traitgene all other traits... Lets setup an initial database of conflicts.
	log_world("DNA2: Checking trait gene conflicts")
	for(var/datum/gene/trait/gene in GLOB.dna_genes)
		gene.has_conflict( GLOB.all_traits, FALSE) // Check all traits beforehand to build the conflict list, so all future checks can be done with a quick contents check
	log_world("DNA2: Initial Conflict summary")
	// This is to setup the initial segments for the gene editing machines to sort gene segments with.
	for(var/datum/gene/trait/gene in GLOB.dna_genes)
		if(LAZYLEN(gene.conflict_traits))
			var/summery = ""
			for(var/path in gene.conflict_traits)
				var/datum/trait/T = GLOB.all_traits[path]
				if(summery != "")
					summery += ", "
				summery += "[T.name]"
			log_world("DNA2: [gene.get_name()] - ([summery])")

/proc/warning(msg)
	msg = "## WARNING: [msg]"
	boot_noise_note(msg)
	log_world(msg)

"########),"whole actual setupgenetics syntax retains genuine Original receipt; semantic world is not synthesized");}

#[test]fn actual_original_call_result_keyword_real_trigger_statement(){assert!(census_first_group_receipt("/proc/probe(trigger_flags)\n    linked_action().Trigger(trigger_flags = trigger_flags)\n"));}
#[test]fn actual_original_safe_call_compound_real_screen_removal_statement(){assert!(census_first_group_receipt("/proc/probe()\n    holder()?.screen -= src\n"));}

#[test]fn actual_original_initial_string_settings_toggle_hardsuit_whole_verb(){assert!(census_first_group_receipt(r########"#define HARDSUIT_CLICK_ACTIONS list(INPUT_ACTION_SWAP_HANDS = "middle-click", INPUT_ACTION_ALTERNATE = "alt-click", INPUT_ACTION_PULL = "control-click")
#define INPUT_ACTION_SWAP_HANDS "swap_hands"
#define INPUT_ACTION_ALTERNATE "alternate"
#define INPUT_ACTION_PULL "pull"
#define VERB_CAT_OOC_GAME_SETTINGS "OOC.Game Settings"
/client/verb/toggle_hardsuit_mode()
	set name = "Toggle Hardsuit Activation Mode"
	set desc = "Switch between hardsuit activation modes."
	set category = VERB_CAT_OOC_GAME_SETTINGS

	var/list/actions = HARDSUIT_CLICK_ACTIONS
	var/index = actions.Find(hardsuit_click_action) + 1
	if(index > length(actions))
		index = 1
	hardsuit_click_action = actions[index]
	to_chat(src, "Hardsuit activation mode set to [actions[hardsuit_click_action]].")
"########),"whole actual verb static String initial settings must use their real Original VALUE receipt");}

#[test]fn actual_original_initial_static_string_settings_proc_and_escaped_literal_isolation(){assert!(census_first_group_receipt(r########"/proc/probe()
    set name=""
    set desc="Escaped \[value] stays literal"
    set category="Settings"
    return null
"########),"actual current staticString VALUE admits only root settings, including escaped-bracket text");}

#[test]fn actual_original_material_service_of_whole_function_safe_call_index(){assert!(census_first_group_receipt(r########"/**
* SpacemanDMM dreamchecker extensions for suite 1.7
* <https://github.com/SpaceManiac/SpacemanDMM/tree/suite-1.7/src/dreamchecker>
*/

#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
	#define SHOULD_CALL_PARENT(X) set SpacemanDMM_should_call_parent = X
	#define UNLINT(X) SpacemanDMM_unlint(X)
	#define SHOULD_NOT_OVERRIDE(X) set SpacemanDMM_should_not_override = X
	#define SHOULD_NOT_SLEEP(X) set SpacemanDMM_should_not_sleep = X
	#define SHOULD_BE_PURE(X) set SpacemanDMM_should_be_pure = X
	#define PRIVATE_PROC(X) set SpacemanDMM_private_proc = X
	#define PROTECTED_PROC(X) set SpacemanDMM_protected_proc = X
	#define CAN_BE_REDEFINED(X) set SpacemanDMM_can_be_redefined = X
	#define VAR_FINAL var/SpacemanDMM_final
	#define VAR_PRIVATE var/SpacemanDMM_private
	#define VAR_PROTECTED var/SpacemanDMM_protected
#else
	#define RETURN_TYPE(X)
	#define SHOULD_CALL_PARENT(X)
	#define UNLINT(X) X
	#define SHOULD_NOT_OVERRIDE(X)
	#define SHOULD_NOT_SLEEP(X)
	#define SHOULD_BE_PURE(X)
	#define PRIVATE_PROC(X)
	#define PROTECTED_PROC(X)
	#define CAN_BE_REDEFINED(X)
	#define VAR_FINAL var
	#define VAR_PRIVATE var
	#define VAR_PROTECTED var
#endif

/proc/material_service_of(obj/O)
	RETURN_TYPE(/datum/material_service)
	var/datum/material_assembly/assembly = capability_data(O)?[/datum/material_assembly]
	return assembly?.service
"########),"whole actual material_service_of source must obtain genuine Original syntax");}

#[test]fn actual_original_capability_data_safe_index_typepath_isolated_value(){assert!(census_first_group_receipt("/proc/probe(obj/O)\n    return capability_data(O)?[/datum/material_assembly]\n"),"actual direct-call receiver and absolute TypePath key, with no rewritten AST");}

#[test]fn actual_original_action_group_check_against_view_whole_diagnostic(){assert!(census_first_group_receipt(r########"/datum/action_group/proc/check_against_view()
	var/owner_view = owner()?.mymob()?.client?.view
	if(!owner_view)
		return
	// Unlikey as it is, we may have been changed. Want to start from our target position and fail down
	column_max = initial(column_max)
	// Convert our viewer's view var into a workable offset
	var/list/view_size = view_to_pixels(owner_view)

	// We're primarially concerned about width here, if someone makes us 1x2000 I wish them a swift and watery death
	var/furthest_screen_loc = ButtonNumberToScreenCoords(column_max - 1)
	var/list/offsets = screen_loc_to_offset(furthest_screen_loc, owner_view)
	if(offsets[1] > world.icon_size && offsets[1] < view_size[1] && offsets[2] > world.icon_size && offsets[2] < view_size[2]) // We're all good
		return

	for(column_max in column_max - 1 to 1 step -1) // Yes I could do this by unwrapping ButtonNumberToScreenCoords, but I don't feel like it
		var/tested_screen_loc = ButtonNumberToScreenCoords(column_max)
		offsets = screen_loc_to_offset(tested_screen_loc, owner_view)
		// We've found a valid max length, pack it in
		if(offsets[1] > world.icon_size && offsets[1] < view_size[1] && offsets[2] > world.icon_size && offsets[2] < view_size[2])
			break
	// Use our newly resized column max
	refresh_actions()
"########),"whole actual unknown-frontier function, no guessed leaf or synthesized semantic world");}

#[test]fn actual_original_action_group_reused_range_negative_step_isolated_diagnostic(){assert!(census_first_group_receipt("/proc/probe()\n    for(column_max in column_max-1 to 1 step -1)\n        break\n"),"isolated actual reused-name range with written step, not an invented local declaration");}

#[test]fn actual_original_relative_verb_unignore_answered_whole_callback(){assert!(census_first_group_receipt(r########"#define VERB_REF(X) (nameof(.verb/##X))
/client/proc/unignore_answered(datum/act/request/A)
	if(!A.answer)
		return
	world.push_usr(A.request.answerer, new /datum/callback(src, VERB_REF(unignore)), A.answer)
"########),"whole actual producer retains VERB_REF namespace and genuine Original syntax receipt");}

#[test]fn actual_original_relative_verb_ticket_help_answered_whole_callback(){assert!(census_first_group_receipt(r########"#define VERB_REF(X) (nameof(.verb/##X))
/client/proc/ticket_help_answered(datum/act/request/A)
	if(!A.answer)
		return
	SStgui.update_uis(src)
	switch(A.answer.captured["entry"])
		if("mentorhelp")
			return world.push_usr(A.request.answerer, new /datum/callback(src, VERB_REF(mentorhelp)), A.answer.captured["original_msg"], A.answer)
		if("adminhelp")
			return world.push_usr(A.request.answerer, new /datum/callback(src, VERB_REF(adminhelp)), A.answer.captured["original_msg"], A.answer)
		if("requesthelp")
			return world.push_usr(A.request.answerer, new /datum/callback(src, VERB_REF(requesthelp)), A.answer)
"########),"whole actual producer retains VERB_REF namespace and genuine Original syntax receipt");}

#[test]fn actual_original_relative_verb_attempt_auto_fit_viewport_whole_proc(){assert!(census_first_group_receipt(r########"#define VERB_REF(X) (nameof(.verb/##X))
#define SECONDS *10
#define CLOCK_WORLD 0
/client/proc/attempt_auto_fit_viewport()
	if(!prefs.read_preference(/datum/preference/toggle/auto_fit_viewport))
		return
	if(fully_created)
		fit_viewport() // its wingets go through DX-exec
	else //Delayed to avoid wingets from Login calls.
		after(src, 1 SECONDS, VERB_REF(fit_viewport), clock = CLOCK_WORLD)
"########),"whole actual producer retains VERB_REF namespace and genuine Original syntax receipt");}

#[test]fn actual_original_two_argument_locate_grille_condition_isolated_actual_leaf(){assert!(census_first_group_receipt("/proc/probe(turf/T)\n    if(!(locate(/obj/structure/grille,T)))\n        return null\n"),"isolated actual sec_camera_report condition uses genuine primary locate proof, not ordinary callee authority");}

#[test]fn actual_original_indexed_member_stream_ban_reason_and_identifier_key_isolation(){for source in["/proc/probe(reason)\n    GLOB.banlist[\"reason\"] << reason\n","/proc/probe(cleaned)\n    F[cleaned] << 1\n"]{assert!(census_first_group_receipt(source),"actual indexed stream leaf needs complete current expression and root role");}}

#[test]fn actual_original_torban_update_done_whole_callback_with_identifier_stream_key(){assert!(census_first_group_receipt(r########"#define TORFILE "data/ToR_ban.bdb"
#define span_filter_adminlog(str) ("<span class='filter_adminlog'>" + str + "</span>") // (Uses the chat message type directly)
/proc/ToRban_update_done(response_arg, error, requester_ckey)
	var/datum/http_response/response = response_arg
	if(error || !response?.body)
		log_world("ToR data update aborted: [error || "no data"].")
		return
	var/list/rawlist = splittext(response.body, "\n")
	if(rawlist.len)
		fdel(TORFILE)
		var/savefile/F = new(TORFILE)
		for( var/line in rawlist )
			if(!line)	continue
			if( copytext(line,1,12) == "ExitAddress" )
				var/cleaned = copytext(line,13,length(line)-19)
				if(!cleaned)	continue
				F[cleaned] << 1
		F["last_update"] << world.realtime
		log_world("ToR data updated!")
		var/client/requester = requester_ckey && GLOB.directory[requester_ckey]
		if(requester)
			to_chat(requester, span_filter_adminlog("ToRban updated."))
		return
	log_world("ToR data update aborted: no data.")
"########),"whole actual ToRban callback retains real macros and both stream key roles");}

#[test]fn actual_original_whole_airway_patency_table_numeric_associative_key(){assert!(census_first_group_receipt(r########"#define STAT_AIRWAY 100007
/datum/affliction/airway/proc/patency_table(datum/act/eval/A)
	return alist(STAT_AIRWAY = patency())
"########),"actual physical constructor keys use existing bounded VALUE proof");}

#[test]fn actual_original_whole_airway_factor_oracle_numeric_associative_key(){assert!(census_first_group_receipt(r########"#define STAT_AIRWAY 100007
/datum/affliction/airway/oracle_factors(alist/acc)
	acc = ..()
	return oracle_accumulate(acc, alist(STAT_AIRWAY = patency()), 1)
"########),"actual physical constructor keys use existing bounded VALUE proof");}

#[test]fn actual_original_whole_radiation_stage_table_prefab_keys(){assert!(census_first_group_receipt(r########"#define TYPE_TABLE(T, N, V...) T/_tt_##N() {return V}
TYPE_TABLE(/datum/affliction/acute_radiation, affliction_stages, list( \
	"Mild" = list( \
		"description" = "Early symptoms of radiation exposure — nausea and fatigue from a low-grade dose.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/nausea             = 80, \
			/datum/affliction_symptom/fatigue            = 80, \
			/datum/affliction_symptom/headache           = 50, \
			/datum/affliction_symptom/radiation_reading  = 95, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 3, \
	), \
	"Moderate" = list( \
		"description" = "Moderate radiation exposure — repeated vomiting, hair loss, and visible bruising as bone marrow function falters.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/nausea             = 95, \
			/datum/affliction_symptom/fatigue            = 90, \
			/datum/affliction_symptom/pallor             = 70, \
			/datum/affliction_symptom/headache           = 60, \
			/datum/affliction_symptom/dizziness          = 50, \
			/datum/affliction_symptom/skin_burns_minor   = 60, \
			/datum/affliction_symptom/radiation_reading  = 95, \
		), \
		"min_symptoms" = 3, \
		"max_symptoms" = 5, \
	), \
	"Severe" = list( \
		"description" = "Severe radiation exposure — multi-system failure approaches. Bone marrow function has effectively stopped; spontaneous bleeding follows.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/nausea             = 95, \
			/datum/affliction_symptom/fatigue            = 95, \
			/datum/affliction_symptom/pallor             = 90, \
			/datum/affliction_symptom/bleeding_visible   = 70, \
			/datum/affliction_symptom/confusion          = 60, \
			/datum/affliction_symptom/dizziness          = 60, \
			/datum/affliction_symptom/skin_burns_minor   = 80, \
			/datum/affliction_symptom/radiation_reading  = 95, \
		), \
		"min_symptoms" = 4, \
		"max_symptoms" = 6, \
	), \
))
"########),"actual physical constructor keys use existing bounded VALUE proof");}

#[test]fn actual_original_whole_brain_damage_stage_table_prefab_keys(){assert!(census_first_group_receipt(r########"#define ACTION_BLOCK_SPEECH     (1<<0)
#define ACTION_BLOCK_SURGERY    (1<<1)
#define STAT_ACCURACY 100001
#define STAT_ACTION_BLOCKS 100002
#define STAT_BP_SYSTOLIC 100042
#define STAT_HEART_RATE 100107
#define STAT_MOTOR_CONTROL 100136
#define STAT_O2_SAT 100142
#define STAT_SLOWDOWN 100173
#define TYPE_TABLE(T, N, V...) T/_tt_##N() {return V}
TYPE_TABLE(/datum/affliction/brain_damage, affliction_stages, list( \
	"Significant" = list( \
		"name" = "anoxic brain injury", \
		"description" = "Brain tissue starved of oxygen long enough to show neurological deficits — confusion, slowed cognition, impaired vision. Alkysine can repair the underlying damage.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/confusion            = 80, \
			/datum/affliction_symptom/blurred_vision       = 60, \
			/datum/affliction_symptom/dizziness            = 70, \
			/datum/affliction_symptom/unsteady_gait        = 60, \
			/datum/affliction_symptom/pupillary_asymmetry  = 50, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 4, \
	), \
	"Critical" = list( \
		"name" = "brain herniation", \
		"description" = "Cranial pressure has displaced brain tissue past the structures that contain it. Past this point, neurological function does not return.", \
		"always_spawns" = list(/datum/affliction/respiratory_arrest), \
		"symptom_pool" = list( \
			/datum/affliction_symptom/confusion      = 90, \
			/datum/affliction_symptom/blurred_vision = 80, \
			/datum/affliction_symptom/dizziness      = 80, \
			/datum/affliction_symptom/pallor         = 60, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 4, \
		"factors" = alist(STAT_SLOWDOWN = 2.5, STAT_ACCURACY = -60, STAT_MOTOR_CONTROL = 0.9, STAT_ACTION_BLOCKS = ACTION_BLOCK_SPEECH | ACTION_BLOCK_SURGERY, STAT_HEART_RATE = -20, STAT_BP_SYSTOLIC = -30, STAT_O2_SAT = -10), \
		"spontaneous_emotes" = list("collapse", "groan"), \
		"spontaneous_emote_prob" = 8, \
	), \
))
"########),"actual physical constructor keys use existing bounded VALUE proof");}

#[test]fn actual_original_whole_burn_shock_stage_table_prefab_keys(){assert!(census_first_group_receipt(r########"#define STAT_ACCURACY 100001
#define STAT_BP_DIASTOLIC 100041
#define STAT_BP_SYSTOLIC 100042
#define STAT_CIRCULATION 100049
#define STAT_HEART_RATE 100107
#define STAT_MOTOR_CONTROL 100136
#define STAT_SLOWDOWN 100173
#define TYPE_TABLE(T, N, V...) T/_tt_##N() {return V}
TYPE_TABLE(/datum/affliction/burn_shock, affliction_stages, list( \
	"Stage 1" = list( \
		"symptom_pool" = list( \
			/datum/affliction_symptom/pallor = 70, \
			/datum/affliction_symptom/chills = 50, \
		), \
		"min_symptoms" = 1, \
		"max_symptoms" = 2, \
		"factors" = alist(STAT_HEART_RATE = 10, STAT_BP_SYSTOLIC = -5), \
	), \
	"Stage 2" = list( \
		"symptom_pool" = list( \
			/datum/affliction_symptom/pallor       = 80, \
			/datum/affliction_symptom/chills       = 60, \
			/datum/affliction_symptom/short_breath = 50, \
			/datum/affliction_symptom/dizziness    = 40, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 3, \
		"factors" = alist(STAT_SLOWDOWN = 0.6, STAT_HEART_RATE = 25, STAT_BP_SYSTOLIC = -20, STAT_BP_DIASTOLIC = -10), \
		"spontaneous_emotes" = list("wince", "groan"), \
		"spontaneous_emote_prob" = 4, \
	), \
	"Stage 3" = list( \
		"symptom_pool" = list( \
			/datum/affliction_symptom/pallor       = 90, \
			/datum/affliction_symptom/chills       = 80, \
			/datum/affliction_symptom/short_breath = 70, \
			/datum/affliction_symptom/dizziness    = 60, \
			/datum/affliction_symptom/confusion    = 40, \
			/datum/affliction_symptom/cyanosis     = 50, \
		), \
		"min_symptoms" = 3, \
		"max_symptoms" = 4, \
		"factors" = alist(STAT_SLOWDOWN = 1.4, STAT_ACCURACY = -20, STAT_MOTOR_CONTROL = 0.97, STAT_HEART_RATE = 40, STAT_BP_SYSTOLIC = -35, STAT_BP_DIASTOLIC = -20, STAT_CIRCULATION = 0.5), \
		"spontaneous_emotes" = list("groan in pain", "collapse", "shudder"), \
		"spontaneous_emote_prob" = 7, \
	), \
))
"########),"actual physical constructor keys use existing bounded VALUE proof");}

#[test]fn actual_original_whole_cardiac_stage_table_prefab_keys(){assert!(census_first_group_receipt(r########"#define STAT_BP_SYSTOLIC 100042
#define STAT_HEART_RATE 100107
#define STAT_PUMP 100156
#define TYPE_TABLE(T, N, V...) T/_tt_##N() {return V}
TYPE_TABLE(/datum/affliction/cardiac_arrhythmia, affliction_stages, list( \
	"Sinus" = list( \
		"name" = "post-arrest rhythm", \
		"description" = "The rhythm has been restored and is settling. Monitor; it resolves on its own.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/rhythm_finding/sinus = 100, \
			/datum/affliction_symptom/palpitations         = 30, \
		), \
		"min_symptoms" = 1, \
		"max_symptoms" = 2, \
		"consciousness_at_max" = 0, \
	), \
	"Tachycardia" = list( \
		"name" = "unstable tachyarrhythmia", \
		"description" = "A fast, disorganised rhythm that still perfuses the body. Cardiac drugs settle it; stimulants push it over into VF.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/rhythm_finding/tachy = 100, \
			/datum/affliction_symptom/palpitations         = 80, \
			/datum/affliction_symptom/dizziness            = 40, \
			/datum/affliction_symptom/pallor               = 40, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 3, \
		"consciousness_at_max" = 0, \
		"factors" = alist(STAT_HEART_RATE = 55, STAT_BP_SYSTOLIC = -15, STAT_PUMP = 0.85), \
	), \
	"VF" = list( \
		"name" = "ventricular fibrillation", \
		"description" = "The ventricles quiver without pumping. No pulse, no blood pressure. Shockable: defibrillate, and keep up CPR until the paddles are ready.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/rhythm_finding/vf = 100, \
			/datum/affliction_symptom/absent_pulse      = 100, \
			/datum/affliction_symptom/cyanosis          = 70, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 3, \
		"consciousness_at_max" = 200, \
		"factors" = alist(STAT_PUMP = 0), \
	), \
	"Asystole" = list( \
		"name" = "asystole", \
		"description" = "A flatline. No electrical activity to shock. CPR and a vasopressor may coarsen it into VF, which can then be shocked.", \
		"symptom_pool" = list( \
			/datum/affliction_symptom/rhythm_finding/asystole = 100, \
			/datum/affliction_symptom/absent_pulse            = 100, \
			/datum/affliction_symptom/cyanosis                = 70, \
		), \
		"min_symptoms" = 2, \
		"max_symptoms" = 3, \
		"consciousness_at_max" = 200, \
		"factors" = alist(STAT_PUMP = 0), \
	), \
))
"########),"actual physical constructor keys use existing bounded VALUE proof");}

#[test]fn actual_original_implicit_world_for_declarations_and_loop_control(){for source in[
"/proc/probe()\n    for(var/datum/d)\n        if(d)break\n        continue\n",
"/proc/probe()\n    for(var/client/T)\n        if(T)continue\n        break\n",
]{assert!(census_first_group_receipt(source),"actual implicit-world syntax needs same current declaration receipt; no fabricated world model");}}
#[test]fn actual_original_typed_for_as_mob_and_obj_whole_orbit_candidates(){assert!(census_first_group_receipt(r########"/datum/admin_verb/adminorbit/proc/orbit_candidates(client/user)
	var/list/possible_things = list()
	for(var/T as mob in view(user.view))	//Let's do mobs before objects
		if(ismob(T))
			possible_things |= T
	for(var/T as obj in view(user.view))
		if(isobj(T))
			possible_things |= T
	return possible_things
"########),"whole physical orbit_candidates preserves both actual As hints and iterable receipts");}
#[test]fn actual_original_inline_break_continue_requires_real_enclosing_loop(){
 assert!(census_first_group_receipt("/proc/probe(entries,limit)\n    for(var/item in entries)\n        if(limit<=0)break\n        if(item)continue\n    return null\n"));
 for control in["break","continue"]{let source=format!("/proc/probe(limit)\n    if(limit<=0){control}\n");assert!(!census_first_group_receipt(&source),"same inline bare control outside a witnessed loop stays unissued");}
}

#[test]fn actual_original_typed_for_mask_remains_in_binding_with_same_local_receipt(){
 for hint in["mob","obj"]{
  let source=format!("/proc/probe(entries)\n    for(var/T as {hint} in entries)\n        return T\n");let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let archive=view.archive();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();
  raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));
   let parsed=syntax.statements.parsed();let dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{binding,source_binding,..},..}=&parsed.statements[0].kind else{panic!("same current ForList")};assert_eq!(binding,&format!("var/T as {hint}"),"consumer must retain actual semantic iteration mask");assert!(source_binding.is_some());let rows=parsed.local_variables.entries().unwrap();assert_eq!(rows.len(),1);assert_eq!(rows[0].source_kind,dm_syntax::LocalSourceKind::ForBinding);assert!(rows[0].type_components.is_empty());assert_eq!(rows[0].source_modifiers,0);Ok(())}).unwrap();
 }
}

#[test]fn actual_original_bare_pick_local_and_terminal_final_keep_real_producer_roles(){assert!(census_first_group_receipt("/proc/probe(resumed,T)\n    var/pick\n    pick=resumed.value\n    if(!pick)\n        return null\n    var/turf/final=get_step(T,0)\n    return final\n"),"actual bare variable and local-name roles do not reclassify primitive pick calls");}

#[test]fn actual_original_bare_pick_whole_topic_c_mode(){assert!(census_first_group_receipt(r########"/datum/admins/proc/topic_c_mode(datum/act/op/A)
	var/mob/user = A.actor
	var/pick = A.step_value("mode")
	if(!pick)
		return
	var/picked_mode = c_mode_choices()[pick]
	if(picked_mode)
		admin_set_master_mode(user, picked_mode)
"########),"whole actual macrofree topic_c_mode preserves bare-pick variable role and builtin call separation");}

#[test]fn actual_original_bare_pick_whole_topic_f_secret(){assert!(census_first_group_receipt(r########"/datum/admins/proc/topic_f_secret(datum/act/op/A)
	var/mob/user = A.actor
	var/pick = A.step_value("mode")
	if(!pick)
		return
	var/picked_mode = f_secret_choices()[pick]
	if(picked_mode)
		admin_set_secret_force_mode(user, picked_mode)
"########),"whole actual macrofree topic_f_secret preserves bare-pick variable role and builtin call separation");}

#[test]fn actual_original_written_negative_range_step_reuses_field_and_scopes_controls(){assert!(census_first_group_receipt("/proc/probe()\n    for(column_max in column_max-1 to 1 step-1)\n        if(column_max<=0)break\n        continue\n"),"same implicit field binding retains actual negative step and existing loop-control scope");}

#[test]fn actual_original_recipe_nested_string_index_compound_isolated_leaf(){assert!(census_first_group_receipt("/proc/probe(food_recipes,Rp,rid)\n    food_recipes[Rp][\"Reagents\"]-=rid\n"),"actual nested staticString compound leaf keeps existing inner index proof and statement-only mutation role");}
#[test]fn actual_original_admin_grouped_intersection_member_condition_isolated_leaf(){assert!(census_first_group_receipt("/proc/probe(target_admin_datum)\n    if((target_admin_datum.ranks&GLOB.protected_ranks).len>0)\n        return null\n"),"actual grouped bitset intersection .len condition keeps same bounded read proof");}

#[test]fn actual_original_real_admin_delete_chained_assignment_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(jmp_coords,coords)
    jmp_coords = coords = "in nullspace"
"########),"actual root assignment/composition source keeps genuine Original receipt");}

#[test]fn actual_original_real_sdql_disable_bitfield_root_statement_isolation(){assert!(census_first_group_receipt(r########"#define DISABLE_BITFIELD(variable, flag)			(variable &= ~(flag))
#define SDQL2_OPTION_SELECT_OUTPUT_SKIP_NULLS			(1<<0)
/proc/probe(options)
    DISABLE_BITFIELD(options, SDQL2_OPTION_SELECT_OUTPUT_SKIP_NULLS)
"########),"actual root assignment/composition source keeps genuine Original receipt");}

#[test]fn actual_original_real_admin_state_named_argument_grouped_cache_write_isolation(){assert!(census_first_group_receipt(r########"#define ADMIN_STATE(required_perms) (GLOB.admin_states[required_perms] ||= new /datum/tgui_state/admin_state(required_perms))
#define APPEARANCE_ALL			0xFFFF
#define R_FUN (1<<3)
/proc/probe(target_human,user)
    target_human.change_appearance(APPEARANCE_ALL, user, check_species_whitelist = 0, state = ADMIN_STATE(R_FUN))
"########),"actual root assignment/composition source keeps genuine Original receipt");}

#[test]fn actual_original_whole_tgui_state_keeps_actual_admin_state_macro_cache_write(){assert!(census_first_group_receipt(r########"#define ADMIN_STATE(required_perms) (GLOB.admin_states[required_perms] ||= new /datum/tgui_state/admin_state(required_perms))
/datum/proc/tgui_state(mob/user)
	// interface(state =, rights =): the state the window's declaration carries, else ui_rights (an admin panel); an instance-dependent
	// state overrides this.
	var/datum/tgui_state/declared = interface_state(src)
	if(declared)
		return declared
	if(ui_rights)
		return ADMIN_STATE(ui_rights)
	return GLOB.tgui_default_state
"########),"actual root assignment/composition source keeps genuine Original receipt");}

#[test]fn actual_original_add_admin_return_slot_membership_condition_isolated_source(){assert!(census_first_group_receipt("/proc/probe(admin_ckey)\n    if(!admin_ckey && (. in (GLOB.admin_datums+GLOB.deadmins)))\n        return null\n"),"isolated exact add_admin membership condition retains bare return-slot Dot and reserved In");}

#[test]fn actual_original_dirblocked_whole_function_diagnostic(){assert!(census_first_group_receipt(r########"/proc/DirBlocked(turf/loc,dir)
	for(var/obj/structure/window/D in turf_contents_of_type(loc, /obj/structure/window))
		if(!D.density)			continue
		if(D.dir == SOUTHWEST)	return 1
		if(D.dir == dir)		return 1

	for(var/obj/machinery/door/D in turf_contents_of_type(loc, /obj/machinery/door))
		if(!D.density)			continue
		if(istype(D, /obj/machinery/door/window))
			if((dir & SOUTH) && (D.dir & (EAST|WEST)))		return 1
			if((dir & EAST ) && (D.dir & (NORTH|SOUTH)))	return 1
		else return 1	// it's a real, air blocking door
	return 0
"########),"whole physical DirBlocked from actualRaw105; no guessed firstleaf or source rewrite");}

#[test]fn actual_original_dirblocked_inline_continue_real_loop_isolation(){assert!(census_first_group_receipt("/proc/probe(turf/loc)\n    for(var/obj/structure/window/D in turf_contents_of_type(loc,/obj/structure/window))\n        if(!D.density)continue\n    return 0\n"),"actual inlinecontinue clause preserves genuine enclosing loop and iterable producer");}
#[test]fn actual_original_dirblocked_inline_return_real_condition_isolation(){assert!(census_first_group_receipt("/proc/probe(D,dir)\n    if(D.dir==dir)return 1\n    return 0\n"),"actual inlineReturn condition isolated without assuming this is the whole function's first gap");}
#[test]fn actual_original_dirblocked_inline_else_return_real_branch_isolation(){assert!(census_first_group_receipt("/proc/probe(D)\n    if(istype(D,/obj/machinery/door/window))\n        return 0\n    else return 1\n"),"actual inline elseReturn branch preserves real if/else parsing and independent child");}

#[test]fn actual_original_block_then_inline_else_return_keeps_nested_closes_and_child_authority(){
 assert!(census_first_group_receipt("/proc/probe(D,flag)\n    if(istype(D,/obj/machinery/door/window))\n        while(flag)\n            return 0\n    else return 1\n"),"actual nested THEN blocks close before exact inline ELSE prefix; Return child independently proves its value");
 assert!(!census_first_group_receipt("/proc/probe(D,a,b,c,d)\n    if(istype(D,/obj/machinery/door/window))\n        return 0\n    else return locate(a,b,c,d)\n"),"ELSE boundary cannot lend unsupported child-expression authority");
}

#[test]fn actual_original_census107_untraced_rank2338_io_job_count_whole_function_baseline(){assert!(census_first_group_receipt(r########"/proc/io_job_count(backend_type)
	. = 0
	for(var/datum/io_job/J as anything in GLOB.io_lane.jobs)
		if(!backend_type || J.backend_type == backend_type)
			.++
"########),"actual107 untraced rank2338 whole physical io_job_count; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2339_io_active_whole_function_baseline(){assert!(census_first_group_receipt(r########"/proc/io_active(datum/io_lane/lane, backend_type)
	. = 0
	for(var/datum/io_job/J as anything in lane.jobs)
		if(J.backend_type == backend_type && !isnull(J.job_id))
			.++
"########),"actual107 untraced rank2339 whole physical io_active; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2370_request_open_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define ASK_ADJACENT (1<<2)
#define ASK_NEAR_SUBJECT (1<<6)
#define MINUTES *600
#define QDELETED(X) (isnull(X) || QDELING(X))
#define QDELING(X) (X.gc_destroyed)
#define REQUEST_DEFAULT_TIMEOUT (10 MINUTES)
#define REQUEST_NO_TIMEOUT -1
#define REQ_CANCELLED 2
#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
#else
	#define RETURN_TYPE(X)
#endif
#define SECOND *10
#define TYPE_PROC_REF(TYPE, X) (nameof(##TYPE.proc/##X))
#define UNIT_TESTS
#define isatom(D)		istype(D, /atom)
#define islist(L) istype(L, /list)
#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))
/proc/request_open(datum/owner, request_type, handler, list/fields, datum/act/context = null)
	RETURN_TYPE(/datum/request)
	if(!ispath(request_type, /datum/request))
		CRASH("open_request(): [request_type] is not a request kind (/datum/prompt, /datum/io, /datum/client_query)")
	if(!owner || QDELETED(owner))
		return null
	var/datum/request/R = new request_type
	var/valid = null
	for(var/name in fields)
		var/value = fields[name]
		if(name == "valid")
			valid = value
			continue
		if(isnull(value))
			continue
		if(!istext(name))
			CRASH("open_request(): [request_type] was given a positional argument ([name]); name it (field = value)")
		if(name == "owner" || name == "handler")
			CRASH("open_request(): [name] is not a field")
		if(!(name in R.vars))
			CRASH("open_request(): [request_type] has no field [name]")
		if(name == "outcome")
			CRASH("open_request(): outcome is the engine's to set")
		if(own_table_of(R).entries?[name])
			rel_set(R, name, value) // a declared relation field goes through the relation, or the target keeps no back-edge to the prompt
		else
			R.vars[name] = value // ALLOW(api): open_request() named arguments: typed request fields by name
	// A question an op asks is about the op's holder unless its fields name another subject (the rechecks of ASK_ADJACENT and ASK_NEAR_SUBJECT read it).
	if(isnull(R.subject) && istype(owner, /datum/pending_op) && istype(context, /datum/act/op))
		var/datum/act/op/asking = context
		if(isatom(asking.holder))
			rel_set(R, nameof(R.subject), asking.holder)
	rel_set(R, nameof(R.owner), owner)
	R.handler = handler
	R.valid = valid
	R.opened_at = world.time // ALLOW(sys_world_time_write): the request's own open stamp, read for diagnostics, not an expiry
	R.answerer_expected = !isnull(R.answerer)
	// Every request ends: one given no timeout gets the default (a request with none pins its owner until the owner dies), logged once per kind so a
	// caller that should name its own is found. timeout = REQUEST_NO_TIMEOUT is the explicit opt-out.
	if(R.timeout == 0)
		R.timeout = REQUEST_DEFAULT_TIMEOUT
		var/static/list/defaulted = list()
		if(!defaulted[R.type])
			defaulted[R.type] = TRUE
			log_game("request: [R.type] opened without a timeout: it times out after [REQUEST_DEFAULT_TIMEOUT / (1 SECOND)] s (pass timeout = ... to choose, REQUEST_NO_TIMEOUT to opt out)")
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	// A test that records the prompts it causes (test_prompts_reset()) sees every one opened, in order.
	if(islist(GLOB.test_prompts) && istype(R, /datum/prompt))
		GLOB.test_prompts += R
#endif
	var/datum/system/requests/registry = SSrequests
	rel_add(registry, nameof(registry.open), R)
	registry.opened++
	if(R.timeout > 0)
		after(R, R.timeout, TYPE_PROC_REF(/datum/request, timed_out), key = "request_timeout")
	// The owner's and the answerer's deletion end the request at once (their qdeleting notice): the prompt must not stay up, and an answer must not
	// reach a handler that is gone.
	observe(owner, /datum/notice/qdeleting, R, then(TYPE_PROC_REF(/datum/request, owner_deleted)))
	if(R.answerer_expected && R.answerer)
		observe(R.answerer, /datum/notice/qdeleting, R, then(TYPE_PROC_REF(/datum/request, answerer_deleted)))
	R.prepare(context)
	if(R.recheck_on_open && request_recheck(R))
		request_end(R, REQ_CANCELLED, null)
		return R
	if(length(R.costs))
		var/why = request_costs_refusal(R)
		if(why)
			op_tell(request_payer(R), why)
			log_game("request: [R.type] not opened: its costs cannot be paid ([reason_text(why)])")
			rel_remove(registry, nameof(registry.open), R)
			cancel_after(R, "request_timeout")
			unobserve(owner, /datum/notice/qdeleting, R)
			if(R.answerer_expected && R.answerer)
				unobserve(R.answerer, /datum/notice/qdeleting, R)
			qdel(R) // ALLOW(lifecycle): a request is a plain datum with no lifecycle verb: one that never opened is deleted at once
			return null
	R.begin()
	return R
"########),"actual107 untraced rank2370 whole physical request_open; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2448_contains_roll_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define islist(L) istype(L, /list)
/proc/contains_roll(datum/holder, datum/entry/E)
	var/type = E.args["type"]
	var/count = E.args["count"]
	if(istext(count))
		count = (count in holder.vars) ? holder.vars[count] : call(holder, count)()
	if(!isnull(E.args["chance"]) && !roller_of(holder).chance(E.args["chance"]))
		return null
	if(ispath(type))
		. = list()
		.[type] = count
		return
	var/rolled
	if(istext(type) && (type in holder.vars))
		rolled = holder.vars[type] // nameof(type_var): a var holding the type, so a mapper or a subtype can change it
	else if(istext(type))
		rolled = call(holder, type)(roller_of(holder))
	else
		var/datum/entry/spec = type
		rolled = roller_of(holder).weighted(spec.args["weights"]) // a missing weight counts 1: a plain list is uniform
	if(isnull(rolled))
		return null
	if(!islist(rolled))
		rolled = list(rolled)
	. = list()
	for(var/thing in rolled)
		if(!ispath(thing))
			. += thing // an instance the roll proc made
			continue
		var/n = rolled[thing]
		.[thing] += (isnum(n) ? n : 1) * count
"########),"actual107 untraced rank2448 whole physical contains_roll; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2519_param_write_whole_function_baseline(){assert!(census_first_group_receipt(r########"/proc/param_write(datum/D, var_name, value)
	if(own_table_of(D).entries?[var_name])
		param_writing++
		try
			rel_set(D, var_name, value)
		catch(var/exception/e)
			param_writing--
			throw e
		param_writing--
		return
	D.vars[var_name] = value // ALLOW(api): a param is written before init, as a map edit would be
"########),"actual107 untraced rank2519 whole physical param_write; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2544_registry_file_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define LAZYADD(L, I) do { if(!L) { L = list(); } L += I; } while(0)
#define LAZYINITLIST(L) do { if (!L) { L = list(); } } while(0)
#define REG_AREA (1<<1)
#define REG_Z (1<<0)
#define SLOT(D) (D.handle_slot || slot_of(D))
#define get_turf(A) get_step(A,0)
#define isatom(D)		istype(D, /atom)
/proc/registry_file(datum/holder, datum/entry/E)
	var/id = E.args["id"]
	var/datum/lifeform_index/I = lifeform_index(id)
	if(I.filed[SLOT(holder)])
		registry_unfile(holder, id)
	var/key_var = E.args["key"]
	var/key = istext(key_var) && (key_var in holder.vars) ? holder.vars[key_var] : null
	var/k = isnull(key) ? "" : "[key]"
	var/z = null
	var/area/area = null
	var/by = E.args["by"]
	if(by && isatom(holder))
		var/turf/T = get_turf(holder)
		if(by & REG_Z)
			z = T ? "[T.z]" : null
		if(by & REG_AREA)
			area = T ? T.loc : null
	I.filed[SLOT(holder)] = list(k, z, area)
	LAZYADD(I.by_key[k], SLOT(holder))
	if(z)
		LAZYINITLIST(I.by_z[z])
		LAZYADD(I.by_z[z][k], SLOT(holder))
	if(area)
		LAZYINITLIST(I.by_area[area])
		LAZYADD(I.by_area[area][k], SLOT(holder))
	holder.registry_mirror_join(id)
"########),"actual107 untraced rank2544 whole physical registry_file; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2545_registry_unfile_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define LAZYREMOVE(L, I) do { if(L) { L -= I; if(!length(L)) { L = null; } } } while(0)
#define SLOT_KNOWN(D) (D.handle_slot || slot_known(D))
/proc/registry_unfile(datum/holder, id)
	var/datum/lifeform_index/I = lifeform_index_peek(id)
	var/list/at = I?.filed[SLOT_KNOWN(holder)]
	if(!at)
		return
	I.filed -= SLOT_KNOWN(holder)
	var/k = at[1]
	LAZYREMOVE(I.by_key[k], SLOT_KNOWN(holder))
	if(at[2])
		LAZYREMOVE(I.by_z[at[2]]?[k], SLOT_KNOWN(holder))
	if(at[3])
		LAZYREMOVE(I.by_area[at[3]]?[k], SLOT_KNOWN(holder))
	holder.registry_mirror_leave(id)
"########),"actual107 untraced rank2545 whole physical registry_unfile; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2579_acceptance_override_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define ENTRY_ACCEPTANCE "acceptance_channel"
/proc/acceptance_override(datum/declarer, list/current, channel, datum/entry/declaration)
	if(!istype(declaration) || declaration.kind != ENTRY_ACCEPTANCE || declaration.args["channel"] != channel)
		CRASH("acceptance override must be a declaration for [channel]")
	var/list/next = current ? current.Copy() : list()
	var/datum/entry/part/acceptance_plan/base = table_of(declarer).acceptance_channels?[channel]
	next[channel] = acceptance_compile(list(declaration), base)
	return next
"########),"actual107 untraced rank2579 whole physical acceptance_override; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2583_acceptance_plan_for_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define LAZYACCESS(L, I) ((L) ? (isnum(I) ? ((I) > 0 && (I) <= length(L) ? (L)[I] : null) : (L)[I]) : null)
#define READS_FROM(args...)
/proc/acceptance_plan_for(datum/declarer, channel)
	READS_FROM(declarer)
	var/list/overrides = declarer.acceptance_overrides()
	var/datum/entry/part/acceptance_plan/override = LAZYACCESS(overrides, channel)
	return override ? override : table_of(declarer).acceptance_channels?[channel]
"########),"actual107 untraced rank2583 whole physical acceptance_plan_for; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank2984_cap_engine_state_make_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define LAZYSET(L, K, V) do { if(!L) { L = list(); } L[K] = V; } while(0)
#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
#else
	#define RETURN_TYPE(X)
#endif
/proc/cap_engine_state_make(atom/A)
	RETURN_TYPE(/datum/cap_engine_state)
	var/datum/cap_engine_state/state = capability_data(A)?[/datum/cap_engine_state]
	if(!state)
		state = new
		LAZYSET(capability_runtime(A).data, /datum/cap_engine_state, state)
	return state
"########),"actual107 untraced rank2984 whole physical cap_engine_state_make; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3014_client_images_index_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define isatom(D)		istype(D, /atom)
#define islist(L) istype(L, /list)
/proc/client_images_index(client/C, thing)
	for(var/image/I as anything in (islist(thing) ? thing : list(thing)))
		if(!istype(I))
			continue
		var/list/viewers = GLOB.client_image_viewers[I]
		if(!viewers)
			viewers = GLOB.client_image_viewers[I] = list()
		viewers |= C
		var/atom/rides = I.loc
		if(isatom(rides))
			var/ride_slot = slot_of(rides)
			var/list/riding = GLOB.client_images_by_loc[ride_slot]
			if(!riding)
				riding = GLOB.client_images_by_loc[ride_slot] = list()
			riding |= I
"########),"actual107 untraced rank3014 whole physical client_images_index; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3124_own_lost_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define QDELETED(X) (isnull(X) || QDELING(X))
#define QDELING(X) (X.gc_destroyed)
/proc/own_lost(datum/holder, var_name, datum/thing)
	var/handler = own_table_of(holder).lost_handlers?[var_name]
	if(handler && !QDELETED(holder))
		call(holder, handler)(thing)
"########),"actual107 untraced rank3124 whole physical own_lost; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3153_slots_retired_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define SLOT_GEN_MAX 31
/proc/slots_retired()
	. = 0
	for(var/gen in handle_gens)
		if(gen > SLOT_GEN_MAX)
			.++
"########),"actual107 untraced rank3153 whole physical slots_retired; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3232_rel_incoming_refs_whole_function_baseline(){assert!(census_first_group_receipt(r########"/proc/rel_incoming_refs(datum/target)
	. = 0
	var/list/index = target ? _rel_index_of(target) : null
	for(var/source_ref in index)
		var/datum/S = slot_datum(source_ref)
		// Only live entries count (an index may hold an entry whose source stopped naming the target).
		for(var/name in rel_names_of(index[source_ref]))
			if(_rel_source_names(S, name, target))
				.++
"########),"actual107 untraced rank3232 whole physical rel_incoming_refs; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3234_rel_drop_z_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define isdatum(D)		istype(D, /datum)
#define islist(L) istype(L, /list)
/proc/rel_drop_z(z)
	rel_pending_flush_all() // a turf of the level may be named by rows the init frame has queued
	var/zkey = "[z]"
	var/list/by_turf = GLOB.rel_turf_index[zkey]
	if(!by_turf)
		return 0
	GLOB.rel_turf_index -= zkey
	. = 0
	for(var/turf_ref in by_turf)
		var/turf/T = slot_datum(turf_ref)
		var/list/index = by_turf[turf_ref]
		if(!isturf(T))
			continue
		for(var/source_ref in index)
			var/datum/S = slot_datum(source_ref)
			if(!isdatum(S))
				continue
			for(var/name in rel_names_of(index[source_ref]))
				if(!(name in S.vars))
					continue
				var/value = S.vars[name]
				if(value == T)
					S.vars[name] = null // ALLOW(api): releasing a z-level clears the view var; the relation machinery is the accessor
					own_field_changed(S, name)
					.++
				else if(islist(value))
					var/list/views = value
					if(T in views)
						views -= T
						.++
"########),"actual107 untraced rank3234 whole physical rel_drop_z; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3332_state_accounted_refs_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define DEP_ALL (DEP_OUTPUTS | DEP_LEGACY | DEP_VALUES)
#define DEP_DRAW (1<<1)
#define DEP_LEGACY (1<<4)
#define DEP_OUTPUTS (DEP_RUN | DEP_DRAW | DEP_UI | DEP_PUSH)
#define DEP_PUSH (1<<3)
#define DEP_RUN (1<<0)
#define DEP_UI (1<<2)
#define DEP_VALUES (((1 << DEP_VALUE_MAX) - 1) << DEP_VALUE_SHIFT)
#define DEP_VALUE_MAX 12
#define DEP_VALUE_SHIFT 5
#define STATE_REFS_FROM_LOC 1
#define STATE_REFS_PER_CONTENT 1
#define isatom(D)		istype(D, /atom)
/proc/state_accounted_refs(datum/node, list/internal, internal_refs)
	. = (isnull(internal_refs) ? state_internal_refs(node, internal) : internal_refs) + rel_incoming_refs(node)
	// A queued refresh (state_changed()) holds it in GLOB.refresh_queue until the drain: framework bookkeeping, which
	// skips a collapsed entity, not an outside holder.
	if(node.refresh_queued)
		.++
	// Its slot (code/engine/refs/slots.dm) holds it in handle_data until the destroy transaction frees it: the same bookkeeping, and the reason a lazy state
	// row (which names its holder by slot) must not pin its holder.
	if(node.handle_slot > 0 && handle_data?[node.handle_slot] == node)
		.++
	// A queued Rust push (refresh_mark() with DEP_PUSH and not DEP_ALL: a rust_push read, a bind, or a write the plan spares the draw
	// of, which marks everything but the look) holds it in GLOB.refresh_push_queue until phase S: the same bookkeeping, and the drain
	// skips a deleted (collapsed) entity.
	if(GLOB.refresh_push_queue[node])
		.++
	if(ismovable(node))
		var/atom/movable/movable = node
		if(movable.loc)
			. += STATE_REFS_FROM_LOC
			// A container's ledger lists what it holds. Inside the subtree the
			// ledger is an owned part and its lists are scanned already.
			var/datum/ledger/L = movable.loc.containment_ledger()
			if(L && !(movable.loc in internal))
				. += L.refs_to(movable)
		. += state_slot_refs(movable, internal)
	if(isatom(node))
		var/atom/A = node
		. += STATE_REFS_PER_CONTENT * length(A.contents)
"########),"actual107 untraced rank3332 whole physical state_accounted_refs; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3337_state_count_refs_in_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define islist(L) istype(L, /list)
/proc/state_count_refs_in(value, datum/node, depth, flat = FALSE)
	if(value == node)
		return 1
	if(!islist(value) || depth > 4)
		return 0
	. = 0
	var/list/L = value
	for(var/key in L)
		// A null entry has no associated value, and L[null] is a bad index.
		if(isnull(key))
			continue
		if(key == node)
			.++
		else if(islist(key))
			. += state_count_refs_in(key, node, depth + 1)
		if(!flat && !isnum(key) && !islist(key))
			var/assoc
			// Some built-in lists held in ordinary vars (appearance/overlay lists of an
			// /image or a copied overlays list) have no associated values, and L[key]
			// on them is a "bad index" runtime. Read those as flat; the sweep caught the
			// runtime per atom but backed the atom off and logged it every pass.
			try
				assoc = L[key]
			catch // ALLOW(silent_catch): a list with no associated values is expected here; it is read as flat
				flat = TRUE
				continue
			if(!isnull(assoc))
				. += state_count_refs_in(assoc, node, depth + 1)
"########),"actual107 untraced rank3337 whole physical state_count_refs_in; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_untraced_rank3350_scheduler_field_field_table_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define CHANGE_RELATED (1<<7)
#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
#else
	#define RETURN_TYPE(X)
#endif
/proc/scheduler_field_field_table(path)
	RETURN_TYPE(/list)
	var/static/list/plain_defs
	var/static/list/derived_defs
	if(!plain_defs)
		plain_defs = list()
		derived_defs = list()
		for(var/def_path in subtypesof(/datum/scheduler_field_definition))
			var/datum/scheduler_field_definition/D = def_path
			if(!initial(D.field))
				continue
			if(initial(D.derived))
				derived_defs += new def_path // inputs is a list: read from an instance
			else
				plain_defs += def_path
	var/list/F = list()
	for(var/datum/scheduler_field_definition/D as anything in plain_defs)
		if(ispath(path, initial(D.of)))
			F[initial(D.field)] |= initial(D.channel)
	var/list/mine = list()
	for(var/datum/scheduler_field_definition/D as anything in derived_defs)
		if(ispath(path, D.of))
			mine += D
	// Derived fields may read other derived fields: resolve until nothing changes.
	for(var/pass in 1 to max(1, length(mine)))
		var/changed = FALSE
		for(var/datum/scheduler_field_definition/D as anything in mine)
			var/channel = F[D.field]
			for(var/input in D.inputs)
				if(isnum(input))
					channel |= input
				else if(findtext(input, "."))
					// "rel.field": the relation var's own channel (relink) plus the relay's CHANGE_RELATED.
					channel |= F[copytext(input, 1, findtext(input, "."))] | CHANGE_RELATED
				else
					channel |= F[input]
			if(channel != F[D.field])
				F[D.field] = channel
				changed = TRUE
		if(!changed)
			break
	return F
"########),"actual107 untraced rank3350 whole physical scheduler_field_field_table; diagnostic baseline only, no assumed cause or fixture closure grant");}

#[test]fn actual_original_census107_member_join_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"/proc/member_join(key, datum/member, source = null, role = null)
	key = member_key(key)
	var/datum/kernel_membership/M = kernel_membership()
	if(!key || !member)
		return FALSE
	var/list/index = M.index_by_key[key]
	if(!index)
		index = M.index_by_key[key] = list()
		M.members_by_key[key] = list()
		M.sources_by_key[key] = list()
		M.role_by_key[key] = list()
	var/list/sources = M.sources_by_key[key]
	var/src_key = source || member
	var/list/held = sources[member]
	var/is_new = !index[member]
	if(!held)
		held = sources[member] = list()
	held[src_key] = TRUE
	if(!isnull(role))
		member_set_role(M, key, member, role)
	if(!is_new)
		return FALSE
	var/list/members = M.members_by_key[key]
	members += member
	index[member] = M.ordered_keys?[key] ? TRUE : length(members)
	var/list/keys = M.keys_of[member]
	if(!keys)
		keys = M.keys_of[member] = list()
	keys += key
	return TRUE
"########),"whole physical member_join retains real assignment family and actual macros");}

#[test]fn actual_original_census107_member_adopt_ordered_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"#define LAZYSET(L, K, V) do { if(!L) { L = list(); } L[K] = V; } while(0)
/proc/member_adopt_ordered(key, list/members)
	var/datum/kernel_membership/M = kernel_membership()
	if(M.ordered_keys?[key])
		return M.members_by_key[key]
	LAZYSET(M.ordered_keys, key, TRUE)
	M.members_by_key[key] = members
	var/list/index = M.index_by_key[key] = list()
	var/list/sources = M.sources_by_key[key] = list()
	M.role_by_key[key] = list()
	for(var/datum/member as anything in members)
		index[member] = TRUE
		var/list/held = sources[member] = list()
		held[member] = TRUE
		var/list/keys = M.keys_of[member]
		if(!keys)
			keys = M.keys_of[member] = list()
		keys |= key
	return members
"########),"whole physical member_adopt_ordered retains real assignment family and actual macros");}

#[test]fn actual_original_census107_io_backend_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"/**
* SpacemanDMM dreamchecker extensions for suite 1.7
* <https://github.com/SpaceManiac/SpacemanDMM/tree/suite-1.7/src/dreamchecker>
*/

#ifdef SPACEMAN_DMM
	#define RETURN_TYPE(X) set SpacemanDMM_return_type = X
	#define SHOULD_CALL_PARENT(X) set SpacemanDMM_should_call_parent = X
	#define UNLINT(X) SpacemanDMM_unlint(X)
	#define SHOULD_NOT_OVERRIDE(X) set SpacemanDMM_should_not_override = X
	#define SHOULD_NOT_SLEEP(X) set SpacemanDMM_should_not_sleep = X
	#define SHOULD_BE_PURE(X) set SpacemanDMM_should_be_pure = X
	#define PRIVATE_PROC(X) set SpacemanDMM_private_proc = X
	#define PROTECTED_PROC(X) set SpacemanDMM_protected_proc = X
	#define CAN_BE_REDEFINED(X) set SpacemanDMM_can_be_redefined = X
	#define VAR_FINAL var/SpacemanDMM_final
	#define VAR_PRIVATE var/SpacemanDMM_private
	#define VAR_PROTECTED var/SpacemanDMM_protected
#else
	#define RETURN_TYPE(X)
	#define SHOULD_CALL_PARENT(X)
	#define UNLINT(X) X
	#define SHOULD_NOT_OVERRIDE(X)
	#define SHOULD_NOT_SLEEP(X)
	#define SHOULD_BE_PURE(X)
	#define PRIVATE_PROC(X)
	#define PROTECTED_PROC(X)
	#define CAN_BE_REDEFINED(X)
	#define VAR_FINAL var
	#define VAR_PRIVATE var
	#define VAR_PROTECTED var
#endif

/proc/io_backend(backend_type)
	RETURN_TYPE(/datum/io_backend)
	var/static/list/backends = list()
	var/datum/io_backend/K = backends[backend_type]
	if(!K && ispath(backend_type, /datum/io_backend))
		K = backends[backend_type] = new backend_type
	return K
"########),"whole physical io_backend retains real assignment family and actual macros");}

#[test]fn actual_original_census107_capability_instance_data_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"#define LAZYSET(L, K, V) do { if(!L) { L = list(); } L[K] = V; } while(0)
/proc/capability_instance_data(atom/A, datum/capability/C)
	var/datum/D = capability_data(A)?[C.key]
	if(D || !C.data_type)
		return D
	D = new C.data_type
	LAZYSET(capability_runtime(A).data, C.key, D)
	return D
"########),"whole physical capability_instance_data retains real assignment family and actual macros");}

#[test]fn actual_original_census107_hooks_change_baseline_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"#define LAZYSET(L, K, V) do { if(!L) { L = list(); } L[K] = V; } while(0)
/proc/hooks_change_baseline(datum/E)
	var/index = change_index_of(E)
	if(!index)
		return
	for(var/key in index)
		for(var/datum/hook/H as anything in index[key])
			LAZYSET(rx_of(E).change_last, "[H.serial]", change_value(E, H))
	// What the init's own writes marked is moot: the baseline is the value now, so nothing is owed a first run.
	if(GLOB.hook_change_pending)
		GLOB.hook_change_pending -= handle_of(E)
"########),"whole physical hooks_change_baseline retains real assignment family and actual macros");}

#[test]fn actual_original_census107_keyed_target_register_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"/proc/keyed_target_register(type, id_var)
	keyed_targets_cache()[type] = id_var
"########),"whole physical keyed_target_register retains real assignment family and actual macros");}

#[test]fn actual_original_census107_link_register_whole_assignment_family_source(){assert!(census_first_group_receipt(r########"/proc/link_register(datum/entry/E)
	if(link_decls_cache()[E.sig])
		return
	link_decls_cache()[E.sig] = E
	if(E.args["hot"] || E.args["sparse"])
		return // an engine hot-path pair (direct lists, no index, nothing published; the engine owns both sides), or a sparse one (link_state.dm): no vars to patch in
	var/list/cache = _scs_own_table
	for(var/type_key in cache)
		var/datum/own_table/T = cache[type_key]
		if(istype(T))
			link_patch_table(T, E)
"########),"whole physical link_register retains real assignment family and actual macros");}

#[test]fn actual_original_census107_complex_chain_isolated_source(){assert!(census_first_group_receipt(r########"/proc/probe(M,key)
    var/list/index=M.index_by_key[key]=list()
    index=M.index_by_key[key]=list()
    return index
"########),"actual observed assignment shape retains current source/local/head receipts");}

#[test]fn actual_original_census107_member_initializer_isolated_source(){assert!(census_first_group_receipt(r########"/proc/probe()
    var/list/registry=GLOB.capability_infos=list()
    return registry
"########),"actual observed assignment shape retains current source/local/head receipts");}

#[test]fn actual_original_census107_call_index_isolated_source(){assert!(census_first_group_receipt(r########"/proc/probe(A,C,D)
    capability_runtime(A).data[C.key]=D
    link_decls_cache()[C.key]=D
    return D
"########),"actual observed assignment shape retains current source/local/head receipts");}

#[test]fn actual_original_return_slot_postfix_whole_km_unrolled_behaviours(){assert!(census_first_group_receipt(r########"#define SCHED_MAX_STAT_TYPES 512
/proc/km_unrolled_behaviours()
	. = 0
	for(var/datum/scheduled_behaviour/B as anything in definition_registry().behaviours)
		if(B && B.id >= SCHED_MAX_STAT_TYPES)
			.++
"########),"whole actual root Dotpostfix producer");}

#[test]fn actual_original_return_slot_index_compound_whole_parse_github_changelog(){assert!(census_first_group_receipt(r########"#define LAZYADDASSOCLIST(L, K, V) do { if(!L) { L = list(); } L[K] += list(V); } while(0)
/proc/parse_github_changelog(body) as /list
	// these shouldn't be static, as this will only be called a few times at most in get_testmerge_data, which will only be called once.
	var/regex/cl_pattern = new(@"(:cl:|🆑)([\S \t]*)$")
	var/regex/entry_pattern = new(@"(\w+): (.+)")
	var/regex/end_pattern = new(@"^/(:cl:|🆑)")
	var/regex/newline_pattern = new(@"(\r\n|\r|\n)")

	// no changes, this is just using the default template
	if(findtext_char(body, "add: Added new mechanics or gameplay changes"))
		return

	var/started = FALSE
	var/list/lines = splittext_char(trimtext(body), newline_pattern)

	for(var/line in lines)
		line = trimtext(line)
		if(findtext_char(line, end_pattern))
			break
		if(started)
			if (findtext_char(line, entry_pattern))
				var/change_type = trimtext(entry_pattern.group[1])
				var/change_desc = trimtext(entry_pattern.group[2])
				if(!change_type || !change_desc)
					continue
				LAZYADDASSOCLIST(., change_type, change_desc)
		else
			if(findtext_char(line, cl_pattern))
				started = TRUE
"########),"whole actual macro producer retains return-slot compound statement");}

#[test]fn actual_original_return_slot_updates_root_isolation(){assert!(census_first_group_receipt("/proc/probe(change_type,change_desc)\n    .++\n    .--\n    .[change_type]+=list(change_desc)\n"));}

#[test]fn actual_original_switch_default_effect_whole_counting_english_list(){assert!(census_first_group_receipt(r########"#define isatom(D)		istype(D, /atom)
#define DET_NONE		0x00
#define DET_DEFINITE	0x01 // the
#define DET_INDEFINITE	0x02 // a, an, some
/proc/counting_english_list(client/viewer, list/input, output_icons = TRUE, determiners = DET_NONE, nothing_text = "nothing", line_prefix = "\t", first_item_prefix = "\n", last_item_suffix = "\n", and_text = "\n", comma_text = "\n", final_comma_text = ",")
	var/list/counts = list() // counted input items
	var/list/items = list() // actual objects for later reference (for icons and formatting)

	// count items
	for(var/item in input)
		var/name = "[item]" // index items by name; usually works fairly well for loose equality
		if(name in counts)
			counts[name]++
		else
			counts[name] = 1
			items.Add(item)

	// assemble the output list
	var/list/out = list()
	var/i = 0
	for(var/item in items)
		var/name = "[item]"
		var/count = counts[name]
		var/item_str = line_prefix
		if(count > 1)
			item_str += "[count]x&nbsp;"

		if(isatom(item))
			// atoms/items/objects can be pretty and whatnot
			var/atom/A = item
			if(output_icons && isicon(A.icon) && !ismob(A)) // mobs tend to have unusable icons
				item_str += "[icon2html(A, viewer)]&nbsp;"
			switch(determiners)
				if(DET_NONE) item_str += A.name
				if(DET_DEFINITE) item_str += "\the [A]"
				if(DET_INDEFINITE) item_str += "\a [A]"
				else item_str += name
		else
			// non-atoms use plain string conversion
			item_str += name

		if(i == 0)
			item_str = first_item_prefix + item_str
		if(i == items.len - 1)
			item_str = item_str + last_item_suffix

		out.Add(item_str)
		i++

	// finally return the list using regular english_list builder
	return english_list(out, nothing_text, and_text, comma_text, final_comma_text)
"########),"whole actual determiner switch keeps all inlinecases and real default assignment");}

#[test]fn actual_original_switch_default_effect_isolation_requires_independent_child(){assert!(census_first_group_receipt("/proc/probe(mode,value)\n    switch(mode)\n        if(0)\n            return 0\n        else output+=value\n"));assert!(!census_first_group_receipt("/proc/probe(mode,a,b,c,d)\n    switch(mode)\n        if(0)\n            return 0\n        else output=locate(a,b,c,d)\n"),"default boundary cannot lend missing child expression proof");}

#[test]fn actual_original_census107_root_rx_ledger_has_whole_read_update_control(){assert!(census_first_group_receipt(r########"/proc/rx_ledger_has(datum/holder, kind, what)
	if(isnum(what))
		what = "[what]"
	return !!holder.rx?.ledger?["[kind]"]?[what]
"########),"exact wholephysical rx_ledger_has; real OriginalHost only, no stub semantics or assumed full-family qualification");}

#[test]fn actual_original_census107_root_rx_ledger_sources_whole_read_update_control(){assert!(census_first_group_receipt(r########"/proc/rx_ledger_sources(datum/holder, kind, what)
	if(isnum(what))
		what = "[what]"
	var/list/sources = holder.rx?.ledger?["[kind]"]?[what]
	return sources ? sources.Copy() : list()
"########),"exact wholephysical rx_ledger_sources; real OriginalHost only, no stub semantics or assumed full-family qualification");}

#[test]fn actual_original_census107_root_activation_attach_whole_read_update_control(){assert!(census_first_group_receipt(r########"#define GLOBAL_PROC_REF(X) (/proc/##X)
#define LAZYADD(L, I) do { if(!L) { L = list(); } L += I; } while(0)
#define OP_PURE_ACTIVE (GLOB.op_pure_depth > 0 || GLOB.derived_evaluating > 0)
#define OP_PURE_GUARD(what) if(OP_PURE_ACTIVE) { op_pure_violation(what) }
#define QDELETED(X) (isnull(X) || QDELING(X))
#define QDELING(X) (X.gc_destroyed)
#define SCOPE_SOURCE 1 // while the source exists, until revoke
#define SLOT(D) (D.handle_slot || slot_of(D))
#define SOURCE_DEF(name)
#define TEST_EVENT_ATTACH "attach"
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
#define TEST_REC_ACTIVATION(event, definition, source, holder) test_rec_activation(event, definition, source, holder)
#else
#define TEST_REC_ACTIVATION(event, definition, source, holder)
#endif
#define isdatum(D)		istype(D, /datum)
/proc/activation_attach(datum/holder, datum/capability/def, source, lasts, scope, scope_data, datum/activation/parent)
	OP_PURE_GUARD("[def?.key] was granted to [holder?.type]")
	if(!isdatum(holder) || QDELETED(holder))
		declare_report("grant([def?.key]): the holder is deleted or not a datum")
		return null
	if(!source_is_valid(source))
		declare_report("grant([def.key]) on [holder.type]: the source must be a live datum or a SOURCE_DEF id, got [isnull(source) ? "null" : "[source]"]")
		return null
	if(!isnull(lasts) && (!isnum(lasts) || lasts <= 0))
		declare_report("grant([def.key]) on [holder.type]: lasts must be a positive number of deciseconds, got [lasts]")
		return null
	var/datum/rx_state/rx = rx_of(holder)
	// One source applies one definition to one holder once.
	var/datum/activation/existing = activation_find(holder, def.key, source)
	if(existing)
		if(existing.def == def && !lasts)
			return existing
		activation_end(existing)
	// Build and validate every contribution before anything is applied: a failure applies nothing.
	var/list/to_apply = activation_plan(def)
	for(var/datum/centry/C as anything in to_apply)
		var/datum/entry/E = C.item
		if(!istype(E))
			continue
		var/datum/entry_engine/engine = entry_engine_for(E.kind)
		var/reason = engine?.validate_for(null, E)
		if(reason)
			declare_report("grant([def.key]) on [holder.type]: [E.kind] entry refused: [reason]")
			return null
	var/datum/activation/A = new
	A.def = def
	A.source = source
	A.holder_slot = SLOT(holder)
	A.scope = scope
	A.scope_data = scope_data
	A.serial = ++GLOB.activation_serial
	A.parent = parent // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	A.lasts = lasts || 0
	LAZYADD(rx.activations, A) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	if(isdatum(source))
		LAZYADD(rx_of(source).sourced, A)
	if(parent)
		LAZYADD(parent.owned, A) // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	TEST_REC_ACTIVATION(TEST_EVENT_ATTACH, def, source, holder)
	// Apply: contributions at once; nested capability definitions become child activations this one owns.
	for(var/datum/centry/C as anything in to_apply)
		if(istype(C.item, /datum/capability))
			activation_attach(holder, C.item, A, null, SCOPE_SOURCE, null, A)
			continue
		var/datum/entry/E = C.item
		var/datum/entry_engine/engine = entry_engine_for(E.kind)
		if(engine?.apply(A, E, C))
			LAZYADD(A.applied, list(list(E, engine)))
	def.on_activate(A)
	if(lasts)
		after(holder, lasts, GLOBAL_PROC_REF(activation_expire), key = "activation:[A.serial]", with = list(A))
	activation_restack(holder, def.key)
	return A
"########),"exact wholephysical activation_attach; real OriginalHost only, no stub semantics or assumed full-family qualification");}

#[test]fn actual_original_census107_root_look_watch_sync_whole_read_update_control(){assert!(census_first_group_receipt(r########"#define isatom(D)		istype(D, /atom)
/proc/look_watch_sync(atom/A, list/keys, list/neighbour_types, alist/look_keys, list/worn_keys)
	var/datum/cap_engine_state/engine = (keys || look_keys) ? cap_engine_state_make(A) : cap_engine_state_of(A)
	if(!engine)
		return
	var/list/was = engine.look_watching
	for(var/key in was)
		if(!(key in keys))
			var/datum/gone = slot_datum(key)
			if(gone)
				rel_unobserve(gone, A)
	for(var/key in keys)
		if(!(key in was))
			var/datum/seen = slot_datum(key)
			if(seen)
				rel_observe(seen, A)
	engine.look_watching = keys
	engine.look_neighbour_types = neighbour_types
	// look.watch_worn(): what the draw shows worn or held is read whole while it does (rx_readers()).
	var/list/worn_was = engine.look_watching_worn
	for(var/key in worn_was)
		if(!(key in worn_keys))
			var/datum/worn_gone = slot_datum(key)
			if(worn_gone?.rx?.worn_watched)
				worn_gone.rx.worn_watched--
	for(var/key in worn_keys)
		if(!(key in worn_was))
			var/datum/worn_seen = slot_datum(key)
			if(worn_seen)
				rx_of(worn_seen).worn_watched++
	engine.look_watching_worn = worn_keys
	// look.watch_look(): the atoms whose look this draw composes. Only their look_published() reaches A, never their other changes.
	var/list/was_looks = engine.look_watching_looks
	for(var/key in was_looks)
		if(!(key in look_keys))
			var/atom/gone_look = slot_datum(key)
			if(isatom(gone_look))
				look_unsubscribe(gone_look, A)
	for(var/key in look_keys)
		if(!(key in was_looks))
			var/atom/seen_look = slot_datum(key)
			if(isatom(seen_look))
				look_subscribe(seen_look, A)
	engine.look_watching_looks = look_keys
"########),"exact wholephysical look_watch_sync; real OriginalHost only, no stub semantics or assumed full-family qualification");}

#[test]fn actual_original_census107_root_refresh_drain_grouped_logical_member_actual_leaf_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(datum/time_scheduler/sched)
	var/datum/km_attr/attr = (sched?.meter || km_meter()).attr
"########),"actual physical leaf isolate only, no whole-function claim");}

#[test]fn actual_original_census107_root_definition_run_if_masks_conditional_key_compound_actual_leaf_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(list/masks,negated,i)
	masks[negated ? 2 : 1] |= 1 << (i - 1)
"########),"actual physical leaf isolate only, no whole-function claim");}

#[test]fn actual_original_census107_root_definition_topo_order_nested_key_compound_actual_leaf_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(list/succ,list/index_of,A,i)
	succ[index_of[A]] |= i
"########),"actual physical leaf isolate only, no whole-function claim");}

#[test]
fn actual_original_latency_admit_whole_function_diagnostic() {
    assert!(census_first_group_receipt(r########"#define LATENCY_L3 3
#define KERNEL_SHED_FLOOR (1 SECONDS)
#define SECONDS *10
/datum/kernel_latency/proc/admit(latency_class, key = "l3")
	if(latency_class < LATENCY_L3 || !enabled || !shedding)
		return TRUE
	if(world.time - (floor_pass[key] || -1e9) >= KERNEL_SHED_FLOOR)
		floor_pass[key] = world.time // ALLOW(sys_world_time_write): the kernel clock: a scheduler timestamp of the kernel itself, not a per-entity expiry
		return TRUE
	shed_by_class[latency_class + 1]++
	return FALSE
"########), "authentic OriginalHost diagnostic control; no semantic stub or first-leaf inference");
}

#[test]
fn actual_original_latency_admit_floor_condition_isolation() {
    assert!(census_first_group_receipt(r########"#define LATENCY_L3 3
#define KERNEL_SHED_FLOOR (1 SECONDS)
#define SECONDS *10
/proc/probe(key)
	if(world.time - (floor_pass[key] || -1e9) >= KERNEL_SHED_FLOOR)
		return TRUE
	return FALSE
"########), "authentic OriginalHost diagnostic control; no semantic stub or first-leaf inference");
}

#[test]
fn actual_original_latency_admit_binary_index_postfix_isolation() {
    assert!(census_first_group_receipt(r########"/proc/probe(latency_class)
	shed_by_class[latency_class + 1]++
"########), "authentic OriginalHost diagnostic control; no semantic stub or first-leaf inference");
}


#[test]fn actual_original_census111_untraced_rank26862_deactivate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/medichines_syn/deactivate(force = FALSE)
	if((. = ..()))
		mode = 0
"########),"actual111 untraced rank26862 whole physical /datum/nifsoft/medichines_syn.deactivate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26863_life_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define get_turf(A) get_step(A,0)
#define isbelly(A)				istype(A, /obj/belly)
/datum/nifsoft/medichines_syn/life()
	if((. = ..()))
		//We're good!
		var/mob/living/carbon/human/S = nif().human
		var/HP_percent = 2 * S.vitality() - 1 // 1 = well, 0 = the crit line, -1 = dead
		if(!length(nif().human.damaged_limbs()))
			if(mode || active)
				nif().notify("User Status: NORMAL. Medichines deactivating.")
//Needs fixing W << 'sound/voice/nifmedsynth_normal.ogg'
				deactivate()
			return TRUE

		if(!mode && !active)
			nif().notify("User Status: DAMAGED. Medichines performing minor repairs.",TRUE)
//Needs fixing W << 'sound/voice/nifmedsynth_injured.ogg'
			activate()

		for(var/obj/item/organ/external/EO as anything in nif().human.damaged_limbs())
			for(var/datum/affliction/wound/W as anything in EO.get_wounds())
				if(W.damage <= 30)
					W.heal_damage(0.1)
					EO.update_damages()
					nif().use_charge(0.1)
					return TRUE //Return entirely, we only heal one at a time.
				else if(mode == 1)
					mode = 2
					nif().notify("Medichines unable to repair all damage. Perform manual repairs.",TRUE)
				else if(mode == 2 && HP_percent < -0.4)
					nif().notify("User Status: CRITICAL. Notifying medical!",TRUE)
					S << 'sound/voice/nifmed_critical.ogg'
					mode = 0
					if(!isbelly(S.loc)) //Not notified in case of vore, for gameplay purposes.
						var/turf/T = get_turf(S)
						var/obj/item/radio/headset/a = new /obj/item/radio/headset/heads/captain(null)
						a.autosay("[S.real_name] is in critical condition, located at ([T.x],[T.y],[T.z])!", "[S.real_name]'s NIF", "Medical")
						spent(a)

		/* //Chomp Comment out, using our solution instead of their backport and edit of our solution.
		if(mode == 2 && HP_percent < -0.4) //lets inform someone who might be able to help us that we got toasted and roasted
			nif.notify("User Status: CRITICAL. Notifying medical!",TRUE)
			mode = 3 //this does nothing except stop it from repeating over and over and over and over and over and over and over
			if(!isbelly(S.loc)) //Not notified in case of vore, for gameplay purposes.
				var/turf/T = get_turf(S)
				var/obj/item/radio/headset/a = new /obj/item/radio/headset/heads/captain(null)
				a.autosay("[S.real_name] is in a critical condition, located at ([T.x],[T.y],[T.z])!", "[S.real_name]'s NIF", "Medical")
				spent(a)
		*/ //Chomp comment out END

		return TRUE
"########),"actual111 untraced rank26863 whole physical /datum/nifsoft/medichines_syn.life; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26864_life_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/mesons/life()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		if(H.client)
			H.claim_global_hud(GLOB.global_hud.meson)
"########),"actual111 untraced rank26864 whole physical /datum/nifsoft/mesons.life; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26865_activate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/mindbackup/activate()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		SStranscore.m_backup(H.mind,H.nif,one_time = TRUE)
		persist_nif_data(H)
		nif().notify("Mind backed up!")
		nif().use_charge(0.1)
		deactivate()
		return TRUE
"########),"actual111 untraced rank26865 whole physical /datum/nifsoft/mindbackup.activate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26866_deactivate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/mindbackup/deactivate(force = FALSE)
	if((. = ..()))
		return TRUE
"########),"actual111 untraced rank26866 whole physical /datum/nifsoft/mindbackup.deactivate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26868_life_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/nightvis/life()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		if(H.client)
			H.claim_global_hud(GLOB.global_hud.nvg)
"########),"actual111 untraced rank26868 whole physical /datum/nifsoft/nightvis.life; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26870_life_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define REAGENT_ID_NUMBENZYME "numbenzyme"
/datum/nifsoft/painkillers/life()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		H.bloodstr.add_reagent(REAGENT_ID_NUMBENZYME,0.5)
"########),"actual111 untraced rank26870 whole physical /datum/nifsoft/painkillers.life; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26872_activate_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define PROC_REF(X) (nameof(.proc/##X))
#define QDELETED(X) (isnull(X) || QDELING(X))
#define QDELING(X) (X.gc_destroyed)
#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))
/datum/nifsoft/sizechange/activate()
	if((. = ..()))
		var/obj/item/nif/implant = nif()
		var/datum/prompt/number/ask
		if(implant?.human && !QDELETED(implant.human))
			ask = open_request(src, /datum/prompt/number, PROC_REF(size_chosen), answerer = implant.human, timeout = 0, step = 1, question = "Put the desired size (25-200%), or (1-600%) in dormitory areas.", title = "Set Size", default = 200, max_value = 600, min_value = 1, subject = implant)
		rel_set(src, nameof(size_prompt), ask)
		// This is a pulse: the answer can outlive its original implanted owner.
		after(src, 0, PROC_REF(deactivate))
"########),"actual111 untraced rank26872 whole physical /datum/nifsoft/sizechange.activate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26874_deactivate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/sizechange/deactivate(force = FALSE)
	if((. = ..()))
		return TRUE
"########),"actual111 untraced rank26874 whole physical /datum/nifsoft/sizechange.deactivate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26879_activate_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define PROC_REF(X) (nameof(.proc/##X))
/datum/nifsoft/soulcatcher/activate()
	if((. = ..()))
		show_settings(nif().human)
		after(src, 0, PROC_REF(deactivate))
"########),"actual111 untraced rank26879 whole physical /datum/nifsoft/soulcatcher.activate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26880_deactivate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/soulcatcher/deactivate(force = FALSE)
	if((. = ..()))
		return TRUE
"########),"actual111 untraced rank26880 whole physical /datum/nifsoft/soulcatcher.deactivate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26882_install_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define NIF_FLAGS_OTHER		4
#define NIF_O_SCOTHERS			0x20
/datum/nifsoft/soulcatcher/install()
	if((. = ..()))
		//nif.set_flag(NIF_O_SCOTHERS,NIF_FLAGS_OTHER)	//Only required on install if the flag is in the default setting_flags list defined few lines above.
		if(nif()?.human)
			grant(nif().human, granted_verb(/mob/proc/nsay), src)
			grant(nif().human, granted_verb(/mob/proc/nme), src)
"########),"actual111 untraced rank26882 whole physical /datum/nifsoft/soulcatcher.install; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26883_uninstall_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/soulcatcher/uninstall()
	rel_clear(src, nameof(brainmobs))
	if((. = ..()) && nif()?.human) //Sometimes NIFs are deleted outside of a human
		revoke(nif().human, granted_verb(/mob/proc/nsay), src)
		revoke(nif().human, granted_verb(/mob/proc/nme), src)
"########),"actual111 untraced rank26883 whole physical /datum/nifsoft/soulcatcher.uninstall; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26886_notify_into_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define MESSAGE_TYPE_NIF "nif"
#define span_bold(str) ("<span class='bold'>" + str + "</span>")
#define span_nif(str) ("<span class='nif'>" + str + "</span>")
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
/datum/nifsoft/soulcatcher/proc/notify_into(message)
	var/obj/item/nif/nif_item = nif()
	var/sound = nif_item.good_sound

	message = " " + span_bold("Soulcatcher") + " displays, \"" + span_notice(span_nif("[message]")) + "\""

	to_chat(nif().human,
			type = MESSAGE_TYPE_NIF,
			html = span_nif(span_bold("\[[icon2html(nif_item.big_icon, nif().human)]NIF\]") + message))
	nif().human << sound

	for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
		to_chat(CS,
				type = MESSAGE_TYPE_NIF,
				html = span_nif(span_bold("\[[icon2html(nif_item.big_icon, CS.client)]NIF\]") + message))
		CS << sound
"########),"actual111 untraced rank26886 whole physical /datum/nifsoft/soulcatcher.notify_into; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26890_soul_settings_stage_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define MAX_MESSAGE_LEN       4096
#define NIF_SC_ALLOW_EARS			0x4
#define NIF_SC_ALLOW_EYES			0x8
#define NIF_SC_BACKUPS				0x10
#define NIF_SC_CATCHING_ME			0x1
#define NIF_SC_CATCHING_OTHERS		0x2
#define NIF_SC_PROJECTING			0x20
#define PROC_REF(X) (nameof(.proc/##X))
#define open_request(owner, request_type, handler, fields...) request_open(owner, request_type, handler, list(fields))
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
/datum/nifsoft/soulcatcher/proc/soul_settings_stage(mob/living/carbon/human/H, list/soul_answers, mob/living/carbon/brain/caught_soul/selected_soul)
	var/settings_list = list(
	"Catching You \[[setting_flags & NIF_SC_CATCHING_ME ? "Enabled" : "Disabled"]\]" = NIF_SC_CATCHING_ME,
	"Catching Prey \[[setting_flags & NIF_SC_CATCHING_OTHERS ? "Enabled" : "Disabled"]\]" = NIF_SC_CATCHING_OTHERS,
	"Ext. Hearing \[[setting_flags & NIF_SC_ALLOW_EARS ? "Enabled" : "Disabled"]\]" = NIF_SC_ALLOW_EARS,
	"Ext. Vision \[[setting_flags & NIF_SC_ALLOW_EYES ? "Enabled" : "Disabled"]\]" = NIF_SC_ALLOW_EYES,
	"Mind Backups \[[setting_flags & NIF_SC_BACKUPS ? "Enabled" : "Disabled"]\]" = NIF_SC_BACKUPS,
	"AR Projecting \[[setting_flags & NIF_SC_PROJECTING ? "Enabled" : "Disabled"]\]" = NIF_SC_PROJECTING,
	"Design Inside",
	"Erase Contents")
	if(!("k150" in soul_answers))
		open_request(src, /datum/prompt/choice/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k150", question = "Select a setting to modify:", title = "Soulcatcher NIFSoft", choices = settings_list)
		return
	var/choice = soul_answers["k150"]
	if(isnull(choice))
		return
	if(choice in settings_list)
		switch(choice)

			if("Design Inside")
				if(!("k155" in soul_answers))
					open_request(src, /datum/prompt/text/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k155", question = "Type what the prey sees after being 'caught'. This will be printed after an intro ending with: \"Around you, you see...\" to the prey. If you already have prey, this will be printed to them after \"Your surroundings change to...\". Limit 2048 char.", title = "VR Environment", default = html_decode(inside_flavor), max_len = MAX_MESSAGE_LEN*2, multiline = TRUE)
					return
				var/new_flavor = soul_answers["k155"]
				if(isnull(new_flavor))
					return
				inside_flavor = new_flavor
				nif().notify("Updating VR environment...")
				for(var/mob/living/carbon/brain/caught_soul/CS as anything in brainmobs)
					to_chat(CS,span_notice("Your surroundings change to...") + "\n[inside_flavor]")
				save_settings()
				return TRUE

			if("Erase Contents")
				if(!("k164" in soul_answers))
					open_request(src, /datum/prompt/choice/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k164", question = "Select a mind to delete:", title = "Erase Mind", choices = brainmobs)
					return
				var/mob/living/carbon/brain/caught_soul/brainpick = selected_soul
				if(isnull(brainpick))
					return

				if(!("k166" in soul_answers))
					open_request(src, /datum/prompt/choice/soulcatcher_settings, PROC_REF(soul_settings_answered), answerer = nif().human, settings_operator = H, selected_soul = selected_soul, soul_answers = soul_answers, soul_key = "k166", question = "Are you SURE you want to erase \"[brainpick]\"?", title = "Erase Mind", choices = list("CANCEL","DELETE"), buttons = TRUE)
					return
				var/warning = soul_answers["k166"]
				if(isnull(warning))
					return
				if(warning == "DELETE")
					rel_remove(src, nameof(brainmobs), brainpick)
				return TRUE

			//Must just be a flag without special handling then.
			else
				var/flag = settings_list[choice]
				return toggle_setting(flag)
"########),"actual111 untraced rank26890 whole physical /datum/nifsoft/soulcatcher.soul_settings_stage; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26896_activate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/spare_breath/activate()
	if(!(filled > 50))
		nif().notify("Respirocytes not saturated!",TRUE)
		return FALSE
	if((. = ..()))
		nif().notify("Now taking air from reserves.")
"########),"actual111 untraced rank26896 whole physical /datum/nifsoft/spare_breath.activate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26897_deactivate_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/spare_breath/deactivate(force = FALSE)
	if((. = ..()))
		nif().notify("Now taking air from environment and refilling reserves.")
"########),"actual111 untraced rank26897 whole physical /datum/nifsoft/spare_breath.deactivate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26898_life_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/spare_breath/life()
	if((. = ..()))
		if(active) //Supplying air, not recharging it
			switch(filled) //Text warnings
				if(75)
					nif().notify("Respirocytes at 75% saturation.",TRUE)
				if(50)
					nif().notify("Respirocytes at 50% saturation!",TRUE)
				if(25)
					nif().notify("Respirocytes at 25% saturation, seek a habitable environment!",TRUE)
				if(5)
					nif().notify("Respirocytes at 5% saturation! Failure imminent!",TRUE)

			if(filled == 0) //Ran out
				deactivate()
			else //Drain a little
				filled--

		else //Recharging air, not supplying it
			if(filled == 100)
				return TRUE
			else if(nif().use_charge(0.1) && ++filled == 100)
				nif().notify("Respirocytes now fully saturated.")
"########),"actual111 untraced rank26898 whole physical /datum/nifsoft/spare_breath.life; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26900_life_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/nifsoft/thermals/life()
	if((. = ..()))
		var/mob/living/carbon/human/H = nif().human
		if(H.client)
			H.claim_global_hud(GLOB.global_hud.thermal)
"########),"actual111 untraced rank26900 whole physical /datum/nifsoft/thermals.life; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26901_activate_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define REGISTRY_ALT_FARMANIMALS "alt_farmanimals"
#define REGISTRY_HUMANS "human_mob_list"
#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
/datum/nifsoft/worldbend/activate()
	if((. = ..()))
		var/list/justme = list(nif().human)
		for(var/human in REGISTRY_MEMBERS(REGISTRY_HUMANS))
			if(human == nif().human)
				continue
			var/mob/living/carbon/human/H = human
			H.display_alt_appearance("animals", justme)
			registry_join(REGISTRY_ALT_FARMANIMALS, nif().human)
"########),"actual111 untraced rank26901 whole physical /datum/nifsoft/worldbend.activate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank26902_deactivate_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define REGISTRY_ALT_FARMANIMALS "alt_farmanimals"
#define REGISTRY_HUMANS "human_mob_list"
#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
/datum/nifsoft/worldbend/deactivate(force = FALSE)
	if((. = ..()))
		var/list/justme = list(nif().human)
		for(var/human in REGISTRY_MEMBERS(REGISTRY_HUMANS))
			if(human == nif().human)
				continue
			var/mob/living/carbon/human/H = human
			H.hide_alt_appearance("animals", justme)
			registry_leave(REGISTRY_ALT_FARMANIMALS, nif().human)
"########),"actual111 untraced rank26902 whole physical /datum/nifsoft/worldbend.deactivate; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27057_check_completion_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/objective/heist/loot/check_completion()
	var/total_amount = 0

	for(var/obj/O in locate(/area/shuttle/skipjack)) // Shuttle area pathname
		if(istype(O, loot_path)) total_amount++
		for(var/obj/I in contents_of(O))
			if(istype(I, loot_path)) total_amount++
		if(total_amount >= target_amount) return 1

	for(var/datum/mind/raider in antag_raiders().current_antagonists)
		if(raider.current)
			for(var/obj/O in raider.current.get_contents())
				if(istype(O, loot_path)) total_amount++
				if(total_amount >= target_amount) return 1

	return 0
"########),"actual111 untraced rank27057 whole physical /datum/objective/heist/loot.check_completion; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27294_parse_begin_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define INFINITY				(1.#INF)	//closer then enough
#define MAP_DMM "dmm"
#define MAP_TGM "tgm"
#if DM_VERSION >= 515
#define RUSTG_CALL call_ext
#else
#define RUSTG_CALL call
#endif
#ifndef RUST_G
#define RUST_G (__rust_g || __detect_rust_g())
#endif
	#define file2text(fname) rustg_file_read("[fname]")
#define rustg_file_read(fname) RUSTG_CALL(RUST_G, "file_read")(fname)
/datum/parsed_map/proc/parse_begin(tfile, x_lower = -INFINITY, x_upper = INFINITY, y_lower = -INFINITY, y_upper=INFINITY, z_lower = -INFINITY, z_upper=INFINITY, measureOnly=FALSE)
	if(isfile(tfile))
		original_path = "[tfile]"
		tfile = file2text(tfile)
	else if(isnull(tfile))
		// create a new datum without loading a map
		return FALSE

	src.bounds = parsed_bounds = list(1.#INF, 1.#INF, 1.#INF, -1.#INF, -1.#INF, -1.#INF)

	if(findtext(tfile, matches_tgm))
		map_format = MAP_TGM
	else
		map_format = MAP_DMM // Fallback

	ps_text = tfile
	ps_index = 1
	ps_x_lower = x_lower
	ps_x_upper = x_upper
	ps_y_lower = y_lower
	ps_y_upper = y_upper
	ps_z_lower = z_lower
	ps_z_upper = z_upper
	ps_measure_only = measureOnly
	return TRUE
"########),"actual111 untraced rank27294 whole physical /datum/parsed_map.parse_begin; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27295_parse_step_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define CHECK_TICK ( TICK_CHECK ? stoplag() : 0 )
#define MAP_MAXX 4
#define MAP_MAXY 5
#define MAP_MAXZ 6
#define MAP_MINX 1
#define MAP_MINY 2
#define MAP_MINZ 3
#define TICK_CHECK ( TICK_USAGE > Kernel.current_ticklimit )
#define TICK_USAGE world.tick_usage
/datum/parsed_map/proc/parse_step(matches, yield = FALSE)
	// lists are structs don't you know :)
	var/list/bounds = src.bounds
	var/list/grid_models = src.grid_models
	var/key_len = src.key_len
	var/line_len = src.line_len
	var/x_lower = ps_x_lower
	var/x_upper = ps_x_upper
	var/y_lower = ps_y_lower
	var/y_upper = ps_y_upper
	var/z_lower = ps_z_lower
	var/z_upper = ps_z_upper
	var/measureOnly = ps_measure_only

	var/stored_index = ps_index
	var/list/regexOutput
	//multiz lool
	while(matches-- > 0)
		if(!dmm_regex.Find(ps_text, stored_index))
			break
		stored_index = dmm_regex.next
		// Datum var lookup is expensive, this isn't
		regexOutput = dmm_regex.group

		// "aa" = (/type{vars=blah})
		if(regexOutput[1]) // Model
			var/key = regexOutput[1]
			if(grid_models[key]) // Duplicate model keys are ignored in DMMs
				continue
			if(key_len != length(key))
				if(!key_len)
					key_len = length(key)
				else
					CRASH("Inconsistent key length in DMM")
			if(!measureOnly)
				grid_models[key] = regexOutput[2]

		// (1,1,1) = {"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
		else if(regexOutput[3]) // Coords
			if(!key_len)
				CRASH("Coords before model definition in DMM")

			var/curr_x = text2num(regexOutput[3])
			if(curr_x < x_lower || curr_x > x_upper)
				continue

			var/curr_y = text2num(regexOutput[4])
			if(curr_y < y_lower || curr_y > y_upper)
				continue

			var/curr_z = text2num(regexOutput[5])
			if(curr_z < z_lower || curr_z > z_upper)
				continue

			var/datum/grid_set/gridSet = new

			gridSet.xcrd = curr_x
			gridSet.ycrd = curr_y
			gridSet.zcrd = curr_z

			bounds[MAP_MINX] = min(bounds[MAP_MINX], curr_x)
			bounds[MAP_MINZ] = min(bounds[MAP_MINZ], curr_z)
			bounds[MAP_MAXZ] = max(bounds[MAP_MAXZ], curr_z)

			var/list/gridLines = splittext(regexOutput[6], "\n")
			gridSet.gridLines = gridLines

			var/leadingBlanks = 0
			while(leadingBlanks < length(gridLines) && gridLines[++leadingBlanks] == "")
			if(leadingBlanks > 1)
				gridLines.Cut(1, leadingBlanks) // Remove all leading blank lines.

			if(!length(gridLines)) // Skip it if only blank lines exist.
				continue

			rel_add(src, nameof(gridSets), gridSet)

			if(gridLines[length(gridLines)] == "")
				gridLines.Cut(length(gridLines)) // Remove only one blank line at the end.

			bounds[MAP_MINY] = min(bounds[MAP_MINY], gridSet.ycrd)
			gridSet.ycrd += length(gridLines) - 1 // Start at the top and work down
			bounds[MAP_MAXY] = max(bounds[MAP_MAXY], gridSet.ycrd)

			if(!line_len)
				line_len = length(gridLines[1])

			var/maxx = curr_x
			if(length(gridLines)) //Not an empty map
				maxx = max(maxx, curr_x + line_len / key_len - 1)

			bounds[MAP_MAXX] = max(bounds[MAP_MAXX], maxx)
		if(yield)
			CHECK_TICK
	src.key_len = key_len
	src.line_len = line_len
	ps_index = stored_index
	// Another match may remain: only the text past the last one proves otherwise, so look once more.
	if(matches > 0)
		return FALSE
	return TRUE
"########),"actual111 untraced rank27295 whole physical /datum/parsed_map.parse_step; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27309_tgm_build_cache_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define INFINITY				(1.#INF)	//closer then enough
#define LAZYOR(L, I) do { if(!L) { L = list(); } L |= I; } while(0)
#define SPACE_KEY "space"
#define stack_trace(message) _stack_trace(message, __FILE__, __LINE__)
/datum/parsed_map/proc/tgm_build_cache(no_changeturf, bad_paths=null, models = INFINITY)
	if(!cache_building)
		if(modelCache && !bad_paths)
			return modelCache
		modelCache = list()
		cache_at = 0
		cache_space_set = FALSE
		cache_building = TRUE
	. = modelCache
	var/list/grid_models = src.grid_models
	// Use where a list is needed, but where it will not be modified
	// Used here to remove the cost of needing to make a new list for each fields entry when it's set manually later
	var/static/list/default_list = GLOB.map_model_default // It's stupid, but it saves += list(list)
	var/static/list/wrapped_default_list = list(default_list) // It's stupid, but it saves += list(list)
	var/static/regex/var_edits = var_edits_tgm

	var/path_to_init = ""
	// Reference to the attributes list we're currently filling, if any
	var/list/current_attributes
	// If we are currently editing a path or not
	var/editing = FALSE
	for(var/cache_index in cache_at + 1 to length(grid_models))
		if(models-- <= 0)
			return modelCache
		cache_at = cache_index
		var/model_key = grid_models[cache_index]
		// We're going to split models by newline
		// This guarentees that each entry will be of interest to us
		// Then we'll process them step by step
		// Hopefully this reduces the cost from read_list that we'd otherwise have
		var/list/lines = splittext(grid_models[model_key], "\n")
		// Builds list of path/edits for later
		// Of note: we cannot preallocate them to save time in list expansion later
		// But fortunately lists allocate at least 8 entries normally anyway, and
		// We are unlikely to have more then that many members
		//will contain all members (paths) in model (in our example : /turf/open/fixed/wall)
		var/list/members = list()
		//will contain lists filled with corresponding variables, if any (in our example : list(icon_state = "rock") and list())
		var/list/members_attributes = list()

		/////////////////////////////////////////////////////////
		//Constructing members and corresponding variables lists
		////////////////////////////////////////////////////////
		// string representation of the path to init
		for(var/line in lines)

			switch(line[length(line)])
				if(";") // Var edit, we'll apply it
					// Var edits look like \tname = value;
					// I'm gonna try capturing them with regex, since it ought to be the fastest here
					// Should hand back key = value
					var_edits.Find(line)
					var/value = parse_constant(var_edits.group[2])
					if(istext(value))
						value = apply_text_macros(value)
					current_attributes[var_edits.group[1]] = value
					continue // Keep on keeping on brother
				if("{") // Start of an edit, and so also the start of a path
					editing = TRUE
					current_attributes = list() // Init the list we'll be filling
					members_attributes += list(current_attributes)
					path_to_init = copytext(line, 1, -1)
				if(",") // Either the end of a path, or the end of an edit
					if(editing) // it was the end of a path
						editing = FALSE
						continue
					members_attributes += wrapped_default_list // We know this is a path, and we also know it has no vv's. so we'll just set this to the default list
					// Drop the last char mind
					path_to_init = copytext(line, 1, -1)
				if("}") // Gotta be the end of an area edit, let's check to be sure
					if(editing) // it was the end of an area edit (shouldn't do those anyhow)
						editing = FALSE
						continue
					stack_trace("ended a line on JUST a }, with no ongoing edit. What? Area shit?")
				else // If we're editing, this is a var edit entry. the last one in a stack, cause god hates me. Otherwise, it's an area
					if(editing) // I want inline I want inline I want inline
						// Var edits look like \tname = value;
						// I'm gonna try capturing them with regex, since it ought to be the fastest here
						// Should hand back key = value
						var_edits.Find(line)
						var/value = parse_constant(var_edits.group[2])
						if(istext(value))
							value = apply_text_macros(value)
						current_attributes[var_edits.group[1]] = value
						continue // Keep on keeping on brother

					members_attributes += wrapped_default_list // We know this is a path, and we also know it has no vv's. so we'll just set this to the default list
					path_to_init = line

			// Alright, if we've gotten to this point, our string is a path
			// Oh and we don't trim it, because we require no padding for these
			// Saves like 1.5 deciseconds
			var/atom_def = text2path(path_to_init) //path definition, e.g /obj/foo/bar

			if(!ispath(atom_def, /atom))
				// A type that became a row of a variant family (code/content/variants/variant_alias.dm): the parent, with the row's vars as
				// edits. The map's own edit lines come after this one and replace the row's values.
				var/alias = variant_alias_of(path_to_init)
				if(alias)
					atom_def = saved_type_path(alias)
					var/list/row_edits = variant_edits_of(alias)
					if(editing)
						for(var/row_var in row_edits)
							current_attributes[row_var] = row_edits[row_var]
					else
						members_attributes[length(members_attributes)] = row_edits
			if(!ispath(atom_def, /atom)) // Skip the item if the path does not exist.  Fix your crap, mappers!
				if(bad_paths)
					// Rare case, avoid the var to save time most of the time
					LAZYOR(bad_paths[copytext(line, 1, -1)], model_key)
				continue
			// Index is already incremented either way, just gotta set the path and all
			members += atom_def

		//check and see if we can just skip this turf
		//So you don't have to understand this horrid statement, we can do this if
		// 1. the space_key isn't set yet
		// 2. no_changeturf is set
		// 3. there are exactly 2 members
		// 4. with no attributes
		// 5. and the members are world.turf and world.area
		// Basically, if we find an entry like this: "XXX" = (/turf/default, /area/default)
		// We can skip calling this proc every time we see XXX
		if(!cache_space_set \
			&& no_changeturf \
			&& members_attributes.len == 2 \
			&& members.len == 2 \
			&& members_attributes[1] == default_list \
			&& members_attributes[2] == default_list \
			&& members[2] == world.area \
			&& members[1] == world.turf
		)
			cache_space_set = TRUE
			.[SPACE_KEY] = model_key
			continue

		.[model_key] = list(members, members_attributes)
	cache_building = FALSE
	return .
"########),"actual111 untraced rank27309 whole physical /datum/parsed_map.tgm_build_cache; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27329_ui_act_transform_size_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define DF_VAR_EDITED			(1<<0)
#define TRANSFORM_COMPLEX_MATRIX_IDENTITY list(1,0,0, 0,1,0, 0,0,1, 0,0,0)
#define TRANSFORM_MATRIX_IDENTITY list(1,0,0, 0,1,0)
#define TRANSFORM_PROJECTION_MATRIX_IDENTITY list(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
/datum/particle_editor/proc/ui_act_transform_size(datum/act/op/A, new_value)
	var/static/list/matrix_size = list("Simple Matrix" = 6, "Complex Matrix" = 12, "Projection Matrix" = 16)
	var/new_size = matrix_size[new_value]
	if(!new_size)
		return FALSE
	. = TRUE
	target().particles.datum_flags |= DF_VAR_EDITED
	if(!target().particles.transform || length(target().particles.transform) != new_size)
		switch(new_size)
			if(6)
				target().particles.transform = list(1,0,0, 1,0,0) // TRANSFORM_MATRIX_IDENTITY seems wrong for only particles?
			if(12)
				target().particles.transform = TRANSFORM_COMPLEX_MATRIX_IDENTITY
			if(16)
				target().particles.transform = TRANSFORM_PROJECTION_MATRIX_IDENTITY
		return
"########),"actual111 untraced rank27329 whole physical /datum/particle_editor.ui_act_transform_size; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27330_ui_act_edit_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define DF_VAR_EDITED			(1<<0)
#define GEN_BOX "box"
#define GEN_VECTOR "vector"
#define PROC_REF(X) (nameof(.proc/##X))
#define P_DATA_GENERATOR "generator"
#define P_DATA_GRADIENT "gradient"
#define P_DATA_ICON_ADD "icon_add"
#define P_DATA_ICON_REMOVE "icon_remove"
#define P_DATA_ICON_WEIGHT "icon_edit"
#define UNSETEMPTY(L) do { if (L && !length(L)) L = null } while(0)
#define islist(L) istype(L, /list)
/datum/particle_editor/proc/ui_act_edit(datum/act/op/A, new_value, var_arg, var_mod_arg)
	var/mob/user = A.actor
	if(!isnull(new_value) && !islist(new_value))
		return FALSE
	var/particles/owner = target().particles
	var/param_var_name = var_arg
	if(!(param_var_name in owner.vars))
		return FALSE
	var/var_value = new_value
	var/var_mod = var_mod_arg
	// we can only return arrays from tgui so lets convert it to something usable if needed
	switch(var_mod)
		if(P_DATA_GENERATOR)
			//these MUST be vectors and the others MUST be floats
			if(var_value[1] in list(GEN_VECTOR, GEN_BOX))
				if(!islist(var_value[2]))
					var_value[2] = list(var_value[2],var_value[2],var_value[2])
				if(!islist(var_value[3]))
					var_value[3] = list(var_value[3],var_value[3],var_value[3])
			//this means we just switched off a vector-requiring generator type
			else if(islist(var_value[2]) && islist(var_value[3]))
				var_value[2] = var_value[1]
				var_value[3] = var_value[1]
			var_value = generator(arglist(var_value))
		if(P_DATA_ICON_ADD)
			// the icon questions are a sequence of their own (the icon is added when they are answered)
			ask_sequence_begin(src, /datum/ask_sequence/picker/icon_pick, user, null, null, PROC_REF(icon_added), null, null, list("pick_only" = TRUE))
			return FALSE
		if(P_DATA_ICON_REMOVE)
			for(var/file in owner.icon)
				if("[file]" == var_value)
					owner.icon -= file
			UNSETEMPTY(owner.icon)
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE
		if(P_DATA_ICON_WEIGHT)
			// [filename, new_weight]
			var/list/mod_data = var_value
			for(var/file in owner.icon)
				if("[file]" == mod_data[1])
					owner.icon[file] = mod_data[2]
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE
		if(P_DATA_GRADIENT)
			var/list/new_grad_list = list()
			for(var/entry in var_value)
				new_grad_list += entry // Unpackage nested lists
			owner.gradient = new_grad_list
			target().particles.datum_flags |= DF_VAR_EDITED
			return TRUE

	owner.vars[param_var_name] = var_value // ALLOW(api): admin particle editor
	target().particles.datum_flags |= DF_VAR_EDITED
	return TRUE
"########),"actual111 untraced rank27330 whole physical /datum/particle_editor.ui_act_edit; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27332_icon_added_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define DF_VAR_EDITED			(1<<0)
#define islist(L) istype(L, /list)
/datum/particle_editor/proc/icon_added(datum/ask_sequence/picker/icon_pick/asked)
	var/var_value = asked.get("result")
	if(!var_value || !target())
		return
	var/particles/owner = target().particles
	var/list/new_values = list()
	new_values += var_value
	new_values[var_value] = 1
	if(isicon(owner.icon))
		new_values[owner.icon] = 1
		owner.icon = new_values
	else if(islist(owner.icon))
		owner.icon[var_value] = 1
	else
		owner.icon = new_values
	target().particles.datum_flags |= DF_VAR_EDITED
	SStgui.update_uis(src)
"########),"actual111 untraced rank27332 whole physical /datum/particle_editor.icon_added; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27333_apply_particle_type_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define DF_VAR_EDITED			(1<<0)
/datum/particle_editor/proc/apply_particle_type(new_type)
	target().particles = new new_type
	target().particles.datum_flags |= DF_VAR_EDITED
	return TRUE
"########),"actual111 untraced rank27333 whole physical /datum/particle_editor.apply_particle_type; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27409_page_data_ranks_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define GLOBAL_PROC_REF(X) (/proc/##X)
#define NONE 0
#define RANK_SOURCE_DB "rank_db"
#define RANK_SOURCE_TEMPORARY "rank_temp"
#define R_DBRANKS (1<<17)
#define R_PERMISSIONS (1<<7)
/datum/permissions_panel/proc/page_data_ranks()
	var/list/data = list()
	// Pull admin->rank mapping from DB to feed "held by" counts.
	var/list/admins_by_rank = list()
	for(var/list/row as anything in db_rows?["admins"])
		var/admin_rank_text = row[2]
		for(var/datum/admin_rank/composed_rank as anything in ranks_from_rank_name(admin_rank_text))
			admins_by_rank[composed_rank.name] ||= list()
			admins_by_rank[composed_rank.name] |= list(row[1])
	for(var/stored_key in GLOB.admin_datums)
		var/datum/admins/live_holder = GLOB.admin_datums[stored_key]
		for(var/datum/admin_rank/composed_rank as anything in live_holder.ranks)
			admins_by_rank[composed_rank.name] ||= list()
			admins_by_rank[composed_rank.name] |= list(stored_key)

	// Collect rank rows from DB + live datums (DB is source of truth where it has the rank).
	var/list/all_ranks = list()
	for(var/list/row as anything in db_rows?["ranks"])
		all_ranks[row[1]] = list(
			"rank" = row[1],
			"flags" = text2num("[row[2]]"),
			"exclude_flags" = text2num("[row[3]]"),
			"can_edit_flags" = text2num("[row[4]]"),
		)
	for(var/datum/admin_rank/rank as anything in GLOB.admin_ranks)
		if(all_ranks[rank.name])
			continue
		all_ranks[rank.name] = list(
			"rank" = rank.name,
			"flags" = rank.include_rights,
			"exclude_flags" = rank.exclude_rights,
			"can_edit_flags" = rank.can_edit_rights,
		)
	sortTim(all_ranks, GLOBAL_PROC_REF(cmp_text_asc), associative = TRUE)

	var/list/rows = list()
	for(var/rank_name in all_ranks)
		var/list/datum/admin_rank/rank_datums = ranks_from_rank_name(rank_name)
		if(!length(rank_datums))
			continue
		var/datum/admin_rank/rank_datum = rank_datums[1]
		var/list/rank_info = all_ranks[rank_name]
		var/can_modify = FALSE
		var/can_delete = FALSE
		if((rank_datum.source == RANK_SOURCE_DB && admin_can(holder().owner(), R_DBRANKS)) || rank_datum.source == RANK_SOURCE_TEMPORARY)
			can_modify = TRUE
			can_delete = TRUE
		if(length(admins_by_rank[rank_name]) != 0)
			can_delete = FALSE
		if((holder().can_edit_rights_flags() & rank_datum.rights) != rank_datum.rights)
			can_modify = FALSE
			can_delete = FALSE
		rows += list(list(
			"name" = rank_name,
			"source" = rank_datum.pretty_print_source(),
			"held_by" = length(admins_by_rank[rank_name]),
			"permissions" = rights2text(rank_info["flags"], seperator = " ", prefix = "+"),
			"denied" = rights2text(rank_info["exclude_flags"], seperator = " ", prefix = "-"),
			"editable" = rights2text(rank_info["can_edit_flags"], seperator = " ", prefix = "*"),
			"can_modify" = !!can_modify,
			"can_delete" = !!can_delete,
		))
	data["rows"] = rows
	data["loading"] = !db_rows || isnull(db_rows["admins"]) || isnull(db_rows["ranks"])
	data["can_create"] = admin_can(holder().owner(), R_PERMISSIONS) && holder().can_edit_rights_flags() != NONE
	return data
"########),"actual111 untraced rank27409 whole physical /datum/permissions_panel.page_data_ranks; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27458_Shutdown_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define to_file(file_entry, source_var) file_entry << source_var
/datum/persistent/proc/Shutdown()
	if(fexists(filename))
		fdel(filename)

	var/list/to_store = list()
	for(var/thing in slot_datums(persistence_tracking_values()[type]))
		if(!IsValidEntry(thing))
			continue
		to_store[++to_store.len] = CompileEntry(thing)

	if(to_store.len)
		to_file(file(filename), json_encode(to_store))
"########),"actual111 untraced rank27458 whole physical /datum/persistent.Shutdown; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27486_Shutdown_whole_function_baseline(){assert!(census_first_group_receipt(r########"#if DM_VERSION >= 515
#define RUSTG_CALL call_ext
#else
#define RUSTG_CALL call
#endif
#define RUSTG_HASH_MD5 "md5"
#ifndef RUST_G
#define RUST_G (__rust_g || __detect_rust_g())
#endif
	#define md5(thing) (isfile(thing) ? rustg_hash_file(RUSTG_HASH_MD5, "[thing]") : rustg_hash_string(RUSTG_HASH_MD5, thing))
#define rustg_hash_file(algorithm, fname) RUSTG_CALL(RUST_G, "hash_file")(algorithm, fname)
#define rustg_hash_string(algorithm, text) RUSTG_CALL(RUST_G, "hash_string")(algorithm, text)
#define to_file(file_entry, source_var) file_entry << source_var
/datum/persistent/paintings/Shutdown()
	for(var/obj/structure/sign/painting/P in persistence_painting_frames())
		P.save_persistent()

	if(SSpersistence.painting_count() > max_entries)
		var/this_many = SSpersistence.painting_count()
		var/over = this_many - max_entries
		log_admin("There are [over] more painting(s) stored than the maximum allowed.")
		while(over > 0)
			var/list/d = persistence_all_paintings()[1]
			var/png_filename = "data/paintings/[d["persistence_id"]]/[d["md5"]].png"
			fdel(png_filename)
			if(SSpersistence.remove_painting(d))
				log_admin("A painting was deleted")
			else
				log_and_message_admins("Attempted to delete a painting, but failed.", null)
			over --

	if(fexists(filename))
		fdel(filename)
	to_file(file(filename), json_encode(persistence_all_paintings()))
"########),"actual111 untraced rank27486 whole physical /datum/persistent/paintings.Shutdown; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27526_get_surroundings_whole_function_baseline(){assert!(census_first_group_receipt(r########"#define LAZYADDASSOCLIST(L, K, V) do { if(!L) { L = list(); } L[K] += list(V); } while(0)
#define isitem(D)		istype(D, /obj/item)
/datum/personal_crafting/proc/get_surroundings(atom/a, list/blacklist=null)
	. = list()
	.["tool_qualities"] = list() // List of tool types available
	.["other"] = list()          // List of reagents/material stacks available
	.["instances"] = list()      // List of /obj/items available, maybe?
	.["machinery"] = list()      // List of /obj/machinery available
	for(var/obj/object in get_environment(a, blacklist))
		if(isitem(object))
			var/obj/item/item = object
			LAZYADDASSOCLIST(.["instances"], item.type, item)
			if(istype(item, /obj/item/stack))
				var/obj/item/stack/stack = item
				.["other"][item.type] += stack.get_amount()
			else if(item.tool_qualities)
				.["tool_qualities"] |= item.tool_qualities
				.["other"][item.type] += 1
			else
				if(istype(item, /obj/item/reagent_containers))
					var/obj/item/reagent_containers/container = item
					if(container.is_open_container()) // this isn't exactly the same
						for(var/datum/reagent/reagent in container.reagents.reagent_list)
							.["other"][reagent.type] += reagent.volume
				.["other"][item.type] += 1
		else if (istype(object, /obj/machinery))
			LAZYADDASSOCLIST(.["machinery"], object.type, object)
"########),"actual111 untraced rank27526 whole physical /datum/personal_crafting.get_surroundings; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_untraced_rank27535_crafting_materials_available_whole_function_baseline(){assert!(census_first_group_receipt(r########"/datum/personal_crafting/proc/crafting_materials_available(list/surroundings, datum/xform/R, list/resolved)
	var/list/needed = crafting_sheets_needed(R, resolved)
	var/list/instances = surroundings["instances"]
	for(var/instance_path in instances)
		for(var/obj/item/stack/material/stock in instances[instance_path])
			if(stock.material?.name in needed)
				needed[stock.material.name] -= stock.get_amount()
	for(var/material_id in needed)
		if(needed[material_id] > 0)
			return FALSE
	return TRUE
"########),"actual111 untraced rank27535 whole physical /datum/personal_crafting.crafting_materials_available; diagnostic baseline, fixture refusal is not automatically a wholeproject grammar frontier");}

#[test]fn actual_original_census111_grouped_return_slot_alarmmonitor_activate_whole_source(){assert!(census_first_group_receipt(r########"/datum/nifsoft/alarmmonitor/activate()
	if((. = ..()))
		tgarscreen.tgui_interact(nif().human)
		return TRUE
"########),"whole actual nifsoft function keeps exact groupedreturn-slot assignment and current child receipts");}

#[test]fn actual_original_census111_grouped_return_slot_alarmmonitor_deactivate_whole_source(){assert!(census_first_group_receipt(r########"/datum/nifsoft/alarmmonitor/deactivate(force = FALSE)
	if((. = ..()))
		return TRUE
"########),"whole actual nifsoft function keeps exact groupedreturn-slot assignment and current child receipts");}

#[test]fn actual_original_census111_grouped_return_slot_commlink_uninstall_whole_source(){assert!(census_first_group_receipt(r########"#define OWN_DELETE 1
/datum/nifsoft/commlink/uninstall()
	var/obj/item/nif/lnif = nif() //Awkward. Parent clears it in an attempt to clean up.
	if((. = ..()) && lnif)
		own_clear(lnif, nameof(lnif.comm), OWN_DELETE)
"########),"whole actual nifsoft function keeps exact groupedreturn-slot assignment and current child receipts");}

#[test]fn actual_original_census111_grouped_return_slot_condition_isolate(){assert!(census_first_group_receipt(r########"/datum/probe/proc/check(flag)
    if((.=..()))
        return flag
    return null
"########),"actual groupDot=ParentCall condition keeps expression/condition authority distinct from DATA shape");}

#[test]fn actual_original_census111_grouped_return_slot_and_condition_isolate(){assert!(census_first_group_receipt(r########"/datum/probe/proc/check(flag)
    if((.=..()) && flag)
        return flag
    return null
"########),"actual groupDot=ParentCall condition keeps expression/condition authority distinct from DATA shape");}

#[test]fn actual_original_nested_index_postfix_whole_prepare_solver(){assert!(census_first_group_receipt(r########"#define MATERIAL_POWER_EDGE_A 1
#define MATERIAL_POWER_EDGE_B 2
/datum/material_power_graph/proc/prepare_solver()
	if(solver_source_edges == edges)
		return
	solver_source_edges = edges
	numeric_topology = null
	var/count = length(vertices)
	var/list/adjacency = new /list(count)
	var/list/degrees = new /list(count)
	var/list/removed = new /list(count)
	for(var/i in 1 to count)
		adjacency[i] = list()
	for(var/list/edge as anything in edges)
		var/list/a = adjacency[edge[MATERIAL_POWER_EDGE_A]]
		var/list/b = adjacency[edge[MATERIAL_POWER_EDGE_B]]
		a += list(edge)
		b += list(edge)
		degrees[edge[MATERIAL_POWER_EDGE_A]]++
		degrees[edge[MATERIAL_POWER_EDGE_B]]++
	var/list/pending = list()
	for(var/i in 2 to count)
		if(degrees[i] == 1)
			pending += i
	leaf_order = list()
	while(length(pending))
		var/leaf = pending[length(pending)]
		pending.len--
		if(removed[leaf])
			continue
		removed[leaf] = TRUE
		for(var/list/edge as anything in adjacency[leaf])
			var/parent = edge[MATERIAL_POWER_EDGE_A] == leaf ? edge[MATERIAL_POWER_EDGE_B] : edge[MATERIAL_POWER_EDGE_A]
			if(removed[parent])
				continue
			leaf_order += list(list(leaf, parent, edge))
			degrees[parent]--
			if(parent != 1 && degrees[parent] == 1)
				pending += parent
	core_vertices = list()
	core_edges = list()
	for(var/i in 2 to count)
		if(!removed[i])
			core_vertices += i
	for(var/list/edge as anything in edges)
		if(!removed[edge[MATERIAL_POWER_EDGE_A]] && !removed[edge[MATERIAL_POWER_EDGE_B]])
			core_edges += list(edge)
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}

#[test]fn actual_original_empty_catch_whole_url_entered(){assert!(census_first_group_receipt(r########"#define PROC_REF(X) (nameof(.proc/##X))
/datum/media_track_add/proc/url_entered(datum/act/request/A)
	url = A.answer?.value
	if(!url)
		return
	var/json
	try
		json = json_decode(url)
	catch // ALLOW(silent_catch): malformed input is the expected failure; the caller handles null
	if(islist(json))
		SSmedia_tracks.manual_track_entered(A.request.answerer, src)
		return
	ask_text(A.request.answerer, PROC_REF(title_entered), "Track Title", "REQUIRED: Provide title for track")
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}

#[test]fn actual_original_colon_write_whole_parse_assignment(){assert!(census_first_group_receipt(r########"#define LAZYADD(L, I) do { if(!L) { L = list(); } L += I; } while(0)
/datum/n_Parser/nS_Parser/proc/ParseAssignment()
	var/name=curToken().value
	var/datum/n_scriptOptions/nS_Options/script_options = options()
	if(!script_options.IsValidID(name))
		rel_add(src, nameof(errors), new/datum/scriptError/InvalidID(curToken()))
		return
	NextToken()
	var/t=script_options.assign_binary_operator(curToken().value)
	var/datum/node/statement/VariableAssignment/stmt=new()
	rel_set(stmt, nameof(stmt.var_name), new /datum/node/identifier(name))
	NextToken()
	if(t)
		rel_set(stmt, nameof(stmt.value), new t())
		stmt.value:exp=new/datum/node/expression/value/variable(name) // its own identifier: the statement owns var_name
		stmt.value:exp2=ParseExpression()
	else
		rel_set(stmt, nameof(stmt.value), ParseExpression())
	LAZYADD(curBlock().statements, stmt)
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}

#[test]fn actual_original_nested_index_postfix_actual_leaf_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(list/degrees,list/edge)
	degrees[edge[1]]++
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}

#[test]fn actual_original_colon_root_write_actual_leaf_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(new_objective,stmt,name)
	new_objective:target=null
	stmt.value:exp=new/datum/node/expression/value/variable(name)
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}

#[test]fn actual_original_empty_catch_continuation_and_unsupported_child_isolations(){assert!(census_first_group_receipt(r########"/proc/probe(value)
	try
		value=1
	catch // real empty catch continuation
	if(value)
		return value
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}

#[test]fn actual_original_empty_catch_boundary_never_grants_child_expression(){assert!(!census_first_group_receipt(r########"/proc/probe(value)
	try
		value=1
	catch
	if(value)
		locate(1,2,3,4)
"########),"whole actual physical or explicit isolate; same genuine OriginalHost, no semantic stubs");}


#[test]fn actual_original_census111_read_call_stats_reset_whole_source(){assert!(census_first_group_receipt(r########"#define KM_MAX_SYSTEMS 192
/datum/km_stats_set/proc/reset()
	for(var/i in 1 to KM_MAX_SYSTEMS)
		var/datum/system_stats/S = systems[i]
		if(S)
			spent(S)
			systems[i] = null
	ticks = 0
	overruns = 0
	max_streak = 0
	mark_start()
	input.reset()
	rollup_base = null
"########),"whole actual physical function with genuine macros");}

#[test]fn actual_original_census111_read_call_can_start_id_whole_source(){assert!(census_first_group_receipt(r########"#define ASCII_A 65
#define ASCII_Z 90
#define ASCII_LOWER_A 97
#define ASCII_LOWER_Z 122
#define ASCII_DOLLAR 36 // $
#define ASCII_ZERO 48
#define ASCII_NINE 57
#define ASCII_UNDERSCORE 95	// _
/datum/n_scriptOptions/proc/CanStartID(char) //returns true if the character can start a variable, function, or keyword name (by default letters or an underscore)
	if(!isnum(char))char=text2ascii(char)
	return (char in ASCII_A to ASCII_Z) || (char in ASCII_LOWER_A to ASCII_LOWER_Z) || char==ASCII_UNDERSCORE || char==ASCII_DOLLAR
"########),"whole actual physical function with genuine macros");}

#[test]fn actual_original_census111_read_call_is_digit_whole_source(){assert!(census_first_group_receipt(r########"#define ASCII_A 65
#define ASCII_Z 90
#define ASCII_LOWER_A 97
#define ASCII_LOWER_Z 122
#define ASCII_DOLLAR 36 // $
#define ASCII_ZERO 48
#define ASCII_NINE 57
#define ASCII_UNDERSCORE 95	// _
/datum/n_scriptOptions/proc/IsDigit(char)
	if(!isnum(char))char=text2ascii(char)
	return char in ASCII_ZERO to ASCII_NINE
"########),"whole actual physical function with genuine macros");}

#[test]fn actual_original_census111_dynamic_new_inline_keyword_actual_leaf_isolate(){assert!(census_first_group_receipt(r########"/proc/probe(kw)
    kw=new kw(inline=1)
    return kw
"########),"actual ParseExpression leaf isolate only; no wholefunction or semanticstub claim");}

#[test]fn actual_original_inline_postfix_whole_heist_check_completion(){assert!(census_first_group_receipt(r########"/datum/objective/heist/loot/check_completion()
	var/total_amount = 0

	for(var/obj/O in locate(/area/shuttle/skipjack)) // Shuttle area pathname
		if(istype(O, loot_path)) total_amount++
		for(var/obj/I in contents_of(O))
			if(istype(I, loot_path)) total_amount++
		if(total_amount >= target_amount) return 1

	for(var/datum/mind/raider in antag_raiders().current_antagonists)
		if(raider.current)
			for(var/obj/O in raider.current.get_contents())
				if(istype(O, loot_path)) total_amount++
				if(total_amount >= target_amount) return 1

	return 0
"########));}

#[test]fn actual_original_inline_postfix_real_if_control_and_hidden_separator(){
 assert!(census_first_group_receipt("/proc/probe(O,path)\n    var/count=0\n    if(istype(O,path)) count++\n    if(istype(O,path)) count--\n    return count\n"));
 assert!(!census_first_group_receipt("/proc/probe(O,path)\n    if(istype(O,path)); count++\n    return 0\n"));
}

#[test]fn actual_original_empty_while_current_sibling_with_real_prefix_key(){
 assert!(census_first_group_receipt(r########"/proc/probe(gridLines)
    var/leadingBlanks=0
    while(leadingBlanks < length(gridLines) && gridLines[++leadingBlanks] == "")
    if(leadingBlanks > 1)
        gridLines.Cut(1,leadingBlanks)
    return leadingBlanks
"########));
 assert!(!census_first_group_receipt("/proc/probe()\n    while(check())\n"));
}

#[test]fn actual_original_interpolated_associative_list_key_keeps_real_template_child(){
 assert!(census_first_group_receipt(r########"/proc/probe(setting_flags)
    var/list/settings = list("Catching You \[[setting_flags & 0x1 ? "Enabled" : "Disabled"]\]" = 0x1)
"########),"actual soul_settings_stage first-key shape and genuine templateVALUE children, not a static-string named key");
}
#[test]fn actual_original_outer_member_assignment_chain_keeps_real_infinity_list(){
 assert!(census_first_group_receipt("/proc/probe()\n    src.bounds = parsed_bounds = list(1.#INF, 1.#INF, 1.#INF, -1.#INF, -1.#INF, -1.#INF)\n"),"actual parse_begin assignment leaf, wholefunction separately reselected");
}
#[test]fn actual_original_infinity_list_values_need_no_new_scalar_policy(){
 assert!(census_first_group_receipt("/proc/probe()\n    var/list/parsed_bounds = list(1.#INF, -1.#INF)\n"),"independent genuine OriginalHost scalar list control isolates existingInfinityVALUE support from root-chain grammar");
}

#[test]fn actual_original_register_work_whole_physical_diagnostic(){assert!(census_first_group_receipt(r########"/datum/controller/kernel/proc/register_work(owner_type, datum/work_item/W)
	W.owner_type = owner_type
	W.test_owned = !isnull(test_now)
	if(!W.handler && !istype(W, /datum/work_item/stage))
		CRASH("kernel_register_work: a work item for [owner_type] has no handler")
	W.name ||= "[W.handler]"
	W.set_key(W.item_key(owner_type))
	if(istype(W, /datum/work_item/stage))
		var/datum/work_item/stage/S = W
		W.set_key("[owner_type]:stage:[S.stage_type]")
	var/datum/work_item/old = work_by_key[W.key]
	if(old)
		work_all -= old
		work_by_owner[owner_type] -= old
		if(old.members)
			work_by_members[old.members] -= old
	work_all += W
	var/list/mine = work_by_owner[owner_type]
	if(!mine)
		mine = work_by_owner[owner_type] = list()
	mine += W
	work_by_key[W.key] = W
	if(W.members)
		W.member_list = member_list_for(W.members)
		var/list/watching = work_by_members[W.members]
		if(!watching)
			watching = work_by_members[W.members] = list()
		watching += W
	if(ispath(W.members, /datum/capability) && !cap_wanted[W.members])
		cap_wanted[W.members] = TRUE
		kernel_backfill_members(W.members)
	work_dirty = TRUE
	test_dirty = TRUE
	return W
"########),"faithful diagnostic wholefunction or explicit role isolate; no macro/proc/type stubs or first-leaf attribution");}

#[test]fn actual_original_register_work_member_logical_template_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(datum/work_item/W)
	W.name ||= "[W.handler]"
"########),"faithful diagnostic wholefunction or explicit role isolate; no macro/proc/type stubs or first-leaf attribution");}

#[test]fn actual_original_register_work_member_logical_static_string_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(datum/work_item/W)
	W.name ||= "work"
"########),"faithful diagnostic wholefunction or explicit role isolate; no macro/proc/type stubs or first-leaf attribution");}

#[test]fn actual_original_register_work_member_plain_template_control(){assert!(census_first_group_receipt(r########"/proc/probe(datum/work_item/W)
	W.name = "[W.handler]"
"########),"faithful diagnostic wholefunction or explicit role isolate; no macro/proc/type stubs or first-leaf attribution");}

#[test]fn actual_original_register_work_later_indexed_chain_isolation(){assert!(census_first_group_receipt(r########"/proc/probe(owner_type)
	var/list/mine = work_by_owner[owner_type]
	if(!mine)
		mine = work_by_owner[owner_type] = list()
	return mine
"########),"faithful diagnostic wholefunction or explicit role isolate; no macro/proc/type stubs or first-leaf attribution");}


#[test]fn actual_original_census115_rank19420_whole_physical_update_ui(){assert!(census_first_group_receipt(r########"#define REGISTRY_JANITORIAL_CARTS "all_janitorial_carts"
#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
#define REGISTRY_MOBS "mob_list"
#define REGISTRY_MOPS "all_mops"
#define REGISTRY_MOP_BUCKETS "all_mopbuckets"
#define get_turf(A) get_step(A,0)
/datum/data/pda/app/janitor/update_ui(mob/user, list/data)
	var/JaniData[0]
	var/turf/cl = get_turf(pda())

	if(cl)
		JaniData["user_loc"] = list("x" = cl.x, "y" = cl.y)
	else
		JaniData["user_loc"] = list("x" = 0, "y" = 0)

	var/MopData[0]
	for(var/obj/item/mop/M in REGISTRY_MEMBERS(REGISTRY_MOPS))//GLOB.janitorial_equipment)
		var/turf/ml = get_turf(M)
		if(ml)
			if(ml.z != cl.z)
				continue
			var/direction = get_dir(pda(), M)
			MopData[++MopData.len] = list ("x" = ml.x, "y" = ml.y, "dir" = uppertext(dir2text(direction)), "status" = M.reagents.total_volume ? "Wet" : "Dry")

	var/BucketData[0]
	for(var/obj/structure/mopbucket/B in REGISTRY_MEMBERS(REGISTRY_MOP_BUCKETS))//GLOB.janitorial_equipment)
		var/turf/bl = get_turf(B)
		if(bl)
			if(bl.z != cl.z)
				continue
			var/direction = get_dir(pda(),B)
			BucketData[++BucketData.len] = list ("x" = bl.x, "y" = bl.y, "dir" = uppertext(dir2text(direction)), "volume" = B.reagents.total_volume, "max_volume" = B.reagents.maximum_volume)

	var/CbotData[0]
	for(var/mob/living/bot/cleanbot/B in REGISTRY_MEMBERS(REGISTRY_MOBS))
		var/turf/bl = get_turf(B)
		if(bl)
			if(bl.z != cl.z)
				continue
			var/direction = get_dir(pda(),B)
			CbotData[++CbotData.len] = list("x" = bl.x, "y" = bl.y, "dir" = uppertext(dir2text(direction)), "status" = B.on ? "Online" : "Offline")

	var/CartData[0]
	for(var/obj/structure/janitorialcart/B in REGISTRY_MEMBERS(REGISTRY_JANITORIAL_CARTS))//GLOB.janitorial_equipment)
		var/turf/bl = get_turf(B)
		if(bl)
			if(bl.z != cl.z)
				continue
			var/direction = get_dir(pda(),B)
			CartData[++CartData.len] = list("x" = bl.x, "y" = bl.y, "dir" = uppertext(dir2text(direction)), "volume" = B.mybucket?.reagents.total_volume || 0, "max_volume" = B.mybucket?.reagents.maximum_volume || 0)

	JaniData["mops"] = MopData.len ? MopData : null
	JaniData["buckets"] = BucketData.len ? BucketData : null
	JaniData["cleanbots"] = CbotData.len ? CbotData : null
	JaniData["carts"] = CartData.len ? CartData : null
	data["janitor"] = JaniData
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19433_whole_physical_ui_act_clear(){assert!(census_first_group_receipt(r########"#define LAZYCLEARLIST(L) do { if(L) { L.Cut(); L = null; } } while(0)
#define LAZYREMOVE(L, I) do { if(L) { L -= I; if(!length(L)) { L = null; } } } while(0)
/datum/data/pda/app/messenger/proc/ui_act_clear(datum/act/op/A, option)
	if(!ui_gate(A))
		return FALSE
	. = TRUE
	if(option == "All")
		LAZYCLEARLIST(tnote)
		LAZYCLEARLIST(conversations)
	if(option == "Convo")
		var/new_tnote[0]
		for(var/i in tnote)
			if(i["target"] != active_conversation)
				new_tnote[++new_tnote.len] = i
		tnote = new_tnote
		LAZYREMOVE(conversations, active_conversation)

	active_conversation = null
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19535_whole_physical_update_ui(){assert!(census_first_group_receipt(r########"#define SUP_ORDER_REQUESTED "Requested"
/datum/data/pda/app/supply/update_ui(mob/user, list/data)
	var/supplyData[0]
	var/datum/shuttle/autodock/ferry/supply/shuttle = SSsupply.cargo_shuttle()
	if (shuttle)
		supplyData["shuttle_moving"] = shuttle.has_arrive_time()
		supplyData["shuttle_eta"] = shuttle.eta_minutes()
		supplyData["shuttle_loc"] = shuttle.at_station() ? "Station" : "Dock"
	var/supplyOrderCount = 0
	var/supplyOrderData[0]
	for(var/datum/supply_order/SO as anything in supply_shoppinglist())

		supplyOrderCount++
		supplyOrderData[++supplyOrderData.len] = list("Number" = SO.ordernum, "Name" = html_encode(SO.supply_pack_of().name), "ApprovedBy" = SO.approved_by, "Comment" = html_encode(SO.comment))

	supplyData["approved"] = supplyOrderData
	supplyData["approved_count"] = supplyOrderCount

	var/requestCount = 0
	var/requestData[0]
	for(var/datum/supply_order/SO as anything in supply_order_history())
		if(SO.status != SUP_ORDER_REQUESTED)
			continue

		requestCount++
		requestData[++requestData.len] = list("Number" = SO.ordernum, "Name" = html_encode(SO.supply_pack_of().name), "OrderedBy" = SO.ordered_by, "Comment" = html_encode(SO.comment))

	supplyData["requests"] = requestData
	supplyData["requests_count"] = requestCount

	data["supply"] = supplyData
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19845_whole_physical_compile_behaviour(){assert!(census_first_group_receipt(r########"#define LANE_COUNT 6
#define LANE_SIMULATION 2
#define NONE 0
/datum/definition_registry/proc/compile_behaviour(datum/scheduled_behaviour/B)
	if(B.clock)
		var/datum/clock_definition/C = clock_by_id[B.clock]
		if(!C)
			error("[B.name]: unknown clock [B.clock]")
		else
			B.clock_idx = C.idx
	if(!(B.lane in 1 to LANE_COUNT))
		error("[B.name]: bad lane [B.lane]")
		B.lane = LANE_SIMULATION
	if(B.wake_if)
		B.compiled_wake_if = definition_check_get(B.wake_if, src)
		if(!B.compiled_wake_if)
			error("[B.name]: malformed wake_if")
	B.requires_mask = 0
	if(B.requires)
		B.compiled_requires = list()
		for(var/spec in definition_spec_list(B.requires))
			var/datum/requirement_definition/C = definition_check_get(spec, src)
			if(!C)
				error("[B.name]: malformed requires entry")
				continue
			B.compiled_requires += C
			B.requires_mask |= C.depends_on
	B.interest = B.wake_on | B.requires_mask
	var/list/intervals = list(B.every, B.every, B.every, B.every)
	if(B.relevance)
		if(length(B.relevance) != 4)
			error("[B.name]: relevance needs 4 entries (NONE, NEAR, VISIBLE, WATCHED)")
		else
			for(var/i in 1 to 4)
				if(!isnull(B.relevance[i]))
					intervals[i] = B.relevance[i]
	B.compiled_intervals = intervals
	B.compiled_max_interval = B.max_interval || (max(intervals) * 4)
	if(B.max_interval && B.every && B.max_interval < B.every)
		error("[B.name]: max_interval below every")
	for(var/path in B.order_after)
		if(!behaviour_by_type[path])
			error("[B.name]: order_after names unknown behaviour [path]")
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank20363_whole_physical_do_bump(){assert!(census_first_group_receipt(r########"/datum/dq_topic_op_probe/proc/do_bump(datum/act/op/A, n, who)
	bumped++
	last_n = n
	last_who = who
	last_note = A.topic_href()?["action"]
	return TRUE
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22104_whole_physical_generated_department_turf(){assert!(census_first_group_receipt(r########"/datum/expedition_objective/proc/generated_department_turf(department_id)
	if(!site()?.station_spec || !site().station_materialization)
		return null
	for(var/datum/generated_station_department_instance/department in site().station_spec.departments)
		if(department.id != department_id)
			continue
		var/list/candidate_areas = list()
		var/area/generated_station/department_area = site().station_materialization.department_areas?[department.layout_node_id]
		if(department_area)
			candidate_areas += department_area
		// Planned rooms own their own areas; the department shell may hold only
		// circulation, so fall back to any room area belonging to this department.
		var/datum/generated_station_materialization/station_materialization = site().station_materialization
		for(var/datum/generated_station_module/module in station_materialization.modules)
			if(module.department_node_id != department.layout_node_id)
				continue
			var/area/generated_station/room_area = site().station_materialization.module_areas?[module.id]
			if(room_area)
				candidate_areas += room_area
		for(var/area/generated_station/A as anything in candidate_areas)
			for(var/turf/T in area_contents_of_type(A, /turf))
				// `!locate(...) in T` parsed as `(!locate(...)) in T`, which is never true.
				if(!T.density && !locate_on(T, /obj/machinery/door))
					return T
	return null
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22679_whole_physical_finish_completion_declatration(){assert!(census_first_group_receipt(r########"#define DEAD        2
#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
#define REGISTRY_PLAYERS "player_list"
#define get_turf(A) get_step(A,0)
#define ishuman(A)		istype(A, /mob/living/carbon/human)
#define isobserver(A)	istype(A, /mob/observer/dead)
#define span_bold(str) ("<span class='bold'>" + str + "</span>")
#define span_filter_system(str) ("<span class='filter_system'>" + str + "</span>") // Plain system filter
/datum/game_mode/proc/finish_completion_declatration()
	var/clients = 0
	var/surviving_humans = 0
	var/surviving_total = 0
	var/ghosts = 0
	var/escaped_humans = 0
	var/escaped_total = 0
	var/escaped_on_pod_1 = 0
	var/escaped_on_pod_2 = 0
	var/escaped_on_pod_3 = 0
	var/escaped_on_pod_4 = 0
	var/escaped_on_pod_5 = 0
	var/escaped_on_pod_6 = 0
	var/escaped_on_shuttle = 0
	var/escaped_on_pod_large_1 = 0
	var/escaped_on_pod_large_2 = 0
	var/escaped_on_cryopod = 0

	var/list/area/escape_locations = list(/area/shuttle/escape/centcom, /area/shuttle/cryo/centcom, /area/shuttle/escape_pod1/centcom, /area/shuttle/escape_pod2/centcom, /area/shuttle/escape_pod3/centcom, /area/shuttle/escape_pod5/centcom, /area/shuttle/escape_pod6/centcom, /area/shuttle/large_escape_pod1/centcom
, /area/shuttle/large_escape_pod2/centcom) //Appended /centcom to the escape shuttle again to fix transfer message. Added some escape pods to the list.

	for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(M.client)
			clients++
			var/M_area_type = (get_turf(M))?.loc?.type
			if(ishuman(M))
				if(M.stat != DEAD)
					surviving_humans++
					if(M_area_type in escape_locations)
						escaped_humans++
			if(M.stat != DEAD)
				surviving_total++
				if(is_path_in_list(M_area_type, escape_locations))
					escaped_total++

				if(M_area_type == /area/shuttle/escape/centcom)
					escaped_on_shuttle++

				if(M_area_type == /area/shuttle/escape_pod1/centcom)
					escaped_on_pod_1++
				if(M_area_type == /area/shuttle/escape_pod2/centcom)
					escaped_on_pod_2++
				if(M_area_type == /area/shuttle/escape_pod3/centcom)
					escaped_on_pod_3++
				if(M_area_type == /area/shuttle/escape_pod4/centcom)
					escaped_on_pod_4++
				if(M_area_type == /area/shuttle/escape_pod5/centcom)
					escaped_on_pod_5++
				if(M_area_type == /area/shuttle/escape_pod6/centcom)
					escaped_on_pod_6++
				if(M_area_type == /area/shuttle/large_escape_pod1/centcom)
					escaped_on_pod_large_1++
				if(M_area_type == /area/shuttle/large_escape_pod2/centcom)
					escaped_on_pod_large_2++
				if(M_area_type == /area/shuttle/cryo/centcom)
					escaped_on_cryopod++

			if(isobserver(M))
				ghosts++

	var/text = ""
	if(surviving_total > 0)
		text += "<br>There [surviving_total>1 ? ("were " + span_bold("[surviving_total] survivors")) : ("was " + span_bold("one survivor"))] ("
		text += span_bold("[escaped_total>0 ? escaped_total : "none"] [emergency_shuttle_evac() ? "escaped" : "transferred"]") + ") and " + span_bold("[ghosts] ghosts")
		text += ".<br>"
	else
		text += "There were " + span_bold("no survivors") + " (" + span_bold("[ghosts] ghosts") + ")."
	to_chat(world, span_filter_system(text))

	if(clients > 0)
		feedback_set("round_end_clients",clients)
	if(ghosts > 0)
		feedback_set("round_end_ghosts",ghosts)
	if(surviving_humans > 0)
		feedback_set("survived_human",surviving_humans)
	if(surviving_total > 0)
		feedback_set("survived_total",surviving_total)
	if(escaped_humans > 0)
		feedback_set("escaped_human",escaped_humans)
	if(escaped_total > 0)
		feedback_set("escaped_total",escaped_total)
	if(escaped_on_shuttle > 0)
		feedback_set("escaped_on_shuttle",escaped_on_shuttle)
	if(escaped_on_pod_1 > 0)
		feedback_set("escaped_on_pod_1",escaped_on_pod_1)
	if(escaped_on_pod_2 > 0)
		feedback_set("escaped_on_pod_2",escaped_on_pod_2)
	if(escaped_on_pod_3 > 0)
		feedback_set("escaped_on_pod_3",escaped_on_pod_3)
	if(escaped_on_pod_4 > 0)
		feedback_set("escaped_on_pod_4",escaped_on_pod_4)
	if(escaped_on_pod_5 > 0)
		feedback_set("escaped_on_pod_5",escaped_on_pod_5)
	if(escaped_on_pod_6 > 0)
		feedback_set("escaped_on_pod_6",escaped_on_pod_6)
	if(escaped_on_pod_large_1 > 0)
		feedback_set("escaped_on_pod_large_1",escaped_on_pod_large_1)
	if(escaped_on_pod_large_2 > 0)
		feedback_set("escaped_on_pod_large_2",escaped_on_pod_large_2)
	if(escaped_on_cryopod > 0)
		feedback_set("escaped_on_cryopod",escaped_on_cryopod)
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank23580_whole_physical_return_to_green(){assert!(census_first_group_receipt(r########"#define GENERATED_STATION_ALERT_BLUE 2
#define GENERATED_STATION_ALERT_GREEN 1
/datum/generated_station_defense_runtime/proc/return_to_green(department_id)
	if(director()?.local_alert_levels?[department_id] == GENERATED_STATION_ALERT_BLUE)
		director().set_alert(GENERATED_STATION_ALERT_GREEN, department_id)
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank23582_whole_physical_finish_order(){assert!(census_first_group_receipt(r########"/datum/generated_station_defense_runtime/proc/finish_order(order_id)
	var/datum/generated_station_order/order = director()?.orders?[order_id]
	if(!order)
		return
	var/datum/generated_station_squad/squad = director().squads?[order.squad_id]
	director().complete_order(order.id)
	sleep_squad(squad?.id)
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank23586_whole_physical_on_casualty(){assert!(census_first_group_receipt(r########"#define PROC_REF(X) (nameof(.proc/##X))
#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define SECONDS *10
/datum/generated_station_defense_runtime/proc/on_casualty(datum/generated_station_defender_agent/agent)
	if(!agent || QDELETED(agent))
		return
	casualties++
	var/department_id = agent.department_id
	var/datum/generated_station_squad/squad = director()?.squads?[agent.squad_id]
	if(squad && agent.defender())
		squad.member_ids -= entity_handle_of(agent.defender())
	director()?.unregister_defender(agent.defender())
	own_take_member(src, nameof(agents), agent)
	spent(agent)
	if(department_id == "security-1" && director()?.request_security_reserve())
		after(src, 10 SECONDS, PROC_REF(spawn_reinforcement), with = list("security-1"))
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank23669_whole_physical_start(){assert!(census_first_group_receipt(r########"#ifdef SHARED_CACHE_STATS
#define CACHED_FAST(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) (++_sch_##N && (I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K, ##A))
#else
#define CACHED_FAST(N, K) (_scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) ((I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (_scs_##N[K] || _sc_##N.miss(K, ##A))
#endif
/// The counted form, whatever the build (the benchmark's comparison arm).
#if (defined(UNIT_TESTS) && !defined(BENCHMARK)) || defined(SPACEMAN_DMM)
// Test builds: every hit is verified against the snapshot taken at build time. A benchmark build measures the release path instead.
#define CACHED(N, K) _sc_##N.guarded(K)
#define CACHED_KEY(N, K, A...) _sc_##N.guarded(K, ##A)
#define CACHED_INT(N, I) _sc_##N.guarded_int(I)
#else
#define CACHED(N, K) CACHED_FAST(N, K)
#define CACHED_KEY(N, K, A...) _CACHED_KEY_FAST(N, K, ##A)
#define CACHED_INT(N, I) CACHED_INT_FAST(N, I)
#endif
#define MIDNIGHT_ROLLOVER		864000	//number of deciseconds in a day
#define MIDNIGHT_ROLLOVER_CHECK ( wall_clock().last_timeofday != world.timeofday ? update_midnight_rollover() : wall_clock().rollovers )
#define REALTIMEOFDAY (world.timeofday + (MIDNIGHT_ROLLOVER * MIDNIGHT_ROLLOVER_CHECK))
#if DM_VERSION >= 515
#define RUSTG_CALL call_ext
#else
#define RUSTG_CALL call
#endif
#ifndef RUST_G
#define RUST_G (__rust_g || __detect_rust_g())
#endif
#define TYPE_TABLE_GET(I, N) CACHED_KEY(tt_##N, (I).type, I)
#define rustg_time_reset(id) RUSTG_CALL(RUST_G, "time_reset")(id)
/datum/generated_station_materialization_job/proc/start(datum/generated_station_spec/spec, z_level, origin_x, origin_y)
	started_at = REALTIMEOFDAY
	checkpoint("Preparing station plan", 22)
	// Do not attribute planner/decoder work from the caller's tick to this job.
	peak_tick_usage = 0
	rustg_time_reset(timer_id)
	last_checkpoint_microseconds = 0
	phases = TYPE_TABLE_GET(materializer(), materialize_phases)
	if(!materializer().prepare_materialization(spec, z_level, origin_x, origin_y, src))
		failed = TRUE
		return FALSE
	return TRUE
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19548_whole_physical_makeOnDuty(){assert!(census_first_group_receipt(r########"#define CLOCK_WORLD 0
#define CONFIG_GET(X) global.config.Get(/datum/config_entry/##X)
#define MIDNIGHT_ROLLOVER		864000	//number of deciseconds in a day
#define MIDNIGHT_ROLLOVER_CHECK ( wall_clock().last_timeofday != world.timeofday ? update_midnight_rollover() : wall_clock().rollovers )
#define REALTIMEOFDAY (world.timeofday + (MIDNIGHT_ROLLOVER * MIDNIGHT_ROLLOVER_CHECK))
#define TIME_NOW(clock, owner...) ((clock) ? own_clock_now(owner) : world.time)
#define STAMP(D, name, clock) (D.name = TIME_NOW(clock, D))
#define get_z(A) (get_step(A, 0)?.z || 0)
#define round_duration_in_ds (GLOB.round_start_time ? REALTIMEOFDAY - GLOB.round_start_time : 0)
#define span_danger(str) ("<span class='danger'>" + str + "</span>")
/datum/data/pda/app/timeclock/proc/makeOnDuty(mob/user, newrank, newassignment)
	var/datum/job/oldjob = SSjob.get_job(pda().id.rank)
	var/datum/job/newjob = SSjob.get_job(newrank)
	if(!oldjob || !isOpenOnDutyJob(user, oldjob.pto_type, newjob))
		return
	if(newassignment != newjob.title && !(newassignment in newjob.alt_titles))
		return
	if(newjob.camp_protection && round_duration_in_ds < CONFIG_GET(number/job_camp_time_limit))
		if(SSjob.has_restricted_keys())
			if(SSjob.is_restricted_key(newjob.title, user.client.ckey))
				to_chat(user,span_danger("[newjob.title] is not presently selectable because you played as it last round. It will become available to you in [round((CONFIG_GET(number/job_camp_time_limit) - round_duration_in_ds) / 600)] minutes, if slots remain open."))
				return
	if(newjob)
		newjob.register_shift_key(user.client.ckey)
		pda().id.access = newjob.get_access()
		pda().id.rank = newjob.title
		pda().id.assignment = newassignment
		pda().id.name = text("[pda().id.registered_name]'s ID Card ([pda().id.assignment])")
		GLOB.data_core.manifest_modify(pda().id.registered_name, pda().id.assignment, pda().id.rank)
		STAMP(pda().id, last_job_switch, CLOCK_WORLD)
		callHook("reassign_employee", list(pda().id))
		newjob.current_positions++
		user.mind.assigned_role = text_or_null(pda().id.rank)
		user.mind.role_alt_title = text_or_null(pda().id.assignment)
		announce.autosay("[pda().id.registered_name] has moved On-Duty as [pda().id.assignment].", "Employee Oversight", channel, zlevels = using_map.get_map_levels(get_z(src)))
	return
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19549_whole_physical_makeOffDuty(){assert!(census_first_group_receipt(r########"#define CLOCK_WORLD 0
#define PTO_CIVILIAN		"Civilian"
#define TIME_NOW(clock, owner...) ((clock) ? own_clock_now(owner) : world.time)
#define STAMP(D, name, clock) (D.name = TIME_NOW(clock, D))
#define get_z(A) (get_step(A, 0)?.z || 0)
#define span_notice(str) ("<span class='notice'>" + str + "</span>")
/datum/data/pda/app/timeclock/proc/makeOffDuty(mob/user)
	var/datum/job/foundjob = SSjob.get_job(pda().id.rank)
	if(!foundjob)
		return
	//If we're not in an area that allows clockout and not in a belly, shouldn't be able to clock out.
	if(!isAllowedAreaClockout(user))
		to_chat(user, span_notice("You cannot clock out from your PDA in this area"))
		return
	var/new_dept = foundjob.pto_type || PTO_CIVILIAN
	var/datum/job/ptojob = null
	for(var/datum/job/job in job_occupations())
		if(job.pto_type == new_dept && job.timeoff_factor < 0)
			ptojob = job
			break
	if(ptojob)
		var/oldtitle = pda().id.assignment
		pda().id.access = ptojob.get_access()
		pda().id.rank = ptojob.title
		pda().id.assignment = ptojob.title
		pda().id.name = text("[pda().id.registered_name]'s ID Card ([pda().id.assignment])")
		GLOB.data_core.manifest_modify(pda().id.registered_name, pda().id.assignment, pda().id.rank)
		STAMP(pda().id, last_job_switch, CLOCK_WORLD)
		callHook("reassign_employee", list(pda().id))
		user.mind.assigned_role = ptojob.title
		user.mind.role_alt_title = ptojob.title
		foundjob.current_positions--
		announce.autosay("[pda().id.registered_name], [oldtitle], has moved Off-Duty.", "Employee Oversight", channel, zlevels = using_map.get_map_levels(get_z(src)))
	return
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19567_whole_physical_start(){assert!(census_first_group_receipt(r########"/datum/data/pda/utility/scanmode/start()
	if(pda().scanmode())
		pda().scanmode().name = "Enable [pda().scanmode().base_name]"

	if(pda().scanmode() == src)
		rel_clear(pda(), nameof(/obj/item/pda::scanmode))
	else
		rel_set(pda(), nameof(/obj/item/pda::scanmode), src)
		set_name("Disable [base_name]")

	pda().update_shortcuts()
	return 1
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19577_whole_physical_scan_atom(){assert!(census_first_group_receipt(r########"#define span_notice(str) ("<span class='notice'>" + str + "</span>")
#define span_warning(str) ("<span class='warning'>" + str + "</span>")
/datum/data/pda/utility/scanmode/notes/scan_atom(atom/A, mob/user)
	if(notes() && istype(A, /obj/item/paper))
		var/obj/item/paper/P = A
		var/static/list/brlist = list("p", "/p", "br", "hr", "h1", "h2", "h3", "h4", "/h1", "/h2", "/h3", "/h4")

		// JMO 20140705: Makes scanned document show up properly in the notes. Not pretty for formatted documents,
		// as this will clobber the HTML, but at least it lets you scan a document. You can restore the original
		// notes by editing the note again. (Was going to allow you to edit, but scanned documents are too long.)
		var/raw_scan = sanitize_simple(P.info, list("\t" = "", "Ã¿" = ""))
		var/formatted_scan = ""
		// Scrub out the tags (replacing a few formatting ones along the way)
		// Find the beginning and end of the first tag.
		var/tag_start = findtext(raw_scan, "<")
		var/tag_stop = findtext(raw_scan, ">")
		// Until we run out of complete tags...
		while(tag_start && tag_stop)
			var/pre = copytext(raw_scan, 1, tag_start) // Get the stuff that comes before the tag
			var/tag = lowertext(copytext(raw_scan, tag_start + 1, tag_stop)) // Get the tag so we can do intellegent replacement
			var/tagend = findtext(tag, " ") // Find the first space in the tag if there is one.
			// Anything that's before the tag can just be added as is.
			formatted_scan = formatted_scan + pre
			// If we have a space after the tag (and presumably attributes) just crop that off.
			if(tagend)
				tag = copytext(tag, 1, tagend)
			if(tag in brlist) // Check if it's I vertical space tag.
				formatted_scan = formatted_scan + "<br>" // If so, add some padding in.
			raw_scan = copytext(raw_scan, tag_stop + 1) // continue on with the stuff after the tag
			// Look for the next tag in what's left
			tag_start = findtext(raw_scan, "<")
			tag_stop = findtext(raw_scan, ">")
		// Anything that is left in the page. just tack it on to the end as is
		formatted_scan = formatted_scan + raw_scan
		// If there is something in there already, pad it out.
		if(length(notes().note) > 0)
			notes().note += "<br><br>"
		// Store the scanned document to the notes
		notes().note += formatted_scan
		notes().notetitle = sanitize_simple(P.name, list("\n" = "", "\t" = "", "Ã¿" = ""))
		// update the saved note too incase we kept the pda open, this is really silly due to how the notehtml is actually what's passed to the editor's text.
		// If I don't update it here, it loses the data when you edit it!
		notes().storednotes[notes().currentnote] = notes().note
		notes().storedtitles[notes().currentnote] = notes().notetitle
		notes().notehtml = html_decode(replacetext(notes().note,"<br>", "\n"))
		// Inform the user
		var/scannedtitle = "Paper"
		if(!isnull(notes().notetitle) && notes().notetitle != "")
			scannedtitle = "'[notes().notetitle]'"
		to_chat(user, span_notice("[scannedtitle] scanned to Notekeeper in note [GLOB.alphabet_upper[notes().currentnote]]."))//concept of scanning paper copyright brainoblivion 2009

	else
		to_chat(user, span_warning("Error scanning [A]."))
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank19925_whole_physical_handle_atoms(){assert!(census_first_group_receipt(r########"#define isitem(D)		istype(D, /obj/item)
#define isliving(A)		istype(A, /mob/living)
/datum/digest_mode/egg/handle_atoms(obj/belly/B, list/touchable_atoms)
	if(B.egg_cycles < 10)
		B.egg_cycles ++
		return
	B.egg_cycles = 0
	var/list/egg_contents = list()
	for(var/E in touchable_atoms)
		if(istype(E, /mob/observer))
			continue
		if(istype(E, /obj/item/storage/vore_egg)) // Don't egg other eggs.
			var/obj/item/storage/vore_egg/EG = E
			if(EG.egg_name != B.egg_name)
				if(!B.egg_name)
					EG.set_egg_name(null)
					EG.name = initial(EG.name)
				else
					EG.set_egg_name(B.egg_name)
					EG.name = B.egg_name
			continue
		if(isliving(E))
			var/mob/living/L = E
			if(L.absorbed)
				continue
			egg_contents += L
		if(isitem(E))
			egg_contents += E
	if(egg_contents.len)
		if(!B.ownegg())
			if(B.egg_type in GLOB.tf_vore_egg_types)
				B.egg_path = GLOB.tf_vore_egg_types[B.egg_type]
			rel_set(B, nameof(B.ownegg), new B.egg_path(B))
			if(B.ownegg() && B.egg_name)
				B.ownegg().egg_name = B.egg_name
				B.ownegg().name = B.egg_name
		var/scale_clamp = 1
		for(var/atom/movable/C in egg_contents)
			if(isitem(C) && egg_contents.len == 1) //Only egging one item
				var/obj/item/I = C
				B.ownegg().set_w_class(I.w_class)
				B.ownegg().max_storage_space = B.ownegg().w_class
				B.slot_remove(I, B.ownegg())
				if(B.egg_size)
					B.ownegg().icon_scale_x = B.egg_size
					B.ownegg().icon_scale_y = B.egg_size
				else
					B.ownegg().icon_scale_x = 0.2 * B.ownegg().w_class
					B.ownegg().icon_scale_y = 0.2 * B.ownegg().w_class
				B.ownegg().update_transform()
				egg_contents -= I
				rel_clear(B, nameof(B.ownegg))
				return GLOB.digest_result_update
			if(isitem(C))
				var/obj/item/I = C
				B.ownegg().set_w_class(B.ownegg().w_class + I.w_class) //Let's assume a regular outfit can reach total w_class of 16.
				B.slot_remove(I, B.ownegg())
			if(isliving(C))
				var/mob/living/M = C
				var/mob_holder_type = M.holder_type || /obj/item/holder
				B.ownegg().set_w_class(B.ownegg().w_class + M.size_multiplier * 4) //Egg size and weight scaled to match occupant.
				if(M.size_multiplier > scale_clamp)
					scale_clamp = M.size_multiplier
				var/obj/item/holder/H = new mob_holder_type(B.ownegg(), M)
				B.ownegg().max_storage_space = H.w_class
				egg_contents -= M
		B.ownegg().calibrate_size()
		B.ownegg().orient2hud()
		B.ownegg().set_w_class(clamp(B.ownegg().w_class * 0.25, 1, 8)) //A total w_class of 16 will result in a backpack sized egg.
		if(B.egg_size)
			B.ownegg().icon_scale_x = B.egg_size
			B.ownegg().icon_scale_y = B.egg_size
		else
			B.ownegg().icon_scale_x = clamp(0.25 * B.ownegg().w_class, 0.25, scale_clamp)
			B.ownegg().icon_scale_y = clamp(0.25 * B.ownegg().w_class, 0.25, scale_clamp)
		B.ownegg().update_transform()
		if(B.ownegg().w_class > 4)
			B.ownegg().set_worn_factor(STAT_ITEM_ENCUMBRANCE, 4)
		rel_clear(B, nameof(B.ownegg))
		return GLOB.digest_result_update
	return
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank21798_whole_physical_ui_data(){assert!(census_first_group_receipt(r########"#define REGISTRY_MEMBERS(ID) (GLOB.registry_members[ID])
#define REGISTRY_SILICONS "silicon_mob_list"
#define isAI(A)			istype(A, /mob/living/silicon/ai)
#define section(name, doc...)
/datum/eventkit/modify_robot/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	. = list()
	.["ion_law"] = ion_law
	.["zeroth_law"] = zeroth_law
	.["inherent_law"] = inherent_law
	.["supplied_law"] = supplied_law
	.["supplied_law_position"] = supplied_law_position
	// Target section for general data
	var/datum/asset/spritesheet_batched/robot_icons/spritesheet = target() ? GLOB.robot_sprite_sheets[target().modtype] : null

	if(target())
		.["theme"] = target().get_ui_theme()
		.["target"] = list()
		.["target"]["name"] = target().name
		.["target"]["ckey"] = target().ckey
		.["target"]["module"] = target().module
		.["target"]["emagged"] = target().emagged
		.["target"]["crisis_override"] = target().crisis_override
		.["target"]["active_restrictions"] = target().restrict_modules_to
		var/list/possible_restrictions = list()
		for(var/entry in GLOB.robot_modules)
			if(!(target().restrict_modules_to?.Find(entry)))
				possible_restrictions += entry
		.["target"]["possible_restrictions"] = possible_restrictions
		// Target section for options once a module has been selected
		if(target().module)
			.["target"]["active"] = target().icon_selected
			.["target"]["sprite"] = sanitize_css_class_name("[target().sprite_datum.type]")
			.["target"]["sprite_size"] = spritesheet?.icon_size_id(.["target"]["sprite"] + "S")
			.["target"]["modules"] = get_target_items(user)
			var/list/module_options = list()
			for(var/module in GLOB.robot_modules)
				module_options += module
			.["model_options"] = module_options
			// Data for the upgrade options
			.["target"] += get_upgrades()
			var/obj/item/robot_module/target_module = target().module
			var/obj/item/gun/energy/kinetic_accelerator/kin = locate_in_list(target_module.modules, /obj/item/gun/energy/kinetic_accelerator)
			if(kin)
				.["target"]["pka"] += get_pka(kin)
			for(var/obj/item/robotic_multibelt/multibelt in target_module.modules)
				.["target"]["multibelt"] += list(get_mult_belt(multibelt))

			// Radio section
			var/list/radio_channels = list()
			for(var/channel in target().radio.channels)
				radio_channels += channel
			var/list/availalbe_channels = list()
			for(var/channel in (GLOB.radiochannels - target().radio.channels))
				availalbe_channels += channel
			.["target"]["radio_channels"] = radio_channels
			.["target"]["availalbe_channels"] = availalbe_channels
			// Components
			.["target"]["components"] = get_components()
			.["cell"] = list("name" = target().cell?.name, "charge" = target().cell?.charge, "maxcharge" = target().cell?.maxcharge)
			.["cell_options"] = get_cells()
			.["camera_options"] = get_component("camera")
			.["radio_options"] = get_component("radio")
			.["actuator_options"] = get_component("actuator")
			.["diagnosis_options"] = get_component("diagnosis")
			.["comms_options"] = get_component("comms")
			.["armour_options"] = get_component("armour")
			.["current_gear"] = get_gear()
			// Access
			.["id_icon"] = icon2html(target().idcard, user, sourceonly=TRUE)
			var/list/active_access = list()
			for(var/access in target().idcard?.GetAccess())
				active_access += list(list("id" = access, "name" = SSaccess.get_access_desc(access)))
			.["target"]["active_access"] = active_access
			var/list/access_options = list()
			for(var/datum/access/acc)
				if(acc.id in target().idcard?.GetAccess())
					continue
				access_options += list(list("id" = acc.id, "name" = acc.desc))
			.["access_options"] = access_options
			// Section for source data for the module we might want to salvage
			if(source)
				.["source"] += get_module_source(user, spritesheet)
	var/list/all_robots = list()
	for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_SILICONS))
		if(!R.loc)
			continue
		all_robots += list(list("displayText" = "[R]", "value" = handle_of(R)))
	.["all_robots"] = all_robots
	// Law data
	.["ion_law_nr"] = ionnum()

	package_laws(., "zeroth_laws", list(target().laws.zeroth_law))
	package_laws(., "ion_laws", target().laws.ion_laws)
	package_laws(., "inherent_laws", target().laws.inherent_laws)
	package_laws(., "supplied_laws", target().laws.supplied_laws)

	.["isAI"] = istype(target(), /mob/living/silicon/ai)
	.["isMalf"] = is_malf(user)
	.["isSlaved"] = target().is_slaved()
	var/list/active_ais = list()
	for(var/mob/living/silicon/ai/ai in active_ais())
		if(!ai.loc)
			continue
		active_ais += list(list("displayText" = "[ai]", "value" = handle_of(ai)))
	.["active_ais"] = active_ais
	.["selected_ai"] = selected_ai ? selected_ai : null

	var/list/channels = list()
	for(var/ch_name in target().law_channels())
		channels[++channels.len] = list("channel" = ch_name)
	.["channel"] = target().lawchannel
	.["channels"] = channels
	.["law_sets"] = package_multiple_laws(law_list)
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22258_whole_physical_New(){assert!(census_first_group_receipt(r########"#define islist(L) istype(L, /list)
#define DEFAULTPICK(L, default) ((islist(L) && length(L)) ? pick(L) : default)
#define LAZYADDASSOC(L, K, V) do { if(!L) { L = list(); } L[K] += V; } while(0)
/datum/experiment/scanning/random/New(datum/techweb/techweb)
	// Generate random contents
	if (length(possible_types))
		var/picked = 0
		while (picked < total_requirement)
			var/randum = min(rand(1, total_requirement - picked), max_requirement_per_type) //Short for "random num" and not "this is dum that I have to rename 100 different variable names"
			LAZYADDASSOC(required_atoms, DEFAULTPICK(possible_types, null), randum)
			picked += randum

	// Fill the experiment as per usual
	..()
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22430_whole_physical_icon_value_picked(){assert!(census_first_group_receipt(r########"/datum/filter_editor/proc/icon_value_picked(datum/ask_sequence/picker/icon_pick/asked)
	var/icon/new_icon = asked.get("result")
	if(new_icon && target())
		target().filter_data[asked.kept["name"]]["icon"] = new_icon
		target().update_filters()
		SStgui.update_uis(src)
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22470_whole_physical_tgui_state(){assert!(census_first_group_receipt(r########"#define ADMIN_STATE(required_perms) (GLOB.admin_states[required_perms] ||= new /datum/tgui_state/admin_state(required_perms))
#define R_ADMIN (1<<1)
#define R_DEBUG (1<<5)
#define R_EVENT (1<<14)
/datum/flight_operations_ui/tgui_state(mob/user)
	if(forced_vessel())
		return ADMIN_STATE(R_ADMIN | R_EVENT | R_DEBUG)
	return GLOB.tgui_default_state
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22483_whole_physical_ui_act_toggle_engines(){assert!(census_first_group_receipt(r########"/datum/flight_operations_ui/proc/ui_act_toggle_engines(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel.ship())
		return FALSE
	vessel.ship().engines_state = !vessel.ship().engines_state
	for(var/datum/ship_engine/engine in vessel.ship().engines)
		if(vessel.ship().engines_state == !engine.is_on())
			engine.toggle()
	return TRUE
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank22484_whole_physical_ui_act_thrust_limit(){assert!(census_first_group_receipt(r########"/datum/flight_operations_ui/proc/ui_act_thrust_limit(datum/act/op/A, value)
	if(!ui_gate(A))
		return FALSE
	var/datum/flight_vessel/vessel = resolve_vessel()
	if(!vessel.ship())
		return FALSE
	vessel.ship().thrust_limit = clamp(value / 100, 0, 1)
	for(var/datum/ship_engine/engine in vessel.ship().engines)
		engine.set_thrust_limit(vessel.ship().thrust_limit)
	return TRUE
"########),"whole exact physical function with actual macros; genuine later unissued leaf remains an honest failure");}

#[test]fn actual_original_inline_call_if_else_keeps_both_real_leaf_receipts(){
 assert!(census_first_group_receipt("/proc/probe(value)\n    if(check(value)) deliver(value)\n    else deliver(other(value))\n    return value\n"));
}
#[test]fn actual_original_foreach_inline_if_keeps_body_and_loop_receipts(){
 assert!(census_first_group_receipt("/proc/probe(values)\n    var/total=0\n    for(var/item in values) if(check(item))\n        total++\n        if(total>3)\n            break\n    return total\n"));
}
#[test]fn actual_original_foreach_inline_call_keeps_real_current_close_gap(){
 assert!(census_first_group_receipt("/proc/probe(values)\n    for(var/item in values.Copy()) deliver(item)\n    return 0\n"));
}

#[test]fn actual_original_census115_rank20624_whole_physical_set_up(){assert!(census_first_group_receipt(r########"#define get_turf(A) get_step(A,0)
/datum/effect/system/expl_particles/proc/set_up(n = 10, loca)
	number = n
	if(istype(loca, /turf/)) rel_set(src, nameof(location), loca)
	else rel_set(src, nameof(location), get_turf(loca))
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank20630_whole_physical_set_up(){assert!(census_first_group_receipt(r########"#define get_turf(A) get_step(A,0)
/datum/effect/system/explosion/proc/set_up(loca)
	if(istype(loca, /turf/)) rel_set(src, nameof(location), loca)
	else rel_set(src, nameof(location), get_turf(loca))
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank21441_whole_physical_start(){assert!(census_first_group_receipt(r########"/datum/event/wallrot/start()
	if(center())
		// Make sure at least one piece of wall rots!
		center().rot()

		// Have a chance to rot lots of other walls.
		var/rotcount = 0
		var/actual_severity = severity * rand(5, 10)
		for(var/turf/simulated/wall/W in range(5, center())) if(prob(50))
			W.rot()
			rotcount++

			// Only rot up to severity walls
			if(rotcount >= actual_severity)
				break
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}

#[test]fn actual_original_census115_rank23321_whole_physical_build_content_plan(){assert!(census_first_group_receipt(r########"#define QDEL_LIST(L) if(L) { for(var/I in L.Copy()) qdel(I); L.Cut(); }
/datum/generated_room_definition/proc/build_content_plan(seed, faction_id, style_id)
	var/datum/generated_room_content_plan/plan = new
	plan.definition_id = id
	plan.feature_types = required_features.Copy()
	plan.group_types = required_groups.Copy()
	var/cohesive_fragment = FALSE
	// Every authored room receives one cohesive motif. The solver may reject a
	// footprint that cannot preserve the motif and its circulation contract;
	// Rust should have assigned that program to compatible geometry instead.
	if(length(fragment_options))
		var/datum/generated_station_prng/fragment_prng = new(seed + 3571)
		var/fragment_type = fragment_options[fragment_prng.next_range(1, length(fragment_options))]
		plan.fragment_types += fragment_type
		if(ispath(fragment_type, /datum/generated_room_fragment/activity_motif))
			cohesive_fragment = TRUE
			var/datum/generated_room_fragment/activity_motif/motif = new fragment_type
			for(var/required_type in plan.feature_types.Copy())
				var/datum/generated_room_feature/required_feature = new required_type
				for(var/motif_type in motif.feature_types)
					var/datum/generated_room_feature/motif_feature = new motif_type
					if(motif_feature.atom_type == required_feature.atom_type)
						plan.feature_types -= required_type
					spent(motif_feature)
				spent(required_feature)
			spent(motif)
		spent(fragment_prng)
	var/list/matches = list()
	var/total_weight = 0
	for(var/variant_type in variant_options)
		var/datum/generated_room_variant/variant = new variant_type
		if(variant.matches(faction_id, style_id) && variant.weight > 0)
			matches += variant
			total_weight += variant.weight
		else
			spent(variant)
	if(total_weight)
		var/datum/generated_station_prng/prng = new(seed)
		var/roll = prng.next_range(1, total_weight)
		spent(prng)
		for(var/datum/generated_room_variant/variant in matches)
			roll -= variant.weight
			if(roll > 0)
				continue
			plan.variant_id = variant.id
			plan.feature_types |= variant.added_feature_types
			plan.group_types |= variant.added_group_types
			plan.fragment_types |= variant.added_fragment_types
			break
	QDEL_LIST(matches)
	if(length(optional_groups) && !cohesive_fragment)
		var/datum/generated_station_prng/optional_prng = new(seed + 7919)
		plan.group_types |= optional_groups[optional_prng.next_range(1, length(optional_groups))]
		spent(optional_prng)
	return plan
"########),"whole exact physical function with actual macro/conditional context; later unissued leaf remains an honest failure");}


// Genuine whole-body resource regression. The retained baseline is represented
// by real initialized Vec storage charged to the SAME unchanged128MiB counter;
// it does not mint source authority or pretend a lease is physical payload.
#[test]fn actual_original_list2text_whole_body_keeps_real_paid_preparse_headroom(){
 use std::sync::atomic::Ordering;
 const LIMIT:usize=128*1024*1024;
 const RETAINED_BEFORE_PARSE:usize=133_337_226;
 const HEADROOM_BEFORE_PARSE:usize=880_502;
 struct PaidBallast{payload:Vec<u8>,credit:dm_syntax::SettingRootLease}
 let(raw,counter)=crate::frontend::declaration_checked_tests::with_original_test_host_shared_counter_controls(|raw,limit,counter|{
  assert_eq!(limit.load(Ordering::Acquire),LIMIT,"the genuine Host keeps its existing fixed budget");(raw,std::sync::Arc::clone(counter))
 });
 let front=build_using(ACTUAL_LIST2TEXT_FULL_PHYSICAL_SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();
 let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 let result=raw.with_declaration_admission(&mut|a|{
  assert!(a.uses_counter(&counter),"actual producer and physical ballast share the SAME real counter");
  let before=counter.load(Ordering::Acquire);
  let bytes=RETAINED_BEFORE_PARSE.checked_sub(before).expect("actual fixture must have room for the measured retained baseline");
  let credit=a.reserve(bytes).map_err(BodySyntaxFailure::Operational)?;
  let mut payload=Vec::<u8>::new();payload.try_reserve_exact(bytes).map_err(|error|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error)))?;
  assert_eq!(payload.capacity(),bytes,"actual Vec capacity must match its paid storage before initialization");payload.resize(bytes,0x5a);
  let ballast=PaidBallast{payload,credit};assert_eq!(ballast.payload.len(),ballast.credit.bytes());
  assert_eq!(counter.load(Ordering::Acquire),RETAINED_BEFORE_PARSE);
  assert_eq!(LIMIT-counter.load(Ordering::Acquire),HEADROOM_BEFORE_PARSE);
  let actual=(||{
   let product=input.parse_original_product_with_setting_admission(a)?;
   let syntax=product.parsed().expect("same genuine complete body producer");let parsed=syntax.statements.parsed();
   assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty(),"real diagnostics/pending remain failures: {:?}",parsed.diagnostics);
   let bound=input.bind_original_product_checked(syntax,a)?;
   match bound.original_code_disposition(){Ok(crate::frontend::OriginalBodyDisposition::Available(_))=>Ok(()),Ok(crate::frontend::OriginalBodyDisposition::Skipped(_))=>panic!("real list2text cannot be skipped"),Err(error)=>Err(error)}
  })().map_err(|original|{
   if matches!(&original,BodySyntaxFailure::Operational(_)){if let Some(actual)=a.take_operational_error(){return BodySyntaxFailure::Operational(actual)}}original
  });
  // Payload allocation physically dies before its lease, on success or error.
  drop(ballast);actual
 });
 drop(input);drop(view);drop(front);drop(raw);
 assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"all real fixture/ballast ownership retired before final refund assertion");
 result.expect("same whole physical list2text must parse/bind under measured preparse headroom; no alternate result, cap raise or operational waiver");
}

// Exact physical appearance99 macro/body; no semantic stub or handwritten expansion.
const ACTUAL_APPEARANCE39_REPLAY_SOURCE:&str=r####"/proc/__appearance_v_debug(appearance/A, name, mob/viewer)
	switch(name)
#define DEBUG_APPEARANCE_VAR(n) if(#n) return debug_variable(name, A.n, 0, null, viewer = viewer)
		DEBUG_APPEARANCE_VAR(alpha)
		DEBUG_APPEARANCE_VAR(appearance_flags)
		DEBUG_APPEARANCE_VAR(blend_mode)
		DEBUG_APPEARANCE_VAR(color)
		DEBUG_APPEARANCE_VAR(desc)
		DEBUG_APPEARANCE_VAR(dir)
		DEBUG_APPEARANCE_VAR(gender)
		DEBUG_APPEARANCE_VAR(icon)
		DEBUG_APPEARANCE_VAR(icon_state)
		DEBUG_APPEARANCE_VAR(invisibility)
		DEBUG_APPEARANCE_VAR(infra_luminosity)
		DEBUG_APPEARANCE_VAR(filters)
		DEBUG_APPEARANCE_VAR(layer)
		DEBUG_APPEARANCE_VAR(luminosity)
		DEBUG_APPEARANCE_VAR(maptext)
		DEBUG_APPEARANCE_VAR(maptext_width)
		DEBUG_APPEARANCE_VAR(maptext_height)
		DEBUG_APPEARANCE_VAR(maptext_x)
		DEBUG_APPEARANCE_VAR(maptext_y)
		DEBUG_APPEARANCE_VAR(mouse_over_pointer)
		DEBUG_APPEARANCE_VAR(mouse_drag_pointer)
		DEBUG_APPEARANCE_VAR(mouse_drop_pointer)
		DEBUG_APPEARANCE_VAR(mouse_drop_zone)
		DEBUG_APPEARANCE_VAR(mouse_opacity)
		DEBUG_APPEARANCE_VAR(name)
		DEBUG_APPEARANCE_VAR(opacity)
		DEBUG_APPEARANCE_VAR(overlays)
		DEBUG_APPEARANCE_VAR(override)
		DEBUG_APPEARANCE_VAR(pixel_x)
		DEBUG_APPEARANCE_VAR(pixel_y)
		DEBUG_APPEARANCE_VAR(pixel_w)
		DEBUG_APPEARANCE_VAR(pixel_z)
		DEBUG_APPEARANCE_VAR(plane)
		DEBUG_APPEARANCE_VAR(render_source)
		DEBUG_APPEARANCE_VAR(render_target)
		DEBUG_APPEARANCE_VAR(suffix)
		DEBUG_APPEARANCE_VAR(text)
		DEBUG_APPEARANCE_VAR(transform)
		DEBUG_APPEARANCE_VAR(underlays)
		// DEBUG_APPEARANCE_VAR(vis_flags)
#undef DEBUG_APPEARANCE_VAR
"####;

#[derive(Debug)]struct Appearance39ReplayProbe{production_polls:usize,uncached_polls:usize,replay_after_first_polls:usize,cursors:Vec<dm_syntax::OriginalCaseCursor>,body_start:usize}
fn appearance39_replay_probe(prefix_count:usize,nested:bool,following:bool)->Appearance39ReplayProbe{
 use std::cell::Cell;use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_shared_counter_controls(|raw,limit,counter|{
  assert_eq!(limit.load(Ordering::Acquire),128*1024*1024);
  let mut source=String::new();
  for n in 0..prefix_count{source.push_str(&format!("/proc/__appearance_cursor_unrelated_{n}()\n\treturn 0\n"));}
  if nested{source.push_str("/datum/__appearance_cursor_scope\n");}
  for line in ACTUAL_APPEARANCE39_REPLAY_SOURCE.lines(){
   if nested&&!line.starts_with('#')&&!line.is_empty(){source.push('\t');}
   if nested&&line.starts_with("/proc/__appearance_v_debug("){source.push_str(line.strip_prefix('/').unwrap());}else{source.push_str(line);}
   source.push('\n');
  }
  if following{source.push_str("/proc/__appearance_cursor_following()\n\treturn 1\n");}
  let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();assert!(view.receipt().errors().is_empty(),"genuine source receipt: {:?}",view.receipt().errors());
  let archive=view.archive();let ordinal=archive.occurrences().iter().position(|body|archive.callables().identity_for_member(body.member).is_some_and(|id|id.name==dm_ir::SymbolId::of("__appearance_v_debug"))).unwrap();
  let archived=archive.parse_checked(ordinal).unwrap();let tokens=archived.original_body_tokens().unwrap();let input=archive.syntax_input_checked(ordinal,&||Ok(())).unwrap();
  let calls=Cell::new(0usize);let poll=||{calls.set(calls.get()+1);Ok(())};let a=dm_syntax::SettingAdmission::new(counter,limit.load(Ordering::Acquire),&poll);
  // This is the genuine production provider: its per-parse replay context must
  // actually be reused, rather than testing only a privately constructed hint.
  let product=input.parse_original_product_with_setting_admission(&a).unwrap();let production_polls=calls.get();let parsed=product.parsed().unwrap();let statements=parsed.statements.parsed();assert!(statements.diagnostics.is_empty()&&statements.pending_bodies.is_empty());
  let [switch]=statements.statements.as_slice()else{panic!("one whole physical switch")};let dm_syntax::StatementKind::Switch{cases,else_branch,..}=&switch.kind else{panic!("actual39 case switch")};assert_eq!(cases.len(),39);assert!(else_branch.is_empty());
  let replay=tokens.case_layout_replay();let optimized=replay.attach(tokens).unwrap();let(mut uncached_polls,mut replay_after_first_polls)=(0usize,0usize);let mut cursors=Vec::new();let body_start=archived.occurrence().expanded_span.start;
  let relative=|cursor|match cursor{dm_syntax::OriginalCaseCursor::Token(at)=>dm_syntax::OriginalCaseCursor::Token(dm_syntax::Span::new(at.start-body_start,at.end-body_start)),dm_syntax::OriginalCaseCursor::SourceEnd{offset,fallback}=>dm_syntax::OriginalCaseCursor::SourceEnd{offset:offset-body_start,fallback:dm_syntax::Span::new(fallback.start-body_start,fallback.end-body_start)}};
  for(index,case)in cases.iter().enumerate(){
   assert_eq!(case.body.len(),1);assert!(matches!(&case.body[0].kind,dm_syntax::StatementKind::Return(Some(_))),"each realmacro returns exactlyonce");
   let site=case.original_site;let mut old_calls=0usize;let old=tokens.switch_case_cursor_using(site.header,site.body,&mut||{old_calls+=1;Ok::<(),&'static str>(())}).unwrap();uncached_polls+=old_calls;
   let mut new_calls=0usize;let new=optimized.switch_case_cursor_using(site.header,site.body,&mut||{new_calls+=1;Ok::<(),&'static str>(())}).unwrap();if index!=0{replay_after_first_polls+=new_calls;}
   assert_eq!(new,old,"cachedcursor differs atrealmacrocase{index}");assert_eq!(site.cursor.unwrap(),old,"PRODUCTION providercursor differs atrealmacrocase{index}");cursors.push(relative(old));
  }
  Appearance39ReplayProbe{production_polls,uncached_polls,replay_after_first_polls,cursors,body_start}
 })
}
#[test]fn actual_appearance39_production_replay_keeps_all_cursors_and_prefix_independent_reuse(){
 let small=appearance39_replay_probe(0,false,false);let large=appearance39_replay_probe(2048,false,false);
 assert!(large.body_start>small.body_start+50000,"actual large unrelated prefix must shift this body");assert_eq!(small.cursors,large.cursors);assert_eq!(small.replay_after_first_polls,large.replay_after_first_polls,"afterfirstauthenticprefixscan no unrelated token is repolled");
 assert!(large.production_polls*2<large.uncached_polls,"genuineproductionprovider must reuse prefixstate: {large:?}");
}
#[test]fn actual_appearance39_production_replay_keeps_nested_indent_shift_and_following_body_boundary(){
 for nested in[false,true]{for following in[false,true]{let small=appearance39_replay_probe(0,nested,following);let shifted=appearance39_replay_probe(256,nested,following);assert_eq!(small.cursors,shifted.cursors);assert_eq!(small.replay_after_first_polls,shifted.replay_after_first_polls);}}
}

// Actual Raw135 radio post_signal frontier; positive receipt tests preserve old-code refusal.
#[test]
fn actual_original_radio_post_signal_whole_physical_keeps_real_churn_count_macro(){assert!(census_first_group_receipt(r########"#define CHURN_COUNT(kind, key) GLOB.churn_census.kind[key] += 1
#define get_turf(A) get_step(A,0)
#define RADIO_DEFAULT "radio_default"
/datum/radio_frequency/proc/post_signal(obj/source as obj|null, datum/signal/signal, radio_filter = null as text|null, range = null as num|null)
	CHURN_COUNT(signals, "[frequency] [source?.type]")
	var/turf/start_point
	if(range)
		start_point = get_turf(source)
		if(!start_point)
			signal_release(signal)
			return 0
	if (radio_filter)
		send_to_filter(source, signal, radio_filter, start_point, range)
		send_to_filter(source, signal, RADIO_DEFAULT, start_point, range)
	else
		//Broadcast the signal to everyone!
		for (var/next_filter in devices)
			send_to_filter(source, signal, next_filter, start_point, range)
	signal_release(signal)
"########));}
#[test]
fn actual_original_radio_post_signal_safe_template_key_compound_leaf(){assert!(census_first_group_receipt(r########"/proc/__radio_safe_template_key(frequency, obj/source)
	GLOB.churn_census.signals["[frequency] [source?.type]"] += 1
"########));}
#[test]
fn actual_original_radio_post_signal_safe_template_key_keeps_shifted_local_bindings(){assert!(census_first_group_receipt(r########"
// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.

// Unrelated source prefix shifts the SAME actual local parameter and literal spans.
/proc/__radio_safe_template_key(frequency, obj/source)
	GLOB.churn_census.signals["[frequency] [source?.type]"] += 1
"########));}

// Actual Raw137 refresh_drain frontier: real macro-expanded compound key update.
#[test]
fn actual_original_refresh_drain_whole_physical_keeps_real_churn_count_macros(){assert!(census_first_group_receipt(r########"#define CHURN_COUNT(kind, key) GLOB.churn_census.kind[key] += 1
#define LAZYADD(L, I) do { if(!L) { L = list(); } L += I; } while(0)
#define QDELING(X) (X.gc_destroyed)
#define QDELETED(X) (isnull(X) || QDELING(X))
#define TICK_DELTA_TO_MS(percent_of_tick_used) ((percent_of_tick_used) * world.tick_lag)
#define TICK_USAGE_TO_MS(starting_tickusage) (TICK_DELTA_TO_MS(world.tick_usage - starting_tickusage))
#define TICK_USAGE world.tick_usage
#define KM_SYS_APPEARANCE 5
#define KA_KIND_DRAW 3
#define DEP_CREATED (1<<17)
#define DEP_PARKED (1<<18)
/proc/refresh_drain(datum/time_scheduler/sched)
	rx_drain() // change reactions (on_change / on_cross / observe) run before the outputs
	var/list/Q = GLOB.refresh_queue
	var/datum/km_attr/attr = (sched?.meter || km_meter()).attr
	// review 2 M4: each entity refreshes at most once per drain; one re-queued by its own refresh (or
	// by a chain that comes back to it) waits for the next frame instead of spinning here. The pass stamp (refresh_pass) replaces a per-drain
	// list of the entities already run: a nested drain takes its own pass number, as it had its own list.
	var/pass = ++GLOB.refresh_drain_pass
	var/list/deferred
	var/i = 0
	while(i < length(Q))
		i++
		var/datum/D = Q[i]
		if(isnull(D))
			continue // a hard-deleted queued entity leaves a null entry
		var/queued_slot = slot_known(D)
		if(queued_slot && GLOB.refresh_queue_at[queued_slot] == GLOB.refresh_queue_base + i)
			GLOB.refresh_queue_at -= queued_slot // this entry is consumed (an older duplicate of it leaves the newer one's place alone)
		if(D.refresh_pass == pass)
			LAZYADD(deferred, D)
			continue
		var/pending = D.refresh_queued
		if(pending == DEP_PARKED)
			continue // a stale entry of an atom parked since (refresh_park_backlog()): it keeps owing its first draw
		D.refresh_queued = 0
		if(QDELETED(D))
			D.refresh_bits = 0
			continue
		if(!pending)
			continue // a stale duplicate: an earlier entry already ran its outputs
		var/fresh = pending & DEP_CREATED
		pending &= ~DEP_CREATED
		if(fresh && type_look_stamped(D))
			// Queued at creation before its type's verdict was in, and the type's default look is empty: nothing to draw (look_stamp.dm).
			D.refresh_bits = 0
			GLOB.type_look_stamp_skipped++
			continue
		if(!refresh_wanted_queued(D))
			// Every atom's first refresh is queued at init (caps_init()) before its type's verdict is in: the first
			// instance probes the type, and the rest, queued behind it, skip here once it is known to derive nothing.
			D.refresh_bits = 0
			continue
		D.refresh_pass = pass
		CHURN_COUNT(draws, D.type)
		var/bits = D.refresh_bits
		D.refresh_bits = 0
		GLOB.refresh_bench_drained++
		var/attr_start = TICK_USAGE
		try
			refresh_one(D, bits, pending)
			if(fresh)
				type_look_stamp_record(D)
		catch(var/exception/e)
			if(sched)
				sched.report_caught(e, "refresh of [D.type]: [e] ([e.file]:[e.line])")
			else
				dq_report_caught(e, "refresh of [D.type]")
		attr.note(KA_KIND_DRAW, KM_SYS_APPEARANCE, D.type, km_attr_reason(pending | fresh), TICK_USAGE_TO_MS(attr_start))
		if(sched?.out_of_budget() && i < length(Q))
			Q.Cut(1, i + 1)
			GLOB.refresh_queue_base += i
			for(var/datum/later as anything in deferred)
				refresh_queue_push(later)
			return FALSE
	Q.Cut()
	GLOB.refresh_queue_base = 0 // every place was given back as its entry was consumed
	for(var/datum/later as anything in deferred)
		refresh_queue_push(later)
	if(deferred)
		return FALSE
	return TRUE
"########));}
#[test]
fn actual_original_refresh_drain_member_key_add_leaf(){assert!(census_first_group_receipt(r########"/proc/__refresh_member_key_add(datum/D)
	GLOB.churn_census.draws[D.type] += 1
"########));}
#[test]
fn actual_original_refresh_drain_member_key_add_keeps_shifted_binding(){assert!(census_first_group_receipt(r########"
// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.

// Actual source-local binding and key spans shift with a harmless prefix.
/proc/__refresh_member_key_add(datum/D)
	GLOB.churn_census.draws[D.type] += 1
"########));}
