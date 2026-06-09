GLOBAL_LIST_EMPTY(all_robolimbs)
GLOBAL_LIST_EMPTY(robolimb_data)
GLOBAL_LIST_EMPTY(chargen_robolimbs)
GLOBAL_DATUM(basic_robolimb, /datum/robolimb)

/proc/populate_robolimb_list()
	GLOB.basic_robolimb = new()
	for(var/limb_type in typesof(/datum/robolimb))
		var/datum/robolimb/R = new limb_type()
		GLOB.all_robolimbs[R.company] = R
		if(!R.unavailable_at_chargen)
			GLOB.chargen_robolimbs[R.company] = R //List only main brands and solo parts.

	for(var/company in GLOB.all_robolimbs)
		var/datum/robolimb/R = GLOB.all_robolimbs[company]
		if(R.species_alternates)
			for(var/species in R.species_alternates)
				var/species_company = R.species_alternates[species]
				if(species_company in GLOB.all_robolimbs)
					R.species_alternates[species] = GLOB.all_robolimbs[species_company]

/datum/robolimb
	var/company = "Unbranded"                            // Shown when selecting the limb.
	var/desc = "A generic unbranded robotic prosthesis." // Seen when examining a limb.
	var/icon = 'icons/mob/human_races/robotic.dmi'       // Icon base to draw from.
	var/monitor_icon = 'icons/mob/monitor_icons.dmi'     // Where it draws the monitor icon from.
	var/unavailable_at_chargen                           // If set, not available at chargen.
	var/unavailable_to_build                             // If set, can't be constructed.
	var/lifelike                                         // If set, appears organic.
	var/skin_tone                                        // If set, applies skin tone rather than part color Overrides color.
	var/skin_color                                       // If set, applies skin color rather than part color.
	var/blood_color = SYNTH_BLOOD_COLOUR                 // Colour for blood splatters.
	var/blood_name = "oil"                               // Descriptor for blood splatters.
	var/list/monitor_styles                              // If empty, the model of limbs offers a head compatible with monitors.
	var/parts = BP_ALL                                   // Defines what parts said brand can replace on a body.
	var/health_hud_intensity = 1                         // Intensity modifier for the health GUI indicator.
	var/suggested_species = "Human"                      // If it should make the torso a species
	var/speech_bubble_appearance = "synthetic"           // What icon_state to use for speech bubbles when talking.  Check talk.dmi for all the icons.
	var/modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // Whether or not this limb allows attaching/detaching, and whether or not it checks its parent as well. // Let's just do full detachment/reattachment by default.
	var/robo_brute_mod = 1                               // Multiplier for incoming brute damage.
	var/robo_burn_mod = 1                                // As above for burn.
	// Species in this list cannot take these prosthetics.
	var/list/species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_XENOCHIMERA)
	// "Species Name" = "Robolimb Company", List, when initialized, will become "Species Name" = RobolimbDatum, used for alternate species sprites.
	var/list/species_alternates = list(SPECIES_TAJARAN = "Unbranded - Tajaran", SPECIES_UNATHI = "Unbranded - Unathi")

/datum/robolimb/unbranded_monitor
	company = "Unbranded Monitor"
	desc = "A generic unbranded interpretation of a popular prosthetic head model. It looks rudimentary and cheaply constructed."
	icon = 'icons/mob/human_races/cyberlimbs/unbranded/unbranded_monitor.dmi'
	parts = list(BP_HEAD)
	monitor_styles = STANDARD_MONITOR_STYLES
	unavailable_to_build = 1

