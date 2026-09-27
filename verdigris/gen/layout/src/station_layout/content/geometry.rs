use super::*;

pub(super) fn step_facing(point: Point, facing: Facing) -> Point {
    match facing {
        Facing::North => Point {
            x: point.x,
            y: point.y.saturating_add(1),
        },
        Facing::South => Point {
            x: point.x,
            y: point.y.saturating_sub(1),
        },
        Facing::East => Point {
            x: point.x.saturating_add(1),
            y: point.y,
        },
        Facing::West => Point {
            x: point.x.saturating_sub(1),
            y: point.y,
        },
    }
}
pub(super) fn face_toward(from: Point, to: Point) -> Facing {
    if from.x.abs_diff(to.x) >= from.y.abs_diff(to.y) {
        if from.x < to.x {
            Facing::East
        } else {
            Facing::West
        }
    } else if from.y < to.y {
        Facing::North
    } else {
        Facing::South
    }
}
pub(super) fn distance(a: Point, b: Point) -> u16 {
    a.x.abs_diff(b.x) + a.y.abs_diff(b.y)
}
pub(super) fn neighbors(layout: &StationLayout, p: Point) -> Vec<Point> {
    point_neighbors(p, layout.width, layout.height)
}
pub(super) fn point_neighbors(p: Point, width: u16, height: u16) -> Vec<Point> {
    let mut v = Vec::new();
    if p.x > 0 {
        v.push(Point { x: p.x - 1, y: p.y })
    }
    if p.x + 1 < width {
        v.push(Point { x: p.x + 1, y: p.y })
    }
    if p.y > 0 {
        v.push(Point { x: p.x, y: p.y - 1 })
    }
    if p.y + 1 < height {
        v.push(Point { x: p.x, y: p.y + 1 })
    }
    v
}
pub(super) fn directed_neighbors(layout: &StationLayout, p: Point) -> Vec<(Point, Facing)> {
    point_neighbors(p, layout.width, layout.height)
        .into_iter()
        .map(|q| {
            (
                q,
                if q.x < p.x {
                    Facing::West
                } else if q.x > p.x {
                    Facing::East
                } else if q.y < p.y {
                    Facing::South
                } else {
                    Facing::North
                },
            )
        })
        .collect()
}
pub(super) fn adjacent_to_wall(layout: &StationLayout, p: Point) -> bool {
    neighbors(layout, p).into_iter().any(|q| {
        matches!(
            layout.tile(q).class,
            TileClass::Hull | TileClass::Structure | TileClass::Partition
        )
    })
}
pub(super) fn has(value: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| value.contains(needle))
}
pub(super) fn department_name(mapping: &CatalogMapping, id: u16) -> &str {
    mapping
        .departments
        .get(&id)
        .map(|d| d.name.as_str())
        .unwrap_or("Department")
}
pub(super) fn select_richest_variant<'a>(
    mapping: &'a CatalogMapping,
    room: &Room,
    role: &str,
) -> &'a CatalogRoomWire {
    let assigned = mapping
        .rooms
        .get(&room.room_type_id)
        .expect("assigned room variant exists");
    let width = room.bounds.width;
    let height = room.bounds.height;
    let area = room.tiles.len() as u32;
    mapping
        .rooms
        .values()
        .filter(|variant| {
            let program = if variant.definition_id.contains("-compact-")
                || variant.definition_id.contains("-micro-")
            {
                compact_room_program(&variant.department_id, &variant.role, 0)
            } else {
                room_program(&variant.department_id, &variant.role, 0)
            };
            // Semantic role names are intentionally reused across departments
            // (reception, storage, operations, equipment). Never enrich a
            // room with another department's same-named program.
            variant.department_id == assigned.department_id
                && variant.role == role
                && area
                    >= variant
                        .minimum_usable_tiles
                        .max(variant.content_area)
                        .max(program.minimum_area)
                && ((width <= variant.max_width + 3 && height <= variant.max_height + 3)
                    || (height <= variant.max_width + 3 && width <= variant.max_height + 3))
        })
        .max_by_key(|variant| {
            let program = if variant.definition_id.contains("-compact-")
                || variant.definition_id.contains("-micro-")
            {
                compact_room_program(&variant.department_id, &variant.role, 0)
            } else {
                room_program(&variant.department_id, &variant.role, 0)
            };
            (
                variant
                    .minimum_usable_tiles
                    .max(variant.content_area)
                    .max(program.minimum_area),
                variant.ideal_usable_tiles.max(program.ideal_area),
            )
        })
        .unwrap_or_else(|| {
            mapping
                .rooms
                .get(&room.room_type_id)
                .expect("assigned room variant exists")
        })
}
pub(super) fn title(value: &str) -> String {
    value
        .split('-')
        .map(|part| {
            let mut chars = part.chars();
            chars
                .next()
                .map(|first| first.to_uppercase().collect::<String>() + chars.as_str())
                .unwrap_or_default()
        })
        .collect::<Vec<_>>()
        .join(" ")
}
pub(super) fn floor_style(aesthetic: &str, role: &str) -> &'static str {
    if has(role, &["ai", "core"]) {
        "reinforced-tech"
    } else if has(role, &["medical", "surgery", "treatment"]) {
        "sterile-white"
    } else if has(role, &["engineering", "workshop", "maintenance"]) {
        "industrial-grid"
    } else if aesthetic.contains("command") {
        "executive"
    } else {
        "department-tile"
    }
}
pub(super) fn accent_style(department: &str, _role: &str) -> &'static str {
    // Accent colour communicates departmental ownership. A room's role may
    // select its tile material/pattern, but must never make (for example) an
    // engineering storeroom look like part of cargo.
    match department {
        "command" => "command-blue",
        "ai" => "ai-cyan",
        "security" => "security-red",
        "medical" => "medical-blue",
        "engineering" => "engineering-yellow",
        "logistics" | "cargo" => "cargo-brown",
        "science" | "research" => "science-purple",
        "docking" => "docking-gray",
        _ => "neutral-gray",
    }
}
