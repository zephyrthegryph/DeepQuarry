/mob/living/carbon/human/proc/get_hair_accessory_overlay()
	if(hair_accessory_style && !(get_equipped_item(SLOT_ID_HEAD) && (get_equipped_item(SLOT_ID_HEAD).flags_inv & BLOCKHEADHAIR)))
		var/icon/hair_acc_s = icon(hair_accessory_style.icon, hair_accessory_style.icon_state)
		if(hair_accessory_style.do_colouration)
			hair_acc_s.Blend(rgb(src.r_ears, src.g_ears, src.b_ears), hair_accessory_style.color_blend_mode)
		return hair_acc_s
	return null
