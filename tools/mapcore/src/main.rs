use deepquarry_mapcore::{render, sprite, Map};
use std::env;
use std::fs;
use std::io::{self, BufRead, Write};

fn dispatch(request: serde_json::Value) -> Result<serde_json::Value,String> {
    let method=request.get("method").and_then(serde_json::Value::as_str).ok_or("Missing method")?;
    match method {
        "route" => {
            let input=serde_json::from_value(request.get("args").cloned().ok_or("Missing arguments")?)
                .map_err(|e| e.to_string())?;
            serde_json::to_value(deepquarry_mapcore::network::route(input)?)
                .map_err(|e| e.to_string())
        }
        _ => Err("Unknown mapcore method".into()),
    }
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("serve") => {
            for line in io::stdin().lock().lines() {
                let line=line.map_err(|e| e.to_string())?;
                let result=serde_json::from_str(&line).map_err(|e| e.to_string()).and_then(dispatch);
                let response=match result {Ok(value)=>value,Err(error)=>serde_json::json!({"error":error})};
                println!("{}",response);
                io::stdout().flush().map_err(|e| e.to_string())?;
            }
        }
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
        Some("render") => {
            let input = args.get(2).ok_or("Usage: mapcore render SCENE.json OUTPUT.png")?;
            let output = args.get(3).ok_or("Missing output PNG path")?;
            let scene: render::Scene = serde_json::from_slice(&fs::read(input).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
            render::render_png(&scene, std::path::Path::new(input).parent().unwrap_or(std::path::Path::new(".")), std::path::Path::new(output))?;
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