/datum/robolimb/unbranded_alt1
	company = "Unbranded - Protez"
	desc = "A simple robotic limb with retro design. Seems rather stiff."
	icon = 'icons/mob/human_races/cyberlimbs/unbranded/unbranded_alt1.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/unbranded_alt2
	company = "Unbranded - Mantis Prosis"
	desc = "This limb has a casing of sleek black metal and repulsive insectile design."
	icon = 'icons/mob/human_races/cyberlimbs/unbranded/unbranded_alt2.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/unbranded_tajaran
	company = "Unbranded - Tajaran"
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_UNATHI, SPECIES_SKRELL, SPECIES_ZADDAT)
	suggested_species = SPECIES_TAJARAN
	desc = "A simple robotic limb with feline design. Seems rather stiff."
	icon = 'icons/mob/human_races/cyberlimbs/unbranded/unbranded_tajaran.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/unbranded_unathi
	company = "Unbranded - Unathi"
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_TAJARAN, SPECIES_SKRELL, SPECIES_ZADDAT)
	suggested_species = SPECIES_UNATHI
	desc = "A simple robotic limb with reptilian design. Seems rather stiff."
	icon = 'icons/mob/human_races/cyberlimbs/unbranded/unbranded_unathi.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/unbranded_teshari
	company = "Unbranded - Teshari"
	species_cannot_use = list(SPECIES_UNATHI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_TAJARAN, SPECIES_SKRELL, SPECIES_ZADDAT)
	suggested_species = SPECIES_TESHARI
	desc = "A simple robotic limb with a small, raptor-like design. Seems rather stiff."
	icon = 'icons/mob/human_races/cyberlimbs/unbranded/unbranded_teshari.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions
	parts = list(BP_HEAD, BP_TORSO, BP_GROIN)

