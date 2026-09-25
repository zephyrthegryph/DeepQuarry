//Dionaea regenerate health and nutrition in light.
/datum/om/stage/life/environment/carbon/alien/diona
	of = /mob/living/carbon/alien/diona

/datum/om/stage/life/environment/carbon/alien/diona/exchange(mob/living/carbon/alien/diona/self, datum/gas_mixture/environment)

	var/light_amount = 0 //how much light there is in the place, affects receiving nutrition and healing
	if(isturf(self.loc)) //else, there's considered to be no light
		var/turf/T = self.loc
		light_amount = T.get_lumcount() * 5

	self.adjust_nutrition(light_amount)

	if(light_amount > 2) //if there's enough light, heal
		self.mend(TREAT_TISSUE_REPAIR, 1)
		self.mend(TREAT_BURN_CARE, 1)
		self.mend(TREAT_ANTITOXIN, 1)
		self.mend(TREAT_OXYGENATION, 1)


	if(!self.client)
		self.npc_behaviour(self)
