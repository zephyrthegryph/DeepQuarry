/obj/item/clothing/head/centhat
	name = "\improper CentCom. hat"
	icon_state = "centcom"
	desc = "It's good to be emperor."
	siemens_coefficient = 0.9
	body_parts_covered = 0

/obj/item/clothing/head/centhat/customs
	name = "Customs Hat"
	desc = "A formal hat for SolGov Customs Officers."
	icon_state = "customshat"

/obj/item/clothing/head/halo
	name = "halo"
	desc = "a small metal ring, floating above it's wearer."
	icon_state = "halo"

/obj/item/clothing/head/headband/maid/modern
	name = "modern maid headband"
	desc = "Just like from my Japanese cartoons!"
	icon_state = "maid_headband"

/obj/item/clothing/head/pin
	icon_state = "pin"
	addblends = "pin_a"
	name = "hair pin"
	desc = "A nice hair pin."
	slot_flags = SLOT_HEAD | SLOT_EARS
	body_parts_covered = 0
	drop_sound = 'sound/items/drop/accessory.ogg'
	pickup_sound = 'sound/items/pickup/accessory.ogg'

/obj/item/clothing/head/pin/pink
	icon_state = "pinkpin"
	addblends = null
	name = "pink hair hat"

/obj/item/clothing/head/pin/clover
	icon_state = "cloverpin"
	name = "clover pin"
	addblends = null
	desc = "A hair pin in the shape of a clover leaf."

/obj/item/clothing/head/pin/butterfly
	icon_state = "butterflypin"
	name = "butterfly pin"
	addblends = null
	desc = "A hair pin in the shape of a bright blue butterfly."

/obj/item/clothing/head/pin/magnetic
	icon_state = "magnetpin"
	name = "magnetic 'pin'"
	addblends = null
	desc = "Finally, a hair pin even a Morpheus chassis can use."
	matter = list(MAT_STEEL = 10)

/obj/item/clothing/head/pin/flower
	name = "red flower pin"
	icon_state = "hairflower"
	addblends = null
	desc = "Smells nice."

/obj/item/clothing/head/pin/flower/blue
	icon_state = "hairflower_blue"
	name = "blue flower pin"

/obj/item/clothing/head/pin/flower/pink
	icon_state = "hairflower_pink"
	name = "pink flower pin"

/obj/item/clothing/head/pin/flower/yellow
	icon_state = "hairflower_yellow"
	name = "yellow flower pin"

/obj/item/clothing/head/pin/flower/violet
	icon_state = "hairflower_violet"
	name = "violet flower pin"

/obj/item/clothing/head/pin/flower/orange
	icon_state = "hairflower_orange"
	name = "orange flower pin"

/obj/item/clothing/head/pin/flower/white
	icon_state = "hairflower_white"
	addblends = "hairflower_white_a"
	name = "flower pin"

/obj/item/clothing/head/pin/bow
	icon_state = "bow"
	addblends = "bow_a"
	name = "hair bow"
	desc = "A ribbon tied into a bow with a clip on the back to attach to hair."
	item_state_slots = list(slot_r_hand_str = "pill", slot_l_hand_str = "pill")

/obj/item/clothing/head/pin/bow/big
	icon_state = "whiteribbon"
	name = "ribbon"

/obj/item/clothing/head/pin/bow/big/red
	icon_state = "redribbon"
	name = "red ribbon"
	addblends = null

/obj/item/clothing/head/powdered_wig
	name = "powdered wig"
	desc = "A powdered wig."
	icon_state = "pwig"

/obj/item/clothing/head/redcoat
	name = "redcoat's hat"
	icon_state = "redcoat"
	item_state_slots = list(slot_r_hand_str = "pirate", slot_l_hand_str = "pirate")
	desc = span_italics("'I guess it's a redhead.'")
	body_parts_covered = 0

/obj/item/clothing/head/mailman
	name = "station cap"
	icon_state = "mailman"
	item_state_slots = list(slot_r_hand_str = "hopcap", slot_l_hand_str = "hopcap")
	desc = "<i>Choo-choo</i>!"
	body_parts_covered = 0

/obj/item/clothing/head/plaguedoctorhat
	name = "plague doctor's hat"
	desc = "These were once used by Plague doctors, allegedly. They're pretty much useless."
	icon_state = "plaguedoctor"
	item_state_slots = list(slot_r_hand_str = "tophat", slot_l_hand_str = "tophat")
	permeability_coefficient = 0.01
	siemens_coefficient = 0.9
	body_parts_covered = 0

