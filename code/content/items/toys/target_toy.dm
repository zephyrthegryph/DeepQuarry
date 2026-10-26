/obj/item/storage/briefcase/target_toy
	starts_with = list(
	/obj/item/paper/target,
	/obj/item/gun/projectile/revolver/toy/big_iron,
	/obj/item/grenade/confetti = 2
	)

/obj/item/paper/target
	name = "target notice"

CAPABILITIES(/obj/item/paper/target)
	rolls(nameof(info), PROC_REF(roll_info))

/// Rolled before init (rolls()): the target's name.
/obj/item/paper/target/proc/roll_info(datum/roller/R)
	return "Your target is " + span_bold("[random_name(R.choose(list(MALE, FEMALE)))]") + ". Make sure they don't get out of there alive."

