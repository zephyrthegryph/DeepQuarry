//! Client lighting's glow masks, baked off the game thread: DM hands over a shape key and the glow sprite's file and polls for the PNGs
//! (`code/content/lighting/client_shadow.dm`); the pixels are `vg_core::propagate::mask`'s. One worker thread takes the keys in order (a mask is
//! a fraction of a millisecond, so one is plenty and needs no pool), bakes each into the mask directory once (a key baked already is a cache
//! hit) and files the answer for the next `glow_mask_poll`. The worker is a thread of its own, like the log writer's: `world::shutdown` joins it
//! before BYOND unloads the DLL (`stop`), and the next bake starts a new one.
use std::path::Path;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::Mutex;

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_core::propagate::mask::MaskStore;

use crate::held::Held;

/// Masks kept on disk, and their bytes (a mask is a few KB). DM keeps at most 8192 icons of its own, so a mask it asks for again is nearly always
/// still here.
const MAX_FILES: usize = 16_384;
const MAX_BYTES: u64 = 256 * 1024 * 1024;

struct Job {
    key: String,
    dir: String,
    icon: String,
}

/// One answered bake, as `glow_mask_poll` hands it to DM.
struct Done {
    key: String,
    path: String,
    error: String,
    ms: f64,
    hit: bool,
}

struct Worker {
    tx: Option<Sender<Job>>,
    handle: Option<std::thread::JoinHandle<()>>,
}

static WORKER: Mutex<Worker> = Mutex::new(Worker {
    tx: None,
    handle: None,
});
static DONE: Mutex<Vec<Done>> = Mutex::new(Vec::new());
static STORE: Mutex<Option<MaskStore>> = Mutex::new(None);

/// Bakes one mask through the DLL's store (made on first use, or again when the directory changes).
fn bake_one(key: &str, dir: &str, icon: &str) -> Result<(String, f64, bool), String> {
    let mut guard = STORE.lock().map_err(|_| "the mask store is poisoned".to_owned())?;
    if guard.as_ref().is_none_or(|s| s.dir() != Path::new(dir)) {
        *guard = Some(MaskStore::new(Path::new(dir), MAX_FILES, MAX_BYTES)?);
    }
    let store = guard.as_mut().ok_or("no mask store")?;
    let baked = store.bake(key, icon)?;
    Ok((baked.path.to_string_lossy().into_owned(), baked.ms, baked.hit))
}

fn run(rx: &Receiver<Job>) {
    while let Ok(job) = rx.recv() {
        let result = std::panic::catch_unwind(|| bake_one(&job.key, &job.dir, &job.icon))
            .unwrap_or_else(|_| Err("the mask bake panicked".to_owned()));
        let done = match result {
            Ok((path, ms, hit)) => Done {
                key: job.key,
                path,
                error: String::new(),
                ms,
                hit,
            },
            Err(error) => Done {
                key: job.key,
                path: String::new(),
                error,
                ms: 0.0,
                hit: false,
            },
        };
        if let Ok(mut d) = DONE.lock() {
            d.push(done);
        }
    }
}

fn sender() -> Option<Sender<Job>> {
    let mut w = WORKER.lock().ok()?;
    if w.tx.is_none() {
        let (tx, rx) = channel();
        match std::thread::Builder::new()
            .name("vg-glow-mask".into())
            .spawn(move || run(&rx))
        {
            Ok(h) => {
                w.tx = Some(tx);
                w.handle = Some(h);
            }
            Err(e) => eprintln!("vg-glow-mask: could not start the worker thread: {e}"),
        }
    }
    w.tx.clone()
}

/// Ends and joins the worker (world shutdown); results not yet polled are dropped with the DLL.
pub fn stop() {
    let handle = WORKER.lock().ok().and_then(|mut w| {
        w.tx = None;
        w.handle.take()
    });
    if let Some(h) = handle {
        let _ = h.join();
    }
}

/// Queues a mask bake and returns at once: `key` is the shape key, `dir` the directory the PNG goes in, `icon` the glow sprite's file (the DMI,
/// whose image is the sprite). The answer comes from `glow_mask_poll`. With no worker thread to be had, the bake is run here.
#[auxmacros::bind("/proc/glow_mask_bake")]
fn glow_mask_bake(key: ByondValue, dir: ByondValue, icon: ByondValue) -> Result<ByondValue> {
    let job = Job {
        key: key.get_string()?,
        dir: dir.get_string()?,
        icon: icon.get_string()?,
    };
    match sender() {
        Some(tx) => {
            if let Err(e) = tx.send(job) {
                let job = e.0;
                push_inline(&job);
            }
        }
        None => push_inline(&job),
    }
    Ok(ByondValue::null())
}

fn push_inline(job: &Job) {
    let done = match bake_one(&job.key, &job.dir, &job.icon) {
        Ok((path, ms, hit)) => Done {
            key: job.key.clone(),
            path,
            error: String::new(),
            ms,
            hit,
        },
        Err(error) => Done {
            key: job.key.clone(),
            path: String::new(),
            error,
            ms: 0.0,
            hit: false,
        },
    };
    if let Ok(mut d) = DONE.lock() {
        d.push(done);
    }
}

/// Bakes a mask on the calling thread and returns its path (tests, where DM waits for it); an error is a runtime.
#[auxmacros::bind("/proc/glow_mask_bake_now")]
fn glow_mask_bake_now(key: ByondValue, dir: ByondValue, icon: ByondValue) -> Result<ByondValue> {
    match bake_one(&key.get_string()?, &dir.get_string()?, &icon.get_string()?) {
        Ok((path, _, _)) => Ok(Held::new_str(path)?.leak()),
        Err(e) => bail!("glow_mask_bake_now: {e}"),
    }
}

/// The bakes that finished since the last call, as a flat list of five strings each: the key, the PNG's path (empty on an error), the error (empty
/// on success), the milliseconds the worker spent, and `1` when the mask was already baked.
#[auxmacros::bind("/proc/glow_mask_poll")]
fn glow_mask_poll() -> Result<ByondValue> {
    let done = DONE
        .lock()
        .map(|mut d| std::mem::take(&mut *d))
        .unwrap_or_default();
    let mut out = Vec::with_capacity(done.len() * 5);
    for d in done {
        out.push(Held::new_str(d.key)?);
        out.push(Held::new_str(d.path)?);
        out.push(Held::new_str(d.error)?);
        out.push(Held::new_str(format!("{:.3}", d.ms))?);
        out.push(Held::new_str(if d.hit { "1" } else { "0" })?);
    }
    Ok(crate::held::hand_owned_list(out)?)
}

/// `"baked,hits,failed,evicted,bake_ms_total,bake_ms_max,files,bytes"` of the mask store since the DLL loaded (zeros before the first bake).
#[auxmacros::bind("/proc/glow_mask_stats")]
fn glow_mask_stats() -> Result<ByondValue> {
    let s = STORE
        .lock()
        .ok()
        .and_then(|g| g.as_ref().map(MaskStore::stats))
        .unwrap_or_default();
    Ok(Held::new_str(format!(
        "{},{},{},{},{:.3},{:.3},{},{}",
        s.baked, s.hits, s.failed, s.evicted, s.bake_ms_total, s.bake_ms_max, s.files, s.bytes
    ))?
    .leak())
}
