
/obj/item/healthanalyzer/proc/guidance_toggled(datum/act/op/A)
	set_guide(!guide)
	to_chat(A.actor, span_notice("You toggle \the [src]'s guidance system [guide ? "on" : "off"]."))
	return OP_OK

/obj/item/healthanalyzer/guide
	name = "Instructional health analyzer"
	desc = "A hand-held body scanner able to distinguish vital signs of the subject. It shows extra information to medical personnel!"
	guide = TRUE
	icon_state = "health-g"

/// Beginner advice per treatment mechanism the patient's detected afflictions
/// respond to (the analyzer's own treatment_demand()). Every TREAT_* tag has a line
/// that names a treatment a medic can get: the dispenser and chemistry lab, a medical
/// locker or kit (code/content/medical/stabilisation, instruments) or a surgery step.
/proc/analyzer_guidance_line(tag)
	return GLOB.analyzer_guidance[tag]

GLOBAL_LIST_INIT(analyzer_guidance, list( \
	TREAT_HEMOSTATIC = "Bleeding - Apply bandages or administer Bicaridine. Internal bleeds need coagulants such as Myelamine or vein repair surgery.", \
	TREAT_TISSUE_REPAIR = "Physical trauma - Bandage the wounded body part. Administer Bicaridine.", \
	TREAT_BURN_CARE = "Burns - Salve the wound in ointment. Administer Kelotane or Dermaline. Check for infections.", \
	TREAT_BURN_DEEP = "Deep burns - Administer Dermaline; Kelotane barely reaches them. Check for infections and keep the airway open.", \
	TREAT_BONE_REPAIR = "Bone fracture - Splint the area and set the bone with bone repair surgery. Osteodaxon on an unset fracture knits the bone crooked.", \
	TREAT_BONE_SETTING = "Unset bone - Perform Set Bone surgery with a bone setter or bone gel, then splint the limb.", \
	TREAT_ANTIMICROBIAL = "Infection - Administer Spaceacillin. If severe, use Corophizine and monitor until well.", \
	TREAT_ANTITOXIN = "Toxins - Inject Dylovene or Carthatoline. Monitor the liver and kidneys.", \
	TREAT_OXYGENATION = "Poor oxygenation - Administer Dexalin or Dexalin Plus. Check the airway, heart and lungs.", \
	TREAT_NEURAL_REPAIR = "Brain injury - Administer Alkysine or Peridaxon, or commence brain repair surgery.", \
	TREAT_SOULMEND = "Brain death - Only Soul Dew mends a dead brain. Inform the Chief Medical Officer.", \
	TREAT_ANTIRADIATION = "Radiation exposure - Administer Hyronalin or Arithrazine. Monitor for genetic damage.", \
	TREAT_GENETIC_REPAIR = "Genetic damage - Use a cryogenic pod with Cryoxadone below 70 K, or give Rezadone.", \
	TREAT_BLOOD_RESTORE = "Low blood volume - Transfuse blood via IV drip or give blood-restorative chemicals (copper for zorren and skrell, iron for the rest).", \
	TREAT_HEPATORENAL = "Liver or kidney damage - Administer Peridaxon; perform a full body scan for targeted surgery.", \
	TREAT_CARDIAC = "Heart damage - Administer Peridaxon; perform a full body scan for targeted surgery.", \
	TREAT_RESPIRATORY = "Lung damage - Administer Peridaxon; perform a full body scan for targeted surgery.", \
	TREAT_OCULAR = "Eye damage - Administer Imidazoline or Peridaxon. Shield the eyes from light until they recover.", \
	TREAT_DIGESTIVE = "Stomach or bowel damage - Administer Gastirodaxon. A swollen appendix needs the appendix removed.", \
	TREAT_THERMOREGULATION = "Abnormal body temperature - Administer Leporazine. Warm a cold patient with a blanket or a warm room, cool an overheated one, and treat any burns.", \
	TREAT_CIRCULATORY = "Weak circulation - Administer Inaprovaline or use a stabiliser autoinjector, lay the patient down and stop any bleeding.", \
	TREAT_VASOPRESSOR = "Collapsed pressure or swollen airway - Use a stabiliser autoinjector or Adrenaline. Adrenaline also helps restart a stopped heart during CPR.", \
	TREAT_STIMULANT = "Slowed or stopped breathing - Ventilate with a bag-valve mask and give a stimulant such as Adrenaline. Do not give stimulants to a bleeding patient.", \
	TREAT_ANALGESIC = "Pain - Administer Paracetamol, Tramadol or Oxycodone.", \
	TREAT_ANTIEMETIC = "Nausea - Administer Calcium Carbonate.", \
	TREAT_ANTICONVULSANT = "Seizure - Administer Anticonvulsant, move hard objects away and protect the head.", \
	TREAT_ANTIEDEMA = "Airway swelling - Administer Dermaline, keep the airway open and watch the patient's breathing.", \
	TREAT_WOUND_PACKING = "Open bleeding wound - Pack it with hemostatic gauze or press on a pressure bandage from a field stabilisation kit.", \
	TREAT_OCCLUSIVE_SEAL = "Open chest wound - Apply a chest seal from a field stabilisation kit, then check the lungs.", \
	TREAT_DECOMPRESSION = "Trapped air in the chest - Use a decompression needle on the chest, or perform Surgical Decompression. Seal any open chest wound.", \
	TREAT_AIRWAY = "Airway compromised - Clear and secure the airway with an airway kit, or perform the Heimlich manoeuvre.", \
	TREAT_CHEST_COMPRESSION = "Stopped heart - Start chest compressions (CPR) and keep them up until a defibrillator arrives.", \
	TREAT_DEFIBRILLATION = "Shockable cardiac rhythm - Defibrillate.", \
	TREAT_SURGICAL_REPAIR = "Torn organ - Perform Repair Organ surgery. Stabilise the patient with drugs first.", \
	TREAT_RESECTION = "Dead tissue - Perform Resect Necrotic Tissue or Debride Dead Tissue surgery.", \
	TREAT_VESSEL_REPAIR = "Torn vessel - Perform Repair Blood Vessels surgery with a FixOVein, and apply a tourniquet above the tear meanwhile.", \
	TREAT_TENDON_REPAIR = "Severed tendon - Perform Repair Tendon surgery.", \
	TREAT_FOREIGN_BODY_REMOVAL = "Embedded object - Perform Extract Foreign Body surgery; do not pull it out in the field.", \
	TREAT_LITHOTRIPSY = "Deposits in the tissue - Perform Ultrasound Lithotripsy surgery.", \
	TREAT_SURGICAL_CLOSURE = "Open incision - Close it with a cautery.", \
	TREAT_REGENERATION = "Natural recovery - Keep the patient fed, hydrated and resting, and let them sleep.", \
	TREAT_RESTORATION = "Needs a full restorative, which the medbay does not stock. Inform the Chief Medical Officer.", \
	TREAT_PLATING_REPAIR = "Damaged plating - Weld the plating or apply nanopaste, or inform the Robotics department.", \
	TREAT_WIRING_REPAIR = "Damaged wiring - Replace it with cable coil or apply nanopaste, or inform the Robotics department.", \
	TREAT_SYSTEM_RESTORE = "System fault - Run a multitool pass over the head or use a recharging station. Inform the Robotics department if it persists.", \
	TREAT_COOLANT = "Overheating chassis - Supply coolant and let the unit rest.", \
	TREAT_CALIBRATION = "Misaligned actuators - Recalibrate them with a multitool, or perform Recalibrate Actuators surgery.", \
	TREAT_PANEL_CLOSURE = "Open maintenance panel - Close the hatch with a screwdriver.", \
	TREAT_FEEDSTOCK = "Nanoform starved of material - Feed it steel to rebuild.", \
))

/obj/item/healthanalyzer/proc/guide(mob/living/M, mob/living/user)
	var/list/demand = M.body?.treatment_demand(active_profile())
	var/list/lines = list()
	for(var/tag in demand)
		var/line = analyzer_guidance_line(tag)
		if(line)
			lines += line
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		for(var/datum/affliction/contagion/D in H.get_contagions())
			if((D.visibility_flags & HIDDEN_SCANNER) || !global_flag_check(D.virus_modifiers, DISCOVERED))
				continue
			lines += "Viral infection - Inform a Virologist or the Chief Medical Officer and administer antiviral chemicals such as Spaceacillin. Limit exposure to other personnel."
			break
		for(var/obj/item/organ/external/E as anything in H.organs)
			if(E.is_robotic())
				lines += "Robotic body parts - Inform the Robotics department."
				break
	if(!length(lines))
		return
	user.show_message(span_notice(span_bold("GUIDANCE SYSTEM BEGIN")) + "<br>" + lines.Join("<br>") + "<br>" + span_notice("For more detailed information on the patient's condition, utilize a body scanner at the closest medical bay."), 1)
