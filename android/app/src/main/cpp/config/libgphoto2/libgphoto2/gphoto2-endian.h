/* Hand-written replacement for the configure-generated libgphoto2/gphoto2-endian.h (Android).
 * Provides the byte-order helpers used by camlibs/ptp2: htoleN/leNtoh (from <endian.h>) plus the
 * unaligned byte-array variants leNatoh(ptr) / htoleNa(ptr, value). */
#ifndef GPHOTO2_ENDIAN_H_ANDROID
#define GPHOTO2_ENDIAN_H_ANDROID

#include <stdint.h>
#include <endian.h>

#if !defined(__BYTE_ORDER) || __BYTE_ORDER != __LITTLE_ENDIAN
#error "This gphoto2-endian.h assumes a little-endian target (true for all Android ABIs)"
#endif

#define _GP_B(p, i) ((uint64_t) ((const uint8_t *) (p))[i])

#define le16atoh(p) ((uint16_t) (_GP_B(p, 0) | (_GP_B(p, 1) << 8)))
#define le32atoh(p) ((uint32_t) (_GP_B(p, 0) | (_GP_B(p, 1) << 8) | (_GP_B(p, 2) << 16) | (_GP_B(p, 3) << 24)))
#define le64atoh(p) ((uint64_t) le32atoh(p) | ((uint64_t) le32atoh((const uint8_t *) (p) + 4) << 32))
#define be16atoh(p) ((uint16_t) ((_GP_B(p, 0) << 8) | _GP_B(p, 1)))
#define be32atoh(p) ((uint32_t) ((_GP_B(p, 0) << 24) | (_GP_B(p, 1) << 16) | (_GP_B(p, 2) << 8) | _GP_B(p, 3)))

#define htole16a(a, x) do { uint8_t *_p = (uint8_t *) (a); uint16_t _v = (uint16_t) (x); \
	_p[0] = (uint8_t) _v; _p[1] = (uint8_t) (_v >> 8); } while (0)
#define htole32a(a, x) do { uint8_t *_p = (uint8_t *) (a); uint32_t _v = (uint32_t) (x); \
	_p[0] = (uint8_t) _v; _p[1] = (uint8_t) (_v >> 8); _p[2] = (uint8_t) (_v >> 16); _p[3] = (uint8_t) (_v >> 24); } while (0)
#define htole64a(a, x) do { uint8_t *_q = (uint8_t *) (a); uint64_t _w = (uint64_t) (x); \
	htole32a(_q, (uint32_t) _w); htole32a(_q + 4, (uint32_t) (_w >> 32)); } while (0)
#define htobe16a(a, x) do { uint8_t *_p = (uint8_t *) (a); uint16_t _v = (uint16_t) (x); \
	_p[0] = (uint8_t) (_v >> 8); _p[1] = (uint8_t) _v; } while (0)
#define htobe32a(a, x) do { uint8_t *_p = (uint8_t *) (a); uint32_t _v = (uint32_t) (x); \
	_p[0] = (uint8_t) (_v >> 24); _p[1] = (uint8_t) (_v >> 16); _p[2] = (uint8_t) (_v >> 8); _p[3] = (uint8_t) _v; } while (0)

#endif
