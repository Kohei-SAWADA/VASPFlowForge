#!/usr/bin/env bash
# promote_contcar.sh - Hand a relaxed structure over to the next stage:
# copy SRC_DIR/CONTCAR to DST_DIR/POSCAR, with validation and provenance.
#
# Usage:
#   promote_contcar.sh SRC_DIR DST_DIR
#
# Safety checks before copying:
#   - SRC_DIR/CONTCAR exists, is non-empty, and has at least 8 lines
#     (comment, scale, 3 lattice vectors, element/count lines, coordinates)
#   - DST_DIR exists
# After copying, DST_DIR/POSCAR.provenance.txt records where the structure
# came from, when, and its checksum, so the chain remains auditable.
#
# Exit codes: 0 ok / 1 validation or copy failure / 3 usage error

set -u

if [ $# -ne 2 ]; then
  echo "usage: promote_contcar.sh SRC_DIR DST_DIR" >&2
  exit 3
fi

SRC_DIR="$1"
DST_DIR="$2"
SRC="$SRC_DIR/CONTCAR"
DST="$DST_DIR/POSCAR"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "unavailable"
  fi
}

if [ ! -s "$SRC" ]; then
  echo "promote_contcar.sh: ERROR: $SRC is missing or empty; previous stage did not produce a usable structure" >&2
  exit 1
fi

nlines=$(wc -l < "$SRC" | tr -d ' ')
if [ "$nlines" -lt 8 ]; then
  echo "promote_contcar.sh: ERROR: $SRC has only $nlines lines; not a valid CONTCAR" >&2
  exit 1
fi

if [ ! -d "$DST_DIR" ]; then
  echo "promote_contcar.sh: ERROR: destination directory $DST_DIR does not exist" >&2
  exit 1
fi

cp "$SRC" "$DST" || exit 1

{
  echo "POSCAR provenance"
  echo "  copied_from : $SRC"
  echo "  copied_at   : $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "  sha256      : $(sha256_of "$DST")"
  echo "  rule        : next-stage POSCAR must always come from the previous stage CONTCAR"
} > "$DST_DIR/POSCAR.provenance.txt"

echo "promote_contcar.sh: $SRC -> $DST"
exit 0
