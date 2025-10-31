#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    echo "Example: $0 simardeepsingh"
    exit 1
fi

GITHUB_USERNAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Updating GitHub URLs for username: ${GITHUB_USERNAME}"

# Update app-repo references
find "${ROOT_DIR}" -name "*.yaml" -o -name "*.yml" | xargs sed -i.bak "s|github.com/example/progressive-delivery-app|github.com/${GITHUB_USERNAME}/app-repo|g"

# Update env-repo references  
find "${ROOT_DIR}" -name "*.yaml" -o -name "*.yml" | xargs sed -i.bak "s|github.com/example/env-repo|github.com/${GITHUB_USERNAME}/env-repo|g"

# Update app-repo GitHub Actions
find "${ROOT_DIR}/../app-repo" -name "*.yaml" -o -name "*.yml" | xargs sed -i.bak "s|github.com/example/progressive-delivery-app|github.com/${GITHUB_USERNAME}/app-repo|g"
find "${ROOT_DIR}/../app-repo" -name "*.yaml" -o -name "*.yml" | xargs sed -i.bak "s|github.com/example/env-repo|github.com/${GITHUB_USERNAME}/env-repo|g"

# Clean up backup files
find "${ROOT_DIR}" -name "*.bak" -delete
find "${ROOT_DIR}/../app-repo" -name "*.bak" -delete

echo "URLs updated successfully!"
echo ""
echo "Next steps:"
echo "1. git add ."
echo "2. git commit -m 'Update GitHub repository URLs'"
echo "3. git push"