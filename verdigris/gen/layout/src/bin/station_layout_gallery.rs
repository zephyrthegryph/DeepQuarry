use std::{env, fs, path::PathBuf, process};
use vg_layout::station_layout::{
    decode_catalog, generate, generate_station_blueprint, render_blueprint_png,
    render_blueprint_sprites, render_blueprint_svg, render_png, render_svg,
    validate_station_structure,
};

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
    let (base_request, mapping) =
        decode_catalog(&payload).expect("failed to decode station catalog");
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
    let render_sprites = env::var_os("DQ_SKIP_SPRITES").is_none();
    fs::create_dir_all(&output).expect("failed to create gallery directory");
    let mut cards = String::new();
    for seed in seeds {
        let mut request = base_request.clone();
        request.settings.seed = seed;
        // Retained catalogs may predate the enlarged live canvas. Galleries
        // should visualize current production geometry, not the old bound.
        request.settings.width = request.settings.width.max(160);
        request.settings.height = request.settings.height.max(160);
        let layout = generate(&request).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
        validate_station_structure(&layout)
            .unwrap_or_else(|error| panic!("seed {seed} validation: {error}"));
        // Always retain the structural artifact. Content failures should be
        // diagnosable from the exact room/corridor geometry that caused them,
        // rather than losing the useful result to a later furnishing panic.
        fs::write(
            output.join(format!("seed-{seed}-layout.svg")),
            render_svg(&layout, 7),
        )
        .expect("failed to write structural SVG");
        fs::write(
            output.join(format!("seed-{seed}-layout.png")),
            render_png(&layout, 7),
        )
        .expect("failed to write structural PNG");
        let blueprint = generate_station_blueprint(layout, &mapping)
            .unwrap_or_else(|error| panic!("seed {seed} content: {error}"));
        let local_by_department: std::collections::BTreeMap<_, _> = blueprint
            .layout
            .tiles
            .iter()
            .filter(|cell| cell.class == vg_layout::station_layout::TileClass::Local)
            .fold(std::collections::BTreeMap::new(), |mut counts, cell| {
                *counts.entry(cell.owner).or_insert(0usize) += 1;
                counts
            });
        println!("seed {seed}: local tiles by department {local_by_department:?}");
        let svg = render_blueprint_svg(&blueprint, 7);
        fs::write(output.join(format!("seed-{seed}.svg")), &svg)
            .expect("failed to write gallery SVG");
        fs::write(
            output.join(format!("seed-{seed}.png")),
            render_blueprint_png(&blueprint, 7),
        )
        .expect("failed to write gallery PNG");
        if render_sprites {
            fs::write(
                output.join(format!("seed-{seed}-sprites.png")),
                render_blueprint_sprites(
                    &blueprint,
                    if PathBuf::from("deepquarry.dme").is_file() {
                        PathBuf::from(".")
                    } else {
                        PathBuf::from("..")
                    }
                    .as_path(),
                )
                .unwrap_or_else(|error| panic!("seed {seed} sprite render: {error}")),
            )
            .expect("failed to write sprite gallery PNG");
        }
        fs::write(
            output.join(format!("seed-{seed}.blueprint.json")),
            serde_json::to_vec_pretty(&blueprint).expect("blueprint serializes"),
        )
        .expect("failed to write blueprint JSON");
        cards.push_str(&format!(
            "<article><h2>Seed {seed}</h2><p>{} rooms · {} doors · {} maintenance entrances</p>{svg}</article>",
            blueprint.rooms.len(),
            blueprint.fixtures.len(),
            blueprint.networks.len(),
        ));
    }
    let html = format!(
        r#"<!doctype html><html><head><meta charset="utf-8"><title>Complete generated stations</title><style>
        :root{{color-scheme:dark}}body{{margin:0;background:#090d12;color:#e8edf2;font-family:system-ui;padding:24px}}
        h1{{margin:0 0 20px}}main{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}}
        article{{background:#111821;border:1px solid #293440;border-radius:10px;padding:12px;overflow:hidden}}
        h2{{margin:0;font-size:18px}}p{{margin:4px 0 10px;color:#aeb8c2;font-size:13px}}
        svg{{width:100%;height:auto;display:block;background:#080b10}}
        </style></head><body><h1>Complete Rust station blueprints</h1><main>{cards}</main></body></html>"#
    );
    fs::write(output.join("index.html"), html).expect("failed to write gallery HTML");
    println!("wrote complete station gallery to {}", output.display());
}
