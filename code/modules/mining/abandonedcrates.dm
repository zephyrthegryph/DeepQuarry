/obj/structure/closet/crate/secure/loot
	name = "abandoned crate"
	desc = "What could be inside?"
	closet_appearance = /datum/decl/closet_appearance/crate/secure
	var/list/code = list()
	var/list/lastattempt = list()
	var/attempts = 10
	var/codelen = 4
	locked = 1

/obj/structure/closet/crate/secure/loot/Initialize(mapload)
	. = ..()
	var/list/digits = list("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")

	for(var/i in 1 to codelen)
		code += pick(digits)
		digits -= code[code.len]

	generate_loot()

/* see abandonedcrates_vr.dm for virgo version. Keeping legacy proc in comments for reference.

/obj/structure/closet/crate/secure/loot/proc/generate_loot()
	var/loot = rand(1, 100)
	switch(loot)
		if(1 to 5) // Common things go, 5%
			new/obj/item/reagent_containers/food/drinks/bottle/rum(src)
			new/obj/item/reagent_containers/food/drinks/bottle/whiskey(src)
			new/obj/item/reagent_containers/food/snacks/grown/ambrosiadeus(src)
			new/obj/item/flame/lighter/zippo(src)
		if(6 to 10)
			new/obj/item/pickaxe/advdrill(src)
			new/obj/item/taperecorder(src)
			new/obj/item/clothing/suit/space(src)
			new/obj/item/clothing/head/helmet/space(src)
		if(11 to 15)
			new/obj/item/reagent_containers/glass/beaker/bluespace(src)
		if(16 to 20)
			for(var/i = 0, i < 10, i++)
				new/obj/item/ore/diamond(src)
		if(21 to 25)
			for(var/i = 0, i < 3, i++)
				new/obj/machinery/portable_atmospherics/hydroponics(src)
		if(26 to 30)
			for(var/i = 0, i < 3, i++)
				new/obj/item/reagent_containers/glass/beaker/noreact(src)
		if(31 to 35)
			spawn_money(rand(300,800), src)
		if(36 to 40)
			new/obj/item/melee/baton(src)
		if(41 to 45)
			new/obj/item/clothing/under/shorts/red(src)
			new/obj/item/clothing/under/shorts/blue(src)
		if(46 to 50)
			new/obj/item/clothing/under/chameleon(src)
			for(var/i = 0, i < 7, i++)
				new/obj/item/clothing/accessory/tie/horrible(src)
		if(51 to 52) // Uncommon, 2% each
			new/obj/item/melee/classic_baton(src)
		if(53 to 54)
			new/obj/item/latexballon(src)
		if(55 to 56)
			var/newitem = pick(subtypesof(/obj/item/toy/mecha))
			new newitem(src)
		if(57 to 58)
			new/obj/item/toy/syndicateballoon(src)
		if(59 to 60)
			new/obj/item/rig/industrial(src)
		if(61 to 62)
			for(var/i = 0, i < 12, ++i)
				new/obj/item/clothing/head/kitty(src)
		if(63 to 64)
			var/t = rand(4,7)
			for(var/i = 0, i < t, ++i)
				var/newcoin = pick(/obj/item/coin/silver, /obj/item/coin/silver, /obj/item/coin/silver, /obj/item/coin/iron, /obj/item/coin/iron, /obj/item/coin/iron, /obj/item/coin/gold, /obj/item/coin/diamond, /obj/item/coin/phoron, /obj/item/coin/uranium, /obj/item/coin/platinum)
				new newcoin(src)
		if(65 to 66)
			new/obj/item/clothing/suit/ianshirt(src)
		if(67 to 68)
			var/t = rand(4,7)
			for(var/i = 0, i < t, ++i)
				var/newitem = pick(subtypesof(/obj/item/stock_parts) - /obj/item/stock_parts/subspace)
				new newitem(src)
		if(69 to 70)
			new/obj/item/pickaxe/silver(src)
		if(71 to 72)
			new/obj/item/pickaxe/drill(src)
		if(73 to 74)
			new/obj/item/pickaxe/jackhammer(src)
		if(75 to 76)
			new/obj/item/pickaxe/diamond(src)
		if(77 to 78)
			new/obj/item/pickaxe/diamonddrill(src)
		if(79 to 80)
			new/obj/item/pickaxe/gold(src)
		if(81 to 82)
			new/obj/item/pickaxe/plasmacutter(src)
		if(83 to 84)
			new/obj/item/toy/katana(src)
		if(85 to 86)
			new/obj/item/seeds/random(src)
		if(87) // Rarest things, some are unobtainble otherwise, some are just robust,  1% each
			new/obj/item/weed_extract(src)
		if(88)
			new/obj/item/xenos_claw(src)
		if(89)
			new/obj/item/clothing/head/bearpelt(src)
		if(90)
			new/obj/item/organ/internal/heart(src)
		if(91)
			new/obj/item/soulstone(src)
		if(92)
			new/obj/item/material/sword/katana(src)
		if(93)
			new/obj/item/dnainjector/set_trait/xray(src) // Probably the least OP
		if(94) // Why the hell not
			new/obj/item/storage/backpack/clown(src)
			new/obj/item/clothing/under/rank/clown(src)
			new/obj/item/clothing/shoes/clown_shoes(src)
			new/obj/item/pda/clown(src)
			new/obj/item/clothing/mask/gas/clown_hat(src)
			new/obj/item/bikehorn(src)
			//new/obj/item/stamp/clown(src) I'd add it, but only clowns can use it
			new/obj/item/pen/crayon/rainbow(src)
			new/obj/item/reagent_containers/spray/waterflower(src)
		if(95)
			new/obj/item/clothing/under/mime(src)
			new/obj/item/clothing/shoes/black(src)
			new/obj/item/pda/mime(src)
			new/obj/item/clothing/gloves/white(src)
			new/obj/item/clothing/mask/gas/mime(src)
			new/obj/item/clothing/head/beret(src)
			new/obj/item/clothing/suit/suspenders(src)
			new/obj/item/pen/crayon/mime(src)
			new/obj/item/reagent_containers/food/drinks/bottle/bottleofnothing(src)
		if(96)
			new/obj/item/vampiric(src)
		if(97)
			new/obj/item/archaeological_find(src)
		if(98)
			new/obj/item/melee/energy/sword(src)
		if(99)
			new/obj/item/storage/belt/champion(src)
			new/obj/item/clothing/mask/luchador(src)
		if(100)
			new/obj/item/personal_shield_generator/belt/mining/loaded(src)

vorestation edit end */


