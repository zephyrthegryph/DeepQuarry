//  Virgo modified syndie beacon, does not give objectives

// DQEdit Start — attack_hand body relocated to modular_dq/code/modules/admin/misc_admin_panels.dm (structured TGUI).
// DQEdit End

/obj/machinery/syndicate_beacon/virgo/Topic(href, href_list)
	if(href_list["betraitor"])
		if(charges < 1)
			updateUsrDialog(usr)
			return
		var/mob/M = locate(href_list["traitormob"])
		if(M.mind.tcrystals > 0 || jobban_isbanned(M, JOB_SYNDICATE))
			temptext = "<i>We have no need for you at this time. Have a pleasant day.</i><br>"
			updateUsrDialog(usr)
			return
		charges -= 1
		if(ishuman(M))
			var/mob/living/carbon/human/N = M
			to_chat(N, span_infoplain(span_bold("Access granted, here are the supplies!")))
			GLOB.traitors.spawn_uplink(N)
			N.mind.tcrystals = DEFAULT_TELECRYSTAL_AMOUNT
			N.mind.accept_tcrystals = 1
			message_admins("[N]/([N.ckey]) has received an uplink and telecrystals from the syndicate beacon.")

	updateUsrDialog(usr)
	return
