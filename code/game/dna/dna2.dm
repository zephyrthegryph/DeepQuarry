// What each index means:
#define DNA_OFF_LOWERBOUND 1
#define DNA_OFF_UPPERBOUND 2
#define DNA_ON_LOWERBOUND  3
#define DNA_ON_UPPERBOUND  4

// Traitgenes Genes accessible by global VV, and lists for good and bad mutations for quick randomized selection of traitgenes. Removed dna from gene's path
GLOBAL_LIST_EMPTY_TYPED(dna_genes, /datum/gene)
GLOBAL_LIST_EMPTY(trait_to_dna_genes) // Reverse lookup genes, use get_gene_from_trait(var/trait_path) to read this
GLOBAL_LIST_EMPTY_TYPED(dna_genes_good, /datum/gene/trait)
GLOBAL_LIST_EMPTY_TYPED(dna_genes_neutral, /datum/gene/trait)
GLOBAL_LIST_EMPTY_TYPED(dna_genes_bad, /datum/gene/trait)

/proc/get_gene_from_trait(trait_path) // ALWAYS USE THIS
	RETURN_TYPE(/datum/gene/trait)
	var/G = GLOB.trait_to_dna_genes[trait_path]
	#ifndef UNIT_TESTS
	if(!G) // This SHOULD NOT HAPPEN, be sure any viruses or injectors that give trait paths are actually traitgenes.
		stack_trace("[trait_path] was used as a traitgene, without being flagged as one.")
	#endif
	return G

/datum/dna
	// unique_enzymes is the only piece of "encoded" identity actually stored: the
	// hex-encoded uni_identity/struc_enzymes strings used to be materialized here
	// too, duplicating the SE[]/UI[] block arrays below (the canonical storage) in
	// string form. They are now derived on demand -- see GetUniIdentity() /
	// GetStrucEnzymes() / SetUniIdentity() / SetStrucEnzymes() further down. Do not
	// re-add uni_identity/struc_enzymes as stored vars; route through those procs.
	var/unique_enzymes="" // MD5 of player name

	/// TRUE once SE[]/UI[] hold real data (via ResetSE()/ResetUIFrom()/ready_dna()/
	/// SetStrucEnzymes()/SetUniIdentity()). Replaces the old check of whether the
	/// now-removed struc_enzymes/uni_identity cache strings were still their blank
	/// "" default -- see check_integrity() below.
	var/dna_ready = FALSE

	// Okay to read, but you're an idiot if you do.
	// BLOCK = VALUE
	var/list/SE[DNA_SE_LENGTH] // ALLOW(instance_list): d: fixed-size DNA block list, always filled
	var/list/UI[DNA_UI_LENGTH] // ALLOW(instance_list): d: fixed-size DNA block list, always filled

	// From old dna.
	var/b_type = DEFAULT_BLOOD_TYPE  // Should probably change to an integer => string map but I'm lazy.
	var/real_name          // Stores the real name of the person who originally got this dna datum. Used primarily for changelings,

	var/custom_species
	var/base_species = SPECIES_HUMAN
	var/list/species_traits
	var/blood_color = "#A10808"
	var/blood_reagents = "iron"
	var/scale_appearance = 0
	var/offset_override = 0
	var/synth_markings = 0
	var/custom_speech_bubble = "default"
	var/species_sounds = "None"
	var/gender_specific_species_sounds = FALSE
	var/species_sounds_male = "None"
	var/species_sounds_female = "None"
	var/custom_say
	var/custom_ask
	var/custom_whisper
	var/custom_exclaim
	var/list/custom_heat
	var/list/custom_cold
	var/digitigrade = 0 //0, Not FALSE, for future use as indicator for digitigrade types
	var/custom_footstep = FOOTSTEP_MOB_SHOE

	// New stuff
	var/species = SPECIES_HUMAN
	var/list/body_markings

