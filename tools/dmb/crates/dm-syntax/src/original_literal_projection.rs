//! Source-free alias of the actual output owner. Composing borrowed spelling
//! here is DATA only. The private producer must validate its concrete owner
//! and SAME final SourceText before current HeaderInput publication.
use crate::{OriginalStringMode, OriginalTokenValue, SettingAdmission, SettingRootLease};
use std::{any::Any, io, sync::Arc};
pub trait OriginalLiteralOutputOwner: Any + Send + Sync {
    fn as_any(&self) -> &dyn Any;
    fn release(self: Arc<Self>);
    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize));
}
pub struct OriginalLiteralProjectionOwner(Option<Arc<dyn OriginalLiteralOutputOwner>>);
impl OriginalLiteralProjectionOwner {
    pub fn from_output_data(owner: Arc<dyn OriginalLiteralOutputOwner>) -> Self {
        Self(Some(owner))
    }
    pub fn output_data(&self) -> &dyn Any {
        self.0.as_ref().expect("live output DATA").as_any()
    }
    pub fn same(&self, other: &Self) -> bool {
        Arc::ptr_eq(self.0.as_ref().unwrap(), other.0.as_ref().unwrap())
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.0.as_ref().unwrap().visit_storage(&mut visit)
    }
}
impl Clone for OriginalLiteralProjectionOwner {
    fn clone(&self) -> Self {
        Self(Some(Arc::clone(self.0.as_ref().unwrap())))
    }
}
impl Drop for OriginalLiteralProjectionOwner {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            owner.release()
        }
    }
}
#[repr(C)]
#[derive(Clone, Copy)]
pub(crate) struct ProjectedLiteral {
    pub bits: u32,
    pub kind: u8,
    pub mode: OriginalStringMode,
    pub alias: [u8; 2],
}
impl ProjectedLiteral {
    pub fn kind(self) -> &'static str {
        match self.kind {
            0 => "Int",
            1 => "Float",
            2 => "String",
            3 => "Resource",
            _ => unreachable!("closed projected literal kind"),
        }
    }
    pub fn value<'a>(self, raw: &'a str) -> io::Result<OriginalTokenValue<&'a str>> {
        let text = if self.alias[1] == 0 {
            ""
        } else {
            let end = raw
                .len()
                .checked_sub(usize::from(self.alias[1] - 1))
                .ok_or(io::ErrorKind::InvalidData)?;
            raw.get(usize::from(self.alias[0])..end)
                .ok_or(io::ErrorKind::InvalidData)?
        };
        Ok(match self.kind {
            0 => OriginalTokenValue::Int(self.bits as i32),
            1 => OriginalTokenValue::Float(f32::from_bits(self.bits)),
            2 => OriginalTokenValue::String(text),
            3 => OriginalTokenValue::Resource(text),
            _ => return Err(io::ErrorKind::InvalidData.into()),
        })
    }
}
#[derive(Clone, Copy)]
pub(crate) struct ProjectedLiteralRef<'a> {
    pub descriptor: ProjectedLiteral,
    pub raw: Option<&'a str>,
    pub raw_capacity: usize,
    pub owner: &'a OriginalLiteralProjectionOwner,
    pub ordinal: usize,
}
impl<'a> ProjectedLiteralRef<'a> {
    pub fn raw(self) -> io::Result<&'a str> {
        self.raw.ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::NotConnected,
                "Original projected spelling has no authenticated source loan",
            )
        })
    }
    pub fn same(self, other: ProjectedLiteralRef<'_>) -> bool {
        self.ordinal == other.ordinal && self.owner.same(other.owner)
    }
}
pub(crate) struct DetachedProjectedLiteral {
    pub raw: Box<str>,
    pub descriptor: ProjectedLiteral,
    pub owner: OriginalLiteralProjectionOwner,
    pub ordinal: usize,
}
impl DetachedProjectedLiteral {
    pub fn new(
        data: ProjectedLiteralRef<'_>,
        a: &SettingAdmission<'_>,
    ) -> io::Result<(Box<Self>, SettingRootLease)> {
        a.checkpoint()
            .map_err(|e| a.take_operational_error().unwrap_or(e))?;
        let text = data.raw()?;
        let bytes = std::mem::size_of::<Self>()
            .checked_add(text.len())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        let credit = a
            .reserve(bytes)
            .map_err(|e| a.take_operational_error().unwrap_or(e))?;
        let raw = if text.is_empty() {
            Box::<str>::default()
        } else {
            let layout = std::alloc::Layout::array::<u8>(text.len())
                .map_err(|_| io::ErrorKind::OutOfMemory)?;
            let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) })
                .ok_or(io::ErrorKind::OutOfMemory)?;
            // SAFETY: the length-derived Global layout is funded before allocation;
            // the complete valid UTF-8 loan initializes the same Box<str> layout.
            unsafe {
                std::ptr::copy_nonoverlapping(text.as_ptr(), pointer.as_ptr(), text.len());
                Box::from_raw(
                    std::ptr::slice_from_raw_parts_mut(pointer.as_ptr(), text.len()) as *mut str,
                )
            }
        };
        let layout = std::alloc::Layout::new::<Self>();
        let pointer = std::ptr::NonNull::new(unsafe { std::alloc::alloc(layout) }.cast::<Self>())
            .ok_or(io::ErrorKind::OutOfMemory)?;
        // SAFETY: exact funded Global Box layout, initialized once, same Box drop.
        unsafe {
            pointer.as_ptr().write(Self {
                raw,
                descriptor: data.descriptor,
                owner: data.owner.clone(),
                ordinal: data.ordinal,
            });
            Ok((Box::from_raw(pointer.as_ptr()), credit))
        }
    }
    pub fn view(&self) -> ProjectedLiteralRef<'_> {
        ProjectedLiteralRef {
            descriptor: self.descriptor,
            raw: Some(&self.raw),
            raw_capacity: self.raw.len(),
            owner: &self.owner,
            ordinal: self.ordinal,
        }
    }
}
