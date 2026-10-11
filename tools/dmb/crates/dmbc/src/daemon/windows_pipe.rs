//! Audited Win32 handle boundary: pipe ACL grants only the process token user.
use std::{
    ffi::c_void,
    fs::File,
    io,
    os::windows::io::{AsRawHandle, FromRawHandle},
    ptr,
};
type Handle = *mut c_void;
// Individual nonblocking operations must make progress independently of frame
// length and pipe quota. Framing stays in protocol::send/receive_bounded.
const IO_CHUNK: usize = 4096;
#[cfg(test)]
#[path = "windows_pipe_frame_tests.rs"]
mod frame_tests;
#[repr(C)]
struct SecurityAttributes {
    length: u32,
    descriptor: *mut c_void,
    inherit: i32,
}
#[link(name = "kernel32")]
unsafe extern "system" {
    fn GetCurrentProcess() -> Handle;
    fn CloseHandle(handle: Handle) -> i32;
    fn LocalFree(memory: Handle) -> Handle;
    fn CreateNamedPipeW(
        name: *const u16,
        open: u32,
        mode: u32,
        instances: u32,
        out_size: u32,
        in_size: u32,
        timeout: u32,
        security: *const SecurityAttributes,
    ) -> Handle;
    fn PeekNamedPipe(
        pipe: Handle,
        buffer: Handle,
        size: u32,
        read: *mut u32,
        available: *mut u32,
        left: *mut u32,
    ) -> i32;
    fn SetNamedPipeHandleState(
        pipe: Handle,
        mode: *const u32,
        collection: *const u32,
        timeout: *const u32,
    ) -> i32;
    fn ConnectNamedPipe(pipe: Handle, overlapped: Handle) -> i32;
    fn CreateFileW(
        name: *const u16,
        access: u32,
        share: u32,
        security: Handle,
        creation: u32,
        flags: u32,
        template: Handle,
    ) -> Handle;
}
#[link(name = "advapi32")]
unsafe extern "system" {
    fn OpenProcessToken(process: Handle, access: u32, token: *mut Handle) -> i32;
    fn GetTokenInformation(
        token: Handle,
        class: u32,
        buffer: Handle,
        length: u32,
        required: *mut u32,
    ) -> i32;
    fn ConvertSidToStringSidW(sid: Handle, text: *mut *mut u16) -> i32;
    fn ConvertStringSecurityDescriptorToSecurityDescriptorW(
        text: *const u16,
        revision: u32,
        descriptor: *mut Handle,
        size: *mut u32,
    ) -> i32;
}
pub(in crate::daemon) struct Stream {
    file: File,
    deadline: std::time::Instant,
}
impl Stream {
    fn new(file: File) -> io::Result<Self> {
        let mode = 1; // PIPE_NOWAIT, byte mode unchanged.
        if unsafe { SetNamedPipeHandleState(file.as_raw_handle(), &mode, ptr::null(), ptr::null()) }
            == 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(Self {
            file,
            deadline: std::time::Instant::now() + std::time::Duration::from_secs(20),
        })
    }
    fn remaining(&self) -> io::Result<()> {
        if std::time::Instant::now() >= self.deadline {
            Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "daemon transport deadline expired",
            ))
        } else {
            Ok(())
        }
    }
}
impl io::Read for Stream {
    fn read(&mut self, bytes: &mut [u8]) -> io::Result<usize> {
        if bytes.is_empty() {
            return Ok(0);
        }
        loop {
            self.remaining()?;
            let mut available = 0;
            if unsafe {
                PeekNamedPipe(
                    self.file.as_raw_handle(),
                    ptr::null_mut(),
                    0,
                    ptr::null_mut(),
                    &mut available,
                    ptr::null_mut(),
                )
            } == 0
            {
                return Err(io::Error::last_os_error());
            }
            if available == 0 {
                std::thread::sleep(std::time::Duration::from_millis(2));
                continue;
            }
            // Consume only bytes the pipe actually advertised. A large frame
            // does not turn this nonblocking operation into a full-frame read.
            let length = bytes.len().min(available as usize).min(IO_CHUNK);
            match io::Read::read(&mut self.file, &mut bytes[..length]) {
                Ok(0) => std::thread::sleep(std::time::Duration::from_millis(2)),
                Err(error) if matches!(error.raw_os_error(), Some(232 | 536)) => {
                    std::thread::sleep(std::time::Duration::from_millis(2))
                }
                result => return result,
            }
        }
    }
}
impl io::Write for Stream {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.is_empty() {
            return Ok(0);
        }
        loop {
            self.remaining()?;
            let chunk = &bytes[..bytes.len().min(IO_CHUNK)];
            match io::Write::write(&mut self.file, chunk) {
                Ok(0) => std::thread::sleep(std::time::Duration::from_millis(2)),
                Err(error) if matches!(error.raw_os_error(), Some(232 | 536)) => {
                    std::thread::sleep(std::time::Duration::from_millis(2))
                }
                result => return result,
            }
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        self.remaining()
    }
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
#[derive(Clone)]
pub(in crate::daemon) struct Endpoint {
    name: Vec<u16>,
    sid: String,
}
pub(in crate::daemon) struct Listener {
    endpoint: Endpoint,
    first: std::sync::atomic::AtomicBool,
}
fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(Some(0)).collect()
}
fn user_sid() -> io::Result<String> {
    unsafe {
        let mut token = ptr::null_mut();
        if OpenProcessToken(GetCurrentProcess(), 8, &mut token) == 0 {
            return Err(io::Error::last_os_error());
        }
        let result = (|| {
            let mut required = 0;
            GetTokenInformation(token, 1, ptr::null_mut(), 0, &mut required);
            if required == 0 {
                return Err(io::Error::last_os_error());
            } // usize backing supplies TOKEN_USER pointer alignment.
            let mut buffer =
                vec![0usize; (required as usize).div_ceil(std::mem::size_of::<usize>())];
            if GetTokenInformation(
                token,
                1,
                buffer.as_mut_ptr().cast(),
                required,
                &mut required,
            ) == 0
            {
                return Err(io::Error::last_os_error());
            }
            let sid = *(buffer.as_ptr().cast::<Handle>());
            let mut text = ptr::null_mut();
            if ConvertSidToStringSidW(sid, &mut text) == 0 {
                return Err(io::Error::last_os_error());
            }
            let mut length = 0;
            while *text.add(length) != 0 {
                length += 1;
            }
            let result = String::from_utf16(std::slice::from_raw_parts(text, length))
                .map_err(io::Error::other);
            LocalFree(text.cast());
            result
        })();
        CloseHandle(token);
        result
    }
}
impl Endpoint {
    pub(in crate::daemon) fn current() -> io::Result<Self> {
        let sid = user_sid()?;
        Ok(Self {
            name: wide(&super::namespace::current_name(&format!(
                r"\\.\pipe\dmbd-{sid}"
            ))?),
            sid,
        })
    }
}
pub(in crate::daemon) fn listener(endpoint: &Endpoint) -> io::Result<Listener> {
    Ok(Listener {
        endpoint: endpoint.clone(),
        first: std::sync::atomic::AtomicBool::new(true),
    })
}
pub(in crate::daemon) fn connect(endpoint: &Endpoint) -> io::Result<Stream> {
    unsafe {
        let handle = CreateFileW(
            endpoint.name.as_ptr(),
            0xc0000000,
            0,
            ptr::null_mut(),
            3,
            0,
            ptr::null_mut(),
        );
        if handle as isize == -1 {
            Err(io::Error::last_os_error())
        } else {
            Stream::new(File::from_raw_handle(handle))
        }
    }
}
impl Listener {
    pub(in crate::daemon) fn accept(&self) -> io::Result<Stream> {
        unsafe {
            let mut descriptor = ptr::null_mut();
            let sddl = wide(&format!("D:P(A;;GA;;;{})", self.endpoint.sid));
            if ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.as_ptr(),
                1,
                &mut descriptor,
                ptr::null_mut(),
            ) == 0
            {
                return Err(io::Error::last_os_error());
            }
            let security = SecurityAttributes {
                length: std::mem::size_of::<SecurityAttributes>() as u32,
                descriptor,
                inherit: 0,
            };
            let first = self.first.swap(false, std::sync::atomic::Ordering::AcqRel);
            let handle = CreateNamedPipeW(
                self.endpoint.name.as_ptr(),
                3 | if first { 0x00080000 } else { 0 },
                8,
                255,
                65536,
                65536,
                0,
                &security,
            );
            LocalFree(descriptor);
            if handle as isize == -1 {
                return Err(io::Error::last_os_error());
            }
            if ConnectNamedPipe(handle, ptr::null_mut()) == 0
                && io::Error::last_os_error().raw_os_error() != Some(535)
            {
                let error = io::Error::last_os_error();
                CloseHandle(handle);
                return Err(error);
            }
            Stream::new(File::from_raw_handle(handle))
        }
    }
}