/datum/robolimb/unbranded_teshari/limbs
	company = "Unbranded - Teshari (Limbs)"
	parts = list(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC

/datum/robolimb/nanotrasen
	company = "NanoTrasen"
	desc = "A simple but efficient robotic limb, created by NanoTrasen."
	icon = 'icons/mob/human_races/cyberlimbs/nanotrasen/nanotrasen_main.dmi'
	species_alternates = list(SPECIES_TAJARAN = "NanoTrasen - Tajaran", SPECIES_UNATHI = "NanoTrasen - Unathi")
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/nanotrasen_tajaran
	company = "NanoTrasen - Tajaran"
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_UNATHI, SPECIES_SKRELL, SPECIES_ZADDAT)
	species_alternates = list(SPECIES_HUMAN = "NanoTrasen")
	suggested_species = SPECIES_TAJARAN
	desc = "A simple but efficient robotic limb, created by NanoTrasen."
	icon = 'icons/mob/human_races/cyberlimbs/nanotrasen/nanotrasen_tajaran.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/nanotrasen_unathi
	company = "NanoTrasen - Unathi"
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_TAJARAN, SPECIES_SKRELL, SPECIES_ZADDAT)
	species_alternates = list(SPECIES_HUMAN = "NanoTrasen")
	suggested_species = SPECIES_UNATHI
	desc = "A simple but efficient robotic limb, created by NanoTrasen."
	icon = 'icons/mob/human_races/cyberlimbs/nanotrasen/nanotrasen_unathi.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/cenilimicybernetics_teshari
	company = "Cenilimi Cybernetics"
	species_cannot_use = list(SPECIES_UNATHI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_TAJARAN, SPECIES_SKRELL, SPECIES_ZADDAT)
	species_alternates = list(SPECIES_HUMAN = "NanoTrasen")
	suggested_species = SPECIES_TESHARI
	desc = "Made by a Teshari-owned company, for Teshari."
	icon = 'icons/mob/human_races/cyberlimbs/cenilimicybernetics/cenilimicybernetics_teshari.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/bishop
	company = "Bishop"
	desc = "This limb has a white polymer casing with blue holo-displays."
	icon = 'icons/mob/human_races/cyberlimbs/bishop/bishop_main.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/bishop_alt1
	company = "Bishop - Glyph"
	desc = "This limb has a white polymer casing with blue holo-displays."
	icon = 'icons/mob/human_races/cyberlimbs/bishop/bishop_alt1.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/bishop_alt2
	company = "Bishop - Rook"
	desc = "This limb has a solid plastic casing with blue lights along it."
	icon = 'icons/mob/human_races/cyberlimbs/bishop/bishop_alt2.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/bishop_monitor
	company = "Bishop Monitor"
	desc = "Bishop Cybernetics' unique spin on a popular prosthetic head model. The themes conflict in an intriguing way."
	icon = 'icons/mob/human_races/cyberlimbs/bishop/bishop_monitor.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = STANDARD_MONITOR_STYLES
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/gestaltframe
	company = "Skrellian Exoskeleton"
	desc = "This limb looks to be more like a strange.. puppet, than a prosthetic."
	icon = 'icons/mob/human_races/cyberlimbs/veymed/dionaea/skrellian.dmi'
	blood_color = "#63b521"
	blood_name = "synthetic ichor"
	speech_bubble_appearance = "machine"
	unavailable_to_build = 1
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_TAJARAN, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_UNATHI, SPECIES_SKRELL, SPECIES_ZADDAT)
	suggested_species = SPECIES_DIONA
	// Dionaea are naturally very tanky, so the robotic limbs are actually far weaker than their normal bodies.
	robo_brute_mod = 1.3
	robo_burn_mod = 1.3
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/cybersolutions
	company = "Cyber Solutions"
	desc = "This limb is grey and rough, with little in the way of aesthetic."
	icon = 'icons/mob/human_races/cyberlimbs/cybersolutions/cybersolutions_main.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/cybersolutions_alt2
	company = "Cyber Solutions - Outdated"
	desc = "This limb is of severely outdated design; there's no way it's comfortable or very functional to use."
	icon = 'icons/mob/human_races/cyberlimbs/cybersolutions/cybersolutions_alt2.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/cybersolutions_alt1
	company = "Cyber Solutions - Wight"
	desc = "This limb has cheap plastic panels mounted on grey metal."
	icon = 'icons/mob/human_races/cyberlimbs/cybersolutions/cybersolutions_alt1.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/cybersolutions_alt3
	company = "Cyber Solutions - Array"
	desc = "This limb is simple and functional; array of sensors on a featureless case."
	icon = 'icons/mob/human_races/cyberlimbs/cybersolutions/cybersolutions_alt3.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/einstein
	company = "Einstein Engines"
	desc = "This limb is lightweight with a sleek design."
	icon = 'icons/mob/human_races/cyberlimbs/einstein/einstein_main.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/grayson
	company = "Grayson"
	desc = "This limb has a sturdy and heavy build to it."
	icon = 'icons/mob/human_races/cyberlimbs/grayson/grayson_main.dmi'
	unavailable_to_build = 0
	monitor_styles = "blank=grayson_off-colored;\
		red=grayson_red-colored;\
		green=grayson_green-colored;\
		blue=grayson_blue-colored;\
		rgb=grayson_rgb-colored"
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/grayson_alt1
	company = "Grayson - Reinforced"
	desc = "This limb has a sturdy and heavy build to it."
	icon = 'icons/mob/human_races/cyberlimbs/grayson/grayson_alt1.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = "blank=grayson_alt_off;\
		green=grayson_alt_green;\
		scroll=grayson_alt_scroll;\
		rgb=grayson_alt_rgb;\
		rainbow=grayson_alt_rainbow"
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/grayson_monitor
	company = "Grayson Monitor"
	desc = "This limb has a sturdy and heavy build to it, and uses plastics in the place of glass for the monitor."
	icon = 'icons/mob/human_races/cyberlimbs/grayson/grayson_monitor.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = STANDARD_MONITOR_STYLES
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/hephaestus
	company = "Hephaestus"
	desc = "This limb has a militaristic black and green casing with gold stripes."
	icon = 'icons/mob/human_races/cyberlimbs/hephaestus/hephaestus_main.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/hephaestus_alt1
	company = "Hephaestus - Frontier"
	desc = "A rugged prosthetic head featuring the standard Hephaestus theme, a visor and an external display."
	icon = 'icons/mob/human_races/cyberlimbs/hephaestus/hephaestus_alt1.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = "blank=hesphiastos_alt_off-colored;\
		pink=hesphiastos_alt_pink-colored;\
		orange=hesphiastos_alt_orange-colored;\
		goggles=hesphiastos_alt_goggles-colored;\
		scroll=hesphiastos_alt_scroll;\
		rgb=hesphiastos_alt_rgb-colored;\
		rainbow=hesphiastos_alt_rainbow-colored"
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/hephaestus_alt2
	company = "Hephaestus - Athena"
	desc = "This rather thick limb has a militaristic green plating."
	icon = 'icons/mob/human_races/cyberlimbs/hephaestus/hephaestus_alt2.dmi'
	unavailable_to_build = 1
	monitor_styles = "red=athena_red-colored;\
		blank=athena_off-colored"
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/hephaestus_monitor
	company = "Hephaestus Monitor"
	desc = "Hephaestus' unique spin on a popular prosthetic head model. It looks rugged and sturdy."
	icon = 'icons/mob/human_races/cyberlimbs/hephaestus/hephaestus_monitor.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = STANDARD_MONITOR_STYLES
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/morpheus
	company = "Morpheus"
	desc = "This limb is simple and functional; no effort has been made to make it look human."
	icon = 'icons/mob/human_races/cyberlimbs/morpheus/morpheus_main.dmi'
	unavailable_to_build = 0
	monitor_styles = STANDARD_MONITOR_STYLES
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/morpheus_alt1
	company = "Morpheus - Zenith"
	desc = "This limb is simple and functional; no effort has been made to make it look human."
	icon = 'icons/mob/human_races/cyberlimbs/morpheus/morpheus_alt1.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/morpheus_alt2
	company = "Morpheus - Skeleton Crew"
	desc = "This limb is simple and functional; it's basically just a case for a brain."
	icon = 'icons/mob/human_races/cyberlimbs/morpheus/morpheus_alt2.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/veymed
	company = "Vey-Med"
	desc = "This high quality limb is nearly indistinguishable from an organic one."
	icon = 'icons/mob/human_races/cyberlimbs/veymed/veymed_main_vr.dmi' // fixing the color application
	unavailable_to_build = 1
	lifelike = 1
	skin_tone = 1
	species_alternates = list(SPECIES_SKRELL = "Vey-Med - Skrell")
	blood_color = "#CCCCCC"
	blood_name = "coolant"
	speech_bubble_appearance = "normal"
	// robo_brute_mod = 1.1 //
	// robo_burn_mod = 1.1 //
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/veymed_skrell
	company = "Vey-Med - Skrell"
	desc = "This high quality limb is nearly indistinguishable from an organic one."
	icon = 'icons/mob/human_races/cyberlimbs/veymed/veymed_skrell.dmi'
	unavailable_to_build = 1
	lifelike = 1
	skin_color = TRUE
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_TAJARAN, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_UNATHI, SPECIES_DIONA, SPECIES_ZADDAT)
	blood_color = "#4451cf"
	blood_name = "coolant"
	speech_bubble_appearance = "normal"
	// robo_brute_mod = 1.05 //
	// robo_burn_mod = 1.05 //
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/wardtakahashi
	company = "Ward-Takahashi"
	desc = "This limb features sleek black and white polymers."
	icon = 'icons/mob/human_races/cyberlimbs/wardtakahashi/wardtakahashi_main.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/wardtakahashi_alt1
	company = "Ward-Takahashi - Shroud"
	desc = "This limb features sleek black and white polymers. This one looks more like a helmet of some sort."
	icon = 'icons/mob/human_races/cyberlimbs/wardtakahashi/wardtakahashi_alt1.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/wardtakahashi_alt2
	company = "Ward-Takahashi - Spirit"
	desc = "This limb has white and purple features, with a heavier casing."
	icon = 'icons/mob/human_races/cyberlimbs/wardtakahashi/wardtakahashi_alt2.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/wardtakahashi_monitor
	company = "Ward-Takahashi Monitor"
	desc = "Ward-Takahashi's unique spin on a popular prosthetic head model. It looks sleek and modern."
	icon = 'icons/mob/human_races/cyberlimbs/wardtakahashi/wardtakahashi_monitor.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = STANDARD_MONITOR_STYLES
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/xion
	company = "Xion"
	desc = "This limb has a minimalist black and red casing."
	icon = 'icons/mob/human_races/cyberlimbs/xion/xion_main.dmi'
	unavailable_to_build = 0
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/xion_alt1
	company = "Xion - Breach"
	desc = "This limb has a minimalist black and red casing. Looks a bit menacing."
	icon = 'icons/mob/human_races/cyberlimbs/xion/xion_alt1.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/xion_alt2
	company = "Xion - Hull"
	desc = "This limb has a thick orange casing with steel plating."
	icon = 'icons/mob/human_races/cyberlimbs/xion/xion_alt2.dmi'
	unavailable_to_build = 1
	monitor_styles = "blank=xion_off-colored;\
		red=xion_red-colored;\
		green=xion_green-colored;\
		blue=xion_blue-colored;\
		rgb=xion_rgb-colored"
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/xion_alt3
	company = "Xion - Whiteout"
	desc = "This limb has a minimalist black and white casing."
	icon = 'icons/mob/human_races/cyberlimbs/xion/xion_alt3.dmi'
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/xion_alt4
	company = "Xion - Breach - Whiteout"
	desc = "This limb has a minimalist black and white casing. Looks a bit menacing."
	icon = 'icons/mob/human_races/cyberlimbs/xion/xion_alt4.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions


/datum/robolimb/xion_monitor
	company = "Xion Monitor"
	desc = "Xion Mfg.'s unique spin on a popular prosthetic head model. It looks and minimalist and utilitarian."
	icon = 'icons/mob/human_races/cyberlimbs/xion/xion_monitor.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_styles = STANDARD_MONITOR_STYLES
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/zenghu
	company = "Zeng-Hu"
	desc = "This limb has a rubbery fleshtone covering with visible seams."
	icon = 'icons/mob/human_races/cyberlimbs/zenghu/zenghu_main.dmi'
	species_alternates = list(SPECIES_TAJARAN = "Zeng-Hu - Tajaran")
	unavailable_to_build = 1
	skin_tone = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC // remove the restrictions

/datum/robolimb/wooden
	company = "Morgan Trading Co"
	desc = "A simplistic, metal-banded, wood-panelled prosthetic."
	icon = 'icons/mob/human_races/cyberlimbs/prosthesis/wooden.dmi'
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC
	parts = list(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC

/obj/item/disk/limb
	name = "Limb Blueprints"
	desc = "A disk containing the blueprints for prosthetics."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-white"
	var/company = ""

/datum/robolimb/wooden/teshari
	company = "Morgan Trading Co - Teshari"
	icon = 'icons/mob/human_races/cyberlimbs/prosthesis/wooden_teshari.dmi'
	species_cannot_use = list(SPECIES_UNATHI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_TAJARAN, SPECIES_SKRELL, SPECIES_ZADDAT)
	species_alternates = list(SPECIES_HUMAN = "Morgan Trading Co")
	suggested_species = SPECIES_TESHARI

/datum/robolimb/wooden/sif
	company = "Morgan Trading Co - Sif wood"
	desc = "A simplistic, metal-banded, wood-panelled prosthetic. This one is covered in Sivian wood!"
	icon = 'icons/mob/human_races/cyberlimbs/prosthesis/wooden_sif.dmi'

/datum/robolimb/wooden/sif/teshari
	company = "Morgan Trading Co - Sif wood - Teshari"
	icon = 'icons/mob/human_races/cyberlimbs/prosthesis/wooden_sif_teshari.dmi'
	species_cannot_use = list(SPECIES_UNATHI, SPECIES_PROMETHEAN, SPECIES_DIONA, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_TAJARAN, SPECIES_SKRELL, SPECIES_ZADDAT)
	species_alternates = list(SPECIES_HUMAN = "Morgan Trading Co")
	suggested_species = SPECIES_TESHARI

/datum/robolimb/replika
	company = "Replikant"
	desc = "An advanced biomechanical prosthetic with pegs for feet."
	icon = 'icons/mob/human_races/cyberlimbs/replikant/replikant.dmi'
	lifelike = 1
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC
	parts = list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)

