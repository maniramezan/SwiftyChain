# Contributing

## Prerequisites

Use Swift 6.3 or newer:

```bash
swift --version
```

## Build

```bash
swift build
```

## Test

```bash
swift test
swift test --enable-code-coverage
```

## Format

```bash
swift-format lint --recursive Sources Tests
swift-format format --recursive --in-place Sources Tests
```

## Pull Requests

Ensure build, tests, formatting, and documentation updates are complete before opening a PR.
