//! Synchronization primitives for lazy evaluation.
//!
//! Implementation adapted from the `LazyLock` type of the standard library. See:
//! <https://doc.rust-lang.org/std/sync/struct.LazyLock.html>

use crate::{once::Once, RelaxStrategy, Spin};
use core::{cell::Cell, fmt, ops::Deref};

/// A value which is initialized on the first access.
///
/// This type is a thread-safe `LazyLock`, and can be used in statics.
///
/// # Examples
///
/// ```
/// use std::collections::HashMap;
/// use spin::LazyLock;
///
/// static HASHMAP: LazyLock<HashMap<i32, String>> = LazyLock::new(|| {
///     println!("initializing");
///     let mut m = HashMap::new();
///     m.insert(13, "Spica".to_string());
///     m.insert(74, "Hoyten".to_string());
///     m
/// });
///
/// fn main() {
///     println!("ready");
///     std::thread::spawn(|| {
///         println!("{:?}", HASHMAP.get(&13));
///     }).join().unwrap();
///     println!("{:?}", HASHMAP.get(&74));
///
///     // Prints:
///     //   ready
///     //   initializing
///     //   Some("Spica")
///     //   Some("Hoyten")
/// }
/// ```
pub struct LazyLock<T, F = fn() -> T, R = Spin> {
    cell: Once<T, R>,
    init: Cell<Option<F>>,
}

impl<T: fmt::Debug, F, R> fmt::Debug for LazyLock<T, F, R> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut d = f.debug_tuple("LazyLock");
        let d = if let Some(x) = self.cell.get() {
            d.field(&x)
        } else {
            d.field(&format_args!("<uninit>"))
        };
        d.finish()
    }
}

// We never create a `&F` from a `&LazyLock<T, F>` so it is fine
// to not impl `Sync` for `F`
// we do create a `&mut Option<F>` in `force`, but this is
// properly synchronized, so it only happens once
// so it also does not contribute to this impl.
unsafe impl<T, F: Send, R> Sync for LazyLock<T, F, R> where Once<T>: Sync {}
// auto-derived `Send` impl is OK.

impl<T, F, R> LazyLock<T, F, R> {
    /// Creates a new lazy value with the given initializing
    /// function.
    pub const fn new(f: F) -> Self {
        Self {
            cell: Once::new(),
            init: Cell::new(Some(f)),
        }
    }
    /// Retrieves a mutable pointer to the inner data.
    ///
    /// This is especially useful when interfacing with low level code or FFI where the caller
    /// explicitly knows that it has exclusive access to the inner data. Note that reading from
    /// this pointer is UB until initialized or directly written to.
    pub fn as_mut_ptr(&self) -> *mut T {
        self.cell.as_mut_ptr()
    }
}

impl<T, F: FnOnce() -> T, R: RelaxStrategy> LazyLock<T, F, R> {
    /// Forces the evaluation of this lazy value and
    /// returns a reference to result. This is equivalent
    /// to the `Deref` impl, but is explicit.
    ///
    /// # Examples
    ///
    /// ```
    /// use spin::LazyLock;
    ///
    /// let lazy = LazyLock::new(|| 92);
    ///
    /// assert_eq!(LazyLock::force(&lazy), &92);
    /// assert_eq!(&*lazy, &92);
    /// ```
    pub fn force(this: &Self) -> &T {
        this.cell.call_once(|| match this.init.take() {
            Some(f) => f(),
            None => panic!("LazyLock instance has previously been poisoned"),
        })
    }
}

impl<T, F: FnOnce() -> T, R: RelaxStrategy> Deref for LazyLock<T, F, R> {
    type Target = T;

    fn deref(&self) -> &T {
        Self::force(self)
    }
}

impl<T: Default, R> Default for LazyLock<T, fn() -> T, R> {
    /// Creates a new lazy value using `Default` as the initializing function.
    fn default() -> Self {
        Self::new(T::default)
    }
}