/obj/item/clothing/head/plaguedoctorhat/gold
	name = "golden plague doctor's hat"
	desc = "These were once used by plague doctors, allegedly. This one has gold accents."
	icon_state = "plaguedoctor2"

/obj/item/clothing/head/hasturhood
	name = "hastur's hood"
	desc = "It's unspeakably stylish"
	icon_state = "hasturhood"
	item_state_slots = list(slot_r_hand_str = "enginering_beret", slot_l_hand_str = "enginering_beret")
	flags_inv = BLOCKHAIR
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/head/nursehat
	name = "nurse's hat"
	desc = "It allows quick identification of trained medical personnel."
	icon_state = "nursehat"
	siemens_coefficient = 0.9
	body_parts_covered = 0

/obj/item/clothing/head/syndicatefake
	name = "red space-helmet replica"
	item_state_slots = list(slot_r_hand_str = "syndicate-helm-black-red", slot_l_hand_str = "syndicate-helm-black-red")
	icon_state = "syndicate"
	desc = "A plastic replica of a bloodthirsty mercenary's space helmet, you'll look just like a real murderous criminal operative in this! This is a toy, it is not made for use in space!"
	flags_inv = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE|BLOCKHAIR
	siemens_coefficient = 2.0
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/head/cueball
	name = "cueball helmet"
	desc = "A large, featureless white orb mean to be worn on your head. How do you even see out of this thing?"
	icon_state = "cueball"
	flags_inv = BLOCKHAIR
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/head/greenbandana
	name = "green bandana"
	desc = "It's a green bandana with some fine nanotech lining."
	icon_state = "greenbandana"
	flags_inv = 0
	body_parts_covered = 0

/obj/item/clothing/head/cardborg
	name = "cardborg helmet"
	desc = "A helmet made out of a box."
	icon_state = "cardborg_h"
	flags_inv = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE
	body_parts_covered = HEAD|FACE|EYES
	drop_sound = 'sound/items/drop/cardboardbox.ogg'
	pickup_sound = 'sound/items/pickup/cardboardbox.ogg'

/obj/item/clothing/head/rabbitears
	name = "rabbit ears"
	desc = "A pair of rabbit ears!" // weird description bgone
	icon_state = "bunny"
	body_parts_covered = 0

/obj/item/clothing/head/flatcap
	name = "flat cap"
	desc = "A working man's cap."
	icon_state = "flat_cap"
	item_state_slots = list(slot_r_hand_str = "detective", slot_l_hand_str = "detective")
	siemens_coefficient = 0.9 //...what?

/obj/item/clothing/head/flatcap/grey
	icon_state = "flat_capw"
	addblends = "flat_capw_a"
	item_state_slots = list(slot_r_hand_str = "greysoft", slot_l_hand_str = "greysoft")

/obj/item/clothing/head/pirate
	name = "pirate hat"
	desc = "Yarr."
	icon_state = "pirate"
	body_parts_covered = 0

/obj/item/clothing/head/hgpiratecap
	name = "pirate hat"
	desc = "Yarr."
	icon_state = "hgpiratecap"
	item_state_slots = list(slot_r_hand_str = "hoscap", slot_l_hand_str = "hoscap")
	body_parts_covered = 0

/obj/item/clothing/head/bandana
	name = "pirate bandana"
	desc = "Yarr."
	icon_state = "bandana"
	item_state_slots = list(slot_r_hand_str = "redbandana", slot_l_hand_str = "redbandana")

/obj/item/clothing/head/witchwig
	name = "witch costume wig"
	desc = "Eeeee~heheheheheheh!"
	icon_state = "witch"
	flags_inv = BLOCKHAIR
	siemens_coefficient = 2.0

/obj/item/clothing/head/chicken
	name = "chicken suit head"
	desc = "Bkaw!"
	icon_state = "chickenhead"
	flags_inv = BLOCKHAIR
	siemens_coefficient = 0.7
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/head/bearpelt
	name = "bear pelt hat"
	desc = "Fuzzy."
	icon_state = "bearpelt"
	item_state_slots = list(slot_r_hand_str = "beret_black", slot_l_hand_str = "beret_black")
	flags_inv = BLOCKHAIR
	siemens_coefficient = 0.7

