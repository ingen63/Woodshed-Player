/* Build configuration of libFLAC (core/third_party/flac, #113), replaces the config.h that
 * libFLAC's own CMake or autotools build would generate. Only the encoder and decoder of native
 * FLAC are built: no Ogg, no threads, no SIMD intrinsics (plain C on every CPU, so all platforms
 * encode the same bytes). All supported platforms are little-endian. */
#ifndef WP_FLAC_CONFIG_H
#define WP_FLAC_CONFIG_H

#define PACKAGE_VERSION "1.5.0"

#define CPU_IS_BIG_ENDIAN 0
#define CPU_IS_LITTLE_ENDIAN 1
#define WORDS_BIGENDIAN 0
#define ENABLE_64_BIT_WORDS 1

#define FLAC__HAS_OGG 0
#define FLAC__NO_ASM 1
#define FLAC__HAS_X86INTRIN 0
#define FLAC__HAS_NEONINTRIN 0
#define FLAC__HAS_A64NEONINTRIN 0

#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LROUND 1
#if !defined(_WIN32)
#define HAVE_FSEEKO 1
#define HAVE_SYS_PARAM_H 1
#endif

#endif
