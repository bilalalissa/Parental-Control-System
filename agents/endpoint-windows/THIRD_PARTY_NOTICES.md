# Windows endpoint third-party notices

Stage 07 pins all direct NuGet dependencies in committed lock files.

- BouncyCastle.Cryptography 2.7.0 — MIT license — Ed25519 protocol interoperability. Source commit recorded by the package: `4007498b13582d90ee1eda5d9920c324428b98b3`.
- Microsoft .NET 8 runtime, WPF, MSTest, and `System.*` packages — MIT license — Windows runtime, UI, tests, DPAPI, service, and named-pipe ACL APIs.
- WiX Toolset SDK 5.0.2 — Microsoft Reciprocal License (MS-RL) — MSI construction only. Source commit recorded by the package: `aa65968c419420d32e3e1b647aea0082f5ca5b78`.

The installer is produced by WiX; WiX is not installed as a runtime component. Package repositories and content hashes are recorded in `packages.lock.json` files.