/obj/item/clothing/head/xenos
	name = "xenos helmet"
	icon_state = "xenos"
	item_state_slots = list(slot_r_hand_str = "xenos_helm", slot_l_hand_str = "xenos_helm")
	desc = "A helmet made out of chitinous alien hide."
	flags_inv = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE|BLOCKHAIR
	siemens_coefficient = 2.0
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/head/philosopher_wig
	name = "natural philosopher's wig"
	desc = "A stylish monstrosity unearthed from Earth's Renaissance period. With this most distinguish'd wig, you'll be ready for your next soiree!"
	icon_state = "philosopher_wig"
	item_state_slots = list(slot_r_hand_str = "pwig", slot_l_hand_str = "pwig")
	flags_inv = BLOCKHAIR
	siemens_coefficient = 2.0 //why is it so conductive?!
	body_parts_covered = 0

/obj/item/clothing/head/orangebandana //themij: Taryn Kifer
	name = "orange bandana"
	desc = "An orange piece of cloth, worn on the head."
	icon_state = "orange_bandana"
	body_parts_covered = 0

/obj/item/clothing/head/hijab
	name = "hijab"
	desc = "A veil that is wrapped to cover the head and chest"
	icon_state = "hijab"
	addblends = "hijab_a"
	item_state_slots = list(slot_r_hand_str = "beret_white", slot_l_hand_str = "beret_white")
	body_parts_covered = 0
	flags_inv = BLOCKHAIR

/obj/item/clothing/head/kippa
	name = "kippa"
	desc = "A small, brimless cap."
	icon_state = "kippa"
	addblends = "kippa_a"
	body_parts_covered = 0

/obj/item/clothing/head/turban
	name = "turban"
	desc = "A cloth used to wind around the head"
	icon_state = "turban"
	addblends = "turban_a"
	item_state_slots = list(slot_r_hand_str = "beret_white", slot_l_hand_str = "beret_white")
	body_parts_covered = 0
	flags_inv = BLOCKHEADHAIR

/obj/item/clothing/head/taqiyah
	name = "taqiyah"
	desc = "A short, rounded skullcap usually worn for religious purposes."
	icon_state = "taqiyah"
	addblends = "taqiyah_a"
	item_state_slots = list(slot_r_hand_str = "taq", slot_l_hand_str = "taq")

/obj/item/clothing/head/beanie
	name = "beanie"
	desc = "A head-hugging brimless winter cap. This one is tight."
	icon_state = "beanie"
	addblends = "beanie_a"
	body_parts_covered = 0

/obj/item/clothing/head/beanie_loose
	name = "loose beanie"
	desc = "A head-hugging brimless winter cap. This one is loose."
	icon_state = "beanie_hang"
	addblends = "beanie_hang_a"
	body_parts_covered = 0

/obj/item/clothing/head/beretg
	name = "beret"
	desc = "A beret, an artists favorite headwear."
	icon_state = "beret_g"
	addblends = "beret_g_a"
	body_parts_covered = 0

/obj/item/clothing/head/sombrero
	name = "sombrero"
	desc = "A wide-brimmed hat popularly worn in Mexico."
	icon_state = "sombrero"
	body_parts_covered = 0

/obj/item/clothing/head/headband/maid
	name = "maid headband"
	desc = "Keeps hair out of the way for important... jobs."
	icon_state = "maid"
	body_parts_covered = 0

/obj/item/clothing/head/maangtikka
	name = "maang tikka"
	desc = "A jeweled headpiece originating in India."
	icon_state = "maangtikka"
	body_parts_covered = 0
	drop_sound = 'sound/items/drop/ring.ogg'
	pickup_sound = 'sound/items/pickup/ring.ogg'

/obj/item/clothing/head/jingasa
	name = "jingasa"
	desc = "A wide, flat rain hat originally from Japan."
	icon_state = "jingasa"
	body_parts_covered = 0
	item_state_slots = list(slot_r_hand_str = "taq", slot_l_hand_str = "taq")

/obj/item/clothing/head/blackngoldheaddress
	name = "black and gold headdress"
	desc = "An odd looking headdress that covers the eyes."
	icon_state = "blackngoldheaddress"
	flags_inv = HIDEEYES
	body_parts_covered = HEAD|EYES

//Corporate Berets

/obj/item/clothing/head/beret/corp/saare
	name = "\improper SAARE beret"
	desc = "A red beret denoting service with Stealth Assault Enterprises. For mercenaries that are more inclined towards style than safety."
	icon_state = "beret_red"

