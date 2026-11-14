//! Client lighting's baked glow masks (`code/content/lighting/client_shadow.dm`): a light's glow sprite cut to the floor its light reaches,
//! as the PNG viewers draw the glow with. A mask is named by its shape key `"{margin}|{dx,dy,...}|{blocked dx,dy,...}"` (the cells the light
//! reaches, then the fully opaque cells it sees; [`super::view::shape_key`] builds it), and the pixels follow from the key alone:
//!
//! - a reached tile is solid (the sprite's own pixels);
//! - a tile outside the reach is clear, so a wall holds no light at all;
//! - the edge of a reached tile that borders an unreached *floor* tile fades inward in [`RINGS`] bands of [`RING_STEP`] pixels (a blocked
//!   neighbour, a wall, is a real edge: floor beside it stays full strength, and a tile touching the reach by a corner alone does not fade);
//! - the result is the glow sprite multiplied by that mask, white, so one icon serves every colour.
//!
//! [`MaskStore`] bakes masks to PNG files in one directory, once per key (a key already baked is a hit), and keeps the directory inside a
//! file count and a byte budget by dropping the oldest files first. It owns no thread and no global: the DLL's worker holds one.
use std::collections::{HashMap, HashSet, VecDeque};
use std::fs::{self, File};
use std::io::BufWriter;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

/// Pixels of one world tile.
pub const TILE: i32 = 32;
/// Pixels one fade band adds.
pub const RING_STEP: i32 = 4;
/// Alpha of each fade band, deepest into the reached tile first.
pub const RINGS: [u8; 4] = [0xCC, 0x99, 0x66, 0x33];

/// The cells of a shape key, as offsets from the light.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Shape {
    /// Pixels the glow sprite extends past its own tile on each side.
    pub margin: i32,
    pub reached: HashSet<(i32, i32)>,
    pub blocked: HashSet<(i32, i32)>,
}

fn pairs(text: &str) -> Result<HashSet<(i32, i32)>, String> {
    let mut out = HashSet::new();
    if text.is_empty() {
        return Ok(out);
    }
    let mut numbers = Vec::new();
    for part in text.split(',') {
        numbers.push(
            part.parse::<i32>()
                .map_err(|e| format!("bad offset {part:?}: {e}"))?,
        );
    }
    if numbers.len() % 2 != 0 {
        return Err("an odd number of offsets".to_owned());
    }
    for c in numbers.chunks_exact(2) {
        out.insert((c[0], c[1]));
    }
    Ok(out)
}

impl Shape {
    /// Reads a shape key.
    ///
    /// # Errors
    /// A key that is not `margin|offsets|blocked` (the last part may be left off), or has a margin that is not a whole non-negative number.
    pub fn parse(key: &str) -> Result<Shape, String> {
        let mut parts = key.split('|');
        let margin_text = parts.next().unwrap_or("");
        let margin = margin_text
            .parse::<f32>()
            .map_err(|e| format!("bad margin {margin_text:?}: {e}"))?;
        if !(margin >= 0.0) || margin.fract() != 0.0 || margin > 4096.0 {
            return Err(format!("bad margin {margin_text:?}"));
        }
        let reached = pairs(parts.next().unwrap_or(""))?;
        let blocked = pairs(parts.next().unwrap_or(""))?;
        Ok(Shape {
            margin: margin as i32,
            reached,
            blocked,
        })
    }

    /// Pixels on a side of the glow sprite this shape cuts.
    #[must_use]
    pub fn size(&self) -> i32 {
        self.margin * 2 + TILE
    }
}

/// The 0-based pixel box `[x0, x1) x [y0, y1)` of tile (`dx`, `dy`) grown by `grow` pixels, clamped to a `size` square; `None` when empty.
fn tile_box(
    shape: &Shape,
    size: i32,
    dx: i32,
    dy: i32,
    grow: i32,
) -> Option<(usize, usize, usize, usize)> {
    let x0 = (dx * TILE + shape.margin - grow).max(0);
    let y0 = (dy * TILE + shape.margin - grow).max(0);
    let x1 = ((dx + 1) * TILE + shape.margin + grow).min(size);
    let y1 = ((dy + 1) * TILE + shape.margin + grow).min(size);
    (x0 < x1 && y0 < y1).then_some((x0 as usize, y0 as usize, x1 as usize, y1 as usize))
}

