// Nitrous oxide as the surgical anaesthetic. Breathing the sleeping gas (breathe_sleeping_gas() in code/domains/body/breath_profile.dm) holds this
// effect for as long as the gas is in the breath and a few seconds beyond it. Its factors are the same stats a drug would give: analgesia takes the
// pain off a surgical step and off the patient's own pain (patient_mult() in code/content/surgery/surgery.dm reads both), sedation dulls the mind a little.
// There is no surgery special case: a patient on N2O counts as covered because their stats say so.

/datum/body_effect/n2o_anesthesia
	name = "nitrous oxide anaesthesia"
	desc = "The sleeping gas numbs you."
	hidden = TRUE
	stacks = MODIFIER_STACK_EXTEND
	factors = alist(STAT_ANALGESIA = 80, STAT_SEDATION = 10)