/obj/structure/closet/crate/secure/loot/togglelock(mob/user)
	if(!locked)
		return

	to_chat(user, span_notice("The crate is locked with a Deca-code lock."))
	var/input = tgui_input_text(user, "Enter [codelen] digits. All digits must be unique.", "Deca-Code Lock", "", codelen)
	if(!Adjacent(user))
		return
	if(input == null)
		to_chat(user, span_notice("You leave the crate alone."))
		return
	var/list/sanitised = list()
	var/sanitycheck = 1
	for(var/i=1,i<=length(input),i++) //put the guess into a list
		sanitised += text2num(copytext(input,i,i+1))
	for(var/i=1,i<=(length(input)-1),i++) //compare each digit in the guess to all those following it
		for(var/j=(i+1),j<=length(input),j++)
			if(sanitised[i] == sanitised[j])
				sanitycheck = null //if a digit is repeated, reject the input

	if(sanitycheck == null || length(input) != codelen)
		to_chat(user, span_notice("You aren't sure this input is a good idea."))
		return

	if(check_input(input))
		to_chat(user, span_notice("The crate unlocks!"))
		playsound(src, 'sound/machines/lockreset.ogg', 50, 1)
		set_locked(0)
	else
		visible_message(span_warning("A red light on \the [src]'s control panel flashes briefly."))
		attempts--
		if (attempts == 0)
			to_chat(user, span_danger("The crate's anti-tamper system activates!"))
			var/turf/T = get_turf(src.loc)
			explosion(T, 0, 0, 1, 2)
			qdel(src)

