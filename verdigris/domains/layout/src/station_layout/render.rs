use super::model::*;
use serde::Deserialize;
use std::{
    collections::BTreeMap,
    fs,
    io::{BufReader, Cursor},
    path::{Path, PathBuf},
};

#[derive(Deserialize)]
struct DmiManifest {
    width: u32,
    height: u32,
    cols: u32,
    state: Vec<DmiState>,
}

#[derive(Deserialize)]
struct DmiState {
    name: String,
    dirs: u32,
    frames: u32,
}

struct SpriteSheet {
    manifest: DmiManifest,
    rgba: Vec<u8>,
    width: u32,
}

/// Render the authoritative blueprint with the same source sprites that the
/// icon repacker turns into runtime DMIs. Missing sprite metadata is rendered
/// as a conspicuous magenta tile so preview coverage can be quality-gated.
pub fn render_blueprint_sprites(
    blueprint: &StationBlueprint,
    repository_root: &Path,
) -> Result<Vec<u8>, String> {
    const TILE: u32 = 32;
    let layout = &blueprint.layout;
    let occupied = layout
        .tiles
        .iter()
        .enumerate()
        .filter(|(_, cell)| cell.class != TileClass::Exterior)
        .map(|(index, _)| Point {
            x: u16::try_from(index % usize::from(layout.width)).unwrap_or(0),
            y: u16::try_from(index / usize::from(layout.width)).unwrap_or(0),
        })
        .collect::<Vec<_>>();
    let min_x = occupied
        .iter()
        .map(|point| point.x)
        .min()
        .unwrap_or(0)
        .saturating_sub(2);
    let min_y = occupied
        .iter()
        .map(|point| point.y)
        .min()
        .unwrap_or(0)
        .saturating_sub(2);
    let max_x = occupied
        .iter()
        .map(|point| point.x)
        .max()
        .unwrap_or(layout.width.saturating_sub(1))
        .saturating_add(2)
        .min(layout.width.saturating_sub(1));
    let max_y = occupied
        .iter()
        .map(|point| point.y)
        .max()
        .unwrap_or(layout.height.saturating_sub(1))
        .saturating_add(2)
        .min(layout.height.saturating_sub(1));
    let width = u32::from(max_x - min_x + 1) * TILE;
    let height = u32::from(max_y - min_y + 1) * TILE;
    let mut pixels = vec![0u8; width as usize * height as usize * 4];
    let mut cache: BTreeMap<PathBuf, SpriteSheet> = BTreeMap::new();
    let mut missing_previews = std::collections::BTreeSet::new();
    let room_floor_styles = blueprint
        .rooms
        .iter()
        .map(|room| (room.room_id, room.floor_style.as_str()))
        .collect::<BTreeMap<_, _>>();
    let room_accent_styles = blueprint
        .rooms
        .iter()
        .map(|room| (room.room_id, room.accent_style.as_str()))
        .collect::<BTreeMap<_, _>>();

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let point = Point { x, y };
            let render_point = Point {
                x: x - min_x,
                y: y - min_y,
            };
            let cell = layout.tile(point);
            let room_style = cell
                .room
                .and_then(|room_id| room_floor_styles.get(&room_id).copied());
            let (icon, state) = tile_preview(cell.class, room_style);
            if let Some(sprite) =
                load_sprite(repository_root, &mut cache, icon, state, Facing::South)?
            {
                blit_tile(&mut pixels, width, height, render_point, &sprite);
            } else {
                missing_previews.insert(format!("tile {icon}:{state}"));
                fill_tile(
                    &mut pixels,
                    width,
                    height,
                    render_point,
                    match cell.class {
                        TileClass::Exterior => [2, 4, 9, 255],
                        TileClass::Hull | TileClass::Structure | TileClass::Partition => {
                            [70, 76, 83, 255]
                        }
                        _ => [54, 58, 64, 255],
                    },
                );
            }
        }
    }

    // Paint a continuous department-colour inset around every authored room.
    // This mirrors the live borderfloor decals instead of tinting arbitrary
    // whole tiles, preserving each room's role-specific base flooring.
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let point = Point { x, y };
            let Some(room_id) = layout.tile(point).room else {
                continue;
            };
            let Some(color) = room_accent_styles
                .get(&room_id)
                .and_then(|style| accent_rgb(style))
            else {
                continue;
            };
            for (facing, dx, dy) in [
                (Facing::North, 0i32, 1i32),
                (Facing::East, 1, 0),
                (Facing::South, 0, -1),
                (Facing::West, -1, 0),
            ] {
                let nx = i32::from(x) + dx;
                let ny = i32::from(y) + dy;
                let same_room = nx >= 0
                    && ny >= 0
                    && nx < i32::from(layout.width)
                    && ny < i32::from(layout.height)
                    && layout
                        .tile(Point {
                            x: u16::try_from(nx).unwrap_or(0),
                            y: u16::try_from(ny).unwrap_or(0),
                        })
                        .room
                        == Some(room_id);
                if same_room {
                    continue;
                }
                if let Some(mut sprite) = load_sprite(
                    repository_root,
                    &mut cache,
                    "icons/turf/flooring/decals_vr.dmi",
                    "bordercolor",
                    facing,
                )? {
                    tint_sprite(&mut sprite, color);
                    blit_tile(
                        &mut pixels,
                        width,
                        height,
                        Point {
                            x: x - min_x,
                            y: y - min_y,
                        },
                        &sprite,
                    );
                }
            }
        }
    }

    for door in &layout.doors {
        let preview = if door.connects_maintenance {
            ("icons/obj/doors/Doormaint.dmi", "door_closed")
        } else {
            ("icons/obj/doors/doorint.dmi", "door_closed")
        };
        if let Some(sprite) = load_sprite(
            repository_root,
            &mut cache,
            preview.0,
            preview.1,
            Facing::South,
        )? {
            blit_tile(
                &mut pixels,
                width,
                height,
                Point {
                    x: door.at.x - min_x,
                    y: door.at.y - min_y,
                },
                &sprite,
            );
        } else {
            missing_previews.insert(format!("door {}:{}", preview.0, preview.1));
        }
    }

    for fixture in &blueprint.fixtures {
        let preview = if matches!(
            fixture.fixture_id.as_str(),
            "notice_board"
                | "manifest_board"
                | "charger_table"
                | "wall_light"
                | "apc"
                | "air_alarm"
                | "fire_alarm"
                | "vent"
                | "scrubber"
        ) {
            builtin_fixture_preview(&fixture.fixture_id)
        } else {
            blueprint
                .sprite_previews
                .get(&fixture.fixture_id)
                .map(|preview| (preview.icon_file.as_str(), preview.icon_state.as_str()))
                .or_else(|| builtin_fixture_preview(&fixture.fixture_id))
        };
        let mut layers = Vec::new();
        if let Some((icon, state)) = preview {
            layers.push((icon, state));
            if let Some(screen) = operational_icon_state(&fixture.fixture_id, icon) {
                // Computer role states are screen overlays. They must be
                // composited over the chassis rather than replacing it.
                if screen != state {
                    layers.push((icon, screen));
                }
            }
            if fixture.fixture_id == "apc" {
                // Match a closed, locked, operating APC with automatic
                // equipment/lighting/environment channels. APC indicator
                // states are overlays in power.dmi, not alternate bodies.
                layers.extend([
                    (icon, "apcox-1"),
                    (icon, "apco3-0"),
                    (icon, "apco0-2"),
                    (icon, "apco1-2"),
                    (icon, "apco2-2"),
                ]);
            }
        }
        let mut rendered_any = false;
        for (icon, state) in layers {
            let sprite = load_sprite(
                repository_root,
                &mut cache,
                icon,
                state,
                fixture_sprite_facing(fixture),
            )?;
            let Some(sprite) = sprite else {
                missing_previews.insert(format!("{} layer {icon}:{state}", fixture.fixture_id));
                continue;
            };
            let (offset_x, offset_y) = fixture_pixel_offset(fixture);
            blit_tile_offset(
                &mut pixels,
                width,
                height,
                Point {
                    x: fixture.at.x - min_x,
                    y: fixture.at.y - min_y,
                },
                &sprite,
                offset_x,
                offset_y,
            );
            rendered_any = true;
        }
        if !rendered_any {
            missing_previews.insert(format!("{} ({preview:?})", fixture.fixture_id));
            draw_missing_sprite(
                &mut pixels,
                width,
                height,
                Point {
                    x: fixture.at.x - min_x,
                    y: fixture.at.y - min_y,
                },
            );
        }
    }

    if !missing_previews.is_empty() {
        return Err(format!(
            "sprite preview coverage is incomplete: {}",
            missing_previews.into_iter().collect::<Vec<_>>().join(", ")
        ));
    }
    let scale = std::env::var("DQ_SPRITE_SCALE")
        .ok()
        .and_then(|value| value.parse::<u32>().ok())
        .unwrap_or(2)
        .clamp(1, 4);
    if scale == 1 {
        encode_rgba(width, height, &pixels)
    } else {
        let scaled = upscale_nearest_rgba(width, height, &pixels, scale);
        encode_rgba(width * scale, height * scale, &scaled)
    }
}

