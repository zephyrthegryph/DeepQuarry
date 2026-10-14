//! Long-lived request threads. A thread that exits abandons its allocator heap,
//! stranding the retained owners it allocated in pages no later request reuses;
//! persistent threads keep those heaps owned and reusable. Threads are spawned
//! on demand (at most one per concurrent connection) and never exit.
use std::{
    io,
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc, Arc, Mutex, OnceLock,
    },
};

type Job = Box<dyn FnOnce() + Send + 'static>;
struct Pool {
    sender: mpsc::Sender<Job>,
    receiver: Arc<Mutex<mpsc::Receiver<Job>>>,
    idle: Arc<AtomicUsize>,
}

pub(super) fn run(job: impl FnOnce() + Send + 'static) -> io::Result<()> {
    static POOL: OnceLock<Pool> = OnceLock::new();
    let pool = POOL.get_or_init(|| {
        let (sender, receiver) = mpsc::channel();
        Pool {
            sender,
            receiver: Arc::new(Mutex::new(receiver)),
            idle: Arc::new(AtomicUsize::new(0)),
        }
    });
    // Reserve an idle thread if one exists; otherwise add a thread.
    let reserved = pool
        .idle
        .fetch_update(Ordering::AcqRel, Ordering::Acquire, |idle| idle.checked_sub(1))
        .is_ok();
    pool.sender
        .send(Box::new(job))
        .map_err(|_| io::Error::other("request thread pool closed"))?;
    if !reserved {
        let receiver = Arc::clone(&pool.receiver);
        let idle = Arc::clone(&pool.idle);
        std::thread::Builder::new()
            .name("dmbd-request".into())
            .stack_size(dm_exec::COMPILER_STACK_BYTES)
            .spawn(move || loop {
                let next = receiver.lock().unwrap_or_else(|e| e.into_inner()).recv();
                match next {
                    Ok(job) => {
                        // A panicking request must not kill the long-lived thread.
                        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(job));
                        idle.fetch_add(1, Ordering::AcqRel);
                    }
                    Err(_) => return,
                }
            })?;
    }
    Ok(())
}
