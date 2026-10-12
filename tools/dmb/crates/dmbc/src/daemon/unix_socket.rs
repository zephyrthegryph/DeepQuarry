use std::{
    fs, io,
    os::unix::{
        fs::{DirBuilderExt, FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::PathBuf,
};
pub(in crate::daemon) struct Stream {
    socket: UnixStream,
    deadline: std::time::Instant,
}
impl Stream {
    fn new(socket: UnixStream) -> Self {
        Self {
            socket,
            deadline: std::time::Instant::now() + std::time::Duration::from_secs(20),
        }
    }
    fn remaining(&self) -> io::Result<std::time::Duration> {
        self.deadline
            .checked_duration_since(std::time::Instant::now())
            .filter(|duration| !duration.is_zero())
            .ok_or_else(|| {
                io::Error::new(io::ErrorKind::TimedOut, "daemon transport deadline expired")
            })
    }
}
impl io::Read for Stream {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        self.socket.set_read_timeout(Some(self.remaining()?))?;
        io::Read::read(&mut self.socket, bytes)
    }
}
impl io::Write for Stream {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.socket.set_write_timeout(Some(self.remaining()?))?;
        io::Write::write(&mut self.socket, bytes)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.remaining().map(|_| ())
    }
}
#[derive(Clone)]
pub(in crate::daemon) struct Endpoint(PathBuf);
pub(in crate::daemon) struct Listener {
    socket: UnixListener,
    path: PathBuf,
    identity: (u64, u64),
    // Persistent control files are never removed. The OS releases this lease.
    _lease: fs::File,
}
unsafe extern "C" {
    fn getuid() -> u32;
}
impl Endpoint {
    pub(in crate::daemon) fn current() -> io::Result<Self> {
        let uid = unsafe { getuid() };
        Self::named(super::namespace::current_name(&format!("dmbd-{uid}"))?, uid)
    }
    pub(in crate::daemon) fn generation(compiler: u128) -> io::Result<Self> {
        let uid = unsafe { getuid() };
        Self::named(
            super::namespace::current_generation_name(&format!("dmbd-{uid}"), compiler)?,
            uid,
        )
    }
    pub(in crate::daemon) fn discovery() -> io::Result<Self> {
        let uid = unsafe { getuid() };
        Self::named(
            super::namespace::current_discovery_name(&format!("dmbd-{uid}"))?,
            uid,
        )
    }
    fn named(name: String, uid: u32) -> io::Result<Self> {
        let directory = std::env::temp_dir().join(name);
        match fs::symlink_metadata(&directory) {
            Ok(_) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                // Create with private mode atomically. Concurrent clients may
                // discover this generation at the same time; validate the
                // winning directory rather than failing or relaxing its mode.
                match fs::DirBuilder::new().mode(0o700).create(&directory) {
                    Ok(()) => {}
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
                    Err(error) => return Err(error),
                }
            }
            Err(e) => return Err(e),
        }
        let metadata = fs::symlink_metadata(&directory)?;
        if !metadata.is_dir() || metadata.uid() != uid || metadata.permissions().mode() & 0o077 != 0
        {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "daemon runtime directory is not private",
            ));
        }
        Ok(Self(directory.join("compiler.sock")))
    }
}
pub(in crate::daemon) fn listener(endpoint: &Endpoint) -> io::Result<Listener> {
    use fs2::FileExt;
    let lease_path = endpoint.0.with_extension("lock");
    if let Ok(metadata) = fs::symlink_metadata(&lease_path) {
        if !metadata.is_file() || metadata.uid() != unsafe { getuid() } {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "daemon endpoint lease is not an owned regular file",
            ));
        }
    }
    let lease = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(lease_path)?;
    lease.try_lock_exclusive().map_err(|error| {
        if error.kind() == io::ErrorKind::WouldBlock {
            io::Error::new(io::ErrorKind::AddrInUse, "daemon endpoint lease is held")
        } else {
            error
        }
    })?;
    if let Ok(metadata) = fs::symlink_metadata(&endpoint.0) {
        if !metadata.file_type().is_socket() || metadata.uid() != unsafe { getuid() } {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "daemon endpoint is not a socket",
            ));
        }
        match UnixStream::connect(&endpoint.0) {
            Ok(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::AddrInUse,
                    "daemon already running",
                ));
            }
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::ConnectionRefused | io::ErrorKind::NotFound
                ) =>
            {
                fs::remove_file(&endpoint.0)?
            }
            Err(error) => return Err(error),
        }
    }
    let socket = UnixListener::bind(&endpoint.0)?;
    fs::set_permissions(&endpoint.0, fs::Permissions::from_mode(0o600))?;
    socket.set_nonblocking(true)?;
    let metadata = fs::symlink_metadata(&endpoint.0)?;
    Ok(Listener {
        socket,
        path: endpoint.0.clone(),
        identity: (metadata.dev(), metadata.ino()),
        _lease: lease,
    })
}
pub(in crate::daemon) fn connect(endpoint: &Endpoint) -> io::Result<Stream> {
    UnixStream::connect(&endpoint.0).map(Stream::new)
}
impl Listener {
    pub(in crate::daemon) fn accept(&self) -> io::Result<Stream> {
        loop {
            if let Some(stream) = self.try_accept()? {
                return Ok(stream);
            }
            std::thread::sleep(std::time::Duration::from_millis(2));
        }
    }
    pub(in crate::daemon) fn try_accept(&self) -> io::Result<Option<Stream>> {
        match self.socket.accept() {
            Ok((stream, _)) => Ok(Some(Stream::new(stream))),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => Ok(None),
            Err(error) => Err(error),
        }
    }
}
impl Drop for Listener {
    fn drop(&mut self) {
        // Never unlink a successor. The endpoint OS lease is still held here.
        if fs::symlink_metadata(&self.path).is_ok_and(|metadata| {
            metadata.file_type().is_socket() && (metadata.dev(), metadata.ino()) == self.identity
        }) {
            let _ = fs::remove_file(&self.path);
        }
    }
}

