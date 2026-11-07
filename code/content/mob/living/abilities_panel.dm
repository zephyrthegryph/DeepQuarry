// The abilities panel: the species, trait, mob-type and settings abilities of a mob (what the Abilities.* verb tabs were) in one command
// panel (code/library/ui/command_panel.dm). The abilities are procs of the mob that the species, trait or mob type grants as before; a proc
// with no `set category` is no tab entry (verb_panel_listed()), so the panel lists the ones the mob has been granted (PANEL_IF_GRANTED)
// and a player has one entry in the right-click menu on their own mob instead of a verb each.

GLOBAL_LIST_INIT(ability_panel_commands, list(
	panel_command("mob.living.carbon.human.proc.acidspit", "Toggle Acid Spit (50)", "Readies an acidic spit, which burns the target if they are not wearing protective gear.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.evolve", "Evolve (500)", "Produce an internal egg sac capable of spawning children. Only one queen can exist at a time.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.gut", "Slaughter", "While grabbing someone aggressively, rip their guts out or tear them apart.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lay_egg", "Lay Egg (500)", "Lay an egg that will eventually hatch into a new xenomorph larva. Life finds a way.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.leap", "Leap", "Leap at a target and grab them aggressively.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.neurotoxin", "Toggle Neurotoxic Spit (40)", "Readies a neurotoxic spit, which paralyzes the target for a short time if they are not wearing protective gear.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.plant", "Plant Weeds (50)", "Plants some alien weeds", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.plant_weak", "Plant Weeds (150)", "Plants some alien weeds.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.resin", "Secrete Resin (75)", "Secrete tough malleable resin.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.resin_weak", "Secrete Resin (25)", "Secrete tough, malleable resin in front of us.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.alraune_fruit_reagent", "Poison Fruit", "Select a reagent to be placed in your fruit.", "Alraune", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.alraune_fruit_select", "Select fruit", "Select what fruit/vegetable you wish to grow.", "Alraune", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.jumpstart", "Revive Host", "Send a jolt of electricity through your host, reviving them.", "Borer", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.proc.punish_host", "Torment host", "Punish your host with agony.", "Brainslug", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.proc.release_control", "Release Control", "Release control of your host's body.", "Brainslug", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.proc.spawn_larvae", "Reproduce", "Spawn several young.", "Brainslug", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.alienanimals.catslug.suslug.proc.assussinate", "Kill Innocent", "Kill an innocent suslug!", "Catslug", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.alien.diona.proc.merge", "Merge with gestalt", "Merge with another diona.", "Diona", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.alien.diona.proc.split", "Split from gestalt", "Split away from your gestalt as a lone nymph.", "Diona", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.diona_split_nymph", "Split", "Split your humanoid form into its constituent nymphs.", "Diona", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.gargoyle_checkenergy", "Gargoyle - Check Energy", "Check how much energy you have remaining as a gargoyle.", "Gargoyle", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.gargoyle_pause", "Gargoyle - Pause", "Pause your energy while standing still, so you don't use up any more, though you will lose a small amount upon moving again.", "Gargoyle", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.gargoyle_transformation", "Gargoyle - Petrification", "Turn yourself into (or back from) being a gargoyle.", "Gargoyle", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.bloodsuck", "Partially Drain prey of blood", "Bites prey and drains them of a significant portion of blood, feeding you in the process. You may only do this once per minute.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.commune", "Commune with creature", "Send a telepathic message to an unlucky recipient.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.regenerate", "Regenerate", "Allows you to regrow limbs and heal organs after a period of rest.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.self_diagnostics", "Self-Diagnostics", "Run an internal self-diagnostic to check for damage.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.sonar_ping", "Listen In", "Allows you to listen in to movement and noises around you.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.tackle", "Tackle", "Tackle someone down.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.toggle_eye_glow", "Toggle Eye Glowing", "Toggle Eye Glowing", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.toggle_pain_module", "Toggle pain simulation.", "Turn on your pain simulation for that organic experience! Or turn it off for repairs, or if it's too much.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.trait_tutorial", "Explain Custom Traits", "Click this verb to obtain a detailed tutorial on your selected traits. ", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.water_stealth", "Dive under water / Resurface", "Dive under water, allowing for you to be stealthy and move faster.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.flying_toggle", "Toggle Flight", "While flying over open spaces, you will use up some nutrition. If you run out nutrition, you will fall.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.glow_toggle", "Glow (Toggle)", "Toggle your glowing on/off!", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.hide", "Hide", "Allows to hide beneath tables or certain items. Toggled on or off.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.injection", "Injection", "Inject another being with something!", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.insect_sting", "Insect Sting", "Sting a target and inject a small amount of toxin", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.mobegglaying", "Egg laying", "you can lay Eggs", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.set_size", "Adjust Mass", "Adjust Mass", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.start_wings_hovering", "Hover", "Allows you to stop gliding and hover. This will take a fair amount of nutrition to perform.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_active_cloaking", "Toggle Active Cloaking", "Toggle Active Cloaking", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_pass_table", "Toggle Agility", "Allows you to start/stop hopping over things such as hydroponics trays, tables, and railings.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_patting_defence", "Toggle Reflexive Biting", "Toggles the automatic biting for if someone pats you on the head or boops your nose.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_personal_space", "Toggle Personal Space", "Toggles dodging any attempts to hug or pat you.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_pickup_dodge", "Toggle Pickup Dodge", "Toggles dodging any attempts to pick you up.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_rider_reins", "Give Reins", "Let people riding on you control your movement.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_thorns", "Toggle Thorns", "Toggles defensive thorns across your body.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.ventcrawl", "Crawl through Vent", "Enter an air vent and crawl through the pipe system.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.zorgoia.proc.appearance_switch", "Adjust Mob Markings", "Change your markings and mob colors.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.zorgoia.proc.recolor", "Change Color", "Change your main color.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.proc.toggle_motion_echo_vis", "Toggle Vibration Senses", "Toggle the visibility of pings revealed by vibration senses or motion trackers.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.leopardmander.exotic.proc.toggle_glow", "Toggle Glow", "Switch between glowing and not glowing.", "Leopardmander", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.hanner_beast_form", "Beast Form (100)", "Take the form of a non-humanoid creature.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_alchemy", "Alchemy (25)", "Convert a potion material into a potion without the use of a base or alembic.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_beast_form", "Beast Form (100)", "Take the form of a non-humanoid creature.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_contact", "Energy Transfer", "Take the energy of another creature by making physical contact with them, the other party must consent. This will make them feel drained.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_invisibility", "Invisibility (75)", "Change your appearance to match your surroundings, becoming completely invisible to the naked eye.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_rings", "Place/Use Rings", "Place or teleport to a glamour ring.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_select_colour", "Select Body Colour", "Select Body Colour", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_select_shape", "Select Body Shape", "Select Body Shape", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.lleill_transmute", "Transmute Object (50)", "Convert an object into a piece of glamour.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.revert_beast_form", "Revert Beast Form", "Return to your humanoid form.", "Lleill", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.acidspit", "Toggle Acid Spit", "Readies an acidic spit, which burns the target if they are not wearing protective gear.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.hunting_vision", "Track Prey Through Walls", "Uses you natural predatory instincts to seek out prey even through walls, or your natural survival instincts to spot predators from a distance.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.leap", "Pounce Target", "Select a target to pounce at.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.neurotoxin", "Toggle Neurotoxic Spit", "Readies a neurotoxic spit, which paralyzes the target for a short time if they are not wearing protective gear.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.pounce_toggle", "Toggle Pouncing", "Toggle pouncing. Doubleclick to pounce.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.use_headset", "Use Headset", "Opens your headset's GUI, if you have one.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.use_pda", "Use PDA", "Opens your PDA's GUI, if you have one.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.morph.proc.take_over_prey", "Take Over Prey", "Take command of your prey's body.", "Morph", null, PANEL_IF_GRANTED),
	panel_command("mob.living.silicon.pai.proc.choose_chassis", "Choose Chassis", "Choose Chassis", "pAI Commands", null, PANEL_IF_GRANTED),
	panel_command("mob.living.silicon.pai.proc.choose_verbs", "Choose Speech Verbs", "Choose Speech Verbs", "pAI Commands", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.prommie_blobform", "Toggle Blobform", "Switch between amorphous and humanoid forms.", "Promethean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.prommie_select_colour", "Select Body Colour", "Select Body Colour", "Promethean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.prommie_toggle_expand", "Toggle Width", "Switch between smole and lorge.", "Promethean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.prommie_toggle_shine", "Toggle Shine", "Shine on you crazy diamond.", "Promethean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.absorb_implant", "Absorb Implant", "Absorb Implant", "Protean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.chest_transparency_toggle", "transparency toggle (chest only)", "transparency toggle (chest only)", "Protean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.nano_change_fitting", "Change Species Fit", "Tweak your shape to change what suits you fit into (and their sprites!).", "Protean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.prot_hide", "Hide Self", "Disperses your mass into a thin veil, making a trap to snatch prey with, or simply hide.", "Protean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.transparency_toggle", "Toggle Transparency", "Toggle Transparency", "Protean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.usehardsuit", "Utilize Hardsuit Interface", "Allows a protean to open its hardsuit interface.", "Protean", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.radiation_control_panel", "Radiation Control Panel", "Allows you to adjust the settings of various radioactive settings!", "Radiation", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.sect_drone.proc.set_abdomen_color", "Set Glow Color", "Customize your eyes and abdomen glow color.", "Sect Drone", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.sect_queen.proc.set_abdomen_color", "Set Glow Color", "Customize your eyes and abdomen glow color.", "Sect Queen", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.glow_color", "Glow (Set Color)", "Pick a color for your body's glow.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.ColorMate", "Recolour", "Allows to recolour once.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.choose_gender", "Set Gender", "Set your gender.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.pick_color", "Pick Color", "You can set your color!", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.pick_size", "Pick Size", "Pick Size", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.set_desc", "Set Description", "Set your description.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.set_name", "Set Name", "Sets your mobs name. You only get to do this once.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.alienanimals.catslug.proc.catslug_color", "Pick Color", "You can set your color!", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.export_style", "Export style string", "Export a string of text that can be used to instantly get the current style back using the import style verb", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.flame_toggle", "Toggle breath attack", "Toggles whether you will breath attack on harm intent (If you have one).", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.import_style", "Import style string", "Import a string of text that was made using the import style verb to get back that style", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.set_style", "Set Dragon Style", "Customise your icons.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.special_toggle", "Toggle special attacks", "Toggles whether you will tail spin and charge (If you have them).", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.sprite_toggle", "Toggle Small Sprite", "Switches your sprite to a smaller variant so you can see what you're doing. Others will always see your standard sprite instead. ", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.bigdragon.proc.toggle_glow", "Toggle Glow", "Switch between glowing and not glowing.", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.morph.proc.morph_color", "Pick Color", "You can set your color!", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.retaliate.lion.proc.pick_mane_color", "Set Mane Color", "Set the color of your mane", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.retaliate.lion.proc.set_sex", "Set Sex", "Set what sprite set you use (male/female)", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.zorgoia.proc.export_style", "Export style string", "Export a string of text that can be used to instantly get the current style back using the import style verb", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.zorgoia.proc.import_style", "Import style string", "Import a string of text that was made using the import style verb to get back that style", "Settings", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.shadekin_control_panel", "Shadekin Control Panel", "Allows you to adjust the settings of various shadekin settings!", "Shadekin", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.promethean_select_opaqueness", "Toggle Transparency", "Toggle Transparency", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_copy_body", "Copy Form", "If you are aggressively grabbing someone, with their consent, you can turn into a copy of them. (Without their name).", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_reassemble", "Complete Reform", "Complete Reform", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_regenerate", "Fully Reform", "Reload your appearance from whatever character slot you have loaded.", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_colour", "Select Body Colour", "Select Body Colour", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_ears", "Select Ears", "Select Ears", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_eye_colour", "Select Eye Color", "Select Eye Color", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_gender", "Select Gender", "Select Gender", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_hair", "Select Hair", "Select Hair", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_hair_colors", "Select Hair Colors", "Select Hair Colors", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_secondary_ears", "Select Secondary Ears", "Select Secondary Ears", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_shape", "Select Body Shape", "Select Body Shape", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_tail", "Select Tail", "Select Tail", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshifter_select_wings", "Select Wings", "Select Wings", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.shapeshift_form", "Shapeshift Form", "Shape shift between set mob forms. (Requires a spawned mob to be varedited into the user's tf_form var as mob reference.)", "Shapeshift", null, PANEL_IF_GRANTED),
	panel_command("mob.living.silicon.robot.proc.robot_panel", "Silicon Panel", "Every cyborg command and subsystem in one window.", "Silicon", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.play_dead", "Play Dead", "Literally just die on the spot. It's okay, you can get better.", "Sparkledog", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.healing_rainbows", "Firin Mah Lazor", "Fire a glowing beam of rainbows at another person to heal them!", "Sparkledog", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_sparkles", "Toggle Sparkles", "Toggle fancy glowing sparkles!", "Sparkledog", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.succubus_drain", "Drain prey of nutrition", "Slowly drain prey of all the nutrition in their body, feeding you in the process. You may only do this to one person at a time.", "Succubus", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.succubus_drain_finalize", "Drain/Feed Finalization", "Toggle to allow for draining to be prolonged. Turn this on to make it so prey will be knocked out/die while being drained, or you will feed yourself to the prey's selected stomach if you're feeding them. Can be toggled at any time.", "Succubus", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.succubus_drain_lethal", "Lethally drain prey", "Slowly drain prey of all the nutrition in their body, feeding you in the process. Once prey run out of nutrition, you will begin to drain them lethally. You may only do this to one person at a time.", "Succubus", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.succubus_bite", "Inject Prey", "Bite prey and inject them with various toxins.", "Succubus", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.innate_shapeshifting", "Transform Appearance", "Transform Appearance", "Superpowers", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.remoteobserve", "Remote View", "Remote View", "Superpowers", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.remotesay", "Project mind", "Project mind", "Superpowers", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.shapeshfit_form", "Transform Shape", "Transform Shape", "Superpowers", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.name_change_verb", "Change Name", "Change your name. Notifies admins.", "Superpowers", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.proc.disguise", "Toggle Form", "Switch between amorphous and humanoid forms.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.proc.distend_stomach", "Distend Stomach", "Allows you to throw up your stomach, giving your attacks burn damage at the cost of your stomach contents going everywhere. Yuck.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.proc.randomspeech", "speak", "Take a sentence you heard and speak it.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.proc.set_style", "Set Style", "Customise your icons.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.proc.sonar_ping", "Listen In", "Allows you to listen in to movement and noises around you.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.contort", "contort", "Allows to hide beneath tables or certain items. Toggled on or off.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.alienanimals.teppi.proc.produce_offspring", "Produce Offspring", "You can have babies if the conditions are right.", "Teppi", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.vore.alienanimals.teppi.proc.toggle_producing_offspring", "Toggle Producing Offspring", "You can toggle whether or not you can produce offspring.", "Teppi", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.slime_feed", "Feed prey with self", "Slowly feed prey with your body, draining you in the process. You may only do this to one person at a time.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.synth_reag_toggle", "Toggle Reagent Processing", "Toggle reagent processing as synth.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.underwater_devour", "Devour From Water", "Grab something in the water with you and devour them with your selected stomach.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.dominate_prey", "Dominate Prey", "Connect to and dominate the brain of your prey.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.eat_minerals", "Eat Minerals", "Consume held raw ore, gems and refined minerals. Snack time!", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.eat_trash", "Eat Trash", "Consume held garbage.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.flying_vore_toggle", "Toggle Flight Vore", "Allows you to engage in voracious misadventures while flying.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.lend_prey_control", "Give Prey Control", "Allow prey control of your body.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.long_vore", "Grab Prey With Appendage", "Grab a target with any of your appendages!", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.restrict_trasheater", "Restrict Trash Eater", "Toggle Trash Eater restriction level.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.shred_limb", "Damage/Remove Prey's Organ", "Severely damages prey's organ. If the limb is already severely damaged, it will be torn off.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.shred_limb_temp", "Damage/Remove Prey's Organ (beartrap)", "Severely damages prey's organ. If the limb is already severely damaged, it will be torn off.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.target_lunge", "Lunge At Prey", "Dive atop your prey and gobble them up!", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_stuffing_mode", "Toggle feeding mode", "Switch whether you will try to feed other people food whole or normally, bite by bite.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.toggle_trash_catching", "Toggle Trash Catching", "Toggle Trash Eater throw vore abilities.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.vertical_nom", "Nom from Above", "Allows you to eat people who are below your tile or adjacent one. Requires passability.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.proc.dominate_predator", "Dominate Predator", "Connect to and dominate the brain of your predator.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.proc.release_predator", "Restore Control", "Release control of your predator's body.", "Vore", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.fake_exit_vr", "Log Out Of Virtual Reality", "Log Out Of Virtual Reality", "VR", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.perform_exit_vr", "Exit Virtual Reality", "Exit Virtual Reality", "VR", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.vr_transform_into_mob", "Transform Into Creature", "Become a different creature", "VR", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.vr_revert_mob_tf", "Revert Transformation", "Revert Transformation", "VR", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.enter_cocoon", "Spin Cocoon", "Spin Cocoon", "Weaver", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.weaver_control_panel", "Weaver Control Panel", "Allows you to adjust the settings of various weaver settings!", "Weaver", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.hatch", "Hatch", "Hatch", "Xenochimera", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.reconstitute_form", "Reconstitute Form", "Reconstitute Form", "Xenochimera", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.convert_to_rev", "Convert Bourgeoise", "Ask someone nearby to join the revolution.", "Antag", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_oview_mobs)),
	panel_command("mob.living.proc.convert_to_loyalist", "Convert Recidivist", "Ask someone nearby to side with the station again.", "Antag", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_oview_mobs)),
	panel_command("mob.living.carbon.human.proc.psychic_whisper", "Psychic Whisper", "Whisper silently to someone over a distance.", "General", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_oview_mobs)),
	panel_command("mob.living.carbon.human.proc.telepathy", "Project Mind", "Talk telepathically to someone over a distance.", "General", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_oview_mobs)),
	panel_command("mob.living.carbon.human.proc.lick_wounds", "Lick Wounds", "Disinfect and heal small wounds with your saliva.", "General", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_touchable_carbon)),
	panel_command("mob.living.carbon.human.proc.taur_mount", "Taur Mount/Dismount", "Let people ride on you.", "General", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_mountable)),
	panel_command("mob.living.carbon.human.proc.check_plasma_amount", "Check Plasma Reserves", "See how much plasma you have stored.", "Alien", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.human.proc.transfer_plasma", "Transfer Plasma", "Transfer plasma to another alien.", "Alien", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_oview_humans)),
	panel_command("mob.living.carbon.human.proc.corrosive_acid", "Corrosive Acid (200)", "Drench an object in acid, destroying it over time.", "Alien", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_acid)),
	panel_command("mob.living.simple_mob.proc.corrosive_acid", "Corrosive Acid", "Drench an object in acid, destroying it over time.", "Mob", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_acid)),
	panel_command("mob.living.simple_mob.proc.speen", "Spin Attack", "Spins to strike enemies away from you.", "Mob", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.proc.animal_mount", "Animal Mount/Dismount", "Let people ride on you.", "Mob", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_mountable)),
	panel_command("mob.living.simple_mob.proc.animal_nom", "Animal Nom", "Eat someone next to you.", "Vore", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_nearby_living)),
	panel_command("mob.living.silicon.pai.proc.pai_nom", "pAI Nom", "Allows you to eat someone while unfolded. Can't be used while in card form.", "pAI Commands", null, PANEL_IF_GRANTED, TYPE_PROC_REF(/mob/living, panel_targets_nearby_living)),
	panel_command("mob.living.simple_mob.vore.blaidd.proc.blaidd_invis", "Invisibility", "Change your appearance to match your surroundings, becoming somewhat invisible to the naked eye.", "Glamour", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.glamour_invisibility", "Invisibility", "Change your appearance to match your surroundings, becoming completely invisible to the naked eye.", "Glamour", null, PANEL_IF_GRANTED),
	panel_command("mob.living.proc.polymorph", "Polymorph", "Take the form of a non-humanoid creature.", "Glamour", null, PANEL_IF_GRANTED),
	panel_command("mob.living.carbon.alien.proc.evolve", "Evolve", "Evolve into your adult form.", "General", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.passive.mouse.proc.set_mouse_colour", "Set Mouse Colour", "Set the colour of your mouse.", "Mouse", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.ai.pet.debug.proc.rename", "Rename", "Renames the synx.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.ai.pet.debug.proc.redesc", "Redescribe", "Redescribes the synx.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("mob.living.simple_mob.animal.synx.ai.pet.debug.proc.resprite", "Resprite", "Resprites the synx.", "Synx", null, PANEL_IF_GRANTED),
	panel_command("integrated_communicator", "Use Communicator", "Utilizes your built-in communicator.", "Silicon", TYPE_PROC_REF(/mob/living, use_integrated_communicator), TYPE_PROC_REF(/mob/living, has_integrated_communicator)),
	panel_command("integrated_pda", "Use PDA", "Utilizes your built-in PDA.", "Silicon", TYPE_PROC_REF(/mob/living, use_integrated_pda), TYPE_PROC_REF(/mob/living, has_integrated_pda)),
))

