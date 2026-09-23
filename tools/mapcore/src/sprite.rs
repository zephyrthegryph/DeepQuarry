//! DMI source-sheet frame lookup and PNG extraction.

use std::fs;
use std::io::Cursor;
use std::path::Path;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Frame {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

pub fn frame_location(metadata: &str, state_name: &str, direction: u32) -> Result<Frame, String> {
    let data: toml::Value = metadata.parse::<toml::Value>().map_err(|e| e.to_string())?;
    let width = data
        .get("width")
        .and_then(toml::Value::as_integer)
        .ok_or("Missing DMI width")? as u32;
    let height = data
        .get("height")
        .and_then(toml::Value::as_integer)
        .ok_or("Missing DMI height")? as u32;
    let cols = data
        .get("cols")
        .and_then(toml::Value::as_integer)
        .ok_or("Missing DMI columns")? as u32;
    let states = data
        .get("state")
        .and_then(toml::Value::as_array)
        .ok_or("Missing DMI states")?;
    let mut position = 0u32;
    for state in states {
        let name = state
            .get("name")
            .and_then(toml::Value::as_str)
            .ok_or("Unnamed DMI state")?;
        let dirs = state
            .get("dirs")
            .and_then(toml::Value::as_integer)
            .ok_or("Missing DMI dirs")? as u32;
        let frames = state
            .get("frames")
            .and_then(toml::Value::as_integer)
            .ok_or("Missing DMI frames")? as u32;
        if name == state_name {
            let offset = if dirs == 1 {
                0
            } else {
                let order = [2, 1, 4, 8, 6, 10, 5, 9];
                order
                    .iter()
                    .take(dirs as usize)
                    .position(|value| *value == direction)
                    .unwrap_or(0) as u32
            };
            let index = position + offset;
            return Ok(Frame {
                x: index % cols * width,
                y: index / cols * height,
                width,
                height,
            });
        }
        position += dirs * frames;
    }
    Err(format!("Sprite state {state_name:?} is absent"))
}

pub fn extract_png(
    sheet: impl AsRef<Path>,
    metadata: impl AsRef<Path>,
    state: &str,
    direction: u32,
) -> Result<Vec<u8>, String> {
    let meta = fs::read_to_string(metadata).map_err(|e| e.to_string())?;
    let frame = frame_location(&meta, state, direction)?;
    let bytes = fs::read(sheet).map_err(|e| e.to_string())?;
    let mut decoder = png::Decoder::new(Cursor::new(bytes));
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|e| e.to_string())?;
    let mut buffer = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buffer).map_err(|e| e.to_string())?;
    if frame.x + frame.width > info.width || frame.y + frame.height > info.height {
        return Err("Sprite frame exceeds sheet".into());
    }
    let channels = match info.color_type {
        png::ColorType::Rgba => 4,
        png::ColorType::Rgb => 3,
        png::ColorType::GrayscaleAlpha => 2,
        png::ColorType::Grayscale => 1,
        _ => return Err("Unsupported PNG color type".into()),
    };
    let mut pixels = vec![0u8; (frame.width * frame.height * 4) as usize];
    for y in 0..frame.height as usize {
        for x in 0..frame.width as usize {
            let source =
                (((frame.y as usize + y) * info.width as usize) + frame.x as usize + x) * channels;
            let target = (y * frame.width as usize + x) * 4;
            match channels {
                4 => pixels[target..target + 4].copy_from_slice(&buffer[source..source + 4]),
                3 => {
                    pixels[target..target + 3].copy_from_slice(&buffer[source..source + 3]);
                    pixels[target + 3] = 255;
                }
                2 => {
                    pixels[target..target + 3].fill(buffer[source]);
                    pixels[target + 3] = buffer[source + 1];
                }
                _ => {
                    pixels[target..target + 3].fill(buffer[source]);
                    pixels[target + 3] = 255;
                }
            }
        }
    }
    let mut output = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut output, frame.width, frame.height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
        writer
            .write_image_data(&pixels)
            .map_err(|e| e.to_string())?;
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn real_floor_frame() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../icons/turf/flooring");
        let image = extract_png(
            root.join("tiles_vr.png"),
            root.join("tiles_vr.dmi.toml"),
            "tiled",
            2,
        )
        .unwrap();
        assert!(image.starts_with(b"\x89PNG"));
    }
}
