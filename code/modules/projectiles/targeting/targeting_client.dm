//These are called by the on-screen buttons, adjusting what the victim can and cannot do.
/client/proc/add_gun_icons()
	if(!mob) return 1
	screen |= mob.item_use_icon
	screen |= mob.gun_move_icon
	screen |= mob.radio_use_icon

/client/proc/remove_gun_icons()
	if(!mob) return 1
	screen -= mob.item_use_icon
	screen -= mob.gun_move_icon
	screen -= mob.radio_use_icon
