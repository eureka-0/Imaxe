# Defaults to running `just --list --unsorted` if no recipe is specified.
default:
    @just --list --unsorted

# Format all Swift files in the project using SwiftFormat and shell scripts using shfmt.
format:
    swiftformat Imaxe/ ImaxeTests/ ImaxeUITests/ --config .swiftformat
    shfmt -w -i 2 -s -bn ./Scripts/

# Lint all Swift files in the project using SwiftLint and shell scripts using ShellCheck.
lint:
    swiftlint lint --quiet --config .swiftlint.yml Imaxe/ ImaxeTests/ ImaxeUITests/
    shellcheck ./Scripts/*.sh

# Run tests. Use `--help` for usage information.
test *args:
    ./Scripts/test.sh {{ args }}

# Test file update functionality.
test-file-update:
    ./Scripts/test-file-update.sh

# Build the zip file for distribution.
build notes="Build/release-notes.md":
    RELEASE_NOTES_FILE={{ quote(notes) }} ./Scripts/build-zip.sh

# Create a GitHub release and upload the built zip file.
publish:
    ./Scripts/build-zip.sh --publish

# Generate Sparkle keys for signing updates.
generate-keys:
    ./Build/DerivedData/Release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys

# Reconcile stable releases with gh-pages and explicitly redeploy the complete site.
deploy-updates:
    gh workflow run updates.yml --repo eureka-0/Imaxe --ref main