/datum/robolimb/replika2
	company = "Replikant - 2nd Gen"
	desc = "Modern, second-generation biomechanical prosthetics with pegs for feet."
	icon = 'icons/mob/human_races/cyberlimbs/replikant/replikant2.dmi'
	lifelike = 1
	unavailable_to_build = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC
	parts = list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)

/* 
/datum/robolimb/digi
	company = "DSI Digitigrade Legs" //yup that's how I'm fixing this, you NEED to have digi on or else oh god it looks weird
	desc = "Synthflesh-wrapped robotic digitigrade legs, for the animal in all of us."
	icon = 'icons/mob/human_races/r_digi.dmi'
	lifelike = 1
	unavailable_to_build = 1
	skin_tone = 1
	parts = list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
*/

/obj/item/disk/limb/Initialize(mapload)
	. = ..()
	if(company)
		name = "[company] [initial(name)]"

/obj/item/disk/limb/bishop
	company = "Bishop"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/bishop)

/obj/item/disk/limb/cybersolutions
	company = "Cyber Solutions"

/obj/item/disk/limb/grayson
	company = "Grayson"

/obj/item/disk/limb/hephaestus
	company = "Hephaestus"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/hephaestus)

/obj/item/disk/limb/morpheus
	company = "Morpheus"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/morpheus)

/obj/item/disk/limb/veymed
	company = "Vey-Med"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/vey_med)

// Bus disk for Diona mech parts.
/obj/item/disk/limb/veymed/diona
	company = "Skrellian Exoskeleton"

