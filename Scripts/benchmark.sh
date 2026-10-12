#!/bin/bash
#
# PlainX Editor - developer benchmarks (launch, memory, large files, search).
#
#   Scripts/benchmark.sh [--quick]
#
# Generates deterministic fixtures, builds Release, and measures:
#   * launch time (UI visible, usable editor)
#   * blank-window RSS
#   * 1 MB / 20 MB / 100 MB file open time and RSS
#   * 1 GB Large File Mode index time and RSS
#   * streaming search throughput on the 1 GB fixture
#
# Results are printed to stdout; paste them into docs/performance.md.
# This is a developer tool: no user data is collected or transmitted.
#
set -euo pipefail

cd "$(dirname "$0")/.."

QUICK=0
if [[ "${1:-}" == "--quick" ]]; then
  QUICK=1
fi

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/PlainXBuild}"
FIXTURES="${FIXTURES:-$DERIVED_DATA/benchmark-fixtures}"
APP="$DERIVED_DATA/Build/Products/Release/PlainX.app/Contents/MacOS/PlainX"

mkdir -p "$FIXTURES"

# The 1 GB fixture needs about 1.1 GB of free space; skip it gracefully when
# the disk is tight instead of failing mid-write.
AVAILABLE_KB=$(df -k "$FIXTURES" | awk 'NR==2 {print $4}')
REQUIRED_KB=1300000
if [[ "$AVAILABLE_KB" -lt "$REQUIRED_KB" && "$QUICK" == "0" ]]; then
  echo "warning: only $((AVAILABLE_KB / 1024)) MB free; skipping the 1 GB fixture."
  QUICK=1
fi

echo "==> Fixtures in $FIXTURES"
python3 - "$FIXTURES" "$QUICK" <<'PYEOF'
import os, sys, random
fixtures, quick = sys.argv[1], sys.argv[2] == "1"
random.seed(42)

def make_text(path, target_bytes, line_factory):
    if os.path.exists(path) and os.path.getsize(path) >= target_bytes * 0.95:
        return
    with open(path, "w") as handle:
        written = 0
        index = 0
        while written < target_bytes:
            line = line_factory(index)
            handle.write(line)
            written += len(line)
            index += 1

def plain_line(i):
    return f"line {i} with some ordinary payload text abcdefghijklmnopqrstuvwxyz\n"

def log_line(i):
    level = ["INFO", "INFO", "INFO", "WARN", "DEBUG", "ERROR"][i % 6]
    return f"2026-01-01T00:00:00.{i%1000:03d}Z {level} request_id={i} message payload data status=200\n"

make_text(os.path.join(fixtures, "1mb.txt"), 1 * 1024 * 1024, plain_line)
make_text(os.path.join(fixtures, "20mb.log"), 20 * 1024 * 1024, log_line)
make_text(os.path.join(fixtures, "100mb.log"), 100 * 1024 * 1024, log_line)
if not quick:
    make_text(os.path.join(fixtures, "1024mb.log"), 1024 * 1024 * 1024, log_line)
print("fixtures ready")
PYEOF

echo
echo "==> Building Release (native architecture)"
if ! xcodebuild -project PlainX.xcodeproj -scheme PlainX -configuration Release \
  -derivedDataPath "$DERIVED_DATA" build > "$DERIVED_DATA/benchmark-build.log" 2>&1; then
  echo "error: Release build failed; see $DERIVED_DATA/benchmark-build.log" >&2
  exit 1
fi

run_benchmark() {
  local label="$1"; local file="$2"; local seconds="$3"
  echo
  echo "==> $label"
  local env_args=(PLAINX_BENCHMARK=1 PLAINX_BENCHMARK_EXIT_AFTER="$seconds")
  if [[ -n "$file" ]]; then
    env_args+=(PLAINX_BENCHMARK_OPEN_FILE="$file")
  fi
  env "${env_args[@]}" /usr/bin/time -l "$APP" \
    > "$DERIVED_DATA/benchmark-stdout.log" 2> "$DERIVED_DATA/benchmark-time.log" || true
  grep "\[benchmark\]" "$DERIVED_DATA/benchmark-stdout.log" || echo "  (no benchmark output; app may have failed to launch)"
  grep -E "maximum resident set size" "$DERIVED_DATA/benchmark-time.log" | awk '{printf "  max_rss_bytes=%s\n", $1}' || true
}

run_benchmark "Cold launch (blank window)" "" 3
run_benchmark "Open 1 MB text" "$FIXTURES/1mb.txt" 6
run_benchmark "Open 20 MB log (regular editor)" "$FIXTURES/20mb.log" 8
run_benchmark "Open 100 MB log (Large File Mode by default)" "$FIXTURES/100mb.log" 20
if [[ "$QUICK" == "0" ]]; then
  run_benchmark "Open 1 GB log (Large File Mode)" "$FIXTURES/1024mb.log" 45
fi

echo
echo "==> Search throughput (1 GB fixture, via stress test)"
if [[ "$QUICK" == "0" ]]; then
  cat > "$DERIVED_DATA/stress-config.json" <<EOF
{ "file": "$FIXTURES/1024mb.log" }
EOF
  xcodebuild -project PlainX.xcodeproj -scheme PlainX -configuration Release \
    -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' \
    test -only-testing:PlainXTests/LargeFileStressTests \
    ENABLE_TESTABILITY=YES \
    > "$DERIVED_DATA/benchmark-stress.log" 2>&1 || true
  rm -f "$DERIVED_DATA/stress-config.json"
  grep -E "\[stress\]" "$DERIVED_DATA/benchmark-stress.log" || true
else
  echo "(skipped in --quick mode)"
fi

echo
echo "Done. Record results in docs/performance.md."