fn operational_icon_state<'a>(fixture_id: &str, icon_file: &str) -> Option<&'a str> {
    if !icon_file
        .replace('\\', "/")
        .ends_with("icons/obj/computer.dmi")
    {
        return None;
    }
    Some(match fixture_id {
        "medical_console" => "medcomp",
        "research_console" => "rdcomp",
        "id_console" => "id",
        "robotics_console" => "robot",
        "communications_console" => "comm",
        "security_console" | "security_records" | "flash" => "security",
        "supply_console" | "cargo_console" => "supply",
        "engineering_console" | "generator_control" | "power_monitor" => "power_monitor",
        "atmos_control" => "area_atmos",
        "command_console" | "holotable" => "command",
        "ai_upload" | "ai_core" => "aiupload",
        "crew_monitor" | "role_console" | "visitor_console" | "control_console"
        | "data_terminal" | "analyzer" | "plant_analyzer" | "package_scanner" => "crew",
        _ => return None,
    })
}

fn fixture_pixel_offset(fixture: &FixturePlacement) -> (i32, i32) {
    if fixture.layer != FixtureLayer::Wall {
        return (0, 0);
    }
    let distance = match fixture.fixture_id.as_str() {
        "wall_light" => 26,
        "apc" => 22,
        "air_alarm" | "fire_alarm" => 20,
        _ => 24,
    };
    match fixture.facing {
        Facing::North => (0, distance),
        Facing::East => (distance, 0),
        Facing::South => (0, -distance),
        Facing::West => (-distance, 0),
    }
}

fn fixture_sprite_facing(fixture: &FixturePlacement) -> Facing {
    // Air and fire alarms encode `dir` as the direction their face points
    // into the room, while the blueprint facing records the supporting wall.
    // APCs and light fixtures use the supporting-wall direction directly.
    if matches!(fixture.fixture_id.as_str(), "air_alarm" | "fire_alarm") {
        match fixture.facing {
            Facing::North => Facing::South,
            Facing::East => Facing::West,
            Facing::South => Facing::North,
            Facing::West => Facing::East,
        }
    } else {
        fixture.facing
    }
}