/obj/item/clothing/head/beret/corp/saare/officer
	name = "\improper SAARE officer beret"
	desc = "A red beret with a gold insignia, denoting senior service with Stealth Assault Enterprises. For mercenaries who are more inclined towards style than safety."
	icon_state = "beret_redgold"

/obj/item/clothing/head/beret/corp/pcrc
	name = "\improper PCRC beret"
	desc = "A black beret with a PCRC logo insignia, denoting service with Proxima Centauri Risk Control. For private security personnel that are more inclined towards style than safety."
	icon_state = "beret_black_pcrc"


/obj/item/clothing/head/beret/corp/hedberg
	name = "\improper Hedberg-Hammarstrom beret"
	desc = "A tan beret denoting service with Hedberg-Hammarstrom private security. For mercenaries who are more inclined towards style than safety."
	icon_state = "beret_tan"

/obj/item/clothing/head/beret/corp/xion
	name = "\improper Xion beret"
	desc = "An orange beret denoting employment with Xion Manufacturing. For personnel that are more inclined towards style than safety."
	icon_state = "beret_orange"

//Stylish Hats

/obj/item/clothing/head/bowler
	name = "bowler hat"
	desc = "Gentleman, elite aboard!"
	icon_state = "bowler"
	item_state_slots = list(slot_r_hand_str = "tophat", slot_l_hand_str = "tophat")
	body_parts_covered = 0

/obj/item/clothing/head/that
	name = "top-hat"
	desc = "It's an amish looking hat."
	icon_state = "tophat"
	siemens_coefficient = 0.9
	body_parts_covered = 0

/obj/item/clothing/head/beaverhat
	name = "beaver hat"
	desc = "Soft felt makes this hat both comfortable and elegant."
	icon_state = "beaver_hat"
	item_state_slots = list(slot_r_hand_str = "tophat", slot_l_hand_str = "tophat")
	siemens_coefficient = 0.9
	body_parts_covered = 0

/obj/item/clothing/head/boaterhat
	name = "boater hat"
	desc = "The ultimate in summer fashion."
	icon_state = "boater_hat"
	item_state_slots = list(slot_r_hand_str = "tophat", slot_l_hand_str = "tophat")
	body_parts_covered = 0

/obj/item/clothing/head/fedora
	name = "fedora"
	icon_state = "fedora_grey"
	desc = "A sharp, stylish hat that's grey in color."
	item_state_slots = list(slot_r_hand_str = "detective", slot_l_hand_str = "detective")
	body_parts_covered = 0

/obj/item/clothing/head/fedora/brown
	desc = "A brown fedora. Perfect for detectives or those trying to pilfer artifacts."
	icon_state = "fedora_brown"
	allowed = list(POCKET_SLEUTH)

/obj/item/clothing/head/fedora/white
	desc = "A white fedora, really cool hat if you're a mobster. A really lame hat if you're not."
	icon_state = "fedora_white"

/obj/item/clothing/head/fedora/beige
	desc = "A beige fedora. Either the cornerstone of a reporter's style or a poor attempt at looking cool. Depends on the person wearing it."
	icon_state = "fedora_beige"

/obj/item/clothing/head/fedora/panama
	desc = "A fancy, cream colored fedora. Columbian pure."
	icon_state = "fedora_panama"

/obj/item/clothing/head/trilby
	name = "trilby"
	icon_state = "trilby"
	item_state_slots = list(slot_r_hand_str = "detective", slot_l_hand_str = "detective")
	desc = "M'lady"

/obj/item/clothing/head/trilby/feather
	name = "feather trilby"
	icon_state = "feather_trilby"
	item_state_slots = list(slot_r_hand_str = "detective", slot_l_hand_str = "detective")
	desc = "A sharp, stylish hat with a feather."

/obj/item/clothing/head/fez
	name = "fez"
	icon_state = "fez"
	desc = "You should wear a fez. Fezzes are cool."

//Cowboy Hats

/obj/item/clothing/head/cowboy
	name = "cowboy hat"
	desc = "For those that have spurs that go jingle jangle jingle."
	icon_state = "cowboy_1"
	body_parts_covered = 0

/obj/item/clothing/head/cowboy/rattan
	name = "rattan cowboy hat"
	desc = "Made from the same straw harvested from the fields."
	icon_state = "cowboy_2"