// Make a copy of this strand.
// USE THIS WHEN COPYING STUFF OR YOU'LL GET CORRUPTION!
// Can you imagine, this used to be done manually, var by var?
/datum/dna/proc/Clone()
	var/datum/dna/new_dna = new()
	for(var/A in vars)
		switch(A)
			if(BLACKLISTED_COPY_VARS)
				continue
			if("body_markings")
				var/list/body_markings_genetic = LAZYCOPY(body_markings)
				body_markings_genetic -= GLOB.body_marking_nopersist_list
				new_dna.vars[A] = body_markings_genetic // ALLOW(api): DNA copy: every var of the record
				continue
		if(islist(vars[A]))
			var/list/L = vars[A]
			new_dna.vars[A] = L.Copy() // ALLOW(api): DNA copy: every var of the record
			continue
		new_dna.vars[A] = vars[A] // ALLOW(api): DNA copy: every var of the record
	// uni_identity/struc_enzymes are derived from UI[]/SE[] on demand (see
	// GetUniIdentity()/GetStrucEnzymes() below) and were copied above along with
	// the rest of vars, so there is nothing further to refresh here.
	return new_dna

///////////////////////////////////////
// UNIQUE IDENTITY
///////////////////////////////////////

// Create random UI.
/datum/dna/proc/ResetUI(defer=0)
	for(var/i=1,i<=DNA_UI_LENGTH,i++)
		switch(i)
			if(DNA_UI_SKIN_TONE)
				SetUIValueRange(DNA_UI_SKIN_TONE,rand(1,220),220,1) // Otherwise, it gets fucked
			else
				set_UI_at(i, rand(0,4095))
	if(!defer)
		UpdateUI()

/**
 * Beginning of mob to dna, and dna to mob transfer procs.
 * Ensure that ResetUIFrom() and ApplyToMob() mirror each other. All vars should be read FROM the mob, and written back to it!
 * ALL dna logic for reading from the mob, storing the dna data, and writing that dna data back to the mob should be here, and ONLY here.
 */
