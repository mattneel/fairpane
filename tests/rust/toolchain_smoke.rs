use std::panic;
use std::thread;

fn main() {
    let joined = thread::spawn(|| 6 * 7).join().expect("the smoke thread panicked");
    let caught = panic::catch_unwind(|| panic!("fairpane toolchain smoke panic"));
    assert!(caught.is_err());
    println!("fairpane rust toolchain smoke: thread {joined}, unwind caught");
}
