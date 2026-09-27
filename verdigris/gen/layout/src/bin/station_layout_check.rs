use std::{env, fs, process};
use vg_layout::station_layout::{decode_catalog, encode_plan, generate, render_png, render_svg};

fn main() {
    let Some(path) = env::args().nth(1) else {
        eprintln!("usage: station_layout_check <catalog.json>");
        process::exit(2);
    };
    let payload = fs::read_to_string(path).expect("failed to read station catalog");
    let (request, mapping) = decode_catalog(&payload).expect("failed to decode station catalog");
    let started = std::time::Instant::now();
    let layout = generate(&request).expect("failed to generate station layout");
    let encoded = encode_plan(&layout, &mapping).expect("failed to encode station layout");
    if let Some(output_path) = env::args().nth(2) {
        fs::write(output_path, &encoded).expect("failed to write station plan");
    }
    if let Some(svg_path) = env::args().nth(3) {
        fs::write(svg_path, render_svg(&layout, 6)).expect("failed to write station SVG");
    }
    if let Some(png_path) = env::args().nth(4) {
        fs::write(png_path, render_png(&layout, 8)).expect("failed to write station PNG");
    }
    println!(
        "generated {} rooms, {} doors, {} bytes in {:.3}s",
        layout.rooms.len(),
        layout.doors.len(),
        encoded.len(),
        started.elapsed().as_secs_f64()
    );
}
