//! Binds for the world opacity layer (the grid's [`BlockKind::Opacity`]
//! faces): DM writes each turf's `directional_opacity` here, and sight users
//! (lighting, line of sight) read [`view`] over it. Coordinates are DM's
//! one-based turf coordinates.
use crate::held::HeldRead;
use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::grid::{BlockKind, Dir};
use vg_core::propagate::view::{shape_key, view};

use crate::arg::num;
use crate::world::with_world;

/// Writes the opacity of changed turfs: `cells` is a flat list of
/// `x, y, z, mask` (`mask` is BYOND directions, `ALL_CARDINALS` for a fully
/// opaque turf). Returns how many cells were written; a cell outside the grid
/// (not configured yet, or a z-level it has not grown to) is skipped.
#[auxmacros::bind("/proc/sight_set_cells")]
fn sight_set_cells(cells: ByondValue) -> Result<ByondValue> {
    let values: Vec<f32> = cells.held_list()?.iter().map(num).collect::<Result<_>>()?;
    if values.len() % 4 != 0 {
        bail!(
            "sight_set_cells: {} values is not a list of x, y, z, mask",
            values.len()
        );
    }
    let written = with_world(|w| {
        let dims = w.grid().map_err(|e| eyre!("{e}"))?.dims();
        let mut written = 0u32;
        w.edit_grid(|g| {
            for c in values.chunks_exact(4) {
                let (x, y, z) = (c[0] as u32, c[1] as u32, c[2] as u32);
                if x == 0 || y == 0 || z == 0 {
                    continue;
                }
                if let Some(index) = dims.index(x - 1, y - 1, z - 1) {
                    g.set_blocked(BlockKind::Opacity, index, Dir(c[3] as u8 & 0b1111));
                    written += 1;
                }
            }
        })
        .map_err(|e| eyre!("{e}"))?;
        Ok(written)
    })?;
    Ok(ByondValue::new_num(written as f32))
}

/// The turfs a viewer standing on `center` (a turf) sees within `range`
/// through the opacity layer, as a list of turfs on its z-level (the grid cell
/// index is BYOND's turf reference id, so no coordinates cross back). Empty
/// off the grid.
#[auxmacros::bind("/proc/sight_view")]
fn sight_view(center: ByondValue, range: ByondValue) -> Result<ByondValue> {
    let cell = center.get_ref()?;
    let range = num(&range)?;
    if !(range >= 0.0) {
        bail!("sight_view: bad range {range}");
    }
    let cells = with_world(|w| {
        let grid = w.grid().map_err(|e| eyre!("{e}"))?;
        Ok(view(&grid, BlockKind::Opacity, cell, range as u32))
    })?;
    let items: Vec<ByondValue> = cells
        .into_iter()
        .map(|c| ByondValue::new_ref(ValueType::Turf, c))
        .collect();
    Ok(crate::held::hand_list(&items)?)
}

/// The shape keys of a light on `center` (a turf) of reach `range` with each of the cells in `cells` read as blocking as it says instead of as the opacity layer
/// holds it, one at a time: `cells` is a flat list of `x, y, z, mask` (a door's tile and its other state's `directional_opacity`), nearest door first. `margin` is the
/// glow margin (a number; the key prints it as DM does). A key equal to `skip_key` (the light's own shape) or already returned is left out; the first `limit` are returned, as a list of
/// strings, each exactly what `client_glow_shape_key()` builds in DM (`vg_core::propagate::view::shape_key`). The layer is not written.
#[auxmacros::bind("/proc/sight_twin_keys")]
fn sight_twin_keys(
    center: ByondValue,
    range: ByondValue,
    margin: ByondValue,
    cells: ByondValue,
    skip_key: ByondValue,
    limit: ByondValue,
) -> Result<ByondValue> {
    let cell = center.get_ref()?;
    let range = num(&range)?;
    if !(range >= 0.0) {
        bail!("sight_twin_keys: bad range {range}");
    }
    let margin = num(&margin)?;
    // DM prints a whole number without a decimal point, as the key's text does.
    let margin = if margin.fract() == 0.0 {
        format!("{}", margin as i64)
    } else {
        format!("{margin}")
    };
    let skip = skip_key.get_string()?;
    let limit = num(&limit)? as usize;
    let values: Vec<f32> = cells.held_list()?.iter().map(num).collect::<Result<_>>()?;
    if values.len() % 4 != 0 {
        bail!(
            "sight_twin_keys: {} values is not a list of x, y, z, mask",
            values.len()
        );
    }
    let keys = with_world(|w| {
        let grid = w.grid().map_err(|e| eyre!("{e}"))?;
        let dims = grid.dims();
        let mut keys: Vec<String> = Vec::new();
        for c in values.chunks_exact(4) {
            if keys.len() >= limit {
                break;
            }
            let (x, y, z) = (c[0] as u32, c[1] as u32, c[2] as u32);
            if x == 0 || y == 0 || z == 0 {
                continue;
            }
            let Some(flipped) = dims.index(x - 1, y - 1, z - 1) else {
                continue;
            };
            let over = Some((flipped, Dir(c[3] as u8 & 0b1111)));
            let Some(key) = shape_key(&grid, BlockKind::Opacity, cell, range as u32, &margin, over)
            else {
                continue;
            };
            if key != skip && !keys.contains(&key) {
                keys.push(key);
            }
        }
        Ok(keys)
    })?;
    let owned = keys
        .into_iter()
        .map(|k| crate::held::Held::new_str(k))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(crate::held::hand_owned_list(owned)?)
}
