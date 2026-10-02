//! The HashLink carriers an x-idl generated model takes from its adapter's
//! `crate::runtime`: text, bytes, roots, futures, enums, errors, managed
//! records and host hooks, over hl_abi. An adapter re-exports these as its
//! `runtime` module, and may wrap `host::raise` to name its library.

use std::ffi::c_void;
use std::marker::PhantomData;
use std::mem::{ManuallyDrop, size_of};
use std::sync::Arc;
#[cfg(not(target_family = "wasm"))]
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

#[cfg(all(unix, not(target_family = "wasm")))]
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

#[cfg(not(target_family = "wasm"))]
fn future_create() -> FutureCreate {
    static SYMBOL: OnceLock<Option<FutureCreate>> = OnceLock::new();
    match *SYMBOL.get_or_init(|| unsafe { runtime_symbol(b"hlp_future_create\0") }) {
        Some(symbol) => symbol,
        None => {
            host::raise(
                ErrorKind::Runtime,
                "this API requires an Ash runtime with Future support",
            );
            unreachable!()
        }
    }
}

#[cfg(target_family = "wasm")]
fn future_create() -> FutureCreate {
    ash_future_abi::hlp_future_create
}

#[cfg(not(target_family = "wasm"))]
fn future_resolve() -> FutureSettle {
    static SYMBOL: OnceLock<Option<FutureSettle>> = OnceLock::new();
    match *SYMBOL.get_or_init(|| unsafe { runtime_symbol(b"hlp_future_resolve\0") }) {
        Some(symbol) => symbol,
        None => {
            host::raise(
                ErrorKind::Runtime,
                "this API requires an Ash runtime with Future support",
            );
            unreachable!()
        }
    }
}

#[cfg(target_family = "wasm")]
fn future_resolve() -> FutureSettle {
    unsafe extern "C" fn resolve(future: *mut AshFuture, value: *mut vdynamic) -> bool {
        unsafe { ash_future_abi::hlp_future_resolve(future, value.cast()) }
    }
    resolve
}

#[cfg(not(target_family = "wasm"))]
fn future_reject() -> FutureSettle {
    static SYMBOL: OnceLock<Option<FutureSettle>> = OnceLock::new();
    match *SYMBOL.get_or_init(|| unsafe { runtime_symbol(b"hlp_future_reject\0") }) {
        Some(symbol) => symbol,
        None => {
            host::raise(
                ErrorKind::Runtime,
                "this API requires an Ash runtime with Future support",
            );
            unreachable!()
        }
    }
}

#[cfg(target_family = "wasm")]
fn future_reject() -> FutureSettle {
    unsafe extern "C" fn reject(future: *mut AshFuture, error: *mut vdynamic) -> bool {
        unsafe { ash_future_abi::hlp_future_reject(future, error.cast()) }
    }
    reject
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
    use super::{ErrorKind, Text, c_void, hl_throw};

    #[cfg(target_family = "wasm")]
    unsafe extern "C" {
        fn ash_host_agent(name: *const u8, name_len: u32, address: u32) -> i32;
        fn ash_host_watch(
            word: *const u32,
            handler: unsafe extern "C" fn(*mut c_void),
            context: *mut c_void,
        ) -> *const u32;
    }

    /// Throw `message` to the calling Haxe code.
    pub fn raise(_: ErrorKind, message: &str) {
        let text = Text::new(message);
        unsafe { hl_throw(text.value().0) }
    }

    /// Start a browser service through Ash's runtime-owned page harness.
    #[cfg(target_family = "wasm")]
    pub fn agent(name: &str, address: usize) -> bool {
        let (Ok(address), Ok(name_len)) = (u32::try_from(address), u32::try_from(name.len()))
        else {
            return false;
        };
        unsafe { ash_host_agent(name.as_ptr(), name_len, address) != 0 }
    }

    /// Natively there is no page to start a service in.
    #[cfg(not(target_family = "wasm"))]
    pub fn agent(_: &str, _: usize) -> bool {
        false
    }

    /// Register the mailbox completion word with Ash's fiber scheduler.
    ///
    /// # Safety
    /// The word and callback context must remain valid for the program's
    /// lifetime.
    #[cfg(target_family = "wasm")]
    pub unsafe fn watch(
        word: *const u32,
        handler: unsafe extern "C" fn(*mut c_void),
        context: *mut c_void,
    ) -> *const u32 {
        unsafe { ash_host_watch(word, handler, context) }
    }

    /// Natively there is no scheduler to register with.
    ///
    /// # Safety
    /// Nothing is registered; the arguments are not used.
    #[cfg(not(target_family = "wasm"))]
    pub unsafe fn watch(
        _: *const u32,
        _: unsafe extern "C" fn(*mut c_void),
        _: *mut c_void,
    ) -> *const u32 {
        std::ptr::null()
    }
}

