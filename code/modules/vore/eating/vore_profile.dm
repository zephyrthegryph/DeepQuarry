// A mob's vore preferences profile record (code/engine/declare/profiles.dm): the toggles and messages a player sets in the
// vore panel and saves with the character (/datum/vore_preferences is the save format: record_export() and record_import()
// move the fields across by name). Declared on /mob with profile(nameof(vore_prefs), /datum/record/vore_prefs) in mob_defines.dm.
// The spontaneous-vore bellies (spont_belly_*) are references, not data, and stay on the mob.

/datum/record/vore_prefs
	var/digestable = TRUE				// Can the mob be digested inside a belly?
	var/devourable = TRUE				// Can the mob be devoured at all?
	var/feeding = TRUE					// Can the mob be vorishly force fed or fed to others?
	var/absorbable = TRUE				// Are you allowed to absorb this person?
	var/allowmobvore = TRUE				// Will simplemobs attempt to eat the mob?
	var/permit_healbelly = TRUE
	var/allowtemp = TRUE				// Can they be affected by belly temperature?
	var/vore_taste = null				// What the character tastes like
	var/vore_smell = null				// What the character smells like
	var/noisy = FALSE					// Toggle audible hunger.
	var/show_vore_fx = TRUE				// Show belly fullscreens
	var/selective_preference = DM_DEFAULT	// Preference for selective bellymode
	var/size_strip_preference = SIZESTRIP_NONE	// Preference for size change stripping
	var/digest_leave_remains = FALSE	// Will this mob leave bones/skull/etc after the melty demise?
	var/digest_pain = TRUE
	var/noisy_full = FALSE					//Enables belching when a mob has overeaten
	var/eating_privacy_global = FALSE 	// Makes eating attempt/success messages only reach for subtle range if true, overwritten by belly-specific var
	var/vore_death_privacy = FALSE		// Chooses whether to announce prey death when digested to ghosts.
	var/can_be_drop_prey = FALSE
	var/can_be_drop_pred = FALSE
	var/can_be_afk_prey = TRUE
	var/can_be_afk_pred = TRUE
	var/throw_vore = TRUE
	var/food_vore = TRUE
	var/drop_vore = TRUE
	var/slip_vore = TRUE
	var/stumble_vore = TRUE
	var/phase_vore = TRUE					//Enabled by default since you have to enable drop pred/prey to do this anyway
	var/resizable = TRUE				// Can other people resize you? (Usually ignored for self-resizes)
	var/step_mechanics_pref = TRUE		// Allow participation in macro-micro step mechanics
	var/pickup_pref = TRUE				// Allow participation in macro-micro pickup mechanics
	var/allow_spontaneous_tf = FALSE	// Obviously.
	var/allow_mind_transfer = FALSE			//Allows ones mind to be taken over or swapped
	var/allow_mimicry = TRUE 	// Allows mimicking their character
	var/consume_liquid_belly = FALSE	//starting off because if someone is into that, they'll toggle it first time they get the error. Otherway around would be more pref breaky.
	var/receive_reagents = FALSE			//Pref for people to avoid others transfering reagents into them.
	var/apply_reagents = TRUE				//Pref for people to avoid having stomach reagents applied to them
	var/give_reagents = FALSE				//Pref for people to avoid others taking reagents from them.
	var/list/nutrition_messages = list( // ALLOW(instance_list): d: a record's nutrition_messages with starting entries, edited at runtime; one per mob
							"They are starving! You can hear their stomach snarling from across the room!",
							"They are extremely hungry. A deep growl occasionally rumbles from their empty stomach.",
							"",
							"They have a stuffed belly, bloated fat and round from eating too much.",
							"They have a rotund, thick gut. It bulges from their body obscenely, close to sagging under its own weight.",
							"They are sporting a large, round, sagging stomach. It contains at least their body weight worth of glorping slush.",
							"They are engorged with a huge stomach that sags and wobbles as they move. They must have consumed at least twice their body weight. It looks incredibly soft.",
							"Their stomach is firmly packed with digesting slop. They must have eaten at least a few times worth their body weight! It looks hard for them to stand, and their gut jiggles when they move.",
							"They are so absolutely stuffed that you aren't sure how it's possible for them to move. They can't seem to swell any bigger. The surface of their belly looks sorely strained!",
							"They are utterly filled to the point where it's hard to even imagine them moving, much less comprehend it when they do. Their gut is swollen to monumental sizes and amount of food they consumed must be insane.")
	var/nutrition_message_visible = TRUE
	var/weight_message_visible = TRUE
	var/list/weight_messages = list( // ALLOW(instance_list): d: a record's weight_messages with starting entries, edited at runtime; one per mob
							"They are terribly lithe and frail!",
							"They have a very slender frame.",
							"They have a lightweight, athletic build.",
							"They have a healthy, average body.",
							"They have a thick, curvy physique.",
							"They have a plush, chubby figure.",
							"They have an especially plump body with a round potbelly and large hips.",
							"They have a very fat frame with a bulging potbelly, squishy rolls of pudge, very wide hips, and plump set of jiggling thighs.",
							"They are incredibly obese. Their massive potbelly sags over their waistline while their fat ass would probably require two chairs to sit down comfortably!",
							"They are so morbidly obese, you wonder how they can even stand, let alone waddle around the station. They can't get any fatter without being immobilized.")
	var/latejoin_vore = FALSE				//If enabled, latejoiners can spawn into this, assuming they have a client
	var/latejoin_prey = FALSE				//If enabled, latejoiners can spawn ontop of and instantly eat the victim
	var/no_latejoin_vore_warning = FALSE	//Auto accepts pred spwan notifications (roundbased / saveable)
	var/no_latejoin_prey_warning = FALSE	//Auto accepts prey spawn notifications (roundbased / saveable)
	var/no_latejoin_vore_warning_time = 15	//Time until accepting prey
	var/no_latejoin_prey_warning_time = 15	//Time until accepting pred
	var/no_latejoin_vore_warning_persists = FALSE	//Do we save it?
	var/no_latejoin_prey_warning_persists = FALSE	//Do we save it?
	var/max_voreoverlay_alpha = 255
	var/strip_pref = TRUE					//Enables the ability for worn items to be stripped
	var/contaminate_pref = TRUE				//Enables the ability for worn items to be digested/contaminated.
	var/vore_sprite_multiply = list("stomach" = FALSE, "taur belly" = FALSE)
	var/vore_sprite_color = list("stomach" = "#000", "taur belly" = "#000")
	var/belly_rub_target = null
	var/soulcatcher_pref_flags = NONE			//Default disabled
	var/persistend_edit_mode = FALSE

/mob
	/// The player's vore preferences (a profile record, built before init).
	var/datum/record/vore_prefs/vore_prefs
