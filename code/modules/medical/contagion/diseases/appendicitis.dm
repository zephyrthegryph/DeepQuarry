/datum/affliction/contagion/appendicitis
	category = "Abdominal"
	subcategory = "Infection"
	immunogenicity = 0
	presentation = PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB
	symptom_pool = list(
		/datum/affliction_symptom/abdominal_tenderness = 95,
		/datum/affliction_symptom/nausea = 60,
		/datum/affliction_symptom/fever_sensation = 40
	)
	max_symptoms = 3
	factors = alist(BF_TEMPERATURE = 1.5, BF_HEART_RATE = 15)
	form = "Condition"
	name = "Appendicitis"
	medical_name = "Appendicitis"
	max_stages = 3
	spread_text = "Non-contagious"
	disease_flags = CAN_CARRY|CAN_RESIST|CAN_NOT_POPULATE
	spread_flags = DISEASE_SPREAD_NON_CONTAGIOUS
	virus_modifiers = NEEDS_ALL_CURES | BYPASSES_IMMUNITY
	cure_text = "Surgery"
	agent = "Shitty Appendix"
	desc = "If left untreated the subject will become very weak, and may vomit often."
	danger = DISEASE_MINOR
	visibility_flags = HIDDEN_PANDEMIC
	required_organs = list(/obj/item/organ/internal/appendix)

/datum/affliction/contagion/appendicitis/stage_act()
	..()
	switch(stage)
		if(1)
			if(prob(5))
				host.injure(INJURY_TOXIN, 1, affliction = /datum/affliction/appendiceal_sepsis, flags = INJURE_SILENT)
		if(2)
			var/obj/item/organ/internal/appendix/A = host.organ_in(O_APPENDIX)
			if(A)
				A.inflamed = TRUE
			if(prob(3))
				to_chat(host, span_warning("You feel a stabbing pain in your abdomen!"))
				host.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
				host.status_at_least(STAT_STUNNED, rand(4, 6))
				host.injure(INJURY_TOXIN, 1, affliction = /datum/affliction/appendiceal_sepsis, flags = INJURE_SILENT)
		if(3)
			if(prob(1))
				to_chat(host, span_danger("Your abdomen is a world of pain!"))
				host.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
				host.status_at_least(STAT_WEAKENED, 10)
			if(prob(1))
				host.vomit(95)
			if(prob(5))
				to_chat(host, span_warning("You feel a stabbing pain in your abdomen!"))
				host.automatic_custom_emote(VISIBLE_MESSAGE, "winces painfully.", check_stat = TRUE)
				host.status_at_least(STAT_STUNNED, rand(4, 6))
				host.injure(INJURY_TOXIN, 2, affliction = /datum/affliction/appendiceal_sepsis, flags = INJURE_SILENT)
