use std::{env, fs, path::PathBuf, process};
use verdigris::station_layout::{decode_catalog, generate, render_svg, validate_station_structure};

fn main() {
    let Some(catalog_path) = env::args().nth(1) else {
        eprintln!("usage: station_layout_gallery <catalog.json> <output-directory> [seed ...]");
        process::exit(2);
    };
    let Some(output_path) = env::args().nth(2) else {
        eprintln!("usage: station_layout_gallery <catalog.json> <output-directory> [seed ...]");
        process::exit(2);
    };
    let payload = fs::read_to_string(catalog_path).expect("failed to read station catalog");
    let (base_request, _) = decode_catalog(&payload).expect("failed to decode station catalog");
    let seeds: Vec<u64> = {
        let supplied: Vec<_> = env::args()
            .skip(3)
            .map(|seed| {
                seed.parse()
                    .expect("gallery seeds must be decimal u64 values")
            })
            .collect();
        if supplied.is_empty() {
            vec![1, 2, 3, 4, 5, 41, 123, 124, 999]
        } else {
            supplied
        }
    };
    let output = PathBuf::from(output_path);
    fs::create_dir_all(&output).expect("failed to create gallery directory");
    let mut cards = String::new();
    for seed in seeds {
        let mut request = base_request.clone();
        request.settings.seed = seed;
        let layout = generate(&request).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
        validate_station_structure(&layout)
            .unwrap_or_else(|error| panic!("seed {seed} validation: {error}"));
        let svg = render_svg(&layout, 5);
        fs::write(output.join(format!("seed-{seed}.svg")), &svg)
            .expect("failed to write gallery SVG");
        cards.push_str(&format!(
            "<article><h2>Seed {seed}</h2><p>{} rooms · {} doors · {} maintenance entrances</p>{svg}</article>",
            layout.rooms.len(),
            layout.doors.len(),
            layout.doors.iter().filter(|door| door.connects_maintenance).count(),
        ));
    }
    let html = format!(
        r#"<!doctype html><html><head><meta charset="utf-8"><title>Structural station layouts</title><style>
        :root{{color-scheme:dark}}body{{margin:0;background:#090d12;color:#e8edf2;font-family:system-ui;padding:24px}}
        h1{{margin:0 0 20px}}main{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}}
        article{{background:#111821;border:1px solid #293440;border-radius:10px;padding:12px;overflow:hidden}}
        h2{{margin:0;font-size:18px}}p{{margin:4px 0 10px;color:#aeb8c2;font-size:13px}}
        svg{{width:100%;height:auto;display:block;background:#080b10}}
        </style></head><body><h1>Structural lattice station gallery</h1><main>{cards}</main></body></html>"#
    );
    fs::write(output.join("index.html"), html).expect("failed to write gallery HTML");
    println!("wrote structural station gallery to {}", output.display());
}
