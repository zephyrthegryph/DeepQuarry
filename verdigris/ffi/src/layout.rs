//! Binds for `vg-layout`: cave generation and station-layout planning jobs.
use byondapi::prelude::*;
use eyre::Result;
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
    let map = random_map::generate_automata(
        f64::from(limit_x.get_number()?),
        f64::from(limit_y.get_number()?),
        f64::from(iterations.get_number()?),
        f64::from(initial_wall_cell.get_number()?),
    )?;
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

#[auxmacros::bind("/proc/verdigris_submit_station_layout")]
fn verdigris_submit_station_layout(payload: ByondValue) -> Result<ByondValue> {
    let job_id = station_layout::submit_planning_job(payload.get_string()?)
        .map_err(|error| eyre::eyre!(error.to_string()))?;
    Ok(ByondValue::new_str(job_id.to_string().into_bytes())?)
}

#[auxmacros::bind("/proc/verdigris_poll_station_layout")]
fn verdigris_poll_station_layout(job_id: ByondValue) -> Result<ByondValue> {
    let job_id = job_id.get_string()?.parse::<u64>()?;
    let response = station_layout::poll_planning_job(job_id)?;
    Ok(ByondValue::new_str(response.into_bytes())?)
}

#[auxmacros::bind("/proc/verdigris_station_layout_section")]
fn verdigris_station_layout_section(
    job_id: ByondValue,
    section: ByondValue,
    offset: ByondValue,
    limit: ByondValue,
) -> Result<ByondValue> {
    let job_id = job_id.get_string()?.parse::<u64>()?;
    let section = section.get_string()?;
    let offset = offset.get_string()?.parse::<usize>()?;
    let limit = limit.get_string()?.parse::<usize>()?;
    let response = station_layout::planning_job_section(job_id, &section, offset, limit)?;
    Ok(ByondValue::new_str(serde_json::to_vec(&response)?)?)
}

#[auxmacros::bind("/proc/verdigris_finish_station_layout")]
fn verdigris_finish_station_layout(job_id: ByondValue) -> Result<ByondValue> {
    let job_id = job_id.get_string()?.parse::<u64>()?;
    let removed = station_layout::finish_planning_job(job_id)?;
    Ok(ByondValue::new_str(if removed { b"1" } else { b"0" })?)
}
