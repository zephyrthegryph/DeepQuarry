def edit(p, pairs):
    s=open(p,encoding='utf-8',newline='').read()
    for a,b in pairs:
        assert a in s, a
        s=s.replace(a,b,1)
    open(p,'w',encoding='utf-8',newline='').write(s)

edit('code/engine/change/interest.dm',[(
"""	return !interest_covers(T)

// ---- a client's eye ----""",
"""	return !interest_covers(T)

/// Whether a mark of `D`, which is parked already (it owes its whole first draw), leaves it parked: an atom of a lazy type on a turf nobody holds. The parking judged
/// the instance (look_lazy_ok(): its look at creation fits the type's verdict); what it was written since (a window's smoothing, a cable's direction, anything its init
/// or its life changed) is the look its owed draw will show, so it is not judged again: the type's outputs are its look alone, and the draw comes when a viewer does.
/proc/interest_parked_stays(datum/D)
	if(!isatom(D) || ismob(D))
		return FALSE
	var/atom/A = D
	if(!GLOB.type_look_lazy[A.type] || LAZYLEN(A.open_tguis))
		return FALSE
	var/turf/T = isturf(A) ? A : A.loc
	if(!isturf(T))
		return FALSE
	return !interest_covers(T)

// ---- a client's eye ----""")])

edit('code/engine/change/refresh.dm',[
("""!((E.refresh_queued & DEP_PARKED) && GLOB.interest_defer_marks && interest_defers(E))""",
 """!((E.refresh_queued & DEP_PARKED) && GLOB.interest_defer_marks && interest_parked_stays(E))"""),
("""		if(idle && GLOB.interest_defer_marks && ((mask & DEP_DRAW) || owed) && interest_defers(D))""",
 """		if(idle && GLOB.interest_defer_marks && ((mask & DEP_DRAW) || owed) && (owed ? interest_parked_stays(D) : interest_defers(D)))"""),
("""	if(!A.refresh_queued || A.refresh_queued == DEP_PARKED)
		refresh_mark(A, DEP_ALL)
	if(!var_name || !plan_reader_bits(var_name, A.type))""",
"""	if(A.refresh_queued == DEP_PARKED && GLOB.interest_defer_marks && interest_parked_stays(A))
		GLOB.construction_parked_absorbed++ // it owes its whole first draw already, which will show what these writes made; birth settles it (construction_birth())
	else if(!A.refresh_queued || A.refresh_queued == DEP_PARKED)
		refresh_mark(A, DEP_ALL)
	if(!var_name || !plan_reader_bits(var_name, A.type))"""),
("""GLOBAL_VAR_INIT(construction_writes_published, 0)""",
"""GLOBAL_VAR_INIT(construction_writes_published, 0)
/// Writes an atom under construction made while it was parked for a lazy type: each would have woken it into the queue, and none needs to (construction_note()).
GLOBAL_VAR_INIT(construction_parked_absorbed, 0)"""),
])
