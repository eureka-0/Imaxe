# Defaults to running `just --list --unsorted` if no recipe is specified.
default:
    @just --list --unsorted

# Format all Swift files in the project using SwiftFormat and shell scripts using shfmt.
format:
    swiftformat Imaxe/ ImaxeTests/ ImaxeUITests/ --config .swiftformat
    shfmt -w -i 2 -s -bn ./scripts/

# Lint all Swift files in the project using SwiftLint and shell scripts using ShellCheck.
lint:
    swiftlint lint --quiet --config .swiftlint.yml Imaxe/ ImaxeTests/ ImaxeUITests/
    shellcheck ./scripts/*.sh

# Run tests. Use `--help` for usage information.
test *args:
    ./scripts/test.sh {{ args }}

# Test file update functionality.
test-file-update:
    ./scripts/test-file-update.sh

# Build using Imaxe-<version>.md in the matching build/Releases directory.
# If notes are missing, write them at the reported path and rerun.
build:
    ./scripts/build-zip.sh

# Create a GitHub release and upload the built zip file.
publish:
    ./scripts/build-zip.sh --publish

# Generate Sparkle keys for signing updates.
generate-keys:
    ./build/DerivedData/Release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys

# Reconcile stable releases with gh-pages and explicitly redeploy the complete site.
deploy-updates:
    gh workflow run updates.yml --repo eureka-0/Imaxe --ref main
