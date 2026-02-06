use std::fs::File;
use std::io::{self, Read};

fn main() -> io::Result<()> {
    let file_path = "/test-data/test.txt";

    for i in 1..=1000 {
        {
            let mut file = File::open(file_path)?;
            let mut buf = [0u8; 64];
            let _ = file.read(&mut buf)?;
        } // file is dropped here

        if i % 100 == 0 {
            println!("Completed {} iterations", i);
        }
    }

    println!("All 1000 iterations completed successfully!");
    Ok(())
}