/datum/dna/proc/ResetUIFrom(mob/living/carbon/human/character)
	// INITIALIZE!
	ResetUI(1)
	// Hair
	// FIXME:  Species-specific defaults pls
	if(!character.looks.hair_style)
		character.looks.set_hair_style("Skinhead")
	var/hair = GLOB.hair_styles_list.Find(character.looks.hair_style)

	// Facial Hair
	if(!character.looks.facial_style)
		character.looks.set_facial_style("Shaved")
	var/beard	= GLOB.facial_hair_styles_list.Find(character.looks.facial_style)



	// Demi Ears
	var/ear_style = 0
	if(character.ear_style)
		ear_style = GLOB.ear_styles_list.Find(character.ear_style.type)

	var/ear_secondary_style = 0
	if(character.ear_secondary_style)
		ear_secondary_style = GLOB.ear_styles_list.Find(character.ear_secondary_style.type)

	// Demi Tails
	var/tail_style = 0
	if(character.tail_style)
		tail_style = GLOB.tail_styles_list.Find(character.tail_style.type)

	// Demi Wings
	var/wing_style = 0
	if(character.wing_style)
		wing_style = GLOB.wing_styles_list.Find(character.wing_style.type)

	// Hairgrad
	var/grad_style = 0
	if(character.looks.grad_style)
		grad_style = GLOB.hair_gradients.Find(character.looks.grad_style)

	// Playerscale (This assumes list is sorted big->small)
	var/size_multiplier = GLOB.player_sizes_list.len // If fail to find, take smallest
	for(var/N in GLOB.player_sizes_list)
		if(character.size_multiplier >= GLOB.player_sizes_list[N])
			size_multiplier = GLOB.player_sizes_list.Find(N)
			break

	// Technically custom_species is not part of the UI, but this place avoids merge problems.
	src.custom_species = character.custom_species
	src.base_species = character.species.base_species
	src.blood_color = character.species.blood_color
	src.blood_reagents = character.species.blood_reagents
	src.scale_appearance = character.fuzzy
	src.offset_override = character.offset_override
	src.synth_markings = character.looks.synth_markings
	src.custom_speech_bubble = character.custom_speech_bubble
	src.species_sounds = character.species.species_sounds
	src.gender_specific_species_sounds = character.species.gender_specific_species_sounds
	src.species_sounds_male = character.species.species_sounds_male
	src.species_sounds_female = character.species.species_sounds_female
	src.species_traits = character.species.traits.Copy()
	src.custom_say = character.bio.custom_say
	src.custom_ask = character.bio.custom_ask
	src.custom_whisper = character.bio.custom_whisper
	src.custom_exclaim = character.bio.custom_exclaim
	src.custom_heat = sparse_get(character, custom_heat)
	src.custom_cold = sparse_get(character, custom_cold)
	src.digitigrade = character.looks.digitigrade
	src.custom_footstep = character.custom_footstep

	// +1 to account for the none-of-the-above possibility
	SetUIValueRange(DNA_UI_EAR_STYLE,             ear_style + 1,               GLOB.ear_styles_list.len  + 1,  1)
	SetUIValueRange(DNA_UI_EAR_SECONDARY_STYLE,	  ear_secondary_style + 1,     GLOB.ear_styles_list.len  + 1,  1)
	SetUIValueRange(DNA_UI_TAIL_STYLE,	          tail_style + 1,              GLOB.tail_styles_list.len + 1,  1)
	SetUIValueRange(DNA_UI_PLAYERSCALE,           size_multiplier,             GLOB.player_sizes_list.len,     1)
	SetUIValueRange(DNA_UI_WING_STYLE,            wing_style + 1,              GLOB.wing_styles_list.len + 1,  1)
	SetUIValueRange(DNA_UI_GRAD_STYLE,            grad_style,			  	   GLOB.hair_gradients.len,  1)

	SetUIColour(DNA_UI_TAIL_R, character.looks.tail_color)

	SetUIColour(DNA_UI_TAIL2_R, character.looks.tail_color2)

	SetUIColour(DNA_UI_TAIL3_R, character.looks.tail_color3)
	SetUIValueRange(DNA_UI_TAIL_ALPHA,character.looks.tail_alpha,    255,    1)

	SetUIColour(DNA_UI_WING_R, character.looks.wing_color)

	SetUIColour(DNA_UI_WING2_R, character.looks.wing_color2)

	SetUIColour(DNA_UI_WING3_R, character.looks.wing_color3)
	SetUIValueRange(DNA_UI_WING_ALPHA, character.looks.wing_alpha,   255,    1)

	SetUIColour(DNA_UI_EARS_R, character.looks.ears_color)

	SetUIColour(DNA_UI_EARS2_R, character.looks.ears_color2)

	SetUIColour(DNA_UI_EARS3_R, character.looks.ears_color3)
	SetUIValueRange(DNA_UI_EARS_ALPHA,character.looks.ears_alpha,    255,    1)

	SetUIColour(DNA_UI_GRAD_R, character.looks.grad_color)

	for(var/channel in 1 to DNA_UI_EARS_SECONDARY_COLOR_CHANNEL_COUNT)
		var/offset = DNA_UI_EARS_SECONDARY_START + (channel - 1) * 3
		var/list/read_rgb = ReadRGB(LAZYACCESS(character.ear_secondary_colors, channel) || "#ffffff")
		var/red = read_rgb[1]
		var/green = read_rgb[2]
		var/blue = read_rgb[3]
		SetUIValueRange(offset, red, 255, 1)
		SetUIValueRange(offset + 1, green, 255, 1)
		SetUIValueRange(offset + 2, blue, 255, 1)
	SetUIValueRange(DNA_UI_EARS_SECONDARY_ALPHA, character.looks.ears_alpha2, 255, 1)

	SetUIColour(DNA_UI_HAIR_R, character.looks.hair_color)

	SetUIColour(DNA_UI_BEARD_R, character.looks.facial_color)

	SetUIColour(DNA_UI_EYES_R, character.looks.eyes_color)

	SetUIColour(DNA_UI_SKIN_R, character.looks.skin_color)

	SetUIValueRange(DNA_UI_SKIN_TONE, 35-character.looks.skin_tone, 220,    1) // Value can be negative.

	SetUIState(DNA_UI_GENDER,         character.gender!=MALE,        1)

	SetUIValueRange(DNA_UI_HAIR_STYLE,  hair,  GLOB.hair_styles_list.len,       1)
	SetUIValueRange(DNA_UI_BEARD_STYLE, beard, GLOB.facial_hair_styles_list.len,1)

	LAZYCLEARLIST(body_markings)
	for(var/obj/item/organ/external/E in character.organs)
		if(LAZYLEN(E.markings))
			LAZYSET(body_markings, E.organ_tag, E.markings.Copy())

	UpdateUI()
	dna_ready = TRUE

