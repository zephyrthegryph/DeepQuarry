/proc/equip_fx(M, I)
	M.equip_to_slot(I, slot_head)
	M.equip_to_slot(I, "slot_head")
	x = slot_l_hand,
	x = slot_back
	if(SLOT_TOTAL)
	get_inventory_slot(x)
	slot_head
	slot_belt // ALLOW(check_grep): ok
	armor = list(melee = 1)
	var/list/armor = list(melee = 2)
	x.armor["melee"]
	x.armor?["melee"]
	y.armor = 5
	armor_spec = "melee=1"
	own_armor
	x.armored = 1
	z.armor.foo
	roll_armor_variance