/// The Abilities menu entry: opens the abilities panel of the mob.
/mob/living/proc/abilities_panel_chosen(datum/act/op/A)
	command_panel_open(src, "abilities", "Abilities", GLOB.ability_panel_commands)
	return OP_OK

// What the ability commands that took an `M as mob in oview()` argument can be used on: the panel asks the owner to pick one of these.

/// Every mob in view of the owner, but not the owner.
/mob/living/proc/panel_targets_oview_mobs()
	. = list()
	for(var/mob/M in oview(src))
		. += M

/// Every human in view of the owner, but not the owner.
/mob/living/proc/panel_targets_oview_humans()
	. = list()
	for(var/mob/living/carbon/human/H in oview(src))
		. += H

/// The living carbon mobs within one tile (the owner included, who may lick their own wounds).
/mob/living/proc/panel_targets_touchable_carbon()
	. = list()
	for(var/mob/living/carbon/C in view(1, src))
		. += C

/// Who can climb on: the living mobs next to the owner; with riders already up, the owner itself, since the command then sends the riders off.
/mob/living/proc/panel_targets_mountable()
	if(LAZYLEN(buckled_mob_list()))
		return list(src)
	return living_mobs(1)

/// The living mobs within one tile that can be eaten.
/mob/living/proc/panel_targets_nearby_living()
	return living_mobs_in_view(1)

