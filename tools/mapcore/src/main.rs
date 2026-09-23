use deepquarry_mapcore::{sprite, Map};
use std::env;
use std::fs;

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("inspect") => {
            let map = Map::read(args.get(2).ok_or("Usage: mapcore inspect MAP.dmm")?)?;
            println!("{}", serde_json::to_string(&serde_json::json!({"size": map.size, "dictionary_entries": map.dictionary.len(), "tiles": map.grid.len(), "paths": map.used_atom_paths()})).map_err(|e| e.to_string())?);
        }
        Some("roundtrip") => {
            let map = Map::read(args.get(2).ok_or("Usage: mapcore roundtrip INPUT.dmm OUTPUT.dmm")?)?;
            let output = map.write_tgm()?;
            Map::parse(&output)?;
            fs::write(args.get(3).ok_or("Missing output path")?, output).map_err(|e| e.to_string())?;
        }
        Some("sprite") => {
            let image = sprite::extract_png(args.get(2).ok_or("Missing PNG sheet")?, args.get(3).ok_or("Missing DMI TOML")?, args.get(4).ok_or("Missing state")?, args.get(5).ok_or("Missing direction")?.parse().map_err(|_| "Invalid direction")?)?;
            fs::write(args.get(6).ok_or("Missing output PNG")?, image).map_err(|e| e.to_string())?;
        }
        _ => return Err("Usage: mapcore inspect MAP | roundtrip INPUT OUTPUT | sprite PNG DMI_TOML STATE DIR OUTPUT".into()),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("mapcore: {error}");
        std::process::exit(1);
    }
}
