# SwiftVoxAlta / diga CLI Makefile
# Build and install the diga CLI with full Metal shader support

SCHEME = diga
TEST_SCHEME = SwiftVoxAlta-Package
BINARY = diga
BIN_DIR = ./bin
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build release install clean test test-unit test-integration setup-voices resolve help

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
	@echo "CI detected: Skipping SwiftVoxAltaTests (Metal incompatible), running only DigaTests"
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination 'platform=macOS' \
	  -only-testing:DigaTests \
	  -skip-testing:DigaTests/DigaBinaryIntegrationTests
else
	@echo "Local run: Running all tests (DigaTests + SwiftVoxAltaTests)"
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination 'platform=macOS' \
	  -skip-testing:DigaTests/DigaBinaryIntegrationTests
endif

# Integration tests (requires binary + cached voices)
test-integration: install
	@echo "Running integration tests (requires diga binary + cached voices)..."
	xcodebuild test \
	  -scheme $(TEST_SCHEME) \
	  -destination 'platform=macOS' \
	  -only-testing:DigaTests/DigaBinaryIntegrationTests

# All tests (unit + integration)
test: test-unit test-integration
	@echo "All tests complete!"

# One-time setup for local development (downloads CustomVoice model)
setup-voices: install
	@echo "Downloading CustomVoice model (~3.4GB, first run only)..."
	@./bin/diga -v ryan -o /tmp/warmup.wav "test" && rm -f /tmp/warmup.wav
	@echo "✓ CustomVoice model cached at ~/Library/Caches/intrusive-memory/Models/"
	@echo "  You can now run 'make test' or 'make test-integration'."

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
	@echo "  test            - Run all tests (unit + integration)"
	@echo "  test-unit       - Run fast unit tests only (no binary required)"
	@echo "  test-integration - Run binary integration tests (requires binary + voices)"
	@echo "  setup-voices    - One-time setup: generate voices for local testing"
	@echo "  clean           - Clean build artifacts"
	@echo "  help            - Show this help"
	@echo ""
	@echo "All builds use: -destination '$(DESTINATION)'"