/obj/item/disk/limb/wardtakahashi
	company = "Ward-Takahashi"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/ward_takahashi)

/obj/item/disk/limb/xion
	company = "Xion"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/xion)

/obj/item/disk/limb/zenghu
	company = "Zeng-Hu"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/zeng_hu)

/obj/item/disk/limb/nanotrasen
	company = "NanoTrasen"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/nanotrasen)

/obj/item/disk/species
	name = "Species Bioprints"
	desc = "A disk containing the blueprints for species-specific prosthetics."
	icon = 'icons/obj/cloning.dmi'
	icon_state = "datadisk2"
	var/species = SPECIES_HUMAN

/obj/item/disk/species/Initialize(mapload)
	. = ..()
	if(species)
		name = "[species] [initial(name)]"

/obj/item/disk/species/skrell
	species = SPECIES_SKRELL

/obj/item/disk/species/unathi
	species = SPECIES_UNATHI

/obj/item/disk/species/tajaran
	species = SPECIES_TAJARAN

/obj/item/disk/species/teshari
	species = SPECIES_TESHARI

// In case of bus, presently.
/obj/item/disk/species/diona
	species = SPECIES_DIONA

/obj/item/disk/species/zaddat
	species = SPECIES_ZADDAT

/obj/item/disk/limb/cenilimicybernetics
	company = "Cenilimi Cybernetics"


// === merged from robolimbs_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/robolimb
	var/no_icon = FALSE //specifically for DSI things, makes it so it doesn't override the species icons
	var/can_be_digitigrade = FALSE //used for skipping the icon if it can be digitigrade - maybe turn this into more of a 'use this icon/iconstate' instead later, when actual prosthetic digi icons get made

/datum/robolimb/valehoundhead
	company = "VALE Hound- Head"
	desc = "A VALE hound head meant for synthetics."
	icon = 'icons/mob/human_races/cyberlimbs/vale/vale_head.dmi' //Sprited by: Skits
	skin_tone = 1
	parts = list(BP_HEAD)

/datum/robolimb/dsi_tajaran
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_lizard
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_sergal
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_nevrean
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_vulpkanin
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_akula
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_spider
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_zorren
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_fennec
	can_be_digitigrade = TRUE

/datum/robolimb/dsi_teshari/New()
	. = ..()
	species_cannot_use -= SPECIES_PROTEAN


/datum/robolimb/dsi_other
	company = "DSI - Adaptive"
	desc = "This limb has a  realistic design and squish. By Darkside Incorperated."
	blood_color = "#ffe2ff"
	lifelike = 1
	unavailable_to_build = 1
	skin_tone = 1
	no_icon = TRUE

/datum/robolimb/hellscout
	company = "Erebus - Hellscout"
	desc = "Sleek and lightweight aluminum casings, accented with dark silicone."
	icon = 'icons/mob/human_races/cyberlimbs/erebus/hellscout.dmi'
	unavailable_to_build = 0

//ported from citRP

/datum/robolimb/spectre
	company = "Hoffman Tech - RACS Spectre "
	desc = "A simple robotic limb design used for the Hoffman Tech RASC Spectre. A lightweight robotic chassis ideal for exploration and security duties."
	icon = 'icons/mob/human_races/cyberlimbs/cit/hoffman_tech/spectre.dmi'
	unavailable_to_build = TRUE

/datum/robolimb/braincase
	company = "cortexCases - MMI"
	desc = "A solid, transparent case to hold your important bits in with style."
	icon = 'icons/mob/human_races/cyberlimbs/cit/cortex/braincase.dmi'
	unavailable_to_build = TRUE
	parts = list(BP_HEAD)

///obj/item/disk/limb/braincase
//	company = "cortexCases - MMI"

/datum/robolimb/posicase
	company = "cortexCases - Posi"
	desc = "A solid, transparent case to hold your important bits in with style."
	icon = 'icons/mob/human_races/cyberlimbs/cit/cortex/posicase.dmi'
	unavailable_to_build = TRUE
	parts = list(BP_HEAD)

///obj/item/disk/limb/posicase
//	company = "cortexCases - Posi"

