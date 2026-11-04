/datum/trait/neutral/venom_bite
	name = "Venomous Injection"
	desc = "Allows for injecting prey through one method or another to inject them with a variety of chemicals with varying effects!"
	tutorial = "This trait allows you to bite prey with varying effects! <br> \
		Options for venoms: <br> \
		=====Size Chemicals ===== <br> \
		Microcillin: Will make someone shrink. (This is 1% per 0.01 units. So 1 unit = 100% size change) <br> \
		Macrocillin: Will make someone grow. (This is 1% per 0.01 units. So 1 unit = 100% size change) <br> \
		Normalcillin: Will make someone normal size. (This is 1% per 0.01 units. So 1 unit = 100% size change) Stops at 100% size. <br> \
		===== Gender Chemicals ===== <br> \
		Androrovir: Will transform someone's sex to male. <br> \
		Gynorovir: Will transform someone's sex to female. <br> \
		Androgynorovir: Will transform someone's sex to pleural. <br> \
		===== Special Chemicals ===== <br> \
		Stoxin: Will make someone drowsy. <br> \
		Rainbow Toxin: Will make someone see rainbows. <br> \
		Paralysis Toxin: Will make someone paralyzed. <br> \
		Numbing Enzyme: Will make someone unable to feel pain. <br> \
		Pain Enzyme: Will make someone feel pain, amplifieed <br> \
		Aphrodisiac: Will make someone feel in the mood.<br> \
		===== Side Notes ===== <br> \
		You aren't required to inject anything if you prefer to just use it as a normal bite!"
	cost = 0
	custom_only = FALSE

/datum/trait/neutral/venom_bite/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/proc/injection), src)
	H.add_injection_reagent(REAGENT_ID_MICROCILLIN)		// get small
	H.add_injection_reagent(REAGENT_ID_MACROCILLIN)		// get BIG
	H.add_injection_reagent(REAGENT_ID_NORMALCILLIN)	// normal
	H.add_injection_reagent(REAGENT_ID_NUMBENZYME)		// no feelings
	H.add_injection_reagent(REAGENT_ID_ANDROROVIR) 		// -> MALE
	H.add_injection_reagent(REAGENT_ID_GYNOROVIR) 		// -> FEMALE
	H.add_injection_reagent(REAGENT_ID_ANDROGYNOROVIR) 	// -> PLURAL
	H.add_injection_reagent(REAGENT_ID_STOXIN)			// night night chem
	H.add_injection_reagent(REAGENT_ID_RAINBOWTOXIN) 	// Funny flashing lights.
	H.add_injection_reagent(REAGENT_ID_PARALYSISTOXIN) 	// Paralysis!
	H.add_injection_reagent(REAGENT_ID_PAINENZYME)		// Pain INCREASER
	H.add_injection_reagent(REAGENT_ID_APHRODISIAC) // Horni