/datum/dna/proc/ApplyToMob(mob/living/carbon/human/H)
	////////////////////////////////////////////////////////////////////////////////
	// Apply UIs to character
	//Hair color
	H.looks.set_hair_color(GetUIColour(DNA_UI_HAIR_R))

	//Facial hair color
	H.looks.set_facial_color(GetUIColour(DNA_UI_BEARD_R))

	//Skin color (Tone for humans is seperate)
	H.looks.set_skin_color(GetUIColour(DNA_UI_SKIN_R))

	H.looks.set_skin_tone(35 - GetUIValueRange(DNA_UI_SKIN_TONE, 220))// Value can be negative.

	//Eye color
	H.looks.set_eyes_color(GetUIColour(DNA_UI_EYES_R))

	//Hair gradient color
	H.looks.set_grad_color(GetUIColour(DNA_UI_GRAD_R))

	//Sex... Needs future support for properly handling things other then just male/female. UIs have the capability to do so!
	if(H.gender != NEUTER)
		if (GetUIState(DNA_UI_GENDER))
			H.set_gender(FEMALE)
		else
			H.set_gender(MALE)

	//Body markings
	for(var/tag in body_markings)
		var/obj/item/organ/external/E = H.organs_by_name[tag]
		if(E)
			var/list/marklist = LAZYACCESS(body_markings, tag)
			E.set_markings(marklist.Copy())

	//Hair style
	var/hair = GetUIValueRange(DNA_UI_HAIR_STYLE,GLOB.hair_styles_list.len)
	if((0 < hair) && (hair <= GLOB.hair_styles_list.len))
		H.looks.set_hair_style(GLOB.hair_styles_list[hair])

	//Facial Hair
	var/beard = GetUIValueRange(DNA_UI_BEARD_STYLE,GLOB.facial_hair_styles_list.len)
	if((0 < beard) && (beard <= GLOB.facial_hair_styles_list.len))
		H.looks.set_facial_style(GLOB.facial_hair_styles_list[beard])

	// Ears
	var/ears = GetUIValueRange(DNA_UI_EAR_STYLE, GLOB.ear_styles_list.len + 1) - 1
	if(ears < 1)
		rel_set(H, nameof(H.ear_style), null)
	else if((0 < ears) && (ears <= GLOB.ear_styles_list.len))
		rel_set(H, nameof(H.ear_style), GLOB.ear_styles_list[GLOB.ear_styles_list[ears]])
	var/ears_secondary = GetUIValueRange(DNA_UI_EAR_SECONDARY_STYLE, GLOB.ear_styles_list.len + 1) - 1
	if(ears_secondary < 1)
		rel_set(H, nameof(H.ear_secondary_style), null)
	else if((0 < ears_secondary) && (ears_secondary <= GLOB.ear_styles_list.len))
		rel_set(H, nameof(H.ear_secondary_style), GLOB.ear_styles_list[GLOB.ear_styles_list[ears_secondary]])

	// Ear Color
	H.looks.set_ears_color(rgb(GetUIValueRange(DNA_UI_EARS_R,    255), GetUIValueRange(DNA_UI_EARS_G,    255), GetUIValueRange(DNA_UI_EARS_B, 	  255)))
	H.looks.set_ears_color2(rgb(GetUIValueRange(DNA_UI_EARS2_R,   255), GetUIValueRange(DNA_UI_EARS2_G,   255), GetUIValueRange(DNA_UI_EARS2_B,	  255)))
	H.looks.set_ears_color3(rgb(GetUIValueRange(DNA_UI_EARS3_R,   255), GetUIValueRange(DNA_UI_EARS3_G,   255), GetUIValueRange(DNA_UI_EARS3_B,	  255)))
	H.looks.set_ears_alpha(GetUIValueRange(DNA_UI_EARS_ALPHA, 255))
	H.looks.set_ears_alpha2(GetUIValueRange(DNA_UI_EARS_SECONDARY_ALPHA, 255))

	LAZYINITLIST(H.ear_secondary_colors)
	H.ear_secondary_colors.len = max(length(H.ear_secondary_colors), DNA_UI_EARS_SECONDARY_COLOR_CHANNEL_COUNT)
	for(var/channel in 1 to DNA_UI_EARS_SECONDARY_COLOR_CHANNEL_COUNT)
		var/offset = DNA_UI_EARS_SECONDARY_START + (channel - 1) * 3
		H.set_ear_secondary_colors_at(channel, rgb(
			GetUIValueRange(offset, 255),
			GetUIValueRange(offset + 1, 255),
			GetUIValueRange(offset + 2, 255),
		))

	//Tail
	var/tail = GetUIValueRange(DNA_UI_TAIL_STYLE, GLOB.tail_styles_list.len + 1) - 1
	if(tail < 1)
		rel_set(H, nameof(H.tail_style), null)
	else if((0 < tail) && (tail <= GLOB.tail_styles_list.len))
		rel_set(H, nameof(H.tail_style), GLOB.tail_styles_list[GLOB.tail_styles_list[tail]])

	//Wing
	var/wing = GetUIValueRange(DNA_UI_WING_STYLE, GLOB.wing_styles_list.len + 1) - 1
	if(wing < 1)
		rel_set(H, nameof(H.wing_style), null)
	else if((0 < wing) && (wing <= GLOB.wing_styles_list.len))
		rel_set(H, nameof(H.wing_style), GLOB.wing_styles_list[GLOB.wing_styles_list[wing]])

	//Wing Color
	H.looks.set_wing_color(rgb(GetUIValueRange(DNA_UI_WING_R,     255), GetUIValueRange(DNA_UI_WING_G,     255), GetUIValueRange(DNA_UI_WING_B,     255)))
	H.looks.set_wing_color2(rgb(GetUIValueRange(DNA_UI_WING2_R,    255), GetUIValueRange(DNA_UI_WING2_G,    255), GetUIValueRange(DNA_UI_WING2_B,    255)))
	H.looks.set_wing_color3(rgb(GetUIValueRange(DNA_UI_WING3_R,    255), GetUIValueRange(DNA_UI_WING3_G,    255), GetUIValueRange(DNA_UI_WING3_B,    255)))
	H.looks.set_wing_alpha(GetUIValueRange(DNA_UI_WING_ALPHA,	255))

	// Playerscale
	var/size = GetUIValueRange(DNA_UI_PLAYERSCALE, GLOB.player_sizes_list.len)
	if((0 < size) && (size <= GLOB.player_sizes_list.len))
		H.resize(GLOB.player_sizes_list[GLOB.player_sizes_list[size]], TRUE, ignore_prefs = TRUE)

	// Tail/Taur Color
	H.looks.set_tail_color(rgb(GetUIValueRange(DNA_UI_TAIL_R,    255), GetUIValueRange(DNA_UI_TAIL_G,    255), GetUIValueRange(DNA_UI_TAIL_B,    255)))
	H.looks.set_tail_color2(rgb(GetUIValueRange(DNA_UI_TAIL2_R,   255), GetUIValueRange(DNA_UI_TAIL2_G,   255), GetUIValueRange(DNA_UI_TAIL2_B,   255)))
	H.looks.set_tail_color3(rgb(GetUIValueRange(DNA_UI_TAIL3_R,   255), GetUIValueRange(DNA_UI_TAIL3_G,   255), GetUIValueRange(DNA_UI_TAIL3_B,   255)))
	H.looks.set_tail_alpha(GetUIValueRange(DNA_UI_TAIL_ALPHA,  255))

	// Hair gradiant
	var/grad = GetUIValueRange(DNA_UI_GRAD_STYLE,GLOB.hair_gradients.len)
	if((0 < grad) && (grad <= GLOB.hair_gradients.len))
		H.looks.set_grad_style(GLOB.hair_gradients[grad])

	////////////////////////////////////////////////////////////////////////////////
	// Custom species and other cosmetic vars
	H.custom_species = custom_species
	H.bio.custom_say = custom_say
	H.bio.custom_ask = custom_ask
	H.bio.custom_whisper = custom_whisper
	H.bio.custom_exclaim = custom_exclaim
	H.custom_speech_bubble = custom_speech_bubble
	sparse_set(H, custom_heat, custom_heat)
	sparse_set(H, custom_cold, custom_cold)
	H.custom_footstep = custom_footstep
	H.looks.set_digitigrade(digitigrade)

	// If synths have character markings
	H.looks.set_synth_markings(synth_markings)

	// Scaling style
	H.set_fuzzy(scale_appearance)
	H.set_offset_override(offset_override)

	////////////////////////////////////////////////////////////////////////////////
	// Get a copy of the species datum to edit for ourselves
	// anything that sets stuff in species MUST be done beyond here!
	LAZYINITLIST(species_traits); H.species.produceCopy(species_traits, H, base_species, FALSE) // Traitgenes edit - reset_dna flag required, or genes get reset on resleeve

	// Update species blood with our blood color from dna! produceCopy() left H's species a private
	// copy; proto_private() returns it (and never lets these writes reach a registered species).
	var/datum/species/own_species = rel_private(H, nameof(H.species))
	own_species.blood_reagents = blood_reagents
	own_species.set_blood_color(blood_color)
	own_species.species_sounds = species_sounds
	own_species.gender_specific_species_sounds = gender_specific_species_sounds
	own_species.species_sounds_male = species_sounds_male
	own_species.species_sounds_female = species_sounds_female
