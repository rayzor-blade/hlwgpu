//! HashLink carriers used by xgpu's runtime-neutral generated model.

use std::ffi::c_void;
use std::marker::PhantomData;
use std::mem::{size_of, ManuallyDrop};
use std::sync::Arc;
use std::sync::OnceLock;

use ash_future_abi::AshFuture;
use hl_abi::{hl_type, vbyte, vdynamic, vstring};

unsafe extern "C" {
    static mut hlt_abstract: hl_type;
    fn hl_gc_alloc_gen(ty: *mut hl_type, size: i32, flags: i32) -> *mut c_void;
    fn hl_add_root(slot: *mut c_void);
    fn hl_remove_root(slot: *mut c_void);
    fn hl_alloc_strbytes(format: *const u16, ...) -> *mut vdynamic;
    fn hl_throw(value: *mut vdynamic) -> !;
}

type FutureCreate = unsafe extern "C" fn() -> *mut AshFuture;
type FutureSettle = unsafe extern "C" fn(*mut AshFuture, *mut vdynamic) -> bool;

#[cfg(unix)]
unsafe fn runtime_symbol<T: Copy>(name: &[u8]) -> Option<T> {
    unsafe {
        libloading::os::unix::Library::this()
            .get::<T>(name)
            .ok()
            .map(|symbol| *symbol)
    }
}

#[cfg(windows)]
unsafe fn runtime_symbol<T: Copy>(name: &[u8]) -> Option<T> {
    unsafe {
        libloading::os::windows::Library::this()
            .ok()?
            .get::<T>(name)
            .ok()
            .map(|symbol| *symbol)
    }
}

fn future_create() -> FutureCreate {
    static SYMBOL: OnceLock<Option<FutureCreate>> = OnceLock::new();
    match *SYMBOL.get_or_init(|| unsafe { runtime_symbol(b"hlp_future_create\0") }) {
        Some(symbol) => symbol,
        None => {
            host::raise(
                ErrorKind::Runtime,
                "this GPU API requires an Ash runtime with Future support",
            );
            unreachable!()
        }
    }
}

fn future_resolve() -> FutureSettle {
    static SYMBOL: OnceLock<Option<FutureSettle>> = OnceLock::new();
    match *SYMBOL.get_or_init(|| unsafe { runtime_symbol(b"hlp_future_resolve\0") }) {
        Some(symbol) => symbol,
        None => {
            host::raise(
                ErrorKind::Runtime,
                "this GPU API requires an Ash runtime with Future support",
            );
            unreachable!()
        }
    }
}

fn future_reject() -> FutureSettle {
    static SYMBOL: OnceLock<Option<FutureSettle>> = OnceLock::new();
    match *SYMBOL.get_or_init(|| unsafe { runtime_symbol(b"hlp_future_reject\0") }) {
        Some(symbol) => symbol,
        None => {
            host::raise(
                ErrorKind::Runtime,
                "this GPU API requires an Ash runtime with Future support",
            );
            unreachable!()
        }
    }
}

#[derive(Clone, Copy)]
pub enum ErrorKind {
    Type,
    Runtime,
}

#[derive(Clone, Copy)]
pub struct Value(*mut vdynamic);

unsafe impl Send for Value {}
unsafe impl Sync for Value {}

impl Value {
    pub const fn null() -> Self {
        Self(std::ptr::null_mut())
    }
}

pub mod host {
    use super::{hl_throw, ErrorKind, Text};

    pub fn raise(kind: ErrorKind, message: &str) {
        let prefix = match kind {
            ErrorKind::Type => "GPU type error: ",
            ErrorKind::Runtime => "GPU error: ",
        };
        let text = Text::new(&format!("{prefix}{message}"));
        unsafe { hl_throw(text.value().0) }
    }
}

#[derive(Clone)]
pub struct Text(Option<Arc<str>>);

impl Text {
    pub const NULL: Self = Self(None);

    pub fn new(value: &str) -> Self {
        Self(Some(Arc::from(value)))
    }

    pub unsafe fn from_hl(value: *mut vstring) -> Self {
        if value.is_null() {
            return Self::NULL;
        }
        let units = unsafe { std::slice::from_raw_parts((*value).bytes, (*value).length as usize) };
        Self::new(&String::from_utf16_lossy(units))
    }

    pub fn as_str(&self) -> &str {
        self.0.as_deref().unwrap_or("")
    }

    pub fn value(&self) -> Value {
        let Some(value) = &self.0 else {
            return Value::null();
        };
        let mut units: Vec<u16> = value.encode_utf16().collect();
        units.push(0);
        Value(unsafe { hl_alloc_strbytes(units.as_ptr()) })
    }

