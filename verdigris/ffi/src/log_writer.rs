//! The game's asynchronous log writer: DM hands a line to a channel and a writer thread appends it to its file, so a
//! stalled disk (a scanner, a full buffer) never stalls the tick. Order is the order of the calls (one thread, one FIFO);
//! `verdigris_log_flush` blocks until everything queued so far is on disk (world reboot and shutdown).
use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Condvar, Mutex};

use byondapi::prelude::*;
use eyre::Result;

struct Line {
    path: String,
    text: String,
}

#[derive(Default)]
struct Progress {
    /// Lines handed to the channel.
    queued: u64,
    /// Lines the writer has put on disk (or dropped after a failed write).
    written: u64,
    /// Lines whose write failed (a counted drop, never a silent one).
    failed: u64,
    /// Files found missing when a batch opened them (deleted while the round ran) and started again with their header.
    recovered: u64,
}

struct Inner {
    tx: Option<Sender<Line>>,
    handle: Option<std::thread::JoinHandle<()>>,
}

struct Writer {
    inner: Mutex<Inner>,
    progress: Mutex<Progress>,
    /// File path -> the header it starts with (`verdigris_log_header`): what the writer puts back first when it finds the file gone.
    headers: Mutex<Option<HashMap<String, String>>>,
    done: Condvar,
}

static WRITER: Writer = Writer {
    inner: Mutex::new(Inner {
        tx: None,
        handle: None,
    }),
    progress: Mutex::new(Progress {
        queued: 0,
        written: 0,
        failed: 0,
        recovered: 0,
    }),
    headers: Mutex::new(None),
    done: Condvar::new(),
};

/// The sender of the running writer thread, starting one when none runs (first use, or after `stop`).
fn sender(inner: &mut Inner) -> Option<Sender<Line>> {
    if inner.tx.is_none() {
        let (tx, rx) = channel();
        match std::thread::Builder::new()
            .name("vg-log-writer".into())
            .spawn(move || run(&WRITER, &rx))
        {
            Ok(h) => {
                inner.tx = Some(tx);
                inner.handle = Some(h);
            }
            Err(e) => eprintln!("vg-log-writer: could not start the writer thread: {e}"),
        }
    }
    inner.tx.clone()
}

/// Opens `path` for appending. A file that is gone but has a registered header starts again with that header and counts as
/// recovered, so a deleted log file is noticed on the writer thread and the game thread never has to look at the disk.
fn open(path: &str, recovered: &mut u64) -> std::io::Result<BufWriter<File>> {
    let p = PathBuf::from(path);
    if let Some(dir) = p.parent() {
        if !dir.as_os_str().is_empty() {
            fs::create_dir_all(dir)?;
        }
    }
    let header = WRITER
        .headers
        .lock()
        .ok()
        .and_then(|h| h.as_ref().and_then(|m| m.get(path).cloned()));
    let gone = header.is_some() && !p.exists();
    let mut f = BufWriter::new(OpenOptions::new().create(true).append(true).open(p)?);
    if gone {
        if let Some(h) = header {
            f.write_all(h.as_bytes())?;
        }
        *recovered += 1;
    }
    Ok(f)
}

/// Writes one line to its file through the open handles of this batch.
fn put(
    files: &mut HashMap<String, BufWriter<File>>,
    line: &Line,
    recovered: &mut u64,
) -> std::io::Result<()> {
    if !files.contains_key(&line.path) {
        files.insert(line.path.clone(), open(&line.path, recovered)?);
    }
    match files.get_mut(&line.path) {
        Some(f) => f.write_all(line.text.as_bytes()),
        None => Ok(()),
    }
}

fn run(w: &Writer, rx: &Receiver<Line>) {
    while let Ok(first) = rx.recv() {
        // One batch: every line already queued, then close the handles so a file deleted or rewritten
        // by DM (a category reset) is never written through a stale handle.
        let mut files: HashMap<String, BufWriter<File>> = HashMap::new();
        let mut done = 0_u64;
        let mut failed = 0_u64;
        let mut recovered = 0_u64;
        let mut next = Some(first);
        while let Some(line) = next {
            if put(&mut files, &line, &mut recovered).is_err() {
                failed += 1;
            }
            done += 1;
            next = rx.try_recv().ok();
        }
        for f in files.values_mut() {
            if f.flush().is_err() {
                failed += 1;
            }
        }
        drop(files);
        if let Ok(mut p) = w.progress.lock() {
            p.written += done;
            p.failed += failed;
            p.recovered += recovered;
        }
        w.done.notify_all();
    }
}