fn tile_preview(class: TileClass, room_style: Option<&str>) -> (&'static str, &'static str) {
    if class == TileClass::Room {
        return match room_style {
            Some("reinforced-tech") => ("icons/turf/flooring/eris/tiles_steel.dmi", "techfloor"),
            Some("sterile-white") => ("icons/turf/flooring/eris/tiles_white.dmi", "tiles"),
            Some("industrial-grid") => ("icons/turf/flooring/eris/tiles_steel.dmi", "panels"),
            Some("executive") => ("icons/turf/flooring/eris/tiles_white.dmi", "golden"),
            _ => ("icons/turf/flooring/tiles.dmi", "steel"),
        };
    }
    match class {
        TileClass::Exterior => ("icons/turf/space.dmi", "0"),
        TileClass::Hull | TileClass::Structure | TileClass::Partition => {
            ("icons/turf/walls.dmi", "0")
        }
        TileClass::Maintenance => ("icons/turf/flooring/tiles.dmi", "steel_dirty"),
        TileClass::Public => ("icons/turf/flooring/tiles.dmi", "white"),
        TileClass::Local => ("icons/turf/flooring/tiles.dmi", "dark"),
        TileClass::DepartmentFloor | TileClass::Room => ("icons/turf/flooring/tiles.dmi", "steel"),
    }
}

fn builtin_fixture_preview(id: &str) -> Option<(&'static str, &'static str)> {
    match id {
        "wall_light" => Some(("icons/obj/lighting.dmi", "tube1")),
        "apc" => Some(("icons/obj/power.dmi", "apc0")),
        // Alarm status frames are overlays, not complete objects. Render the
        // same complete base states that exist before their live update_icon()
        // overlays are applied.
        "air_alarm" => Some(("icons/obj/monitors_vr.dmi", "alarm_0")),
        "fire_alarm" => Some(("icons/obj/monitors.dmi", "fire")),
        "notice_board" => Some(("icons/obj/stationobjs.dmi", "nboard00")),
        "manifest_board" => Some(("icons/obj/stationobjs.dmi", "nboard00")),
        "vent" => Some(("icons/obj/atmospherics/vent_pump.dmi", "off")),
        "scrubber" => Some(("icons/obj/atmospherics/vent_scrubber.dmi", "off")),
        _ if id.contains("chair") || id.contains("seat") => {
            Some(("icons/obj/objects.dmi", "chair"))
        }
        _ if id.contains("table") || id.contains("desk") => {
            Some(("icons/obj/tables.dmi", "plain_preview"))
        }
        _ if id.contains("locker") => Some(("icons/obj/closet.dmi", "closed")),
        _ if id.contains("crate") || id.contains("storage") => {
            Some(("icons/obj/storage.dmi", "crate"))
        }
        _ => None,
    }
}

fn load_sprite(
    root: &Path,
    cache: &mut BTreeMap<PathBuf, SpriteSheet>,
    icon_file: &str,
    state_name: &str,
    facing: Facing,
) -> Result<Option<Vec<u8>>, String> {
    let relative = icon_file
        .replace('\\', "/")
        .trim_start_matches("icons/gen/")
        .to_string();
    let dmi_path = root.join(&relative);
    let png_path = dmi_path.with_extension("png");
    let manifest_path = PathBuf::from(format!("{}.toml", dmi_path.display()));
    if !png_path.exists() || !manifest_path.exists() {
        return Ok(None);
    }
    if !cache.contains_key(&png_path) {
        let manifest: DmiManifest = toml::from_str(
            &fs::read_to_string(&manifest_path)
                .map_err(|error| format!("{}: {error}", manifest_path.display()))?,
        )
        .map_err(|error| format!("{}: {error}", manifest_path.display()))?;
        let decoder = png::Decoder::new(BufReader::new(
            fs::File::open(&png_path)
                .map_err(|error| format!("{}: {error}", png_path.display()))?,
        ));
        let mut reader = decoder
            .read_info()
            .map_err(|error| format!("{}: {error}", png_path.display()))?;
        let size = reader
            .output_buffer_size()
            .ok_or_else(|| format!("{} has no output buffer size", png_path.display()))?;
        let mut raw = vec![0; size];
        let info = reader
            .next_frame(&mut raw)
            .map_err(|error| format!("{}: {error}", png_path.display()))?;
        let rgba = pixels_to_rgba(&raw[..info.buffer_size()], info.color_type)?;
        cache.insert(
            png_path.clone(),
            SpriteSheet {
                manifest,
                rgba,
                width: info.width,
            },
        );
    }
    let sheet = &cache[&png_path];
    let mut prior_cells = 0u32;
    let Some(state) = sheet.manifest.state.iter().find(|state| {
        if state.name == state_name {
            true
        } else {
            prior_cells += state.dirs.max(1) * state.frames.max(1);
            false
        }
    }) else {
        return Ok(None);
    };
    let direction = if state.dirs >= 4 {
        match facing {
            Facing::South => 0,
            Facing::North => 1,
            Facing::East => 2,
            Facing::West => 3,
        }
    } else {
        0
    };
    let cell = prior_cells + direction;
    let sx = (cell % sheet.manifest.cols) * sheet.manifest.width;
    let sy = (cell / sheet.manifest.cols) * sheet.manifest.height;
    let mut sprite = vec![0u8; (TILE_PIXELS * 4) as usize];
    let copy_width = sheet.manifest.width.min(32);
    let copy_height = sheet.manifest.height.min(32);
    for y in 0..copy_height {
        for x in 0..copy_width {
            let source = (((sy + y) * sheet.width + sx + x) * 4) as usize;
            let target = ((y * 32 + x) * 4) as usize;
            sprite[target..target + 4].copy_from_slice(&sheet.rgba[source..source + 4]);
        }
    }
    Ok(Some(sprite))
}

const TILE_PIXELS: u32 = 32 * 32;

fn pixels_to_rgba(raw: &[u8], color: png::ColorType) -> Result<Vec<u8>, String> {
    let mut rgba = Vec::with_capacity(raw.len().saturating_mul(4));
    match color {
        png::ColorType::Rgba => rgba.extend_from_slice(raw),
        png::ColorType::Rgb => {
            for pixel in raw.chunks_exact(3) {
                rgba.extend_from_slice(&[pixel[0], pixel[1], pixel[2], 255]);
            }
        }
        png::ColorType::Grayscale => {
            for value in raw {
                rgba.extend_from_slice(&[*value, *value, *value, 255]);
            }
        }
        png::ColorType::GrayscaleAlpha => {
            for pixel in raw.chunks_exact(2) {
                rgba.extend_from_slice(&[pixel[0], pixel[0], pixel[0], pixel[1]]);
            }
        }
        png::ColorType::Indexed => return Err("indexed PNG was not expanded".to_string()),
    }
    Ok(rgba)
}

