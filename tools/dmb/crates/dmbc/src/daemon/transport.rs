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
    Endpoint, Listener, Stream, connect, listener, private_bytes, set_timeout,
};