/obj/structure/closet/crate/secure/loot/emag_act(remaining_charges, mob/user)
	if (locked)
		to_chat(user, span_notice("The crate unlocks!"))
		locked = 0

/obj/structure/closet/crate/secure/loot/proc/check_input(input)
	if(length(input) != codelen)
		return 0

	. = 1
	lastattempt.Cut()
	for(var/i in 1 to codelen)
		var/guesschar = copytext(input, i, i+1)
		lastattempt += guesschar
		if(guesschar != code[i])
			. = 0

/obj/structure/closet/crate/secure/loot/attackby(obj/item/W as obj, mob/user as mob)
	if(locked)
		if (istype(W, /obj/item/multitool)) // Greetings Urist McProfessor, how about a nice game of cows and bulls?
			to_chat(user, span_notice("DECA-CODE LOCK ANALYSIS:"))
			if (attempts == 1)
				to_chat(user, span_warning("* Anti-Tamper system will activate on the next failed access attempt."))
			else
				to_chat(user, span_notice("* Anti-Tamper system will activate after [src.attempts] failed access attempts."))
			if(lastattempt.len)
				var/bulls = 0
				var/cows = 0

				var/list/code_contents = code.Copy()
				for(var/i in 1 to codelen)
					if(lastattempt[i] == code[i])
						++bulls
					else if(lastattempt[i] in code_contents)
						++cows
					code_contents -= lastattempt[i]
				var/previousattempt = null //convert back to string for readback
				for(var/i in 1 to codelen)
					previousattempt = addtext(previousattempt, lastattempt[i])
				to_chat(user, span_notice("Last code attempt, [previousattempt], had [bulls] correct digits at correct positions and [cows] correct digits at incorrect positions."))
			return
	..()


// === merged from abandonedcrates_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/closet/crate/secure/loot
	tamper_proof = 2

