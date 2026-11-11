//! Binds for the world opacity layer (the grid's [`BlockKind::Opacity`]
//! faces): DM writes each turf's `directional_opacity` here, and sight users
//! (lighting, line of sight) read [`view`] over it. Coordinates are DM's
//! one-based turf coordinates.
use crate::held::HeldRead;
use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::grid::{BlockKind, Dir};
use vg_core::propagate::view::view;

use crate::world::{num, with_world};

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
