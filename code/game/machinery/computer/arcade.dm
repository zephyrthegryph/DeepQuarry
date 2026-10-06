/obj/machinery/computer/arcade
	name = "random arcade"
	desc = "random arcade machine"
	icon_state = "arcade1"
	icon_keyboard = null
	clicksound = null	//Gets too spammy and makes no sense for arcade to have the console keyboard noise anyway
	var/list/prizes = list(	/obj/item/storage/box/snappops					= 2, // ALLOW(instance_list): d: edited in place per instance (1 writers)
							/obj/item/toy/blink										= 2,
							/obj/item/clothing/under/syndicate/tacticool			= 2,
							/obj/item/toy/sword										= 2,
							/obj/item/storage/box/capguntoy					= 2,
							/obj/item/gun/projectile/revolver/toy/crossbow	= 2,
							/obj/item/clothing/suit/syndicatefake					= 2,
							/obj/item/storage/fancy/crayons					= 2,
							/obj/item/toy/spinningtoy								= 2,
							/obj/random/mech_toy									= 1,
							/obj/item/reagent_containers/spray/waterflower	= 1,
							/obj/random/action_figure								= 1,
							/obj/random/plushie										= 1,
							/obj/item/toy/cultsword									= 1,
							/obj/item/toy/bouquet/fake								= 1,
							/obj/item/clothing/accessory/badge/sheriff				= 2,
							/obj/item/clothing/head/cowboy/small				= 2,
							/obj/item/toy/stickhorse								= 2
							)
	var/list/special_prizes // Holds instanced objects, intended for admins to shove surprises inside or something.

CAPABILITIES(/obj/machinery/computer/arcade)
	rolls(nameof(rolled_board), PROC_REF(roll_board), when = cond_not(nameof(circuit)))
	after_init(0, then(PROC_REF(become_rolled_board)))
	op("redeem_tickets", item(/obj/item/stack/arcadeticket), priority(OP_PRIORITY_DEFAULT - 1), label("Redeem tickets"), needs(req(PROC_REF(can_redeem_tickets_holds), because = PROC_REF(can_redeem_tickets_refusal))), then(PROC_REF(interaction_redeem_tickets)))

/// A generic cabinet (no circuit) rolls which arcade it is, then becomes that machine once its init is over.
/obj/machinery/computer/arcade/var/rolled_board

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): any arcade board but the claw machine's.
/obj/machinery/computer/arcade/proc/roll_board(datum/roller/R)
	return R.choose(subtypesof(/obj/item/circuitboard/arcade) - /obj/item/circuitboard/arcade/clawmachine)

/obj/machinery/computer/arcade/proc/become_rolled_board(datum/act/A)
	if(!rolled_board || circuit)
		return
	var/obj/item/circuitboard/CB = new rolled_board()
	replace_with(src, CB.build_path, CB)

/obj/machinery/computer/arcade/proc/prizevend(mob/user)
	OM_EMIT(src, /datum/om/event/arcade_prizevend, user)

	if(LAZYLEN(special_prizes)) // Downstream wanted the 'win things inside contents sans circuitboard' feature kept.
		var/atom/movable/AM = pick_n_take(special_prizes)
		AM.forceMove(get_turf(src))
		LAZYREMOVE(special_prizes, AM)

	else if(LAZYLEN(prizes))
		var/prizeselect = pickweight(prizes)
		// /obj/random typepaths spawn their random item and self-delete on Initialize,
		// so creating one at src.loc yields the loot directly.
		new prizeselect(src.loc)

		if(istype(prizeselect, /obj/item/clothing/suit/syndicatefake)) //Helmet is part of the suit
			new	/obj/item/clothing/head/syndicatefake(src.loc)

/// Requirement: a prize costs two tickets.
/obj/machinery/computer/arcade/proc/can_redeem_tickets(mob/user, atom/target, obj/item/stack/arcadeticket/T)
	if(istype(T) && T.get_amount() < ARCADE_TICKETS_PER_PRIZE)
		return "you need [ARCADE_TICKETS_PER_PRIZE] tickets to claim a prize"
	return TRUE

