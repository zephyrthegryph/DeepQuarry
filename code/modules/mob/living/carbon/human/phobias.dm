
/// MED-6: someone with no phobias has nothing to fear. (A phobic mob keeps scanning its view.)
/mob/living/carbon/human/proc/life_phobias_due()
	return src.phobias

/mob/living/carbon/human/proc/life_phobias_rewake()
	return 30 SECONDS

/mob/living/carbon/human/proc/life_phobias(datum/seq_frame/life/F)
	if(!src.phobias)
		return
	if(src.phobias & NYCTOPHOBIA)
		var/turf/T = get_turf(src)
		var/brightness = T.get_lumcount()
		if(brightness < 0.2)
			src.set_fear(min((src.fear + 3), 102))
	if(src.phobias & ARACHNOPHOBIA)
		for (var/mob/living/simple_mob/animal/giant_spider/S in viewers(src, null))
			if(!istype(S) || S.stat)
				continue
			src.set_fear(min((src.fear + 6), 102))
	if(src.phobias & HEMOPHOBIA)
		for(var/obj/effect/decal/cleanable/blood/B in view(7, src))
			if(istype(B, /obj/effect/decal/cleanable/blood/oil) || istype(B, /obj/effect/decal/cleanable/blood/tracks) || istype(B, /obj/effect/decal/cleanable/blood/gibs/robot))
				continue
			src.set_fear(min((src.fear + 2), 102))
		for(var/turf/simulated/floor/water/blood/T in view(7, src))
			src.set_fear(min((src.fear + 2), 102))
	if(src.phobias & THALASSOPHOBIA)
		var/turf/T = get_turf(src)
		if(istype(T,/turf/simulated/floor/water/underwater) || istype(T,/turf/simulated/floor/water/deep))
			src.set_fear(min((src.fear + 4), 102))
	if(src.phobias & CLAUSTROPHOBIA_MINOR)
		if(!isturf(src.loc))
			if(!istype(src.loc,/obj/belly) && !istype(src.loc,/obj/item/holder/micro))
				src.set_fear(min((src.fear + 3), 102))
	if(src.phobias & CLAUSTROPHOBIA_MAJOR) //Also activated inside of a belly
		if(!isturf(src.loc))
			if(!istype(src.loc,/obj/item/holder/micro))
				src.set_fear(min((src.fear + 3), 102))
	if(src.phobias & ANATIDAEPHOBIA)
		for (var/mob/living/simple_mob/animal/space/goose/G in viewers(src, null))
			if(!istype(G) || G.stat)
				continue
			src.set_fear(min((src.fear + 3), 102))
		for (var/mob/living/simple_mob/animal/sif/duck/D in viewers(src, null))
			if(!istype(D) || D.stat)
				continue
			src.set_fear(min((src.fear + 3), 102))
		for(var/obj/item/bikehorn/rubberducky/R in view(7, src))
			if(!istype(R))
				continue
			src.set_fear(min((src.fear + 2), 102))
	if(src.phobias & AGRAVIAPHOBIA)
		if(src.is_floating)
			src.set_fear(min((src.fear + 4), 102))