/// Queues `text` (exactly the bytes to append) for `path`. With no writer thread to be had, the line is written here, so it is never lost.
pub fn append(path: &str, text: &str) {
    let w = &WRITER;
    let line = Line {
        path: path.to_owned(),
        text: text.to_owned(),
    };
    let tx = w.inner.lock().ok().and_then(|mut i| sender(&mut i));
    if let Some(tx) = tx {
        if let Ok(mut p) = w.progress.lock() {
            p.queued += 1;
        }
        if tx.send(line).is_ok() {
            return;
        }
        // The writer thread ended between the lookup and the send: count the line done and failed.
        if let Ok(mut p) = w.progress.lock() {
            p.written += 1;
            p.failed += 1;
        }
        return;
    }
    let mut files = HashMap::new();
    let mut recovered = 0_u64;
    let ok = put(&mut files, &line, &mut recovered).is_ok() && files.values_mut().all(|f| f.flush().is_ok());
    if let Ok(mut p) = w.progress.lock() {
        p.queued += 1;
        p.written += 1;
        if !ok {
            p.failed += 1;
        }
    }
}

/// Blocks until every line queued before the call is on disk (at most 5 s without progress).
pub fn flush() {
    let w = &WRITER;
    let Ok(mut p) = w.progress.lock() else { return };
    let target = p.queued;
    while p.written < target {
        match w.done.wait_timeout(p, std::time::Duration::from_secs(5)) {
            Ok((g, t)) => {
                p = g;
                if t.timed_out() && p.written < target {
                    return;
                }
            }
            Err(_) => return,
        }
    }
}

/// Flushes, then ends and joins the writer thread (before BYOND unloads the DLL); the next `append` starts a new one.
pub fn stop() {
    flush();
    let handle = WRITER.inner.lock().ok().and_then(|mut i| {
        i.tx = None;
        i.handle.take()
    });
    if let Some(h) = handle {
        let _ = h.join();
    }
}

/// (queued, written, failed, recovered) counts.
pub fn counts() -> (u64, u64, u64, u64) {
    WRITER
        .progress
        .lock()
        .map(|p| (p.queued, p.written, p.failed, p.recovered))
        .unwrap_or((0, 0, 0, 0))
}

/// Registers the header a file starts with, for the writer to put back if the file is found gone.
pub fn set_header(path: &str, text: &str) {
    if let Ok(mut h) = WRITER.headers.lock() {
        h.get_or_insert_with(HashMap::new)
            .insert(path.to_owned(), text.to_owned());
    }
}

/// Queues `text` for `path` and returns at once.
#[auxmacros::bind("/proc/verdigris_log_append")]
fn verdigris_log_append(path: ByondValue, text: ByondValue) -> Result<ByondValue> {
    append(&path.get_string()?, &text.get_string()?);
    Ok(ByondValue::null())
}

/// Registers `text` as the header `path` starts with; the writer thread writes it first if it finds the file gone.
#[auxmacros::bind("/proc/verdigris_log_header")]
fn verdigris_log_header(path: ByondValue, text: ByondValue) -> Result<ByondValue> {
    set_header(&path.get_string()?, &text.get_string()?);
    Ok(ByondValue::null())
}

/// Blocks until everything queued so far is on disk (world reboot, shutdown, a category file reset, a test's read).
#[auxmacros::bind("/proc/verdigris_log_flush")]
fn verdigris_log_flush() -> Result<ByondValue> {
    flush();
    Ok(ByondValue::null())
}

/// Flushes and joins the writer thread (world shutdown); a later append starts a new one.
#[auxmacros::bind("/proc/verdigris_log_stop")]
fn verdigris_log_stop() -> Result<ByondValue> {
    stop();
    Ok(ByondValue::null())
}

/// `"queued,written,failed,recovered"`: counts since the DLL loaded.
#[auxmacros::bind("/proc/verdigris_log_counts")]
fn verdigris_log_counts() -> Result<ByondValue> {
    let (q, w, f, r) = counts();
    Ok(crate::held::Held::new_str(format!("{q},{w},{f},{r}"))?.leak())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lines_land_in_call_order_across_files() {
        let dir = std::env::temp_dir().join(format!("vg-log-test-{}", std::process::id()));
        let a = dir.join("a.log").to_string_lossy().into_owned();
        let b = dir.join("sub").join("b.log").to_string_lossy().into_owned();
        for i in 0..200 {
            append(&a, &format!("a{i}\n"));
            append(&b, &format!("b{i}\n"));
        }
        flush();
        stop();
        let ra = fs::read_to_string(&a).unwrap();
        let rb = fs::read_to_string(&b).unwrap();
        let ea: String = (0..200).map(|i| format!("a{i}\n")).collect();
        let eb: String = (0..200).map(|i| format!("b{i}\n")).collect();
        assert_eq!(ra, ea);
        assert_eq!(rb, eb);
        let _ = fs::remove_dir_all(dir);
    }
}
