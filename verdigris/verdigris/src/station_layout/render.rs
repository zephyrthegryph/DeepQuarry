use super::model::*;
use std::io::Cursor;

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

fn tile_rgb(class: TileClass, owner: Option<u16>) -> [u8; 3] {
    match class {
        TileClass::Exterior => [0x08, 0x0b, 0x10],
        TileClass::Hull => [0x75, 0x80, 0x8d],
        TileClass::Structure => [0x25, 0x2b, 0x33],
        TileClass::Public => [0xe0, 0xb8, 0x4f],
        TileClass::Local => [0xa8, 0x87, 0x44],
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
                TileClass::Local => "#a88744",
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