/// Requirement (was REQ_* can_redeem_tickets): the legacy check answers TRUE to pass.
/obj/machinery/computer/arcade/proc/can_redeem_tickets_holds(datum/act/op/A)
	var/answer = can_redeem_tickets(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_redeem_tickets_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/arcade/proc/can_redeem_tickets_refusal(datum/act/op/A)
	var/answer = can_redeem_tickets(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/computer/arcade/proc/interaction_redeem_tickets(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/arcadeticket/T = A.held
	prizevend(user)
	T.pay_tickets()
	to_chat(user, span_notice("You turn in 2 tickets to the [src] and claim a prize!"))
	return TRUE

DAMAGE_REACTION(/obj/machinery/computer/arcade, DAMAGE_EMP, PROC_REF(arcade_emp))
/// An EMP makes a working arcade machine spit out prizes.
/obj/machinery/computer/arcade/proc/arcade_emp(datum/damage_packet/packet)
	if(!operable())
		return
	var/empprize = null
	var/num_of_prizes = 0
	switch(packet.severity)
		if(1)
			num_of_prizes = rand(1,4)
		if(2)
			num_of_prizes = rand(1,3)
		if(3)
			num_of_prizes = rand(0,2)
		if(4)
			num_of_prizes = rand(0,1)
	for(num_of_prizes; num_of_prizes > 0; num_of_prizes--)
		empprize = pickweight(prizes)
		new empprize(src.loc)

///////////////////
//  BATTLE HERE  //
///////////////////

/obj/machinery/computer/arcade/battle
	name = "Battler"
	desc = "Fight through what space has to offer!"
	icon_state = "arcade2"
	icon_screen = "battler"
	circuit = /obj/item/circuitboard/arcade/battle
	var/enemy_name = "Space Villian"
	var/temp = "Winners don't use space drugs" //Temporary message, for attack messages, etc
	var/enemy_action = ""
	var/player_hp = 30 //Player health/attack points
	var/player_mp = 10
	var/enemy_hp = 45 //Enemy health/attack points
	var/enemy_mp = 20
	var/gameover = 0
	var/blocked = 0 //Player cannot attack/heal while set
	var/turtle = 0

// ALLOW(init/INSTANCE_STATE): rolls its arcade characters per machine
/obj/machinery/computer/arcade/battle/Initialize(mapload)
	. = ..()
	randomize_characters()

/obj/machinery/computer/arcade/battle/proc/randomize_characters()
	var/name_action
	var/name_part1
	var/name_part2

	name_action = pick("Defeat ", "Annihilate ", "Save ", "Strike ", "Stop ", "Destroy ", "Robust ", "Romance ", "Pwn ", "Own ", "Ban ")

	name_part1 = pick("the Automatic ", "Farmer ", "Lord ", "Professor ", "the Cuban ", "the Evil ", "the Dread King ", "the Space ", "Lord ", "the Great ", "Duke ", "General ")
	name_part2 = pick("Melonoid", "Murdertron", "Sorcerer", "Ruin", "Jeff", "Ectoplasm", "Crushulon", "Uhangoid", "Vhakoid", "Peteoid", "slime", "Griefer", "ERPer", "Lizard Man", "Unicorn", "Bloopers")

	enemy_name = replacetext((name_part1 + name_part2), "the ", "")
	name = (name_action + name_part1 + name_part2)

EXTEND_INTERACTIONS(/obj/machinery/computer/arcade/battle, \
)

CAPABILITIES(/obj/machinery/computer/arcade/battle)
	interface("ArcadeBattle")
	op("newgame", ui_act("newgame"), then(PROC_REF(ui_act_newgame)))
	op("attack", ui_act("attack"), then(PROC_REF(ui_act_attack)))
	op(XENO_CHEM_HEAL, ui_act(XENO_CHEM_HEAL), then(PROC_REF(ui_act_heal)))
	op("charge", ui_act("charge"), then(PROC_REF(ui_act_charge)))

/obj/machinery/computer/arcade/battle/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["name"] = name
	data["temp"] = temp
	data["enemyAction"] = enemy_action
	data["enemyName"] = enemy_name
	data["playerHP"] = player_hp
	data["playerMP"] = player_mp
	data["enemyHP"] = enemy_hp
	data["gameOver"] = gameover
	return data

/// The player's moves: each is blocked until the last has landed and refused once the game is over.
/obj/machinery/computer/arcade/battle/proc/ui_act_attack(datum/act/op/A)
	if(blocked || gameover)
		return OP_OK
	blocked = 1
	var/attackamt = rand(2,6)
	temp = "You attack for [attackamt] damage!"
	play_sfx(src, SFX_ARCADE_HIT, ignore_walls = FALSE)
	if(turtle > 0)
		turtle--
	after(src, 1 SECOND, PROC_REF(battle_resolve), with = list(A.actor, attackamt, 0, 0))
	return OP_OK

/obj/machinery/computer/arcade/battle/proc/ui_act_heal(datum/act/op/A)
	if(blocked || gameover)
		return OP_OK
	blocked = 1
	var/pointamt = rand(1,3)
	var/healamt = rand(6,8)
	temp = "You use [pointamt] magic to heal for [healamt] damage!"
	play_sfx(src, SFX_ARCADE_HEAL, ignore_walls = FALSE)
	turtle++
	after(src, 1 SECOND, PROC_REF(battle_resolve), with = list(A.actor, 0, pointamt, healamt))
	return OP_OK

/obj/machinery/computer/arcade/battle/proc/ui_act_charge(datum/act/op/A)
	if(blocked || gameover)
		return OP_OK
	blocked = 1
	var/chargeamt = rand(4,7)
	temp = "You regain [chargeamt] points"
	play_sfx(src, SFX_ARCADE_MANA, ignore_walls = FALSE)
	player_mp += chargeamt
	if(turtle > 0)
		turtle--
	after(src, 1 SECOND, PROC_REF(battle_resolve), with = list(A.actor, 0, 0, 0))
	return OP_OK

/obj/machinery/computer/arcade/battle/proc/ui_act_newgame(datum/act/op/A)
	temp = "New Round"
	player_hp = 30
	player_mp = 10
	enemy_hp = 45
	enemy_mp = 20
	gameover = 0
	turtle = 0

	if(emagged)
		randomize_characters()
		set_emagged(0)
	add_fingerprint(A.actor)
	return TRUE

/// The player's move lands a second after it was chosen, then the enemy acts.
/obj/machinery/computer/arcade/battle/proc/battle_resolve(mob/user, enemy_damage, mp_cost, heal)
	enemy_hp -= enemy_damage
	player_mp -= mp_cost
	player_hp += heal
	arcade_action(user)

/obj/machinery/computer/arcade/battle/proc/arcade_action(mob/user)
	if ((enemy_mp <= 0) || (enemy_hp <= 0))
		if(!gameover)
			gameover = 1
			temp = "[enemy_name] has fallen! Rejoice!"
			play_sfx(src, SFX_ARCADE_WIN, ignore_walls = FALSE)

			if(emagged)
				feedback_inc("arcade_win_emagged")
				new /obj/effect/spawner/newbomb/timer/syndicate(src.loc)
				new /obj/item/clothing/head/collectable/petehat(src.loc)
				message_admins("[key_name_admin(user)] has outbombed Cuban Pete and been awarded a bomb.")
				log_game("[key_name_admin(user)] has outbombed Cuban Pete and been awarded a bomb.")
				randomize_characters()
				set_emagged(0)
			else if(!contents_count(src) && !has_latent()) // ALLOW(latent): latent entries checked
				feedback_inc("arcade_win_normal")
				prizevend(user)

			else
				feedback_inc("arcade_win_normal")
				prizevend(user)

	else if (emagged && (turtle >= 4))
		var/boomamt = rand(5,10)
		enemy_action = "[enemy_name] throws a bomb, exploding you for [boomamt] damage!"
		play_sfx(src, SFX_ARCADE_BOOM, ignore_walls = FALSE)
		player_hp -= boomamt

	else if ((enemy_mp <= 5) && (prob(70)))
		var/stealamt = rand(2,3)
		enemy_action = "[enemy_name] steals [stealamt] of your power!"
		play_sfx(src, SFX_ARCADE_STEAL, ignore_walls = FALSE)
		player_mp -= stealamt

		if (player_mp <= 0)
			gameover = 1
			temp = "You have been drained! GAME OVER"
			if(emagged)
				feedback_inc("arcade_loss_mana_emagged")
				user.gib()
			else
				feedback_inc("arcade_loss_mana_normal")

	else if ((enemy_hp <= 10) && (enemy_mp > 4))
		enemy_action = "[enemy_name] heals for 4 health!"
		play_sfx(src, SFX_ARCADE_HEAL, ignore_walls = FALSE)
		enemy_hp += 4
		enemy_mp -= 4

	else
		var/attackamt = rand(3,6)
		enemy_action = "[enemy_name] attacks for [attackamt] damage!"
		play_sfx(src, SFX_ARCADE_HIT, ignore_walls = FALSE)
		player_hp -= attackamt

	if ((player_mp <= 0) || (player_hp <= 0))
		gameover = 1
		temp = "You have been crushed! GAME OVER"
		play_sfx(src, SFX_ARCADE_LOSE, ignore_walls = FALSE)
		if(emagged)
			feedback_inc("arcade_loss_hp_emagged")
			user.gib()
		else
			feedback_inc("arcade_loss_hp_normal")

	blocked = 0
	return


DECLARE_EMAG(/obj/machinery/computer/arcade/battle, PROC_REF(on_emag), null, null)
/obj/machinery/computer/arcade/battle/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	to_chat(user, span_notice("You override the cheat code menu and skip to Cheat #[rand(1, 50)]: Hyper-Lethal Mode."))

	temp = "If you die in the game, you die for real!"
	player_hp = 30
	player_mp = 10
	enemy_hp = 45
	enemy_mp = 20
	gameover = 0
	blocked = 0
	set_emagged(1)

	enemy_name = "Cuban Pete"
	name = "Outbomb Cuban Pete"

	return 1

//////////////////////////
//   ORION TRAIL HERE   //
//////////////////////////
#define ORION_TRAIL_WINTURN		9

//Orion Trail Events
#define ORION_TRAIL_RAIDERS		"Raiders"
#define ORION_TRAIL_FLUX		"Interstellar Flux"
#define ORION_TRAIL_ILLNESS		"Illness"
#define ORION_TRAIL_BREAKDOWN	"Breakdown"
#define ORION_TRAIL_MUTINY		"Mutiny?"
#define ORION_TRAIL_MUTINY_ATTACK "Mutinous Ambush"
#define ORION_TRAIL_MALFUNCTION	"Malfunction"
#define ORION_TRAIL_COLLISION	"Collision"
#define ORION_TRAIL_SPACEPORT	"Spaceport"
#define ORION_TRAIL_BLACKHOLE	"BlackHole"

#define ORION_STATUS_START		1
#define ORION_STATUS_NORMAL		2
#define ORION_STATUS_GAMEOVER	3
#define ORION_STATUS_MARKET		4

/obj/machinery/computer/arcade/orion_trail
	name = "The Orion Trail"
	desc = "Learn how our ancestors got to Orion, and have fun in the process!"
	icon_state = "arcade1"
	icon_screen = "orion"
	circuit = /obj/item/circuitboard/arcade/orion_trail
	var/engine = 0
	var/hull = 0
	var/electronics = 0
	var/food = 80
	var/fuel = 60
	var/turns = 4
	var/alive = 4
	var/eventdat = null
	var/event = null
	var/list/settlers = list("Harry","Larry","Bob") // ALLOW(instance_list): d: edited in place per instance (5 writers)
	var/list/events = list(ORION_TRAIL_RAIDERS		= 3, // ALLOW(instance_list): d: edited in place per instance (1 writers)
						   ORION_TRAIL_FLUX			= 1,
						   ORION_TRAIL_ILLNESS		= 3,
						   ORION_TRAIL_BREAKDOWN	= 2,
						   ORION_TRAIL_MUTINY		= 3,
						   ORION_TRAIL_MALFUNCTION	= 2,
						   ORION_TRAIL_COLLISION	= 1,
						   ORION_TRAIL_SPACEPORT	= 2
						   )
	var/list/stops
	var/list/stopblurbs
	var/traitors_aboard = 0
	var/spaceport_raided = 0
	var/spaceport_freebie = 0
	var/last_spaceport_action = ""
	var/gameStatus = ORION_STATUS_START
	var/canContinueEvent = 0

/obj/machinery/computer/arcade/orion_trail/Initialize(mapload)
	. = ..()
	// Sets up the main trail
	stops = list("Pluto","Asteroid Belt","Proxima Centauri","Dead Space","Rigel Prime","Tau Ceti Beta","Black Hole","Space Outpost Beta-9","Orion Prime")
	stopblurbs = list(
		"Pluto, long since occupied with long-range sensors and scanners, stands ready to, and indeed continues to probe the far reaches of the galaxy.",
		"At the edge of the Sol system lies a treacherous asteroid belt. Many have been crushed by stray asteroids and misguided judgement.",
		"The nearest star system to Sol, in ages past it stood as a reminder of the boundaries of sub-light travel, now a low-population sanctuary for adventurers and traders.",
		"This region of space is particularly devoid of matter. Such low-density pockets are known to exist, but the vastness of it is astounding.",
		"Rigel Prime, the center of the Rigel system, burns hot, basking its planetary bodies in warmth and radiation.",
		"Tau Ceti Beta has recently become a waypoint for colonists headed towards Orion. There are many ships and makeshift stations in the vicinity.",
		"Sensors indicate that a black hole's gravitational field is affecting the region of space we were headed through. We could stay of course, but risk of being overcome by its gravity, or we could change course to go around, which will take longer.",
		"You have come into range of the first man-made structure in this region of space. It has been constructed not by travellers from Sol, but by colonists from Orion. It stands as a monument to the colonists' success.",
		"You have made it to Orion! Congratulations! Your crew is one of the few to start a new foothold for mankind!"
		)

/obj/machinery/computer/arcade/orion_trail/proc/newgame(mob/user)
	// Set names of settlers in crew
	settlers = list()
	for(var/i = 1; i <= 3; i++)
		add_crewmember()
	add_crewmember("[user]")
	// Re-set items to defaults
	engine = 1
	hull = 1
	electronics = 1
	food = 80
	fuel = 60
	alive = 4
	turns = 1
	event = null
	gameStatus = ORION_STATUS_NORMAL
	traitors_aboard = 0

	//spaceport junk
	spaceport_raided = 0
	spaceport_freebie = 0
	last_spaceport_action = ""

// structured TGUI Orion Trail panel; the attack_hand override
// lives in code/modules/admin/orion_trail_panel.dm and
// re-runs the upstream game-over side effects before opening the panel.

/obj/machinery/computer/arcade/orion_trail/proc/malfunction_restore(oldfood, oldfuel)
	if(oldfuel > fuel && oldfood > food)
		src.audible_message("\The [src] lets out a somehow reassuring chime.", runemessage = "reassuring chime")
	else if(oldfuel < fuel || oldfood < food)
		src.audible_message("\The [src] lets out a somehow ominous chime.", runemessage = "ominous chime")
	food = oldfood
	fuel = oldfuel

/// The emagged black hole pulls at the player four times, a second apart.
/obj/machinery/computer/arcade/orion_trail/proc/blackhole_hurt(mob/living/L, hits)
	if(!hits)
		to_chat(L, span_danger("This is really starting to hurt!"))
	if(istype(L))
		L.injure(INJURY_BLUNT, 25, null, src)
	if(hits < 3)
		after(src, 1 SECOND, PROC_REF(blackhole_hurt), with = list(L, hits + 1))

// Event screens embed href links (event()); the tgui buttons call the orion_* procs directly.
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "close", PROC_REF(orion_close))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "slow", PROC_REF(orion_slow))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "useengine", PROC_REF(orion_useengine))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "useelec", PROC_REF(orion_useelec))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "usehull", PROC_REF(orion_usehull))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "wait", PROC_REF(orion_wait))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "keepspeed", PROC_REF(orion_keepspeed))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "holedeath", PROC_REF(orion_holedeath))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "eventclose", PROC_REF(orion_eventclose))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "killcrew", PROC_REF(orion_killcrew))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "buycrew", PROC_REF(orion_buycrew))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "sellcrew", PROC_REF(orion_sellcrew))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "leave_spaceport", PROC_REF(orion_leave_spaceport))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "raid_spaceport", PROC_REF(orion_raid_spaceport))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "buyparts", PROC_REF(orion_buyparts), TOPIC_NUM("buyparts"))
TOPIC_ACTION(/obj/machinery/computer/arcade/orion_trail, "trade", PROC_REF(orion_trade), TOPIC_NUM("trade"))

