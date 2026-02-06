use std::fs::File;
use std::io::{self, Read};

fn main() -> io::Result<()> {
    println!("\nStarting WASI Preview 1 file I/O test");

    let file_path = "/test-data/test.txt";

    for i in 1..=1000 {
        // Use a scope to ensure the file is closed before the next iteration
        {
            // Open the file
            let mut file = File::open(file_path)?;

            // Read some content to verify file operations work
            let mut _buffer = [0u8; 64];
            let _ = file.read(&mut _buffer)?;

            // File is explicitly dropped here at the end of the scope
        }

        // Print progress every 100 iterations
        if i % 100 == 0 {
            println!("Completed {} iterations", i);
        }
    }

    println!("All 1000 iterations completed successfully!\n");

    Ok(())
}
