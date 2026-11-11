//! Magic Key Command-Line Utility.

use std::env;
use std::path::Path;
use std::process;

use magickey_core::engines::hex::HexEngine;
use magickey_core::file_detection::FileDetector;
use magickey_core::format_registry::FormatRegistry;

fn print_usage() {
    println!("Magic Key CLI — Universal File Opener Core Utility");
    println!("Usage:");
    println!("  magickey identify <file> [--json]       Detect format of a target file");
    println!("  magickey hex <file> [offset] [length]   Display virtualized hex chunk");
    println!("  magickey registry                       List all registered file formats");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_usage();
        process::exit(1);
    }

    match args[1].as_str() {
        "identify" => {
            if args.len() < 3 {
                eprintln!("Error: Missing file path for 'identify' command.");
                process::exit(1);
            }
            let file_path = Path::new(&args[2]);
            let json_mode = args.iter().any(|a| a == "--json");

            let detector = FileDetector::new();
            match detector.detect_file(file_path) {
                Ok(res) => {
                    if json_mode {
                        println!("{}", serde_json::to_string_pretty(&res).unwrap());
                    } else {
                        println!("==================================================");
                        println!(" Magic Key — Format Detection Result");
                        println!("==================================================");
                        println!("File Target     : {}", file_path.display());
                        println!("Detected Format : {}", res.display_name);
                        println!("Format ID       : {}", res.format_id);
                        println!("MIME Type       : {}", res.mime_type);
                        println!("Category        : {}", res.category);
                        println!("Confidence      : {}", res.confidence);
                        println!("Detection Method: {}", res.detection_method);
                        println!("Suggested Viewer: {}", res.suggested_viewer);
                        println!("Details         : {}", res.details);
                        println!("==================================================");
                    }
                }
                Err(e) => {
                    eprintln!(
                        "Error: Failed to inspect file '{}': {}",
                        file_path.display(),
                        e
                    );
                    process::exit(1);
                }
            }
        }
        "hex" => {
            if args.len() < 3 {
                eprintln!("Error: Missing file path for 'hex' command.");
                process::exit(1);
            }
            let file_path = Path::new(&args[2]);
            let offset: u64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(0);
            let length: usize = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(256);

            match HexEngine::read_chunk_from_path(file_path, offset, length) {
                Ok(chunk) => {
                    println!(
                        "--- Hex View: {} (Offset: {}, Read: {}/{} bytes, EOF: {}) ---",
                        file_path.display(),
                        chunk.start_offset,
                        chunk.bytes_read,
                        chunk.total_file_size,
                        chunk.is_eof
                    );
                    for row in &chunk.rows {
                        println!("{}", row.formatted_line);
                    }
                }
                Err(e) => {
                    eprintln!(
                        "Error: Failed to read hex chunk from '{}': {}",
                        file_path.display(),
                        e
                    );
                    process::exit(1);
                }
            }
        }
        "registry" => {
            let registry = FormatRegistry::default();
            let all = registry.list_all();
            println!(
                "================================================================================"
            );
            println!(" Magic Key — Format Registry (Total: {})", all.len());
            println!(
                "================================================================================"
            );
            println!(
                "{:<12} {:<30} {:<15} {:<15}",
                "ID", "Display Name", "Category", "Viewer Engine"
            );
            println!("{:-<12} {:-<30} {:-<15} {:-<15}", "", "", "", "");
            for def in all {
                println!(
                    "{:<12} {:<30} {:<15} {:<15}",
                    def.id,
                    def.display_name,
                    def.category.to_string(),
                    def.recommended_viewer.to_string()
                );
            }
            println!(
                "================================================================================"
            );
        }
        _ => {
            print_usage();
            process::exit(1);
        }
    }
}
