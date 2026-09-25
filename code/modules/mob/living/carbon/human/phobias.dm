/datum/om/stage/life/phobias
	order = LIFE_PHASE_TAIL + 260
	name = "phobias"
	wake_on = 0
	run_if = LIFE_RUN_IF_LIVE_BIOLOGY
	of = /mob/living/carbon/human

/datum/om/stage/life/phobias/perform(mob/living/carbon/human/self, datum/om/frame/life/ctx)
	if(!self.phobias)
		return
	if(self.phobias & NYCTOPHOBIA)
		var/turf/T = get_turf(self)
		var/brightness = T.get_lumcount()
		if(brightness < 0.2)
			self.fear = min((self.fear + 3), 102)
	if(self.phobias & ARACHNOPHOBIA)
		for (var/mob/living/simple_mob/animal/giant_spider/S in viewers(self, null))
			if(!istype(S) || S.stat)
				continue
			self.fear = min((self.fear + 6), 102)
	if(self.phobias & HEMOPHOBIA)
		for(var/obj/effect/decal/cleanable/blood/B in view(7, self))
			if(istype(B, /obj/effect/decal/cleanable/blood/oil) || istype(B, /obj/effect/decal/cleanable/blood/tracks) || istype(B, /obj/effect/decal/cleanable/blood/gibs/robot))
				continue
			self.fear = min((self.fear + 2), 102)
		for(var/turf/simulated/floor/water/blood/T in view(7, self))
			self.fear = min((self.fear + 2), 102)
	if(self.phobias & THALASSOPHOBIA)
		var/turf/T = get_turf(self)
		if(istype(T,/turf/simulated/floor/water/underwater) || istype(T,/turf/simulated/floor/water/deep))
			self.fear = min((self.fear + 4), 102)
	if(self.phobias & CLAUSTROPHOBIA_MINOR)
		if(!isturf(self.loc))
			if(!istype(self.loc,/obj/belly) && !istype(self.loc,/obj/item/holder/micro))
				self.fear = min((self.fear + 3), 102)
	if(self.phobias & CLAUSTROPHOBIA_MAJOR) //Also activated inside of a belly
		if(!isturf(self.loc))
			if(!istype(self.loc,/obj/item/holder/micro))
				self.fear = min((self.fear + 3), 102)
	if(self.phobias & ANATIDAEPHOBIA)
		for (var/mob/living/simple_mob/animal/space/goose/G in viewers(self, null))
			if(!istype(G) || G.stat)
				continue
			self.fear = min((self.fear + 3), 102)
		for (var/mob/living/simple_mob/animal/sif/duck/D in viewers(self, null))
			if(!istype(D) || D.stat)
				continue
			self.fear = min((self.fear + 3), 102)
		for(var/obj/item/bikehorn/rubberducky/R in view(7, self))
			if(!istype(R))
				continue
			self.fear = min((self.fear + 2), 102)
	if(self.phobias & AGRAVIAPHOBIA)
		if(self.is_floating)
			self.fear = min((self.fear + 4), 102)
