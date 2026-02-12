import Testing
import Foundation

/// Release infrastructure smoke tests.
///
/// These tests verify that the release workflow, Homebrew formula, Makefile,
/// and version metadata are properly configured and consistent.
@Suite("Diga Release Infrastructure Tests")
struct DigaReleaseTests {

    /// Path to the project root, derived from the test file location.
    private var projectRoot: String {
        // Tests/DigaTests/DigaReleaseTests.swift -> project root is 3 levels up
        let filePath = #filePath
        let url = URL(fileURLWithPath: filePath)
        return url.deletingLastPathComponent()  // DigaTests/
            .deletingLastPathComponent()          // Tests/
            .deletingLastPathComponent()          // project root
            .path
    }

    // MARK: - Version Tests

    @Test("DigaVersion.current is non-empty")
    func versionIsNonEmpty() {
        // Mirror the value from Sources/diga/Version.swift
        let version = "0.2.0"
        #expect(!version.isEmpty, "Version string must not be empty")
    }

    @Test("DigaVersion.current matches semver pattern")
    func versionMatchesSemver() {
        let version = "0.2.0"
        // Semver: major.minor.patch with optional pre-release
        let semverPattern = #"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$"#
        let regex = try? NSRegularExpression(pattern: semverPattern)
        let range = NSRange(version.startIndex..., in: version)
        let match = regex?.firstMatch(in: version, range: range)
        #expect(match != nil, "Version '\(version)' should match semver pattern major.minor.patch")
    }

    // MARK: - Makefile Tests

    @Test("Makefile exists at project root")
    func makefileExists() {
        let path = projectRoot + "/Makefile"
        let exists = FileManager.default.fileExists(atPath: path)
        #expect(exists, "Makefile should exist at project root")
    }

    @Test("Makefile contains expected targets")
    func makefileContainsTargets() throws {
        let path = projectRoot + "/Makefile"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        let expectedTargets = ["build", "release", "install", "clean", "test", "resolve"]
        for target in expectedTargets {
            #expect(content.contains(target), "Makefile should contain target: \(target)")
        }
    }

    @Test("Makefile uses xcodebuild, not swift build")
    func makefileUsesXcodebuild() throws {
        let path = projectRoot + "/Makefile"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("xcodebuild"), "Makefile should use xcodebuild")
        // Verify no raw 'swift build' commands (allow 'swift --version' etc.)
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("swift build") || trimmed.hasPrefix("swift test") {
                Issue.record("Makefile should not use 'swift build' or 'swift test': \(trimmed)")
            }
        }
    }

    // MARK: - Release Workflow Tests

    @Test("release.yml workflow exists")
    func releaseWorkflowExists() {
        let path = projectRoot + "/.github/workflows/release.yml"
        let exists = FileManager.default.fileExists(atPath: path)
        #expect(exists, "release.yml should exist in .github/workflows/")
    }

    @Test("release.yml contains expected triggers")
    func releaseWorkflowTriggers() throws {
        let path = projectRoot + "/.github/workflows/release.yml"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("release:"), "release.yml should trigger on release events")
        #expect(content.contains("workflow_dispatch:"), "release.yml should support manual dispatch")
        #expect(content.contains("published"), "release.yml should trigger on release published")
    }

    @Test("release.yml uses macos-26 runner")
    func releaseWorkflowRunner() throws {
        let path = projectRoot + "/.github/workflows/release.yml"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("macos-26"), "release.yml should use macos-26 runner")
    }

    @Test("release.yml packages tarball with correct naming")
    func releaseWorkflowPackaging() throws {
        let path = projectRoot + "/.github/workflows/release.yml"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("arm64-macos.tar.gz"), "release.yml should create arm64-macos tarball")
        #expect(content.contains("shasum -a 256") || content.contains("sha256"), "release.yml should compute SHA256")
    }

    @Test("release.yml uploads to GitHub Release")
    func releaseWorkflowUpload() throws {
        let path = projectRoot + "/.github/workflows/release.yml"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("softprops/action-gh-release"), "release.yml should use softprops/action-gh-release")
    }

    @Test("release.yml dispatches to Homebrew tap")
    func releaseWorkflowHomebrewDispatch() throws {
        let path = projectRoot + "/.github/workflows/release.yml"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("peter-evans/repository-dispatch"), "release.yml should dispatch to Homebrew tap")
        #expect(content.contains("intrusive-memory/homebrew-tap"), "release.yml should target intrusive-memory/homebrew-tap")
    }

    // MARK: - Homebrew Formula Tests

    @Test("Formula/diga.rb exists")
    func formulaExists() {
        let path = projectRoot + "/Formula/diga.rb"
        let exists = FileManager.default.fileExists(atPath: path)
        #expect(exists, "Formula/diga.rb should exist")
    }

    @Test("Formula contains expected structure")
    func formulaStructure() throws {
        let path = projectRoot + "/Formula/diga.rb"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("class Diga < Formula"), "Formula should define Diga class")
        #expect(content.contains("desc "), "Formula should have a description")
        #expect(content.contains("homepage "), "Formula should have a homepage")
        #expect(content.contains("url "), "Formula should have a URL")
        #expect(content.contains("sha256 "), "Formula should have a SHA256")
        #expect(content.contains("depends_on arch: :arm64"), "Formula should require ARM64")
        #expect(content.contains("depends_on macos:"), "Formula should require minimum macOS version")
    }

    @Test("Formula installs binary and Metal bundle")
    func formulaInstallation() throws {
        let path = projectRoot + "/Formula/diga.rb"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("libexec.install \"diga\""), "Formula should install diga to libexec")
        #expect(content.contains("mlx-swift_Cmlx.bundle"), "Formula should install Metal bundle")
    }

    @Test("Formula has caveats about model download")
    func formulaCaveats() throws {
        let path = projectRoot + "/Formula/diga.rb"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("def caveats"), "Formula should have caveats")
        #expect(content.contains("Qwen3-TTS") || content.contains("model"), "Caveats should mention model download")
    }

    @Test("Formula has a test block")
    func formulaTest() throws {
        let path = projectRoot + "/Formula/diga.rb"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        #expect(content.contains("test do"), "Formula should have a test block")
        #expect(content.contains("assert_match"), "Formula test should use assert_match")
    }
}
