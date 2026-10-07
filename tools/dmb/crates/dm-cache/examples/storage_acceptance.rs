//! Six actual writer processes while the parent repeatedly reads and compacts.
//! Run against a fresh scratch directory; this never invokes a compiler/runtime.
use dm_cache::{Cache, CacheError, Limits, Record, RecordKey};
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    process::{Child, Command},
    sync::Arc,
    time::{Duration, Instant, SystemTime},
};
fn record(content: u128) -> Record {
    Record {
        key: RecordKey {
            stage: 99,
            version: 1,
            content,
        },
        symbols: Vec::new(),
        payload: Arc::from(format!("payload:{content}").as_bytes()),
    }
}
fn validate(key: RecordKey, payload: &[u8], symbols: &[(u64, &[u8])]) -> Result<(), String> {
    if key.stage != 99
        || key.version != 1
        || !symbols.is_empty()
        || payload != format!("payload:{}", key.content).as_bytes()
    {
        return Err("storage acceptance payload differs".into());
    }
    Ok(())
}
fn worker(root: &Path, id: u128) -> Result<(), Box<dyn std::error::Error>> {
    let cache = Cache::open(root, Limits::default())?;
    fs::write(root.join(format!("ready-{id}")), b"ready")?;
    let start = Instant::now();
    while !root.join("start").exists() {
        if start.elapsed() > Duration::from_secs(30) {
            return Err("start barrier timed out".into());
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    let mut sink = cache.publish_sink(400);
    let mut own = BTreeSet::new();
    for index in 0..8 {
        let input = record(id * 100 + index);
        own.insert(input.key);
        sink.push(input)?;
        sink.flush()?;
        cache.record_lease(id, SystemTime::now(), &own)?;
        std::thread::sleep(Duration::from_millis(3));
    }
    sink.finish()?;
    Ok(())
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if args.first().is_some_and(|arg| arg == "--worker") {
        return worker(
            Path::new(args.get(1).ok_or("worker root missing")?),
            args.get(2).ok_or("worker id missing")?.parse()?,
        );
    }
    let root = PathBuf::from(
        args.first()
            .ok_or("usage: storage_acceptance FRESH_SCRATCH_DIRECTORY")?,
    );
    fs::create_dir(&root)?;
    let cache = Cache::open(&root, Limits::default())?;
    let exe = std::env::current_exe()?;
    let mut children: Vec<Child> = Vec::new();
    for id in 1..=6 {
        children.push(
            Command::new(&exe)
                .arg("--worker")
                .arg(&root)
                .arg(id.to_string())
                .spawn()?,
        );
    }
    let result = (|| -> Result<(), Box<dyn std::error::Error>> {
        let start = Instant::now();
        while (1..=6).any(|id| !root.join(format!("ready-{id}")).exists()) {
            if start.elapsed() > Duration::from_secs(30) {
                return Err("worker readiness timed out".into());
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        fs::write(root.join("start"), b"go")?;
        let mut compactions = 0;
        let mut reads = 0;
        loop {
            let reader = cache.snapshot()?;
            for key in reader.record_keys() {
                let view = reader
                    .get(key, |payload, symbols| validate(key, payload, symbols))
                    .ok_or("admitted record disappeared")?;
                validate(key, view.payload, &view.symbols)?;
                reads += 1;
            }
            match cache.compact_leased(SystemTime::now(), Duration::from_secs(14 * 86400), validate)
            {
                Ok(_) => compactions += 1,
                Err(CacheError::Busy) => (),
                Err(error) => return Err(error.into()),
            }
            let mut completed = true;
            for child in &mut children {
                if child.try_wait()?.is_none() {
                    completed = false;
                }
            }
            if completed {
                break;
            }
            if start.elapsed() > Duration::from_secs(60) {
                return Err("six-process storage gate timed out".into());
            }
            std::thread::sleep(Duration::from_millis(2));
        }
        for child in &mut children {
            if !child.wait()?.success() {
                return Err("writer process failed".into());
            }
        }
        let reader = cache.snapshot()?;
        for id in 1..=6 {
            for index in 0..8 {
                let key = record(id * 100 + index).key;
                let view = reader
                    .get(key, |payload, symbols| validate(key, payload, symbols))
                    .ok_or("published record lost after compaction")?;
                validate(key, view.payload, &view.symbols)?;
            }
        }
        println!(
            "six-process storage PASS: 48 records, {compactions} compactions, {reads} mapped reads"
        );
        Ok(())
    })();
    if result.is_err() {
        for child in &mut children {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
    result
}
fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