fn accent_rgb(style: &str) -> Option<[u8; 3]> {
    Some(match style {
        "command-blue" => [0x46, 0x75, 0x9d],
        "ai-cyan" => [0x33, 0x66, 0xcc],
        "security-red" => [0xaa, 0x5f, 0x61],
        "medical-blue" => [0x75, 0x9c, 0xb8],
        "engineering-yellow" => [0xb9, 0x5a, 0x00],
        "science-purple" => [0xa2, 0x81, 0x9e],
        "cargo-brown" => [0xc9, 0xa3, 0x44],
        "docking-gray" => [0x4c, 0x53, 0x5b],
        "neutral-gray" | "department" => [0x80, 0x80, 0x80],
        _ => return None,
    })
}

fn tint_sprite(sprite: &mut [u8], color: [u8; 3]) {
    for pixel in sprite.chunks_exact_mut(4) {
        pixel[0] = ((u16::from(pixel[0]) * u16::from(color[0])) / 255) as u8;
        pixel[1] = ((u16::from(pixel[1]) * u16::from(color[1])) / 255) as u8;
        pixel[2] = ((u16::from(pixel[2]) * u16::from(color[2])) / 255) as u8;
    }
}

fn blit_tile(pixels: &mut [u8], width: u32, height: u32, point: Point, sprite: &[u8]) {
    blit_tile_offset(pixels, width, height, point, sprite, 0, 0);
}

fn blit_tile_offset(
    pixels: &mut [u8],
    width: u32,
    height: u32,
    point: Point,
    sprite: &[u8],
    offset_x: i32,
    offset_y: i32,
) {
    let origin_x = i32::from(point.x) * 32 + offset_x;
    let origin_y =
        i32::try_from(height).unwrap_or(i32::MAX) - (i32::from(point.y) + 1) * 32 - offset_y;
    for y in 0..32 {
        for x in 0..32 {
            let target_x = origin_x + x;
            let target_y = origin_y + y;
            if target_x < 0 || target_y < 0 || target_x >= width as i32 || target_y >= height as i32
            {
                continue;
            }
            let source = ((y * 32 + x) * 4) as usize;
            let target = ((target_y as u32 * width + target_x as u32) * 4) as usize;
            let alpha = u16::from(sprite[source + 3]);
            for channel in 0..3 {
                pixels[target + channel] = ((u16::from(sprite[source + channel]) * alpha
                    + u16::from(pixels[target + channel]) * (255 - alpha))
                    / 255) as u8;
            }
            pixels[target + 3] = 255;
        }
    }
}

fn upscale_nearest_rgba(width: u32, height: u32, pixels: &[u8], scale: u32) -> Vec<u8> {
    let output_width = width * scale;
    let output_height = height * scale;
    let mut output = vec![0u8; output_width as usize * output_height as usize * 4];
    for y in 0..height {
        for x in 0..width {
            let source = ((y * width + x) * 4) as usize;
            for dy in 0..scale {
                for dx in 0..scale {
                    let target =
                        ((((y * scale + dy) * output_width) + x * scale + dx) * 4) as usize;
                    output[target..target + 4].copy_from_slice(&pixels[source..source + 4]);
                }
            }
        }
    }
    output
}

fn fill_tile(pixels: &mut [u8], width: u32, height: u32, point: Point, color: [u8; 4]) {
    let origin_x = u32::from(point.x) * 32;
    let origin_y = height - (u32::from(point.y) + 1) * 32;
    for y in 0..32 {
        for x in 0..32 {
            let offset = (((origin_y + y) * width + origin_x + x) * 4) as usize;
            pixels[offset..offset + 4].copy_from_slice(&color);
        }
    }
}

fn draw_missing_sprite(pixels: &mut [u8], width: u32, height: u32, point: Point) {
    let origin_x = u32::from(point.x) * 32;
    let origin_y = height - (u32::from(point.y) + 1) * 32;
    for y in 5..27 {
        for x in 5..27 {
            if x == y || x + y == 31 || x == 5 || y == 5 || x == 26 || y == 26 {
                let offset = (((origin_y + y) * width + origin_x + x) * 4) as usize;
                pixels[offset..offset + 4].copy_from_slice(&[255, 0, 210, 255]);
            }
        }
    }
}

