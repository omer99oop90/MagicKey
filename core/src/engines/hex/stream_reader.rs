//! Virtualized Stream Reader and Chunking Engine for Hex viewing.

use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::Path;

use super::formatter::{format_row, HexRow};

/// A bounded chunk of formatted Hex data for display in a viewport.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HexChunk {
    /// Starting offset of this chunk in the file.
    pub start_offset: u64,
    /// Number of bytes read in this chunk.
    pub bytes_read: usize,
    /// Total size of the underlying file in bytes.
    pub total_file_size: u64,
    /// Formatted 16-byte rows.
    pub rows: Vec<HexRow>,
    /// Whether the end of the file was reached.
    pub is_eof: bool,
}

/// Incremental, virtualized Hex Engine reader.
pub struct HexEngine;

impl HexEngine {
    /// Reads a bounded chunk from an open seekable stream.
    /// Never loads more than `max_bytes` into memory.
    pub fn read_chunk<R: Read + Seek>(
        reader: &mut R,
        offset: u64,
        max_bytes: usize,
    ) -> io::Result<HexChunk> {
        let total_file_size = reader.seek(SeekFrom::End(0))?;

        // Empty file
        if total_file_size == 0 {
            return Ok(HexChunk {
                start_offset: 0,
                bytes_read: 0,
                total_file_size: 0,
                rows: Vec::new(),
                is_eof: true,
            });
        }

        // Seeking beyond EOF
        if offset >= total_file_size {
            return Ok(HexChunk {
                start_offset: offset,
                bytes_read: 0,
                total_file_size,
                rows: Vec::new(),
                is_eof: true,
            });
        }

        reader.seek(SeekFrom::Start(offset))?;

        let bytes_available = (total_file_size - offset) as usize;
        let bytes_to_read = max_bytes.min(bytes_available);

        let mut buffer = vec![0u8; bytes_to_read];
        reader.read_exact(&mut buffer)?;

        let mut rows = Vec::with_capacity(bytes_to_read.div_ceil(16));
        for (i, chunk) in buffer.chunks(16).enumerate() {
            let row_offset = offset + (i * 16) as u64;
            rows.push(format_row(row_offset, chunk));
        }

        let is_eof = (offset + bytes_to_read as u64) >= total_file_size;

        Ok(HexChunk {
            start_offset: offset,
            bytes_read: bytes_to_read,
            total_file_size,
            rows,
            is_eof,
        })
    }

    /// Reads a bounded chunk directly from a file path.
    pub fn read_chunk_from_path(
        path: &Path,
        offset: u64,
        max_bytes: usize,
    ) -> io::Result<HexChunk> {
        let mut file = File::open(path)?;
        Self::read_chunk(&mut file, offset, max_bytes)
    }
}