/**
 * End of mob to dna, and dna to mob transfer procs.
 */

// Set a DNA UI block's raw value.
/datum/dna/proc/SetUIValue(block,value,defer=0)
	if (block<=0) return
	ASSERT(value>=0)
	ASSERT(value<=4095)
	set_UI_at(block, value)
	if(!defer)
		UpdateUI()

// Get a DNA UI block's raw value.
/datum/dna/proc/GetUIValue(block)
	if (block<=0) return 0
	return UI[block]

// Set a DNA UI block's value, given a value and a max possible value.
// Used in hair and facial styles (value being the index and maxvalue being the len of the hairstyle list)
/datum/dna/proc/SetUIValueRange(block,value,maxvalue,defer=0)
	if (block<=0) return
	ASSERT(maxvalue<=4095)
	var/range = (4095 / maxvalue)
	if(value!=null)
		SetUIValue(block,round(value * range),defer)

/// Writes an "#rrggbb" colour into three consecutive UI blocks from `block` (red, green, blue).
/datum/dna/proc/SetUIColour(block, colour, defer = 1)
	var/list/channels = hex2rgb(colour)
	for(var/i in 1 to 3)
		SetUIValueRange(block + i - 1, channels[i], 255, defer)

/// The "#rrggbb" colour held in three consecutive UI blocks from `block`.
/datum/dna/proc/GetUIColour(block)
	return rgb(GetUIValueRange(block, 255), GetUIValueRange(block + 1, 255), GetUIValueRange(block + 2, 255))

