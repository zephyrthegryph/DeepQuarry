// Indestructible bedrock wall — the perimeter ring of procedural quarry
// layers. /turf/unsimulated/wall is dense, opacity 1, blocks_air; players
// can't mine it because it's not /turf/simulated/mineral so make_floor()
// doesn't apply. The "rock-alt" icon state is the darker rock variant in
// walls.dmi, distinguishing it from the lighter mineable cave walls.
/turf/unsimulated/wall/bedrock
	name = "bedrock"
	desc = "Solid, ancient stone. No pickaxe will scratch this."
	icon = 'icons/turf/walls.dmi'
	icon_state = "rock-alt"


// Cave wall subtype that renders as rocky ground (not sand) when carved.
//
// /turf/simulated/mineral's make_floor() toggles density/opacity in place
// without changing the type — the carved tile still reports as the same
// mineral subtype. The icon switches to whichever sand_icon_state the
// subtype defines, defaulting to "asteroid" (the sandy look).
//
// We want the quarry's carved tiles to look like rocky cave floor, not
// sand. Override sand_icon_path/state to the outdoors rock sprite.

/turf/simulated/mineral/cave/quarry
	sand_icon_path = 'icons/turf/outdoors.dmi'
	sand_icon_state = "rock"

// Hook GetDrilled so mining a quarry wall fires a node-mined event.
// Captures mineral identity BEFORE the parent runs (the parent clears
// `mineral` when it makes the floor), then dispatches after the drop
// so we know the right item type. Non-quarry mineral walls keep their
// upstream behavior — only this subtype tree intercepts.
/turf/simulated/mineral/cave/quarry/GetDrilled(artifact_fail = 0)
	var/captured_name = mineral?.name
	var/captured_item = mineral?.ore
	var/captured_z = z
	var/captured_turf = src
	. = ..()
	if(SSquarry)
		// Mining is noise. emit_noise handles both alerting nearby
		// mobs and bumping the layer's danger meter, so we don't
		// also call the legacy wall-mined danger hook.
		SSquarry.emit_noise(captured_turf, QUARRY_NOISE_PICK, captured_turf)
		if(captured_name)
			SSquarry.on_layer_node_mined(captured_z, captured_name, captured_item)


// Per-tier visual variants. Each 5-layer block uses its own subtype so
// the carved-floor sand_icon_state and (optionally) the wall icon
// differ between blocks. Today only the floor icon varies; the wall
// uses the parent's icon. Extending with per-tier wall sprites later
// is a one-line override.

/turf/simulated/mineral/cave/quarry/shallows
	// 1-5. Standard rocky floor.
	sand_icon_state = "rock"

/turf/simulated/mineral/cave/quarry/midmines
	// 6-10. Darker, cooler stone.
	sand_icon_state = "rock"

/turf/simulated/mineral/cave/quarry/deeps
	// 11-15. Damp, mineral-stained stone.
	sand_icon_state = "rock"

/turf/simulated/mineral/cave/quarry/abyss
	// 16-20. Deeper, more uniform dark stone.
	sand_icon_state = "rock"

/turf/simulated/mineral/cave/quarry/core
	// 21-25. Hot, glassy stone near the planet's core.
	sand_icon_state = "rock"


// --- Biome wall subtypes ---------------------------------------------
//
// Each biome paints its territory with a distinctly-tinted wall.
// `color` applies to both the wall sprite and its carved-floor
// (sand_icon) variant, so a player walking from stone_caverns into
// crystal_pockets sees the wall+floor color shift on the cell border.
// Sprite states stay shared so this costs zero new art.

/turf/simulated/mineral/cave/quarry/biome_stone
	color = "#a8a8a8"

/turf/simulated/mineral/cave/quarry/biome_crystal
	color = "#9bd7ff"

/turf/simulated/mineral/cave/quarry/biome_damp
	color = "#7fb8c0"

/turf/simulated/mineral/cave/quarry/biome_sulfur
	color = "#d9c44b"

/turf/simulated/mineral/cave/quarry/biome_mushroom
	color = "#a8e3a0"

/turf/simulated/mineral/cave/quarry/biome_magma
	color = "#cc4a2a"

/turf/simulated/mineral/cave/quarry/biome_frozen
	color = "#cfe1ee"

/turf/simulated/mineral/cave/quarry/biome_phoron
	color = "#b86bd9"

/turf/simulated/mineral/cave/quarry/biome_bone
	color = "#d4c19a"

/turf/simulated/mineral/cave/quarry/biome_shattered
	color = "#553a6b"
