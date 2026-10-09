//! Current-user-only local transport; no TCP listener.
#[cfg(windows)]
#[path = "windows_pipe.rs"]
mod platform;
#[cfg(unix)]
#[path = "unix_socket.rs"]
mod platform;
pub(super) use platform::{
    connect, listener, private_bytes, set_timeout, Endpoint, Listener, Stream,
};
