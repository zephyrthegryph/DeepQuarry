/obj/item/clothing/under/teshari
	icon = 'icons/inventory/uniform/item_teshari.dmi'
	icon_state = "seromi_grey"
	species_restricted = list(SPECIES_TESHARI)

/obj/item/clothing/under/teshari/smock
	name = "small grey smock"
	desc = "It looks fitted to nonhuman proportions."
	icon_state = "seromi_grey"
	body_parts_covered = 0 // It's a thin piece of cloth with a neck hole.

/obj/item/clothing/under/teshari/smock/dress
	name = "small command dress"
	icon_state = "seromi_dress_cap"

// Worksuits
/obj/item/clothing/under/teshari/undercoat/standard/worksuit
	name = "small black and red worksuit"
	icon_state = "teshari_black_red_worksuit"
	desc = "A small worksuit designed for a Teshari"

//Standard Undercoats

/obj/item/clothing/under/teshari/undercoat
	name = "Undercoat"
	desc =  "A Teshari traditional garb, with a modern twist! Made of micro and nanofibres to make it light and billowy, perfect for going fast and stylishly!"
	icon_state = "tesh_uniform_bo"
	body_parts_covered = CHEST

/obj/item/clothing/under/teshari/undercoat/standard/black_orange
	name = "black and orange undercoat"
	icon_state = "tesh_uniform_bo"

/obj/item/clothing/under/teshari/undercoat/standard/black_grey
	name = "black and grey undercoat"
	icon_state = "tesh_uniform_bg"

/obj/item/clothing/under/teshari/undercoat/standard/black_white
	name = "black and white undercoat"
	icon_state = "tesh_uniform_bw"

/obj/item/clothing/under/teshari/undercoat/standard/black_red
	name = "black and red undercoat"
	icon_state = "tesh_uniform_br"

/obj/item/clothing/under/teshari/undercoat/standard/black
	name = "black undercoat"
	icon_state = "tesh_uniform_bn"

/obj/item/clothing/under/teshari/undercoat/standard/black_yellow
	name = "black and yellow undercoat"
	icon_state = "tesh_uniform_by"

/obj/item/clothing/under/teshari/undercoat/standard/black_green
	name = "black and green undercoat"
	icon_state = "tesh_uniform_bgr"

/obj/item/clothing/under/teshari/undercoat/standard/black_blue
	name = "black and blue undercoat"
	icon_state = "tesh_uniform_bbl"

/obj/item/clothing/under/teshari/undercoat/standard/black_purple
	name = "black and purple undercoat"
	icon_state = "tesh_uniform_bp"

/obj/item/clothing/under/teshari/undercoat/standard/black_pink
	name = "black and pink undercoat"
	icon_state = "tesh_uniform_bpi"

/obj/item/clothing/under/teshari/undercoat/standard/black_brown
	name = "black and brown undercoat"
	icon_state = "tesh_uniform_bbr"

/obj/item/clothing/under/teshari/undercoat/standard/orange_grey
	name = "orange and grey undercoat"
	icon_state = "tesh_uniform_og"

/obj/item/clothing/under/teshari/undercoat/standard/rainbow
	name = "rainbow undercoat"
	icon_state = "tesh_uniform_rainbow"

/obj/item/clothing/under/teshari/undercoat/standard/lightgrey_grey
	name = "light grey and grey undercoat"
	icon_state = "tesh_uniform_lgg"

/obj/item/clothing/under/teshari/undercoat/standard/white_grey
	name = "white and grey undercoat"
	icon_state = "tesh_uniform_wg"

/obj/item/clothing/under/teshari/undercoat/standard/red_grey
	name = "red and grey undercoat"
	icon_state = "tesh_uniform_rg"

/obj/item/clothing/under/teshari/undercoat/standard/orange
	name = "orange undercoat"
	icon_state = "tesh_uniform_on"

/obj/item/clothing/under/teshari/undercoat/standard/yellow_grey
	name = "yellow and grey undercoat"
	icon_state = "tesh_uniform_yg"

/obj/item/clothing/under/teshari/undercoat/standard/green_grey
	name = "green and grey undercoat"
	icon_state = "tesh_uniform_gg"

/obj/item/clothing/under/teshari/undercoat/standard/blue_grey
	name = "blue and grey undercoat"
	icon_state = "tesh_uniform_blug"

/obj/item/clothing/under/teshari/undercoat/standard/purple_grey
	name = "purple and grey undercoat"
	icon_state = "tesh_uniform_pg"

/obj/item/clothing/under/teshari/undercoat/standard/pink_grey
	name = "pink and grey undercoat"
	icon_state = "tesh_uniform_pig"