    pub fn into_ucs2(self) -> *mut vbyte {
        let Some(value) = self.0 else {
            return std::ptr::null_mut();
        };
        let units: Vec<u16> = value.encode_utf16().chain(std::iter::once(0)).collect();
        let bytes = units.len().saturating_mul(size_of::<u16>());
        let Ok(bytes) = i32::try_from(bytes) else {
            return std::ptr::null_mut();
        };
        let out = unsafe { hl_abi::hl_alloc_bytes(bytes) };
        if !out.is_null() {
            unsafe {
                std::ptr::copy_nonoverlapping(units.as_ptr().cast::<u8>(), out, bytes as usize)
            };
        }
        out
    }
}

enum BufferStorage {
    Borrowed(*mut vstring),
    Rooted(Arc<HlBytesRoot>),
    Owned(Arc<[u8]>),
}

impl Clone for BufferStorage {
    fn clone(&self) -> Self {
        match self {
            Self::Borrowed(value) => Self::Borrowed(*value),
            Self::Rooted(value) => Self::Rooted(value.clone()),
            Self::Owned(value) => Self::Owned(value.clone()),
        }
    }
}

struct HlBytesRoot(Box<*mut vstring>);

unsafe impl Send for HlBytesRoot {}
unsafe impl Sync for HlBytesRoot {}

impl HlBytesRoot {
    fn new(value: *mut vstring) -> Self {
        let mut slot = Box::new(value);
        unsafe { hl_add_root((&mut *slot as *mut *mut vstring).cast()) };
        Self(slot)
    }
}

impl Drop for HlBytesRoot {
    fn drop(&mut self) {
        unsafe { hl_remove_root((&mut *self.0 as *mut *mut vstring).cast()) };
    }
}

#[derive(Clone)]
pub struct Buffer(Option<BufferStorage>);

unsafe impl Send for Buffer {}
unsafe impl Sync for Buffer {}

impl Buffer {
    pub const NULL: Self = Self(None);

    pub fn new(bytes: &[u8]) -> Self {
        Self(Some(BufferStorage::Owned(Arc::from(bytes))))
    }

    pub unsafe fn from_hl(value: *mut vstring) -> Self {
        if value.is_null() {
            Self::NULL
        } else {
            Self(Some(BufferStorage::Borrowed(value)))
        }
    }

    fn hl(&self) -> Option<*mut vstring> {
        match self.0.as_ref()? {
            BufferStorage::Borrowed(value) => Some(*value),
            BufferStorage::Rooted(value) => Some(*value.0),
            BufferStorage::Owned(_) => None,
        }
    }

    pub fn len(&self) -> usize {
        if let Some(value) = self.hl() {
            unsafe { (*value).length.max(0) as usize }
        } else {
            match &self.0 {
                Some(BufferStorage::Owned(value)) => value.len(),
                _ => 0,
            }
        }
    }

    pub fn as_ptr(&self) -> *const u8 {
        if let Some(value) = self.hl() {
            unsafe { (*value).bytes.cast() }
        } else {
            match &self.0 {
                Some(BufferStorage::Owned(value)) => value.as_ptr(),
                _ => std::ptr::null(),
            }
        }
    }

    pub fn as_mut_ptr(&self) -> Option<*mut u8> {
        self.hl().map(|value| unsafe { (*value).bytes.cast() })
    }

    pub fn is_read_only(&self) -> bool {
        matches!(self.0, Some(BufferStorage::Owned(_)))
    }

    pub unsafe fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.as_ptr(), self.len()) }
    }

    fn rooted(&self) -> Self {
        match &self.0 {
            Some(BufferStorage::Borrowed(value)) => Self(Some(BufferStorage::Rooted(Arc::new(
                HlBytesRoot::new(*value),
            )))),
            _ => self.clone(),
        }
    }
}

#[derive(Clone)]
pub struct BufferMut(Buffer);

impl BufferMut {
    pub unsafe fn from_hl(value: *mut vstring) -> Self {
        Self(unsafe { Buffer::from_hl(value) })
    }

    pub fn as_mut_ptr(&self) -> *mut u8 {
        self.0.as_mut_ptr().unwrap_or(std::ptr::null_mut())
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn buffer(&self) -> Buffer {
        self.0.clone()
    }
}

pub trait Rootable: Clone {
    fn rooted(&self) -> Self;
}

impl Rootable for Text {
    fn rooted(&self) -> Self {
        self.clone()
    }
}

impl Rootable for Buffer {
    fn rooted(&self) -> Self {
        self.rooted()
    }
}

pub struct Rooted<T: Rootable>(T);

impl<T: Rootable> Rooted<T> {
    pub fn new(value: T) -> Self {
        Self(value.rooted())
    }

