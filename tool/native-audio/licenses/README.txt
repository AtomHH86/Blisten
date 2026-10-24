B听原生音频依赖通知

mpv 0.35.1: Copyright © 2000–2023 mpv/MPlayer/mplayer2 projects. LGPL build (--enable-lgpl).
FFmpeg 6.1.6: FFmpeg contributors. LGPL version 3 or later (--enable-version3, --disable-gpl, --disable-nonfree).
Mbed TLS 3.6.7 and its framework: The Mbed TLS Contributors. This distribution selects Apache License 2.0 where the source offers Apache-2.0 OR GPL-2.0-or-later.
Project Everest: Copyright 2016–2018 INRIA and Microsoft Corporation, Apache License 2.0.
media-kit-android-helper: Copyright (c) 2021 & onwards Hitesh Kumar Saini, MIT.
Android NDK r28c runtime components, including statically linked libc++, libc++abi and compiler runtime: see the Android/LLVM notice files retained here for their respective licenses.

This software is based in part on the work of the Independent JPEG Group.
The FFmpeg copies of libavcodec/jfdctfst.c, libavcodec/jfdctint_template.c and libavcodec/jrevdct.c are unchanged by Blisten.

mpv modifications: three original patches from media-kit/libmpv-android-audio-build commit 87744be8b337c50ed54961249b7a97c5e8cc37c9, for AudioTrack synchronization, JavaVM integration and removing libass.
Blisten changes dated 2026-10-24: Mbed TLS include/mbedtls/mbedtls_config.h enables MBEDTLS_THREADING_C and MBEDTLS_THREADING_PTHREAD for concurrent TLS 1.3 use. The full patches list all changed mpv source files.
Build changes: updated FFmpeg and Mbed TLS, removed unused libxml2, fixed helper source revision, Android API 24 / NDK r28c / 16 KiB ELF linking.

Full corresponding source archives, submodules, patches, build commands and configuration are supplied alongside the APK release. The same-version Blisten application source allows rebuilding and relinking with modified LGPL libraries and signing the resulting APK with your own key. Blisten does not prohibit reverse engineering for debugging modifications to these LGPL components.

These notice files supplement and do not replace copyright/license notices in the complete corresponding source archive.