/// Work done after every game action.
/obj/machinery/computer/arcade/orion_trail/proc/orion_refresh(mob/user)
	add_fingerprint(user)
	updateUsrDialog(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_close(mob/user, list/args)
	user.unset_machine()
	// close the TGUI panel instead of a browse() window.
	SStgui.close_uis(src)
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_continue(mob/user, list/args)
	if(gameStatus == ORION_STATUS_NORMAL && !event && turns != 7)
		if(turns >= ORION_TRAIL_WINTURN)
			win(user)
		else
			food -= (alive+traitors_aboard)*2
			fuel -= 5
			if(turns == 2 && prob(30))
				event = ORION_TRAIL_COLLISION
				event()
			else if(prob(75))
				event = pickweight(events)
				if(traitors_aboard)
					if(event == ORION_TRAIL_MUTINY || prob(55))
						event = ORION_TRAIL_MUTINY_ATTACK
				event()
			turns += 1
		if(emagged)
			var/mob/living/carbon/M = user //for some vars
			switch(event)
				if(ORION_TRAIL_RAIDERS)
					if(prob(50))
						to_chat(user, span_warning("You hear battle shouts. The tramping of boots on cold metal. Screams of agony. The rush of venting air. Are you going insane?"))
						M.status_adjust(STAT_HALLUCINATING, 30)
					else
						to_chat(user, span_danger("Something strikes you from behind! It hurts like hell and feel like a blunt weapon, but nothing is there..."))
						M.injure(INJURY_BLUNT, 25, null, src)
				if(ORION_TRAIL_ILLNESS)
					var/severity = rand(1,3) //pray to RNGesus. PRAY, PIGS
					if(severity == 1)
						to_chat(M, span_warning("You suddenly feel slightly nauseous.")) //got off lucky
					if(severity == 2)
						to_chat(user, span_warning("You suddenly feel extremely nauseous and hunch over until it passes."))
						M.status_at_least(STAT_STUNNED, 3)
					if(severity >= 3) //you didn't pray hard enough
						to_chat(M, span_warning("An overpowering wave of nausea consumes over you. You hunch over, your stomach's contents preparing for a spectacular exit."))
						if(ishuman(M))
							after(M, 3 SECONDS, TYPE_PROC_REF(/mob/living/carbon/human, vomit))
				if(ORION_TRAIL_FLUX)
					if(prob(75))
						M.status_at_least(STAT_WEAKENED, 3)
						src.visible_message("A sudden gust of powerful wind slams \the [M] into the floor!", "You hear a large fwooshing sound, followed by a bang.")
						M.injure(INJURY_BLUNT, 15, null, src)
					else
						to_chat(M, span_warning("A violent gale blows past you, and you barely manage to stay standing!"))
				if(ORION_TRAIL_COLLISION) //by far the most damaging event
					if(prob(90) && !hull)
						var/turf/simulated/floor/F = src.loc
						F.ChangeTurf(/turf/space)
						src.visible_message(span_danger("Something slams into the floor around \the [src], exposing it to space!"), "You hear something crack and break.")
					else
						src.visible_message("Something slams into the floor around \the [src] - luckily, it didn't get through!", "You hear something crack.")
				if(ORION_TRAIL_MALFUNCTION)
					src.visible_message("\The [src] buzzes and the screen goes blank for a moment before returning to the game.")
					var/oldfood = food
					var/oldfuel = fuel
					food = rand(10,80) / rand(1,2)
					fuel = rand(10,60) / rand(1,2)
					if(electronics)
						after(src, 1 SECOND, PROC_REF(malfunction_restore), with = list(oldfood, oldfuel))
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_newgame(mob/user, list/args)
	if(gameStatus == ORION_STATUS_START)
		play_sfx(src, SFX_ARCADE_ORI_BEGIN, ignore_walls = FALSE)
		newgame(user)
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_menu(mob/user, list/args)
	if(gameStatus == ORION_STATUS_GAMEOVER)
		gameStatus = ORION_STATUS_START
		event = null
		food = 80
		fuel = 60
		settlers = list("Harry","Larry","Bob")
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_slow(mob/user, list/args)
	if(event == ORION_TRAIL_FLUX)
		food -= (alive+traitors_aboard)*2
		fuel -= 5
	event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_pastblack(mob/user, list/args)
	if(turns == 7)
		food -= ((alive+traitors_aboard)*2)*3
		fuel -= 15
		turns += 1
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_useengine(mob/user, list/args)
	if(event == ORION_TRAIL_BREAKDOWN)
		engine = max(0, --engine)
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_useelec(mob/user, list/args)
	if(event == ORION_TRAIL_MALFUNCTION)
		electronics = max(0, --electronics)
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_usehull(mob/user, list/args)
	if(event == ORION_TRAIL_COLLISION)
		hull = max(0, --hull)
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_wait(mob/user, list/args)
	if(event == ORION_TRAIL_BREAKDOWN || event == ORION_TRAIL_MALFUNCTION || event == ORION_TRAIL_COLLISION)
		food -= ((alive+traitors_aboard)*2)*3
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_keepspeed(mob/user, list/args)
	if(event == ORION_TRAIL_FLUX)
		if(prob(75))
			event = "Breakdown"
			event()
		else
			event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_blackhole(mob/user, list/args)
	if(turns == 7)
		if(prob(75))
			event = ORION_TRAIL_BLACKHOLE
			event()
			if(emagged) //has to be here because otherwise it doesn't work
				src.show_message("\The [src] states, 'YOU ARE EXPERIENCING A BLACKHOLE. BE TERRIFIED.","You hear something say, 'YOU ARE EXPERIENCING A BLACKHOLE. BE TERRFIED'")
				to_chat(user, span_warning("Something draws you closer and closer to the machine."))
				//spawning a literal blackhole would be fun, but a bit disruptive.
				after(src, 1 SECOND, PROC_REF(blackhole_hurt), with = list(user, 0))
		else
			event = null
			turns += 1
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_holedeath(mob/user, list/args)
	if(event == ORION_TRAIL_BLACKHOLE)
		gameStatus = ORION_STATUS_GAMEOVER
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_eventclose(mob/user, list/args)
	if(canContinueEvent)
		event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_killcrew(mob/user, list/args)
	if(gameStatus == ORION_STATUS_NORMAL || event == ORION_TRAIL_MUTINY)
		play_sfx(src, SFX_ARCADE_KILL_CREW, ignore_walls = FALSE)
		var/sheriff = remove_crewmember() //I shot the sheriff
		var/mob/living/L = user
		if(!istype(L))
			return
		if(settlers.len == 0 || alive == 0)
			src.visible_message("\The [src] states, 'EVERYONE HAS DIED, GAMEOVER.'", "You hear something state, 'EVERYONE HAS DIED, GAMEOVER.'")
			if(emagged)
				src.visible_message("\The [src] produces a loud, gunlike sound.")
				L.injure(INJURY_PIERCE, 30, null, src)
				set_emagged(0)
			gameStatus = ORION_STATUS_GAMEOVER
			event = null
		else if(emagged)
			if(user.name == sheriff)
				act_message(src, user, others = "%U% states, 'THE CREW HAS CHOSEN TO KILL %T%'. A gunshot can be heard coming from %U%", \
					blind = "You hear 'THE CREW HAS CHOSEN TO KILL %T%' followed by a gunshot")
				L.injure(INJURY_PIERCE, 30, null, src)
		if(event == ORION_TRAIL_MUTINY) //only ends the ORION_TRAIL_MUTINY event, since you can do this action in multiple places
			event = null
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_buycrew(mob/user, list/args)
	if(gameStatus == ORION_STATUS_MARKET)
		if(!spaceport_raided && food >= 10 && fuel >= 10)
			play_sfx(src, SFX_ARCADE_GET_FUEL, ignore_walls = FALSE)
			var/bought = add_crewmember()
			last_spaceport_action = "You hired [bought] as a new crewmember."
			fuel -= 10
			food -= 10
			event()
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_sellcrew(mob/user, list/args)
	if(gameStatus == ORION_STATUS_MARKET)
		if(!spaceport_raided && settlers.len > 1)
			play_sfx(src, SFX_ARCADE_LOSE_FUEL, ignore_walls = FALSE)
			var/sold = remove_crewmember()
			last_spaceport_action = "You sold your crewmember, [sold]!"
			fuel += 7
			food += 7
			event()
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_leave_spaceport(mob/user, list/args)
	if(gameStatus == ORION_STATUS_MARKET)
		event = null
		gameStatus = ORION_STATUS_NORMAL
		spaceport_raided = 0
		spaceport_freebie = 0
		last_spaceport_action = ""
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_raid_spaceport(mob/user, list/args)
	if(gameStatus == ORION_STATUS_MARKET)
		if(!spaceport_raided)
			play_sfx(src, SFX_ARCADE_RAID, ignore_walls = FALSE)
			var/success = min(15 * alive,100) //default crew (4) have a 60% chance
			spaceport_raided = 1

			var/FU = 0
			var/FO = 0
			if(prob(success))
				FU = rand(5,15)
				FO = rand(5,15)
				last_spaceport_action = "You successfully raided the spaceport! You gained [FU] Fuel and [FO] Food! (+[FU]FU,+[FO]FO)"
			else
				FU = rand(-5,-15)
				FO = rand(-5,-15)
				last_spaceport_action = "You failed to raid the spaceport! You lost [FU*-1] Fuel and [FO*-1] Food in your scramble to escape! ([FU]FU,[FO]FO)"

				//your chance of lose a crewmember is 1/2 your chance of success
				//this makes higher % failures hurt more, don't get cocky space cowboy!
				if(prob(success*5))
					var/lost_crew = remove_crewmember()
					last_spaceport_action = "You failed to raid the spaceport! You lost [FU*-1] Fuel and [FO*-1] Food, AND [lost_crew] in your scramble to escape! ([FU]FI,[FO]FO,-Crew)"
					if(emagged)
						act_message(user, src, others = "The machine states, 'YOU ARE UNDER ARREST, RAIDER!' and shoots handcuffs onto %U%!", \
							blind = "You hear something say 'YOU ARE UNDER ARREST, RAIDER!' and a clinking sound")
						var/obj/item/handcuffs/C = new(src.loc)
						var/mob/living/carbon/human/H = user
						if(istype(H))
							H.equip_to_slot(C, SLOT_ID_HANDCUFFED)
						else
							C.throw_at(user,16,3,src)


			fuel += FU
			food += FO
			event()
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_buyparts(mob/user, list/args)
	if(gameStatus == ORION_STATUS_MARKET)
		if(!spaceport_raided && fuel > 5)
			play_sfx(src, SFX_ARCADE_GET_FUEL, ignore_walls = FALSE)
			switch(args["buyparts"])
				if(1) //Engine Parts
					engine++
					last_spaceport_action = "Bought Engine Parts"
				if(2) //Hull Plates
					hull++
					last_spaceport_action = "Bought Hull Plates"
				if(3) //Spare Electronics
					electronics++
					last_spaceport_action = "Bought Spare Electronics"
			fuel -= 5 //they all cost 5
			event()
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/orion_trade(mob/user, list/args)
	if(gameStatus == ORION_STATUS_MARKET)
		if(!spaceport_raided)
			play_sfx(src, SFX_ARCADE_GET_FUEL, ignore_walls = FALSE)
			switch(args["trade"])
				if(1) //Fuel
					if(fuel > 5)
						fuel -= 5
						food += 5
						last_spaceport_action = "Traded Fuel for Food"
						event()
				if(2) //Food
					if(food > 5)
						fuel += 5
						food -= 5
						last_spaceport_action = "Traded Food for Fuel"
						event()
	orion_refresh(user)

/obj/machinery/computer/arcade/orion_trail/proc/event()
	eventdat = "<center><h1>[event]</h1></center>"
	canContinueEvent = 0
	switch(event)
		if(ORION_TRAIL_RAIDERS)
			eventdat += "Raiders have come aboard your ship!"
			if(prob(50))
				var/sfood = rand(1,10)
				var/sfuel = rand(1,10)
				food -= sfood
				fuel -= sfuel
				eventdat += "<br>They have stolen [sfood] <b>Food</b> and [sfuel] <b>Fuel</b>."
			else if(prob(10))
				var/deadname = remove_crewmember()
				eventdat += "<br>[deadname] tried to fight back, but was killed."
			else
				eventdat += "<br>Fortunately, you fended them off without any trouble."
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];eventclose=1'>Continue</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
			canContinueEvent = 1

		if(ORION_TRAIL_FLUX)
			play_sfx(src, SFX_ARCADE_EXPLO, ignore_walls = FALSE)
			eventdat += "This region of space is highly turbulent. <br>If we go slowly we may avoid more damage, but if we keep our speed we won't waste supplies."
			eventdat += "<br>What will you do?"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];slow=1'>Slow Down</a> <a href='byond://?src=\ref[src];keepspeed=1'>Continue</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"

		if(ORION_TRAIL_ILLNESS)
			eventdat += "A deadly illness has been contracted!"
			var/deadname = remove_crewmember()
			eventdat += "<br>[deadname] was killed by the disease."
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];eventclose=1'>Continue</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
			canContinueEvent = 1

		if(ORION_TRAIL_BREAKDOWN)
			play_sfx(src, SFX_ARCADE_EXPLO, ignore_walls = FALSE)
			eventdat += "Oh no! The engine has broken down!"
			eventdat += "<br>You can repair it with an engine part, or you can make repairs for 3 days."
			if(engine >= 1)
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];useengine=1'>Use Part</a> <a href='byond://?src=\ref[src];wait=1'>Wait</a></P>"
			else
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];wait=1'>Wait</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"

		if(ORION_TRAIL_MALFUNCTION)
			eventdat += "The ship's systems are malfunctioning!"
			eventdat += "<br>You can replace the broken electronics with spares, or you can spend 3 days troubleshooting the AI."
			if(electronics >= 1)
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];useelec=1'>Use Part</a> <a href='byond://?src=\ref[src];wait=1'>Wait</a></P>"
			else
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];wait=1'>Wait</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"

		if(ORION_TRAIL_COLLISION)
			play_sfx(src, SFX_ARCADE_EXPLO, ignore_walls = FALSE)
			eventdat += "Something hit us! Looks like there's some hull damage."
			if(prob(25))
				var/sfood = rand(5,15)
				var/sfuel = rand(5,15)
				food -= sfood
				fuel -= sfuel
				eventdat += "<br>[sfood] <b>Food</b> and [sfuel] <b>Fuel</b> was vented out into space."
			if(prob(10))
				var/deadname = remove_crewmember()
				eventdat += "<br>[deadname] was killed by rapid depressurization."
			eventdat += "<br>You can repair the damage with hull plates, or you can spend the next 3 days welding scrap together."
			if(hull >= 1)
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];usehull=1'>Use Part</a> <a href='byond://?src=\ref[src];wait=1'>Wait</a></P>"
			else
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];wait=1'>Wait</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"

		if(ORION_TRAIL_BLACKHOLE)
			eventdat += "You were swept away into the black hole."
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];holedeath=1'>Oh...</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
			settlers = list()

		if(ORION_TRAIL_MUTINY)
			eventdat += "You've been hearing rumors of dissenting opinions amoungst your men."
			if(settlers.len <= 2)
				eventdat += "<br>Your crew's so tiny you don't think anybody would risk an uprising."
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];eventclose=1'>Continue</a></P>"
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
				if(prob(10))
					traitors_aboard = min(++traitors_aboard,2)
			else
				if(traitors_aboard) //less likely to stack traitors
					if(prob(20))
						traitors_aboard = min(++traitors_aboard,2)
				else if(prob(70))
					traitors_aboard = min(++traitors_aboard,2)

				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];killcrew=1'>Kill a crewmember</a></P>"
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];eventclose=1'>Risk it</a></P>"
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
			canContinueEvent = 1

		if(ORION_TRAIL_MUTINY_ATTACK)
			if(traitors_aboard <= 0) //shouldn't trigger, but hey.
				eventdat += "Haha, fooled you, there isn't a mutiny on board!"
				eventdat += "<br>(You should report this to a coder :S)"
			else
				var/trait1 = remove_crewmember()
				var/trait2 = ""
				if(traitors_aboard >= 2)
					trait2 = remove_crewmember()

				eventdat += "Oh no, some of your crew are attempting to mutiny!!"
				if(trait2)
					eventdat += "<br>[trait1] and [trait2]'s have armed themselves with weapons!"
				else
					eventdat += "<br>[trait1]'s armed with a weapon!"

				var/chance2attack = alive*20
				if(prob(chance2attack))
					var/chancetokill = 30*traitors_aboard-(5*alive) //eg: 30*2-(10) = 50%, 2 traitorss, 2 crew is 50% chance
					if(prob(chancetokill))
						var/deadguy = remove_crewmember()
						eventdat += "<br>The traitor[trait2 ? "s":""] run[trait2 ? "":"s"] up to [deadguy] and murder[trait2 ? "" : "s"] them!"
					else
						eventdat += "<br>You valiantly fight off the traitor[trait2 ? "s":""]!"
						eventdat += "<br>You cut the traitor[trait2 ? "s":""] up into meat... Eww"
						if(trait2)
							food += 30
							traitors_aboard = max(0,traitors_aboard-2)
						else
							food += 15
							traitors_aboard = max(0,--traitors_aboard)
				else
					eventdat += "<br>The traitor[trait2 ? "s":""] run[trait2 ? "":"s"] away, What wimps!"
					if(trait2)
						traitors_aboard = max(0,traitors_aboard-2)
					else
						traitors_aboard = max(0,--traitors_aboard)

			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];eventclose=1'>Continue</a></P>"
			eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
			canContinueEvent = 1


		if(ORION_TRAIL_SPACEPORT)
			gameStatus = ORION_STATUS_MARKET
			if(spaceport_raided)
				eventdat += "The Spaceport is on high alert! they wont let you dock since you tried to attack them!"
				if(last_spaceport_action)
					eventdat += "<br>Last Spaceport Action: [last_spaceport_action]"
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];leave_spaceport=1'>Depart Spaceport</a></P>"
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];close=1'>Close</a></P>"
			else
				eventdat += "You pull the ship up to dock at a nearby Spaceport, lucky find!"
				eventdat += "<br>This Spaceport is home to travellers who failed to reach Orion, but managed to find a different home..."
				eventdat += "<br>Trading terms: FU = Fuel, FO = Food"
				if(last_spaceport_action)
					eventdat += "<br>Last Spaceport Action: [last_spaceport_action]"
				eventdat += "<h3><b>Crew:</b></h3>"
				eventdat += english_list(settlers)
				eventdat += "<br><b>Food: </b>[food] | <b>Fuel: </b>[fuel]"
				eventdat += "<br><b>Engine Parts: </b>[engine] | <b>Hull Panels: </b>[hull] | <b>Electronics: </b>[electronics]"


				//If your crew is pathetic you can get freebies (provided you haven't already gotten one from this port)
				if(!spaceport_freebie && (fuel < 20 || food < 20))
					spaceport_freebie++
					var/FU = 10
					var/FO = 10
					var/freecrew = 0
					if(prob(30))
						FU = 25
						FO = 25

					if(prob(10))
						add_crewmember()
						freecrew++

					eventdat += "<br>The traders of the spaceport take pity on you, and give you some supplies. (+[FU]FU,+[FO]FO)"
					if(freecrew)
						eventdat += "<br>You also gain a new crewmember!"

					fuel += FU
					food += FO

				//CREW INTERACTIONS
				eventdat += "<P ALIGN=Right>Crew Management:</P>"

				//Buy crew
				if(food >= 10 && fuel >= 10)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];buycrew=1'>Hire a new Crewmember (-10FU,-10FO)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford a new Crewmember</P>"

				//Sell crew
				if(settlers.len > 1)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];sellcrew=1'>Sell crew for Fuel and Food (+7FU,+7FO)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford to sell a Crewmember</P>"

				//BUY/SELL STUFF
				eventdat += "<P ALIGN=Right>Spare Parts:</P>"

				//Engine parts
				if(fuel > 5)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];buyparts=1'>Buy Engine Parts (-5FU)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford to buy Engine Parts</a>"

				//Hull plates
				if(fuel > 5)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];buyparts=2'>Buy Hull Plates (-5FU)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford to buy Hull Plates</a>"

				//Electronics
				if(fuel > 5)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];buyparts=3'>Buy Spare Electronics (-5FU)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford to buy Spare Electronics</a>"

				//Trade
				if(fuel > 5)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];trade=1'>Trade Fuel for Food (-5FU,+5FO)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford to Trade Fuel for Food</P"

				if(food > 5)
					eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];trade=2'>Trade Food for Fuel (+5FU,-5FO)</a></P>"
				else
					eventdat += "<P ALIGN=Right>You cannot afford to Trade Food for Fuel</P"

				//Raid the spaceport
				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];raid_spaceport=1'>!! Raid Spaceport !!</a></P>"

				eventdat += "<P ALIGN=Right><a href='byond://?src=\ref[src];leave_spaceport=1'>Depart Spaceport</a></P>"

