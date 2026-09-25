//! Station-layout planning as a `vg-core` job (`rust_core.md` §10): the pure
//! side of the `verdigris_*_station_layout` binds. vg-ffi submits
//! [`plan_catalog_job`] to the DLL's job registry; DM polls it through the
//! generic job binds and reads the result in sections with [`plan_section`].

use super::contract::CatalogMapping;
use super::{
    LayoutError, LayoutRequest, StationLayout, decode_catalog, encode_plan, generate,
    generate_station_blueprint,
};
use vg_core::jobs::JobCtx;

/// The job name station planning runs under (and its metrics prefix).
pub const PLANNING_JOB: &str = "station_layout";

fn generate_catalog_layout(
    request: &LayoutRequest,
    mapping: &CatalogMapping,
) -> Result<StationLayout, LayoutError> {
    let layout = generate(request)?;
    if !mapping.architecture_choices.contains(&layout.archetype) {
        return Err(LayoutError(
            "generated architecture is excluded by the request".into(),
        ));
    }
    // The structural planner may deliberately give an authored room additional
    // breathing room after all required programs fit. `max_width/max_height`
    // describe the preferred content envelope, not a hard polygon-area limit;
    // the content blueprint owns density and circulation validation for the
    // resulting footprint.
    Ok(layout)
}

/// Plans a station from a catalog request: structure, content blueprint and
/// the encoded plan, merged into one JSON object. Checkpoints between
/// phases so frames keep priority and a cancel stops early.
///
/// # Errors
/// If the request is invalid, planning fails, or the job was cancelled.
pub fn plan_catalog_job(payload: &str, ctx: &JobCtx) -> Result<serde_json::Value, String> {
    let step = |p: f32| {
        ctx.set_progress(p);
        ctx.checkpoint().map_err(|e| e.to_string())
    };
    let (request, mapping) = decode_catalog(payload).map_err(|error| error.to_string())?;
    step(0.05)?;
    let layout = generate_catalog_layout(&request, &mapping).map_err(|error| error.to_string())?;
    step(0.5)?;
    let blueprint =
        generate_station_blueprint(layout.clone(), &mapping).map_err(|error| error.to_string())?;
    step(0.85)?;
    let encoded = encode_plan(&layout, &mapping).map_err(|error| error.to_string())?;
    let mut root: serde_json::Value =
        serde_json::from_str(&encoded).map_err(|error| error.to_string())?;
    let object = root
        .as_object_mut()
        .ok_or_else(|| "encoded station plan is not an object".to_string())?;
    let mut put = |name: &str, value: Result<serde_json::Value, serde_json::Error>| {
        value
            .map(|v| {
                object.insert(name.into(), v);
            })
            .map_err(|error| error.to_string())
    };
    put("content_rooms", serde_json::to_value(&blueprint.rooms))?;
    put("fixtures", serde_json::to_value(&blueprint.fixtures))?;
    put("networks", serde_json::to_value(&blueprint.networks))?;
    put("content_quality", serde_json::to_value(&blueprint.quality))?;
    Ok(root)
}

/// Plan synchronously and return the encoded plan (`verdigris_generate_station_layout`).
pub fn generate_catalog_plan(payload: &str) -> eyre::Result<String> {
    let (request, mapping) = decode_catalog(payload)?;
    let layout = generate_catalog_layout(&request, &mapping)
        .map_err(|error| eyre::eyre!(error.to_string()))?;
    encode_plan(&layout, &mapping)
}

/// One section of a finished plan: `header` (every non-array field) or a slice
/// `[offset, offset + limit)` of an array section.
pub fn plan_section(
    root: &serde_json::Value,
    section: &str,
    offset: usize,
    limit: usize,
) -> eyre::Result<serde_json::Value> {
    Ok(if section == "header" {
        let mut header = root
            .as_object()
            .ok_or_else(|| eyre::eyre!("station plan root is not an object"))?
            .clone();
        header.retain(|_, value| !value.is_array());
        serde_json::Value::Object(header)
    } else {
        let rows = root
            .get(section)
            .and_then(serde_json::Value::as_array)
            .ok_or_else(|| eyre::eyre!("unknown station plan section"))?;
        let end = offset.saturating_add(limit).min(rows.len());
        let slice = if offset < rows.len() {
            rows[offset..end].to_vec()
        } else {
            Vec::new()
        };
        serde_json::Value::Array(slice)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use vg_core::jobs::{JobRegistry, JobStatus};

    #[test]
    fn planning_runs_on_the_job_registry() {
        let jobs = JobRegistry::new(1).unwrap();
        let id = jobs.submit(PLANNING_JOB, None, |ctx| plan_catalog_job("not json", ctx));
        let start = std::time::Instant::now();
        let status = loop {
            match jobs.poll(id) {
                JobStatus::Pending { .. } if start.elapsed().as_secs() < 30 => {
                    std::thread::yield_now();
                }
                other => break other,
            }
        };
        assert!(matches!(status, JobStatus::Failed(_)), "{status:?}");
    }

    #[test]
    fn sections_slice_arrays_and_strip_the_header() {
        let root = serde_json::json!({"seed": 4, "rooms": [1, 2, 3]});
        assert_eq!(
            plan_section(&root, "header", 0, 0).unwrap(),
            serde_json::json!({"seed": 4})
        );
        assert_eq!(
            plan_section(&root, "rooms", 1, 5).unwrap(),
            serde_json::json!([2, 3])
        );
        assert!(plan_section(&root, "nope", 0, 1).is_err());
    }
}
