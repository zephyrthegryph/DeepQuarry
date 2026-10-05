
//This proc is the most basic of the procs. All it does is make a new mob on the same tile and transfer over a few variables.
//Returns the new mob
//Note that this proc does NOT do MMI related stuff!
/// The mob type change_mob_type() was called without; the rest of its arguments ride along.
/datum/prompt/text/mob_type
	title = "Mob type"
	question = "Mob type path:"
	timeout = 0
	var/turf/location
	var/location_expected = FALSE
	var/new_name
	var/delete_old_mob
	var/subspecies

CAPABILITIES(/datum/prompt/text/mob_type)
	ref_one(nameof(location), /turf)

/datum/prompt/text/mob_type/prepare(datum/act/A)
	. = ..()
	var/turf/captured_location = location
	location_expected = !isnull(captured_location)
	rel_clear(src, nameof(location))
	if(captured_location && !QDELETED(captured_location))
		rel_set(src, nameof(location), captured_location)

/datum/prompt/text/mob_type/recheck_extra()
	if(location_expected && QDELETED(location))
		return "gone"

/mob/proc/mob_type_entered(datum/act/request/A)
	if(!A.answer)
		return
	return mob_type_apply(A)

/mob/proc/mob_type_apply(datum/act/request/A)
	var/datum/prompt/text/mob_type/ask = A.answer
	if(ask.value)
		change_mob_type(ask.value, ask.location, ask.new_name, ask.delete_old_mob, ask.subspecies)

/mob/proc/change_mob_type(new_type = null, turf/location = null, new_name = null as text, delete_old_mob = 0 as num, subspecies)

	if(isnewplayer(src))
		to_chat(src, span_red("cannot convert players who have not entered yet."))
		return

	if(!new_type)
		open_request(src, /datum/prompt/text/mob_type, PROC_REF(mob_type_entered), answerer = src, location = location, new_name = new_name, delete_old_mob = delete_old_mob, subspecies = subspecies)
		return

	if(istext(new_type))
		new_type = text2path(new_type)

	if( !ispath(new_type) )
		to_chat(src, "Invalid type path (new_type = [new_type]) in change_mob_type(). Contact a coder.")
		return

	if( new_type == /mob/new_player )
		to_chat(src, span_red("cannot convert into a new_player mob type."))
		return

	var/mob/M
	if(isturf(location))
		M = new new_type( location )
	else
		M = new new_type( src.loc )

	if(!M || !ismob(M))
		to_chat(src, "Type path is not a mob (new_type = [new_type]) in change_mob_type(). Contact a coder.")
		qdel(M)
		return

	if( istext(new_name) )
		M.name = new_name
		M.real_name = new_name
	else
		M.name = src.name
		M.real_name = src.real_name

	if(src.dna)
		own_clear(M, nameof(M.dna), OWN_DELETE)
		rel_set(M, nameof(M.dna), src.dna.Clone())

	if(isliving(src) && isliving(M))
		move_player(src, M, "admin changed mob type to [new_type]")
	else
		M.key = key // admin tool on an observer or into a non-living mob: first assignment

	if(subspecies && ishuman(M))
		var/mob/living/carbon/human/H = M
		H.set_species(subspecies)

	if(delete_old_mob)
		expire(1)
	return M
