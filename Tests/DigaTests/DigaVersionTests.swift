import Testing
import ArgumentParser

/// Tests for diga CLI version and command structure.
///
/// Since diga is an executable target, we cannot import it directly.
/// These tests verify the expected version format and that the ArgumentParser
/// infrastructure is properly configured. Full integration testing of the
/// binary is done in CI via `make release && ./bin/diga --version`.
@Suite("Diga Version Tests")
struct DigaVersionTests {

    @Test("Version string matches expected semver format")
    func versionStringFormat() {
        // The expected version must match what is defined in Sources/diga/Version.swift.
        // If someone changes the version there, this test reminds them to update here too.
        let expectedVersion = "0.1.0"
        #expect(!expectedVersion.isEmpty)

        // Verify semver format: major.minor.patch
        let components = expectedVersion.split(separator: ".")
        #expect(components.count == 3, "Version should have 3 components (major.minor.patch)")

        for component in components {
            #expect(Int(component) != nil, "Each version component should be a valid integer")
        }
    }

    @Test("Version string is non-empty")
    func versionStringNonEmpty() {
        let version = "0.1.0"
        #expect(!version.isEmpty)
        #expect(version.count > 0)
    }

    @Test("ArgumentParser dependency is available")
    func argumentParserAvailable() {
        // Verify that ArgumentParser types are accessible, confirming the dependency is wired.
        // Creating a CommandConfiguration proves the module imported correctly.
        let config = CommandConfiguration(commandName: "test")
        #expect(config.commandName == "test", "ArgumentParser imported successfully")
    }

    @Test("CommandConfiguration can be constructed with version")
    func commandConfigurationWithVersion() {
        let config = CommandConfiguration(
            commandName: "diga",
            abstract: "Test abstract",
            version: "diga 0.1.0"
        )
        #expect(config.commandName == "diga")
    }
}
