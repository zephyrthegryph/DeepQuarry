//! The order Python's `os.walk` visits files in, for lints whose result depends on which of two
//! files is seen first (`instance_list` keeps the first declaration of a `type/var`, `init`'s
//! `init_from_table` flags are overwritten by the last file that sets one).
//!
//! `os.walk(top)` yields a directory's files before descending into its sub-directories, and
//! visits entries in `os.scandir` order. On NTFS that is the directory's index order: names
//! compared case-insensitively on their upper-cased UTF-16 code units. (On ext4 it is hash order,
//! which no port can reproduce; a lint that must be stable there must not depend on the order.)
//!
//! The tree is sorted by byte order of the path instead (`Tree::select`); [`walk_order`] re-sorts a
//! selection into the walk order.

use std::cmp::Ordering;

use crate::tree::SourceFile;

/// The NTFS name key: upper-cased UTF-16 code units (a character whose upper case is more than one
/// character keeps its own: the `$UpCase` table is a per-code-unit map).
fn name_key_using<C:crate::key_policy_control::Control>(name:&str,c:&mut C)->Result<Vec<u16>,C::Error>{let mut out=Vec::new();if C::CHECKED{let count=name.len().checked_mul(4).ok_or_else(||c.overflow())?;crate::key_policy_control::reserve(c,||count.checked_mul(std::mem::size_of::<u16>())?.checked_add(128))?;out.try_reserve_exact(name.len()).map_err(|_|c.allocation_failed())?;if out.capacity()>count{return Err(c.allocation_failed())}}for ch in name.chars(){c.checkpoint()?;let mut up=ch.to_uppercase();let u=match(up.next(),up.next()){(Some(u),None)=>u,_=>ch};let mut buf=[0u16;2];out.extend_from_slice(u.encode_utf16(&mut buf));}Ok(out)}

/// `(is_dir, name key)` per path component: files (false) sort before directories (true) at each
/// level, the entries of each kind in name order.
pub type WalkKey=Vec<(bool,Vec<u16>)>;
pub fn walk_key_using<C:crate::key_policy_control::Control>(rel:&str,c:&mut C)->Result<WalkKey,C::Error>{let count=rel.bytes().try_fold(1usize,|n,byte|{c.checkpoint()?;if byte==b'/'{n.checked_add(1).ok_or_else(||c.overflow())}else{Ok(n)}})?;let mut out=Vec::new();if C::CHECKED{let bound=count.checked_mul(4).ok_or_else(||c.overflow())?;crate::key_policy_control::reserve(c,||bound.checked_mul(std::mem::size_of::<(bool,Vec<u16>)>())?.checked_add(128))?;out.try_reserve_exact(count).map_err(|_|c.allocation_failed())?;if out.capacity()>bound{return Err(c.allocation_failed())}}for(index,part)in rel.split('/').enumerate(){c.checkpoint()?;out.push((index+1!=count,name_key_using(part,c)?));}Ok(out)}
fn walk_key(rel:&str)->WalkKey{walk_key_using(rel,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}

pub fn cmp_keys(a:&[(bool,Vec<u16>)],b:&[(bool,Vec<u16>)])->Ordering{cmp_keys_using(a,b,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
pub fn cmp_keys_using<C:crate::key_policy_control::Control>(a:&[(bool,Vec<u16>)],b:&[(bool,Vec<u16>)],control:&mut C)->Result<Ordering,C::Error>{
    for (x, y) in a.iter().zip(b.iter()) {
        control.checkpoint()?;
        match x.0.cmp(&y.0).then_with(|| x.1.cmp(&y.1)) {
            Ordering::Equal => {}
            o => return Ok(o),
        }
    }
    Ok(a.len().cmp(&b.len()))
}

/// `files` in `os.walk` order (NTFS `scandir` order within each directory).
pub fn walk_order<'a>(files: &[&'a SourceFile]) -> Vec<&'a SourceFile> {
    let mut keyed: Vec<(Vec<(bool, Vec<u16>)>, &'a SourceFile)> = files.iter().map(|f| (walk_key(&f.rel), *f)).collect();
    keyed.sort_by(|a, b| cmp_keys(&a.0, &b.0));
    keyed.into_iter().map(|(_, f)| f).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn order(paths: &[&str]) -> Vec<String> {
        let files: Vec<SourceFile> = paths.iter().map(|p| SourceFile::from_text(p, "")).collect();
        let refs: Vec<&SourceFile> = files.iter().collect();
        walk_order(&refs).iter().map(|f| f.rel.clone()).collect()
    }

    #[test]
    fn files_come_before_subdirectories() {
        assert_eq!(
            order(&["code/a/b.dm", "code/z.dm", "code/a.dm", "code/modules/x.dm", "code/modules/a/y.dm"]),
            ["code/a.dm", "code/z.dm", "code/a/b.dm", "code/modules/x.dm", "code/modules/a/y.dm"]
        );
    }

    #[test]
    fn names_compare_case_insensitively_on_upper_case() {
        // '_' (0x5f) sorts after the letters once they are upper-cased, unlike byte order of lower case.
        assert_eq!(order(&["code/a_b.dm", "code/ab.dm", "code/B.dm", "code/a.dm"]), ["code/a.dm", "code/ab.dm", "code/a_b.dm", "code/B.dm"]);
        assert_eq!(order(&["code/Zed.dm", "code/apple.dm"]), ["code/apple.dm", "code/Zed.dm"]);
        // a dot and a space sort before digits and letters
        assert_eq!(order(&["code/a1.dm", "code/a .dm", "code/a.dm"]), ["code/a .dm", "code/a.dm", "code/a1.dm"]);
    }

    #[test]
    fn a_dotted_file_before_its_dot_dm_sibling() {
        assert_eq!(order(&["code/.h/x.dm", "code/.hid.dm", "code/a.dm"]), ["code/.hid.dm", "code/a.dm", "code/.h/x.dm"]);
    }
}
