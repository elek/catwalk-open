#!/usr/bin/env bash
#
# Rename charmbracelet/catwalk -> elek/catwalk-open everywhere,
# move internal/deprecated -> pkg/deprecated,
# move internal/providers -> providers,
# and update all Go import paths and file references accordingly.
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OLD_MODULE="charm.land/catwalk"
NEW_MODULE="github.com/elek/catwalk-open"

echo "=== Step 1: Move directories ==="

# Move internal/deprecated -> pkg/deprecated
if [ -d internal/deprecated ]; then
    echo "  Moving internal/deprecated -> pkg/deprecated"
    mkdir -p pkg
    mv internal/deprecated pkg/deprecated
else
    echo "  internal/deprecated not found, skipping"
fi

# Move internal/providers -> providers (top-level)
if [ -d internal/providers ]; then
    echo "  Moving internal/providers -> providers"
    mv internal/providers providers
else
    echo "  internal/providers not found, skipping"
fi

# Remove internal/ if empty
if [ -d internal ] && [ -z "$(ls -A internal)" ]; then
    echo "  Removing empty internal/ directory"
    rmdir internal
fi

echo "=== Step 2: Rename module and import paths in all files ==="

# Find all non-binary, non-.git files and do replacements
# Order matters: do the longer/more-specific replacements first.
find . -type f \
    -not -path './.git/*' \
    -not -path './rename.sh' \
    -not -name '*.sum' \
    -print0 |
while IFS= read -r -d '' file; do
    # Skip binary files
    if file --mime-encoding "$file" | grep -q binary; then
        continue
    fi

    changed=false

    # 1. Module path: charm.land/catwalk -> github.com/elek/catwalk-open
    if grep -qF "$OLD_MODULE" "$file"; then
        sed -i "s|${OLD_MODULE}|${NEW_MODULE}|g" "$file"
        changed=true
    fi

    # 2. GitHub references: charmbracelet/catwalk -> elek/catwalk-open
    if grep -q 'charmbracelet/catwalk' "$file"; then
        sed -i 's|charmbracelet/catwalk|elek/catwalk-open|g' "$file"
        changed=true
    fi

    # 3. Import path moves: internal/deprecated -> pkg/deprecated
    #    (already handled by module rename above for Go imports,
    #     but also catch literal path references like in comments/WriteFile calls)
    if grep -qF 'internal/deprecated' "$file"; then
        sed -i 's|internal/deprecated|pkg/deprecated|g' "$file"
        changed=true
    fi

    # 4. Import path moves: internal/providers -> providers
    #    Go import: charm.land/catwalk/internal/providers -> github.com/elek/catwalk-open/providers
    #    (the module rename already changed charm.land/catwalk -> github.com/elek/catwalk-open,
    #     so we just need to fix /internal/providers -> /providers in import paths)
    if grep -qF "${NEW_MODULE}/internal/providers" "$file"; then
        sed -i "s|${NEW_MODULE}/internal/providers|${NEW_MODULE}/providers|g" "$file"
        changed=true
    fi

    # 5. Literal file path references like WriteFile("internal/providers/...")
    if grep -qF 'internal/providers' "$file"; then
        sed -i 's|internal/providers|providers|g' "$file"
        changed=true
    fi

    if [ "$changed" = true ]; then
        echo "  Updated: $file"
    fi
done

echo "=== Step 3: Verify ==="

echo ""
echo "Remaining references to old module (should be empty):"
grep -r --include='*.go' --include='*.mod' --include='*.yml' --include='*.yaml' --include='*.md' \
    -l 'charm\.land/catwalk\|charmbracelet/catwalk\|internal/deprecated\|internal/providers' . \
    --exclude-dir=.git --exclude=rename.sh || echo "  (none - all clean!)"

echo ""
echo "Done! You may want to run 'go mod tidy' to update go.sum."
