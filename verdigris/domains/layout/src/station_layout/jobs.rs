//! Station-layout planning jobs: the pure side of the `verdigris_*_station_layout`
//! binds in `vg-ffi`. Planning runs on its own thread; DM submits, polls, reads
//! the result in sections and finishes the job.

use super::contract::CatalogMapping;
use super::{
    LayoutError, LayoutRequest, StationLayout, decode_catalog, encode_plan, generate,
    generate_station_blueprint,
};
use std::collections::HashMap;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

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

enum PlanningJob {
    Pending,
    Complete(serde_json::Value),
    Failed(String),
}

static NEXT_JOB_ID: AtomicU64 = AtomicU64::new(1);
static PLANNING_JOBS: OnceLock<Mutex<HashMap<u64, PlanningJob>>> = OnceLock::new();

fn planning_jobs() -> &'static Mutex<HashMap<u64, PlanningJob>> {
    PLANNING_JOBS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn submit_planning_job(payload: String) -> Result<u64, LayoutError> {
    let job_id = NEXT_JOB_ID.fetch_add(1, Ordering::Relaxed);
    planning_jobs()
        .lock()
        .map_err(|_| LayoutError("station planning registry was poisoned".into()))?
        .insert(job_id, PlanningJob::Pending);
    std::thread::Builder::new()
        .name(format!("station-layout-{job_id}"))
        .spawn(move || {
            let outcome = catch_unwind(AssertUnwindSafe(|| {
                let (request, mapping) =
                    decode_catalog(&payload).map_err(|error| error.to_string())?;
                let layout = generate_catalog_layout(&request, &mapping)
                    .map_err(|error| error.to_string())?;
                let blueprint = generate_station_blueprint(layout.clone(), &mapping)
                    .map_err(|error| error.to_string())?;
                let encoded = encode_plan(&layout, &mapping).map_err(|error| error.to_string())?;
                let mut root: serde_json::Value =
                    serde_json::from_str(&encoded).map_err(|error| error.to_string())?;
                let object = root
                    .as_object_mut()
                    .ok_or_else(|| "encoded station plan is not an object".to_string())?;
                object.insert(
                    "content_rooms".into(),
                    serde_json::to_value(&blueprint.rooms).map_err(|error| error.to_string())?,
                );
                object.insert(
                    "fixtures".into(),
                    serde_json::to_value(&blueprint.fixtures).map_err(|error| error.to_string())?,
                );
                object.insert(
                    "networks".into(),
                    serde_json::to_value(&blueprint.networks).map_err(|error| error.to_string())?,
                );
                object.insert(
                    "content_quality".into(),
                    serde_json::to_value(&blueprint.quality).map_err(|error| error.to_string())?,
                );
                Ok(root)
            }));
            let state = match outcome {
                Ok(Ok(response)) => PlanningJob::Complete(response),
                Ok(Err(error)) => PlanningJob::Failed(error),
                Err(_) => PlanningJob::Failed("station planning worker panicked".into()),
            };
            if let Ok(mut jobs) = planning_jobs().lock() {
                jobs.insert(job_id, state);
            }
        })
        .map_err(|error| {
            LayoutError(format!("could not start station planning worker: {error}"))
        })?;
    Ok(job_id)
}

/// Plan synchronously and return the encoded plan (`verdigris_generate_station_layout`).
pub fn generate_catalog_plan(payload: &str) -> eyre::Result<String> {
    let (request, mapping) = decode_catalog(payload)?;
    let layout = generate_catalog_layout(&request, &mapping)
        .map_err(|error| eyre::eyre!(error.to_string()))?;
    Ok(encode_plan(&layout, &mapping)?)
}

/// `PENDING`, `READY`, or `ERROR:<reason>`. A failed job is removed when its
/// error is reported.
pub fn poll_planning_job(job_id: u64) -> eyre::Result<String> {
    let mut jobs = planning_jobs()
        .lock()
        .map_err(|_| eyre::eyre!("station planning registry was poisoned"))?;
    Ok(match jobs.get(&job_id) {
        Some(PlanningJob::Pending) => "PENDING".into(),
        Some(PlanningJob::Complete(_)) => "READY".into(),
        Some(PlanningJob::Failed(_)) => match jobs.remove(&job_id) {
            Some(PlanningJob::Failed(error)) => format!("ERROR:{error}"),
            _ => unreachable!(),
        },
        None => "ERROR:unknown station planning job".into(),
    })
}

/// One section of a finished plan: `header` (every non-array field) or a slice
/// `[offset, offset + limit)` of an array section.
pub fn planning_job_section(
    job_id: u64,
    section: &str,
    offset: usize,
    limit: usize,
) -> eyre::Result<serde_json::Value> {
    let jobs = planning_jobs()
        .lock()
        .map_err(|_| eyre::eyre!("station planning registry was poisoned"))?;
    let PlanningJob::Complete(root) = jobs
        .get(&job_id)
        .ok_or_else(|| eyre::eyre!("unknown station planning job"))?
    else {
        return Err(eyre::eyre!("station planning job is not ready"));
    };
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

/// Drop a job's result. Returns whether the job existed.
pub fn finish_planning_job(job_id: u64) -> eyre::Result<bool> {
    Ok(planning_jobs()
        .lock()
        .map_err(|_| eyre::eyre!("station planning registry was poisoned"))?
        .remove(&job_id)
        .is_some())
}
