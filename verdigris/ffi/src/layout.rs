//! Binds for `vg-layout`: cave generation and station-layout planning, which
//! runs on the job registry (`jobs.rs`).
use byondapi::prelude::*;
use eyre::Result;
use vg_core::alloc::AllocTag;
use vg_layout::{random_map, station_layout};

/// Args: (limit_x, limit_y, iterations, initial_wall_cell). Returns a flat
/// row-major DM list of 1/0 (wall/floor) of length limit_x * limit_y.
#[auxmacros::bind("/proc/generate_automata")]
fn generate_automata(
    limit_x: ByondValue,
    limit_y: ByondValue,
    iterations: ByondValue,
    initial_wall_cell: ByondValue,
) -> Result<ByondValue> {
    // get_number() yields f32; widen to f64 so validation/ceiling math has
    // integer headroom.
    let (x, y, iterations, wall) = (
        f64::from(limit_x.get_number()?),
        f64::from(limit_y.get_number()?),
        f64::from(iterations.get_number()?),
        f64::from(initial_wall_cell.get_number()?),
    );
    let map = crate::allocator::tagged(AllocTag::Layout, || {
        random_map::generate_automata(x, y, iterations, wall)
    })?;
    let elems: Vec<ByondValue> = map
        .iter()
        .map(|&b| ByondValue::from(if b { 1.0f32 } else { 0.0f32 }))
        .collect();
    let list = ByondValue::new_list()?;
    list.write_list(&elems)?;
    Ok(list)
}

#[auxmacros::bind("/proc/verdigris_generate_station_layout")]
fn verdigris_generate_station_layout(payload: ByondValue) -> Result<ByondValue> {
    let response = station_layout::generate_catalog_plan(&payload.get_string()?)?;
    Ok(ByondValue::new_str(response.into_bytes())?)
}

/// Starts a station-layout planning job and returns its id. Plans for
/// different sites may run at once, so there is no supersede key. Poll with
/// `vg_verdigris_job_poll`, read with `vg_verdigris_station_layout_section`,
/// release with `vg_verdigris_job_finish`.
#[auxmacros::bind("/proc/verdigris_submit_station_layout")]
fn verdigris_submit_station_layout(payload: ByondValue) -> Result<ByondValue> {
    let payload = payload.get_string()?;
    let id = crate::jobs::registry().submit(station_layout::PLANNING_JOB, None, move |ctx| {
        crate::allocator::tagged(AllocTag::Layout, || {
            station_layout::plan_catalog_job(&payload, ctx)
        })
    });
    crate::jobs::id_value(id)
}

/// One section of a finished plan (JSON): `header`, or rows
/// `[offset, offset + limit)` of an array section.
#[auxmacros::bind("/proc/verdigris_station_layout_section")]
fn verdigris_station_layout_section(
    job_id: ByondValue,
    section: ByondValue,
    offset: ByondValue,
    limit: ByondValue,
) -> Result<ByondValue> {
    let job_id = crate::jobs::parse_id(&job_id)?;
    let section = section.get_string()?;
    let offset = offset.get_string()?.parse::<usize>()?;
    let limit = limit.get_string()?.parse::<usize>()?;
    let response = crate::jobs::registry()
        .with_result(job_id, |root: &serde_json::Value| {
            station_layout::plan_section(root, &section, offset, limit)
        })
        .ok_or_else(|| eyre::eyre!("station planning job is not ready"))??;
    Ok(ByondValue::new_str(serde_json::to_vec(&response)?)?)
}
