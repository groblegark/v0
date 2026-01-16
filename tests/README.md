# v0 Test Suite

This directory contains the test suite for v0, using [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Running Tests

```bash
# Run all unit tests
make test

# Run tests with verbose output
make test-verbose

# Run a specific test file
make test-file FILE=tests/unit/v0-common.bats

# Run integration tests
make test-integration

# Run all tests (unit + integration)
make test-all

# Run linting and tests
make check
```

## Test Isolation Requirements

All tests **MUST** follow these isolation rules:

### 1. Set Test Mode
Tests must enable test mode to suppress notifications:
```bash
export V0_TEST_MODE=1
export V0_NO_NOTIFICATIONS=1
```

### 2. Use Isolated Temp Directories
Never write to the project working directory. Always use `$TEST_TEMP_DIR`:
```bash
# WRONG - touches real directory
setup() {
  touch .v0/test-file
}

# RIGHT - uses isolated temp directory
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  cd "$TEST_TEMP_DIR"
  mkdir -p .v0
  touch .v0/test-file
}
```

### 3. Clean Up in Teardown
Always clean up temporary files:
```bash
teardown() {
  if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}
```

### 4. Clear Environment Variables
Prevent leakage from parent environment:
```bash
setup() {
  unset V0_ROOT
  unset PROJECT
  unset V0_STATE_DIR
  # ... other v0 variables
}
```

## Directory Structure

```
tests/
├── unit/               # Unit tests (one per script/module)
│   ├── v0-cancel.bats
│   ├── v0-common.bats
│   ├── v0-decompose.bats
│   └── ...
├── integration/        # Integration tests (workflow tests)
├── fixtures/           # Test data files
│   ├── configs/        # Sample .v0.rc configurations
│   ├── states/         # Sample state.json files
│   └── queues/         # Sample queue.json files
├── helpers/            # Test utilities
│   ├── test_helper.bash  # Common setup/teardown
│   ├── mocks.bash        # Mock functions
│   └── mock-bin/         # Mock executable scripts
└── bats/               # BATS framework (auto-installed)
```

## Writing New Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

load '../helpers/test_helper'

setup() {
  # Create temp directory
  TEST_TEMP_DIR="$(mktemp -d)"
  export TEST_TEMP_DIR

  # Set up mock home
  export REAL_HOME="$HOME"
  export HOME="$TEST_TEMP_DIR/home"
  mkdir -p "$HOME/.local/state/v0"

  # Enable test mode
  export V0_TEST_MODE=1
  export V0_NO_NOTIFICATIONS=1

  # Clear inherited variables
  unset V0_ROOT
  unset PROJECT

  # Create test project
  cd "$TEST_TEMP_DIR"
}

teardown() {
  export HOME="$REAL_HOME"
  rm -rf "$TEST_TEMP_DIR"
}

@test "description of what is being tested" {
  run some_command
  assert_success
  assert_output --partial "expected output"
}
```

### Using Test Helpers

The `test_helper.bash` provides common utilities:

```bash
# Source a library
source_lib "v0-common.sh"

# Create a .v0.rc file
create_v0rc "project-name" "prefix"

# Create operation state
create_operation_state "op-name" '{"status": "init"}'

# Create queue file
create_queue_file '{"entries": []}'

# Use a fixture file
use_fixture "queues/sample.json" "queue.json"

# Assert file exists
assert_file_exists "$path"

# Assert JSON field value
assert_json_field "file.json" ".status" "completed"

# Initialize mock git repo
init_mock_git_repo "$path"
```

### Mocking External Commands

Use mock-bin scripts for external commands:

```bash
# In setup:
export PATH="$TESTS_DIR/helpers/mock-bin:$PATH"

# Create custom mock in test:
cat > "$TEST_TEMP_DIR/mock-bin/git" <<'EOF'
#!/bin/bash
echo "mock git: $*"
exit 0
EOF
chmod +x "$TEST_TEMP_DIR/mock-bin/git"
```

### Test Isolation Verification

Use helper functions to verify test isolation:

```bash
@test "verify we're in isolated environment" {
  assert_test_isolation
  assert_test_env
}
```

## Test Categories

### Unit Tests
- Test individual functions and scripts in isolation
- Mock all external dependencies
- Located in `tests/unit/`

### Integration Tests
- Test complete workflows with mocked externals
- Use realistic scenarios
- Located in `tests/integration/`

## Fixtures

Place test data in `tests/fixtures/`:

- `configs/` - Sample configuration files
- `states/` - Sample state.json for operations
- `queues/` - Sample queue.json files

Use fixtures in tests:
```bash
use_fixture "states/completed.json" "state.json"
```

## Linting

Run ShellCheck on all scripts:

```bash
# Lint source scripts
make lint

# Lint test files
make lint-tests
```

## Best Practices

1. **One assertion per test** when possible
2. **Descriptive test names** that explain the behavior
3. **Test both success and failure paths**
4. **Use `# bats test_tags=todo:implement`** for pending tests
5. **Keep tests fast** - mock slow operations
6. **Avoid testing implementation details** - focus on behavior
