//! Binds for the propagation users (`simulation.md` §8): radiation shielding
//! and EMP falloff.
//!
//! The radiation insulation layer lives here as process state until M1b folds
//! it into the frame model; every call is synchronous. Coordinates are DM's
//! one-based turf coordinates.
use std::sync::Mutex;

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_core::grid::GridDims;
use vg_core::propagate::{RadiationField, emp};

static FIELD: Mutex<Option<RadiationField>> = Mutex::new(None);

fn number(value: &ByondValue) -> Result<f32> {
    Ok(value.get_number()?)
}

/// One-based DM coordinate to zero-based.
fn coord(value: &ByondValue) -> Result<u32> {
    let n = number(value)?;
    if !n.is_finite() || n < 1.0 {
        bail!("invalid turf coordinate {n}");
    }
    Ok(n as u32 - 1)
}

fn numbers(list: &ByondValue) -> Result<Vec<f32>> {
    list.get_list_values()?.iter().map(number).collect()
}

/// Writes radiation transmission for changed turfs. `cells` is a flat list of
/// `x, y, z, transmission`. The field is sized to the plane `max_x` by
/// `max_y` (z-levels are added as written) and reset if the plane changes.
#[auxmacros::bind("/proc/radiation_set_cells")]
fn radiation_set_cells(
    max_x: ByondValue,
    max_y: ByondValue,
    cells: ByondValue,
) -> Result<ByondValue> {
    let Some(dims) = GridDims::planar(number(&max_x)? as u32, number(&max_y)? as u32) else {
        bail!("invalid radiation grid plane");
    };
    let values = numbers(&cells)?;
    let mut guard = FIELD
        .lock()
        .map_err(|_| eyre::eyre!("radiation field poisoned"))?;
    let field = match guard.as_mut() {
        Some(field) if field.dims() == dims => field,
        _ => guard.insert(RadiationField::new(dims)),
    };
    for cell in values.chunks_exact(4) {
        let (x, y, z) = (cell[0] as u32, cell[1] as u32, cell[2] as u32);
        if x == 0 || y == 0 || z == 0 {
            continue;
        }
        if let Some(index) = dims.index(x - 1, y - 1, z - 1) {
            field.set_transmission(index, cell[3]);
        }
    }
    Ok(ByondValue::null())
}

/// One radiation pulse from (`x`, `y`, `z`): returns the path transmission
/// to each target in `targets` (a flat list of `x, y, z`), or -1 for targets
/// out of `range`, on another z-level or off the grid. Rays stop early once
/// the transmission drops below `threshold`.
#[auxmacros::bind("/proc/radiation_pulse")]
fn radiation_pulse(
    x: ByondValue,
    y: ByondValue,
    z: ByondValue,
    range: ByondValue,
    threshold: ByondValue,
    targets: ByondValue,
) -> Result<ByondValue> {
    let source = (coord(&x)?, coord(&y)?, coord(&z)?);
    let range = number(&range)?.max(0.0) as u32;
    let threshold = number(&threshold)?;
    let flat = numbers(&targets)?;
    let targets: Vec<(u32, u32, u32)> = flat
        .chunks_exact(3)
        .map(|t| {
            let c = |v: f32| (v as u32).wrapping_sub(1);
            (c(t[0]), c(t[1]), c(t[2]))
        })
        .collect();
    let guard = FIELD
        .lock()
        .map_err(|_| eyre::eyre!("radiation field poisoned"))?;
    let result = match guard.as_ref() {
        Some(field) => field.pulse(source, range, threshold, &targets),
        None => bail!("radiation field used before radiation_set_cells"),
    };
    let values: Vec<ByondValue> = result.into_iter().map(ByondValue::from).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&values)?;
    Ok(list)
}

/// EMP severity around (`x`, `y`, `z`) with the four band radii in `ranges`
/// (non-decreasing). Returns `list(min_x, min_y, max_x, max_y, severity...)`
/// with severities in `block()` order over that square, clipped to the map:
/// 1 heavy .. 4 harmless, `n.5` a coin flip between `n` and `n + 1`.
#[auxmacros::bind("/proc/emp_falloff")]
#[allow(clippy::too_many_arguments)]
fn emp_falloff(
    x: ByondValue,
    y: ByondValue,
    z: ByondValue,
    max_x: ByondValue,
    max_y: ByondValue,
    max_z: ByondValue,
    ranges: ByondValue,
) -> Result<ByondValue> {
    let Some(dims) = GridDims::new(
        number(&max_x)? as u32,
        number(&max_y)? as u32,
        number(&max_z)? as u32,
    ) else {
        bail!("invalid emp grid");
    };
    let r = numbers(&ranges)?;
    if r.len() != 4 {
        bail!("emp_falloff needs four ranges");
    }
    let band = |v: f32| v.max(0.0) as u32;
    let ranges = [band(r[0]), band(r[1]), band(r[2]), band(r[3])];
    let Some(f) = emp::falloff(dims, (coord(&x)?, coord(&y)?, coord(&z)?), ranges) else {
        bail!("emp epicentre is off the map");
    };
    let mut values = Vec::with_capacity(4 + f.severity.len());
    for v in [f.min.0 + 1, f.min.1 + 1, f.max.0 + 1, f.max.1 + 1] {
        values.push(ByondValue::from(v as f32));
    }
    values.extend(f.severity.into_iter().map(ByondValue::from));
    let list = ByondValue::new_list()?;
    list.write_list(&values)?;
    Ok(list)
}
