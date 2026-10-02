#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find Sources -name '*.swift' ! -name main.swift | sort)
xcrun swiftc -parse-as-library -framework AppKit -framework SwiftUI -framework WebKit -framework Security "${sources[@]}" tests/CommandCode/main.swift -o build/command-code-checks
build/command-code-checks "$@"
