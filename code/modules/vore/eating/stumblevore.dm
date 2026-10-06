/mob/living/Bump(atom/movable/AM)
	//. = ..()
	if(isliving(AM))
		var/mob/living/L = AM
		if(!L.is_incorporeal())
			if(src?.buckled_to() != AM && (((has_status(STAT_CONFUSED) || is_blind()) && stat == CONSCIOUS && prob(50) && m_intent==I_RUN) || flying && flight_vore))
				AM.stumble_into(src)
	return ..()
// Because flips toggle density
/mob/living/Crossed(atom/movable/AM)
	if(isliving(AM) && isturf(loc) && AM != src)
		var/mob/living/AMV = AM
		if(AMV?.buckled_to() != src && (((AMV.has_status(STAT_CONFUSED) || AMV.is_blind()) && AMV.stat == CONSCIOUS && prob(50) && AMV.m_intent==I_RUN) || AMV.flying && AMV.flight_vore))
			stumble_into(AMV)
	..()

/mob/living/stumble_into(mob/living/M)
	if(src?.buckled_to() || M?.buckled_to())
		return

	//Stumblevore occurs here. Look at the 'stumblevore' element for more information.
	if(guard(src, GUARD_STUMBLED_INTO, M))
		return

	play_sfx(src, SFX_PUNCH, 0.5, extrarange = -1)
	M.status_at_least(STAT_WEAKENED, 4)
	M.stop_flying()

	if(ishuman(src))
		var/mob/living/carbon/human/S = src
		if(S.species.lightweight == 1)
			act_message(M, src, others = span_vwarning("%U% carelessly bowls %T% over!"))
			M.forceMove(get_turf(src))
			M.injure(INJURY_BLUNT, 0.5, source = src)
			status_at_least(STAT_WEAKENED, 4)
			stop_flying()
			injure(INJURY_BLUNT, 0.5, source = M)
			return

	if(round(weight) > 474)
		var/throwtarget = get_edge_target_turf(M, reverse_direction(M.dir))
		act_message(M, src, others = span_vwarning("%U% bounces backwards off of %T%'s plush body!"))
		M.throw_at(throwtarget, 5, 1) //it's funny and nobdy ever takes weight >474 so this is extremely rare
		return

	act_message(M, src, others = span_vwarning("%U% trips over %T%!"))
	M.forceMove(get_turf(src))
	M.injure(INJURY_BLUNT, 1, source = src)