/obj/machinery/computer/arcade/orion_trail/proc/add_crewmember(specific = "")
	var/newcrew = ""
	if(specific)
		newcrew = specific
	else
		if(prob(50))
			newcrew = pick(GLOB.first_names_male)
		else
			newcrew = pick(GLOB.first_names_female)
	if(newcrew)
		settlers += newcrew
		alive++
	return newcrew

/obj/machinery/computer/arcade/orion_trail/proc/remove_crewmember(specific = "", dont_remove = "")
	var/list/safe2remove = settlers
	var/removed = ""
	if(dont_remove)
		safe2remove -= dont_remove
	if(specific && specific != dont_remove)
		safe2remove = list(specific)
	else
		removed = pick(safe2remove)

	if(removed)
		if(traitors_aboard && prob(40*traitors_aboard)) //if there are 2 traitors you're twice as likely to get one, obviously
			traitors_aboard = max(0,--traitors_aboard)
		settlers -= removed
		alive--
	return removed

/obj/machinery/computer/arcade/orion_trail/proc/win(mob/user)
	gameStatus = ORION_STATUS_START
	src.visible_message("\The [src] plays a triumpant tune, stating 'CONGRATULATIONS, YOU HAVE MADE IT TO ORION.'")
	play_sfx(src, SFX_ARCADE_ORI_WIN, ignore_walls = FALSE)
	if(emagged)
		new /obj/item/orion_ship(src.loc)
		message_admins("[key_name_admin(user)] made it to Orion on an emagged machine and got an explosive toy ship.")
		log_game("[key_name(user)] made it to Orion on an emagged machine and got an explosive toy ship.")
	else
		prizevend(user)
	set_emagged(0)
	name = "The Orion Trail"
	desc = "Learn how our ancestors got to Orion, and have fun in the process!"

