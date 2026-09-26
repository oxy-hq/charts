#!/usr/bin/env bash
# Decides which chart packages the GHCR push in helm-publish.yml may push:
# only those whose GitHub release chart-releaser created in THIS run.
#
#   chart-packages-to-push.sh snapshot
#       Print the remote's tags, one per line. Run it before chart-releaser.
#   chart-packages-to-push.sh select <packages-dir> <tags-before-file>
#       Print the path of each package to push, one per line.
#
# Why: chart-releaser repackages every chart whose directory changed since the
# last tag, including a tests-only change that leaves the version alone. Its
# --skip-existing skips only the GitHub release upload, so pushing every file
# in .cr-release-packages overwrote the published version in GHCR with the same
# files and a new digest (oxy-1.0.8, twice, on 2026-09-26). A release is a tag
# named <name>-<version> (cr's default release-name-template), so a package is
# new exactly when its tag was absent before chart-releaser ran and exists now.
#
# Fails closed: a failed or empty tag listing, or a package that was neither
# released before nor released now, stops the publish before anything is pushed.
set -euo pipefail

remote=${CHART_TAGS_REMOTE:-origin}

snapshot() {
  git ls-remote --tags --refs "$remote" | sed 's#^.*refs/tags/##' | sort -u
}

# <name>-<version> from the package's own Chart.yaml — the same fields cr names
# the release from, so a renamed .tgz can't pass for a different version.
release_tag() {
  helm show chart "$1" | yq -r '.name + "-" + .version'
}

select_packages() {
  local pkg_dir=$1 before=$2 after pkg tag status=0
  if [[ ! -s "$before" ]]; then
    echo "::error::no tags recorded before chart-releaser ran ($before); refusing to push" >&2
    return 1
  fi
  after=$(snapshot)
  if [[ -z "$after" ]]; then
    echo "::error::the remote lists no tags after chart-releaser ran; refusing to push" >&2
    return 1
  fi

  shopt -s nullglob
  for pkg in "$pkg_dir"/*.tgz; do
    tag=$(release_tag "$pkg")
    if grep -qxF -- "$tag" "$before"; then
      echo "skip $tag: released before this run; a published version is never overwritten" >&2
    elif grep -qxF -- "$tag" <<<"$after"; then
      echo "push $tag: released in this run" >&2
      echo "$pkg"
    else
      echo "::error::$tag was packaged but has no release; not pushing anything" >&2
      status=1
    fi
  done
  return "$status"
}

case "${1:-}" in
  snapshot) snapshot ;;
  select)
    [[ $# -eq 3 ]] || { echo "usage: $0 select <packages-dir> <tags-before-file>" >&2; exit 2; }
    select_packages "$2" "$3"
    ;;
  *)
    echo "usage: $0 snapshot | select <packages-dir> <tags-before-file>" >&2
    exit 2
    ;;
esac
