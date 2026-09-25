use std::{env, fs, path::PathBuf, process};
use vg_layout::station_layout::{StationBlueprint, render_blueprint_sprites};

fn main() {
    let Some(input) = env::args().nth(1) else {
        eprintln!(
            "usage: station_blueprint_render <blueprint.json> <output.png> [repository-root]"
        );
        process::exit(2);
    };
    let Some(output) = env::args().nth(2) else {
        eprintln!(
            "usage: station_blueprint_render <blueprint.json> <output.png> [repository-root]"
        );
        process::exit(2);
    };
    let root = env::args().nth(3).unwrap_or_else(|| "..".to_string());
    let mut blueprint: StationBlueprint =
        serde_json::from_slice(&fs::read(input).expect("read blueprint"))
            .expect("decode blueprint");
    if let Some(preview_source) = env::args().nth(4) {
        let donor: StationBlueprint =
            serde_json::from_slice(&fs::read(preview_source).expect("read preview blueprint"))
                .expect("decode preview blueprint");
        blueprint.sprite_previews.extend(donor.sprite_previews);
    }
    let png = render_blueprint_sprites(&blueprint, PathBuf::from(root).as_path())
        .expect("render blueprint sprites");
    fs::write(output, png).expect("write sprite render");
}
