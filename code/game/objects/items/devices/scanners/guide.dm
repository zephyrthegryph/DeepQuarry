/obj/item/healthanalyzer/verb/toggle_guide()
	set name = "Toggle Guidance"
	set desc = "Toggles whether or not the health analyzer will provide guidance and instruction in addition to scanning."
	set category = "Object"
	guide = !guide
	to_chat(usr, span_notice("You toggle \the [src]'s guidance system [guide ? "on" : "off"]."))

/obj/item/healthanalyzer/guide
	name = "Instructional health analyzer"
	desc = "A hand-held body scanner able to distinguish vital signs of the subject. It shows extra information to medical personnel!"
	guide = TRUE
	icon_state = "health-g"

/// Beginner advice per treatment mechanism the patient's detected afflictions
/// respond to (the analyzer's own treatment_demand()).
/proc/analyzer_guidance_line(tag)
	var/static/list/advice = list(
		TREAT_HEMOSTATIC = "Bleeding - Apply bandages or administer Bicaridine. Internal bleeds need coagulants such as Myelamine or vein repair surgery.",
		TREAT_TISSUE_REPAIR = "Physical trauma - Bandage the wounded body part. Administer Bicaridine or Vermicetol depending on the severity.",
		TREAT_BURN_CARE = "Burns - Salve the wound in ointment. Administer Kelotane or Dermaline. Check for infections.",
		TREAT_BONE_REPAIR = "Bone fracture - Splint the area. Treat with bone repair surgery or Osteodaxon.",
		TREAT_ANTIMICROBIAL = "Infection - Administer Spaceacillin. If severe, use Corophizine and monitor until well.",
		TREAT_ANTITOXIN = "Toxins - Inject Dylovene or Carthatoline. Monitor the liver and kidneys.",
		TREAT_OXYGENATION = "Poor oxygenation - Administer Dexalin or Dexalin Plus. Check the airway, heart and lungs.",
		TREAT_NEURAL_REPAIR = "Brain injury - Administer Alkysine or Peridaxon, or commence brain repair surgery.",
		TREAT_ANTIRADIATION = "Radiation exposure - Administer Hyronalin or Arithrazine. Monitor for genetic damage.",
		TREAT_GENETIC_REPAIR = "Genetic damage - Use a cryogenic pod with Cryoxadone below 70 K, or give Rezadone.",
		TREAT_BLOOD_RESTORE = "Low blood volume - Transfuse blood via IV drip or give blood-restorative chemicals (copper for zorren and skrell, iron for the rest).",
		TREAT_HEPATORENAL = "Liver or kidney damage - Administer Peridaxon; perform a full body scan for targeted surgery.",
		TREAT_CARDIAC = "Heart damage - Administer Peridaxon; perform a full body scan for targeted surgery.",
		TREAT_RESPIRATORY = "Lung damage - Administer Peridaxon; perform a full body scan for targeted surgery.",
		TREAT_DEFIBRILLATION = "Shockable cardiac rhythm - Defibrillate.",
		TREAT_AIRWAY = "Airway compromised - Clear and secure the airway.",
	)
	return advice[tag]

/obj/item/healthanalyzer/proc/guide(mob/living/M, mob/living/user)
	var/list/demand = M.body?.treatment_demand(active_profile())
	var/list/lines = list()
	for(var/tag in demand)
		var/line = analyzer_guidance_line(tag)
		if(line)
			lines += line
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/datum/disease/D in H.GetViruses())
			if(D.visibility_flags & HIDDEN_SCANNER)
				continue
			lines += "Viral infection - Inform a Virologist or the Chief Medical Officer and administer antiviral chemicals such as Spaceacillin. Limit exposure to other personnel."
			break
		for(var/obj/item/organ/external/E as anything in H.organs)
			if(E.robotic >= ORGAN_ROBOT)
				lines += "Robotic body parts - Inform the Robotics department."
				break
	if(!length(lines))
		return
	user.show_message(span_notice(span_bold("GUIDANCE SYSTEM BEGIN")) + "<br>" + lines.Join("<br>") + "<br>" + span_notice("For more detailed information on the patient's condition, utilize a body scanner at the closest medical bay."), 1)