fn encode_rgba(width: u32, height: u32, pixels: &[u8]) -> Result<Vec<u8>, String> {
    let mut output = Vec::new();
    {
        let mut encoder = png::Encoder::new(Cursor::new(&mut output), width, height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().map_err(|error| error.to_string())?;
        writer
            .write_image_data(pixels)
            .map_err(|error| error.to_string())?;
    }
    Ok(output)
}

pub fn render_png(layout: &StationLayout, scale: u16) -> Vec<u8> {
    let width = u32::from(layout.width) * u32::from(scale);
    let height = u32::from(layout.height) * u32::from(scale);
    let mut pixels = vec![0u8; width as usize * height as usize * 3];
    for y in 0..layout.height {
        for x in 0..layout.width {
            let cell = layout.tile(Point { x, y });
            let color = tile_rgb(cell.class, cell.owner);
            for pixel_y in 0..scale {
                for pixel_x in 0..scale {
                    let output_x = u32::from(x) * u32::from(scale) + u32::from(pixel_x);
                    let output_y =
                        u32::from(layout.height - 1 - y) * u32::from(scale) + u32::from(pixel_y);
                    let offset = (output_y as usize * width as usize + output_x as usize) * 3;
                    pixels[offset..offset + 3].copy_from_slice(&color);
                }
            }
        }
    }
    for door in &layout.doors {
        let color = if door.maintenance_choke {
            [0xff, 0x9f, 0x43]
        } else if door.connects_maintenance && door.connects_public {
            [0x74, 0xf0, 0xb2]
        } else if door.connects_maintenance && door.room_id.is_some() {
            [0xc9, 0x86, 0xff]
        } else if door.connects_maintenance {
            [0xf6, 0xf6, 0xf6]
        } else if door.connects_public {
            [0x55, 0xe7, 0xff]
        } else {
            [0xff, 0x4f, 0xd8]
        };
        for pixel_y in 0..scale {
            for pixel_x in 0..scale {
                let output_x = u32::from(door.at.x) * u32::from(scale) + u32::from(pixel_x);
                let output_y = u32::from(layout.height - 1 - door.at.y) * u32::from(scale)
                    + u32::from(pixel_y);
                let offset = (output_y as usize * width as usize + output_x as usize) * 3;
                pixels[offset..offset + 3].copy_from_slice(&color);
            }
        }
    }
    let mut output = Vec::new();
    {
        let mut encoder = png::Encoder::new(Cursor::new(&mut output), width, height);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header is valid");
        writer
            .write_image_data(&pixels)
            .expect("PNG raster has the declared dimensions");
    }
    output
}

pub fn render_blueprint_png(blueprint: &StationBlueprint, scale: u16) -> Vec<u8> {
    let layout = &blueprint.layout;
    let width = u32::from(layout.width) * u32::from(scale);
    let height = u32::from(layout.height) * u32::from(scale);
    let mut pixels = vec![0u8; width as usize * height as usize * 3];
    let mut paint = |point: Point, color: [u8; 3], inset: u16| {
        for py in inset..scale.saturating_sub(inset) {
            for px in inset..scale.saturating_sub(inset) {
                let ox = u32::from(point.x) * u32::from(scale) + u32::from(px);
                let oy = u32::from(layout.height - 1 - point.y) * u32::from(scale) + u32::from(py);
                let offset = (oy as usize * width as usize + ox as usize) * 3;
                pixels[offset..offset + 3].copy_from_slice(&color);
            }
        }
    };
    for y in 0..layout.height {
        for x in 0..layout.width {
            let p = Point { x, y };
            paint(p, tile_rgb(layout.tile(p).class, layout.tile(p).owner), 0);
        }
    }
    for room in &blueprint.rooms {
        let route: std::collections::BTreeSet<Point> = room.circulation.iter().copied().collect();
        for p in &room.circulation {
            paint_route_segment(&mut pixels, width, layout.height, scale, *p, *p);
            for neighbor in [
                Point {
                    x: p.x.saturating_add(1),
                    y: p.y,
                },
                Point {
                    x: p.x,
                    y: p.y.saturating_add(1),
                },
            ] {
                if route.contains(&neighbor) {
                    paint_route_segment(&mut pixels, width, layout.height, scale, *p, neighbor);
                }
            }
        }
    }
    let mut paint = |point: Point, color: [u8; 3], inset: u16| {
        for py in inset..scale.saturating_sub(inset) {
            for px in inset..scale.saturating_sub(inset) {
                let ox = u32::from(point.x) * u32::from(scale) + u32::from(px);
                let oy = u32::from(layout.height - 1 - point.y) * u32::from(scale) + u32::from(py);
                let offset = (oy as usize * width as usize + ox as usize) * 3;
                pixels[offset..offset + 3].copy_from_slice(&color);
            }
        }
    };
    for fixture in &blueprint.fixtures {
        for access in &fixture.required_access {
            paint(*access, [0x56, 0xf0, 0xc5], 1);
        }
    }
    for fixture in &blueprint.fixtures {
        let color = if fixture.fixture_id == "wall_light" {
            [0xff, 0xf7, 0xa8]
        } else if fixture.fixture_id == "apc" {
            [0x65, 0xd4, 0x6e]
        } else if fixture.fixture_id.contains("alarm") {
            [0xff, 0x78, 0x5f]
        } else if fixture.fixture_id == "vent" {
            [0x74, 0xd8, 0xff]
        } else if fixture.fixture_id == "scrubber" {
            [0xa4, 0x8c, 0xff]
        } else if fixture.fixture_id.contains("console")
            || fixture.fixture_id.contains("core")
            || fixture.layer == FixtureLayer::Machine
        {
            [0x55, 0xa9, 0xff]
        } else if fixture.fixture_id.contains("table") || fixture.fixture_id.contains("desk") {
            [0xbd, 0x8b, 0x62]
        } else {
            [0xd5, 0xdb, 0xe1]
        };
        if fixture.blocks_movement {
            paint(fixture.at, [0xff, 0x30, 0x4f], 1);
        }
        paint(
            fixture.at,
            color,
            if fixture.layer == FixtureLayer::Wall {
                1
            } else {
                2
            },
        );
    }
    for door in &layout.doors {
        paint(door.at, [0x55, 0xe7, 0xff], 0);
    }
    let mut output = Vec::new();
    {
        let mut encoder = png::Encoder::new(Cursor::new(&mut output), width, height);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().expect("PNG header");
        writer.write_image_data(&pixels).expect("PNG data");
    }
    output
}

fn paint_route_segment(
    pixels: &mut [u8],
    image_width: u32,
    layout_height: u16,
    scale: u16,
    from: Point,
    to: Point,
) {
    let half = u32::from(scale) / 2;
    let thickness = 3u32.min(u32::from(scale));
    let radius = thickness / 2;
    let center = |point: Point| {
        (
            u32::from(point.x) * u32::from(scale) + half,
            u32::from(layout_height - 1 - point.y) * u32::from(scale) + half,
        )
    };
    let (ax, ay) = center(from);
    let (bx, by) = center(to);
    let min_x = ax.min(bx).saturating_sub(radius);
    let max_x = ax.max(bx).saturating_add(radius);
    let min_y = ay.min(by).saturating_sub(radius);
    let max_y = ay.max(by).saturating_add(radius);
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let offset = (y as usize * image_width as usize + x as usize) * 3;
            if offset + 2 < pixels.len() {
                pixels[offset..offset + 3].copy_from_slice(&[0x72, 0x9c, 0xa4]);
            }
        }
    }
}

