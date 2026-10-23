#!/usr/bin/env bash
# Source this file from Bash or Zsh; keep the SDK and caches outside the repo.
if [ -n "${BASH_VERSION:-}" ]; then
  _abts_env_file="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _abts_env_file="${(%):-%x}"
else
  printf '%s\n' 'Source tool/android-env.sh from Bash or Zsh.' >&2
  return 1
fi
_abts_workspace="$(cd "$(dirname "$_abts_env_file")/../.." && pwd)"
export ABTS_TOOLCHAIN_ROOT="${ABTS_TOOLCHAIN_ROOT:-$_abts_workspace/.android-toolchain}"
export FLUTTER_ROOT="${FLUTTER_ROOT:-$_abts_workspace/.flutter-sdk/flutter}"
export JAVA_HOME="${ABTS_JAVA_HOME:-$ABTS_TOOLCHAIN_ROOT/jdk/amazon-corretto-17.jdk/Contents/Home}"
export ANDROID_HOME="$ABTS_TOOLCHAIN_ROOT/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="$ABTS_TOOLCHAIN_ROOT/android-user"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
export GRADLE_USER_HOME="$ABTS_TOOLCHAIN_ROOT/gradle-home"
export PUB_CACHE="$ABTS_TOOLCHAIN_ROOT/pub-cache"
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/19.0/bin:$FLUTTER_ROOT/bin:$PATH"
unset _abts_env_file _abts_workspace
