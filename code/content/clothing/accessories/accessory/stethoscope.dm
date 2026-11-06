/obj/item/clothing/accessory/stethoscope
	name = "stethoscope"
	desc = "An outdated medical apparatus for listening to the sounds of the human body. It also makes you look like you know what you're doing."
	icon_state = "stethoscope"
	slot = ACCESSORY_SLOT_TIE

/obj/item/clothing/accessory/stethoscope/use_on_patient(mob/living/carbon/human/M, mob/living/user, stance = I_HURT)
	if(stance != I_HELP) //in case it is ever used as a surgery tool
		return ..()
	attack(M, user, hud_of(user)?.zone_sel?.selecting || BP_TORSO, 1, stance) //default surgery behaviour is just to scan as usual
	return 1

/obj/item/clothing/accessory/stethoscope/attack(mob/living/carbon/human/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(ishuman(M) && isliving(user))
		if(stance == I_HELP)
			var/body_part = parse_zone(hud_of(user)?.zone_sel?.selecting)

			var/message_holder	//Holds pervy message
			var/message_holder2	//Hods the nutrition related message.
			var/beat_size = ""	//Small prey = quiet

			if(body_part)
				var/their = "their"
				switch(M.gender)
					if(MALE)	their = "his"
					if(FEMALE)	their = "her"

				var/sound = "heartbeat"
				var/sound_strength = "cannot hear"
				if(M.stat == DEAD || (M.status_flags & FAKEDEATH))
					sound_strength = "cannot hear"
					sound = "anything"
				else
					switch(body_part)
						//TORSO:
						//ORGANS INVENTORY: Heart, Lungs, Spleen, Voicebox,
						if(BP_TORSO)
							for(var/belly in M.vore_organs) // Pervy edit. //
								var/obj/belly/B = belly
								for(var/mob/living/carbon/human/H in B)
									if(H.size_multiplier < 0.5)
										beat_size = pick("quiet ", "hushed " ,"low " ,"hushed ")
									message_holder = pick("You can hear disparate heartbeats as well.", "You can hear a different [beat_size]heartbeat too.", "It sounds like there is more than one heartbeat." ,"You can pick up a [beat_size]heatbeat along with everything else.")
							if(nutrition_of(M) > 900)	//dead
								message_holder2 = pick("Your listening is troubled by the occasional deep groan of their body.", "There is some moderate bubbling in the background.", "They seem to have a healthy metabolism as well.")

							var/obj/item/organ/internal/heart/heart = M.organ_in(O_HEART)
							sound_strength = "hear"
							sound = "no heartbeat"
							if(heart)
								if(heart.is_bruised())
									sound = span_warning("muffled heart sounds, as if fluid is around the heart") //yes this shows over the heart beinng robotic.
								else if(heart.robotic) //They have JUST a heart but no heartbeat
									if(heart.robotic == ORGAN_ASSISTED) //LVAD
										sound = "a loud, continual, electronic hum"
									else if(heart.robotic == ORGAN_ROBOT || heart.robotic == ORGAN_LIFELIKE)
										sound = "a light, rhythmic, mechanical clicking"
									else
										sound = span_warning("no heartbeat")
									if(istype(heart, /obj/item/organ/internal/heart/machine/anomalock))
										var/obj/item/organ/internal/heart/machine/anomalock/zap_heart = heart
										if(zap_heart.core)
											user.electrocute_act(15, src)
											user.emote("scream")
								else
									switch(M.pulse)
										if(PULSE_NONE)
											sound = "no heartbeat"
										if(PULSE_SLOW)
											sound = "a slow heartbeat"
										if(PULSE_NORM)
											sound = "a normal, healthy heartbeat"
										if(PULSE_FAST)
											sound = "a rapid heartbeat"
										if(PULSE_2FAST)
											sound = span_info("a very rapid heartbeat")
										if(PULSE_THREADY)
											sound = span_warning("an extremely rapid, thready, irregular heartbeat")

							var/obj/item/organ/internal/lungs/L = M.organ_in(O_LUNGS)
							if(!L || M.losebreath())
								sound += span_warning(" and no respiration")
							else if(M.is_lung_ruptured() || M.oxygen_debt() > 50)
								sound += span_warning(" and [pick("wheezing","gurgling")] sounds")
							else
								sound += " and healthy respiration"
						//GROIN
						//ORGANS INVENTORY: Appendix, Intestines, Kidneys, Liver, Spleen, Stomach.
						//Of these, the Intestines, Stomach, Liver, and Kidneys make noise.
						if(BP_GROIN)
							var/obj/item/organ/internal/intestine/intestine = M.organ_in(O_INTESTINE)
							var/obj/item/organ/internal/stomach/stomach = M.organ_in(O_STOMACH)
							var/obj/item/organ/internal/kidneys/kidneys = M.organ_in(O_KIDNEYS)
							var/obj/item/organ/internal/liver/liver = M.organ_in(O_LIVER)
							sound_strength = "hear"
							sound = span_warning("no gastric sounds,")
							if(intestine)
								if(intestine.is_bruised())
									sound = span_warning("slowed intestinal sounds")
								else
									sound = "normal intestinal sounds,"

							if(stomach)
								if(stomach.is_bruised())
									sound += span_warning(" slowed digestive sounds,")
								else
									sound += " with normal digestive sounds,"
							else
								sound += span_warning(" no digestive sounds,")

							if(kidneys && kidneys.is_bruised())
								sound += span_warning(" renal bruits,") //I don't really know how to convey this without using medical terminology.
							else
								sound += " no renal sounds,"

							if(liver) //yeah, I didn't know your liver could make sounds either.
								if(liver.is_bruised())
									sound += span_warning(" and abnormal liver sounds.")
								else
									sound += " and normal liver sounds."
						else
							sound_strength = "cannot hear"
							sound = "anything"

				act_message(user, src, MSG_SELF("You place %T% against [their] [body_part]. You [sound_strength] [sound]. [message_holder] [message_holder2]"), \
					MSG_OTHERS("%U% places %T% against [M]'s [body_part] and listens attentively."))
				return ITEM_INTERACT_SUCCESS

	return ..(M, user, target_zone, attack_modifier, stance)
