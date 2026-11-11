//! Format Registry module.

pub mod model;
pub mod registry;

pub use model::{FileCategory, FormatDefinition, SupportStatus, ViewerEngine};
pub use registry::FormatRegistry;
