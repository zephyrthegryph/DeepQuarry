/obj/item/entrepreneur/horoscope
	name = "horoscope book"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "horoscope"
	desc = "A book with a years worth of horoscope readings in it, each one perfectly tailored to the phase of the stars and planets for every sign."
	var/static/list/stars_list = list("Due to Mercuary being in retrograde, you are recieving a powerful energy.",
					"The sun, Sol, of the Sol system, the birthplace of humanity, is your sign right now.",
					"Jupiter is in antegrade, affecting your energy directly.",
					"La luna has swung into virgo, be prepared!",
					"The moon of Earth is lingering in your lazy, hazy twelfth house.",
					"The moon starts the day in your intrepid ninth house!",
					"Menhir hovers about your secluded third house.",
					"Due to how Caledonia is in prograde, you are benefitting from it's energy.",
					"Mercuary hovers in your second house, unfortunately.",
					"Mars lingers in Scorpio now, this has a direct effect on your energy.",
					"Menhir has swung into Leo!",
					"The sun, Virgo-Erigone, lines up just right with Sol today.",
					"Don't let the fact that Mars and Menhir are collaborating affect your day!",
					"The moon is swinging between Cancer and Aries for you today.",
					"Venus holds the key for you, resting right in your fourth house.",
					"The wolftaur home of Elea lingers in Capricorn today.",
					"The Salvoran star, Holloway, glows extra bright for you.",
					"Mohges is caught in retrograde, Unathi are feeling it everywhere.",
					"Qerr'balak is in the prograde of your first house.",
					"Tal hovers above your ninth house.",
					"Creatures from another plane watch you from afar.",
					"Abundance in All Things Serene is in antegrade right now, you aren't benefiting from it any longer.",
					"Paraiso is confiding with you today, you'll do well to bear it.",
					"Sars Mara is no longer in Pisces, this will change your energy from the past few days.",
					"The planet Salthan is bordering on Taurus now.",
					"Procyon glistens for you betwixt the other stars.",
					"Proxima Centauri is edging for you, take heed of it.",
					"Sirius is cusping beyond your tenth house, you're getting a dose of its energy.",
					"Sanctum and Infernum line up for you, chaos will no doubt ensue.",
					"Infernum swings into Cancer for you, expect something firey!",
					"Elysian stars turn their attention away from you now.",
					"The stars of Elysium have caught you in their sights.",
					"The burning planet of Zehtir in the virgo-erigone system twists against Gemini.",
					"The purple soul of Geret Baht hungers for you.")
	var/static/list/prediction_list = list("This leads you to listen to your own wants above those of others.",
					"Prepare for this to lead you towards dark temptations.",
					"Your soul is being filled with a glorious love for life.",
					"Expect this to boost your confidence for a short while!",
					"This is going to drain your energy and you will need to recover it somehow.",
					"The effect will be strongest in the morning, but will settle down by the evening.",
					"Don't let this get in the way of being your best self.",
					"Consumption is on the menu for today, don't try to deny it.",
					"An undeniable need for enhancement lingers within you.",
					"A sense of adventure may blossom, but you are in danger of over-committing!",
					"The sense of spontaneous spontaneity beats in your heart, don't let it go to waste!",
					"Love is your world, combine with those around you, don't push them away.",
					"Sullen moons make for a quiet day, but it is not as though you can't take advantage of the silence.",
					"Some people are likely to be hidden away, people close to you.",
					"Desire beats with in you, do not deny the call.",
					"Beware of gluttony, it surrounds you today.",
					"Power is unbalanced in your life, seize it for yourself lest others take it from you.",
					"Joy, so much joy, all for yourself and to share with those you love.",
					"You will make a new friend, it is someone you may not expect to encounter.",
					"The universe pleads for you to plunder its riches, take what you deserve.",
					"Punishment will be dished out today, and you are at the centre of it.",
					"Allow yourself to make a real connection with another person today, it can only have good outcomes.",
					"You may find yourself frustrated, but other people can take it from you.",
					"Don't let yourself be consumed, the stars are tempting it.",
					"Hope is on the horizon, chase it down and don't let it get away from you.",
					"You might find yourself feeling drained due to those alignments or other factors in your life.",
					"Pride will be the undoing of you today, but you can still harness it.",
					"Perhaps you are feeling cute? Or perhaps something cute has taken your eye?",
					"You will feel a growing warmth in your very core.",
					"Expect a feeling of intense fulfilment.",
					"There's a high likelyhood of you getting caught up in a sticky situation, one way or another.",
					"Liberty is strong today, but beware it is fleeting for some.")
	var/static/list/advice_list = list("You will have a lot of compassionate energy today. Use it on a needy friend.",
					"It's wisest if you just admit to any anxieties or insecurities you have up front.",
					"New beginnings are important, but don't lose your appreciation for old connections.",
					"Your creativity could use a nice workout -- the kitchen is the perfect place for it.",
					"Leaving too many questions unanswered will cause someone's imagination to spin in a weird direction.",
					"Where you are going with someone isn't clear, but it's clear you are going together.",
					"It's time to lavish yourself with the attention you deserve. Treat yourself right.",
					"Ride your emotions like a roller coaster with your hands held straight up!",
					"If you want to put one of your innovative ideas into action right now, you have to be open to the possibility of asking for help from someone in a higher position than you.",
					"In any and all confrontations you have today, be sure to take the high road.",
					"Indulge in nourishing meals that fuel your energy while allowing yourself a guilt-free treat every now and then.",
					"Explore new cuisines and flavors to stimulate your taste buds and keep your meals exciting this month.",
					"Whether dining alone or with loved ones, take a moment to appreciate the food on your plate and the hands that prepared it.",
					"Tune into your body's needs and cravings without judgment, allowing yourself the freedom to enjoy food in a way that feels nourishing and satisfying.",
					"Boldly pursue your goals and assert your authority in all endeavors today!",
					"Try releasing control over outcomes and trusting in the universe to guide you towards your highest good.",
					"Surrender to the natural rhythms of life and have faith that everything will unfold according to plan when the time is right.",
					"Nurture your relationships and cultivate deep bonds with those who bring warmth and affection into your life and body.",
					"Take the time to sit back and digest the things that have happened to you lately.",
					"It never hurts to really absorb what you have taken in.",
					"Focus on nurturing trust and intimacy in your relationships rather than letting insecurity devour you.",
					"Keep your communication clear and your words sweet, lest you find yourself eaten alive by misunderstandings.",
					"Remember to take time to savor life's simple pleasures along the way.",
					"Be wary of being consumed by your own ego. Remember to share the spotlight and let others take a bite of the limelight too.",
					"Listen to others reminisce about the past. You will gain some incredible insight.",
					"Recognise your ability to communicate with others, and how this draws others to you.",
					"Going out could be more trouble than it's worth. Protest with your vote or your wallet instead.",
					"Walk side by side with others, eventually you will become one.",
					"Take a break from your usual routine, focus on yourself and treat yourself a little.",
					"This is a good day to get out and make connections with people. Maybe treat them a bit too!")
	var/aries = ""
	var/taurus = ""
	var/gemini = ""
	var/cancer = ""
	var/leo = ""
	var/virgo = ""
	var/libra = ""
	var/scorpio = ""
	var/sagittarius = ""
	var/capricorn = ""
	var/aquarius = ""
	var/pisces = ""
	var/static/list/zodiacs = list("aries","taurus","gemini","cancer","leo","virgo","libra","scorpio","sagittarius","capricorn","aquarius","pisces")