/obj/item/clothing/head/cowboy/dark
	name = "dark cowboy hat"
	desc = "Protect yer head in this new frontier."
	icon_state = "cowboy_3"

/obj/item/clothing/head/cowboy/ranger
	name = "ranger cowboy hat"
	desc = "Feel the western vibe from this good ol' classic."
	icon_state = "cowboy_4"

/obj/item/clothing/head/cowboy/rustler
	name = "rustler cowboy hat"
	desc = "Rustle up some of that there cattle bucko."
	icon_state = "cowboy_5"

/obj/item/clothing/head/cowboy/black
	name = "black cowboy hat"
	desc = "Perfect for the budding tram robber."
	icon_state = "cowboy_7"

/obj/item/clothing/head/cowboy/fancy
	name = "fancy cowboy hat"
	desc = "Premium black leather had with a rattlesnake hatband to top the ensemble."
	icon_state = "cowboy_8"

/obj/item/clothing/head/cowboy/wide
	name = "wide-brimmed cowboy hat"
	desc = "Because justice isn't going to dispense itself."
	icon_state = "cowboy_6"

/obj/item/clothing/head/cowboy/bandit
	name = "bandit cowboy hat"
	desc = "You can almost hear the old western music."
	icon_state = "cowboy_9"

/obj/item/clothing/head/cowboy/small
	name = "small cowboy hat"
	desc = "For the tiniest of cowboys."
	icon_state = "cowboy_small"

/obj/item/clothing/head/wheat
	name = "straw hat"
	desc = "It's a hat made from synthetic straw. Brought to you by \"Country Girls LLC.\" the choice brand for the galaxy's working class."
	icon_state = "wheat"

//Ruin Marine (Doom Marine)
/obj/item/clothing/head/marine
	name = "marine helmet"
	desc = "A marine helmet prop from the popular game 'Ruin'."
	icon_state = "marine"
	flags_inv = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE|BLOCKHAIR
	body_parts_covered = HEAD|FACE|EYES

//Laser Tag Helmets
/obj/item/clothing/head/bluetag
	name = "blue laser tag helmet"
	desc = "Blue Pride, Station Wide."
	icon_state = "bluetag"
	flags_inv = HIDEEARS|BLOCKHEADHAIR
	body_parts_covered = HEAD|EYES

/obj/item/clothing/head/redtag
	name = "red laser tag helmet"
	desc = "Reputed to go faster."
	icon_state = "redtag"
	flags_inv = HIDEEARS|BLOCKHEADHAIR
	body_parts_covered = HEAD|EYES

/obj/item/clothing/head/omnitag
	name = "omni laser tag helmet"
	desc = "FIRST BLOOD!"
	icon_state = "marine"
	flags_inv = HIDEEARS|BLOCKHEADHAIR
	body_parts_covered = HEAD|EYES

//hair bows

/obj/item/clothing/head/bow
	name = "large bow"
	desc = "A large bow that you can place on top of your head."
	icon_state = "large_bow"
	body_parts_covered = 0

/obj/item/clothing/head/bow/small
	name = "small bow"
	desc = "A small compact bow that you can place on the side of your hair."
	icon_state = "small_bow"

/obj/item/clothing/head/bow/back
	name = "back bow"
	desc = "A large bow that you can place on the back of your head."
	icon_state = "back_bow"

/obj/item/clothing/head/bow/sweet
	name = "sweet bow"
	desc = "A sweet bow that you can place on the back of your head."
	icon_state = "sweet_bow"


// === merged from misc_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/head/wiggler
	icon_override = 'icons/vore/misc_ch.dmi'
	icon = 'icons/vore/misc_ch.dmi'//lets use our own DMI with blackjack and deers
	icon_state = "flailing_helmet"
	item_state = "flailing_helmet_worn"
	name = "Flailing hat"
	desc = "It's a hat, it flails."
	body_parts_covered = 0

/obj/item/clothing/head/wiggler/make_worn_icon(body_type,slot_name,inhands,default_icon,default_layer,icon/clip_mask = null)
	var/image/so_far = ..()
	so_far.pixel_y += 16
	so_far.pixel_x += 0
	return so_far

/obj/item/clothing/head/soft/purple/wah
	name = "assistant cap"
	desc = "What a lovely purple cap, its said its given out as a trophy to assistants. Why does that sound so depressing?"
	icon_state = "wahcap"
	item_state_slots = list(slot_r_hand_str = "wahcap", slot_l_hand_str = "wahcap")
	icon = 'icons/obj/clothing/hats_ch.dmi'
	icon_override = 'icons/mob/head.dmi'


