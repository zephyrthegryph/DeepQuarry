//! Current-user-only local transport; no TCP listener.
#[path = "endpoint_namespace.rs"]
mod namespace;
#[cfg(windows)]
#[path = "windows_pipe.rs"]
mod platform;
#[cfg(unix)]
#[path = "unix_socket.rs"]
mod platform;
pub(super) use platform::{
    available_physical_bytes, connect, endpoint_addresses, listener, private_bytes, set_timeout, Endpoint, Listener, Stream,
};
/// How long one build request may hold its connection, client and daemon alike. It is a fixed deadline from the request, not an
/// idle timeout, so it must cover a cold compile on a loaded machine: 600 s failed real compiles that were still running (cold
/// production compiles took 320 s with five lanes compiling, and one took 623 s and was thrown away).
pub(super) const BUILD_DEADLINE: std::time::Duration = std::time::Duration::from_secs(1800);
