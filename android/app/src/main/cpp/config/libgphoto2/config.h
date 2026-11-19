/* Hand-written config.h for libgphoto2 2.5.34 on Android (bionic, API 24+, NDK r28).
 * Replaces the autoconf-generated file. Only the ptp2 camlib is built (Canon EOS etc.). */
#ifndef GP_ANDROID_CONFIG_H
#define GP_ANDROID_CONFIG_H

#define PACKAGE "libgphoto2"
#define PACKAGE_NAME "libgphoto2 photo camera library"
#define PACKAGE_TARNAME "libgphoto2"
#define PACKAGE_VERSION "2.5.34"
#define PACKAGE_STRING "libgphoto2 photo camera library 2.5.34"
#define PACKAGE_BUGREPORT "gphoto-devel@lists.sourceforge.net"
#define PACKAGE_URL ""
#define VERSION "2.5.34"
#define GETTEXT_PACKAGE_LIBGPHOTO2 "libgphoto2-6"
#define HAVE_CC "clang (Android NDK)"
#define GP_CAMLIB_SET "ptp2"
#define GP_CAMLIB_SET_IS_NONSTANDARD 1

#define MAIL_GPHOTO_DEVEL "<gphoto-devel@lists.sourceforge.net>"
#define MAIL_GPHOTO_TRANSLATION "<gphoto-translation@lists.sourceforge.net>"
#define MAIL_GPHOTO_USER "<gphoto-user@lists.sourceforge.net>"
#define URL_DIGICAM_LIST "http://www.gphoto.org/proj/libgphoto2/support.php"
#define URL_GPHOTO_HOME "http://www.gphoto.org/"
#define URL_GPHOTO_PROJECT "https://github.com/gphoto"
#define URL_JPHOTO_HOME "http://jphoto.sourceforge.net/"
#define URL_USB_MASSSTORAGE "http://www.linux-usb.org/USB-guide/x498.html"

#define STDC_HEADERS 1
#define HAVE_DIRENT_H 1
#define HAVE_DLFCN_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_SYS_MOUNT_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_STATVFS_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_VFS_H 1
#define HAVE_UNISTD_H 1

#define HAVE_GETENV 1
#define HAVE_GMTIME_R 1
#define HAVE_INET_ATON 1
#define HAVE_LIBM 1
#define HAVE_LOCALTIME_R 1
#define HAVE_LSTAT 1
#define HAVE_MKDIR 1
#define HAVE_RAND_R 1
#define HAVE_SETENV 1
#define HAVE_SNPRINTF 1
#define HAVE_SPRINTF 1
#define HAVE_STATVFS 1
#define HAVE_STRCPY 1
#define HAVE_STRDUP 1
#define HAVE_STRNCPY 1
#define HAVE_STRUCT_STATVFS_F_BLOCKS 1
#define HAVE_TM_GMTOFF 1
#define HAVE_VA_COPY 1
#define HAVE_VSNPRINTF 1

/* Optional libraries not built for Android: libexif, libjpeg, libxml2, libcurl, iconv, gettext, gd */

#endif
