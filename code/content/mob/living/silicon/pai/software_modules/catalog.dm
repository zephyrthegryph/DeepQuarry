/datum/pai_software/radio_config
	name = "Radio Configuration"
	ram_cost = 0
	id = "radio"
	toggle = 0
	default = 1

/datum/pai_software/radio_config/ui_redirect(mob/living/silicon/pai/user)
	return user.radio

/datum/pai_software/messenger
	name = "Digital Messenger"
	ram_cost = 0
	id = "messenger"
	toggle = 0
	default = 1		//Can already be accessed through verbs, and also why not

/datum/pai_software/messenger/ui_redirect(mob/living/silicon/pai/user)
	return user.pda

/datum/pai_software/deathalarm
	name = "Death Alarm"
	ram_cost = 25
	id = "death_alarm"

/datum/pai_software/deathalarm/toggle(mob/living/silicon/pai/user)
	user.paiDA = !user.paiDA

/datum/pai_software/deathalarm/is_active(mob/living/silicon/pai/user)
	return user.paiDA
