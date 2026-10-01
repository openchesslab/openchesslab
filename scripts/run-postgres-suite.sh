#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run the OpenChessLab PostgreSQL test suite.

Usage:
  ./run-postgres-suite.sh [--database-url URL] [--skip-migrations]

DATABASE_URL may also be supplied through the environment.

Examples:
  export DATABASE_URL='ecto://openchesslab:openchesslab@localhost/openchesslab_test'
  ./run-postgres-suite.sh

  ./run-postgres-suite.sh \
    --database-url 'ecto://openchesslab:openchesslab@localhost/openchesslab_test'

  ./run-postgres-suite.sh --skip-migrations
EOF
}

database_url="${DATABASE_URL:-ecto://openchesslab:openchesslab@localhost/openchesslab_test}"
skip_migrations=false

while (($# > 0)); do
  case "$1" in
    --database-url)
      if (($# < 2)); then
        echo "error: --database-url requires a value" >&2
        exit 2
      fi

      database_url="$2"
      shift 2
      ;;
    --skip-migrations)
      skip_migrations=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$database_url" ]]; then
  echo "error: DATABASE_URL is required" >&2
  echo >&2
  usage >&2
  exit 2
fi

is_repo_root() {
  local path="$1"

  [[ -f "$path/mix.exs" ]] &&
    [[ -f "$path/apps/analysis/mix.exs" ]] &&
    [[ -f "$path/apps/database/mix.exs" ]]
}

walk_up() {
  local current="$1"

  current="$(cd "$current" && pwd)"

  while true; do
    if is_repo_root "$current"; then
      printf '%s\n' "$current"
      return 0
    fi

    local parent
    parent="$(dirname "$current")"

    if [[ "$parent" == "$current" ]]; then
      return 1
    fi

    current="$parent"
  done
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_root=""

if repo_root="$(walk_up "$PWD" 2>/dev/null)"; then
  :
elif repo_root="$(walk_up "$script_dir" 2>/dev/null)"; then
  :
else
  echo "error: could not find the OpenChessLab repository root" >&2
  echo "Run this script from the repository or place it in the repository (for example under scripts/)." >&2
  exit 2
fi

export DATABASE_URL="$database_url"

echo "OpenChessLab PostgreSQL suite"
echo "Repository: $repo_root"

if [[ "$skip_migrations" == false ]]; then
  echo
  echo "==> Running PostgreSQL migrations"

  (
    cd "$repo_root/apps/database"
    MIX_ENV=dev mix ecto.migrate
  )
else
  echo
  echo "==> Skipping PostgreSQL migrations"
fi

echo
echo "==> Running PostgreSQL-tagged Analysis tests"

(
  cd "$repo_root/apps/analysis"
  POSTGRES_TESTS=true MIX_ENV=test mix test --only postgres
)

echo
echo "PostgreSQL suite passed."