fn tile_rgb(class: TileClass, owner: Option<u16>) -> [u8; 3] {
    match class {
        TileClass::Exterior => [0x08, 0x0b, 0x10],
        TileClass::Hull => [0x75, 0x80, 0x8d],
        TileClass::Structure => [0x25, 0x2b, 0x33],
        TileClass::Public => [0xe0, 0xb8, 0x4f],
        TileClass::Local => [0xc4, 0x72, 0x32],
        TileClass::Maintenance => [0x54, 0x63, 0x4d],
        TileClass::DepartmentFloor => [0x35, 0x46, 0x5b],
        TileClass::Partition => [0x87, 0x90, 0x9c],
        TileClass::Room => department_rgb(owner.unwrap_or(0)),
    }
}

fn department_rgb(id: u16) -> [u8; 3] {
    const COLORS: [[u8; 3]; 8] = [
        [0x44, 0x6f, 0x91],
        [0x7a, 0x51, 0x6f],
        [0x4e, 0x7d, 0x62],
        [0x81, 0x5b, 0x43],
        [0x65, 0x55, 0x8a],
        [0x89, 0x7d, 0x42],
        [0x3f, 0x77, 0x78],
        [0x78, 0x50, 0x4a],
    ];
    COLORS[usize::from(id) % COLORS.len()]
}