/datum/robolimb/antares
	company = "Antares Robotics"
	desc = "Mustard-yellow industrial limb. Heavyset and thick."
	icon = 'icons/mob/human_races/cyberlimbs/cit/antares/antares_main.dmi'
	unavailable_to_build = TRUE
	monitor_styles = STANDARD_MONITOR_STYLES

///obj/item/disk/limb/antares
//	company = "Antares Robotics"

/datum/robolimb/replika
	company = "Replikant"
	desc = "An advanced biomechanical prosthetic with pegs for feet."
	icon = 'icons/mob/human_races/cyberlimbs/cit/replikant/replikant.dmi'
	lifelike = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC
	parts = list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)


// === merged from robolimbs_vr.dm during hard-fork de-suffix (verified no override-order change) ===
GLOBAL_LIST_INIT(dsi_to_species, list(SPECIES_TAJARAN = "DSI - Tajaran", SPECIES_UNATHI = "DSI - Lizard", SPECIES_SERGAL = "DSI - Sergal", SPECIES_NEVREAN = "DSI - Nevrean", \
									SPECIES_VULPKANIN = "DSI - Vulpkanin", SPECIES_AKULA = "DSI - Akula", SPECIES_VASILISSAN = "DSI - Vasilissan", SPECIES_ZORREN = "DSI - Zorren",\
									SPECIES_TESHARI = "DSI - Teshari", SPECIES_FENNEC = "DSI - Fennec"))


// Placeholder for protean limbs during character spawning, before they have a properly set model
/datum/robolimb/protean
	company = "protean"
	desc = "Nano-y!"
	lifelike = 1
	unavailable_to_build = 1
	unavailable_at_chargen = 1

//////////////// For-specific-character fluff ones /////////////////
// arokha : Aronai Sieyes
/datum/robolimb/kitsuhana
	company = "Kitsuhana"
	desc = "This limb seems rather vulpine and fuzzy, with realistic-feeling flesh."
	icon = 'icons/mob/human_races/cyberlimbs/_fluff/aronai.dmi'
	blood_color = "#5dd4fc"
	includes_tail = 1
	includes_ears = 1
	lifelike = 1
	unavailable_to_build = 1
	suggested_species = SPECIES_VULPKANIN
	whitelisted_to = list("arokha")

/obj/item/disk/limb/kitsuhana
	company = "Kitsuhana"

// silencedmp5a5 : Serdykov Antoz
/datum/robolimb/white_kryten
	company = "White Kryten Cybernetics"
	desc = "This limb feels realistic to the touch, with soft fur. Were it not for the bright orange lights embedded in it, you might have trouble telling it from a non synthetic limb!"
	icon = 'icons/mob/human_races/cyberlimbs/_fluff/serdykov.dmi'
	blood_color = "#ff6a00"
	unavailable_to_build = 1
	includes_tail = 1
	whitelisted_to = list("silencedmp5a5")

/obj/item/disk/limb/white_kryten
	company = "White Kryten Cybernetics"

// tucker0666 : Frost
/datum/robolimb/zenghu_frost
	company = "Zeng-Hu (Custom)"
	desc = "This limb has realistic synthetic flesh covering with 'blue accents'."
	icon = 'icons/mob/human_races/cyberlimbs/_fluff/Frosty.dmi'
	blood_color = "#45ccff"
	lifelike = 1
	skin_tone = 1
	unavailable_to_build = 1
	whitelisted_to = list("tucker0666")

/obj/item/disk/limb/zenghu_frost
	company = "Zeng-Hu (Modified)"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/zeng_hu)

//Ported from CitRP
/datum/robolimb/cyber_beast
	company = "Cyber Tech"
	desc = "Adjusted for deep space, the material is durable and heavy."
	icon = 'icons/mob/human_races/cyberlimbs/c-tech/c_beast.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)
	monitor_icon = 'icons/mob/monitor_icons_vr.dmi'
	monitor_styles = CYBERBEAST_MONITOR_STYLES

/obj/item/disk/limb/cyber_beast
	company = "Cyber Tech"

/datum/robolimb/zenghu_glacier
	company = "Zeng-Hu Glacier"
	desc = "This limb has a rubbery white covering with visible seams."
	icon = 'icons/mob/human_races/cyberlimbs/zenghu/zenghu_glacier_main.dmi'
	species_alternates = list(SPECIES_TAJARAN = "Zeng-Hu - Tajaran")
	unavailable_to_build = 1
	skin_tone = 1
	modular_bodyparts = MODULAR_BODYPART_PROSTHETIC