DECLARE_EMAG(/obj/machinery/computer/arcade/orion_trail, PROC_REF(on_emag), null, null)
/obj/machinery/computer/arcade/orion_trail/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	to_chat(user, span_notice("You override the cheat code menu and skip to Cheat #[rand(1, 50)]: Realism Mode."))
	name = "The Orion Trail: Realism Edition"
	desc = "Learn how our ancestors got to Orion, and try not to die in the process!"
	newgame(user)
	set_emagged(1)
	return 1

/obj/item/orion_ship
	name = "model settler ship"
	desc = "A model spaceship, it looks like those used back in the day when travelling to Orion! It even has a miniature FX-293 reactor, which was renowned for its instability and tendency to explode..."
	icon = 'icons/obj/toy.dmi'
	icon_state = "ship"
	w_class = ITEMSIZE_SMALL
	var/active = 0 //if the ship is on

/obj/item/orion_ship/examine(mob/user)
	. = ..()
	if(in_range(user, src))
		if(!active)
			. += span_notice("There's a little switch on the bottom. It's flipped down.")
		else
			. += span_notice("There's a little switch on the bottom. It's flipped up.")

CAPABILITIES(/obj/item/orion_ship)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/orion_ship/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(active)
		return TRUE

	message_admins("[key_name_admin(user)] primed an explosive Orion ship for detonation.")
	log_game("[key_name(user)] primed an explosive Orion ship for detonation.")

	to_chat(user, span_warning("You flip the switch on the underside of [src]."))
	active = 1
	src.visible_message(span_notice("[src] softly beeps and whirs to life!"))
	src.audible_message(span_bold("\The [src]") + " says, 'This is ship ID #[rand(1,1000)] to Orion Port Authority. We're coming in for landing, over.'")
	after(src, 2 SECONDS, PROC_REF(countdown), with = list(1))
	return TRUE

