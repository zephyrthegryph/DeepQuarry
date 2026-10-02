//! Short shared connection leases amortize redb recovery/allocator publication.
//! The database is always dropped before its advisory lock is released.
use super::*;
use std::sync::{Arc, Mutex, OnceLock, Weak, atomic::AtomicUsize};
const IDLE: Duration = Duration::from_millis(25);
const OWNERSHIP: Duration = Duration::from_millis(250);
const CACHE_LIMIT: usize = 64 * 1024 * 1024;
static CACHE_BYTES: AtomicUsize = AtomicUsize::new(0);
static SESSIONS: OnceLock<Mutex<BTreeMap<PathBuf,Weak<Session>>>> = OnceLock::new();
#[derive(Debug,Default)]
pub(super) struct Session { state:Mutex<Option<Lease>>, open_failure:Mutex<Option<(Instant,String)>> }
struct Lease {
    db:Option<Database>, lock:Option<Lock>, permit:CachePermit,
    opened:Instant, touched:Instant, path:PathBuf,
}
impl std::fmt::Debug for Lease {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {f.debug_struct("Lease").field("path",&self.path).finish()}
}
struct CachePermit(usize);
impl Drop for CachePermit {fn drop(&mut self){CACHE_BYTES.fetch_sub(self.0,Ordering::AcqRel);}}
impl Drop for Lease {
    fn drop(&mut self) {
        let started=Instant::now();
        drop(self.db.take());
        drop(self.lock.take());
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE store connection close: {} {:.3}s cache_bytes={}",self.path.display(),started.elapsed().as_secs_f64(),self.permit.0);
        }
    }
}
pub(super) fn canonical_path(path:&Path)->io::Result<PathBuf> {
    let absolute=if path.is_absolute(){path.to_owned()}else{std::env::current_dir()?.join(path)};
    let parent=absolute.parent().ok_or_else(||invalid_data("store path lacks parent"))?;
    fs::create_dir_all(parent)?;
    Ok(fs::canonicalize(parent)?.join(absolute.file_name().ok_or_else(||invalid_data("store path lacks filename"))?))
}
pub(super) fn session(path:&Path)->Arc<Session> {
    let registry=SESSIONS.get_or_init(|| {
        std::thread::Builder::new().name("dm-store-lease-reaper".into()).spawn(||loop {
            std::thread::sleep(Duration::from_millis(10));
            let Some(registry)=SESSIONS.get() else {continue;};
            let sessions={
                let mut rows=registry.lock().unwrap_or_else(|error|error.into_inner());
                rows.retain(|_,weak|weak.strong_count()!=0);
                rows.values().filter_map(Weak::upgrade).collect::<Vec<_>>()
            };
            for session in sessions {
                if let Ok(mut state)=session.state.try_lock() {
                    if state.as_ref().is_some_and(|lease|lease.touched.elapsed()>=IDLE || lease.opened.elapsed()>=OWNERSHIP) {
                        // Drop outside the registry lock: redb close can publish
                        // allocator state, but cannot block unrelated DB owners.
                        drop(state.take());
                    }
                }
            }
        }).expect("store lease reaper thread");
        Mutex::new(BTreeMap::new())
    });
    let mut rows=registry.lock().unwrap_or_else(|error|error.into_inner());
    if let Some(session)=rows.get(path).and_then(Weak::upgrade){return session;}
    let session=Arc::new(Session::default());rows.insert(path.to_owned(),Arc::downgrade(&session));session
}
impl Session {
    pub(super) fn access<T>(&self,store:&Store,cancel:Option<&AtomicBool>,f:impl FnOnce(&Database)->io::Result<T>)->io::Result<T> {
        let started=Instant::now();
        let mut state=loop {
            if cancel.is_some_and(|flag|flag.load(Ordering::Relaxed)) {return Err(io::Error::new(io::ErrorKind::Interrupted,"store acquisition cancelled"));}
            match self.state.try_lock() {
                Ok(state)=>break state,
                Err(std::sync::TryLockError::Poisoned(error))=>break error.into_inner(),
                Err(std::sync::TryLockError::WouldBlock)=>{},
            }
            if started.elapsed()>=store.timeout {return Err(io::Error::new(io::ErrorKind::TimedOut,"store local acquisition timed out"));}
            std::thread::sleep(Duration::from_millis(2));
        };
        {
            let mut failure=self.open_failure.lock().unwrap_or_else(|error|error.into_inner());
            if let Some((at,message))=failure.as_ref() {
                if at.elapsed()<store.timeout {
                    return Err(io::Error::other(format!("store open temporarily unavailable after prior failure: {message}")));
                }
                *failure=None;
            }
        }
        if state.as_ref().is_some_and(|lease|lease.opened.elapsed()>=OWNERSHIP || lease.permit.0!=store.cache_bytes) {
            drop(state.take());
            // Give an already waiting independent process a lock handoff point.
            std::thread::sleep(Duration::from_millis(5));
        }
        if state.is_none() {
            let permit=loop {
                let held=CACHE_BYTES.load(Ordering::Acquire);
                if held<=CACHE_LIMIT.saturating_sub(store.cache_bytes)
                    && CACHE_BYTES.compare_exchange_weak(held,held+store.cache_bytes,Ordering::AcqRel,Ordering::Acquire).is_ok() {break CachePermit(store.cache_bytes);}
                if cancel.is_some_and(|flag|flag.load(Ordering::Relaxed)) {return Err(io::Error::new(io::ErrorKind::Interrupted,"store cache admission cancelled"));}
                if started.elapsed()>=store.timeout {return Err(io::Error::new(io::ErrorKind::TimedOut,"store cache admission timed out"));}
                std::thread::sleep(Duration::from_millis(5));
            };
            let lock=store.lock(cancel)?;
            let db=match store.open_database() {
                Ok(db)=>db,
                Err(error)=>{
                    *self.open_failure.lock().unwrap_or_else(|error|error.into_inner())=Some((Instant::now(),error.to_string()));
                    return Err(error);
                }
            };
            let now=Instant::now();
            *state=Some(Lease {db:Some(db),lock:Some(lock),permit,opened:now,touched:now,path:store.path.clone()});
        }
        let lease=state.as_mut().unwrap();
        let result=f(lease.db.as_ref().unwrap());
        lease.touched=Instant::now();
        // Failed transactions must not keep a poisoned connection across calls.
        if result.as_ref().is_err_and(|error| !matches!(error.kind(),io::ErrorKind::InvalidInput|io::ErrorKind::InvalidData|io::ErrorKind::NotFound)) {
            drop(state.take());
        }
        result
    }
}