    pub fn get(&self) -> T {
        self.0.clone()
    }
}

impl<T: Rootable> Clone for Rooted<T> {
    fn clone(&self) -> Self {
        Self::new(self.get())
    }
}

pub struct Future<T>(*mut AshFuture, PhantomData<fn() -> T>);

impl<T> Clone for Future<T> {
    fn clone(&self) -> Self {
        *self
    }
}

impl<T> Copy for Future<T> {}

unsafe impl<T> Send for Future<T> {}
unsafe impl<T> Sync for Future<T> {}

impl<T> Future<T> {
    pub const NULL: Self = Self(std::ptr::null_mut(), PhantomData);

    pub fn new() -> Self {
        Self(unsafe { future_create()() }, PhantomData)
    }

    pub fn as_ptr(self) -> *mut AshFuture {
        self.0
    }

    pub fn resolve(self, value: Value) -> bool {
        unsafe { future_resolve()(self.0, value.0) }
    }

    pub fn reject(self, error: Value) -> bool {
        unsafe { future_reject()(self.0, error.0) }
    }

    pub fn resolve_boxed(self, value: Box<T>) -> bool {
        let handle = unsafe { (value.as_ref() as *const T).cast::<i32>().read_unaligned() };
        drop(value);
        let boxed = unsafe { hl_abi::box_i32(handle) };
        unsafe { future_resolve()(self.0, boxed) }
    }
}

impl<T> Rootable for Future<T> {
    fn rooted(&self) -> Self {
        *self
    }
}

pub trait NativeEnum: Copy {
    fn native(self) -> i32;
    fn from_native(value: i32) -> Option<Self>;
}

#[derive(Clone, Copy)]
pub struct Enum<T: NativeEnum + Default>(T);

impl<T: NativeEnum + Default> Enum<T> {
    pub fn from_native(value: i32) -> Self {
        Self(T::from_native(value).unwrap_or_default())
    }

    pub fn get(self) -> T {
        self.0
    }
}

impl<T: NativeEnum + Default> From<T> for Enum<T> {
    fn from(value: T) -> Self {
        Self(value)
    }
}

#[repr(C)]
pub struct Managed<T> {
    finalizer: unsafe extern "C" fn(*mut c_void),
    value: ManuallyDrop<T>,
}

unsafe extern "C" fn finalize<T>(value: *mut c_void) {
    let managed = value.cast::<Managed<T>>();
    unsafe { ManuallyDrop::drop(&mut (*managed).value) };
}

pub fn managed_new<T>(value: T) -> *mut Managed<T> {
    const MEM_KIND_FINALIZER: i32 = 3;
    let size = i32::try_from(size_of::<Managed<T>>()).expect("managed xgpu value is too large");
    let managed = unsafe {
        hl_gc_alloc_gen(
            std::ptr::addr_of_mut!(hlt_abstract),
            size,
            MEM_KIND_FINALIZER,
        )
        .cast::<Managed<T>>()
    };
    assert!(
        !managed.is_null(),
        "HashLink could not allocate an xgpu value"
    );
    unsafe {
        managed.write(Managed {
            finalizer: finalize::<T>,
            value: ManuallyDrop::new(value),
        });
    }
    managed
}

pub unsafe fn managed_ref<'a, T>(value: *mut Managed<T>) -> &'a T {
    unsafe { &*(&(*value).value as *const ManuallyDrop<T>).cast::<T>() }
}

pub unsafe fn managed_mut<'a, T>(value: *mut Managed<T>) -> &'a mut T {
    unsafe { &mut *(&mut (*value).value as *mut ManuallyDrop<T>).cast::<T>() }
}

unsafe extern "C" fn buffer_result_len(value: *mut Managed<Buffer>) -> i32 {
    i32::try_from(unsafe { managed_ref(value) }.len()).unwrap_or(i32::MAX)
}

unsafe extern "C" fn buffer_result_copy(value: *mut Managed<Buffer>, out: *mut vstring) {
    if value.is_null() || out.is_null() {
        return;
    }
    let value = unsafe { managed_ref(value) };
    let len = value.len().min(unsafe { (*out).length.max(0) as usize });
    unsafe { std::ptr::copy_nonoverlapping(value.as_ptr(), (*out).bytes.cast(), len) };
}

hl_abi::define_prim!(
    hlp_buffer_result_len,
    buffer_result_len,
    "PXxgpu_buffer_result__i"
);
hl_abi::define_prim!(
    hlp_buffer_result_copy,
    buffer_result_copy,
    "PXxgpu_buffer_result_OBi__v"
);