/obj/item/clothing/head/crown //Generic crown doesnt exist, no sprites
	icon = 'icons/obj/clothing/hats_ch.dmi'
	icon_override = 'icons/mob/head.dmi'
	icon_state = "crown"
	item_state = "crown"
	name = "crown"
	desc = "A crown, it's pretty."
	body_parts_covered = 0

/obj/item/clothing/head/crown/goose_king
	name = "Crown of the golden goose king"
	desc = "It's the crown given to the goose king from the golden goose casino, what an honor!"
	icon = 'icons/obj/clothing/hats_ch.dmi'
	icon_override = 'icons/mob/head.dmi'
	icon_state = "goose_king"
	item_state = "goose_king"

/obj/item/clothing/head/crown/goose_king/christmas
	name = "Crown of the Goose King of Holiday Spirit"
	desc = "It's the crown from the golden goose casino of the Goose King! Given to the one to uphold christmas spirit on Southern Cross, merry christmas!"


/obj/item/clothing/head/crown/goose_queen
	name = "Crown of the golden goose queen"
	desc = "It's the crown given to the goose queen from the golden goose casino, what an honor!"
	icon = 'icons/obj/clothing/hats_ch.dmi'
	icon_override = 'icons/mob/head.dmi'
	icon_state = "goose_queen"
	item_state = "goose_queen"

/obj/item/clothing/head/crown/goose_queen/christmas
	name = "Crown of the Goose Queen of Holiday Cheer"
	desc = "It's the crown from the golden goose casino of the Goose Queen! Given to the one to spread christmas cheer on Southern Cross, happy holidays!"

/obj/item/clothing/head/pelt
	name = "Bear pelt"
	desc = "A luxurious bear pelt, good to keep warm in winter. Or to sleep through winter."
	icon = 'icons/obj/clothing/hats_ch.dmi'
	icon_override = 'icons/mob/head.dmi'
	icon_state = "bearpelt_brown"
	item_state = "bearpelt_brown"

/obj/item/clothing/head/pelt/black
	icon_state = "bearpelt_black"
	item_state = "bearpelt_black"

/obj/item/clothing/head/pelt/wolfpelt
	name = "Wolf pelt"
	desc = "A fuzzy wolf pelt, demanding respect as a hunter, well if it isn't synthetic or anything at least. Or bought."
	icon_override = 'icons/mob/wolfpelt_ch.dmi'
	icon_state = "wolfpelt_brown"
	item_state = "wolfpelt_brown"

/obj/item/clothing/head/pelt/wolfpeltblack
	name = "Wolf pelt"
	desc = "A fuzzy wolf pelt, demanding respect as a hunter, well if it isn't synthetic or anything at least. Or bought."
	icon_override = 'icons/mob/wolfpelt_ch.dmi'
	icon_state = "wolfpelt_gray"
	item_state = "wolfpelt_gray"

/obj/item/clothing/head/pelt/tigerpelt
	name = "Shiny tiger pelt"
	desc = "A vibrant tiger pelt, particularly fabulous."
	icon_state = "tigerpelt_shiny"
	item_state = "tigerpelt_shiny"

/obj/item/clothing/head/pelt/tigerpeltsnow
	name = "Snow tiger pelt"
	desc = "A pelt of a less vibrant tiger, but rather warm."
	icon_state = "tigerpelt_snow"
	item_state = "tigerpelt_snow"

/obj/item/clothing/head/pelt/tigerpeltpink
	name = "Pink tiger pelt"
	desc = "A particularly vibrant tiger pelt, for those who want to be the most fabulous at parties."
	icon_state = "tigerpelt_pink"
	item_state = "tigerpelt_pink"


// === merged from misc_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
//Angel Halo
/obj/item/clothing/head/angel_halo
	name = "Angel halo"
	desc = "A halo fashioned after classic depictions of an angel. It slowly pulses and rises."
	icon = 'icons/inventory/head/mob_angel_halo.dmi'
	default_worn_icon = 'icons/inventory/head/mob_angel_halo.dmi'
	icon_state = "angel_halo"
//Angel Halo End


// === merged from misc_vr.dm during hard-fork de-suffix (chain-verified, vr->ch order preserved) ===
/obj/item/clothing/head/centhat/customs
	desc = "A formal hat for SolGov Customs Officers." // SolGov

