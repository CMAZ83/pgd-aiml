#!/usr/bin/env bash
set -euo pipefail

# Creates a separate public GitHub repository for each Jupyter notebook
# found in the current directory.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - git configured with user.name and user.email
#
# Usage:
#   chmod +x create_notebook_repos.sh
#   ./create_notebook_repos.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track all temporary directories so the EXIT trap can clean them all up.
TMP_DIRS=()
cleanup() {
  for d in "${TMP_DIRS[@]:-}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# Derive GitHub username from the authenticated gh session
GH_USER=$(gh api user --jq '.login' 2>/dev/null || true)
if [[ -z "$GH_USER" ]]; then
  echo "ERROR: Could not determine GitHub username. Run 'gh auth login' first." >&2
  exit 1
fi

echo "Creating notebook repositories for GitHub user: $GH_USER"
echo ""

for notebook in "$SCRIPT_DIR"/*.ipynb; do
  [[ -f "$notebook" ]] || continue

  filename="$(basename "$notebook")"
  # Convert filename to a repo-friendly name:
  # strip .ipynb, lowercase, replace spaces/underscores with hyphens
  repo_name="$(echo "${filename%.ipynb}" | tr '[:upper:]' '[:lower:]' | tr ' _' '-')"

  echo "Processing: $filename -> repo: $repo_name"

  tmp_dir="$(mktemp -d)"
  TMP_DIRS+=("$tmp_dir")

  # Initialise a local git repo
  git -C "$tmp_dir" init -q
  git -C "$tmp_dir" config user.name  "$(git config --global user.name  2>/dev/null || echo 'Notebook Bot')"
  git -C "$tmp_dir" config user.email "$(git config --global user.email 2>/dev/null || echo 'bot@example.com')"

  # Copy the notebook
  cp "$notebook" "$tmp_dir/"

  # Copy any CSV whose basename (without extension) matches the notebook basename
  notebook_base="${filename%.ipynb}"
  companion_csv="$SCRIPT_DIR/${notebook_base}.csv"
  if [[ -f "$companion_csv" ]]; then
    cp "$companion_csv" "$tmp_dir/"
  fi

  # Create a minimal README
  cat > "$tmp_dir/README.md" <<EOF
# ${repo_name}

Jupyter notebook: \`${filename}\`

Part of a PGD AI/ML curriculum — Python machine learning practice project.
EOF

  git -C "$tmp_dir" add .
  git -C "$tmp_dir" commit -qm "Initial commit: add ${filename}"

  # Create the remote repo (skip if it already exists)
  if gh repo view "$GH_USER/$repo_name" &>/dev/null; then
    echo "  Repository $GH_USER/$repo_name already exists, skipping creation."
  else
    gh repo create "$GH_USER/$repo_name" \
      --public \
      --description "ML notebook: ${filename%.ipynb}" \
      --source "$tmp_dir" \
      --remote origin \
      --push
    echo "  Created and pushed: https://github.com/$GH_USER/$repo_name"
  fi

  echo ""
done

echo "Done."
