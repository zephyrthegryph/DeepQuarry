/*
Semi-randomized loot for PoIs involving medicine.
Note that most of these include both 'good' and 'bad' results, with the bad results often being
much more likely to show up. This is done for several purposes;

 * A large influx of valuable medicine makes medical/SAR less needed for explorers, which is something we want to avoid.
 * Blindly using autoinjectors should be risky, and to accomplish that, it needs to be more likely to get a bad effect.
 * A large amount of bad loot helps make the good loot feel better to acquire.

*/

// This one makes a purely random hypo. Not recommended for PoIs since it will produce nonsensical results for a PoI's theme.
// It's more of a thing to help pick specific hypos for the other lists.
/obj/random/unidentified_medicine
	name = "unidentified medicine"
	desc = "This will make a random hypo."
	icon = 'icons/obj/syringe.dmi'
	icon_state = "autoinjector1"

CAPABILITIES(/obj/random/unidentified_medicine)
	loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/clonemed/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/brute/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/burn/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/toxin/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/oxy/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/purity/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/pain/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/organ/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/combat/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/healing_nanites/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/stimm/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/bliss/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/expired/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/serotrotium/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cryptobiolin/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mindbreaker/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/psilocybin/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/soporific/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cyanide/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/impedrezene/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mutagen/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/defective_nanites/unidentified,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated/unidentified))

// Produces things you might find in an old medicine cabinet in a PoI.
// Old cabinets are typical of ruins and abandoned buildings in the plains, meaning they're usually easier to reach, and as such, inferior loot.
/obj/random/unidentified_medicine/old_medicine
CAPABILITIES(/obj/random/unidentified_medicine/old_medicine)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/brute/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/burn/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/toxin/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/oxy/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/purity/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/pain/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/expired/unidentified = 65,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated/unidentified = 5)))

// Medicine belonging to a place still being occupied (or was recently), meaning the goods might still be fresh, and better.
/obj/random/unidentified_medicine/fresh_medicine
CAPABILITIES(/obj/random/unidentified_medicine/fresh_medicine)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/clonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/brute/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/burn/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/toxin/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/oxy/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/purity/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/pain/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/organ/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/expired/unidentified = 25)))

// For military PoIs like BSD. High odds of good loot since those PoIs are really hard.
/obj/random/unidentified_medicine/combat_medicine
CAPABILITIES(/obj/random/unidentified_medicine/combat_medicine)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/clonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/brute/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/burn/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/pain/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/organ/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/combat/unidentified = 30,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/soporific/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cyanide/unidentified = 30)))

// Hyposprays found inside various illicit places.
/obj/random/unidentified_medicine/drug_den
CAPABILITIES(/obj/random/unidentified_medicine/drug_den)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/clonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/pain/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/organ/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/combat/unidentified = 40,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/stimm/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/bliss/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/serotrotium/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cryptobiolin/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mindbreaker/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/psilocybin/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/soporific/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/impedrezene/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cyanide/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated/unidentified = 5)))

// Medicine made FOR SCIENCE.
/obj/random/unidentified_medicine/scientific
CAPABILITIES(/obj/random/unidentified_medicine/scientific)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/clonemed/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/organ/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/combat/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/healing_nanites/unidentified = 5,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated/unidentified = 20,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cyanide/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mutagen/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/defective_nanites/unidentified = 5)))

// Nanomachines, son. Found in very advanced places such as the Crashed UFO.
/obj/random/unidentified_medicine/nanites
CAPABILITIES(/obj/random/unidentified_medicine/nanites)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/healing_nanites/unidentified = 30,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/defective_nanites/unidentified = 70)))

// Found in virus-related areas like the Quarantined Shuttle.
/obj/random/unidentified_medicine/viral
CAPABILITIES(/obj/random/unidentified_medicine/viral)
	configure(loot(
		table = list(
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/purity/unidentified = 30,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/expired/unidentified = 40,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mutagen/unidentified = 10,
			/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated/unidentified = 20)))