// Getter version of above.
/datum/dna/proc/GetUIValueRange(block,maxvalue)
	if (block<=0) return 0
	var/value = GetUIValue(block)
	return round(0.5 + (value / 4095) * maxvalue)

// Is the UI gene "on" or "off"?
// For UI, this is simply a check of if the value is > 2050.
/datum/dna/proc/GetUIState(block)
	if (block<=0) return
	return UI[block] > 2050


// Set UI gene "on" (1) or "off" (0)
/datum/dna/proc/SetUIState(block,on,defer=0)
	if (block<=0) return
	var/val
	if(on)
		val=rand(2050,4095)
	else
		val=rand(1,2049)
	SetUIValue(block,val,defer)

// Get a hex-encoded UI block.
/datum/dna/proc/GetUIBlock(block)
	return EncodeDNABlock(GetUIValue(block))

// Do not use this unless you absolutely have to.
// Set a block from a hex string.  This is inefficient.  If you can, use SetUIValue().
// Used in DNA modifiers.
/datum/dna/proc/SetUIBlock(block,value,defer=0)
	if (block<=0) return
	return SetUIValue(block,hex2num(value),defer)

// Get a sub-block from a block.
/datum/dna/proc/GetUISubBlock(block,subBlock)
	return copytext(GetUIBlock(block),subBlock,subBlock+1)

