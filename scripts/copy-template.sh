#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <destination>" >&2
  exit 1
fi

cp template/article.md "$1"
echo "Copied template/article.md -> $1"
