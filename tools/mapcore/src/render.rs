//! Ordered sprite compositing for deterministic map previews and other offline tools.
//! The browser uses the same bottom-to-top quad ordering in its WebGL viewport.
use serde::Deserialize;
use std::collections::HashMap;
use std::fs::File;
use std::io::BufWriter;
use std::path::{Path, PathBuf};

#[derive(Deserialize)]
pub struct Scene {
    pub width: u32,
    pub height: u32,
    #[serde(default = "default_background")]
    pub background: [u8; 4],
    pub quads: Vec<Quad>,
}

fn default_background() -> [u8; 4] { [16, 25, 27, 255] }

#[derive(Deserialize)]
pub struct Quad {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    #[serde(default = "white")]
    pub tint: [u8; 4],
    pub sprite: Option<PathBuf>,
    pub crop: Option<[u32; 4]>,
}

fn white() -> [u8; 4] { [255; 4] }

struct Texture { width: u32, height: u32, pixels: Vec<u8> }

fn read_texture(path: &Path) -> Result<Texture, String> {
    let file = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut decoder = png::Decoder::new(file);
    decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
    let mut reader = decoder.read_info().map_err(|e| e.to_string())?;
    let mut bytes = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut bytes).map_err(|e| e.to_string())?;
    let mut pixels = Vec::with_capacity(info.width as usize * info.height as usize * 4);
    for pixel in bytes[..info.buffer_size()].chunks_exact(match info.color_type {
        png::ColorType::Rgba => 4, png::ColorType::Rgb => 3,
        png::ColorType::GrayscaleAlpha => 2, png::ColorType::Grayscale => 1,
        _ => return Err("Unsupported PNG color format".into()),
    }) {
        match info.color_type {
            png::ColorType::Rgba => pixels.extend_from_slice(pixel),
            png::ColorType::Rgb => pixels.extend_from_slice(&[pixel[0], pixel[1], pixel[2], 255]),
            png::ColorType::GrayscaleAlpha => pixels.extend_from_slice(&[pixel[0], pixel[0], pixel[0], pixel[1]]),
            png::ColorType::Grayscale => pixels.extend_from_slice(&[pixel[0], pixel[0], pixel[0], 255]),
            _ => unreachable!(),
        }
    }
    Ok(Texture { width: info.width, height: info.height, pixels })
}

pub fn rgba(scene: &Scene, base: &Path) -> Result<Vec<u8>, String> {
    let count = (scene.width as usize).checked_mul(scene.height as usize)
        .and_then(|n| n.checked_mul(4)).ok_or("Image is too large")?;
    if count > 512 * 1024 * 1024 { return Err("Image is too large".into()); }
    let mut result = vec![0; count];
    for pixel in result.chunks_exact_mut(4) { pixel.copy_from_slice(&scene.background); }
    let mut textures = HashMap::<PathBuf, Texture>::new();
    for quad in &scene.quads {
        if quad.width == 0 || quad.height == 0 { continue; }
        let texture = if let Some(path) = &quad.sprite {
            let full = base.join(path);
            if !textures.contains_key(&full) { textures.insert(full.clone(), read_texture(&full)?); }
            textures.get(&full)
        } else { None };
        let crop = quad.crop.unwrap_or_else(|| texture.map_or([0, 0, 1, 1], |t| [0, 0, t.width, t.height]));
        if crop[2] == 0 || crop[3] == 0 { continue; }
        for dy in 0..quad.height {
            let y = quad.y + dy as i32;
            if y < 0 || y >= scene.height as i32 { continue; }
            for dx in 0..quad.width {
                let x = quad.x + dx as i32;
                if x < 0 || x >= scene.width as i32 { continue; }
                let sample = if let Some(t) = texture {
                    let sx = crop[0] + dx * crop[2] / quad.width;
                    let sy = crop[1] + dy * crop[3] / quad.height;
                    if sx >= t.width || sy >= t.height { continue; }
                    let offset = ((sy * t.width + sx) * 4) as usize;
                    &t.pixels[offset..offset + 4]
                } else { &[255, 255, 255, 255][..] };
                let target = ((y as u32 * scene.width + x as u32) * 4) as usize;
                let alpha = sample[3] as u32 * quad.tint[3] as u32 / 255;
                for channel in 0..3 {
                    let source = sample[channel] as u32 * quad.tint[channel] as u32 / 255;
                    result[target + channel] = ((source * alpha + result[target + channel] as u32 * (255 - alpha) + 127) / 255) as u8;
                }
                result[target + 3] = 255;
            }
        }
    }
    Ok(result)
}

pub fn render_png(scene: &Scene, base: &Path, output: &Path) -> Result<(), String> {
    let image = rgba(scene, base)?;
    let writer = BufWriter::new(File::create(output).map_err(|e| e.to_string())?);
    let mut encoder = png::Encoder::new(writer, scene.width, scene.height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    encoder.write_header().map_err(|e| e.to_string())?
        .write_image_data(&image).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn composites_in_order_with_tint() {
        let scene = Scene { width: 2, height: 1, background: [0, 0, 0, 255], quads: vec![
            Quad { x: 0, y: 0, width: 2, height: 1, tint: [200, 0, 0, 255], sprite: None, crop: None },
            Quad { x: 1, y: 0, width: 1, height: 1, tint: [0, 0, 200, 255], sprite: None, crop: None },
        ]};
        assert_eq!(rgba(&scene, Path::new(".")).unwrap(), vec![200,0,0,255,0,0,200,255]);
    }
}