pub fn render_svg(layout: &StationLayout, scale: u16) -> String {
    let w = u32::from(layout.width) * u32::from(scale);
    let h = u32::from(layout.height) * u32::from(scale);
    let full_width = w + 260;
    let mut svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="{full_width}" height="{h}" viewBox="0 0 {full_width} {h}"><rect width="100%" height="100%" fill="#080b10"/><g id="station-raster">"##
    );
    for y in 0..layout.height {
        for x in 0..layout.width {
            let p = Point { x, y };
            let cell = layout.tile(p);
            let color = match cell.class {
                TileClass::Exterior => continue,
                TileClass::Hull => "#75808d",
                TileClass::Structure => "#252b33",
                TileClass::Public => "#e0b84f",
                TileClass::Local => "#c47232",
                TileClass::Maintenance => "#54634d",
                TileClass::DepartmentFloor => "#35465b",
                TileClass::Partition => "#87909c",
                TileClass::Room => department_color(cell.owner.unwrap_or(0)),
            };
            let px = u32::from(x) * u32::from(scale);
            let py = u32::from(layout.height - 1 - y) * u32::from(scale);
            svg.push_str(&format!(
                r##"<rect x="{px}" y="{py}" width="{scale}" height="{scale}" fill="{color}"/>"##
            ));
        }
    }
    svg.push_str("</g><g id=\"semantic-overlays\" font-family=\"monospace\" font-size=\"9\">");
    for department in &layout.departments {
        let x = u32::from(department.bounds.x) * u32::from(scale);
        let y = u32::from(layout.height - department.bounds.top() - 1) * u32::from(scale);
        let width = u32::from(department.bounds.width) * u32::from(scale);
        let height = u32::from(department.bounds.height) * u32::from(scale);
        svg.push_str(&format!(r##"<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="none" stroke="#ffffff" stroke-opacity=".45" stroke-dasharray="3 2"/><text x="{}" y="{}" fill="#ffffff">D{}</text>"##, x + 2, y + 10, department.id));
    }
    for door in &layout.doors {
        let x = u32::from(door.at.x) * u32::from(scale);
        let y = u32::from(layout.height - 1 - door.at.y) * u32::from(scale);
        let color = if door.maintenance_choke {
            "#ff9f43"
        } else if door.connects_maintenance && door.connects_public {
            "#74f0b2"
        } else if door.connects_maintenance && door.room_id.is_some() {
            "#c986ff"
        } else if door.connects_maintenance {
            "#f6f6f6"
        } else if door.connects_public {
            "#55e7ff"
        } else {
            "#ff4fd8"
        };
        svg.push_str(&format!(
            r##"<rect x="{x}" y="{y}" width="{scale}" height="{scale}" fill="{color}" stroke="#080b10" stroke-width="1"/>"##
        ));
    }
    svg.push_str("</g>");
    svg.push_str(&format!(
        r##"<g id="diagnostics" transform="translate({},20)" font-family="monospace" fill="#e8edf2"><text x="0" y="0" font-size="16" font-weight="bold">{:?}</text><text x="0" y="20" font-size="12">seed {}</text>{}</g>"##,
        w + 18,
        layout.archetype,
        layout.seed,
        metric_lines(layout),
    ));
    svg.push_str(&format!(
        r#"<text x="8" y="18" fill="white" font-family="monospace" font-size="12">seed {} · {:?}</text></svg>"#,
        layout.seed, layout.archetype
    ));
    svg
}

/// Complete blueprint visualization: structural raster plus exact furniture,
/// machines, wall fixtures, utility endpoints, circulation, and room labels.
pub fn render_blueprint_svg(blueprint: &StationBlueprint, scale: u16) -> String {
    let layout = &blueprint.layout;
    let w = u32::from(layout.width) * u32::from(scale);
    let h = u32::from(layout.height) * u32::from(scale);
    let full_width = w + 330;
    let mut svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="{full_width}" height="{h}" viewBox="0 0 {full_width} {h}"><rect width="100%" height="100%" fill="#080b10"/><g stroke="#111820" stroke-width=".35">"##
    );
    for y in 0..layout.height {
        for x in 0..layout.width {
            let cell = layout.tile(Point { x, y });
            if cell.class == TileClass::Exterior {
                continue;
            }
            let color = match cell.class {
                TileClass::Hull => "#75808d",
                TileClass::Structure => "#252b33",
                TileClass::Public => "#e0b84f",
                TileClass::Local => "#c47232",
                TileClass::Maintenance => "#54634d",
                TileClass::DepartmentFloor => "#35465b",
                TileClass::Partition => "#87909c",
                TileClass::Room => department_color(cell.owner.unwrap_or(0)),
                TileClass::Exterior => "#080b10",
            };
            svg.push_str(&format!(
                r##"<rect x="{}" y="{}" width="{scale}" height="{scale}" fill="{color}"/>"##,
                u32::from(x) * u32::from(scale),
                u32::from(layout.height - 1 - y) * u32::from(scale)
            ));
        }
    }
    svg.push_str("</g><g id=\"circulation\" fill=\"#b5f4ff\" fill-opacity=\".45\" stroke=\"#b5f4ff\" stroke-opacity=\".45\" stroke-width=\"3\" stroke-linecap=\"square\">");
    for room in &blueprint.rooms {
        let route: std::collections::BTreeSet<Point> = room.circulation.iter().copied().collect();
        for point in &room.circulation {
            let cx = u32::from(point.x) * u32::from(scale) + u32::from(scale) / 2;
            let cy =
                u32::from(layout.height - 1 - point.y) * u32::from(scale) + u32::from(scale) / 2;
            for neighbor in [
                Point {
                    x: point.x.saturating_add(1),
                    y: point.y,
                },
                Point {
                    x: point.x,
                    y: point.y.saturating_add(1),
                },
            ] {
                if route.contains(&neighbor) && neighbor != *point {
                    let nx = u32::from(neighbor.x) * u32::from(scale) + u32::from(scale) / 2;
                    let ny = u32::from(layout.height - 1 - neighbor.y) * u32::from(scale)
                        + u32::from(scale) / 2;
                    svg.push_str(&format!(
                        r##"<path d="M {cx} {cy} L {nx} {ny}" fill="none"/>"##
                    ));
                }
            }
            svg.push_str(&format!(
                r##"<circle cx="{cx}" cy="{cy}" r="1.5" stroke="none"/>"##
            ));
        }
    }
    svg.push_str("</g><g id=\"fixture-access\">");
    for fixture in &blueprint.fixtures {
        for point in &fixture.required_access {
            let x = u32::from(point.x) * u32::from(scale);
            let y = u32::from(layout.height - 1 - point.y) * u32::from(scale);
            svg.push_str(&format!(r##"<rect x="{x}" y="{y}" width="{scale}" height="{scale}" fill="#56f0c5" fill-opacity=".38"><title>required clear access for {}</title></rect>"##, xml(&fixture.fixture_id)));
        }
    }
    svg.push_str("</g><g id=\"fixtures\" stroke=\"#080b10\" stroke-width=\".7\">");
    for fixture in &blueprint.fixtures {
        let x = u32::from(fixture.at.x) * u32::from(scale);
        let y = u32::from(layout.height - 1 - fixture.at.y) * u32::from(scale);
        let (color, shape) = fixture_style(&fixture.fixture_id, fixture.layer);
        let inset = if fixture.layer == FixtureLayer::Wall {
            1
        } else {
            2
        };
        let size = u32::from(scale).saturating_sub(inset * 2).max(2);
        if shape == "circle" {
            svg.push_str(&format!(
                r##"<circle cx="{}" cy="{}" r="{}" fill="{color}"><title>{}</title></circle>"##,
                x + u32::from(scale) / 2,
                y + u32::from(scale) / 2,
                size / 2,
                xml(&fixture.fixture_id)
            ));
        } else {
            svg.push_str(&format!(r##"<rect x="{}" y="{}" width="{size}" height="{size}" rx="1" fill="{color}"><title>{}</title></rect>"##,x+inset,y+inset,xml(&fixture.fixture_id)));
        }
        if fixture.blocks_movement {
            svg.push_str(&format!(r##"<path d="M {} {} L {} {} M {} {} L {} {}" stroke="#ff304f" stroke-width="1" pointer-events="none"/>"##,x+1,y+1,x+u32::from(scale)-1,y+u32::from(scale)-1,x+u32::from(scale)-1,y+1,x+1,y+u32::from(scale)-1));
        }
    }
    svg.push_str("</g><g id=\"doors\">");
    for door in &layout.doors {
        let x = u32::from(door.at.x) * u32::from(scale);
        let y = u32::from(layout.height - 1 - door.at.y) * u32::from(scale);
        svg.push_str(&format!(r##"<rect x="{x}" y="{y}" width="{scale}" height="{scale}" fill="#55e7ff" stroke="#061018" stroke-width="1"/>"##));
    }
    svg.push_str("</g><g font-family=\"sans-serif\" font-size=\"7\" fill=\"#fff\">");
    for room in &blueprint.rooms {
        let x = u32::from(room.activity_center.x) * u32::from(scale) + 2;
        let y = u32::from(layout.height - 1 - room.activity_center.y) * u32::from(scale)
            + u32::from(scale) / 2;
        svg.push_str(&format!(r##"<text x="{x}" y="{y}" paint-order="stroke" stroke="#080b10" stroke-width="2">{}</text>"##,xml(&room.semantic_role)));
    }
    svg.push_str("</g>");
    svg.push_str(&format!(r##"<g transform="translate({},22)" font-family="monospace" fill="#e8edf2"><text font-size="16" font-weight="bold">Complete station blueprint</text><text y="22" font-size="11">seed {} · {:?}</text>{}</g>"##,w+16,layout.seed,layout.archetype,blueprint_metrics(blueprint)));
    svg.push_str("</svg>");
    svg
}

fn fixture_style(id: &str, layer: FixtureLayer) -> (&'static str, &'static str) {
    if id == "wall_light" {
        ("#fff7a8", "circle")
    } else if id == "apc" {
        ("#65d46e", "rect")
    } else if id.contains("alarm") {
        ("#ff785f", "circle")
    } else if id == "vent" {
        ("#74d8ff", "circle")
    } else if id == "scrubber" {
        ("#a48cff", "circle")
    } else if id.contains("chair") || id.contains("stool") || id.contains("bench") {
        ("#8bc5a4", "circle")
    } else if id.contains("table") || id.contains("desk") || id.contains("counter") {
        ("#bd8b62", "rect")
    } else if id.contains("console")
        || id.contains("analyzer")
        || id.contains("core")
        || layer == FixtureLayer::Machine
    {
        ("#55a9ff", "rect")
    } else if id.contains("locker")
        || id.contains("cabinet")
        || id.contains("rack")
        || id.contains("shelf")
    {
        ("#d5a85c", "rect")
    } else {
        ("#d5dbe1", "rect")
    }
}

fn blueprint_metrics(blueprint: &StationBlueprint) -> String {
    let mut output = String::new();
    let mut y = 52;
    for (label, value) in &blueprint.quality {
        output.push_str(&format!(r##"<text y="{y}" font-size="11" fill="#aeb8c2">{}</text><text x="285" y="{y}" text-anchor="end" font-size="11">{value}</text>"##,xml(label)));
        y += 18;
    }
    let legend = [
        ("#55e7ff", "doors"),
        ("#fff7a8", "lights"),
        ("#65d46e", "APCs"),
        ("#ff785f", "alarms"),
        ("#74d8ff", "vents"),
        ("#a48cff", "scrubbers"),
        ("#55a9ff", "machines"),
        ("#bd8b62", "tables/desks"),
        ("#d5a85c", "storage"),
    ];
    y += 18;
    for (color, label) in legend {
        output.push_str(&format!(r##"<rect x="0" y="{}" width="12" height="12" fill="{color}"/><text x="20" y="{y}" font-size="11">{label}</text>"##,y-10));
        y += 18;
    }
    output
}

fn xml(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn metric_lines(layout: &StationLayout) -> String {
    let count = |class| {
        layout
            .tiles
            .iter()
            .filter(|cell| cell.class == class)
            .count()
    };
    let rows = [
        ("departments", layout.departments.len().to_string()),
        ("rooms", layout.rooms.len().to_string()),
        ("doors", layout.doors.len().to_string()),
        ("public tiles", count(TileClass::Public).to_string()),
        ("local tiles", count(TileClass::Local).to_string()),
        ("maintenance", count(TileClass::Maintenance).to_string()),
        ("room tiles", count(TileClass::Room).to_string()),
        ("partitions", count(TileClass::Partition).to_string()),
        ("structural walls", count(TileClass::Structure).to_string()),
    ];
    let mut output = String::new();
    let legend_start = 48 + rows.len() * 19 + 16;
    for (index, (label, value)) in rows.into_iter().enumerate() {
        let y = 48 + index * 19;
        output.push_str(&format!(
            r##"<text x="0" y="{y}" font-size="11" fill="#aeb8c2">{label}</text><text x="190" y="{y}" font-size="11" text-anchor="end">{value}</text>"##
        ));
    }
    let legend = [
        ("#e0b84f", "public"),
        ("#a88744", "local"),
        ("#54634d", "maintenance"),
        ("#35465b", "unassigned department floor"),
        ("#87909c", "partition"),
        ("#252b33", "structural walls"),
        ("#ff4fd8", "room door"),
        ("#55e7ff", "public door"),
        ("#f6f6f6", "maintenance door"),
        ("#ff9f43", "maintenance choke"),
        ("#74f0b2", "public-maintenance door"),
        ("#c986ff", "room service door"),
    ];
    for (index, (color, label)) in legend.into_iter().enumerate() {
        let y = legend_start + index * 19;
        output.push_str(&format!(
            r##"<rect x="0" y="{}" width="12" height="12" fill="{color}"/><text x="20" y="{y}" font-size="11">{label}</text>"##,
            y - 10,
        ));
    }
    output
}

fn department_color(id: u16) -> &'static str {
    const COLORS: [&str; 8] = [
        "#446f91", "#7a516f", "#4e7d62", "#815b43", "#65558a", "#897d42", "#3f7778", "#78504a",
    ];
    COLORS[usize::from(id) % COLORS.len()]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(id: &str, layer: FixtureLayer, facing: Facing) -> FixturePlacement {
        FixturePlacement {
            id: 1,
            fixture_id: id.into(),
            at: Point { x: 2, y: 2 },
            facing,
            layer,
            department_id: 1,
            room_id: Some(1),
            network_id: None,
            variant: 0,
            blocks_movement: false,
            required_access: Vec::new(),
        }
    }

    #[test]
    fn operational_computer_states_are_fixture_specific() {
        let icon = "icons/obj/computer.dmi";
        assert_eq!(
            operational_icon_state("medical_console", icon),
            Some("medcomp")
        );
        assert_eq!(
            operational_icon_state("security_console", icon),
            Some("security")
        );
        assert_eq!(
            operational_icon_state("cargo_console", icon),
            Some("supply")
        );
        assert_eq!(
            operational_icon_state("medical_console", "icons/obj/surgery.dmi"),
            None
        );
    }

    #[test]
    fn wall_fixtures_are_offset_toward_their_supporting_wall() {
        assert_eq!(
            fixture_pixel_offset(&fixture("apc", FixtureLayer::Wall, Facing::East)),
            (22, 0)
        );
        assert_eq!(
            fixture_pixel_offset(&fixture("wall_light", FixtureLayer::Wall, Facing::South)),
            (0, -26)
        );
        assert_eq!(
            fixture_pixel_offset(&fixture("apc", FixtureLayer::Machine, Facing::East)),
            (0, 0)
        );
        assert_eq!(
            fixture_sprite_facing(&fixture("air_alarm", FixtureLayer::Wall, Facing::North)),
            Facing::South
        );
        assert_eq!(
            fixture_sprite_facing(&fixture("apc", FixtureLayer::Wall, Facing::North)),
            Facing::North
        );
    }
}
