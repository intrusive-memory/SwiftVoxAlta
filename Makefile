# SwiftVoxAlta / diga CLI Makefile
# Build and install the diga CLI with full Metal shader support

SCHEME = diga
TEST_SCHEME = SwiftVoxAlta-Package
BINARY = diga
BIN_DIR = ./bin
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build release install clean test test-unit test-integration setup-voices resolve lint help

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
	@echo "  clean           - Clean build artifacts"
	@echo "  help            - Show this help"
	@echo ""
	@echo "All builds use: -destination '$(DESTINATION)'"
