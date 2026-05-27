# Hank for Haxe

A Haxe implementation of the Hank language.

This repository provides a spec-compliant, environment-agnostic library (`hank`) for embedding the Hank interpreter into any Haxe-supported target (C++, JavaScript, Python, Java, C#, etc.).

## Features
- **Strict Spec Compliance**: Implements the v1.3.0-alpha1 specification.
- **Environment Agnostic**: The core library has zero dependencies on `sys` or target-specific APIs.
- **Universal Parity**: Bit-perfect execution parity with Go, Rust, TS, and Dart implementations.
- **Modular StdLib**: Full parity with official standard library specifications.

## Installation

```bash
haxelib git hank https://github.com/Igazine/hank-haxe.git
```

## Example Demo

An example CLI demo is included in `examples/demo`. To run the conformance tests:

1. **Initialize Submodules**:
   ```bash
   git submodule update --init --recursive
   ```
2. **Run Demo**:
   ```bash
   cd examples/demo
   haxe build.hxml
   ```

## Project Links

- **Hank Core Repo**: [Igazine/hank](https://github.com/Igazine/hank)
- **Official Documentation**: [https://igazine.github.io/hank/](https://igazine.github.io/hank/)

## License

This project is licensed under the MIT License.
