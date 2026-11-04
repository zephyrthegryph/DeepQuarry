/datum/lore/organization/gov/fyrds
	name = "Unitary Alliance of Salthan Fyrds"
	short_name = "Saltha"
	acronym = "SMS"
	desc = "Born out of neglect, the Salthan Fyrds are cast-off colonies of the Commonwealth after giving up on \
				pacifying the wartorn region and fighting off the stray Unathi Raiders after the Hegemony War. \
				In the end they self-organized into military pacts and have formed a militaristic society, in which \
				every person, be it organic or robot, is a soldier for the continued cause in serving as aegis against \
				another Unathi Incursion. They are very no-nonsense."
	history = ""
	work = "human stratocracy"
	headquarters = "The Pact, Myria"
	motto = ""

	org_type = "government"
	ship_prefixes = list("SFM-M" = "a patrol")	 // The Salthans don't do anything else.
			//specifically-undefeated generals, just to shake up the usual list everyone knows
	ship_names = list(
			"Ahmose I",
			"Thutmose I & III",
			"Seti I",
			"Ramesses II",
			"Tariq ibn Ziyad",
			"Shaka Zulu",
			"Bai Qi",
			"Ashoka the Great",
			"Han Xin",
			"Chen Qingzhi",
			"Sargon of Akkad",
			"Khalid ibn al-Walid",
			"Narses",
			"David IV",
			"Yue Fei",
			"Subutai",
			"Tamerlane",
			"Kumbha of Mewar",
			"Akbar",
			"Admiral Yi",
			"Chatrapati Sambhaji Maharaj",
			"Baji Rao",
			"Nguyen Hue",
			"Alexander the Great",
			"Epaminondas",
			"Nero Claudius Drusus",
			"Burebista",
			"Pepin the Short",
			"El Cid",
			"Jan Zizka",
			"Scanderbeg",
			"Edward IV",
			"Pal Kinizsi",
			"Ivan Sirko",
			"John Churchill",
			"Maurice of Nassau",
			"Alvaro de Bazan",
			"Blas de Lezo",
			"Prince Henry",
			"Alexander Suvorov",
			"Fyodor Ushakov",
			"Charles XI",
			"August von Mackensen",
			"Paul von Lettow-Vorbeck",
			"George Henry Thomas"
			)
	/* retained for archival, no longer necessary
	destination_names = list(
			"Base Alpha-Romero",
			"Base Zeta-Xray",
			"Base Epsilon-Epsilon",
			"Base Xray-Beta",
			"Base Gamma-Delta",
			"Base Yotta-Epsilon"
			)
	*/

/datum/lore/organization/gov/fyrds/New()
	..()
	var/fyrdsgen = rand(8, 16) //significantly increased from original values due to the greater length of rounds on YW
	var/list/location = list(
			"Base","Outpost","Installation","Station","Waypoint","Nav Point"
			)
	var/list/greek = list(
			"Alpha","Beta","Gamma","Delta","Epsilon","Zeta","Eta","Theta","Iota","Kappa","Lambda","Mu","Nu","Xi","Omicron","Pi","Rho","Sigma","Tau","Upsilon","Phi","Chi","Psi","Omega"
			)
	var/list/phoenician = list(
			"Aleph","Beth","Gimel","Daleth","He","Zayin","Heth","Teth","Yodh","Kaph","Lamedh","Mem","Nun","Samekh","'Ayin","Pe","Res","Sin","Taw","Waw","Sade","Qoph"
			)
	var/list/russian = list(
			"Anna","Boris","Vasily","Gregory","Galina","Dmitri","Yelena","Zhenya","Zinaida","Zoya","Ivan","Konstantin","Leonid","Mikhail","Mariya","Nikolai","Olga","Pavel","Roman","Semyon","Sergei","Tatyana","Tamara","Ulyana","Fyodor","Khariton","Tsaplya","Tsentr","Chelovek","Shura","Shchuka","Yery","Znak","Echo","Emma","Yuri","Yakov"
			)
	var/list/american = list(
			"Alfa","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","Xray","Yankee","Zulu"
			)

	while(fyrdsgen)
		LAZYINITLIST(destination_names); destination_names.Add("[pick(location)] [pick(greek)]-[pick(greek)]","[pick(location)] [pick(phoenician)]-[pick(phoenician)]","[pick(location)] [pick(russian)]-[pick(russian)]","[pick(location)] [pick(american)]-[pick(american)]")
		fyrdsgen--