/obj/structure/closet/crate/secure/loot/proc/generate_loot()
	var/lootvalue = 0
	while(lootvalue <= 10) //if the initial generation gives you less than 10 points of stuff, add more stuff
		//pick a thing to add to the crate - the format is "list(filepath, value) = weight,"
		var/choice = list()
		choice = pickweight(list(
			list(pick(/obj/item/ore/diamond,
				/obj/item/ore/osmium,
				/obj/item/ore/hydrogen,
				/obj/item/ore/verdantium,
				/obj/item/ore/uranium), 1) = 10,
			list(pick(subtypesof(/obj/item/coin)), 2) = 10,
			list(/obj/item/spacecash/c500, 4) = 5,
			list(/obj/item/spacecash/c200, 2) = 10,
			list(/obj/item/spacecash/c100, 1) = 10,
			list(/obj/item/spacecash/c50, 1) = 10,
			list(/obj/item/spacecash/c20, 1) = 10,
			list(pick(subtypesof(/obj/item/reagent_containers/food/drinks/bottle/) - /obj/item/reagent_containers/food/drinks/bottle/small), 1) = 5,
			list(/obj/item/storage/backpack/dufflebag/cratebooze,5) = 5,
			list(/obj/item/storage/backpack/dufflebag/cratedrills, 5) = 5,
			list(/obj/item/reagent_containers/glass/beaker/bluespace, 3) = 5,
			list(/obj/item/reagent_containers/glass/beaker/noreact, 3) = 5,
			list(/obj/item/melee/baton, 5) = 4,
			list(pick(subtypesof(/obj/item/storage/mre)), 2) = 3,
			list(/obj/item/seeds/random, 2) = 3,
			list(/obj/item/clothing/under/chameleon, 5) = 3,
			list(/obj/item/melee/classic_baton, 6) = 3,
			list(/obj/item/rig/industrial, 6) = 3,
			list(/obj/item/multitool/hacktool, 5) = 3,
			list(/obj/item/multitool/hacktool/modified, 4) = 4,
			list(/obj/item/toy/katana, 1) = 2,
			list(/obj/item/clothing/head/kitty, 1) = 2,
			list(pick(subtypesof(/obj/item/soap)), 1) = 2,
			list(/obj/item/clothing/under/shorts/red, 1) = 2,
			list(/obj/item/clothing/under/shorts/blue, 1) = 2,
			list(/obj/item/clothing/accessory/tie/horrible, 1) = 2,
			list(pick(subtypesof(/obj/item/stock_parts) - /obj/item/stock_parts/subspace), 2) = 3,
			list(/obj/item/latexballon, 2) = 2,
			list(/obj/item/toy/syndicateballoon, 3) = 2,
			list(/obj/item/clothing/suit/ianshirt, 3) = 2,
			list(/obj/item/clothing/head/bearpelt, 4) = 2,
			//list(/obj/item/archaeological_find, 3) = 2, // Removed, causes runtimes
			list(pick(subtypesof(/obj/item/toy/mecha)), 4) = 2,
			list(pick(subtypesof(/obj/item/toy/figure)), 4) = 2,
			list(pick(subtypesof(/obj/item/toy/plushie)), 4) = 2,
			list(pick(subtypesof(/obj/item/storage/firstaid)), 4) = 2,
			list(/obj/item/pickaxe/silver, 3) = 2,
			list(/obj/item/pickaxe/drill, 3) = 2,
			list(/obj/item/pickaxe/jackhammer, 4) = 2,
			list(/obj/item/pickaxe/gold, 4) = 2,
			list(/obj/item/pickaxe/diamond, 5) = 2,
			list(/obj/item/pickaxe/diamonddrill, 6) = 2,
			list(/obj/item/pickaxe/plasmacutter, 5) = 2,
			list(/obj/item/soulstone, 5) = 2,
			list(/obj/item/material/sword/katana, 5) = 2,
			list(/obj/item/storage/belt/utility/chief/full, 8) = 2,
			list(/obj/item/personal_shield_generator/belt/mining/loaded, 6) = 2,
			list(pick(subtypesof(/obj/item/melee/energy/sword) - /obj/item/melee/energy/sword/charge), 6) = 2,
			// Traitgenes New injector loot
			list(pick(/obj/item/dnainjector/random_good,/obj/item/dnainjector/random_good_labeled,/obj/item/dnainjector/random_labeled,/obj/item/dnainjector/random), 6) = 2,
			list(/obj/item/gun/energy/netgun, 7) = 2,
			list(pick(prob(300);/obj/item/gun/energy/mouseray,
				prob(50);/obj/item/gun/energy/mouseray/corgi,
				prob(50);/obj/item/gun/energy/mouseray/woof,
				prob(50);/obj/item/gun/energy/mouseray/cat,
				prob(50);/obj/item/gun/energy/mouseray/chicken,
				prob(50);/obj/item/gun/energy/mouseray/lizard,
				prob(50);/obj/item/gun/energy/mouseray/rabbit,
				prob(50);/obj/item/gun/energy/mouseray/fennec,
				prob(5);/obj/item/gun/energy/mouseray/monkey,
				prob(5);/obj/item/gun/energy/mouseray/wolpin,
				prob(5);/obj/item/gun/energy/mouseray/otie,
				prob(5);/obj/item/gun/energy/mouseray/direwolf,
				prob(5);/obj/item/gun/energy/mouseray/giantrat,
				prob(50);/obj/item/gun/energy/mouseray/redpanda,
				prob(5);/obj/item/gun/energy/mouseray/catslug,
				prob(5);/obj/item/gun/energy/mouseray/teppi,
				prob(1);/obj/item/gun/energy/mouseray/metamorphosis,
				prob(1);/obj/item/gun/energy/mouseray/metamorphosis/advanced/random
				), 8) = 2,
			list(/obj/item/gun/energy/pummeler, 11) = 2,
			list(pick(subtypesof(/obj/item/reagent_containers/food/drinks/glass2/coffeemug)), 1) = 1,
			list(/obj/item/xenos_claw, 1) = 1,
			list(/obj/item/organ/internal/heart, 1) = 1,
			list(/obj/item/vampiric, 2) = 1,
			list(/obj/item/weed_extract, 2) = 1,
			list(/obj/item/storage/backpack/luchador/loaded, 3) = 1,
			list(/obj/item/storage/backpack/clown/loaded, 5) = 1,
			list(/obj/item/storage/backpack/mime/loaded, 5) = 1,
			list(pick(/obj/item/multitool/alien,
				/obj/item/stack/cable_coil/alien,
				/obj/item/tool/crowbar/alien,
				/obj/item/tool/screwdriver/alien,
				/obj/item/weldingtool/alien,
				/obj/item/tool/wirecutters/alien,
				/obj/item/tool/wrench/alien), 7) = 1,
			list(pick(/obj/item/melee/energy/axe, /obj/item/melee/energy/spear), 11) = 1,
			list(/obj/item/card/emag/used, 7) = 1,
			list(pick(/obj/item/grenade/spawnergrenade/spesscarp, /obj/item/grenade/spawnergrenade/spider, /obj/item/grenade/explosive/frag), 7) = 1,
			list(/obj/item/grenade/flashbang/clusterbang, 7) = 1,
			list(/obj/item/card/emag, 11) = 1,
			list(/obj/item/melee/shock_maul, 11) = 3,
			list(/obj/item/clothing/suit/storage/vest/martian_miner/reinforced, 4) = 6,
			list(/obj/item/storage/backpack/sport/hyd/catchemall, 11) = 1,
			list(/obj/item/prop/alien/junk, 12) = 1,
			))
		var/path = choice[1]
		var/value = choice[2]
		contents += new path()
		lootvalue += value

