// Class-aware ranges for the eleven /datum/material core stats, plus
// helpers used by the dynamic material roller (name / color generation).
//
// Material behavior live on /datum/component subtypes — see
// material_components.dm. There's no shared property datum class in this
// design; the eleven stats are direct vars on /datum/material, and the
// three "actor" properties (luminescence, radioactivity, toxicity) are
// component magnitudes.

// MATCLASS_* defines live in code/__defines/material_defines.dm
// so they parse before upstream /datum/material reaches them.


// --- Class-aware core stat ranges --------------------------------------------
//
// Per-class min/max for each direct-var stat on /datum/material. The
// dynamic roller (dq_roll_dynamic_material) pulls magnitudes from here
// at material creation time. Static materials ignore these — they
// author values by hand.
//
// The eleven stats are grouped into mechanical / thermal / electrical /
// chemical, mirroring the layout on /datum/material itself. Ranges are
// authored so each class has a distinct profile: metals are dense and
// conductive, crystals are hard and brittle, organics are light and
// reactive, ceramics resist heat and corrosion.

/proc/dq_core_stat_range(stat_name, material_class)
	var/static/list/ranges = list(
		// Mechanical
		"hardness" = list(
			MATCLASS_METAL   = list(40, 95),
			MATCLASS_CRYSTAL = list(60, 100),
			MATCLASS_ORGANIC = list(5, 40),
			MATCLASS_CERAMIC = list(50, 90),
		),
		"density" = list(
			MATCLASS_METAL   = list(15, 40),
			MATCLASS_CRYSTAL = list(10, 30),
			MATCLASS_ORGANIC = list(2, 20),
			MATCLASS_CERAMIC = list(10, 30),
		),
		"integrity" = list(
			MATCLASS_METAL   = list(150, 600),
			MATCLASS_CRYSTAL = list(80, 250),
			MATCLASS_ORGANIC = list(40, 200),
			MATCLASS_CERAMIC = list(120, 400),
		),
		"elasticity" = list(
			MATCLASS_METAL   = list(30, 80),
			MATCLASS_CRYSTAL = list(5, 25),
			MATCLASS_ORGANIC = list(40, 95),
			MATCLASS_CERAMIC = list(10, 30),
		),
		"brittleness" = list(
			MATCLASS_METAL   = list(5, 30),
			MATCLASS_CRYSTAL = list(40, 90),
			MATCLASS_ORGANIC = list(15, 50),
			MATCLASS_CERAMIC = list(40, 80),
		),
		// Thermal
		"heat_resistance" = list(
			MATCLASS_METAL   = list(30, 80),
			MATCLASS_CRYSTAL = list(25, 70),
			MATCLASS_ORGANIC = list(5, 30),
			MATCLASS_CERAMIC = list(60, 100),
		),
		"thermal_insulation" = list(
			MATCLASS_METAL   = list(5, 30),
			MATCLASS_CRYSTAL = list(20, 60),
			MATCLASS_ORGANIC = list(30, 80),
			MATCLASS_CERAMIC = list(40, 95),
		),
		// Electrical / magnetic
		"conductivity" = list(
			MATCLASS_METAL   = list(20, 100),
			MATCLASS_CRYSTAL = list(1, 30),
			MATCLASS_ORGANIC = list(1, 10),
			MATCLASS_CERAMIC = list(1, 15),
		),
		"magnetism" = list(
			MATCLASS_METAL   = list(20, 100),
			MATCLASS_CRYSTAL = list(5, 50),
			MATCLASS_ORGANIC = list(1, 20),
			MATCLASS_CERAMIC = list(5, 40),
		),
		// Chemical
		"reactivity" = list(
			MATCLASS_METAL   = list(20, 70),
			MATCLASS_CRYSTAL = list(15, 55),
			MATCLASS_ORGANIC = list(40, 95),
			MATCLASS_CERAMIC = list(5, 35),
		),
		"corrosion_resistance" = list(
			MATCLASS_METAL   = list(20, 70),
			MATCLASS_CRYSTAL = list(40, 95),
			MATCLASS_ORGANIC = list(5, 30),
			MATCLASS_CERAMIC = list(50, 95),
		),
	)
	var/list/by_class = ranges[stat_name]
	if(by_class)
		var/list/rng = by_class[material_class]
		if(rng)
			return rng
	return list(0, 0)


