//! r550 Rust native parity contract.
//!
//! Documentation-as-code for the C-source parity rules that must not regress.
//! This is not a synthetic implementation module and must not be used to fake
//! missing helper coverage.

pub const R550_PARITY_MARKER: &str = "rust-native-v27-binary-version-marker-r550";
pub const R550_EMPTY_STUBS_FORBIDDEN: bool = true;
pub const R550_STRICT_SMOKE_DEFAULT: bool = true;
pub const R550_RUNTIME_REPLACEMENT_APPROVED: bool = false;

pub const R550_REAL_FIXES: &[&str] = &[
    "r550 keeps r544/v25 CLI/schema/capability behavior and removes only source-level unused Rust helpers",
    "r548/r547/r546/r545 tools and Dex security fixes remain retained in the full bundle",
    "r544 speedscan root binding Android compile fix remains retained",
    "r543 release size profile remains retained: opt-level=z, LTO, codegen-units=1, panic=abort, strip=symbols plus llvm-strip in build scripts",
    "r541/r539/r538/r537 parity fixes remain retained",
    "tools.sh runtime behavior is unchanged except hard-disabled metadata download dead branches are removed",
];