//putting the multi-object loot items as their own things

/obj/item/storage/backpack/dufflebag/cratebooze
	starts_with = list(
		/obj/item/reagent_containers/food/drinks/bottle/rum,
		/obj/item/reagent_containers/food/drinks/bottle/whiskey,
		/obj/item/reagent_containers/food/snacks/grown/ambrosiadeus,
		/obj/item/reagent_containers/food/snacks/grown/ambrosiadeus,
		/obj/item/reagent_containers/food/snacks/grown/ambrosiadeus,
		)

/obj/item/storage/backpack/dufflebag/cratedrills
	starts_with = list(
		/obj/item/pickaxe/advdrill,
		/obj/item/taperecorder,
		/obj/item/clothing/suit/space,
		/obj/item/clothing/head/helmet/space
		)

/obj/item/storage/backpack/clown/loaded
	starts_with = list(
		/obj/item/clothing/under/rank/clown,
		/obj/item/clothing/shoes/clown_shoes,
		/obj/item/pda/clown,
		/obj/item/clothing/mask/gas/clown_hat,
		/obj/item/bikehorn,
		/obj/item/pen/crayon/rainbow,
		/obj/item/reagent_containers/spray/waterflower
	)

/obj/item/storage/backpack/mime/loaded
	starts_with = list(
		/obj/item/clothing/under/mime,
		/obj/item/clothing/shoes/black,
		/obj/item/pda/mime,
		/obj/item/clothing/gloves/white,
		/obj/item/clothing/mask/gas/mime,
		/obj/item/clothing/head/beret,
		/obj/item/clothing/suit/suspenders,
		/obj/item/pen/crayon/mime,
		/obj/item/reagent_containers/food/drinks/bottle/bottleofnothing
	)

/obj/item/storage/backpack/luchador/loaded
	starts_with = list(
		/obj/item/storage/belt/champion,
		/obj/item/clothing/mask/luchador
	)


/obj/item/storage/backpack/sport/hyd/catchemall
	name = "sports backpack"
	desc = "A green sports backpack."
	starts_with = list(
		/obj/item/clothing/head/soft/red,
		/obj/item/clothing/suit/varsity/blue,
		/obj/item/clothing/under/pants/youngfolksjeans,
		/obj/item/capture_crystal
	)

/obj/item/storage/backpack/sport/hyd/catchemall/Initialize(mapload) //gotta have your starter 'mon too (or an improved way to catch one)
	. = ..()
	var/path = pick(subtypesof(/obj/item/capture_crystal))
	contents += new path()