/// Roll a numeric value uniformly from the per-class range for a stat.
/proc/dq_roll_core_stat(stat_name, material_class)
	var/list/rng = dq_core_stat_range(stat_name, material_class)
	return rand(rng[1], rng[2])


// --- Behavior component roll table ------------------------------------------
//
// Per-class chance (percent) of attaching each of the three behavior
// components. Magnitudes when attached are pulled from their own range
// tables below. Independent rolls — a material can carry multiple
// behaviors.

/proc/dq_roll_behavior_components(datum/material/M)
	if(!M)
		return
	var/static/list/chances = list(
		MATCLASS_METAL   = list("luminescent" = 5,  "radioactive" = 20, "toxic" = 10),
		MATCLASS_CRYSTAL = list("luminescent" = 35, "radioactive" = 15, "toxic" = 5),
		MATCLASS_ORGANIC = list("luminescent" = 15, "radioactive" = 5,  "toxic" = 30),
		MATCLASS_CERAMIC = list("luminescent" = 10, "radioactive" = 10, "toxic" = 10),
	)
	var/list/by_class = chances[M.material_class]
	if(!by_class)
		return
	if(prob(by_class["luminescent"]))
		M.AddComponent(/datum/component/material_luminescent, rand(10, 60))
	if(prob(by_class["radioactive"]))
		M.AddComponent(/datum/component/material_radioactive, rand(3, 25))
	if(prob(by_class["toxic"]))
		M.AddComponent(/datum/component/material_toxic, rand(10, 50))


// --- Name + color generation (used by /datum/material/dynamic) --------------

/proc/_dq_generate_material_name()
	var/static/list/prefixes = list(
		"Cae", "Vel", "Tor", "Quin", "Zen", "Mor", "Lyr", "Stel",
		"Pyr", "Cry", "Lum", "Umb", "Ner", "Xan", "Iod", "Cor",
		"Ar", "Bel", "Cel", "Drav", "Eph", "Fal", "Gly", "Hes",
		"Ith", "Jor", "Kel", "Lan", "Mir", "Nov", "Or", "Pal",
		"Quor", "Rud", "Sil", "Tarn", "Ul", "Ver", "Wis", "Xyl",
	)
	var/static/list/midfixes = list(
		"", "a", "e", "i", "o", "u",
		"ar", "en", "ir", "or", "us",
		"al", "il", "ol", "yl",
	)
	var/static/list/suffixes = list(
		"ite", "ium", "ide", "ine", "ane",
		"on", "ore", "yte", "ar", "ax",
		"is", "ys", "um", "ex",
	)
	return "[pick(prefixes)][pick(midfixes)][pick(suffixes)]"


/proc/_dq_generate_material_color()
	var/h = rand(0, 359)
	var/s = rand(40, 85)
	var/l = rand(35, 65)
	return hsl_to_hex_string(h, s, l)


/proc/hsl_to_hex_string(h, s, l)
	s = s / 100
	l = l / 100
	var/c = (1 - abs(2 * l - 1)) * s
	var/hp = h / 60
	var/x = c * (1 - abs((hp - 2 * round(hp / 2)) - 1))
	var/r1 = 0
	var/g1 = 0
	var/b1 = 0
	if(hp >= 0 && hp < 1)
		r1 = c; g1 = x
	else if(hp >= 1 && hp < 2)
		r1 = x; g1 = c
	else if(hp >= 2 && hp < 3)
		g1 = c; b1 = x
	else if(hp >= 3 && hp < 4)
		g1 = x; b1 = c
	else if(hp >= 4 && hp < 5)
		r1 = x; b1 = c
	else
		r1 = c; b1 = x
	var/m = l - c / 2
	var/r = round((r1 + m) * 255)
	var/g = round((g1 + m) * 255)
	var/b = round((b1 + m) * 255)
	return "#[num2hex(clamp(r, 0, 255), 2)][num2hex(clamp(g, 0, 255), 2)][num2hex(clamp(b, 0, 255), 2)]"
