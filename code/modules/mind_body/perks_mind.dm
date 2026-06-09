// Mind perks. ~22 per department category, distributed across that
// department's sub-role trees. All Mind perks share their department's pool, so
// taking perks across multiple sub-roles is the intended specialisation pattern.
// Most effects are descriptive roadmaps for content to read off mob flags.

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND  (Captain + Head of Personnel, ~11 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Captain ────────────────────────────────────────────────────────────────────

/datum/perk/mind/cmd_capt_composure
	name = "Composure"
	desc = "Hard-won emotional control. Your Command radio messages cut through interruptions."
	icon_name = "comment-dots"
	cost = 1
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_authority
	name = "Authority"
	desc = "When you give an order over comms, the responding crewmember moves 10% faster for 30s."
	icon_name = "bullhorn"
	cost = 2
	tree = PERK_TREE_MIND_CMD_CAPTAIN
	requires = list(/datum/perk/mind/cmd_capt_composure)

/datum/perk/mind/cmd_capt_strategy
	name = "Strategy"
	desc = "Tactical map summary — power, atmos, antag status — surfaced in one Command HUD."
	icon_name = "chess-king"
	cost = 3
	tree = PERK_TREE_MIND_CMD_CAPTAIN
	requires = list(/datum/perk/mind/cmd_capt_authority)

/datum/perk/mind/cmd_capt_spotlight
	name = "Spotlight"
	desc = "Hostile NPCs in your line of sight are intimidated — they hesitate to engage you first."
	icon_name = "lightbulb"
	cost = 2
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_tactical
	name = "Tactical Vision"
	desc = "Visible threats are highlighted on your HUD with a small intent icon."
	icon_name = "binoculars"
	cost = 2
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_charge
	name = "Lead the Charge"
	desc = "Nearby crew briefly gain +5% movement speed when you run toward a threat."
	icon_name = "flag"
	cost = 2
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_voice
	name = "Command Voice"
	desc = "Your Command-channel radio range is extended by one z-level."
	icon_name = "tower-broadcast"
	cost = 1
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_resolve
	name = "Iron Resolve"
	desc = "Charisma stays steady in firefights. Allies you face do not panic."
	icon_name = "heart-circle-check"
	cost = 1
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_unyielding
	name = "Unyielding"
	desc = "You never break and run. Mass-fear effects are suppressed for you."
	icon_name = "person-rays"
	cost = 1
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_decorated
	name = "Decorated"
	desc = "A history of service. Sec / Cargo / Medical NPCs treat you as a respected superior."
	icon_name = "medal"
	cost = 2
	tree = PERK_TREE_MIND_CMD_CAPTAIN

/datum/perk/mind/cmd_capt_final
	name = "Final Authority"
	desc = "Override Captain-restricted doors and consoles without an ID swipe."
	icon_name = "key"
	cost = 3
	tree = PERK_TREE_MIND_CMD_CAPTAIN
	requires = list(/datum/perk/mind/cmd_capt_decorated)

// ── Head of Personnel ──────────────────────────────────────────────────────────

/datum/perk/mind/cmd_hop_paperwork
	name = "Paperwork"
	desc = "ID console operations — access edits, transfers, prints — complete 50% faster."
	icon_name = "file-lines"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_diplomacy
	name = "Diplomacy"
	desc = "Crewmembers you speak to gain a small mood boost for 60s."
	icon_name = "handshake"
	cost = 2
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_dept_master
	name = "Department Master"
	desc = "Grant Cargo / Civilian access on any ID computer without a head-of-department override."
	icon_name = "id-badge"
	cost = 3
	tree = PERK_TREE_MIND_CMD_HOP
	requires = list(/datum/perk/mind/cmd_hop_paperwork)

/datum/perk/mind/cmd_hop_bureaucrat
	name = "Bureaucrat"
	desc = "Approval-pending requests across the station bypass the standard delay when you sign off."
	icon_name = "stamp"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_people
	name = "People Person"
	desc = "Crew you've onboarded carry a small +mood pickup for 5 minutes after their first spawn."
	icon_name = "people-group"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_connections
	name = "Connections"
	desc = "Examining a crewmember reveals their declared department and the last time they were on shift."
	icon_name = "users"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_negotiator
	name = "Negotiator"
	desc = "Cargo supply order prices via your console are 5% cheaper."
	icon_name = "scale-balanced"
	cost = 2
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_recruiter
	name = "Recruiter"
	desc = "Open positions filled at your terminal grant the new hire a small starting credit bonus."
	icon_name = "user-plus"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_welcoming
	name = "Welcoming"
	desc = "Visitor / transient roles gain extra access in your presence."
	icon_name = "door-open"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_cataloguer
	name = "Cataloguer"
	desc = "ID-printer queue holds two extra pending requests without dropping any."
	icon_name = "book"
	cost = 1
	tree = PERK_TREE_MIND_CMD_HOP

/datum/perk/mind/cmd_hop_open_doors
	name = "Open Doors"
	desc = "Personnel doors you approach pre-open even without a valid ID — saves time for emergencies."
	icon_name = "door-closed"
	cost = 2
	tree = PERK_TREE_MIND_CMD_HOP
	requires = list(/datum/perk/mind/cmd_hop_bureaucrat)

// ═══════════════════════════════════════════════════════════════════════════════
// SECURITY  (Officer + Detective + Warden, ~7-8 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Officer ────────────────────────────────────────────────────────────────────

/datum/perk/mind/sec_off_threat
	name = "Threat Assessment"
	desc = "Visible sidearms are surfaced when you examine a person."
	icon_name = "eye"
	cost = 1
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_off_restraint
	name = "Restraint Training"
	desc = "Cuff application is 25% faster and your grab pulls are harder to break."
	icon_name = "handcuffs"
	cost = 2
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_off_reflexes
	name = "Combat Reflexes"
	desc = "The first stun in a fight no longer staggers you."
	icon_name = "bolt-lightning"
	cost = 3
	tree = PERK_TREE_MIND_SEC_OFFICER
	requires = list(/datum/perk/mind/sec_off_threat)

/datum/perk/mind/sec_off_tactical_stance
	name = "Tactical Stance"
	desc = "Aiming a ranged weapon grants 10% accuracy and a small slowdown trade."
	icon_name = "crosshairs"
	cost = 1
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_off_take_aim
	name = "Take Aim"
	desc = "Held weapons gain +20% accuracy against the marked target."
	icon_name = "bullseye"
	cost = 2
	tree = PERK_TREE_MIND_SEC_OFFICER
	requires = list(/datum/perk/mind/sec_off_tactical_stance)

/datum/perk/mind/sec_off_hardened
	name = "Hardened"
	desc = "PTSD / panic effects from combat are halved in duration."
	icon_name = "shield-blank"
	cost = 1
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_off_pursuit
	name = "Pursuit"
	desc = "Your sprint endurance is doubled while chasing a fleeing suspect."
	icon_name = "person-running"
	cost = 2
	tree = PERK_TREE_MIND_SEC_OFFICER

/datum/perk/mind/sec_off_takedown
	name = "Takedown"
	desc = "Tackle attempts succeed 25% more often and the target lands prone."
	icon_name = "person-falling"
	cost = 2
	tree = PERK_TREE_MIND_SEC_OFFICER

// ── Detective ──────────────────────────────────────────────────────────────────

/datum/perk/mind/sec_det_forensic
	name = "Forensic Eye"
	desc = "Examining a crime scene surfaces nearby fingerprints / DNA."
	icon_name = "magnifying-glass"
	cost = 1
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_interrogate
	name = "Interrogator"
	desc = "Cuffed suspects you examine reveal their last 5 minutes of suit-sensor history."
	icon_name = "user-secret"
	cost = 2
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_intuition
	name = "Intuition"
	desc = "Antag radio chatter you overhear is highlighted in your chat log."
	icon_name = "lightbulb"
	cost = 3
	tree = PERK_TREE_MIND_SEC_DETECTIVE
	requires = list(/datum/perk/mind/sec_det_interrogate)

/datum/perk/mind/sec_det_eagle
	name = "Eagle Eye"
	desc = "You can examine targets at 50% greater range."
	icon_name = "eye"
	cost = 1
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_trail
	name = "Trail"
	desc = "Bloody footprints and other trail evidence remain visible to you 50% longer."
	icon_name = "shoe-prints"
	cost = 1
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_profiler
	name = "Profiler"
	desc = "Antag-identifying examination ('they look suspicious') gives reliable text instead of probabilistic."
	icon_name = "user-tag"
	cost = 2
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_cold_read
	name = "Cold Read"
	desc = "Interrogated subjects yield extra detail — known associates, recent locations."
	icon_name = "comment-medical"
	cost = 1
	tree = PERK_TREE_MIND_SEC_DETECTIVE

/datum/perk/mind/sec_det_sealed_case
	name = "Sealed Case"
	desc = "Capstone investigative. Evidence you collect cannot be tampered with or destroyed."
	icon_name = "box-archive"
	cost = 3
	tree = PERK_TREE_MIND_SEC_DETECTIVE
	requires = list(/datum/perk/mind/sec_det_profiler, /datum/perk/mind/sec_det_forensic)

// ── Warden ─────────────────────────────────────────────────────────────────────

/datum/perk/mind/sec_warden_quarter
	name = "Armoury Quartermaster"
	desc = "Armoury checkout console shows who pulled what."
	icon_name = "warehouse"
	cost = 1
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_lockdown
	name = "Lockdown"
	desc = "Cell-door overrides on prisoners you've processed don't trip the 30s cooldown."
	icon_name = "lock"
	cost = 2
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_keymaster
	name = "Keymaster"
	desc = "Your ID acts as a master key on Security brig doors."
	icon_name = "key"
	cost = 3
	tree = PERK_TREE_MIND_SEC_WARDEN
	requires = list(/datum/perk/mind/sec_warden_quarter)

/datum/perk/mind/sec_warden_riot_geared
	name = "Riot Geared"
	desc = "Riot gear's slowdown penalty is halved on you."
	icon_name = "shield-cat"
	cost = 1
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_stand_tall
	name = "Stand Tall"
	desc = "Prisoners' attempts to disarm or grab you fail noticeably more often."
	icon_name = "user-shield"
	cost = 1
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_roll_call
	name = "Roll Call"
	desc = "Security manifest console summarises which officers have what gear, in real time."
	icon_name = "clipboard-user"
	cost = 1
	tree = PERK_TREE_MIND_SEC_WARDEN

/datum/perk/mind/sec_warden_brig_eye
	name = "Brig Eye"
	desc = "All brig cameras are accessible from any cell terminal once you sign in."
	icon_name = "video"
	cost = 2
	tree = PERK_TREE_MIND_SEC_WARDEN

// ═══════════════════════════════════════════════════════════════════════════════
// ENGINEERING  (Atmos + Engine + Salvage, ~7-8 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Atmos Tech ─────────────────────────────────────────────────────────────────

/datum/perk/mind/eng_atmos_reader
	name = "Vent Reader"
	desc = "Atmos analyser readings include a one-line suggested fix."
	icon_name = "wind"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_balancer
	name = "Pressure Balancer"
	desc = "Setting vent/scrubber pressure on a control panel snaps to safe defaults."
	icon_name = "gauge"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_firefighter
	name = "Firefighter"
	desc = "Burn damage taken while fighting an active fire is reduced 30%."
	icon_name = "fire-extinguisher"
	cost = 3
	tree = PERK_TREE_MIND_ENG_ATMOS
	requires = list(/datum/perk/mind/eng_atmos_reader)

/datum/perk/mind/eng_atmos_gas_tinkerer
	name = "Gas Tinkerer"
	desc = "Holding the gas-mix tool reveals atmos composition in target tiles."
	icon_name = "vial-circle-check"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_cooling
	name = "Cooling Specialist"
	desc = "Freezers and chillers you set up cool 25% faster."
	icon_name = "snowflake"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_sealer
	name = "Sealer"
	desc = "Plasteel patches you apply to breached walls hold air immediately."
	icon_name = "block"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ATMOS

/datum/perk/mind/eng_atmos_oxygen_chief
	name = "Oxygen Chief"
	desc = "Oxygen-canister refill cycles complete in 50% less time at your station."
	icon_name = "circle-dot"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ATMOS
	requires = list(/datum/perk/mind/eng_atmos_balancer)

// ── Engine Tech ────────────────────────────────────────────────────────────────

/datum/perk/mind/eng_engine_wirework
	name = "Wirework"
	desc = "Wire-puzzle outcomes are revealed without trial-and-error."
	icon_name = "plug"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_tesla
	name = "Tesla Whisperer"
	desc = "Examine the engine to see its current containment + decay timers."
	icon_name = "bolt"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_overdrive
	name = "Overdrive"
	desc = "APCs you maintain charge 25% faster from external power."
	icon_name = "battery-full"
	cost = 3
	tree = PERK_TREE_MIND_ENG_ENGINE
	requires = list(/datum/perk/mind/eng_engine_wirework)

/datum/perk/mind/eng_engine_circuit_eye
	name = "Circuit Eye"
	desc = "Multitool readings on circuits show the trace path."
	icon_name = "microchip"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_power_route
	name = "Power Router"
	desc = "Reroute power across two APCs without breaking the load — perfect for hot patches."
	icon_name = "code-fork"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_supermatter
	name = "Supermatter Reverence"
	desc = "Standing near a stable engine grants you minor combat resilience."
	icon_name = "atom"
	cost = 2
	tree = PERK_TREE_MIND_ENG_ENGINE

/datum/perk/mind/eng_engine_singulo
	name = "Singularity Walker"
	desc = "EM radiation from the singulo containment damages you 50% less."
	icon_name = "compact-disc"
	cost = 1
	tree = PERK_TREE_MIND_ENG_ENGINE

// ── Salvage ────────────────────────────────────────────────────────────────────

/datum/perk/mind/eng_salv_scrapper
	name = "Scrapper"
	desc = "Deconstructing machinery returns 15% more parts on average."
	icon_name = "screwdriver"
	cost = 1
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salv_jury_rig
	name = "Jury Rig"
	desc = "Patch breached walls with metal sheets without welding fuel."
	icon_name = "hammer"
	cost = 2
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salv_pack_rat
	name = "Pack Rat"
	desc = "Your utility belt holds two extra small items."
	icon_name = "box-archive"
	cost = 1
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salv_field_repair
	name = "Field Repair"
	desc = "Welder repairs on machinery use 25% less fuel."
	icon_name = "wrench"
	cost = 1
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salv_ironcost
	name = "Iron Economy"
	desc = "Metal/sheet recipes return one extra unit on average when you craft them."
	icon_name = "cubes"
	cost = 2
	tree = PERK_TREE_MIND_ENG_SALVAGE

/datum/perk/mind/eng_salv_disassembly
	name = "Disassembly"
	desc = "Tear down complex machinery in one fewer step."
	icon_name = "screwdriver-wrench"
	cost = 2
	tree = PERK_TREE_MIND_ENG_SALVAGE
	requires = list(/datum/perk/mind/eng_salv_scrapper)

/datum/perk/mind/eng_salv_hoarder
	name = "Hoarder"
	desc = "Capstone salvage. Crates you open also yield a small bonus assortment of common parts."
	icon_name = "box-open"
	cost = 3
	tree = PERK_TREE_MIND_ENG_SALVAGE
	requires = list(/datum/perk/mind/eng_salv_disassembly)

// ═══════════════════════════════════════════════════════════════════════════════
// MEDICAL  (Doctor + Surgeon + Chemist, ~7-8 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Doctor ─────────────────────────────────────────────────────────────────────

/datum/perk/mind/med_doc_anatomy
	name = "Anatomy"
	desc = "Examining a patient surfaces visibly damaged organs and bleeds."
	icon_name = "bone"
	cost = 1
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_triage
	name = "Triage"
	desc = "Patients you're treating display a color-coded priority HUD."
	icon_name = "bell-concierge"
	cost = 2
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_cpr
	name = "CPR Mastery"
	desc = "CPR you perform restores 15% more oxygen damage per cycle."
	icon_name = "heart-circle-bolt"
	cost = 3
	tree = PERK_TREE_MIND_MED_DOCTOR
	requires = list(/datum/perk/mind/med_doc_triage)

/datum/perk/mind/med_doc_diagnostician
	name = "Diagnostician"
	desc = "Body scanners give you a free 'differential' line summarising likely causes."
	icon_name = "stethoscope"
	cost = 1
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_first_aid
	name = "First Aid"
	desc = "Field bandages and basic injectors heal 20% more per application."
	icon_name = "kit-medical"
	cost = 1
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_rapid_response
	name = "Rapid Response"
	desc = "When a crewmember enters crit, you receive a one-time location ping."
	icon_name = "tower-broadcast"
	cost = 2
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_lifesaver
	name = "Lifesaver"
	desc = "Defibrillator success window extended by 15s after death."
	icon_name = "heart-pulse"
	cost = 2
	tree = PERK_TREE_MIND_MED_DOCTOR

/datum/perk/mind/med_doc_caregiver
	name = "Caregiver"
	desc = "Patients you've treated regenerate 10% faster for the next 5 minutes."
	icon_name = "hands-holding-circle"
	cost = 1
	tree = PERK_TREE_MIND_MED_DOCTOR

// ── Surgeon ────────────────────────────────────────────────────────────────────

/datum/perk/mind/med_surg_focus
	name = "Surgical Focus"
	desc = "Surgery steps complete 15% faster."
	icon_name = "scissors"
	cost = 1
	tree = PERK_TREE_MIND_MED_SURGEON

/datum/perk/mind/med_surg_clean
	name = "Sterile Field"
	desc = "Surgeries you perform are 25% less likely to introduce infection."
	icon_name = "soap"
	cost = 2
	tree = PERK_TREE_MIND_MED_SURGEON

/datum/perk/mind/med_surg_organ
	name = "Organ Transplant"
	desc = "Transplants take 30% less time and the recipient suffers no shock damage."
	icon_name = "heart-pulse"
	cost = 3
	tree = PERK_TREE_MIND_MED_SURGEON
	requires = list(/datum/perk/mind/med_surg_focus)

/datum/perk/mind/med_surg_steady_hands
	name = "Steady Hands"
	desc = "Surgery steps that require precision are 30% less likely to fail under stress."
	icon_name = "hand-holding-medical"
	cost = 1
	tree = PERK_TREE_MIND_MED_SURGEON

/datum/perk/mind/med_surg_cybernetic
	name = "Cybernetic Implant"
	desc = "Installing cybernetic limbs / organs takes one fewer step."
	icon_name = "microchip"
	cost = 2
	tree = PERK_TREE_MIND_MED_SURGEON
	requires = list(/datum/perk/mind/med_surg_focus)

/datum/perk/mind/med_surg_emergency
	name = "Emergency Surgery"
	desc = "You can perform critical surgery without a fully sterile setup at a small penalty."
	icon_name = "hospital"
	cost = 2
	tree = PERK_TREE_MIND_MED_SURGEON

/datum/perk/mind/med_surg_resus
	name = "Resuscitation"
	desc = "Reviving from crit-death is faster and less likely to leave organ damage."
	icon_name = "heart-circle-plus"
	cost = 2
	tree = PERK_TREE_MIND_MED_SURGEON

// ── Chemist ────────────────────────────────────────────────────────────────────

/datum/perk/mind/med_chem_pharma
	name = "Pharmacology"
	desc = "Reagent overdose thresholds for you are 25% higher."
	icon_name = "pills"
	cost = 1
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_synth
	name = "Synth Master"
	desc = "Chemistry reactions you start auto-bring to the correct temperature."
	icon_name = "vial"
	cost = 2
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_grenadier
	name = "Grenadier"
	desc = "Chemical-grenade assembly takes one fewer step."
	icon_name = "explosion"
	cost = 3
	tree = PERK_TREE_MIND_MED_CHEMIST
	requires = list(/datum/perk/mind/med_chem_synth)

/datum/perk/mind/med_chem_field_chemist
	name = "Field Chemist"
	desc = "You can identify any reagent in a container by examining it."
	icon_name = "flask"
	cost = 1
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_yield
	name = "Yield Optimization"
	desc = "Chemistry reactions you start yield 10% more product."
	icon_name = "chart-line"
	cost = 2
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_antidote
	name = "Antidote Specialist"
	desc = "Toxins, poisons, and neurotoxins in your bloodstream metabolise 50% faster."
	icon_name = "vials"
	cost = 2
	tree = PERK_TREE_MIND_MED_CHEMIST

/datum/perk/mind/med_chem_field_synth
	name = "Field Synthesis"
	desc = "Make 5u of any basic reagent on the fly via your dispenser hookup."
	icon_name = "wand-magic-sparkles"
	cost = 1
	tree = PERK_TREE_MIND_MED_CHEMIST

// ═══════════════════════════════════════════════════════════════════════════════
// RESEARCH  (Scientist + Roboticist + Xeno-Archaeology, ~7-8 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Scientist ──────────────────────────────────────────────────────────────────

/datum/perk/mind/res_sci_method
	name = "Methodology"
	desc = "Research scanner results include a one-line prior interpretation."
	icon_name = "atom"
	cost = 1
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_anomaly
	name = "Anomaly Intuition"
	desc = "Anomaly classification scans are 20% faster."
	icon_name = "wand-magic-sparkles"
	cost = 2
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_overclock
	name = "Overclock"
	desc = "Research console cooldowns reduced 25%."
	icon_name = "gauge-high"
	cost = 3
	tree = PERK_TREE_MIND_RES_SCIENTIST
	requires = list(/datum/perk/mind/res_sci_method)

/datum/perk/mind/res_sci_observer
	name = "Observer"
	desc = "Examining alien fauna reveals their faction / aggression / preferred diet."
	icon_name = "eye"
	cost = 1
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_data
	name = "Data Compiler"
	desc = "Research-point gains from scanning artifacts are 15% larger."
	icon_name = "chart-bar"
	cost = 2
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_protocol
	name = "Strict Protocol"
	desc = "Hazardous specimens you handle do not damage their container."
	icon_name = "clipboard-check"
	cost = 1
	tree = PERK_TREE_MIND_RES_SCIENTIST

/datum/perk/mind/res_sci_polymath
	name = "Polymath"
	desc = "Access to any research console's published research no matter the department."
	icon_name = "graduation-cap"
	cost = 2
	tree = PERK_TREE_MIND_RES_SCIENTIST

// ── Roboticist ─────────────────────────────────────────────────────────────────

/datum/perk/mind/res_robo_assembly
	name = "Assembly"
	desc = "Mech / cyborg assembly steps take 25% less time."
	icon_name = "robot"
	cost = 1
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_calibration
	name = "Calibration"
	desc = "Cyborgs you assemble start with +50 cell charge."
	icon_name = "screwdriver-wrench"
	cost = 2
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_diag
	name = "Diagnostic Subsystem"
	desc = "Diagnostic scans on machinery reveal hidden wire-fault state."
	icon_name = "microchip"
	cost = 3
	tree = PERK_TREE_MIND_RES_ROBOTICIST
	requires = list(/datum/perk/mind/res_robo_assembly)

/datum/perk/mind/res_robo_repair
	name = "Robotic Repair"
	desc = "Welder repairs on borgs / mechs heal 25% more per attempt."
	icon_name = "wrench"
	cost = 1
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_module
	name = "Module Configuration"
	desc = "Borg module swaps complete in 50% less time."
	icon_name = "code-pull-request"
	cost = 2
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_mech_eng
	name = "Mech Engineering"
	desc = "Mechs you maintain have a 10% higher armor cap."
	icon_name = "shield-cat"
	cost = 2
	tree = PERK_TREE_MIND_RES_ROBOTICIST

/datum/perk/mind/res_robo_protocol_master
	name = "Protocol Master"
	desc = "All borgs you build come with the Slaved-To-You safety protocol enabled."
	icon_name = "shield-cat"
	cost = 2
	tree = PERK_TREE_MIND_RES_ROBOTICIST
	requires = list(/datum/perk/mind/res_robo_module)

// ── Xeno-Archaeology ───────────────────────────────────────────────────────────

/datum/perk/mind/res_xeno_dig
	name = "Careful Excavation"
	desc = "Excavation tool use never destroys artifacts."
	icon_name = "brush"
	cost = 1
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_catalog
	name = "Cataloguer"
	desc = "Artifact analysers always return a verbose effect description."
	icon_name = "book"
	cost = 2
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_curator
	name = "Curator"
	desc = "Field-deployed artifacts you set up retain their unique effects after pickup."
	icon_name = "landmark"
	cost = 3
	tree = PERK_TREE_MIND_RES_XENOARCH
	requires = list(/datum/perk/mind/res_xeno_catalog)

/datum/perk/mind/res_xeno_strata
	name = "Strata Reader"
	desc = "Mining scanner highlights artifact-bearing strata."
	icon_name = "layer-group"
	cost = 1
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_linguist
	name = "Xeno-Linguist"
	desc = "Translate inscriptions on artifacts at a glance."
	icon_name = "language"
	cost = 2
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_sample
	name = "Sample Master"
	desc = "Biological samples you take from xeno fauna preserve 50% longer."
	icon_name = "vial-circle-check"
	cost = 1
	tree = PERK_TREE_MIND_RES_XENOARCH

/datum/perk/mind/res_xeno_curio
	name = "Curio Collector"
	desc = "Display-case artifacts give a small science research boost while displayed."
	icon_name = "trophy"
	cost = 2
	tree = PERK_TREE_MIND_RES_XENOARCH

// ═══════════════════════════════════════════════════════════════════════════════
// CARGO  (Quartermaster + Cargo Tech + Miner, ~7-8 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Quartermaster ──────────────────────────────────────────────────────────────

/datum/perk/mind/cargo_qm_market
	name = "Market Sense"
	desc = "Supply order prices show their last-week average alongside the current rate."
	icon_name = "clipboard-list"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_trader
	name = "Trader"
	desc = "Orders you approve cost 5% less department credits."
	icon_name = "money-bill-trend-up"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_logistics
	name = "Logistics"
	desc = "Mail bundles you sort are delivered 50% faster."
	icon_name = "truck-fast"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_QM
	requires = list(/datum/perk/mind/cargo_qm_market)

/datum/perk/mind/cargo_qm_negotiator
	name = "Skilled Negotiator"
	desc = "Premium-tier orders unlock at 10% discount."
	icon_name = "scale-balanced"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_priority
	name = "Priority Shipping"
	desc = "Express orders ship in one-third the standard time."
	icon_name = "rocket"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_bulk
	name = "Bulk Deal"
	desc = "Ordering 4+ of the same item drops the marginal cost by 15%."
	icon_name = "pallet"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_QM

/datum/perk/mind/cargo_qm_finance
	name = "Finance"
	desc = "Department-account interest accrues 25% faster while you're on shift."
	icon_name = "piggy-bank"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_QM

// ── Cargo Tech ─────────────────────────────────────────────────────────────────

/datum/perk/mind/cargo_tech_loader
	name = "Loader"
	desc = "You move heavy crates 25% faster."
	icon_name = "boxes-stacked"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_inventory
	name = "Inventory Eye"
	desc = "Examining a crate reveals every item inside without opening it."
	icon_name = "eye"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_dispatcher
	name = "Dispatcher"
	desc = "Disposal-bin sorting respects multi-tag routes you assign."
	icon_name = "compass"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_TECH
	requires = list(/datum/perk/mind/cargo_tech_loader)

/datum/perk/mind/cargo_tech_double_hand
	name = "Double Hand"
	desc = "Carry one extra crate in your hands at once."
	icon_name = "hand"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_swift
	name = "Swift Sorter"
	desc = "Sorting machines route items 50% faster while you're on shift."
	icon_name = "arrow-right-arrow-left"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_signage
	name = "Signage"
	desc = "Disposal pipe destination tags are visible to you on the world tile."
	icon_name = "signs-post"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_TECH

/datum/perk/mind/cargo_tech_express
	name = "Express Lane"
	desc = "Capstone shipping. Mail you process for express routes arrives instantly."
	icon_name = "envelope-circle-check"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_TECH
	requires = list(/datum/perk/mind/cargo_tech_dispatcher)

// ── Miner ──────────────────────────────────────────────────────────────────────

/datum/perk/mind/cargo_miner_strokes
	name = "Strong Strokes"
	desc = "Pickaxe / drill mining cycles are 20% faster."
	icon_name = "gem"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_geologist
	name = "Geologist"
	desc = "Mining scanner returns rarer ore types from further away."
	icon_name = "mountain"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_pathfinder
	name = "Pathfinder"
	desc = "Quarry-floor hazards (gas, fauna) are flagged on your HUD before you reach them."
	icon_name = "route"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_MINER
	requires = list(/datum/perk/mind/cargo_miner_geologist)

/datum/perk/mind/cargo_miner_efficient
	name = "Efficient Mining"
	desc = "Mining yields 10% additional ore on average."
	icon_name = "chart-line"
	cost = 2
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_lung
	name = "Quarry Lungs"
	desc = "Dust and rock-particle inhalation no longer slows or damages you."
	icon_name = "lungs"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_climber
	name = "Climber"
	desc = "Ladders and vent escape routes work 50% faster for you."
	icon_name = "stairs"
	cost = 1
	tree = PERK_TREE_MIND_CARGO_MINER

/datum/perk/mind/cargo_miner_motherlode
	name = "Motherlode"
	desc = "Capstone mining. Once-per-shift, your strike on a rare ore returns triple yield."
	icon_name = "diamond"
	cost = 3
	tree = PERK_TREE_MIND_CARGO_MINER
	requires = list(/datum/perk/mind/cargo_miner_strokes, /datum/perk/mind/cargo_miner_efficient)

// ═══════════════════════════════════════════════════════════════════════════════
// CIVILIAN  (Bartender + Chef + Botanist + Janitor, ~5-6 each)
// ═══════════════════════════════════════════════════════════════════════════════

// ── Bartender ──────────────────────────────────────────────────────────────────

/datum/perk/mind/civ_bar_pour
	name = "Steady Pour"
	desc = "Drinks you mix never spill and end at exactly the requested volume."
	icon_name = "martini-glass"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BARTENDER

/datum/perk/mind/civ_bar_recipe
	name = "Cocktail Repertoire"
	desc = "Drinks you serve apply a small mood boost to the patron for 60s."
	icon_name = "wine-glass"
	cost = 2
	tree = PERK_TREE_MIND_CIV_BARTENDER

/datum/perk/mind/civ_bar_bouncer
	name = "Bouncer"
	desc = "Disarm attempts inside the bar succeed 25% more often for you."
	icon_name = "hand"
	cost = 3
	tree = PERK_TREE_MIND_CIV_BARTENDER
	requires = list(/datum/perk/mind/civ_bar_pour)

/datum/perk/mind/civ_bar_listener
	name = "Listener"
	desc = "Patrons unload their secrets to you — examining a buzzed patron may reveal recent locations."
	icon_name = "ear-listen"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BARTENDER

/datum/perk/mind/civ_bar_signature
	name = "Signature Drink"
	desc = "Your signature cocktail grants a larger mood buff than standard drinks."
	icon_name = "champagne-glasses"
	cost = 2
	tree = PERK_TREE_MIND_CIV_BARTENDER

/datum/perk/mind/civ_bar_neutral_ground
	name = "Neutral Ground"
	desc = "Fights are less likely to start within line of sight of your bar."
	icon_name = "dove"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BARTENDER

// ── Chef ───────────────────────────────────────────────────────────────────────

/datum/perk/mind/civ_chef_knife
	name = "Knife Skills"
	desc = "Food prep is 25% faster and chopped ingredients yield an extra portion."
	icon_name = "utensils"
	cost = 1
	tree = PERK_TREE_MIND_CIV_CHEF

/datum/perk/mind/civ_chef_seasoning
	name = "Seasoning"
	desc = "Dishes you serve grant a small mood buff to the diner."
	icon_name = "pepper-hot"
	cost = 2
	tree = PERK_TREE_MIND_CIV_CHEF

/datum/perk/mind/civ_chef_pastry
	name = "Pastry"
	desc = "Baking recipes complete in one fewer step and produce an extra serving."
	icon_name = "cookie-bite"
	cost = 3
	tree = PERK_TREE_MIND_CIV_CHEF
	requires = list(/datum/perk/mind/civ_chef_knife)

/datum/perk/mind/civ_chef_butcher
	name = "Butcher"
	desc = "Butchered carcasses yield 25% more meat product."
	icon_name = "drumstick-bite"
	cost = 1
	tree = PERK_TREE_MIND_CIV_CHEF

/datum/perk/mind/civ_chef_food_critic
	name = "Food Critic"
	desc = "Examining a food item reveals its full recipe, nutrition, and any added reagents."
	icon_name = "burger"
	cost = 1
	tree = PERK_TREE_MIND_CIV_CHEF

/datum/perk/mind/civ_chef_legendary
	name = "Legendary Dish"
	desc = "Once per shift, prepare a signature meal with a unique long-duration mood buff."
	icon_name = "star"
	cost = 2
	tree = PERK_TREE_MIND_CIV_CHEF
	requires = list(/datum/perk/mind/civ_chef_seasoning)

// ── Botanist ───────────────────────────────────────────────────────────────────

/datum/perk/mind/civ_bot_greenthumb
	name = "Green Thumb"
	desc = "Plants you tend grow 15% faster."
	icon_name = "seedling"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BOTANIST

/datum/perk/mind/civ_bot_breeder
	name = "Breeder"
	desc = "Hybrid splices succeed 20% more often when you operate the pad."
	icon_name = "flask"
	cost = 2
	tree = PERK_TREE_MIND_CIV_BOTANIST

/datum/perk/mind/civ_bot_harvest
	name = "Bountiful Harvest"
	desc = "Harvests you collect yield one extra unit on average."
	icon_name = "wheat-awn"
	cost = 3
	tree = PERK_TREE_MIND_CIV_BOTANIST
	requires = list(/datum/perk/mind/civ_bot_greenthumb)

/datum/perk/mind/civ_bot_curator
	name = "Plant Curator"
	desc = "Examining a plant reveals its stats and unique traits."
	icon_name = "leaf"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BOTANIST

/datum/perk/mind/civ_bot_pollinator
	name = "Pollinator"
	desc = "Plants spread their effects to adjacent tiles when you've tended them."
	icon_name = "bug"
	cost = 1
	tree = PERK_TREE_MIND_CIV_BOTANIST

/datum/perk/mind/civ_bot_master_gardener
	name = "Master Gardener"
	desc = "Plants you grow have a 10% boost to their primary stat."
	icon_name = "tree"
	cost = 2
	tree = PERK_TREE_MIND_CIV_BOTANIST

// ── Janitor ────────────────────────────────────────────────────────────────────

/datum/perk/mind/civ_jan_sweep
	name = "Sweeping Stroke"
	desc = "Your mop / pushbroom clears a wider tile pattern per swipe."
	icon_name = "broom"
	cost = 1
	tree = PERK_TREE_MIND_CIV_JANITOR

/datum/perk/mind/civ_jan_no_slip
	name = "Steady Feet"
	desc = "You never slip on wet floors and your wet-floor signs deter would-be slippers."
	icon_name = "shoe-prints"
	cost = 2
	tree = PERK_TREE_MIND_CIV_JANITOR

/datum/perk/mind/civ_jan_immaculate
	name = "Immaculate"
	desc = "Spaces you clean stay clean — debris and stains don't accumulate for 5 minutes."
	icon_name = "spray-can-sparkles"
	cost = 3
	tree = PERK_TREE_MIND_CIV_JANITOR
	requires = list(/datum/perk/mind/civ_jan_sweep)

/datum/perk/mind/civ_jan_bucket_eye
	name = "Bucket Eye"
	desc = "Examining a janitorial bucket reveals its current and max contents."
	icon_name = "magnifying-glass"
	cost = 1
	tree = PERK_TREE_MIND_CIV_JANITOR

/datum/perk/mind/civ_jan_solvent
	name = "Solvent Specialist"
	desc = "Cleaning solutions you use refill 50% slower — you have a knack for stretching them."
	icon_name = "soap"
	cost = 1
	tree = PERK_TREE_MIND_CIV_JANITOR

/datum/perk/mind/civ_jan_silent_runner
	name = "Silent Runner"
	desc = "Your janitorial cart moves quietly — footstep sounds suppressed when pushing it."
	icon_name = "user-ninja"
	cost = 2
	tree = PERK_TREE_MIND_CIV_JANITOR
