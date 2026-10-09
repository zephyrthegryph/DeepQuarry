//! Request-local disk handles shared by resident-first memo adapters.
#[path = "lazy_disk.rs"]
mod lazy;
pub use lazy::LazyDisk;
