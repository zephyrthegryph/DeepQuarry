use std::{
    fs, io,
    os::unix::{
        fs::{FileTypeExt, MetadataExt, PermissionsExt},
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
}
unsafe extern "C" {
    fn getuid() -> u32;
}
impl Endpoint {
    pub(in crate::daemon) fn current() -> io::Result<Self> {
        let uid = unsafe { getuid() };
        let directory = std::env::temp_dir().join(format!("dmbd-{uid}"));
        match fs::symlink_metadata(&directory) {
            Ok(metadata) => {
                if !metadata.is_dir()
                    || metadata.uid() != uid
                    || metadata.permissions().mode() & 0o077 != 0
                {
                    return Err(io::Error::new(
                        io::ErrorKind::PermissionDenied,
                        "daemon runtime directory is not private",
                    ));
                }
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                fs::create_dir(&directory)?;
                fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))?;
            }
            Err(e) => return Err(e),
        }
        Ok(Self(directory.join("compiler.sock")))
    }
}
pub(in crate::daemon) fn listener(endpoint: &Endpoint) -> io::Result<Listener> {
    if endpoint.0.exists() {
        if !fs::symlink_metadata(&endpoint.0)?.file_type().is_socket() {
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
                ))
            }
            Err(_) => fs::remove_file(&endpoint.0)?,
        }
    }
    let socket = UnixListener::bind(&endpoint.0)?;
    fs::set_permissions(&endpoint.0, fs::Permissions::from_mode(0o600))?;
    Ok(Listener {
        socket,
        path: endpoint.0.clone(),
    })
}
pub(in crate::daemon) fn connect(endpoint: &Endpoint) -> io::Result<Stream> {
    UnixStream::connect(&endpoint.0).map(Stream::new)
}
impl Listener {
    pub(in crate::daemon) fn accept(&self) -> io::Result<Stream> {
        self.socket.accept().map(|(stream, _)| Stream::new(stream))
    }
}
impl Drop for Listener {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
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
