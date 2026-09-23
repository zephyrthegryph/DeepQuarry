// Diagnostic profiles: what an instrument can perceive.
//
// A profile is a stateless singleton (diagnostic_profile(type)). Every
// device that reports on a patient names one profile and hands it to
// body.diagnose(); devices differ only in what their sensors see and how a
// renderer presents the resulting /datum/diagnosis. See
// doc/health_system_review.md §5.8.
//
//   senses       PRESENT_* this device perceives; an affliction is found when
//                its presentation overlaps
//   biology      BIOLOGY_* of the parts its sensors read
//   vitals       VITALS_* it measures
//   part_detail  DIAG_PARTS_* per-part integrity reporting
//   localize     findings name the part they sit on
//   describe     findings carry the clinical description
//   hints        the report carries treatment_demand() as hints
//   trends       findings carry a trend against the previous scan
//   scan_level   SCANNABLE_* reagent / GM-affliction detection tier
//   scanner_machine  a medbay machine (GM afflictions show only when the GM
//                allows scanners to see them)
//   sees_fake_death  reads through feigned death

/datum/diagnostic_profile
	var/name = "unknown instrument"
	var/senses = PRESENT_VISIBLE
	var/biology = BIOLOGY_ALL
	var/vitals = NONE
	var/part_detail = DIAG_PARTS_NONE
	var/localize = FALSE
	var/describe = FALSE
	var/hints = FALSE
	var/trends = FALSE
	var/scan_level = SCANNABLE_BENEFICIAL
	var/scanner_machine = FALSE
	var/sees_fake_death = FALSE

/// The shared singleton for a profile type.
/proc/diagnostic_profile(profile_type)
	var/static/list/singletons = list()
	. = singletons[profile_type]
	if(!.)
		. = new profile_type()
		singletons[profile_type] = .

/// Naked eye: examine text and a passing glance.
/datum/diagnostic_profile/glance
	name = "visual inspection"
	senses = PRESENT_VISIBLE
	localize = TRUE

/// Hands on: grab inspection.
/datum/diagnostic_profile/palpation
	name = "palpation"
	senses = PRESENT_VISIBLE | PRESENT_PALPATION
	vitals = VITALS_PULSE | VITALS_CONSCIOUSNESS
	localize = TRUE

/// Medical HUD: status icons from what a glance plus a pulse sensor gives.
/datum/diagnostic_profile/medical_hud
	name = "medical HUD"
	senses = PRESENT_VISIBLE
	vitals = VITALS_PULSE

/// Suit sensors: coarse vitals over the crew monitor.
/datum/diagnostic_profile/suit_sensors
	name = "suit sensors"
	senses = NONE
	vitals = VITALS_PULSE | VITALS_SPO2 | VITALS_TEMP

/// Basic health analyzer: surface sensors, organic only.
/datum/diagnostic_profile/health_analyzer
	name = "health analyzer"
	senses = PRESENT_VISIBLE | PRESENT_SURFACE
	biology = BIOLOGY_ORGANIC
	vitals = VITALS_PULSE | VITALS_SPO2 | VITALS_TEMP | VITALS_CONSCIOUSNESS

/datum/diagnostic_profile/health_analyzer/improved
	name = "improved health analyzer"
	vitals = VITALS_PULSE | VITALS_BP | VITALS_SPO2 | VITALS_TEMP | VITALS_CONSCIOUSNESS
	localize = TRUE
	scan_level = SCANNABLE_ADVANCED

/// Advanced analyzer: internal imaging, full vitals, clinical hints.
/datum/diagnostic_profile/health_analyzer/advanced
	name = "advanced health analyzer"
	senses = PRESENT_VISIBLE | PRESENT_SURFACE | PRESENT_INTERNAL
	vitals = VITALS_ALL
	part_detail = DIAG_PARTS_BANDS
	localize = TRUE
	describe = TRUE
	hints = TRUE
	scan_level = SCANNABLE_DIFFICULT

/datum/diagnostic_profile/health_analyzer/phasic
	name = "phasic health analyzer"
	senses = PRESENT_VISIBLE | PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB
	vitals = VITALS_ALL
	part_detail = DIAG_PARTS_BANDS
	localize = TRUE
	describe = TRUE
	hints = TRUE
	trends = TRUE
	scan_level = SCANNABLE_SECRETIVE

/// Body scanner machine: every organic test, lesions included.
/datum/diagnostic_profile/body_scanner
	name = "body scanner"
	senses = PRESENT_VISIBLE | PRESENT_SURFACE | PRESENT_INTERNAL | PRESENT_LAB
	biology = BIOLOGY_ORGANIC | BIOLOGY_SYNTHETIC
	vitals = VITALS_ALL
	part_detail = DIAG_PARTS_BANDS
	localize = TRUE
	describe = TRUE
	hints = TRUE
	trends = TRUE
	scan_level = SCANNABLE_SECRETIVE
	scanner_machine = TRUE

/// Operating table monitor.
/datum/diagnostic_profile/operating_computer
	name = "operating computer"
	senses = PRESENT_VISIBLE | PRESENT_SURFACE | PRESENT_INTERNAL
	biology = BIOLOGY_ORGANIC | BIOLOGY_SYNTHETIC
	vitals = VITALS_ALL
	localize = TRUE
	describe = TRUE
	scanner_machine = TRUE

/// Bedside vitals monitor: every vital sign, no findings.
/datum/diagnostic_profile/vitals_monitor
	name = "vitals monitor"
	senses = NONE
	vitals = VITALS_ALL

/// Cyborg analyzer: the synthetic diagnostic bus.
/datum/diagnostic_profile/robot_analyzer
	name = "cyborg analyzer"
	senses = PRESENT_VISIBLE | PRESENT_SYNTHETIC
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	vitals = VITALS_TEMP | VITALS_CONSCIOUSNESS
	part_detail = DIAG_PARTS_BANDS
	localize = TRUE
	describe = TRUE
	hints = TRUE

/// Nanite swarm telemetry (protean diagnostics).
/datum/diagnostic_profile/nanite
	name = "nanite diagnostic"
	senses = PRESENT_VISIBLE | PRESENT_SYNTHETIC | PRESENT_NANITE
	biology = BIOLOGY_NANOFORM | BIOLOGY_SYNTHETIC
	vitals = VITALS_TEMP | VITALS_CONSCIOUSNESS
	part_detail = DIAG_PARTS_BANDS
	localize = TRUE
	describe = TRUE
	hints = TRUE

/// Automation (medbots, kiosks, sleepers): surface sensors plus treatment
/// demand, so a trained doctor with better instruments stays ahead.
/datum/diagnostic_profile/automation
	name = "automated triage"
	senses = PRESENT_VISIBLE | PRESENT_SURFACE
	biology = BIOLOGY_ORGANIC
	vitals = VITALS_PULSE | VITALS_SPO2 | VITALS_TEMP | VITALS_CONSCIOUSNESS
	localize = TRUE
	hints = TRUE

/// Admins see everything, through feigned death.
/datum/diagnostic_profile/admin
	name = "admin scan"
	senses = PRESENT_ALL
	vitals = VITALS_ALL
	part_detail = DIAG_PARTS_BANDS
	localize = TRUE
	describe = TRUE
	hints = TRUE
	scan_level = SCANNABLE_UNSCANNABLE
	sees_fake_death = TRUE
