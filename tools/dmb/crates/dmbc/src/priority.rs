//! Process priority: dmbc (client, daemon and their worker threads) runs below normal so a compile never starves the
//! interactive desktop. `DMB_PRIORITY=normal` opts out; `DMB_PRIORITY=idle` goes lower still.
//! Windows: `SetPriorityClass` on the current process (child processes inherit the class). Unix: `setpriority(PRIO_PROCESS)`.
use std::ffi::OsStr;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Level {
    Normal,
    BelowNormal,
    Idle,
}

/// Parse `DMB_PRIORITY`; unset or empty means below normal. An unknown value is an error naming the accepted ones.
pub fn parse(value: Option<&OsStr>) -> Result<Level, String> {
    match value.and_then(OsStr::to_str) {
        None | Some("") | Some("below_normal") | Some("below-normal") | Some("low") => Ok(Level::BelowNormal),
        Some("normal") => Ok(Level::Normal),
        Some("idle") => Ok(Level::Idle),
        Some(other) => Err(format!("DMB_PRIORITY must be normal, below_normal or idle, not {other:?}")),
    }
}

/// Lower this process's priority per `DMB_PRIORITY`. Returns the level applied, or None when it was left alone or the OS refused
/// (never fatal: a compile at normal priority is still a correct compile). Logs one line on stderr only when it fails.
pub fn apply_from_env() -> Option<Level> {
    let level = match parse(std::env::var_os("DMB_PRIORITY").as_deref()) {
        Ok(Level::Normal) => return None,
        Ok(level) => level,
        Err(message) => {
            eprintln!("dmbc: {message}; keeping normal priority");
            return None;
        }
    };
    match os::set(level) {
        Ok(()) => Some(level),
        Err(code) => {
            eprintln!("dmbc: could not lower process priority (os error {code}); continuing at normal priority");
            None
        }
    }
}

#[cfg(windows)]
mod os {
    use super::Level;
    use std::ffi::c_void;
    const BELOW_NORMAL_PRIORITY_CLASS: u32 = 0x0000_4000;
    const IDLE_PRIORITY_CLASS: u32 = 0x0000_0040;
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetCurrentProcess() -> *mut c_void;
        fn SetPriorityClass(process: *mut c_void, class: u32) -> i32;
        fn GetLastError() -> u32;
    }
    pub fn set(level: Level) -> Result<(), i32> {
        let class = match level {
            Level::Idle => IDLE_PRIORITY_CLASS,
            _ => BELOW_NORMAL_PRIORITY_CLASS,
        };
        unsafe {
            if SetPriorityClass(GetCurrentProcess(), class) != 0 {
                Ok(())
            } else {
                Err(GetLastError() as i32)
            }
        }
    }
    /// The current priority class, for tests and diagnostics.
    pub fn current_class() -> u32 {
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn GetPriorityClass(process: *mut c_void) -> u32;
        }
        unsafe { GetPriorityClass(GetCurrentProcess()) }
    }
}

#[cfg(unix)]
mod os {
    use super::Level;
    unsafe extern "C" {
        fn setpriority(which: i32, who: u32, prio: i32) -> i32;
        fn getpriority(which: i32, who: u32) -> i32;
    }
    const PRIO_PROCESS: i32 = 0;
    pub fn set(level: Level) -> Result<(), i32> {
        let nice = match level {
            Level::Idle => 19,
            _ => 10,
        };
        // who = 0 is the calling process (on Linux, the calling thread; threads spawned afterwards inherit it, and
        // main calls this before any worker exists).
        if unsafe { setpriority(PRIO_PROCESS, 0, nice) } == 0 {
            Ok(())
        } else {
            Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(-1))
        }
    }
    pub fn current_class() -> u32 {
        unsafe { getpriority(PRIO_PROCESS, 0) as u32 }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_below_normal_and_normal_opts_out() {
        assert_eq!(parse(None).unwrap(), Level::BelowNormal);
        assert_eq!(parse(Some(OsStr::new(""))).unwrap(), Level::BelowNormal);
        assert_eq!(parse(Some(OsStr::new("normal"))).unwrap(), Level::Normal);
        assert_eq!(parse(Some(OsStr::new("idle"))).unwrap(), Level::Idle);
        assert!(parse(Some(OsStr::new("high"))).is_err());
    }

    /// Runs in a child process so the test harness's own priority is untouched.
    #[test]
    fn applying_lowers_the_real_priority_class() {
        if std::env::var_os("DMB_PRIORITY_CHILD").is_some() {
            let before = os::current_class();
            assert_eq!(set_below_normal(), Ok(()));
            let after = os::current_class();
            #[cfg(windows)]
            assert_eq!((before, after), (0x20, 0x4000));
            #[cfg(unix)]
            assert!(after > before || before >= 10, "nice {before} -> {after}");
            println!("priority-child-ok");
            return;
        }
        let exe = std::env::current_exe().unwrap();
        let output = std::process::Command::new(exe)
            .args(["priority::tests::applying_lowers_the_real_priority_class", "--exact", "--nocapture"])
            .env("DMB_PRIORITY_CHILD", "1")
            .env_remove("DMB_PRIORITY")
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(output.status.success() && text.contains("priority-child-ok"), "{text}\n{}", String::from_utf8_lossy(&output.stderr));
    }

    fn set_below_normal() -> Result<(), i32> {
        os::set(Level::BelowNormal)
    }
}
