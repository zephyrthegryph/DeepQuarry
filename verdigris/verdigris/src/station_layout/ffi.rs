use super::contract::CatalogMapping;
use super::{LayoutError, LayoutRequest, StationLayout, generate};
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
    for room in &layout.rooms {
        let room_type = request
            .departments
            .iter()
            .find(|department| department.id == room.department_id)
            .and_then(|department| {
                department
                    .room_types
                    .iter()
                    .find(|room_type| room_type.id == room.room_type_id)
            })
            .ok_or_else(|| LayoutError(format!("room {} lost its catalog contract", room.id)))?;
        let tile_count = room.tiles.len();
        let maximum = usize::from(room_type.max_width) * usize::from(room_type.max_height);
        if tile_count > maximum {
            return Err(LayoutError(format!(
                "room {} contains {tile_count} tiles but its authored maximum is {maximum}",
                room.id
            )));
        }
    }
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

fn submit_planning_job(payload: String) -> Result<u64, LayoutError> {
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
                    super::decode_catalog(&payload).map_err(|error| error.to_string())?;
                let layout = generate_catalog_layout(&request, &mapping)
                    .map_err(|error| error.to_string())?;
                let encoded =
                    super::encode_plan(&layout, &mapping).map_err(|error| error.to_string())?;
                serde_json::from_str(&encoded).map_err(|error| error.to_string())
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

#[cfg(target_arch = "x86")]
mod binds {
    use super::super::{decode_catalog, encode_plan};
    use super::generate_catalog_layout;
    use byondapi::prelude::*;
    use eyre::Result;

    #[byondapi::bind("/proc/verdigris_generate_station_layout")]
    #[auxmacros::panic_safe]
    fn verdigris_generate_station_layout(payload: ByondValue) -> Result<ByondValue> {
        let payload = payload.get_string()?;
        let (request, mapping) = decode_catalog(&payload)?;
        let layout = generate_catalog_layout(&request, &mapping)
            .map_err(|error| eyre::eyre!(error.to_string()))?;
        let response = encode_plan(&layout, &mapping)?;
        Ok(ByondValue::new_str(response.into_bytes())?)
    }

    #[byondapi::bind("/proc/verdigris_submit_station_layout")]
    #[auxmacros::panic_safe]
    fn verdigris_submit_station_layout(payload: ByondValue) -> Result<ByondValue> {
        let payload = payload.get_string()?;
        let job_id =
            super::submit_planning_job(payload).map_err(|error| eyre::eyre!(error.to_string()))?;
        Ok(ByondValue::new_str(job_id.to_string().into_bytes())?)
    }

    #[byondapi::bind("/proc/verdigris_poll_station_layout")]
    #[auxmacros::panic_safe]
    fn verdigris_poll_station_layout(job_id: ByondValue) -> Result<ByondValue> {
        let job_id = job_id.get_string()?.parse::<u64>()?;
        let mut jobs = super::planning_jobs()
            .lock()
            .map_err(|_| eyre::eyre!("station planning registry was poisoned"))?;
        let response = match jobs.get(&job_id) {
            Some(super::PlanningJob::Pending) => return Ok(ByondValue::new_str(b"PENDING")?),
            Some(super::PlanningJob::Complete(_)) => "READY".into(),
            Some(super::PlanningJob::Failed(_)) => match jobs.remove(&job_id) {
                Some(super::PlanningJob::Failed(error)) => format!("ERROR:{error}"),
                _ => unreachable!(),
            },
            None => "ERROR:unknown station planning job".into(),
        };
        Ok(ByondValue::new_str(response.into_bytes())?)
    }

    #[byondapi::bind("/proc/verdigris_station_layout_section")]
    #[auxmacros::panic_safe]
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
        let jobs = super::planning_jobs()
            .lock()
            .map_err(|_| eyre::eyre!("station planning registry was poisoned"))?;
        let super::PlanningJob::Complete(root) = jobs
            .get(&job_id)
            .ok_or_else(|| eyre::eyre!("unknown station planning job"))?
        else {
            return Err(eyre::eyre!("station planning job is not ready"));
        };
        let response = if section == "header" {
            let mut header = root
                .as_object()
                .ok_or_else(|| eyre::eyre!("station plan root is not an object"))?
                .clone();
            header.retain(|_, value| !value.is_array());
            serde_json::Value::Object(header)
        } else {
            let rows = root
                .get(&section)
                .and_then(serde_json::Value::as_array)
                .ok_or_else(|| eyre::eyre!("unknown station plan section"))?;
            let end = offset.saturating_add(limit).min(rows.len());
            let slice = if offset < rows.len() {
                rows[offset..end].to_vec()
            } else {
                Vec::new()
            };
            serde_json::Value::Array(slice)
        };
        Ok(ByondValue::new_str(serde_json::to_vec(&response)?)?)
    }

    #[byondapi::bind("/proc/verdigris_finish_station_layout")]
    #[auxmacros::panic_safe]
    fn verdigris_finish_station_layout(job_id: ByondValue) -> Result<ByondValue> {
        let job_id = job_id.get_string()?.parse::<u64>()?;
        let removed = super::planning_jobs()
            .lock()
            .map_err(|_| eyre::eyre!("station planning registry was poisoned"))?
            .remove(&job_id)
            .is_some();
        Ok(ByondValue::new_str(if removed { b"1" } else { b"0" })?)
    }
}