#[derive(Clone)]
pub struct Text(Option<Arc<str>>);

impl Text {
    pub const NULL: Self = Self(None);

    pub fn new(value: &str) -> Self {
        Self(Some(Arc::from(value)))
    }

    /// # Safety
    /// `value` is null or a live HashLink `String`.
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

/// A `haxe.io.Bytes` as HashLink lays it out: its length, then its data.
/// A generated model's `Buffer` arguments arrive as one.
#[repr(C)]
pub struct HlBytes {
    pub t: *mut hl_type,
    pub length: i32,
    pub b: *mut u8,
}

enum BufferStorage {
    Borrowed(*mut HlBytes),
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

struct HlBytesRoot(Box<*mut HlBytes>);

unsafe impl Send for HlBytesRoot {}
unsafe impl Sync for HlBytesRoot {}

impl HlBytesRoot {
    fn new(value: *mut HlBytes) -> Self {
        let mut slot = Box::new(value);
        unsafe { hl_add_root((&mut *slot as *mut *mut HlBytes).cast()) };
        Self(slot)
    }
}

impl Drop for HlBytesRoot {
    fn drop(&mut self) {
        unsafe { hl_remove_root((&mut *self.0 as *mut *mut HlBytes).cast()) };
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

    /// # Safety
    /// `value` is null or a live `haxe.io.Bytes`, which must outlive the
    /// buffer unless it is rooted.
    pub unsafe fn from_hl(value: *mut HlBytes) -> Self {
        if value.is_null() {
            Self::NULL
        } else {
            Self(Some(BufferStorage::Borrowed(value)))
        }
    }

    fn hl(&self) -> Option<*mut HlBytes> {
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

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn as_ptr(&self) -> *const u8 {
        if let Some(value) = self.hl() {
            unsafe { (*value).b.cast_const() }
        } else {
            match &self.0 {
                Some(BufferStorage::Owned(value)) => value.as_ptr(),
                _ => std::ptr::null(),
            }
        }
    }

    pub fn as_mut_ptr(&self) -> Option<*mut u8> {
        self.hl().map(|value| unsafe { (*value).b })
    }

    pub fn is_read_only(&self) -> bool {
        matches!(self.0, Some(BufferStorage::Owned(_)))
    }

    /// # Safety
    /// The bytes must not change while the slice is held.
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
    /// # Safety
    /// As `Buffer::from_hl`.
    pub unsafe fn from_hl(value: *mut HlBytes) -> Self {
        Self(unsafe { Buffer::from_hl(value) })
    }

    pub fn as_mut_ptr(&self) -> *mut u8 {
        self.0.as_mut_ptr().unwrap_or_default()
    }

    pub fn len(&self) -> usize {
        self.0.len()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
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

    // Making one asks the runtime for a future, which a default should not.
    #[allow(clippy::new_without_default)]
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
    let size = i32::try_from(size_of::<Managed<T>>()).expect("a managed value is too large");
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
        "HashLink could not allocate a managed value"
    );
    unsafe {
        managed.write(Managed {
            finalizer: finalize::<T>,
            value: ManuallyDrop::new(value),
        });
    }
    managed
}

/// # Safety
/// `value` is a live `Managed<T>` from `managed_new`, not mutably borrowed
/// for `'a`.
pub unsafe fn managed_ref<'a, T>(value: *mut Managed<T>) -> &'a T {
    unsafe { &*(&(*value).value as *const ManuallyDrop<T>).cast::<T>() }
}

/// # Safety
/// `value` is a live `Managed<T>` from `managed_new`, not otherwise borrowed
/// for `'a`.
pub unsafe fn managed_mut<'a, T>(value: *mut Managed<T>) -> &'a mut T {
    unsafe { &mut *(&mut (*value).value as *mut ManuallyDrop<T>).cast::<T>() }
}