fn fill(alpha: &mut [u8], size: usize, b: (usize, usize, usize, usize), value: u8) {
    for y in b.1..b.3 {
        alpha[y * size + b.0..y * size + b.2].fill(value);
    }
}

/// The mask's alpha, `size * size` bytes, row by row from the top (a tile north of the light, `dy` above 0, is nearer the top): 255 where the light reaches, 0 elsewhere, the fade bands on reached
/// floor edges. Every step overwrites, in this order: reached tiles, the fade bands (widest first, each over every fading tile), then every
/// unreached tile cleared exactly, so the bands show inside the reached tiles only.
#[must_use]
pub fn mask_alpha(shape: &Shape) -> Vec<u8> {
    let size = shape.size();
    let mut alpha = vec![0u8; (size * size) as usize];
    let grid = (shape.margin + TILE - 1) / TILE;
    let mut outside = Vec::new();
    let mut fading = Vec::new();
    for dy in -grid..=grid {
        for dx in -grid..=grid {
            let tile = (dx, dy);
            if shape.reached.contains(&tile) {
                if let Some(b) = tile_box(shape, size, dx, dy, 0) {
                    fill(&mut alpha, size as usize, b, 255);
                }
                continue;
            }
            outside.push(tile);
            // Only a floor edge fades: a tile touching the reach by a corner alone would dim floor beside a wall.
            let beside_reach = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                .iter()
                .any(|(ax, ay)| shape.reached.contains(&(dx + ax, dy + ay)));
            if !shape.blocked.contains(&tile) && beside_reach {
                fading.push(tile);
            }
        }
    }
    for (i, band) in RINGS.iter().enumerate() {
        let grow = (RINGS.len() - i) as i32 * RING_STEP;
        for (dx, dy) in &fading {
            if let Some(b) = tile_box(shape, size, *dx, *dy, grow) {
                fill(&mut alpha, size as usize, b, *band);
            }
        }
    }
    for (dx, dy) in &outside {
        if let Some(b) = tile_box(shape, size, *dx, *dy, 0) {
            fill(&mut alpha, size as usize, b, 0);
        }
    }
    // Built with y counted up from the bottom, as DM and the key count it; a PNG's first row is the top.
    let side = size as usize;
    let mut flipped = Vec::with_capacity(alpha.len());
    for row in alpha.chunks_exact(side).rev() {
        flipped.extend_from_slice(row);
    }
    flipped
}

/// A square RGBA glow sprite, 8 bits a channel.
#[derive(Debug, Clone)]
pub struct Sprite {
    pub size: u32,
    pub rgba: Vec<u8>,
}

impl Sprite {
    /// Reads the first (only) frame of a glow icon: a PNG, or a DMI, which is one (its metadata rides in a text chunk). The image must be
    /// square.
    ///
    /// # Errors
    /// A file that is missing, is not a PNG, or is not square.
    pub fn load(path: &Path) -> Result<Sprite, String> {
        let name = path.display();
        let file = File::open(path).map_err(|e| format!("{name}: {e}"))?;
        let mut decoder = png::Decoder::new(std::io::BufReader::new(file));
        decoder.set_transformations(png::Transformations::normalize_to_color8());
        let mut reader = decoder.read_info().map_err(|e| format!("{name}: {e}"))?;
        let mut buf = vec![0u8; reader.output_buffer_size().ok_or("sprite too large")?];
        let info = reader
            .next_frame(&mut buf)
            .map_err(|e| format!("{name}: {e}"))?;
        if info.width != info.height {
            return Err(format!(
                "{name}: {}x{} is not a single square frame",
                info.width, info.height
            ));
        }
        let data = &buf[..info.buffer_size()];
        let mut rgba = Vec::with_capacity((info.width * info.height) as usize * 4);
        match info.color_type {
            png::ColorType::Rgba => rgba.extend_from_slice(data),
            png::ColorType::Rgb => data
                .chunks_exact(3)
                .for_each(|c| rgba.extend_from_slice(&[c[0], c[1], c[2], 255])),
            png::ColorType::Grayscale => data
                .iter()
                .for_each(|g| rgba.extend_from_slice(&[*g, *g, *g, 255])),
            png::ColorType::GrayscaleAlpha => data
                .chunks_exact(2)
                .for_each(|c| rgba.extend_from_slice(&[c[0], c[0], c[0], c[1]])),
            png::ColorType::Indexed => return Err(format!("{name}: palette was not expanded")),
        }
        Ok(Sprite {
            size: info.width,
            rgba,
        })
    }
}

