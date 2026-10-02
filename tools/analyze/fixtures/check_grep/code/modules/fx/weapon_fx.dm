/obj/item/sword
	damtype = BRUTE
	var/damtype = 1
	x = M.damtype
	check_armour(x)
	attack_sharp = 1
	x.attack_edge
	injury_kind_for(x)
	damage_type = BRUTE
	var/damage_type = BURN
	damage_type = TOX
	damage_type = BRUTE // ALLOW(check_grep): ok
#define TOX 1
#define TOXIN 2
	HALLOSS
	SEARING
	ELECTROMAG
	ELECTROMAGNETIC
	x = run_armor_check(1)
	x = getarmor(1)
	x = getarmor_organ(1)
	get_injury_mod(1)
	injury_mod_groups
