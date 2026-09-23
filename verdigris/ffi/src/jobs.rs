//! The DLL's job registry (`rust_core.md` §10) and the generic job binds.
//! Domain binds submit work (see `layout.rs`); DM polls, cancels and
//! finishes by id through the binds here.
use std::sync::{Arc, OnceLock};

use byondapi::prelude::*;
use eyre::Result;
use vg_core::jobs::{JobId, JobRegistry, JobStatus};

static JOBS: OnceLock<JobRegistry> = OnceLock::new();

/// Job threads. Two: long jobs must never crowd out frame tasks or BYOND.
const JOB_THREADS: usize = 2;

pub fn registry() -> &'static JobRegistry {
    JOBS.get_or_init(|| {
        JobRegistry::new(JOB_THREADS)
            .expect("could not start the verdigris job pool")
            .with_metrics(Arc::clone(crate::metrics::registry()))
    })
}

/// Job ids cross to DM as decimal strings (a float would lose bits).
pub fn parse_id(value: &ByondValue) -> Result<JobId> {
    Ok(JobId(value.get_string()?.parse::<u64>()?))
}

pub fn id_value(id: JobId) -> Result<ByondValue> {
    Ok(ByondValue::new_str(id.0.to_string().into_bytes())?)
}

/// A job's status: `PENDING`, `READY`, `CANCELLED` or `ERROR:<reason>`
/// (`ERROR:unknown job` once finished).
#[auxmacros::bind("/proc/verdigris_job_poll")]
fn verdigris_job_poll(job_id: ByondValue) -> Result<ByondValue> {
    let status = match registry().poll(parse_id(&job_id)?) {
        JobStatus::Pending { .. } => "PENDING".to_owned(),
        JobStatus::Ready => "READY".to_owned(),
        JobStatus::Cancelled => "CANCELLED".to_owned(),
        JobStatus::Failed(error) => format!("ERROR:{error}"),
        JobStatus::Unknown => "ERROR:unknown job".to_owned(),
    };
    Ok(ByondValue::new_str(status.into_bytes())?)
}

/// A job's progress in 0..1 (1 once it has finished; 0 if unknown).
#[auxmacros::bind("/proc/verdigris_job_progress")]
fn verdigris_job_progress(job_id: ByondValue) -> Result<ByondValue> {
    let progress = match registry().poll(parse_id(&job_id)?) {
        JobStatus::Pending { progress } => progress,
        JobStatus::Unknown => 0.0,
        _ => 1.0,
    };
    Ok(ByondValue::from(progress))
}

/// Asks a job to stop; its result is dropped. Returns 1 if it was pending.
#[auxmacros::bind("/proc/verdigris_job_cancel")]
fn verdigris_job_cancel(job_id: ByondValue) -> Result<ByondValue> {
    let pending = registry().cancel(parse_id(&job_id)?);
    Ok(ByondValue::from(if pending { 1.0f32 } else { 0.0 }))
}

/// Forgets a job and drops its result (cancelling it if still pending).
/// Returns 1 if the job existed.
#[auxmacros::bind("/proc/verdigris_job_finish")]
fn verdigris_job_finish(job_id: ByondValue) -> Result<ByondValue> {
    let existed = registry().finish(parse_id(&job_id)?);
    Ok(ByondValue::from(if existed { 1.0f32 } else { 0.0 }))
}

/// Ids (decimal strings) of jobs that finished since the last call, for DM
/// code that prefers one completion sweep per tick over polling each job.
#[auxmacros::bind("/proc/verdigris_jobs_completed")]
fn verdigris_jobs_completed() -> Result<ByondValue> {
    let ids = registry()
        .drain_completed()
        .into_iter()
        .map(id_value)
        .collect::<Result<Vec<_>>>()?;
    let list = ByondValue::new_list()?;
    list.write_list(&ids)?;
    Ok(list)
}
