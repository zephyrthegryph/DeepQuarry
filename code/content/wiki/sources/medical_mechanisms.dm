// What each treatment mechanism (TREAT_* in code/defines/content/body.dm, named in code/domains/body/treatment.dm) does, in the wiki's words.
// A condition names the mechanisms that help it and the providers (drugs, tools, surgery) name the mechanisms they give, so each mechanism has
// one article (med/mech/<tag>) that links both sides; this table is its explanation. The wiki test asks for a line for every named mechanism.

GLOBAL_LIST_INIT(wiki_treatment_about, list( \
	TREAT_HEMOSTATIC       = "Stops bleeding: clotting and vessel constriction slow blood loss from wounds and internal bleeds.", \
	TREAT_TISSUE_REPAIR    = "Repairs soft tissue: bruises, cuts and torn muscle knit back together.", \
	TREAT_BONE_REPAIR      = "Knits broken bone. On a fracture that has not been set the bone knits crooked, so set it first.", \
	TREAT_BURN_CARE        = "Repairs burned skin and the tissue just under it.", \
	TREAT_ANTIMICROBIAL    = "Kills bacteria and fungi: treats wound infections, sepsis and other infections.", \
	TREAT_ANTITOXIN        = "Binds and clears toxins from the blood before they reach the liver and kidneys.", \
	TREAT_OXYGENATION      = "Raises the oxygen the blood carries to the tissues, whatever the lungs are managing.", \
	TREAT_NEURAL_REPAIR    = "Repairs brain and nerve tissue. It cannot repair a brain that has died.", \
	TREAT_CARDIAC          = "Repairs heart muscle.", \
	TREAT_RESPIRATORY      = "Repairs lung tissue.", \
	TREAT_HEPATORENAL      = "Repairs the liver and kidneys.", \
	TREAT_OCULAR           = "Repairs the eyes. It does not clear a clouded lens (cataracts need surgery).", \
	TREAT_ANTIRADIATION    = "Purges radiation from the body and limits the damage it does while it is purged.", \
	TREAT_GENETIC_REPAIR   = "Repairs damaged cells and DNA (genetic damage from radiation, cloning or mutagens).", \
	TREAT_THERMOREGULATION = "Brings the core temperature back toward normal, from too hot or too cold.", \
	TREAT_BLOOD_RESTORE    = "Rebuilds lost blood volume: transfusions and the minerals the body makes blood from.", \
	TREAT_CIRCULATORY      = "Supports the circulation: steadies the pulse and holds up the blood pressure.", \
	TREAT_ANALGESIC        = "Relieves pain. Pain relief also stops a patient flinching during surgery.", \
	TREAT_STIMULANT        = "Raises the heart rate and breathing drive. It makes bleeding worse.", \
	TREAT_PLATING_REPAIR   = "Repairs a synthetic's structural plating (welder, nanopaste).", \
	TREAT_WIRING_REPAIR    = "Repairs a synthetic's wiring and burned circuits (cable coil, nanopaste).", \
	TREAT_SYSTEM_RESTORE   = "Clears a synthetic's processor and system faults.", \
	TREAT_COOLANT          = "Replenishes a synthetic's coolant.", \
	TREAT_CALIBRATION      = "Recalibrates a synthetic's actuators and sensors (multitool).", \
	TREAT_SURGICAL_REPAIR  = "Sews torn or perforated organ tissue shut during surgery.", \
	TREAT_RESECTION        = "Cuts away dead (necrotic) tissue and growths during surgery.", \
	TREAT_AIRWAY           = "Clears and secures a blocked airway (an airway kit, the Heimlich manoeuvre).", \
	TREAT_DECOMPRESSION    = "Lets trapped air out of the chest so the lung can expand again (decompression needle, surgical decompression).", \
	TREAT_DEFIBRILLATION   = "Shocks a heart in a shockable rhythm back into a normal one (defibrillator).", \
	TREAT_CHEST_COMPRESSION = "Chest compressions (CPR): keep some blood moving while the heart is stopped.", \
	TREAT_VASOPRESSOR      = "Adrenaline-type drugs: raise a collapsed blood pressure, shrink airway swelling and help restart a stopped heart.", \
	TREAT_DIGESTIVE        = "Repairs the stomach, the bowel and the appendix.", \
	TREAT_ANTIEMETIC       = "Settles nausea and stops vomiting.", \
	TREAT_HYDRATION        = "Rehydrates: water, salts and sugar by mouth or drip. Also feeds the body's fight against a cold.", \
	TREAT_ANTICONVULSANT   = "Stops a seizure and makes the next less likely.", \
	TREAT_OPIOID_ANTAGONIST = "Knocks opioids off their receptors: reverses an opioid overdose.", \
	TREAT_WOUND_PACKING    = "Packs or presses a bleeding wound shut (hemostatic gauze, pressure bandage).", \
	TREAT_OCCLUSIVE_SEAL   = "Seals an open chest wound airtight (chest seal).", \
	TREAT_REGENERATION     = "The body's own healing: works best on a fed, watered, resting and sleeping patient.", \
	TREAT_RESTORATION      = "Full restoration (powers, magic, admin intervention): repairs every condition that can be repaired.", \
	TREAT_FEEDSTOCK        = "Feeds a nanoform's refactory with steel so it can rebuild itself.", \
	TREAT_SURGICAL_CLOSURE = "Closes an organic incision at the end of surgery (cautery, sutures).", \
	TREAT_PANEL_CLOSURE    = "Closes and secures a synthetic's maintenance panel (screwdriver).", \
	TREAT_BONE_SETTING     = "Sets a broken bone and closes a sawn bone layer (bone gel, bone setter).", \
	TREAT_VESSEL_REPAIR    = "Repairs a torn blood vessel or a cut artery during surgery (FixOVein).", \
	TREAT_TENDON_REPAIR    = "Rejoins a severed tendon during surgery.", \
	TREAT_FOREIGN_BODY_REMOVAL = "Takes out shrapnel, bullets and other embedded objects during surgery.", \
	TREAT_LITHOTRIPSY      = "Breaks up deposits in the tissue with focused ultrasound during surgery.", \
	TREAT_BURN_DEEP        = "Treats deep burns (charred and carbonised tissue) and burns of the airway, which ordinary burn care barely reaches.", \
	TREAT_ANTIEDEMA        = "Shrinks swelling in the airway, such as after breathing in fire.", \
	TREAT_SOULMEND         = "The only repair for a brain that has died. Every other neural repair stops at brain death.", \
))

/proc/wiki_treatment_about(tag)
	return GLOB.wiki_treatment_about[tag]
