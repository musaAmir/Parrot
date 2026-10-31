#!/bin/bash
# Keep Xcode/SwiftPM paths physical and consistent while preserving build/ links.
parrot_init_build_directory() {
  local root="$1"
  if [[ -d "$root/build" && ! -L "$root/build" ]]; then
    if [[ -e "$root/build.noindex" ]]; then
      echo 'Both build/ and build.noindex/ exist; consolidate build output before building.' >&2
      return 1
    fi
    mv "$root/build" "$root/build.noindex"
  fi
  mkdir -p "$root/build.noindex"
  if [[ ! -e "$root/build" && ! -L "$root/build" ]]; then
    ln -s build.noindex "$root/build"
  fi
  PARROT_BUILD_ROOT="$(cd "$root/build.noindex" && pwd -P)"
}