// Do not use this unless you absolutely have to.
// Set a block from a hex string.  This is inefficient.  If you can, use SetUIValue().
// Used in DNA modifiers.
/datum/dna/proc/SetUISubBlock(block,subBlock, newSubBlock, defer=0)
	if (block<=0) return
	var/oldBlock=GetUIBlock(block)
	var/newBlock=""
	for(var/i=1, i<=length(oldBlock), i++)
		if(i==subBlock)
			newBlock+=newSubBlock
		else
			newBlock+=copytext(oldBlock,i,i+1)
	SetUIBlock(block,newBlock,defer)

///////////////////////////////////////
// STRUCTURAL ENZYMES
///////////////////////////////////////

// "Zeroes out" all of the blocks.
/datum/dna/proc/ResetSE()
	for(var/i = 1, i <= DNA_SE_LENGTH, i++)
		SetSEValue(i,rand(1,1024),1)
	UpdateSE()
	dna_ready = TRUE

// Set a DNA SE block's raw value.
/datum/dna/proc/SetSEValue(block,value,defer=0)
	if (block<=0) return
	ASSERT(value>=0)
	ASSERT(value<=4095)
	set_SE_at(block, value)
	if(!defer)
		UpdateSE()

// Get a DNA SE block's raw value.
/datum/dna/proc/GetSEValue(block)
	if (block<=0) return 0
	return SE[block]

// Set a DNA SE block's value, given a value and a max possible value.
// Might be used for species?
/datum/dna/proc/SetSEValueRange(block,value,maxvalue)
	if (block<=0) return
	ASSERT(maxvalue<=4095)
	var/range = round(4095 / maxvalue)
	if(value)
		SetSEValue(block, value * range - rand(1,range-1))

// Getter version of above.
/datum/dna/proc/GetSEValueRange(block,maxvalue)
	if (block<=0) return 0
	var/value = GetSEValue(block)
	return round(1 +(value / 4095)*maxvalue)

// Is the block "on" (1) or "off" (0)? (Un-assigned genes are always off.)
/datum/dna/proc/GetSEState(block)
	if (block<=0) return 0
	var/list/BOUNDS=GetDNABounds(block)
	var/value=GetSEValue(block)
	return (value > BOUNDS[DNA_ON_LOWERBOUND])

// Set a block "on" or "off".
/datum/dna/proc/SetSEState(block,on,defer=0)
	if (block<=0) return
	var/list/BOUNDS=GetDNABounds(block)
	var/val
	if(on)
		val=rand(BOUNDS[DNA_ON_LOWERBOUND],BOUNDS[DNA_ON_UPPERBOUND])
	else
		val=rand(1,BOUNDS[DNA_OFF_UPPERBOUND])
	SetSEValue(block,val,defer)

// Get hex-encoded SE block.
/datum/dna/proc/GetSEBlock(block)
	return EncodeDNABlock(GetSEValue(block))

// Get activation intensity, returns 0 to 1, you MUST check if the gene is active first! This is used for future expansion where genetraits can have multiple levels of activation/intensity
/datum/dna/proc/GetSEActivationIntensity(block)
	if (block<=0) return 0
	var/list/BOUNDS=GetDNABounds(block)
	var/value=GetSEValue(block)
	var/val = (value - BOUNDS[DNA_ON_LOWERBOUND]) / (BOUNDS[DNA_ON_UPPERBOUND] - BOUNDS[DNA_ON_LOWERBOUND])
	return val

// Gets the activation intensity index. ex: if a genetrait has 5 levels of activations, the gene will have 5 possible levels of activation. this is a future TODO.
/datum/dna/proc/GetSEActivationLevel(block,number_of_levels)
	var/raw_val = GetSEActivationIntensity(block)
	return round(raw_val * number_of_levels) // TODO - If this should be round/floor/ceil

// Do not use this unless you absolutely have to.
// Set a block from a hex string.  This is inefficient.  If you can, use SetUIValue().
// Used in DNA modifiers.
/datum/dna/proc/SetSEBlock(block,value,defer=0)
	if (block<=0) return
	var/nval=hex2num(value)
	return SetSEValue(block,nval,defer)

/datum/dna/proc/GetSESubBlock(block,subBlock)
	return copytext(GetSEBlock(block),subBlock,subBlock+1)