/// The objects and turfs within one tile that acid can be spat on.
/mob/living/proc/panel_targets_acid()
	. = list()
	for(var/atom/A in oview(1, src))
		if(isobj(A) || isturf(A))
			. += A

/// Does this mob carry an integrated communicator? (A silicon's own; the abilities panel lists the command for those only.)
/mob/living/proc/has_integrated_communicator(id)
	return !!integrated_communicator_item()

/// Does this mob carry an integrated PDA?
/mob/living/proc/has_integrated_pda(id)
	return !!integrated_pda_item()

/// The integrated communicator of this mob, or null: a silicon names its own.
/mob/living/proc/integrated_communicator_item()
	return null

/// The integrated PDA of this mob, or null.
/mob/living/proc/integrated_pda_item()
	return null

/mob/living/silicon/ai/integrated_communicator_item()
	return aiCommunicator

/mob/living/silicon/ai/integrated_pda_item()
	return aiPDA

/mob/living/silicon/robot/integrated_communicator_item()
	return communicator

/mob/living/silicon/robot/integrated_pda_item()
	return rbPDA

/mob/living/silicon/pai/integrated_communicator_item()
	return communicator

/mob/living/silicon/pai/integrated_pda_item()
	return pda

/// Opens the integrated communicator.
/mob/living/proc/use_integrated_communicator()
	var/obj/item/communicator/integrated/communicator_item = integrated_communicator_item()
	if(!communicator_item)
		return
	communicator_item.use_by(src)

/// Opens the integrated PDA.
/mob/living/proc/use_integrated_pda()
	var/obj/item/pda/ai/pda_item = integrated_pda_item()
	if(!pda_item)
		return
	pda_item.open_for(src)