#[repr(C)]
struct MemoryCounters {
    size: u32,
    faults: u32,
    values: [usize; 9],
}
#[link(name = "psapi")]
unsafe extern "system" {
    fn GetProcessMemoryInfo(process: Handle, counters: *mut MemoryCounters, size: u32) -> i32;
}
pub(in crate::daemon) fn private_bytes() -> Option<u64> {
    unsafe {
        let mut counters = MemoryCounters {
            size: std::mem::size_of::<MemoryCounters>() as u32,
            faults: 0,
            values: [0; 9],
        };
        if GetProcessMemoryInfo(GetCurrentProcess(), &mut counters, counters.size) == 0 {
            None
        } else {
            Some(counters.values[8] as u64)
        }
    }
}
#[cfg(test)]
mod acl_tests {
    use super::*;
    #[test]
    fn endpoint_is_derived_from_real_token_sid() {
        let endpoint = Endpoint::current().unwrap();
        assert!(endpoint.sid.starts_with("S-1-"));
        let name = String::from_utf16(&endpoint.name[..endpoint.name.len() - 1]).unwrap();
        assert_eq!(name, format!(r"\\.\pipe\dmbd-{}", endpoint.sid));
    }
    #[test]
    fn connected_idle_pipe_waits_for_bytes_instead_of_reporting_eof() {
        use std::io::{Read, Write};
        let mut endpoint = Endpoint::current().unwrap();
        static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        endpoint.name = wide(&format!(
            r"\\.\pipe\dmbd-test-{}-{}-{}",
            endpoint.sid,
            std::process::id(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ));
        let listener = listener(&endpoint).unwrap();
        let (ack_send, ack_receive) = std::sync::mpsc::channel();
        let worker = std::thread::spawn(move || {
            let mut stream = listener.accept().unwrap();
            std::thread::sleep(std::time::Duration::from_millis(30));
            stream.write_all(b"bytes").unwrap();
            ack_receive
                .recv_timeout(std::time::Duration::from_secs(2))
                .unwrap();
        });
        let mut stream = (0..200)
            .find_map(|_| {
                let result = connect(&endpoint).ok();
                if result.is_none() {
                    std::thread::sleep(std::time::Duration::from_millis(5));
                }
                result
            })
            .expect("private test pipe connects");
        set_timeout(&mut stream, std::time::Duration::from_secs(2)).unwrap();
        let mut bytes = [0; 5];
        stream.read_exact(&mut bytes).unwrap();
        assert_eq!(&bytes, b"bytes");
        ack_send.send(()).unwrap();
        worker.join().unwrap();
        assert!(stream.read(&mut [0]).is_err());
    }
}
