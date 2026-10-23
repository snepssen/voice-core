/* What espeak-ng's CMake writes from config.h.in, for the options every
   snepssen voice was trained through (scripts/build-espeak.sh): no async,
   Klatt, speechPlayer, MBROLA, libsonic or pcaudio. glibc has mkstemp and
   iswblank, and no <sys/endian.h>. */
#define HAVE_MKSTEMP 1
#define HAVE_NBTOOL_CONFIG_H 0
#define HAVE_DECL_OPTRESET 0
#define HAVE_SYS_ENDIAN_H 0
#define HAVE_ISWBLANK 1

#define USE_ASYNC 0
#define USE_KLATT 0
#define USE_LIBPCAUDIO 0
#define USE_LIBSONIC 0
#define USE_MBROLA 0
#define USE_SPEECHPLAYER 0

#define PACKAGE_VERSION "1.52.0.1"
