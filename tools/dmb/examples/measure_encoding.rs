//! Built-in, single-process encoding measurement. No sampler or runtime launch.
//! This measures encoding a decoded image, not symbolic linking or a compiler.
use byond_dmb::dmb::Dmb;
use std::{error::Error, fs, time::Instant};

fn main() -> Result<(), Box<dyn Error>> {
    let path = std::env::args().nth(1).ok_or("expected compiled DMB path")?;
    let stage = Instant::now();
    let source = fs::read(&path)?;
    let read_seconds = stage.elapsed().as_secs_f64();
    let input_md5 = format!("{:x}", md5::compute(&source));
    let stage = Instant::now();
    let image = Dmb::from_bytes(&source)?;
    let decode_seconds = stage.elapsed().as_secs_f64();
    let stage = Instant::now();
    image.validate_references()?;
    let validate_seconds = stage.elapsed().as_secs_f64();
    let stage = Instant::now();
    let encoded = image.to_bytes()?;
    let encode_seconds = stage.elapsed().as_secs_f64();
    let byte_identical = source == encoded;
    println!("{}", serde_json::json!({
        "scope": "decoded-dmb-encoding-only",
        "path": path,
        "input_bytes": source.len(),
        "input_md5": input_md5,
        "output_bytes": encoded.len(),
        "byte_identical": byte_identical,
        "read_seconds": read_seconds,
        "decode_seconds": decode_seconds,
        "validation_seconds": validate_seconds,
        "encoding_seconds": encode_seconds,
        "includes_symbolic_linking": false,
        "includes_publication": false,
        "includes_resource_encoding": false,
    }));
    if !byte_identical { return Err("decoded image did not re-encode byte-identically".into()); }
    Ok(())
}