/// The glow sprite multiplied by the shape's mask (white where the mask has alpha, nothing where it has none), RGBA.
///
/// # Errors
/// A sprite whose size is not the shape's.
pub fn cut(sprite: &Sprite, shape: &Shape) -> Result<Vec<u8>, String> {
    if i64::from(sprite.size) != i64::from(shape.size()) {
        return Err(format!(
            "the glow sprite is {0}x{0} but the shape wants {1}x{1}",
            sprite.size,
            shape.size()
        ));
    }
    let alpha = mask_alpha(shape);
    let mut out = vec![0u8; sprite.rgba.len()];
    for (i, a) in alpha.iter().enumerate() {
        if *a == 0 {
            continue;
        }
        let s = &sprite.rgba[i * 4..i * 4 + 4];
        let o = &mut out[i * 4..i * 4 + 4];
        o[..3].copy_from_slice(&s[..3]);
        o[3] = ((u32::from(s[3]) * u32::from(*a) + 127) / 255) as u8;
    }
    Ok(out)
}

/// Writes `rgba` (`size` square) as a PNG at `path` (through a temporary file, so a reader never sees half of one). Returns its length.
///
/// # Errors
/// A write that fails.
pub fn write_png(path: &Path, size: u32, rgba: &[u8]) -> Result<u64, String> {
    let tmp = path.with_extension("tmp");
    let result = (|| -> Result<(), String> {
        let file = File::create(&tmp).map_err(|e| e.to_string())?;
        let mut encoder = png::Encoder::new(BufWriter::new(file), size, size);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_compression(png::Compression::Fast);
        let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
        writer.write_image_data(rgba).map_err(|e| e.to_string())?;
        writer.finish().map_err(|e| e.to_string())
    })();
    if let Err(e) = result {
        let _ = fs::remove_file(&tmp);
        return Err(format!("{}: {e}", path.display()));
    }
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("{}: {e}", path.display())
    })?;
    fs::metadata(path)
        .map(|m| m.len())
        .map_err(|e| e.to_string())
}

