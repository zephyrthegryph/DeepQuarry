//! Windows daemon launch with an explicit handle-inheritance allowlist.
//! Stable Command stdio replacement leaves arbitrary inheritable parent capture
//! pipes open in the daemon. Only the three duplicated standard handles cross.
use std::{
    ffi::{c_void, OsStr},
    fs::File,
    io, mem,
    os::windows::{
        ffi::OsStrExt,
        io::{AsRawHandle, FromRawHandle, OwnedHandle},
    },
    path::Path,
    ptr,
};
type Handle = *mut c_void;
const HANDLE_LIST: usize = 0x0002_0002;
const DUPLICATE_SAME_ACCESS: u32 = 2;
const STARTF_USESTDHANDLES: u32 = 0x100;
const CREATE_UNICODE_ENVIRONMENT: u32 = 0x400;
const EXTENDED_STARTUPINFO_PRESENT: u32 = 0x0008_0000;
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const BELOW_NORMAL_PRIORITY_CLASS: u32 = 0x4000;
#[repr(C)]
struct StartupInfo {
    cb: u32,
    reserved: *mut u16,
    desktop: *mut u16,
    title: *mut u16,
    x: u32,
    y: u32,
    x_size: u32,
    y_size: u32,
    x_chars: u32,
    y_chars: u32,
    fill: u32,
    flags: u32,
    show: u16,
    reserved_len: u16,
    reserved_bytes: *mut u8,
    stdin: Handle,
    stdout: Handle,
    stderr: Handle,
}
#[repr(C)]
struct StartupInfoEx {
    startup: StartupInfo,
    attributes: *mut c_void,
}
#[repr(C)]
struct ProcessInfo {
    process: Handle,
    thread: Handle,
    pid: u32,
    tid: u32,
}
#[link(name = "kernel32")]
unsafe extern "system" {
    fn GetCurrentProcess() -> Handle;
    fn DuplicateHandle(
        source_process: Handle,
        source: Handle,
        target_process: Handle,
        target: *mut Handle,
        access: u32,
        inherit: i32,
        options: u32,
    ) -> i32;
    fn InitializeProcThreadAttributeList(
        list: *mut c_void,
        count: u32,
        flags: u32,
        size: *mut usize,
    ) -> i32;
    fn UpdateProcThreadAttribute(
        list: *mut c_void,
        flags: u32,
        attribute: usize,
        value: *mut c_void,
        size: usize,
        previous: *mut c_void,
        returned: *mut usize,
    ) -> i32;
    fn DeleteProcThreadAttributeList(list: *mut c_void);
    fn CreateProcessW(
        application: *const u16,
        command: *mut u16,
        process_security: *mut c_void,
        thread_security: *mut c_void,
        inherit: i32,
        flags: u32,
        environment: *const c_void,
        directory: *const u16,
        startup: *mut StartupInfo,
        info: *mut ProcessInfo,
    ) -> i32;
}
fn duplicate(file: &File) -> io::Result<OwnedHandle> {
    let mut handle = ptr::null_mut();
    // Source File remains live; adopt the distinct inheritable duplicate once.
    let ok = unsafe {
        DuplicateHandle(
            GetCurrentProcess(),
            file.as_raw_handle(),
            GetCurrentProcess(),
            &mut handle,
            0,
            1,
            DUPLICATE_SAME_ACCESS,
        )
    };
    if ok == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe { OwnedHandle::from_raw_handle(handle) })
}
struct Attributes {
    storage: Vec<usize>,
}
impl Attributes {
    fn new(handles: &mut [Handle; 3]) -> io::Result<Self> {
        let mut bytes = 0;
        // Sizing call does not initialize a list; no Delete is needed on failure.
        unsafe {
            InitializeProcThreadAttributeList(ptr::null_mut(), 1, 0, &mut bytes);
        }
        if bytes == 0 {
            return Err(io::Error::last_os_error());
        }
        let words = bytes
            .checked_add(mem::size_of::<usize>() - 1)
            .ok_or_else(|| io::Error::other("daemon attribute size overflow"))?
            / mem::size_of::<usize>();
        let mut storage = vec![0usize; words];
        if unsafe {
            InitializeProcThreadAttributeList(storage.as_mut_ptr().cast(), 1, 0, &mut bytes)
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        let mut list = Self { storage };
        // The allowlist and its three owned duplicates stay live through spawn.
        if unsafe {
            UpdateProcThreadAttribute(
                list.as_mut_ptr(),
                0,
                HANDLE_LIST,
                handles.as_mut_ptr().cast(),
                mem::size_of_val(handles),
                ptr::null_mut(),
                ptr::null_mut(),
            )
        } == 0
        {
            return Err(io::Error::last_os_error());
        }
        Ok(list)
    }
    fn as_mut_ptr(&mut self) -> *mut c_void {
        self.storage.as_mut_ptr().cast()
    }
}
impl Drop for Attributes {
    fn drop(&mut self) {
        unsafe {
            DeleteProcThreadAttributeList(self.as_mut_ptr());
        }
    }
}
fn wide(value: &OsStr) -> io::Result<Vec<u16>> {
    let mut value: Vec<_> = value.encode_wide().collect();
    if value.contains(&0) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "daemon executable path contains NUL",
        ));
    }
    value.push(0);
    Ok(value)
}
fn command_line(executable: &OsStr) -> io::Result<Vec<u16>> {
    let executable = wide(executable)?;
    let mut out = vec![u16::from(b'"')];
    let mut slashes = 0;
    for &c in &executable[..executable.len() - 1] {
        if c == u16::from(b'\\') {
            slashes += 1;
            continue;
        }
        if c == u16::from(b'"') {
            out.extend(std::iter::repeat_n(u16::from(b'\\'), slashes * 2 + 1));
        } else {
            out.extend(std::iter::repeat_n(u16::from(b'\\'), slashes));
        }
        slashes = 0;
        out.push(c);
    }
    out.extend(std::iter::repeat_n(u16::from(b'\\'), slashes * 2));
    out.push(u16::from(b'"'));
    out.extend(" --serve-daemon".encode_utf16());
    out.push(0);
    Ok(out)
}
pub(super) fn spawn(executable: &Path, log: File) -> io::Result<()> {
    let input = File::open(r"\\.\NUL")?;
    let output = std::fs::OpenOptions::new().write(true).open(r"\\.\NUL")?;
    let stdin = duplicate(&input)?;
    let stdout = duplicate(&output)?;
    let stderr = duplicate(&log)?;
    let mut handles = [
        stdin.as_raw_handle(),
        stdout.as_raw_handle(),
        stderr.as_raw_handle(),
    ];
    let mut attributes = Attributes::new(&mut handles)?;
    let mut startup = StartupInfoEx {
        startup: StartupInfo {
            cb: mem::size_of::<StartupInfoEx>() as u32,
            reserved: ptr::null_mut(),
            desktop: ptr::null_mut(),
            title: ptr::null_mut(),
            x: 0,
            y: 0,
            x_size: 0,
            y_size: 0,
            x_chars: 0,
            y_chars: 0,
            fill: 0,
            flags: STARTF_USESTDHANDLES,
            show: 0,
            reserved_len: 0,
            reserved_bytes: ptr::null_mut(),
            stdin: handles[0],
            stdout: handles[1],
            stderr: handles[2],
        },
        attributes: attributes.as_mut_ptr(),
    };
    let mut process = ProcessInfo {
        process: ptr::null_mut(),
        thread: ptr::null_mut(),
        pid: 0,
        tid: 0,
    };
    let application = wide(executable.as_os_str())?;
    let mut command = command_line(executable.as_os_str())?;
    // Null env/CWD preserve caller state. Flags: extended startup info, no console,
    // Unicode environment and below-normal priority. All buffers remain live.
    let ok = unsafe {
        CreateProcessW(
            application.as_ptr(),
            command.as_mut_ptr(),
            ptr::null_mut(),
            ptr::null_mut(),
            1,
            EXTENDED_STARTUPINFO_PRESENT
                | CREATE_NO_WINDOW
                | CREATE_UNICODE_ENVIRONMENT
                | BELOW_NORMAL_PRIORITY_CLASS,
            ptr::null(),
            ptr::null(),
            &mut startup.startup,
            &mut process,
        )
    };
    if ok == 0 {
        return Err(io::Error::last_os_error());
    }
    // Close only our launch references. Do not wait/terminate the child daemon.
    let _process = unsafe { OwnedHandle::from_raw_handle(process.process) };
    let _thread = unsafe { OwnedHandle::from_raw_handle(process.thread) };
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn executable_is_one_quoted_argument_with_only_fixed_daemon_switch() {
        let source = OsStr::new(r"E:\directory with spaces\compiler.exe");
        let line = command_line(source).unwrap();
        assert_eq!(
            String::from_utf16(&line[..line.len() - 1]).unwrap(),
            r#""E:\directory with spaces\compiler.exe" --serve-daemon"#
        );
        assert_eq!(line.last(), Some(&0));
    }
    #[test]
    fn nul_is_rejected_and_quote_backslash_pairs_are_preserved() {
        use std::os::windows::ffi::OsStringExt;
        let bad = std::ffi::OsString::from_wide(&[65, 0, 66]);
        assert!(wide(&bad).is_err());
        assert!(command_line(&bad).is_err());
        let line = command_line(OsStr::new("a\"b\\")).unwrap();
        assert_eq!(
            String::from_utf16(&line[..line.len() - 1]).unwrap(),
            r#""a\"b\\" --serve-daemon"#
        );
    }
}