/obj/item/orion_ship/proc/countdown(stage)
	switch(stage)
		if(1)
			src.visible_message(span_warning("[src] begins to vibrate..."))
			src.audible_message(span_bold("\The [src]") + " says, 'Uh, Port? Having some issues with our reactor, could you check it out? Over.'")
			after(src, 3 SECONDS, PROC_REF(countdown), with = list(2))
		if(2)
			src.audible_message(span_bold("\The [src]") + " says, 'Oh, God! Code Eight! CODE EIGHT! IT'S GONNA BL-'")
			after(src, 0.36 SECONDS, PROC_REF(countdown), with = list(3))
		if(3)
			src.visible_message(span_danger("[src] explodes!"))
			explosion(src.loc, 1,2,4)
			destroyed(src, null, "explosion")

#undef ORION_TRAIL_WINTURN
#undef ORION_TRAIL_RAIDERS
#undef ORION_TRAIL_FLUX
#undef ORION_TRAIL_ILLNESS
#undef ORION_TRAIL_BREAKDOWN
#undef ORION_TRAIL_MUTINY
#undef ORION_TRAIL_MUTINY_ATTACK
#undef ORION_TRAIL_MALFUNCTION
#undef ORION_TRAIL_COLLISION
#undef ORION_TRAIL_SPACEPORT
#undef ORION_TRAIL_BLACKHOLE