/datum/robolimb/zenghu_taj_glacier
	company = "Zeng-Hu Glacier - Tajaran"
	desc = "This limb has a rubbery white covering with visible seams."
	icon = 'icons/mob/human_races/cyberlimbs/zenghu/zenghu_glacier_taj.dmi'
	unavailable_to_build = 1
	parts = list(BP_HEAD)


// === merged from robolimbs_chomp.dm during hard-fork de-suffix (manually verified: all-new types / new defines, no base re-open) ===
#define YR3_MONITOR_STYLES "blank=YR3_blank;\
	eyes=YR3_eyes;\
	foureyes=YR3_foureyes;\
	slanteyes=YR3_evileyes;\
	bigeyes=YR3_bigeyes;\
	talleyes=YR3_talleyes;\
	sliteyes=YR3_sliteyes;\
	monoeye=YR3_monoeye;\
	blindeye=YR3_blindeye;\
	protodefault=cyber_default;\
	protofrown=cyber_unhapp;\
	protosad=cyber_sad;\
	proto^w^=cyber_nwn;\
	protoOwO=yr3cyber_owo;\
	protoUwU=cyber_uwu;\
	pokerface=cyber_flat;\
	smiley=cyber_happ;\
	question=cyber_question;\
	query=YR3_query-colored;\
	interrogative=YR3_interrogative-colored;\
	heart=cyber_heart;\
	X=cyber_cross;\
	exclamation=cyber_alert;\
	alarmed=YR3_danger-colored;\
	surprised=YR3_surprise-colored;\
	checkmark=YR3_safe-colored;\
	heart=YR3_heart-colored;\
	idle=cyber_idle;\
	loading=YR3_loading;\
	hypno=YR3_hypno;\
	static=yr3cyber_static;\
	lowpower=cyber_lowpower;\
	bluescreen=YR3_bsod-colored;\
	cracked=YR3_cracked-colored;\
	broken=YR3_broken-colored;\
	endo=YR3_safebar-colored;\
	processing1=YR3_processing-colored;\
	processing2=YR3_assimilating-colored;\
	processed=YR3_processed-colored;\
	containmentbreach=YR3_crackedopenbloody-colored"

/datum/robolimb/enviroshell
	company = "YR3 Enviroshell"
	desc = "A limb with oddly high internal pressure tolerance."
	icon = 'icons/mob/human_races/cyberlimbs/YR3/YR3_enviroshell.dmi'
	monitor_icon = 'icons/mob/monitor_icons.dmi'
	monitor_styles = YR3_MONITOR_STYLES

/datum/robolimb/enviroshell/original
	company = "YR3 Enviroshell- Original Xenochimera Model"
	desc = "A limb with oddly high internal pressure tolerance. In a somewhat macrabe manner, it uses the blood of its wearer, in place of hydraulic fluids."
	species_cannot_use = list(SPECIES_TESHARI, SPECIES_PROMETHEAN, SPECIES_TAJARAN, SPECIES_HUMAN, SPECIES_VOX, SPECIES_HUMAN_VATBORN, SPECIES_UNATHI, SPECIES_SKRELL, SPECIES_ZADDAT, SPECIES_DIONA)
	blood_name = "blood"
	blood_color = "#ba0b0b"

/datum/robolimb/enviroshell/colorable
	company = "YR3 Enviroshell-Colorable"
	icon = 'icons/mob/human_races/cyberlimbs/YR3/YR3_enviroshell_colorable.dmi'
	lifelike = 1
	skin_tone = 1

/datum/robolimb/enviroshell/original/colorable
	company = "YR3 Enviroshell- Colorable Xenochimera Model"
	icon = 'icons/mob/human_races/cyberlimbs/YR3/YR3_enviroshell_colorable.dmi'
	lifelike = 1
	skin_tone = 1

/datum/robolimb/enviroshell/sleek
	company = "YR3 Slimline"
	desc = "A limb which sacrifices the YR3 Enviroshell's containment capabilities, replacing the intended occupant with a mesh of deceptively simple nanite pseudomuscle"
	blood_name = "motor nanites"
	blood_color = "#0e1213"
	icon = 'icons/mob/human_races/cyberlimbs/YR3/YR3_sleek.dmi'
	lifelike = TRUE

#undef YR3_MONITOR_STYLES