// Do not use this unless you absolutely have to.
// Set a sub-block from a hex character.  This is inefficient.  If you can, use SetUIValue().
// Used in DNA modifiers.
/datum/dna/proc/SetSESubBlock(block,subBlock, newSubBlock, defer=0)
	if (block<=0) return
	var/oldBlock=GetSEBlock(block)
	var/newBlock=""
	for(var/i=1, i<=length(oldBlock), i++)
		if(i==subBlock)
			newBlock+=newSubBlock
		else
			newBlock+=copytext(oldBlock,i,i+1)
	SetSEBlock(block,newBlock,defer)


/proc/EncodeDNABlock(value)
	return num2hex(value, 3)

/**
 * These used to be maintained eagerly: every SetUIValue()/SetSEValue() (unless
 * deferred) rebuilt and stored a full hex-encoded copy of the whole UI/SE block
 * array in uni_identity/struc_enzymes, so each /datum/dna carried its genetic
 * data twice -- once as SE[93]/UI[65] int blocks (the canonical storage) and
 * once as ~279/195-byte hex strings. The strings are now derived on demand
 * instead of stored; SE[]/UI[] is the only storage. UpdateUI()/UpdateSE() are
 * kept as harmless no-ops for API stability (some callers still call them after
 * a deferred Set*Value(..., defer=1) run; there's simply nothing left to flush).
 */
/datum/dna/proc/UpdateUI()
	return

/datum/dna/proc/UpdateSE()
	return

/// Returns the full hex-encoded Unique Identity string, built fresh from UI[].
/// Route external reads of the old uni_identity var through this proc.
/datum/dna/proc/GetUniIdentity()
	var/result = ""
	for(var/block in UI)
		result += EncodeDNABlock(block)
	return result

/// Returns the full hex-encoded Structural Enzymes string, built fresh from SE[].
/// Route external reads of the old struc_enzymes var through this proc.
/datum/dna/proc/GetStrucEnzymes()
	var/result = ""
	for(var/block in SE)
		result += EncodeDNABlock(block)
	return result

/// Decodes a full hex-encoded UI string (as produced by GetUniIdentity()) back
/// into UI[]. Used only for the "detached dna datum" backwards-compat default
/// in check_integrity() below -- prefer SetUIValue()/SetUIBlock() elsewhere.
/datum/dna/proc/SetUniIdentity(hex)
	for(var/i = 1, i <= DNA_UI_LENGTH, i++)
		var/pos = (i - 1) * 3 + 1
		SetUIValue(i, hex2num(copytext(hex, pos, pos + 3)), 1)
	dna_ready = TRUE

/// Decodes a full hex-encoded SE string (as produced by GetStrucEnzymes()) back
/// into SE[]. Used only for the "detached dna datum" backwards-compat default
/// in check_integrity() below -- prefer SetSEValue()/SetSEBlock() elsewhere.
/datum/dna/proc/SetStrucEnzymes(hex)
	for(var/i = 1, i <= DNA_SE_LENGTH, i++)
		var/pos = (i - 1) * 3 + 1
		SetSEValue(i, hex2num(copytext(hex, pos, pos + 3)), 1)
	dna_ready = TRUE

// BACK-COMPAT!
//  Just checks our character has all the crap it needs.
/datum/dna/proc/check_integrity(mob/living/carbon/human/character)
	if(character)
		if(!dna_ready)
			ResetUIFrom(character)
			ResetSE()

		if(length(unique_enzymes) != 32)
			unique_enzymes = md5(character.real_name)
	else
		if(!dna_ready)
			SetUniIdentity("00600200a00e0110148fc01300b0095bd7fd3f4")
			SetStrucEnzymes("43359156756131e13763334d1c369012032164d4fe4cd61544b6c03f251b6c60a42821d26ba3b0fd6")

// BACK-COMPAT!
//  Initial DNA setup.  I'm kind of wondering why the hell this doesn't just call the above.
/datum/dna/proc/ready_dna(mob/living/carbon/human/character)
	ResetUIFrom(character)

	ResetSE()

	unique_enzymes = md5(character.real_name)

#undef DNA_OFF_LOWERBOUND
#undef DNA_OFF_UPPERBOUND
#undef DNA_ON_LOWERBOUND
#undef DNA_ON_UPPERBOUND