/// One sign's reading: a star alignment, a prediction and a piece of advice.
/obj/item/entrepreneur/horoscope/proc/roll_reading(datum/roller/R)
	return "[R.choose(stars_list)] [R.choose(prediction_list)] [R.choose(advice_list)]"

CAPABILITIES(/obj/item/entrepreneur/horoscope)
	op("self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), asks(/datum/prompt/choice, fields = list("question" = "Which of todays zodiacs do you want to read?", "title" = "Zodiac", "choices" = nameof(zodiacs), "timeout" = 0), step = "zodiac"), then(PROC_REF(interaction_self)))
	rolls(nameof(aries), PROC_REF(roll_reading))
	rolls(nameof(taurus), PROC_REF(roll_reading))
	rolls(nameof(gemini), PROC_REF(roll_reading))
	rolls(nameof(cancer), PROC_REF(roll_reading))
	rolls(nameof(leo), PROC_REF(roll_reading))
	rolls(nameof(virgo), PROC_REF(roll_reading))
	rolls(nameof(libra), PROC_REF(roll_reading))
	rolls(nameof(scorpio), PROC_REF(roll_reading))
	rolls(nameof(sagittarius), PROC_REF(roll_reading))
	rolls(nameof(capricorn), PROC_REF(roll_reading))
	rolls(nameof(aquarius), PROC_REF(roll_reading))
	rolls(nameof(pisces), PROC_REF(roll_reading))

/// Old attack_self.
/obj/item/entrepreneur/horoscope/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/zodiac = A.step_value("zodiac")
	if(isnull(zodiac))
		return OP_OK
	if(zodiac)
		switch(zodiac)
			if("aries")
				to_chat(user, span_notice("Today's reading for Aries: [aries]"))
			if("taurus")
				to_chat(user, span_notice("Today's reading for Taurus: [taurus]"))
			if("gemini")
				to_chat(user, span_notice("Today's reading for Gemini: [gemini]"))
			if("cancer")
				to_chat(user, span_notice("Today's reading for Cancer: [cancer]"))
			if("leo")
				to_chat(user, span_notice("Today's reading for Leo: [leo]"))
			if("virgo")
				to_chat(user, span_notice("Today's reading for Virgo: [virgo]"))
			if("libra")
				to_chat(user, span_notice("Today's reading for Libra: [libra]"))
			if("scorpio")
				to_chat(user, span_notice("Today's reading for Scorpio: [scorpio]"))
			if("sagittarius")
				to_chat(user, span_notice("Today's reading for Sagittarius: [sagittarius]"))
			if("capricorn")
				to_chat(user, span_notice("Today's reading for Capricorn: [capricorn]"))
			if("aquarius")
				to_chat(user, span_notice("Today's reading for Aquarius: [aquarius]"))
			if("pisces")
				to_chat(user, span_notice("Today's reading for Pisces: [pisces]"))
	return OP_OK
