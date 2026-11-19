/* Minimal replacement for libtool's <ltdl.h> used by libgphoto2 on Android.
 *
 * libgphoto2 normally dlopen()s camera drivers (camlibs) and port drivers (iolibs) from
 * directories. On Android we link the ptp2 camlib and the libusb1 iolib statically into the
 * app's single shared library and expose them through this shim as "built-in modules". */
#ifndef LTDL_SHIM_H
#define LTDL_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void *lt_ptr;
typedef struct lt_shim_module *lt_dlhandle;

int lt_dlinit(void);
int lt_dlexit(void);
int lt_dladdsearchdir(const char *search_dir);
int lt_dlforeachfile(const char *search_path, int (*func)(const char *filename, lt_ptr data), lt_ptr data);
lt_dlhandle lt_dlopenext(const char *filename);
void *lt_dlsym(lt_dlhandle handle, const char *name);
int lt_dlclose(lt_dlhandle handle);
const char *lt_dlerror(void);

#ifdef __cplusplus
}
#endif

#endif
