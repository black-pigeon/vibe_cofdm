# Third-party matrix provenance

Only the `H_648_1_2` numeric base matrix was adapted from:

- Project: tavildar/LDPC
- URL: https://github.com/tavildar/LDPC
- File: LdpcC/WiFiLDPC.h
- Retrieved: 2026-09-23
- Repository HEAD observed: `05ee7f4af36ed5dacf52861315af68b8a17e71e0` (the initial download used master).
- SHA-256 of retrieved full header: `b2a6e22dce37ab57c883503f7078feb16fcc8e5dc029efc7bc596c10de196934`.
- Matrix: 12 x 24, Z=27, n=648, k=324; adapted into `+cofdm/ldpc_code.m`.

Encoder and decoder implementations in this directory are newly written. The numeric matrix is described by the upstream as a Wi-Fi LDPC matrix; use of it does not make our frame or receiver IEEE 802.11 compliant. Before interoperability work, cross-check against the exact standard edition and external reference vectors. Current tests check syndrome, parity rank and an independent GF(2) encoder, not a Wi-Fi conformance suite.

The license text retrieved alongside the matrix is reproduced verbatim below:

```text
MIT License

Copyright (c) 2026 Saurabh Tavildar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
