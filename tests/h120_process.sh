#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for mode in c cxx; do
    if [ "$mode" = c ]; then compiler=clang; language=c; standard=c11; else compiler=clang++; language=c++; standard=c++11; fi
    for test in h120_process h120_policy; do
        "$compiler" -x "$language" -std="$standard" -Wall -Wextra -Werror -pedantic "tests/$test.c" hello120hz/Core/H120Policy.c -lm -o "$tmp/$test-$mode"
        "$tmp/$test-$mode"
    done
done
