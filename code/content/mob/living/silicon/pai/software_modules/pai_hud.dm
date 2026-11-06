/datum/pai_software/pai_hud
	name = "AR HUD"
	ram_cost = 30
	id = "ar_hud"

/datum/pai_software/pai_hud/toggle(mob/living/silicon/pai/user)
	user.paiHUD = !user.paiHUD
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_ID,user.paiHUD)
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_WANTED,user.paiHUD)
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_IMPTRACK,user.paiHUD)
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_IMPCHEM,user.paiHUD)
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_STATUS_R,user.paiHUD)
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_HEALTH_VR,user.paiHUD)
	hud_of(user)?.plane_holder?.set_vis(VIS_CH_BACKUP,user.paiHUD) //backup stuff from silicon_vr is here now
	hud_of(user)?.plane_holder?.set_vis(VIS_AUGMENTED,user.paiHUD)

/datum/pai_software/pai_hud/is_active(mob/living/silicon/pai/user)
	return user.paiHUD
