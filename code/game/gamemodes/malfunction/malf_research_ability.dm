/datum/malf_research_ability
	var/ability = null 									// Path to verb which will be given to the AI when researched.
	var/name = "Unknown Ability"						// Name of this ability
	var/price = 0										// Amount of CPU time needed to unlock this ability.
	var/invested = 0 									// Amount of CPU time already used to research this ability. When larger or equal to price unlocks the ability.
	var/unlocked = 0									// Changed to 1 when fully researched.
	var/datum/malf_research_ability/next = null			// Next research (if applicable).

/// The next research of the chain: each ability owns it (its type says which one it starts with), and finishing this one moves it to the researcher.
CAPABILITIES(/datum/malf_research_ability)
	owns_one(nameof(next), /datum/malf_research_ability)


/datum/malf_research_ability/proc/research_tick(time = 0)
	invested += time
	if(invested >= price)
		set_unlocked(1)

