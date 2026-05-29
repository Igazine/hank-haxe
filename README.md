# Hank for Haxe

Hank is a purely symbolic, instruction-oriented embeddable language designed to bring secure, dynamic automation to any host application. Built on a strict air-gapped execution model, Hank has zero built-in I/O, guaranteeing that scripts cannot access the filesystem, network, or OS without explicit delegation. This makes it the perfect predictable environment for game scripting, microservice orchestration, and user-facing plugin systems. With a highly readable, keyword-less syntax and universal cross-platform parity, Hank seamlessly bridges the gap between static configuration files and complex general-purpose programming.

This repository provides the official Haxe implementation of the Hank language. It is a spec-compliant, environment-agnostic library (`hank`) for embedding the Hank interpreter into any Haxe-supported target (C++, JavaScript, Python, Java, C#, etc.).

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
