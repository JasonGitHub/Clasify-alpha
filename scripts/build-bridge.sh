#!/bin/bash
# Builds LibrespotBridge as one universal (arm64 + x86_64) static library for the app.
# Output: LibrespotBridge/target/universal/liblibrespot_bridge.a
# Run it before you build Clasify.xcodeproj. CI runs it too.
set -euo pipefail
cd "$(dirname "$0")/../LibrespotBridge"
export MACOSX_DEPLOYMENT_TARGET=14.0
targets=(aarch64-apple-darwin x86_64-apple-darwin)
rustup target add "${targets[@]}"
libs=()
for target in "${targets[@]}"; do
    cargo build --locked --release --lib --target "$target"
    libs+=("target/$target/release/liblibrespot_bridge.a")
done
mkdir -p target/universal
lipo -create "${libs[@]}" -output target/universal/liblibrespot_bridge.a
lipo -info target/universal/liblibrespot_bridge.a