#undef ORION_STATUS_START
#undef ORION_STATUS_NORMAL
#undef ORION_STATUS_GAMEOVER
#undef ORION_STATUS_MARKET

//////////////////
// Claw Machine //
//////////////////

/obj/machinery/computer/arcade/clawmachine
	name = "AlliCo Grab-a-Gift"
	desc = "Show off your arcade skills for that special someone!"
	icon_state = "clawmachine_new"
	icon_keyboard = null
	icon_screen = null
	circuit = /obj/item/circuitboard/arcade/clawmachine
	prizes = list(/obj/random/plushie)
	var/wintick = 0
	var/winprob = 0
	var/instructions = "Insert 1 thaler or swipe a card to play!"
	var/gameStatus = "CLAWMACHINE_NEW"
	var/gamepaid = 0
	var/gameprice = 1
	var/winscreen = ""

/// Payment and Use. The old attackby tested the base arcade's own interactions
/// (ticket redemption) first via `if(..()) return`, so our own payment
/// interaction is declared after ..() rather than before it; attack_hand's
/// `if(..()) return; tgui_interact(user)` is the shared open_ui interaction.
/obj/machinery/computer/arcade/clawmachine/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()
	into += list(
		/datum/interaction/machine_item/clawmachine_pay,
	)

/// Pay for a game of claw machine with an ID, ewallet or cash.
/datum/interaction/machine_item/clawmachine_pay
	id = "clawmachine_pay"
	name = "Pay"
	category = INTERACTION_CAT_INSERT
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/computer/arcade/clawmachine/proc/wants_payment, null))
	effect = /obj/machinery/computer/arcade/clawmachine/proc/interaction_pay

/// Whether the claw machine still needs payment and can take it right now.
/obj/machinery/computer/arcade/clawmachine/proc/wants_payment(mob/actor, atom/target, obj/item/held)
	return gamepaid == 0 && GLOB.vendor_account && !GLOB.vendor_account.suspended

/obj/machinery/computer/arcade/clawmachine/proc/interaction_pay(mob/user, obj/item/I, datum/interaction/interaction)
	var/paid = 0
	var/obj/item/card/id/W = I.GetID()
	if(W) //for IDs and PDAs and wallets with IDs
		paid = pay_with_card(W, I, user)
	else if(istype(I, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/C = I
		paid = pay_with_ewallet(C, user)
	else if(istype(I, /obj/item/spacecash))
		var/obj/item/spacecash/C = I
		paid = pay_with_cash(C, user)
	if(paid)
		gamepaid = 1
		instructions = "Hit start to play!"
	return TRUE

////// Cash
/obj/machinery/computer/arcade/clawmachine/proc/pay_with_cash(obj/item/spacecash/cashmoney, mob/user)
	if(!emagged)
		if(gameprice > cashmoney.worth)

			// This is not a status display message, since it's something the character
			// themselves is meant to see BEFORE putting the money in
			to_chat(user, "[icon2html(cashmoney,user.client)] " + span_warning("That is not enough money."))
			return 0

		if(istype(cashmoney, /obj/item/spacecash))

			act_message(user, src, others = span_info("%U% inserts some cash into %T%."))
			cashmoney.worth -= gameprice

			if(cashmoney.worth <= 0)
				consume(cashmoney, user)
			else
				cashmoney.update_icon()

		// Machine has no idea who paid with cash
		credit_purchase("(cash)")
		return 1
	if(emagged)
		play_sfx(src, SFX_ARCADE_STEAL, ignore_walls = FALSE)
		to_chat(user, span_info("It doesn't seem to accept that! Seem you'll need to swipe a valid ID."))

///// Ewallet
/obj/machinery/computer/arcade/clawmachine/proc/pay_with_ewallet(obj/item/spacecash/ewallet/wallet, mob/user)
	if(!emagged)
		act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = wallet)
		play_sfx(src, SFX_MACHINES_ID_SWIPE)
		if(gameprice > wallet.worth)
			visible_message(span_info("Insufficient funds."))
			return 0
		else
			wallet.worth -= gameprice
			credit_purchase("[wallet.owner_name] (chargecard)")
			return 1
	if(emagged)
		play_sfx(src, SFX_ARCADE_STEAL, ignore_walls = FALSE)
		to_chat(user, span_info("It doesn't seem to accept that! Seem you'll need to swipe a valid ID."))

///// ID
/obj/machinery/computer/arcade/clawmachine/proc/pay_with_card(obj/item/card/id/I, obj/item/ID_container, mob/user)
	if(I==ID_container || ID_container == null)
		act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = I)
	else
		act_message(user, src, others = span_info("%U% swipes %I% through %T%."), item = ID_container)
	play_sfx(src, SFX_MACHINES_ID_SWIPE)
	var/datum/money_account/customer_account = get_account(I.associated_account_number)
	if(!customer_account)
		visible_message(span_info("Error: Unable to access account. Please contact technical support if problem persists."))
		return 0

	if(customer_account.suspended)
		visible_message(span_info("Unable to access account: account suspended."))
		return 0

	// Have the customer punch in the PIN before checking if there's enough money. Prevents people from figuring out acct is
	// empty at high security levels
	if(customer_account.security_level != 0) //If card requires pin authentication (ie seclevel 1 or 2)
		open_request(src, /datum/prompt/number/claw_pin, PROC_REF(card_pin_entered), valid = PROC_REF(request_usable), answerer = user, account = I.associated_account_number, timeout = 0)
		return 0
	return charge_account(customer_account)