/obj/item/clothing/head/fish
	name = "fish skull"
	desc = "You... you're not actually going to wear that, right?"
	icon_state = "fishskull"
	flags_inv = HIDEEARS|BLOCKHAIR

/obj/item/clothing/head/crown
	name = "crown"
	desc = "How regal!"
	icon_state = "crown"

/obj/item/clothing/head/fancy_crown
	name = "fancy crown"
	desc = "How extraordinarily regal!"
	icon_state = "fancycrown"

/obj/item/clothing/head/shiny_hood
	icon_override = 'icons/mob/modular_shiny_vr.dmi'
	icon = 'icons/obj/clothing/modular_shiny_vr.dmi'
	name = "shiny hood"
	desc = "You can be a super-hero in this! Just don't forget your suit!"
	icon_state = "hood_o"
	flags_inv = HIDEFACE|BLOCKHAIR
	body_parts_covered = FACE|HEAD

/obj/item/clothing/head/shiny_hood/poly
	name = "polychromic shiny hood"
	icon_state = "hood_col_o"
	polychromic = TRUE

/obj/item/clothing/head/shiny_hood/closed
	name = "shiny hood"
	desc = "You can be a super-hero in this! Just don't forget your superhuman senses!"
	icon_state = "hood_c"
	gas_transfer_coefficient = 0.90

/obj/item/clothing/head/shiny_hood/closed/poly
	name = "polychromic closed shiny hood"
	icon_state = "hood_col"
	polychromic = TRUE

/obj/item/clothing/head/pelt
	name = "Bear pelt"
	desc = "A luxurious bear pelt, good to keep warm in winter. Or to sleep through winter."
	icon_state = "bearpelt_brown"
	item_state = "bearpelt_brown"

/obj/item/clothing/head/pelt/wolfpelt
	name = "Wolf pelt"
	desc = "A fuzzy wolf pelt, demanding respect as a hunter, well if it isn't synthetic or anything at least. Or bought."
	icon_override = 'icons/mob/wolfpelt_vr.dmi'
	icon_state = "wolfpelt_brown"
	item_state = "wolfpelt_brown"

/obj/item/clothing/head/pelt/wolfpeltblack
	name = "Wolf pelt"
	desc = "A fuzzy wolf pelt, demanding respect as a hunter, well if it isn't synthetic or anything at least. Or bought."
	icon_override = 'icons/mob/wolfpelt_vr.dmi'
	icon_state = "wolfpelt_gray"
	item_state = "wolfpelt_gray"

/obj/item/clothing/head/pelt/tigerpelt
	name = "Shiny tiger pelt"
	desc = "A vibrant tiger pelt, particularly fabulous."
	icon_state = "tigerpelt_shiny"
	item_state = "tigerpelt_shiny"

/obj/item/clothing/head/pelt/tigerpeltsnow
	name = "Snow tiger pelt"
	desc = "A pelt of a less vibrant tiger, but rather warm."
	icon_state = "tigerpelt_snow"
	item_state = "tigerpelt_snow"

/obj/item/clothing/head/pelt/tigerpeltpink
	name = "Pink tiger pelt"
	desc = "A particularly vibrant tiger pelt, for those who want to be the most fabulous at parties."
	icon_state = "tigerpelt_pink"
	item_state = "tigerpelt_pink"

/obj/item/clothing/head/pizzaguy
	name = "pizza delivery visor"
	desc = "A fancy visor showing alignment to pizza delivery service. Extremely risky career choice."
	icon_state = "pizzadelivery"
	item_state = "pizzadelivery"

/obj/item/clothing/head/fluff/names_pizza
	name = "pizza delivery hat"
	desc = "A hat fit for delivering pizzas! Smells of pepperoni and unpaid student debt."
	icon_state = "pizzadelivery_fluff"
	item_state = "pizzadelivery_fluff"

/obj/item/clothing/head/wedding
	name = "wedding veil"
	desc = "A lace veil worn over the face, typically by a bride during their wedding."
	icon_state = "weddingveil"

/obj/item/clothing/head/halo/alt
	name = "metal halo"
	desc = "A halo made of a light metal. This one doesn't float, but it's still a circle on your head!"
	icon_state = "halo_alt"

/obj/item/clothing/head/buckethat
	name = "bucket hat"
	desc = "Turns out these are actually called 'gatsby caps' but telling people you wear a bucket is slightly more interesting, so that's what it's called."
	icon_state = "buckethat"