/obj/item/clothing/under/teshari/undercoat/standard/brown_grey
	name = "brown and grey undercoat"
	icon_state = "tesh_uniform_brg"

//Job Undercoats
/obj/item/clothing/under/teshari/undercoat/jobs/cap
	name = "site manager undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_SITE_MANAGER
	icon_state = "tesh_uniform_cap"

/obj/item/clothing/under/teshari/undercoat/jobs/hop
	name = "head of personnel undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_HEAD_OF_PERSONNEL
	icon_state = "tesh_uniform_hop"

/obj/item/clothing/under/teshari/undercoat/jobs/ce
	name = "chief engineer undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_CHIEF_ENGINEER
	icon_state = "tesh_uniform_ce"

/obj/item/clothing/under/teshari/undercoat/jobs/hos
	name = "head of security undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_HEAD_OF_SECURITY + ". Made with slightly sturdier materials."
	icon_state = "tesh_uniform_hos"
	armor = list(melee = 10, bullet = 0, laser = 0,energy = 0, bomb = 0, bio = 0, rad = 0) // start
	siemens_coefficient = 0.9
	body_parts_covered = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS // end

/obj/item/clothing/under/teshari/undercoat/jobs/rd
	name = "research director undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_RESEARCH_DIRECTOR
	icon_state = "tesh_uniform_rd"

/obj/item/clothing/under/teshari/undercoat/jobs/engineer
	name = "engineering undercoat"
	desc = "A traditional Teshari garb made for the Engineering department"
	icon_state = "tesh_uniform_engie"

/obj/item/clothing/under/teshari/undercoat/jobs/atmos
	name = "atmospherics undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_ATMOSPHERIC_TECHNICIAN
	icon_state = "tesh_uniform_atmos"

/obj/item/clothing/under/teshari/undercoat/jobs/cmo
	name = "chief medical officer undercoat"
	desc = "A traditional Teshari garb made for the Chief Medical Officer"
	icon_state = "tesh_uniform_cmo"

/obj/item/clothing/under/teshari/undercoat/jobs/qm
	name = "quartermaster undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_QUARTERMASTER
	icon_state = "tesh_uniform_qm"

/obj/item/clothing/under/teshari/undercoat/jobs/cargo
	name = "cargo undercoat"
	desc = "A traditional Teshari garb made for the Cargo department"
	icon_state = "tesh_uniform_car"

/obj/item/clothing/under/teshari/undercoat/jobs/mining
	name = "mining undercoat"
	desc = "A traditional Teshari garb made for Mining"
	icon_state = "tesh_uniform_mine"

/obj/item/clothing/under/teshari/undercoat/jobs/medical
	name = "medical undercoat"
	desc = "A traditional Teshari garb made for the Medical department"
	icon_state = "tesh_uniform_doc"

/obj/item/clothing/under/teshari/undercoat/jobs/chemistry
	name = "chemist undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_CHEMIST
	icon_state = "tesh_uniform_chem"

/obj/item/clothing/under/teshari/undercoat/jobs/viro
	name = "virologist undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_ALT_VIROLOGIST
	icon_state = "tesh_uniform_viro"

/obj/item/clothing/under/teshari/undercoat/jobs/psych
	name = "psychiatrist undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_PSYCHIATRIST
	icon_state = "tesh_uniform_psych"

/obj/item/clothing/under/teshari/undercoat/jobs/para
	name = "paramedic undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_PARAMEDIC
	icon_state = "tesh_uniform_para"

/obj/item/clothing/under/teshari/undercoat/jobs/sci
	name = "scientist undercoat"
	desc = "A traditional Teshari garb made for the Science department"
	icon_state = "tesh_uniform_sci"

/obj/item/clothing/under/teshari/undercoat/jobs/robo
	name = "roboticist undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_ROBOTICIST
	icon_state = "tesh_uniform_robo"

/obj/item/clothing/under/teshari/undercoat/jobs/sec
	name = "security undercoat"
	desc = "A traditional Teshari garb made for the Security department. Made with slightly sturdier materials."
	icon_state = "tesh_uniform_sec"
	armor = list(melee = 10, bullet = 0, laser = 0,energy = 0, bomb = 0, bio = 0, rad = 0) // start
	siemens_coefficient = 0.9
	body_parts_covered = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS // end

/obj/item/clothing/under/teshari/undercoat/jobs/service
	name = "service undercoat"
	desc = "A traditional Teshari garb made for the Service department"
	icon_state = "tesh_uniform_serv"

/obj/item/clothing/under/teshari/undercoat/jobs/iaa
	name = "internal affairs undercoat"
	desc = "A traditional Teshari garb made for the " + JOB_INTERNAL_AFFAIRS_AGENT
	icon_state = "tesh_uniform_iaa"