fn fnv(bytes: &[u8], seed: u64) -> u64 {
    let mut h = seed;
    for b in bytes {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// The file name a key bakes to: two 64-bit hashes of the key, so a clash is out of the question.
#[must_use]
pub fn file_name(key: &str) -> String {
    format!(
        "cglow_{:016x}{:016x}.png",
        fnv(key.as_bytes(), 0xcbf2_9ce4_8422_2325),
        fnv(key.as_bytes(), 0x8422_2325_cbf2_9ce4)
    )
}

/// What a store has done (the DM baker's log line reads these).
#[derive(Debug, Default, Clone, Copy)]
pub struct StoreStats {
    pub baked: u64,
    pub hits: u64,
    pub failed: u64,
    pub evicted: u64,
    pub bake_ms_total: f64,
    pub bake_ms_max: f64,
    pub files: u64,
    pub bytes: u64,
}

/// One answered bake.
#[derive(Debug, Clone)]
pub struct Baked {
    pub path: PathBuf,
    /// The file was already there (the key had been baked and the file was still on disk).
    pub hit: bool,
    pub ms: f64,
}

struct Entry {
    path: PathBuf,
    bytes: u64,
}

/// The masks baked into one directory, by key.
pub struct MaskStore {
    dir: PathBuf,
    max_files: usize,
    max_bytes: u64,
    entries: HashMap<String, Entry>,
    order: VecDeque<String>,
    bytes: u64,
    sprites: HashMap<String, Arc<Sprite>>,
    stats: StoreStats,
}

impl MaskStore {
    /// A store writing into `dir` (made if missing), holding at most `max_files` files and `max_bytes` bytes. Masks of an earlier run
    /// (`cglow_*` files the new store does not know) are deleted.
    ///
    /// # Errors
    /// A directory that cannot be made.
    pub fn new(dir: &Path, max_files: usize, max_bytes: u64) -> Result<MaskStore, String> {
        fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        if let Ok(read) = fs::read_dir(dir) {
            for e in read.flatten() {
                if e.file_name().to_string_lossy().starts_with("cglow_") {
                    let _ = fs::remove_file(e.path());
                }
            }
        }
        Ok(MaskStore {
            dir: dir.to_owned(),
            max_files,
            max_bytes,
            entries: HashMap::new(),
            order: VecDeque::new(),
            bytes: 0,
            sprites: HashMap::new(),
            stats: StoreStats::default(),
        })
    }

    #[must_use]
    pub fn dir(&self) -> &Path {
        &self.dir
    }

    #[must_use]
    pub fn stats(&self) -> StoreStats {
        StoreStats {
            files: self.entries.len() as u64,
            bytes: self.bytes,
            ..self.stats
        }
    }

    fn sprite(&mut self, icon: &str) -> Result<Arc<Sprite>, String> {
        if let Some(s) = self.sprites.get(icon) {
            return Ok(Arc::clone(s));
        }
        let s = Arc::new(Sprite::load(Path::new(icon))?);
        self.sprites.insert(icon.to_owned(), Arc::clone(&s));
        Ok(s)
    }

    /// The mask of `key` cut from the glow sprite at `icon`: the file's path, baked now or found already baked.
    ///
    /// # Errors
    /// A key or sprite that cannot be read, or a file that cannot be written (counted in [`StoreStats::failed`]).
    pub fn bake(&mut self, key: &str, icon: &str) -> Result<Baked, String> {
        let started = Instant::now();
        if let Some(e) = self.entries.get(key) {
            if e.path.exists() {
                self.stats.hits += 1;
                return Ok(Baked {
                    path: e.path.clone(),
                    hit: true,
                    ms: started.elapsed().as_secs_f64() * 1000.0,
                });
            }
            // The file was deleted under us: forget it and bake again.
            let gone = self.entries.remove(key);
            self.order.retain(|k| k != key);
            self.bytes -= gone.map_or(0, |g| g.bytes);
        }
        let made = (|| {
            let shape = Shape::parse(key)?;
            let sprite = self.sprite(icon)?;
            let rgba = cut(&sprite, &shape)?;
            let path = self.dir.join(file_name(key));
            let bytes = write_png(&path, sprite.size, &rgba)?;
            Ok::<_, String>((path, bytes))
        })();
        match made {
            Ok((path, bytes)) => {
                let ms = started.elapsed().as_secs_f64() * 1000.0;
                self.stats.baked += 1;
                self.stats.bake_ms_total += ms;
                self.stats.bake_ms_max = self.stats.bake_ms_max.max(ms);
                self.bytes += bytes;
                self.entries.insert(
                    key.to_owned(),
                    Entry {
                        path: path.clone(),
                        bytes,
                    },
                );
                self.order.push_back(key.to_owned());
                self.evict(key);
                Ok(Baked {
                    path,
                    hit: false,
                    ms,
                })
            }
            Err(e) => {
                self.stats.failed += 1;
                Err(e)
            }
        }
    }

    /// Drops the oldest files until the store is inside its budgets, sparing `keep` (the mask just baked).
    fn evict(&mut self, keep: &str) {
        while (self.entries.len() > self.max_files || self.bytes > self.max_bytes)
            && self.order.len() > 1
        {
            let Some(old) = self.order.pop_front() else {
                break;
            };
            if old == keep {
                self.order.push_back(old);
                continue;
            }
            if let Some(e) = self.entries.remove(&old) {
                let _ = fs::remove_file(&e.path);
                self.bytes -= e.bytes;
                self.stats.evicted += 1;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: usize = TILE as usize;

    /// Alpha at pixel (`px`, `py`) of tile (`dx`, `dy`) of a shape's mask, counted from the tile's bottom-left corner (`py` up).
    fn at(shape: &Shape, alpha: &[u8], dx: i32, dy: i32, px: usize, py: usize) -> u8 {
        let size = shape.size() as usize;
        let x = (dx * TILE + shape.margin) as usize + px;
        let y_up = (dy * TILE + shape.margin) as usize + py;
        alpha[(size - 1 - y_up) * size + x]
    }

    /// The nine tiles around the light, as a key of margin 64 (a 160 pixel sprite), with `blocked` listed as walls.
    fn nine(blocked: &str) -> Shape {
        Shape::parse(&format!("64|-1,-1,0,-1,1,-1,-1,0,0,0,1,0,-1,1,0,1,1,1|{blocked}")).unwrap()
    }

    #[test]
    fn parses_a_key() {
        let s = Shape::parse("32|0,0,1,0|0,-1").unwrap();
        assert_eq!(s.margin, 32);
        assert_eq!(s.size(), 96);
        assert!(s.reached.contains(&(1, 0)) && s.blocked.contains(&(0, -1)));
        assert!(Shape::parse("32||").unwrap().reached.is_empty());
        assert!(Shape::parse("x|0,0|").is_err());
        assert!(Shape::parse("32|0,0,1|").is_err());
    }

    #[test]
    fn reached_is_opaque_and_outside_is_clear() {
        let s = nine("");
        let a = mask_alpha(&s);
        assert_eq!(at(&s, &a, 0, 0, T / 2, T / 2), 255);
        assert_eq!(at(&s, &a, 1, 1, 0, 0), 255, "a tile in the reach's corner is solid away from its open edges");
        assert_eq!(at(&s, &a, 2, 2, T / 2, T / 2), 0, "a tile touching the reach by a corner alone is clear");
        assert_eq!(at(&s, &a, 2, 0, T / 2, T / 2), 0);
        assert_eq!(at(&s, &a, -2, -2, 0, 0), 0);
    }

    #[test]
    fn a_floor_edge_fades_inward() {
        // The west edge of the western tile borders unreached floor (-2, 0): four bands of four pixels, faintest outermost.
        let s = nine("");
        let a = mask_alpha(&s);
        let row = T / 2;
        let band: Vec<u8> = (0..T).map(|px| at(&s, &a, -1, 0, px, row)).collect();
        assert!(band[..4].iter().all(|v| *v == 0x33));
        assert!(band[4..8].iter().all(|v| *v == 0x66));
        assert!(band[8..12].iter().all(|v| *v == 0x99));
        assert!(band[12..16].iter().all(|v| *v == 0xCC));
        assert!(band[16..].iter().all(|v| *v == 255), "past the bands the tile is solid");
        // The fade is inside the reached tile: the unreached tile beside it stays clear.
        assert_eq!(at(&s, &a, -2, 0, T - 1, row), 0);
    }

    #[test]
    fn a_wall_edge_is_hard() {
        // A wall column on the west: the western edge keeps full strength, the eastern edge (open floor) fades, and the wall holds no light.
        let s = nine("-2,-1,-2,0,-2,1");
        let a = mask_alpha(&s);
        let row = T / 2;
        assert!((0..T).all(|px| at(&s, &a, -1, 0, px, row) == 255), "beside a wall the floor does not dim");
        assert_eq!(at(&s, &a, 1, 0, T - 1, row), 0x33, "beside open floor it fades");
        assert_eq!(at(&s, &a, -2, 0, T - 1, row), 0, "the wall tile itself holds no light");
    }

    #[test]
    fn the_cut_multiplies_the_sprite() {
        let s = Shape::parse("32|0,0|").unwrap();
        assert_eq!(s.size(), 96);
        let mut rgba = Vec::new();
        for _ in 0..96 * 96 {
            rgba.extend_from_slice(&[10, 20, 30, 200]);
        }
        let sprite = Sprite { size: 96, rgba };
        let out = cut(&sprite, &s).unwrap();
        // The sprite's colour is kept and its alpha scaled by the mask: the tile's middle sits in the deepest band, its corner in the faintest.
        let scaled = |a: u8| ((200u32 * u32::from(a) + 127) / 255) as u8;
        let px = |x: usize, y: usize| &out[(y * 96 + x) * 4..(y * 96 + x) * 4 + 4];
        assert_eq!(px(48, 48), &[10, 20, 30, scaled(0xCC)]);
        assert_eq!(px(32, 63), &[10, 20, 30, scaled(0x33)]);
        // Outside the reach everything is zero.
        assert_eq!(px(0, 0), &[0, 0, 0, 0]);
        let bad = Sprite { size: 64, rgba: vec![0; 64 * 64 * 4] };
        assert!(cut(&bad, &s).is_err());
    }

    fn scratch(label: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("vg-mask-{label}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }

    fn write_sprite(dir: &Path, size: u32) -> String {
        fs::create_dir_all(dir).unwrap();
        let path = dir.join(format!("light_{size}.png"));
        let rgba: Vec<u8> = (0..size * size)
            .flat_map(|_| [255u8, 255, 255, 255])
            .collect();
        write_png(&path, size, &rgba).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn a_baked_png_reads_back_and_a_second_bake_is_a_hit() {
        let root = scratch("bake");
        let icon = write_sprite(&root.join("icons"), 96);
        let mut store = MaskStore::new(&root.join("masks"), 100, 1 << 20).unwrap();
        let key = "32|0,0,1,0|";
        let first = store.bake(key, &icon).unwrap();
        assert!(!first.hit);
        let back = Sprite::load(&first.path).unwrap();
        assert_eq!(back.size, 96);
        let alpha = mask_alpha(&Shape::parse(key).unwrap());
        for (i, a) in alpha.iter().enumerate() {
            assert_eq!(back.rgba[i * 4 + 3], *a, "pixel {i}");
        }
        let again = store.bake(key, &icon).unwrap();
        assert!(again.hit && again.path == first.path);
        let stats = store.stats();
        assert_eq!((stats.baked, stats.hits, stats.files), (1, 1, 1));
        // A file deleted behind the store's back is baked again.
        fs::remove_file(&first.path).unwrap();
        assert!(!store.bake(key, &icon).unwrap().hit);
        // A bad key and a missing sprite are errors, counted.
        assert!(store.bake("x||", &icon).is_err());
        assert!(store.bake(key, "no/such/icon.png").is_ok(), "the sprite is cached by now");
        assert!(store.bake("32|3,3|", "no/such/icon.png").is_err());
        assert_eq!(store.stats().failed, 2);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn the_oldest_files_go_past_the_budget() {
        let root = scratch("evict");
        let icon = write_sprite(&root.join("icons"), 96);
        let mut store = MaskStore::new(&root.join("masks"), 3, 1 << 20).unwrap();
        let keys: Vec<String> = (0..5).map(|i| format!("32|{i},0|")).collect();
        let paths: Vec<PathBuf> = keys
            .iter()
            .map(|k| store.bake(k, &icon).unwrap().path)
            .collect();
        assert!(!paths[0].exists() && !paths[1].exists(), "the oldest two are gone");
        assert!(paths[2].exists() && paths[3].exists() && paths[4].exists());
        let stats = store.stats();
        assert_eq!((stats.files, stats.evicted), (3, 2));
        // A store opened on the directory again clears the files an earlier run left.
        let reopened = MaskStore::new(&root.join("masks"), 3, 1 << 20).unwrap();
        assert!(!paths[4].exists());
        assert_eq!(reopened.stats().files, 0);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn the_byte_budget_holds_too() {
        let root = scratch("bytes");
        let icon = write_sprite(&root.join("icons"), 96);
        let mut store = MaskStore::new(&root.join("masks"), 1000, 1).unwrap();
        for i in 0..4 {
            store.bake(&format!("32|{i},0|"), &icon).unwrap();
        }
        assert_eq!(store.stats().files, 1, "only the newest survives a budget under one file");
        let _ = fs::remove_dir_all(root);
    }
}
