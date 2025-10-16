#!/usr/bin/env bash

# Standalone test for release_app function
# This test doesn't require the full buildpack test runner

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Source the functions we're testing
BUILDPACK_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BUILDPACK_HOME}/lib/misc_funcs.sh" || true
source "${BUILDPACK_HOME}/lib/app_funcs.sh" || true

# Setup test environment
setup_test() {
  # Create a temporary directory for the test
  export TEST_TEMP_DIR=$(mktemp -d)
  export build_path="${TEST_TEMP_DIR}/build"
  mkdir -p "${build_path}"

  # Create a mock bin directory for stubbed executables
  export MOCK_BIN="${TEST_TEMP_DIR}/mock_bin"
  mkdir -p "${MOCK_BIN}"

  # Add mock bin to PATH so our stubs are found first
  export PATH="${MOCK_BIN}:${PATH}"

  # Create a stub mix executable that records what it was called with
  cat > "${MOCK_BIN}/mix" << 'EOF'
#!/bin/bash
# Record the arguments passed to mix with argument count
# Format: [ARG_COUNT] arg1 arg2 arg3 ...
echo "[$(($# - 1))] $@" >> "${MOCK_BIN}/mix_calls.log"
# Exit successfully by default
exit 0
EOF
  chmod +x "${MOCK_BIN}/mix"

  # Initialize the call log
  > "${MOCK_BIN}/mix_calls.log"

  # Set default values
  export release=false
  unset release_flags
}

teardown_test() {
  # Clean up
  rm -rf "${TEST_TEMP_DIR}"
  unset release
  unset release_flags
}

# Test assertion helpers
assert_true() {
  local condition=$1
  local message=$2

  if eval "$condition"; then
    echo -e "${GREEN}✓${NC} $message"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} $message"
    ((TESTS_FAILED++))
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3

  # Use case statement for pattern matching to avoid grep flag issues on macOS
  case "$haystack" in
    *"$needle"*)
      echo -e "${GREEN}✓${NC} $message"
      ((TESTS_PASSED++))
      ;;
    *)
      echo -e "${RED}✗${NC} $message"
      echo "  Expected to find: $needle"
      echo "  In: $haystack"
      ((TESTS_FAILED++))
      ;;
  esac
}

# Test: release_app does nothing when release=false
test_release_app_disabled() {
  setup_test

  release=false
  release_app

  # Verify mix was not called
  assert_true "[ ! -s ${MOCK_BIN}/mix_calls.log ]" "release_app: does nothing when release=false"

  teardown_test
}

# Test: release_app uses default --overwrite flag when no release_flags set
test_release_app_default_flag() {
  setup_test

  release=true
  unset release_flags
  release_app

  # Verify mix was called with --overwrite
  assert_true "[ -s ${MOCK_BIN}/mix_calls.log ]" "release_app: calls mix when release=true"
  assert_contains "$(cat ${MOCK_BIN}/mix_calls.log)" "--overwrite" \
    "release_app: uses default --overwrite flag when no release_flags set"

  teardown_test
}

# Test: release_app uses release_flags when set as array
test_release_app_with_flags_array() {
  setup_test

  release=true
  release_flags=(--no-compile --no-deps-check --overwrite)
  release_app

  # Verify mix was called with all flags
  assert_true "[ -s ${MOCK_BIN}/mix_calls.log ]" "release_app: calls mix with flags array"
  local calls=$(cat ${MOCK_BIN}/mix_calls.log)
  assert_contains "$calls" "--no-compile" "release_app: passes --no-compile flag"
  assert_contains "$calls" "--no-deps-check" "release_app: passes --no-deps-check flag"
  assert_contains "$calls" "--overwrite" "release_app: passes --overwrite flag"

  teardown_test
}

# Test: release_app with single flag in array
test_release_app_with_single_flag() {
  setup_test

  release=true
  release_flags=(--no-compile)
  release_app

  # Verify mix was called with the flag
  assert_true "[ -s ${MOCK_BIN}/mix_calls.log ]" "release_app: calls mix with single flag"
  assert_contains "$(cat ${MOCK_BIN}/mix_calls.log)" "--no-compile" \
    "release_app: passes single flag correctly"

  teardown_test
}

# Test: release_app with empty array should use default
test_release_app_with_empty_array() {
  setup_test

  release=true
  release_flags=()
  release_app

  # Verify mix was called with --overwrite (default)
  assert_true "[ -s ${MOCK_BIN}/mix_calls.log ]" "release_app: calls mix with empty array"
  assert_contains "$(cat ${MOCK_BIN}/mix_calls.log)" "--overwrite" \
    "release_app: uses default --overwrite for empty array"

  teardown_test
}

# Test: release_app with flags containing spaces/special values
# This demonstrates why we need [@] instead of [*] for command execution
test_release_app_with_flag_values() {
  setup_test

  release=true
  # Simulate a flag with a value that contains spaces
  release_flags=(--config "path with spaces" --no-compile)
  release_app

  # Verify mix was called with all flags as separate arguments
  assert_true "[ -s ${MOCK_BIN}/mix_calls.log ]" "release_app: calls mix with flag values"
  local calls=$(cat ${MOCK_BIN}/mix_calls.log)

  assert_contains "$calls" "[3]" "release_app: passes flags as separate arguments (not concatenated)"
  assert_contains "$calls" "--config" "release_app: passes --config flag"
  assert_contains "$calls" "path with spaces" "release_app: preserves flag value with spaces"
  assert_contains "$calls" "--no-compile" "release_app: passes --no-compile flag"

  teardown_test
}

# Run all tests
echo -e "${YELLOW}Running release_app tests...${NC}\n"

test_release_app_disabled || true
test_release_app_default_flag || true
test_release_app_with_flags_array || true
test_release_app_with_single_flag || true
test_release_app_with_empty_array || true
test_release_app_with_flag_values || true

# Print summary
echo ""
echo -e "${YELLOW}Test Summary:${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}Failed: 0${NC}"
  exit 0
fi

