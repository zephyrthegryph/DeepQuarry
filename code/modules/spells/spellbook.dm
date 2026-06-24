/obj/item/spellbook
	name = "spell book"
	desc = "The legendary book of spells of the wizard."
	icon = 'icons/obj/library.dmi'
	icon_state ="spellbook"
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	var/uses = 5
	var/temp = null
	var/max_uses = 5
	var/op = 1

	///Var for attack_self chain
	var/special_handling = FALSE

// attack_self moved to code/modules/spells/spellbook_panel.dm so it opens via structured TGUI.

/obj/item/spellbook/Topic(href, href_list)
	..()
	if(!ishuman(usr))
		return 1
	var/mob/living/carbon/human/H = usr

	if(H.stat || H.restrained())
		return

	if(H.mind && H.mind.special_role == JOB_APPRENTICE)
		temp = "If you got caught sneaking a peak from your teacher's spellbook, you'd likely be expelled from the Wizard Academy. Better not."
		return

	if(loc == H || (in_range(src, H) && istype(loc, /turf)))
		H.set_machine(src)
		if(href_list["spell_choice"])
			if(href_list["spell_choice"] == "rememorize")
				var/area/wizard_station/A = locate()
				if(H in A.contents)
					uses = max_uses
					H.spellremove()
					temp = "All spells have been removed. You may now memorize a new set of spells."
					feedback_add_details("wizard_spell_learned","UM") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
				else
					temp = "You may only re-memorize spells whilst located inside the wizard sanctuary."
			else if(uses >= 1 && max_uses >=1)
				if(href_list["spell_choice"] == "noclothes")
					if(uses < 2)
						return
				uses--
			/*
			*/
				var/list/available_spells = list(magicmissile = "Magic Missile", fireball = "Fireball", disabletech = "Disable Tech", smoke = "Smoke", blind = "Blind", subjugation = "Subjugation", mindswap = "Mind Transfer", forcewall = "Forcewall", blink = "Blink", teleport = "Teleport", mutate = "Mutate", etherealjaunt = "Ethereal Jaunt", knock = "Knock", horseman = "Curse of the Horseman", staffchange = "Staff of Change", mentalfocus = "Mental Focus", soulstone = "Six Soul Stone Shards and the spell Artificer", armor = "Mastercrafted Armor Set", staffanimate = "Staff of Animation", noclothes = "No Clothes")
				var/already_knows = 0
				for(var/datum/spell/aspell in H.spell_list)
					if(available_spells[href_list["spell_choice"]] == initial(aspell.name))
						already_knows = 1
						if(!aspell.can_improve())
							temp = "This spell cannot be improved further."
							uses++
							break
						else
							if(aspell.can_improve("speed") && aspell.can_improve("power"))
								switch(tgui_alert(src, "Do you want to upgrade this spell's speed or power?", "Select Upgrade", list("Speed", "Power", "Cancel")))
									if("Speed")
										temp = aspell.quicken_spell()
									if("Power")
										temp = aspell.empower_spell()
									else
										uses++
										break
							else if (aspell.can_improve("speed"))
								temp = aspell.quicken_spell()
							else if (aspell.can_improve("power"))
								temp = aspell.empower_spell()
			/*
			*/
				if(!already_knows)
					switch(href_list["spell_choice"])
						if("noclothes")
							feedback_add_details("wizard_spell_learned","NC")
							H.add_spell(new/datum/spell/noclothes)
							temp = "This teaches you how to use your spells without your magical garb, truely you are the wizardest."
							uses--
						if("magicmissile")
							feedback_add_details("wizard_spell_learned","MM") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/targeted/projectile/magic_missile)
							temp = "You have learned magic missile."
						if("fireball")
							feedback_add_details("wizard_spell_learned","FB") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/targeted/projectile/dumbfire/fireball)
							temp = "You have learned fireball."
						if("disabletech")
							feedback_add_details("wizard_spell_learned","DT") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/aoe_turf/disable_tech)
							temp = "You have learned disable technology."
						if("smoke")
							feedback_add_details("wizard_spell_learned","SM") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/aoe_turf/smoke)
							temp = "You have learned smoke."
						if("blind")
							feedback_add_details("wizard_spell_learned","BD") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/targeted/genetic/blind)
							temp = "You have learned blind."
						if("subjugation")
							feedback_add_details("wizard_spell_learned","SJ") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/targeted/subjugation)
							temp = "You have learned subjugate."
//						if("mindswap")
//							feedback_add_details("wizard_spell_learned","MT") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
//							H.add_spell(new/datum/spell/targeted/mind_transfer)
//							temp = "You have learned mindswap."
						if("forcewall")
							feedback_add_details("wizard_spell_learned","FW") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/aoe_turf/conjure/forcewall)
							temp = "You have learned forcewall."
						if("blink")
							feedback_add_details("wizard_spell_learned","BL") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/aoe_turf/blink)
							temp = "You have learned blink."
						if("teleport")
							feedback_add_details("wizard_spell_learned","TP") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/area_teleport)
							temp = "You have learned teleport."
						if("mutate")
							feedback_add_details("wizard_spell_learned","MU") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/targeted/genetic/mutate)
							temp = "You have learned mutate."
						if("etherealjaunt")
							feedback_add_details("wizard_spell_learned","EJ") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/targeted/ethereal_jaunt)
							temp = "You have learned ethereal jaunt."
						if("knock")
							feedback_add_details("wizard_spell_learned","KN") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							H.add_spell(new/datum/spell/aoe_turf/knock)
							temp = "You have learned knock."
