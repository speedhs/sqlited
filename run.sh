#!/bin/sh

set -e # Exit early if any commands fail

(
  cd "$(dirname "$0")" # Ensure compile steps are run within the repository directory

  # Allow overriding the generator and disabling vcpkg for local runs
  # Example: CMAKE_GENERATOR="Ninja" NO_VCPKG=1 ./your_program.sh
  if [ -n "${CMAKE_GENERATOR:-}" ]; then
    GENERATOR="$CMAKE_GENERATOR"
  else
    # Prefer Ninja if available, otherwise fall back to Unix Makefiles
    if command -v ninja >/dev/null 2>&1; then
      GENERATOR="Ninja"
    elif command -v make >/dev/null 2>&1; then
      GENERATOR="Unix Makefiles"
    else
      echo "Error: no build tool found (install ninja-build or make)." >&2
      exit 1
    fi
  fi

  # Detect compilers and set CMake variables so CMake doesn't fail when system has unusual paths
  if command -v cc >/dev/null 2>&1; then
    C_COMPILER="$(command -v cc)"
  elif command -v gcc >/dev/null 2>&1; then
    C_COMPILER="$(command -v gcc)"
  fi
  if command -v c++ >/dev/null 2>&1; then
    CXX_COMPILER="$(command -v c++)"
  elif command -v g++ >/dev/null 2>&1; then
    CXX_COMPILER="$(command -v g++)"
  elif command -v clang++ >/dev/null 2>&1; then
    CXX_COMPILER="$(command -v clang++)"
  fi

  # If compilers were not detected, print a helpful message
  if [ -z "${C_COMPILER:-}" ] || [ -z "${CXX_COMPILER:-}" ]; then
    echo "Warning: C or C++ compiler not found in PATH. Install build-essential or set C/CXX environment variables." >&2
  fi

  # Only pass vcpkg toolchain file if VCPKG_ROOT is set and the file exists
  CMAKE_TOOLCHAIN_ARG=""
  if [ -z "${NO_VCPKG:-}" ] && [ -n "${VCPKG_ROOT:-}" ] && [ -f "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" ]; then
    CMAKE_TOOLCHAIN_ARG="-DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
  else
    if [ -n "${VCPKG_ROOT:-}" ] && [ -n "${NO_VCPKG:-}" ]; then
      echo "Notice: NO_VCPKG is set; skipping vcpkg toolchain." >&2
    fi
  fi
  # If an existing CMake cache references a toolchain file that no longer exists,
  # remove the build directory to force a clean configure. This fixes the
  # "Could not find toolchain file: /scripts/buildsystems/vcpkg.cmake" error
  # that occurs when a previous run passed a bad VCPKG_ROOT.
  if [ -f build/CMakeCache.txt ]; then
    CACHE_TOOLCHAIN=$(grep -m1 '^CMAKE_TOOLCHAIN_FILE:INTERNAL=' build/CMakeCache.txt || true)
    CACHE_TOOLCHAIN=${CACHE_TOOLCHAIN#CMAKE_TOOLCHAIN_FILE:INTERNAL=}
    if [ -n "$CACHE_TOOLCHAIN" ] && [ ! -f "$CACHE_TOOLCHAIN" ]; then
      echo "Removing stale build directory because cached toolchain is missing: $CACHE_TOOLCHAIN"
      rm -rf build
    fi
  fi

  echo "Configuring with generator: $GENERATOR"
  # Pass explicit compiler variables if detected to avoid CMake failing to find compilers
  CMAKE_COMPILER_ARGS=""
  if [ -n "${C_COMPILER:-}" ]; then
    CMAKE_COMPILER_ARGS="$CMAKE_COMPILER_ARGS -DCMAKE_C_COMPILER=${C_COMPILER}"
  fi
  if [ -n "${CXX_COMPILER:-}" ]; then
    CMAKE_COMPILER_ARGS="$CMAKE_COMPILER_ARGS -DCMAKE_CXX_COMPILER=${CXX_COMPILER}"
  fi

  cmake -B build -S . -G "$GENERATOR" $CMAKE_TOOLCHAIN_ARG $CMAKE_COMPILER_ARGS

  echo "Building (generator: $GENERATOR)"
  cmake --build ./build
)

exec $(dirname "$0")/build/sqlite "$@"
