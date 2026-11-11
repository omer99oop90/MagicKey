//! Automated tests for Hex Viewer Formatter and Virtualized Stream Reader.

use magickey_core::engines::hex::{format_row, HexEngine};
use std::io::Cursor;

#[test]
fn test_hex_row_formatting_canonical_16_bytes() {
    let data = b"Hello, MagicKey!";
    assert_eq!(data.len(), 16);

    let row = format_row(0x00000000, data);
    assert_eq!(row.offset, 0);
    assert_eq!(row.byte_count, 16);

    // Verify left and right 8-byte hex grouping
    let expected_hex = "48 65 6C 6C 6F 2C 20 4D  61 67 69 63 4B 65 79 21";
    assert_eq!(row.hex_dump, expected_hex);
    assert_eq!(row.ascii_dump, "|Hello, MagicKey!|");

    let expected_line =
        "00000000  48 65 6C 6C 6F 2C 20 4D  61 67 69 63 4B 65 79 21  |Hello, MagicKey!|";
    assert_eq!(row.formatted_line, expected_line);
}

#[test]
fn test_hex_row_formatting_partial_row() {
    // 5 bytes (partial row)
    let data = [0x50, 0x4B, 0x03, 0x04, 0x14];
    let row = format_row(0x00000020, &data);

    assert_eq!(row.offset, 0x20);
    assert_eq!(row.byte_count, 5);

    // Padding spaces must align the ASCII column across all 48 characters of the hex grid
    let expected_hex = "50 4B 03 04 14                                  ";
    assert_eq!(row.hex_dump, expected_hex);
    assert_eq!(row.ascii_dump, "|PK...|");

    let expected_line = "00000020  50 4B 03 04 14                                    |PK...|";
    assert_eq!(row.formatted_line, expected_line);
}

#[test]
fn test_hex_row_non_printable_ascii() {
    // Control bytes < 32 and > 126
    let data = [
        0x00, 0x01, 0x02, 0x09, 0x0A, 0x1F, 0x20, 0x41, 0x7E, 0x7F, 0x80, 0xFF,
    ];
    let row = format_row(0x100, &data);

    // ' ' is 0x20, 'A' is 0x41, '~' is 0x7E -> printable
    // 0x00-0x1F, 0x7F, 0x80, 0xFF -> '.'
    assert_eq!(row.ascii_dump, "|...... A~...|");
}

#[test]
fn test_hex_engine_empty_stream() {
    let mut cursor = Cursor::new(Vec::<u8>::new());
    let chunk = HexEngine::read_chunk(&mut cursor, 0, 256).expect("Empty read should succeed");

    assert_eq!(chunk.start_offset, 0);
    assert_eq!(chunk.bytes_read, 0);
    assert_eq!(chunk.total_file_size, 0);
    assert!(chunk.rows.is_empty());
    assert!(chunk.is_eof);
}

#[test]
fn test_hex_engine_bounded_chunk_reading() {
    // 64 bytes test data
    let mut data = Vec::with_capacity(64);
    for i in 0..64u8 {
        data.push(i);
    }
    let mut cursor = Cursor::new(data);

    // Read first 32 bytes (2 rows of 16)
    let chunk1 = HexEngine::read_chunk(&mut cursor, 0, 32).unwrap();
    assert_eq!(chunk1.start_offset, 0);
    assert_eq!(chunk1.bytes_read, 32);
    assert_eq!(chunk1.total_file_size, 64);
    assert_eq!(chunk1.rows.len(), 2);
    assert!(!chunk1.is_eof);
    assert_eq!(chunk1.rows[0].offset, 0x00);
    assert_eq!(chunk1.rows[1].offset, 0x10);

    // Read next 32 bytes from offset 32 to end
    let chunk2 = HexEngine::read_chunk(&mut cursor, 32, 32).unwrap();
    assert_eq!(chunk2.start_offset, 32);
    assert_eq!(chunk2.bytes_read, 32);
    assert_eq!(chunk2.rows.len(), 2);
    assert!(chunk2.is_eof);
    assert_eq!(chunk2.rows[0].offset, 0x20);
    assert_eq!(chunk2.rows[1].offset, 0x30);
}

#[test]
fn test_hex_engine_seeking_past_eof() {
    let mut cursor = Cursor::new(vec![1, 2, 3, 4]);
    let chunk = HexEngine::read_chunk(&mut cursor, 100, 32).unwrap();

    assert_eq!(chunk.start_offset, 100);
    assert_eq!(chunk.bytes_read, 0);
    assert_eq!(chunk.total_file_size, 4);
    assert!(chunk.rows.is_empty());
    assert!(chunk.is_eof);
}

#[test]
fn test_hex_engine_large_file_simulation() {
    // Simulated large file: 16 MB (16,777,216 bytes)
    // Using a sparse seekable cursor without allocating 16 MB in memory
    struct SparseReader {
        size: u64,
        pos: u64,
    }

    impl std::io::Read for SparseReader {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            if self.pos >= self.size {
                return Ok(0);
            }
            let to_read = buf.len().min((self.size - self.pos) as usize);
            for (i, b) in buf[..to_read].iter_mut().enumerate() {
                *b = ((self.pos + i as u64) % 256) as u8;
            }
            self.pos += to_read as u64;
            Ok(to_read)
        }
    }

    impl std::io::Seek for SparseReader {
        fn seek(&mut self, pos: std::io::SeekFrom) -> std::io::Result<u64> {
            match pos {
                std::io::SeekFrom::Start(p) => self.pos = p.min(self.size),
                std::io::SeekFrom::End(p) => {
                    self.pos = if p >= 0 {
                        self.size
                    } else {
                        (self.size as i64 + p).max(0) as u64
                    };
                }
                std::io::SeekFrom::Current(p) => {
                    self.pos = (self.pos as i64 + p).clamp(0, self.size as i64) as u64;
                }
            }
            Ok(self.pos)
        }
    }

    let mut sparse = SparseReader {
        size: 16 * 1024 * 1024, // 16 MB
        pos: 0,
    };

    // Read 64 bytes at offset 10,000,000 (10 MB in)
    let chunk = HexEngine::read_chunk(&mut sparse, 10_000_000, 64).unwrap();
    assert_eq!(chunk.start_offset, 10_000_000);
    assert_eq!(chunk.bytes_read, 64);
    assert_eq!(chunk.total_file_size, 16 * 1024 * 1024);
    assert_eq!(chunk.rows.len(), 4);
    assert!(!chunk.is_eof);
    assert_eq!(chunk.rows[0].offset, 10_000_000);
    assert_eq!(chunk.rows[1].offset, 10_000_016);
    assert_eq!(chunk.rows[2].offset, 10_000_032);
    assert_eq!(chunk.rows[3].offset, 10_000_048);
}