//						if("horseman")
//							feedback_add_details("wizard_spell_learned","HH") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
//							H.add_spell(new/datum/spell/targeted/equip_item/horsemask)
//							temp = "You have learned curse of the horseman."
						if("mentalfocus")
							feedback_add_details("wizard_spell_learned","MF") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							new /obj/item/gun/energy/staff/focus(get_turf(H))
							temp = "An artefact that channels the will of the user into destructive bolts of force."
							max_uses--
						if("soulstone")
							feedback_add_details("wizard_spell_learned","SS") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							new /obj/item/storage/belt/soulstone/full(get_turf(H))
							H.add_spell(new/datum/spell/aoe_turf/conjure/construct)
							temp = "You have purchased a belt full of soulstones and have learned the artificer spell."
							max_uses--
						if("armor")
							feedback_add_details("wizard_spell_learned","HS") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							new /obj/item/clothing/shoes/sandal(get_turf(H)) //In case they've lost them.
							new /obj/item/clothing/gloves/purple(get_turf(H))//To complete the outfit
							new /obj/item/clothing/suit/space/void/wizard(get_turf(H))
							new /obj/item/clothing/head/helmet/space/void/wizard(get_turf(H))
							temp = "You have purchased a suit of wizard armor."
							max_uses--
						if("scrying")
							feedback_add_details("wizard_spell_learned","SO") //please do not change the abbreviation to keep data processing consistent. Add a unique id to any new spells
							new /obj/item/scrying(get_turf(H))
							if (!(XRAY in H.mutations))
								H.mutations.Add(XRAY)
								H.sight |= (SEE_MOBS|SEE_OBJS|SEE_TURFS)
								H.see_in_dark = 8
								H.see_invisible = SEE_INVISIBLE_LEVEL_TWO
								to_chat(H, span_notice("The walls suddenly disappear."))
							temp = "You have purchased a scrying orb, and gained x-ray vision."
							max_uses--
		else
			if(href_list["temp"])
				temp = null
		attack_self()

	return

//Single Use Spellbooks//

/obj/item/spellbook/oneuse
	var/spell = /datum/spell/targeted/projectile/magic_missile //just a placeholder to avoid runtimes if someone spawned the generic
	var/spellname = "sandbox"
	var/used = 0
	name = "spellbook of "
	uses = 1
	max_uses = 1
	desc = "This template spellbook was never meant for the eyes of man..."
	special_handling = TRUE

/obj/item/spellbook/oneuse/Initialize(mapload)
	. = ..()
	name += spellname

/obj/item/spellbook/oneuse/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/datum/spell/S = new spell(user)
	for(var/datum/spell/knownspell in user.spell_list)
		if(knownspell.type == S.type)
			if(user.mind)
				// TODO: Update to new antagonist system.
				if(user.mind.special_role == JOB_APPRENTICE || user.mind.special_role == JOB_WIZARD)
					to_chat(user, span_notice("You're already far more versed in this spell than this flimsy how-to book can provide."))
				else
					to_chat(user, span_notice("You've already read this one."))
			return
	if(used)
		recoil(user)
	else
		user.add_spell(S)
		to_chat(user, span_notice("you rapidly read through the arcane book. Suddenly you realize you understand [spellname]!"))
		add_attack_logs(user, src, "learned the spell [spellname] ([S]).")
		onlearned(user)

/obj/item/spellbook/oneuse/proc/recoil(mob/user as mob)
	user.visible_message(span_warning("[src] glows in a black light!"))

/obj/item/spellbook/oneuse/proc/onlearned(mob/user as mob)
	used = 1
	user.visible_message(span_warning("[src] glows dark for a second!"))

/obj/item/spellbook/oneuse/attackby()
	return

/obj/item/spellbook/oneuse/fireball
	spell = /datum/spell/targeted/projectile/dumbfire/fireball
	spellname = "fireball"
	icon_state ="bookfireball"
	desc = "This book feels warm to the touch."

/obj/item/spellbook/oneuse/fireball/recoil(mob/user as mob)
	..()
	explosion(user.loc, -1, 0, 2, 3, 0)
	qdel(src)

/obj/item/spellbook/oneuse/smoke
	spell = /datum/spell/aoe_turf/smoke
	spellname = "smoke"
	icon_state ="booksmoke"
	desc = "This book is overflowing with the dank arts."

/obj/item/spellbook/oneuse/smoke/recoil(mob/living/user as mob)
	..()
	to_chat(user, span_warning("Your stomach rumbles..."))
	if(user.nutrition)
		user.adjust_nutrition(-200)