/// The PIN arrived: the play is paid once the account accepts it.
/datum/prompt/number/claw_pin
	title = "Vendor transaction"
	question = "Enter pin code"
	min_value = null
	var/account

/obj/machinery/computer/arcade/clawmachine/proc/card_pin_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/claw_pin/R = A.request
	var/datum/money_account/customer_account = attempt_account_access(R.account, A.answer.value, 2)
	if(!customer_account)
		visible_message(span_info("Unable to access account: incorrect credentials."))
		return
	if(!gamepaid && charge_account(customer_account))
		gamepaid = 1
		instructions = "Hit start to play!"

/obj/machinery/computer/arcade/clawmachine/proc/charge_account(datum/money_account/customer_account)
	if(gameprice > customer_account.money)
		visible_message(span_info("Insufficient funds in account."))
		return 0
	else
		// Okay to move the money at this point
		if(emagged)
			gameprice = customer_account.money
		return transfer_account_funds(customer_account, GLOB.vendor_account, gameprice, "Arcade play", name)

/// Add to vendor account

/obj/machinery/computer/arcade/clawmachine/proc/credit_purchase(target as text)
	GLOB.vendor_account.credit(gameprice, name, "Arcade play", name)

	var/datum/transaction/T = new()
	T.target_name = target
	T.purpose = "Purchase of arcade game([name])"
	T.amount = "[gameprice]"
	T.source_terminal = name
	T.date = GLOB.current_date_string
	T.time = stationtime2text()
	rel_add(GLOB.vendor_account, nameof(/datum/money_account::transaction_log), T)

/// TGUI Stuff

CAPABILITIES(/obj/machinery/computer/arcade/clawmachine)
	interface("ClawMachine")
	op("newgame", ui_act("newgame"), then(PROC_REF(ui_act_newgame)))
	op("return", ui_act("return"), then(PROC_REF(ui_act_return)))
	op("pointless", ui_act("pointless"), then(PROC_REF(ui_act_pointless)))

/obj/machinery/computer/arcade/clawmachine/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["wintick"] = wintick
	data["instructions"] = instructions
	data["gameStatus"] = gameStatus
	data["winscreen"] = winscreen
	return data

/// The play is a live game: the window refreshes on its own.
/obj/machinery/computer/arcade/clawmachine/ui_opening(mob/user, datum/tgui/ui)
	ui.set_autoupdate(TRUE)

/obj/machinery/computer/arcade/clawmachine/proc/ui_act_newgame(datum/act/op/A)
	if(gamepaid == 0)
		play_sfx(src, SFX_ARCADE_STEAL, ignore_walls = FALSE)
	else if(gamepaid == 1)
		gameStatus = "CLAWMACHINE_ON"
		icon_state = "clawmachine_new_move"
		instructions = "Guide the claw to the prize you want!"
		wintick = 0

/obj/machinery/computer/arcade/clawmachine/proc/ui_act_return(datum/act/op/A)
	if(gameStatus == "CLAWMACHINE_END")
		gameStatus = "CLAWMACHINE_NEW"

/obj/machinery/computer/arcade/clawmachine/proc/ui_act_pointless(datum/act/op/A)
	var/mob/user = A.actor
	if(wintick < 10)
		wintick += 1
	if(wintick >= 10)
		instructions = "Insert 1 thaler or swipe a card to play!"
		clawvend(user)

/obj/machinery/computer/arcade/clawmachine/proc/clawvend(mob/user) /// True to a real claw machine, it's NEARLY impossible to win.
	winprob += 1 /// Yeah.

	if(prob(winprob)) /// YEAH.
		if(!emagged)
			prizevend(user)
			winscreen = "You won!"
		else if(emagged)
			gameprice = 1
			set_emagged(0)
			winscreen = "You won...?"
			var/obj/item/grenade/G = new /obj/item/grenade/explosive(get_turf(src)) /// YEAAAAAAAAAAAAAAAAAAH!!!!!!!!!!
			G.activate()
			G.throw_at(get_turf(user),10,10) /// Play stupid games, win stupid prizes.

		play_sfx(src, SFX_ARCADE_ORI_WIN, ignore_walls = FALSE)
		winprob = 0

	else
		play_sfx(src, SFX_ARCADE_ORI_FAIL, ignore_walls = FALSE)
		winscreen = "Aw, shucks. Try again!"
	wintick = 0
	gamepaid = 0
	icon_state = "clawmachine_new"
	gameStatus = "CLAWMACHINE_END"

DECLARE_EMAG(/obj/machinery/computer/arcade/clawmachine, PROC_REF(on_emag), null, null)
/obj/machinery/computer/arcade/clawmachine/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	to_chat(user, span_info("You modify the claw of the machine. The next one is sure to win! You just have to pay..."))
	name = "AlliCo Snag-A-Prize"
	desc = "Get some goodies, all for you!"
	instructions = "Swipe a card to play!"
	winprob = 100
	gamepaid = 0
	wintick = 0
	gameStatus = "CLAWMACHINE_NEW"
	set_emagged(1)
	return 1

// === merged from arcade_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/computer/arcade
	prizes = list(	/obj/item/storage/box/snappops							= 2,
							/obj/item/toy/blink										= 2,
							/obj/item/clothing/under/syndicate/tacticool			= 2,
							/obj/item/toy/sword										= 2,
							/obj/item/storage/box/capguntoy					= 2,
							/obj/item/gun/projectile/revolver/toy/crossbow	= 2,
							/obj/item/clothing/suit/syndicatefake					= 2,
							/obj/item/storage/fancy/crayons					= 2,
							/obj/item/toy/spinningtoy								= 2,
							/obj/random/mech_toy									= 1,
							/obj/item/reagent_containers/spray/waterflower	= 1,
							/obj/random/action_figure								= 1,
							/obj/random/plushie										= 1,
							/obj/item/toy/cultsword									= 1,
							/obj/item/toy/bouquet/fake								= 1,
							/obj/item/clothing/accessory/badge/sheriff				= 2,
							/obj/item/clothing/head/cowboy/small					= 2,
							/obj/item/toy/stickhorse								= 2,
							/obj/item/toy/rock										= 2,
							/obj/item/toy/flash										= 2,
							/obj/item/toy/redbutton									= 2,
							/obj/item/toy/gnome										= 2,
							/obj/item/toy/AI										= 2,
							/obj/item/clothing/gloves/ring/buzzer/toy				= 2,
							/obj/item/storage/box/handcuffs/fake				= 2,
							/obj/item/toy/nuke										= 2,
							/obj/item/toy/minigibber								= 2,
							/obj/item/toy/toy_xeno									= 2,
							/obj/item/toy/monster_bait						= 2,
							/obj/item/toy/russian_revolver							= 1,
							/obj/item/toy/russian_revolver/trick_revolver			= 1,
							/obj/item/toy/chainsaw									= 1,
							/obj/random/miniature									= 1,
							/obj/item/toy/snake_popper								= 1
							)
