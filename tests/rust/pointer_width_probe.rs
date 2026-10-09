//! A metadata build of this library for a target checks two facts.
//! The locked toolchain holds that target's standard library.
//! The compiler evaluates constant assertions without code generation.
//! The library compiles only for a target whose pointers are 4 bytes wide.

#![no_std]

const _: () = assert!(
    core::mem::size_of::<usize>() == 4,
    "the probe needs 4-byte pointers"
);