/obj/item/spellbook/oneuse/blind
	spell = /datum/spell/targeted/genetic/blind
	spellname = "blind"
	icon_state ="bookblind"
	desc = "This book looks blurry, no matter how you look at it."

/obj/item/spellbook/oneuse/blind/recoil(mob/user as mob)
	..()
	to_chat(user, span_warning("You go blind!"))
	user.Blind(10)

/obj/item/spellbook/oneuse/mindswap
	spell = /datum/spell/targeted/mind_transfer
	spellname = "mindswap"
	icon_state ="bookmindswap"
	desc = "This book's cover is pristine, though its pages look ragged and torn."
	var/mob/stored_swap = null //Used in used book recoils to store an identity for mindswaps

/obj/item/spellbook/oneuse/mindswap/onlearned()
	spellname = pick("fireball","smoke","blind","forcewall","knock","horses","charge")
	icon_state = "book[spellname]"
	name = "spellbook of [spellname]" //Note, desc doesn't change by design
	..()

/obj/item/spellbook/oneuse/mindswap/recoil(mob/user as mob)
	..()
	if(stored_swap in GLOB.dead_mob_list)
		stored_swap = null
	if(!stored_swap)
		stored_swap = user
		to_chat(user, span_warning("For a moment you feel like you don't even know who you are anymore."))
		return
	if(stored_swap == user)
		to_chat(user, span_notice("You stare at the book some more, but there doesn't seem to be anything else to learn..."))
		return

	if(user.mind.special_verbs.len)
		for(var/V in user.mind.special_verbs)
			remove_verb(user, V)

	if(stored_swap.mind.special_verbs.len)
		for(var/V in stored_swap.mind.special_verbs)
			remove_verb(stored_swap, V)

	var/mob/observer/dead/ghost = stored_swap.ghostize(0)
	ghost.spell_list = stored_swap.spell_list

	user.mind.transfer_to(stored_swap)
	stored_swap.spell_list = user.spell_list

	if(stored_swap.mind.special_verbs.len)
		for(var/V in user.mind.special_verbs)
			add_verb(user, V)

	ghost.mind.transfer_to(user)
	user.key = ghost.key
	user.spell_list = ghost.spell_list

	if(user.mind.special_verbs.len)
		for(var/V in user.mind.special_verbs)
			add_verb(user, V)

	to_chat(stored_swap, span_warning("You're suddenly somewhere else... and someone else?!"))
	to_chat(user, span_warning("Suddenly you're staring at [src] again... where are you, who are you?!"))
	stored_swap = null

/obj/item/spellbook/oneuse/forcewall
	spell = /datum/spell/aoe_turf/conjure/forcewall
	spellname = "forcewall"
	icon_state ="bookforcewall"
	desc = "This book has a dedication to mimes everywhere inside the front cover."

/obj/item/spellbook/oneuse/forcewall/recoil(mob/user as mob)
	..()
	to_chat(user, span_warning("You suddenly feel very solid!"))
	var/obj/structure/closet/statue/S = new /obj/structure/closet/statue(get_turf(user), user)
	S.timer = 30
	user.drop_item()


/obj/item/spellbook/oneuse/knock
	spell = /datum/spell/aoe_turf/knock
	spellname = "knock"
	icon_state ="bookknock"
	desc = "This book is hard to hold closed properly."

/obj/item/spellbook/oneuse/knock/recoil(mob/user as mob)
	..()
	to_chat(user, span_warning("You're knocked down!"))
	user.Weaken(20)

/obj/item/spellbook/oneuse/horsemask
	spell = /datum/spell/targeted/equip_item/horsemask
	spellname = "horses"
	icon_state ="bookhorses"
	desc = "This book is more horse than your mind has room for."

/obj/item/spellbook/oneuse/horsemask/recoil(mob/living/carbon/user as mob)
	if(ishuman(user))
		to_chat(user, span_narsie(span_bolddanger("HOR-SIE HAS RISEN")))
		var/obj/item/clothing/mask/horsehead/magichead = new /obj/item/clothing/mask/horsehead
		magichead.say_verbs = list("neighs", "whinnys", "snorts")
		magichead.say_messages = list("NEEEEIGH", "KEECHOOOW", "WHIIIINNNY", "NEEEEEEIGHHHH", "KEECHOOOWWW")
		magichead.canremove = FALSE		//curses!
		magichead.flags_inv = null	//so you can still see their face
		magichead.voicechange = 1	//NEEEEIIGHH
		user.drop_from_inventory(user.wear_mask)
		user.equip_to_slot_if_possible(magichead, slot_wear_mask, 1, 1)
		qdel(src)
	else
		to_chat(user, span_notice("I say thee neigh"))

/obj/item/spellbook/oneuse/charge
	spell = /datum/spell/aoe_turf/charge
	spellname = "charging"
	icon_state ="bookcharge"
	desc = "This book is made of 100% post-consumer wizard."

/obj/item/spellbook/oneuse/charge/recoil(mob/user as mob)
	..()
	to_chat(user, span_warning("[src] suddenly feels very warm!"))
	empulse(src, 1, 1, 1, 1)
