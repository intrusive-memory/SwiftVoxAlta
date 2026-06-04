# SwiftVoxAlta / diga CLI Makefile
# Build and install the diga CLI with full Metal shader support

SCHEME = diga
TEST_SCHEME = SwiftVoxAlta-Package
BINARY = diga
BIN_DIR = ./bin
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build release install clean test test-unit test-integration test-leak-probe setup-voices resolve lint help codesign-cli

all: install

# Resolve all SPM package dependencies via xcodebuild
resolve:
	xcodebuild -resolvePackageDependencies -scheme $(SCHEME) -destination '$(DESTINATION)'
	@echo "Package dependencies resolved."

# Development build (xcodebuild debug, no copy)
build: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build

# Release build with xcodebuild + copy to bin
release: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -configuration Release build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(find $(DERIVED_DATA)/SwiftVoxAlta-*/Build/Products/Release -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -n "$$PRODUCT_DIR" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		if [ -d "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" ]; then \
			rm -rf $(BIN_DIR)/mlx-swift_Cmlx.bundle; \
			cp -R "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" $(BIN_DIR)/; \
			echo "Installed $(BINARY) + Metal bundle to $(BIN_DIR)/ (Release)"; \
		else \
			echo "Warning: Metal bundle not found, binary may not work"; \
			echo "Installed $(BINARY) to $(BIN_DIR)/ (Release, no Metal bundle)"; \
		fi; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Debug build with xcodebuild + copy to bin (default)
install: resolve
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build
	@mkdir -p $(BIN_DIR)
	@PRODUCT_DIR=$$(find $(DERIVED_DATA)/SwiftVoxAlta-*/Build/Products/Debug -name $(BINARY) -type f 2>/dev/null | head -1 | xargs dirname); \
	if [ -n "$$PRODUCT_DIR" ]; then \
		cp "$$PRODUCT_DIR/$(BINARY)" $(BIN_DIR)/; \
		if [ -d "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" ]; then \
			rm -rf $(BIN_DIR)/mlx-swift_Cmlx.bundle; \
			cp -R "$$PRODUCT_DIR/mlx-swift_Cmlx.bundle" $(BIN_DIR)/; \
			echo "Installed $(BINARY) + Metal bundle to $(BIN_DIR)/ (Debug)"; \
		else \
			echo "Warning: Metal bundle not found, binary may not work"; \
			echo "Installed $(BINARY) to $(BIN_DIR)/ (Debug, no Metal bundle)"; \
		fi; \
	else \
		echo "Error: Could not find $(BINARY) in DerivedData"; \
		exit 1; \
	fi

# Fast unit tests (library + audio generation, no binary required)
# Note: SwiftVoxAltaTests skipped on CI due to Metal compiler limitations
test-unit:
	@echo "Running unit tests..."
ifdef GITHUB_ACTIONS
	@echo "CI detected: Skipping SwiftVoxAltaTests (Metal incompatible) and DigaBinaryIntegrationTests (no binary/model on runners)"
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination '$(DESTINATION)' \
	  -only-testing:DigaTests \
	  -skip-testing:DigaTests/DigaBinaryIntegrationTests
else
	@echo "Local run: Running all tests (DigaTests + SwiftVoxAltaTests, excluding binary integration)"
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination '$(DESTINATION)' \
	  -skip-testing:DigaTests/DigaBinaryIntegrationTests
endif

# Integration tests (requires binary + cached voices)
# Runs DigaBinaryIntegrationTests against the freshly installed ./bin/diga.
# Skipped on CI by default since the Qwen3-TTS model is not cached on runners.
test-integration: install
ifdef GITHUB_ACTIONS
	@echo "CI detected: Skipping binary integration tests (no cached TTS model on runners)"
else
	@echo "Running binary integration tests against ./bin/diga..."
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination '$(DESTINATION)' \
	  -only-testing:DigaTests/DigaBinaryIntegrationTests
endif

# Empirical RSS-based leak probe (3-cycle load/unload of 1.7B Base model)
# Skipped by default; enable with VOXALTA_RUN_LEAK_PROBE=1 (this target sets it).
# Loads ~8.8GB into RAM; takes ~10s with warm MLX cache, ~2-3min cold.
# Writes LEAK_PROBE_RESULT.md and LEAK_PROBE_XCODEBUILD.log to project root.
# Note: xcodebuild 26+ strips parent env vars from the test runner process;
# a sentinel file at /tmp/voxalta_run_leak_probe is used to gate the probe.
test-leak-probe:
	@echo "Running preflight leak probe (VOXALTA_RUN_LEAK_PROBE=1)..."
	@touch /tmp/voxalta_run_leak_probe
	VOXALTA_RUN_LEAK_PROBE=1 xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination '$(DESTINATION)' \
	  -only-testing:SwiftVoxAltaTests/PreflightLeakProbeTests \
	  2>&1 | tee LEAK_PROBE_XCODEBUILD.log; \
	  EXIT_CODE=$$?; \
	  rm -f /tmp/voxalta_run_leak_probe; \
	  exit $$EXIT_CODE
	@echo "---"
	@echo "Verdict:"
	@grep -E '^Verdict:' LEAK_PROBE_RESULT.md || echo "(no verdict found — probe may have failed)"

# All tests (unit + integration)
test: test-unit test-integration
	@echo "All tests complete!"

# One-time setup for local development (downloads CustomVoice model)
# The destination directory is chosen by SwiftAcervo at runtime; see
# `Acervo.sharedModelsDirectory` for the resolved path.
setup-voices: install
	@echo "Downloading CustomVoice model (~3.4GB, first run only)..."
	@./bin/diga -v ryan -o /tmp/warmup.wav "test" && rm -f /tmp/warmup.wav
	@echo "✓ CustomVoice model cached (destination managed by SwiftAcervo)."
	@echo "  You can now run 'make test' or 'make test-integration'."

# Format Swift source files
lint:
	swift format -i -r .

# Clean build artifacts
clean:
	xcodebuild clean -scheme $(SCHEME) -destination '$(DESTINATION)' 2>/dev/null || true
	rm -rf $(BIN_DIR)
	rm -rf $(DERIVED_DATA)/SwiftVoxAlta-*

# ── App Group code-signing ────────────────────────────────────────────────
# Sign the diga CLI with the com.apple.security.application-groups entitlement
# so the group ID is embedded in the binary and SwiftAcervo resolves the shared
# models container (~/Library/Group Containers/group.intrusive-memory.models/)
# WITHOUT requiring ACERVO_APP_GROUP_ID in the environment. Container access is
# plain POSIX (same-user, mode 700); the entitlement only supplies the group
# identifier at runtime via SecTaskCopyValueForEntitlement.
#
# Default identity is ad-hoc (-). For a distributable build, override with a
# Developer ID by certificate SHA-1 (names collide in the keychain):
#   make install codesign-cli CODESIGN_IDENTITY=<sha1>
APP_GROUP_ID ?= group.intrusive-memory.models
CODESIGN_IDENTITY ?= -
CODESIGN_FLAGS ?=
CODESIGN_ENTITLEMENTS ?= cli.entitlements

codesign-cli:
	@test -f "$(BIN_DIR)/$(BINARY)" || { echo "Error: $(BIN_DIR)/$(BINARY) not found — run 'make install' or 'make release' first."; exit 1; }
	@codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(CODESIGN_ENTITLEMENTS)" $(CODESIGN_FLAGS) "$(BIN_DIR)/$(BINARY)"
	@echo "Signed $(BIN_DIR)/$(BINARY) (identity: $(CODESIGN_IDENTITY), group: $(APP_GROUP_ID))"
	@codesign -d --entitlements - "$(BIN_DIR)/$(BINARY)" 2>/dev/null | grep -A1 "application-groups" || true

help:
	@echo "SwiftVoxAlta / diga CLI Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  resolve         - Resolve all SPM package dependencies"
	@echo "  build           - Development build (xcodebuild debug, no copy)"
	@echo "  install         - Debug build with xcodebuild + copy to ./bin (default)"
	@echo "  release         - Release build with xcodebuild + copy to ./bin"
	@echo "  lint            - Format Swift source files"
	@echo "  test            - Run all tests (unit + integration)"
	@echo "  test-unit       - Run fast unit tests only (no binary required)"
	@echo "  test-integration - Run binary integration tests (requires binary + voices)"
	@echo "  setup-voices    - One-time setup: generate voices for local testing"
	@echo "  codesign-cli    - Sign the diga CLI with the App Group entitlement (run after install/release)"
	@echo "  clean           - Clean build artifacts"
	@echo "  help            - Show this help"
	@echo ""
	@echo "All builds use: -destination '$(DESTINATION)'"
