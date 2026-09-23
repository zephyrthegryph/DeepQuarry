use std::{env, fs, process, time::Instant};
use vg_layout::station_layout::{
    decode_catalog, generate, generate_station_blueprint, validate_station_structure,
};

fn main() {
    let Some(path) = env::args().nth(1) else {
        eprintln!("usage: station_layout_stress <catalog.json> [count] [first-seed]");
        process::exit(2);
    };
    let count: u64 = env::args()
        .nth(2)
        .map(|value| value.parse().expect("count must be a positive integer"))
        .unwrap_or(1_000);
    let first_seed: u64 = env::args()
        .nth(3)
        .map(|value| {
            value
                .parse()
                .expect("first seed must be an unsigned integer")
        })
        .unwrap_or(0);
    let payload = fs::read_to_string(path).expect("failed to read station catalog");
    let (base_request, mapping) =
        decode_catalog(&payload).expect("failed to decode station catalog");
    let started = Instant::now();
    let mut total_rooms = 0usize;
    let mut total_doors = 0usize;
    let mut minimum_rooms = usize::MAX;
    let mut maximum_rooms = 0usize;
    let mut total_fixtures = 0usize;
    for seed in first_seed..first_seed.saturating_add(count) {
        let mut request = base_request.clone();
        request.settings.seed = seed;
        let layout = generate(&request).unwrap_or_else(|error| panic!("seed {seed}: {error}"));
        validate_station_structure(&layout)
            .unwrap_or_else(|error| panic!("seed {seed} validation: {error}"));
        let blueprint = generate_station_blueprint(layout, &mapping)
            .unwrap_or_else(|error| panic!("seed {seed} blueprint: {error}"));
        total_rooms += blueprint.rooms.len();
        total_doors += blueprint.layout.doors.len();
        total_fixtures += blueprint.fixtures.len();
        minimum_rooms = minimum_rooms.min(blueprint.rooms.len());
        maximum_rooms = maximum_rooms.max(blueprint.rooms.len());
    }
    let elapsed = started.elapsed();
    println!(
        "validated {count} complete blueprints in {:.3}s ({:.3}ms/blueprint); rooms {minimum_rooms}..{maximum_rooms} avg {:.1}; doors avg {:.1}; fixtures avg {:.1}",
        elapsed.as_secs_f64(),
        elapsed.as_secs_f64() * 1000.0 / count as f64,
        total_rooms as f64 / count as f64,
        total_doors as f64 / count as f64,
        total_fixtures as f64 / count as f64,
    );
}
