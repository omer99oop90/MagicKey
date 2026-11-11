//! Hex viewing engine module.

pub mod formatter;
pub mod stream_reader;

pub use formatter::{format_row, HexRow};
pub use stream_reader::{HexChunk, HexEngine};
