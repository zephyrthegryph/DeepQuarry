//! Phase 4b guard: the Rust heap peak of a Southern Cross-sized boot.
//!
//! The 32-bit DreamDaemon shares one 4 GB address space between BYOND and the
//! DLL. When the Rust heap peaked at 1.85 GB during boot, most large-explosion
//! boots died on a failed ~9 MB allocation (`doc/rewrite/init_and_turfs.md`
//! §0.1). This drives the same registration path SSair's `setup_allturfs()`
//! uses (8192-turf batches of gas then heat registration), on a grid the size
//! of Southern Cross, and then the first frames, and bounds the peak.

use vg_gas::cell::{GasCell, flags as gas_flags};
use vg_gas::gas::constants::CELL_VOLUME;

use crate::allocator;
use crate::heat::{HEAT_CELL_SOLID, HEAT_CELL_SPACE};
use crate::world::{configure_for_test, with_world};

/// Southern Cross: 256 x 256, three station decks plus CentCom and transit.
const MAX_X: u32 = 256;
const MAX_Y: u32 = 256;
const MAX_Z: u32 = 5;
/// Station air per deck: a central block, about the ~50k air turfs of the
/// live map over its decks. Everything else is space.
const STATION_HALF: u32 = 65;
/// SSair registers turfs in batches of this many (`setup_allturfs()`).
const BATCH: usize = 8192;
/// Frames stepped after registration: the first frames copy every chunk the
/// registration dirtied, which is where the old peak came from.
const FRAMES: usize = 6;
/// The bound. This path measured 255 MB before the bulk direct writes and
/// lazy flux buffers, 113 MB after, and 55 MB once uniform vacuum chunks
/// shared one allocation, substeps stopped snapshotting and owner fluxes
/// were summed per cell (the ceiling is that plus ~25%); the live boot
/// peak was 384 MB and once 1.85 GB.
const PEAK_CEILING_MB: f64 = 70.0;

fn mb(bytes: u64) -> f64 {
    bytes as f64 / 1_048_576.0
}

fn is_station(x: u32, y: u32, z: u32) -> bool {
    let c = MAX_X / 2;
    z < 3 && x.abs_diff(c) < STATION_HALF && y.abs_diff(c) < STATION_HALF
}

fn air() -> GasCell {
    // N2/O2 at 293 K: the first two gases, as a station floor holds.
    let mut moles = [0.0; vg_gas::cell::N];
    moles[0] = 82.0;
    moles[1] = 21.8;
    GasCell::new(moles, 293.15)
}

fn vacuum() -> GasCell {
    let mut v = GasCell::new([0.0; vg_gas::cell::N], 2.7);
    v.flags |= gas_flags::IMMUTABLE;
    v
}

struct Stage {
    name: &'static str,
    current_mb: f64,
    peak_mb: f64,
}

fn stage(stages: &mut Vec<Stage>, name: &'static str) {
    let (current, peak) = allocator::diagnostics();
    stages.push(Stage {
        name,
        current_mb: mb(current),
        peak_mb: mb(peak),
    });
}

#[test]
fn southern_cross_boot_rust_heap_peak_is_bounded() {
    boot(false);
}

/// The live boot: a few turfs register one by one before `setup_allturfs()`
/// (`SSair.add_to_active()` on an initialized turf during SSatoms: atoms that
/// spawn gas, pipelines, fires), which queues port writes in both gas and
/// heat domains. No frame runs during init, so before the bulk bind folded
/// those writes in, every bulk flush saw a non-quiescent domain and sent the
/// whole map through commands and the overlay: half of the live boot's
/// flushes (`bulk.port_fallback_flushes`), +67 MB at "air: turfs registered"
/// and no uniform-chunk sharing (`doc/rewrite/init_and_turfs.md` §0.2b).
#[test]
fn early_single_registrations_keep_the_bulk_path() {
    boot(true);
}

