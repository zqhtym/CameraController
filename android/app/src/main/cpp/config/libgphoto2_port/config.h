/* Hand-written config.h for libgphoto2_port 0.12.2 on Android (bionic, API 24+, NDK r28).
 * Replaces the autoconf-generated file. Only the libusb1 iolib is built. */
#ifndef GP_PORT_ANDROID_CONFIG_H
#define GP_PORT_ANDROID_CONFIG_H

#define PACKAGE "libgphoto2_port"
#define PACKAGE_NAME "libgphoto2 port access library"
#define PACKAGE_TARNAME "libgphoto2_port"
#define PACKAGE_VERSION "0.12.2"
#define PACKAGE_STRING "libgphoto2 port access library 0.12.2"
#define PACKAGE_BUGREPORT "gphoto-devel@lists.sourceforge.net"
#define PACKAGE_URL ""
#define VERSION "0.12.2"
#define GETTEXT_PACKAGE_LIBGPHOTO2_PORT "libgphoto2_port-12"
#define HAVE_CC "clang (Android NDK)"
#define IOLIB_LIST "libusb1"

#define MAIL_GPHOTO_DEVEL "<gphoto-devel@lists.sourceforge.net>"
#define MAIL_GPHOTO_TRANSLATION "<gphoto-translation@lists.sourceforge.net>"
#define MAIL_GPHOTO_USER "<gphoto-user@lists.sourceforge.net>"
#define URL_DIGICAM_LIST "http://www.gphoto.org/proj/libgphoto2/support.php"
#define URL_GPHOTO_HOME "http://www.gphoto.org/"
#define URL_GPHOTO_PROJECT "https://github.com/gphoto"
#define URL_JPHOTO_HOME "http://jphoto.sourceforge.net/"
#define URL_USB_MASSSTORAGE "http://www.linux-usb.org/USB-guide/x498.html"

#define STDC_HEADERS 1
#define HAVE_BYTESWAP_H 1
#define HAVE_DIRENT_H 1
#define HAVE_DLFCN_H 1
#define HAVE_ENDIAN_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_FILE_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TERMIOS_H 1
#define HAVE_UNISTD_H 1

#define HAVE_SNPRINTF 1
#define HAVE_VSNPRINTF 1
#define HAVE_STRERROR 1
#define HAVE_VA_COPY 1
#define HAVE_LIBPTHREAD 1
#define HAVE_REGEX 1

/* libusb-1.0 with Android support: use the file descriptor handed over by UsbManager */
#define HAVE_LIBUSB1 1
#define HAVE_LIBUSB_STRERROR 1
#define HAVE_LIBUSB_WRAP_SYS_DEVICE 1
#define HAVE_LIBUSB_OPTION_NO_DEVICE_DISCOVERY 1

/* Not available / not wanted: ENABLE_NLS, HAVE_GETTEXT, HAVE_ICONV, HAVE_LOCKDEV, HAVE_SERIAL, HAVE_LIBEXIF */

#endif