/obj/item/clothing/head/nonla
	name = "non la"
	desc = "A conical hat typically woven from leaves, good for keeping the sun AND rain off your head, in case it happens to be sunny while raining."
	icon_state = "nonla"

//////////TALON HATS//////////

/obj/item/clothing/head/soft/talon
	name = "Talon baseball cap"
	desc = "It's a ballcap bearing the colors of ITV Talon."
	icon_state = "talonsoft"
	item_state = "talonsoft"
	item_state_slots = list(slot_r_hand_str = "blacksoft", slot_l_hand_str = "blacksoft")

/obj/item/clothing/head/caphat/talon
	name = "Talon nautical hat"
	desc = "It's a classic nautical hat bearing the colors of ITV Talon. Perfect for commanding the ship."
	icon_state = "talon_captain_cap"
	item_state = "taloncaptaincap"

/obj/item/clothing/head/soft/talon/refreshed
	name = "Talon cap"
	desc = "It's a standard dark blue baseball cap, it has the ITV Talon logo on the front proudly displayed."
	icon = 'icons/inventory/head/item.dmi'
	icon_override = 'icons/inventory/head/mob.dmi'
	icon_state = "talonnewsoft"
	item_state = "talonnewsoft"
	item_state_slots = list(slot_r_hand_str = "blacksoft", slot_l_hand_str = "blacksoft")

/obj/item/clothing/head/caphat/talon/refreshed
	name = "Talon captain's peaked cap"
	desc = "It's a parade cap usually worn by the ITV Talon's commanding officer, it displays power and discipline to whoever wears it."
	icon = 'icons/inventory/head/item.dmi'
	icon_override = 'icons/inventory/head/mob.dmi'
	icon_state = "talon_caphat"
	item_state = "talon_caphat"

/obj/item/clothing/head/caphat/talon/pilot
	name = "Talon pilot's cap"
	desc = "It's a formal cap worn usually by ITV Talon's piloting personnel, emblazoned with the ITV Talon's logo on the front of the cap."
	icon = 'icons/inventory/head/item.dmi'
	icon_override = 'icons/inventory/head/mob.dmi'
	icon_state = "talon_pilothat"
	item_state = "talon_pilothat"

/obj/item/clothing/head/beret/talon
	name = "Talon beret"
	desc = "It's a basic beret colored to match ITV Talon's uniforms."
	icon_state = "beret_talon"
	item_state = "baret_talon"

/obj/item/clothing/head/beret/talon/refreshed
	name = "Talon beret"
	desc = "It's a standard dark blue beret with nothing especially interesting on it."
	icon = 'icons/inventory/head/item.dmi'
	icon_override = 'icons/inventory/head/mob.dmi'
	icon_state = "talon_beret"
	item_state = "talon_beret"

/obj/item/clothing/head/beret/talon/command
	name = "Talon officer beret"
	desc = "It's a basic beret colored to match ITV Talon's uniforms with a badge pinned on the front. Perfect for commanders."
	icon_state = "beret_talon_officer"
	item_state = "baret_talon_command"


/obj/item/clothing/head/beret/talon/command/refreshed
	name = "Talon officer beret"
	desc = "It's a standard dark blue beret with the ITV Talon logo on the front proudly displayed."
	icon = 'icons/inventory/head/item.dmi'
	icon_override = 'icons/inventory/head/mob.dmi'
	icon_state = "talon_officer_beret"
	item_state = "talon_officer_beret"

// tiny tophat

/obj/item/clothing/head/tinytophat
	name = "tiny tophat"
	desc = "A tophat that is far too small to properly sit on someone's head!"
	icon_state = "tiny_tophat"

/obj/item/clothing/head/halo
	name = "holographic demonic halo"
	desc = "A hologram displaying a demonic halo."
	icon = 'icons/inventory/head/item.dmi'
	default_worn_icon = 'icons/inventory/head/mob_halo.dmi'
	icon_state = "halo"

/obj/item/clothing/head/halo/alt
	icon = 'icons/inventory/head/item.dmi'
	default_worn_icon = 'icons/inventory/head/mob.dmi'

//Replikant Hat

/obj/item/clothing/head/eulrhat
	name = "sleek side cap"
	desc = "A simple wedge cap with red accents, popular with biosynthetic personnel."
	icon_state = "eulrhat"