/// The allocator's counters are process-wide: one boot at a time.
static BOOT: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn boot(early_writes: bool) {
    let _one_at_a_time = BOOT
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let mut stages = Vec::new();
    allocator::reset_peak();
    let (base, _) = allocator::diagnostics();
    configure_for_test(MAX_X, MAX_Y, MAX_Z).unwrap();
    stage(&mut stages, "world built");

    let gas = crate::gas::turf_key().unwrap();
    let heat = crate::heat::field().unwrap();
    let fallbacks_before = crate::metrics::registry()
        .counter("bulk.port_fallback_flushes")
        .get();
    if early_writes {
        // Per-cell registrations outside any bulk bind, as update_air_ref does.
        let c = MAX_X / 2;
        for i in 0..4 {
            let cell = c * MAX_X + c + i;
            with_world(|w| {
                crate::gas::register_cell(w, gas, cell, air(), CELL_VOLUME, false, Some(0));
                Ok(())
            })
            .unwrap();
            crate::heat::set_turf(
                heat,
                cell,
                HEAT_CELL_SOLID,
                20_000.0,
                0.5,
                0.9,
                293.15,
                true,
            )
            .unwrap();
        }
    }
    let cells: Vec<(u32, bool)> = (0..MAX_Z)
        .flat_map(|z| {
            (0..MAX_Y).flat_map(move |y| {
                (0..MAX_X).map(move |x| (z * MAX_X * MAX_Y + y * MAX_X + x, is_station(x, y, z)))
            })
        })
        .collect();
    let (floor, vac) = (air(), vacuum());
    for batch in cells.chunks(BATCH) {
        // As `_auxmos_register_turfs_bulk` and `heat_set_turfs_bulk` do.
        crate::gas::with_bulk(|| {
            with_world(|w| {
                for &(cell, station) in batch {
                    let value = if station { floor } else { vac };
                    crate::gas::register_cell(w, gas, cell, value, CELL_VOLUME, !station, Some(0));
                }
                Ok(())
            })
        })
        .unwrap();
        crate::heat::with_bulk(heat, || {
            for &(cell, station) in batch {
                let kind = if station {
                    HEAT_CELL_SOLID
                } else {
                    HEAT_CELL_SPACE
                };
                crate::heat::set_turf(heat, cell, kind, 20_000.0, 0.5, 0.9, 293.15, true)?;
            }
            Ok(())
        })
        .unwrap();
    }
    stage(&mut stages, "turfs registered");
    let fallbacks = crate::metrics::registry()
        .counter("bulk.port_fallback_flushes")
        .get()
        - fallbacks_before;
    assert_eq!(
        fallbacks, 0,
        "{fallbacks} bulk flushes went through commands and the overlay instead of the live store"
    );

    for i in 0..FRAMES {
        with_world(|w| {
            w.step_blocking();
            if std::env::var_os("VG_BOOT_MEM_DETAIL").is_some() {
                for (name, m) in w.sim().memory() {
                    eprintln!("  frame {i} port {name}: {m:?}");
                }
            }
            Ok(())
        })
        .unwrap();
        if std::env::var_os("VG_BOOT_MEM_DETAIL").is_some() {
            let (c, p) = allocator::diagnostics();
            eprintln!(
                "  frame {i}: current {:.1} peak {:.1}",
                mb(c) - mb(base),
                mb(p) - mb(base)
            );
        }
    }
    stage(&mut stages, "first frames");

    for s in &stages {
        eprintln!(
            "boot memory: {:<18} current {:>8.1} MB  peak {:>8.1} MB",
            s.name,
            s.current_mb - mb(base),
            s.peak_mb - mb(base)
        );
    }
    let peak = stages.last().map_or(0.0, |s| s.peak_mb) - mb(base);
    assert!(
        peak <= PEAK_CEILING_MB,
        "a Southern Cross-sized boot peaked at {peak:.1} MB of Rust heap, above the \
         {PEAK_CEILING_MB} MB ceiling: a registration or frame path holds a whole-grid copy again \
         (doc/rewrite/init_and_turfs.md §0.2)"
    );
}