pub(in crate::daemon) fn private_bytes() -> Option<u64> {
    None
}

pub(in crate::daemon) fn set_timeout(
    stream: &mut Stream,
    timeout: std::time::Duration,
) -> io::Result<()> {
    stream.deadline = std::time::Instant::now()
        .checked_add(timeout)
        .ok_or_else(|| io::Error::other("daemon timeout overflow"))?;
    Ok(())
}

#[cfg(test)]
mod deadline_tests {
    use super::*;
    #[test]
    fn endpoint_lease_and_inode_guard_do_not_delete_a_successor_or_lock() {
        let identity = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let endpoint = Endpoint::generation(identity).unwrap();
        let owner = listener(&endpoint).unwrap();
        assert_eq!(
            listener(&endpoint).err().unwrap().kind(),
            io::ErrorKind::AddrInUse
        );
        fs::remove_file(&endpoint.0).unwrap();
        let successor = UnixListener::bind(&endpoint.0).unwrap();
        drop(owner);
        assert!(
            endpoint.0.exists(),
            "old listener must not remove a different socket inode"
        );
        assert!(
            endpoint.0.with_extension("lock").exists(),
            "control lock files are never removed"
        );
        drop(successor);
        fs::remove_file(&endpoint.0).unwrap();
    }
    #[test]
    fn silent_peer_cannot_hold_request_forever() {
        use std::io::{Read, Write};
        let (one, mut peer) = UnixStream::pair().unwrap();
        let mut stream = Stream::new(one);
        set_timeout(&mut stream, std::time::Duration::from_millis(10)).unwrap();
        assert!(stream.read(&mut [0]).is_err());
        assert_eq!(
            stream.write(b"expired").unwrap_err().kind(),
            io::ErrorKind::TimedOut
        );
        set_timeout(&mut stream, std::time::Duration::from_secs(1)).unwrap();
        peer.write_all(b"x").unwrap();
        let mut byte = [0];
        stream.read_exact(&mut byte).unwrap();
        assert_eq!(byte, *b"x");
    }
}
