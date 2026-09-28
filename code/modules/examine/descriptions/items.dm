/proc/describe_power(obj/item/source)
	switch(source.force)
		if(0)
			return "a negligable amount of"
		if(1 to 2)
			return "a very small amount of"
		if(3 to 5)
			return "a small amount of"
		if(6 to 10)
			return "a modest amount of"
		if(11 to 15)
			return "a moderate amount of"
		if(16 to 20)
			return "a respectable amount of"
		if(21 to 35)
			return "a serious amount of"
		if(36 to 50)
			return "a very serious amount of"
		if(51 to 100)
			return "a very lethal amount of"
		if(101 to 2000)
			return "a truly ruinous amount of"

/proc/describe_throwpower(obj/item/source)
	switch(source.throwforce)
		if(0)
			return "a negligable amount of"
		if(1 to 2)
			return "a very small amount of"
		if(3 to 5)
			return "a small amount of"
		if(6 to 10)
			return "a modest amount of"
		if(11 to 15)
			return "a moderate amount of"
		if(16 to 20)
			return "a respectable amount of"
		if(21 to 35)
			return "a serious amount of"
		if(36 to 50)
			return "a very serious amount of"
		if(51 to 100)
			return "a very lethal amount of"
		if(101 to 2000)
			return "a truly ruinous amount of"

/proc/describe_penetration(obj/item/source)
	switch(source.armor_penetration)
		if(0)
			return "cannot pierce armor"
		if(1 to 20)
			return "barely pierces armor"
		if(21 to 30)
			return "slightly pierces armor"
		if(31 to 40)
			return "reliably pierces lighter armors"
		if(41 to 50)
			return "pierces standard-issue armor reliably"
		if(51 to 60)
			return "pierces most armor reliably"
		if(61 to 70)
			return "pierces a great deal of armor"
		if(71 to 80)
			return "pierces the vast majority of armor"
		if(81 to 99)
			return "almost completely pierces all armor"
		if(100 to 1000)
			return "completely and utterly pierces all armor"

/proc/describe_speed(obj/item/source)
	if(source.attackspeed > DEFAULT_ATTACK_COOLDOWN)
		return "a slow attack speed"
	else if(source.attackspeed < DEFAULT_ATTACK_COOLDOWN)
		return "a high attack speed"
	else
		return "an average attack speed"

/proc/examine_tags(atom/source)
	var/list/info_stats = list()
	if(source.abstract_type == source.type)
		info_stats += span_hypnophrase("This is an abstract concept, you should report this to a strange entity called GITHUB!")

	if(source.resistance_flags & INDESTRUCTIBLE)
		info_stats += "It is extremely robust! It'll probably withstand anything that could happen to it!"
	else
		if(source.resistance_flags & LAVA_PROOF)
			info_stats += span_info("It is made of an extremely heat-resistant material, it'd probably be able to withstand lava!<br>")
		if(source.resistance_flags & (ACID_PROOF | UNACIDABLE))
			info_stats += span_info("It looks pretty robust! It'd probably be able to withstand acid!<br>")
		if(source.resistance_flags & FREEZE_PROOF)
			info_stats += span_info("It is made of cold-resistant materials.<br>")
		if(source.resistance_flags & FIRE_PROOF)
			info_stats += span_info("It is made of fire-retardant materials.<br>")
		if(source.resistance_flags & SHUTTLE_CRUSH_PROOF)
			info_stats += span_info("It is extremely solid. It should be able to withstand being run over by a shuttle!<br>")
		if(source.resistance_flags & BOMB_PROOF)
			info_stats += span_info("It looks like it could survive an explosion!<br>")
		if(source.resistance_flags & FLAMMABLE)
			info_stats += span_info("It looks like it could easily catch on fire.")
	return info_stats

//	if(flags_1 & HOLOGRAM_1)
//		.["holographic"] = "It looks like a hologram."


/obj/item/get_mechanics_info(list/additional_information)
	var/list/weapon_stats = list()

	if(LAZYLEN(additional_information))
		weapon_stats += additional_information

	if(force)
		weapon_stats += "If used in melee, it deals [describe_power(src)] [sharp ? "sharp" : "blunt"] damage, [describe_penetration(src)], and has [describe_speed(src)]."
	if(throwforce)
		weapon_stats += "If thrown, it would deal [describe_throwpower(src)] [sharp ? "sharp" : "blunt"] damage."
	if(can_cleave)
		weapon_stats += "It is capable of hitting multiple targets with a single swing."
	if(reach > 1)
		weapon_stats += "It can attack targets up to [reach] tiles away, and can attack over certain objects."

	weapon_stats += examine_tags(src)

	if(weapon_stats.len < 1)
		return ""

	var/assembled_string = ""
	for(var/index in 1 to weapon_stats.len)
		var/msg = weapon_stats[index]
		if(index != weapon_stats.len)
			msg += "\n"
		assembled_string += msg

	return assembled_string
