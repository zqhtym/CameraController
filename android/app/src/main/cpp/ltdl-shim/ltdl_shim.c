/* Built-in module table that stands in for libltdl (see ltdl.h). */
#include <string.h>
#include "ltdl.h"

#ifndef CAMLIBS
#error CAMLIBS must be defined (same value as for libgphoto2)
#endif
#ifndef IOLIBS
#error IOLIBS must be defined (same value as for libgphoto2_port)
#endif

/* ptp2 camlib (camlibs/ptp2/library.c) */
extern int camera_id(void *id);
extern int camera_abilities(void *list);
extern int camera_init(void *camera, void *context);

/* libusb1 iolib (libgphoto2_port/libusb1/libusb1.c) */
extern int gp_port_library_type(void);
extern int gp_port_library_list(void *list);
extern void *gp_port_library_operations(void);

struct lt_shim_symbol {
    const char *name;
    void *addr;
};

struct lt_shim_module {
    const char *name;
    const char *dir;
    const struct lt_shim_symbol *symbols;
};

static const struct lt_shim_symbol ptp2_symbols[] = {
    { "camera_id",        (void *) camera_id },
    { "camera_abilities", (void *) camera_abilities },
    { "camera_init",      (void *) camera_init },
    { NULL, NULL }
};

static const struct lt_shim_symbol libusb1_symbols[] = {
    { "gp_port_library_type",       (void *) gp_port_library_type },
    { "gp_port_library_list",       (void *) gp_port_library_list },
    { "gp_port_library_operations", (void *) gp_port_library_operations },
    { NULL, NULL }
};

static struct lt_shim_module modules[] = {
    { "ptp2",    CAMLIBS, ptp2_symbols },
    { "libusb1", IOLIBS,  libusb1_symbols },
};

#define MODULE_COUNT (sizeof(modules) / sizeof(modules[0]))

static __thread const char *last_error = NULL;

int lt_dlinit(void) { return 0; }
int lt_dlexit(void) { return 0; }
int lt_dladdsearchdir(const char *search_dir) { (void) search_dir; return 0; }

int lt_dlforeachfile(const char *search_path, int (*func)(const char *, lt_ptr), lt_ptr data)
{
    size_t i;
    if (!search_path || !func)
        return 0;
    for (i = 0; i < MODULE_COUNT; i++) {
        if (strcmp(search_path, modules[i].dir) == 0) {
            int r = func(modules[i].name, data);
            if (r != 0)
                return r;
        }
    }
    return 0;
}

lt_dlhandle lt_dlopenext(const char *filename)
{
    size_t i;
    if (filename) {
        for (i = 0; i < MODULE_COUNT; i++)
            if (strcmp(filename, modules[i].name) == 0)
                return &modules[i];
    }
    last_error = "module is not built into this app";
    return NULL;
}

void *lt_dlsym(lt_dlhandle handle, const char *name)
{
    const struct lt_shim_symbol *s;
    if (handle && name) {
        for (s = handle->symbols; s->name; s++)
            if (strcmp(s->name, name) == 0)
                return s->addr;
    }
    last_error = "symbol not found in built-in module";
    return NULL;
}

int lt_dlclose(lt_dlhandle handle) { (void) handle; return 0; }

const char *lt_dlerror(void)
{
    const char *e = last_error;
    last_error = NULL;
    return e;
}
