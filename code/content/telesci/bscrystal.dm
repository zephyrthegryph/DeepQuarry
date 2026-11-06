// This proc turns the BSC or arti-BSC into a phased-creature mine.
/obj/item/bluespace_crystal/Crossed(atom/movable/M)
	. = ..()
	if(istype(M, /mob/living))
		var/mob/living/L = M
		var/datum/shadekin/SK = L.get_shadekin_state()
		if(SK && SK.in_phase)
			var/turf/T = get_turf(src)
			visible_message(span_notice("[src] fizzles and disappears as something interacts with it!"))
			play_sfx(src, SFX_SHATTER, volume = 50)
			fx_sparks(T, 5)
			SK.attack_dephase(T, src)
			destroyed(src, M, BRUTE)


// This proc is the 'Dephase grenade' check. range is changeable. 0=self, 1=3x3, 2=5x5, 3=7x7...
/obj/item/bluespace_crystal/proc/dephase_shadekin()
	var/turf/T = get_turf(src)
	for(var/mob/living/living in range(3, T))
		var/datum/shadekin/SK = living.get_shadekin_state()
		if(SK && SK.in_phase)
			SK.attack_dephase(null, src)
