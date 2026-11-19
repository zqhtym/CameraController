/* JNI bridge between the Android app (org.cameracontroller.poc.GPhoto) and libgphoto2.
 * All functions must be called from ONE Java thread (libgphoto2 is not thread-safe). */
#include <jni.h>
#include <android/log.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-port.h>
#include <gphoto2/gphoto2-port-log.h>
#include <gphoto2/gphoto2-port-info-list.h>
#include <gphoto2/gphoto2-version.h>
#include <libusb.h>

#define TAG "gphoto2"

/* Non-rooted Android apps cannot enumerate /dev/bus/usb (and may not open netlink sockets);
 * USB devices are only reachable through UsbManager file descriptors. Disable libusb's own
 * device discovery for every context, so libusb_init() succeeds even without a camera. */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
    (void) vm; (void) reserved;
    libusb_set_option(NULL, LIBUSB_OPTION_NO_DEVICE_DISCOVERY);
    return JNI_VERSION_1_6;
}

static Camera *g_camera = NULL;
static GPContext *g_context = NULL;
static FILE *g_log = NULL;
static int g_log_func_id = -1;
static char g_last_error[2048] = "";

/* ------------------------------------------------------------------ logging */

static void log_line(char level, const char *domain, const char *msg)
{
    int prio = level == 'E' ? ANDROID_LOG_ERROR : (level == 'I' ? ANDROID_LOG_INFO : ANDROID_LOG_DEBUG);
    __android_log_print(prio, TAG, "%s: %s", domain, msg);
    if (g_log) {
        char ts[16];
        time_t t = time(NULL);
        struct tm tm;
        localtime_r(&t, &tm);
        strftime(ts, sizeof ts, "%H:%M:%S", &tm);
        fprintf(g_log, "%s %c %s: %s\n", ts, level, domain, msg);
        fflush(g_log);
    }
}

static void bridge_log(char level, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void bridge_log(char level, const char *fmt, ...)
{
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    log_line(level, "bridge", buf);
}

static void gp_log_cb(GPLogLevel level, const char *domain, const char *str, void *data)
{
    (void) data;
    log_line(level == GP_LOG_ERROR ? 'E' : (level == GP_LOG_VERBOSE ? 'V' : 'D'), domain, str);
}

static void ctx_error_cb(GPContext *context, const char *text, void *data)
{
    (void) context; (void) data;
    snprintf(g_last_error, sizeof g_last_error, "%s", text);
    log_line('E', "context", text);
}

static void ctx_message_cb(GPContext *context, const char *text, void *data)
{
    (void) context; (void) data;
    log_line('I', "context", text);
}

static void set_error(const char *what, int ret)
{
    if (g_last_error[0] == '\0' || ret != GP_OK)
        snprintf(g_last_error, sizeof g_last_error, "%s: %s (%d)", what, gp_result_as_string(ret), ret);
    bridge_log('E', "%s", g_last_error);
}

static jstring jstr(JNIEnv *env, const char *s)
{
    return (*env)->NewStringUTF(env, s ? s : "");
}

/* ------------------------------------------------------------------ session */

static void close_camera(void)
{
    if (g_camera) {
        gp_camera_exit(g_camera, g_context);
        gp_camera_free(g_camera);
        g_camera = NULL;
    }
    if (g_context) {
        gp_context_unref(g_context);
        g_context = NULL;
    }
    /* Forget the wrapped USB handle: with fd -1 the libusb1 iolib drops its cached handle
     * the next time the port list is (re)loaded (see ANDROID PATCH in libusb1.c). */
    gp_port_usb_set_sys_device(-1);
    {
        GPPortInfoList *list = NULL;
        if (gp_port_info_list_new(&list) == GP_OK) {
            gp_port_info_list_load(list);
            gp_port_info_list_free(list);
        }
    }
}

JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_version(JNIEnv *env, jclass cls)
{
    (void) cls;
    const char **v = gp_library_version(GP_VERSION_SHORT);
    const char **pv = gp_port_library_version(GP_VERSION_SHORT);
    char buf[256];
    snprintf(buf, sizeof buf, "libgphoto2 %s / libgphoto2_port %s", v && v[0] ? v[0] : "?", pv && pv[0] ? pv[0] : "?");
    return jstr(env, buf);
}

/* Opens the camera on the USB file descriptor obtained from UsbDeviceConnection.getFileDescriptor().
 * Returns a gphoto2 result code (>= 0 on success). */
JNIEXPORT jint JNICALL
Java_org_cameracontroller_poc_GPhoto_open(JNIEnv *env, jclass cls, jint fd, jstring jfilesDir)
{
    (void) cls;
    int ret;
    const char *dir = (*env)->GetStringUTFChars(env, jfilesDir, NULL);
    char path[1024];

    close_camera();
    g_last_error[0] = '\0';

    setenv("HOME", dir, 1); /* gphoto2-setting.c stores ~/.gphoto/settings */
    snprintf(path, sizeof path, "%s/gphoto2.log", dir);
    (*env)->ReleaseStringUTFChars(env, jfilesDir, dir);
    if (g_log)
        fclose(g_log);
    g_log = fopen(path, "w");
    if (g_log_func_id < 0)
        g_log_func_id = gp_log_add_func(GP_LOG_DEBUG, gp_log_cb, NULL);

    {
        const char **v = gp_library_version(GP_VERSION_SHORT);
        bridge_log('I', "open: libgphoto2 %s, usb fd %d", v && v[0] ? v[0] : "?", (int) fd);
    }

    ret = gp_port_usb_set_sys_device(fd);
    if (ret < GP_OK) {
        set_error("gp_port_usb_set_sys_device", ret);
        return ret;
    }

    g_context = gp_context_new();
    gp_context_set_error_func(g_context, ctx_error_cb, NULL);
    gp_context_set_message_func(g_context, ctx_message_cb, NULL);

    ret = gp_camera_new(&g_camera);
    if (ret < GP_OK) {
        set_error("gp_camera_new", ret);
        g_camera = NULL;
        return ret;
    }
    ret = gp_camera_init(g_camera, g_context); /* autodetects the single wrapped USB device */
    if (ret < GP_OK) {
        set_error("gp_camera_init", ret);
        gp_camera_free(g_camera);
        g_camera = NULL;
        return ret;
    }
    {
        CameraAbilities a;
        if (gp_camera_get_abilities(g_camera, &a) == GP_OK)
            bridge_log('I', "connected: %s (driver %s)", a.model, a.library);
    }
    return GP_OK;
}

JNIEXPORT void JNICALL
Java_org_cameracontroller_poc_GPhoto_close(JNIEnv *env, jclass cls)
{
    (void) env; (void) cls;
    bridge_log('I', "close");
    close_camera();
}

JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_lastError(JNIEnv *env, jclass cls)
{
    (void) cls;
    return jstr(env, g_last_error);
}

JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_model(JNIEnv *env, jclass cls)
{
    (void) cls;
    CameraAbilities a;
    if (!g_camera || gp_camera_get_abilities(g_camera, &a) < GP_OK)
        return NULL;
    return jstr(env, a.model);
}

JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_summary(JNIEnv *env, jclass cls)
{
    (void) cls;
    CameraText text;
    int ret;
    if (!g_camera)
        return NULL;
    ret = gp_camera_get_summary(g_camera, &text, g_context);
    if (ret < GP_OK) {
        set_error("gp_camera_get_summary", ret);
        return NULL;
    }
    return jstr(env, text.text);
}

/* ------------------------------------------------------------------ live view */

JNIEXPORT jbyteArray JNICALL
Java_org_cameracontroller_poc_GPhoto_preview(JNIEnv *env, jclass cls)
{
    (void) cls;
    CameraFile *file = NULL;
    const char *data = NULL;
    unsigned long size = 0;
    jbyteArray out = NULL;
    int ret;

    if (!g_camera)
        return NULL;
    if (gp_file_new(&file) < GP_OK)
        return NULL;
    ret = gp_camera_capture_preview(g_camera, file, g_context);
    if (ret < GP_OK) {
        set_error("gp_camera_capture_preview", ret);
    } else if (gp_file_get_data_and_size(file, &data, &size) == GP_OK && size > 0) {
        out = (*env)->NewByteArray(env, (jsize) size);
        if (out)
            (*env)->SetByteArrayRegion(env, out, 0, (jsize) size, (const jbyte *) data);
    }
    gp_file_free(file);
    return out;
}

/* ------------------------------------------------------------------ capture */

static int is_capture_target_ram(void)
{
    CameraWidget *w = NULL;
    const char *val = NULL;
    int ram = 0;
    if (gp_camera_get_single_config(g_camera, "capturetarget", &w, g_context) == GP_OK) {
        if (gp_widget_get_value(w, &val) == GP_OK && val && strcasestr(val, "RAM"))
            ram = 1;
        gp_widget_free(w);
    }
    return ram;
}

/* Downloads folder/name to dir/<prefix>_<name>; appends the saved path to out (newline separated). */
static int download_file(const char *folder, const char *name, const char *dir, const char *prefix,
                         int delete_after, char *out, size_t outsize)
{
    CameraFile *file = NULL;
    char path[1024];
    int ret;

    snprintf(path, sizeof path, "%s/%s_%s", dir, prefix, name);
    ret = gp_file_new(&file);
    if (ret < GP_OK)
        return ret;
    ret = gp_camera_file_get(g_camera, folder, name, GP_FILE_TYPE_NORMAL, file, g_context);
    if (ret >= GP_OK)
        ret = gp_file_save(file, path);
    gp_file_free(file);
    if (ret < GP_OK) {
        set_error("download", ret);
        return ret;
    }
    bridge_log('I', "saved %s/%s -> %s", folder, name, path);
    if (delete_after)
        gp_camera_file_delete(g_camera, folder, name, g_context); /* frees the camera's RAM buffer */
    if (out[0])
        strncat(out, "\n", outsize - strlen(out) - 1);
    strncat(out, path, outsize - strlen(out) - 1);
    return GP_OK;
}

/* Takes a picture and downloads it (and a possible second RAW+JPEG file) into dir.
 * Returns the saved paths separated by '\n', or null on error (see lastError()). */
JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_capture(JNIEnv *env, jclass cls, jstring jdir)
{
    (void) cls;
    CameraFilePath cpath;
    char out[4096] = "";
    char prefix[32];
    const char *dir;
    int ret, delete_after, i;
    time_t t = time(NULL);
    struct tm tm;

    if (!g_camera)
        return NULL;
    g_last_error[0] = '\0';
    localtime_r(&t, &tm);
    strftime(prefix, sizeof prefix, "%Y%m%d_%H%M%S", &tm);
    delete_after = is_capture_target_ram();

    ret = gp_camera_capture(g_camera, GP_CAPTURE_IMAGE, &cpath, g_context);
    if (ret < GP_OK) {
        set_error("gp_camera_capture", ret);
        return NULL;
    }
    dir = (*env)->GetStringUTFChars(env, jdir, NULL);
    ret = download_file(cpath.folder, cpath.name, dir, prefix, delete_after, out, sizeof out);

    /* With RAW+JPEG the second file arrives as an event; drain events for up to ~2 s. */
    for (i = 0; i < 20 && ret >= GP_OK; i++) {
        CameraEventType type;
        void *data = NULL;
        if (gp_camera_wait_for_event(g_camera, 100, &type, &data, g_context) < GP_OK)
            break;
        if (type == GP_EVENT_FILE_ADDED && data) {
            CameraFilePath *p = data;
            download_file(p->folder, p->name, dir, prefix, delete_after, out, sizeof out);
        }
        free(data);
        if (type == GP_EVENT_TIMEOUT && i >= 3)
            break;
    }
    (*env)->ReleaseStringUTFChars(env, jdir, dir);
    if (!out[0])
        return NULL;
    return jstr(env, out);
}

/* ------------------------------------------------------------------ settings */

/* Returns { current value, choice 1, choice 2, ... } for a radio/menu setting such as
 * "iso", "shutterspeed", "aperture", "capturetarget"; null if not available. */
JNIEXPORT jobjectArray JNICALL
Java_org_cameracontroller_poc_GPhoto_getChoices(JNIEnv *env, jclass cls, jstring jkey)
{
    (void) cls;
    CameraWidget *w = NULL;
    CameraWidgetType type;
    const char *key, *cur = NULL;
    jobjectArray arr = NULL;
    int ret, n, i;

    if (!g_camera)
        return NULL;
    key = (*env)->GetStringUTFChars(env, jkey, NULL);
    ret = gp_camera_get_single_config(g_camera, key, &w, g_context);
    (*env)->ReleaseStringUTFChars(env, jkey, key);
    if (ret < GP_OK)
        return NULL;
    if (gp_widget_get_type(w, &type) == GP_OK && (type == GP_WIDGET_RADIO || type == GP_WIDGET_MENU)) {
        n = gp_widget_count_choices(w);
        gp_widget_get_value(w, &cur);
        if (n >= 0) {
            arr = (*env)->NewObjectArray(env, n + 1, (*env)->FindClass(env, "java/lang/String"), NULL);
            (*env)->SetObjectArrayElement(env, arr, 0, jstr(env, cur));
            for (i = 0; i < n; i++) {
                const char *c = NULL;
                gp_widget_get_choice(w, i, &c);
                (*env)->SetObjectArrayElement(env, arr, i + 1, jstr(env, c));
            }
        }
    }
    gp_widget_free(w);
    return arr;
}

JNIEXPORT jint JNICALL
Java_org_cameracontroller_poc_GPhoto_setConfig(JNIEnv *env, jclass cls, jstring jkey, jstring jvalue)
{
    (void) cls;
    CameraWidget *w = NULL;
    const char *key, *value;
    int ret;

    if (!g_camera)
        return GP_ERROR_BAD_PARAMETERS;
    g_last_error[0] = '\0';
    key = (*env)->GetStringUTFChars(env, jkey, NULL);
    value = (*env)->GetStringUTFChars(env, jvalue, NULL);
    ret = gp_camera_get_single_config(g_camera, key, &w, g_context);
    if (ret >= GP_OK) {
        ret = gp_widget_set_value(w, value);
        if (ret >= GP_OK)
            ret = gp_camera_set_single_config(g_camera, key, w, g_context);
        gp_widget_free(w);
    }
    if (ret < GP_OK)
        set_error(key, ret);
    else
        bridge_log('I', "set %s = %s", key, value);
    (*env)->ReleaseStringUTFChars(env, jkey, key);
    (*env)->ReleaseStringUTFChars(env, jvalue, value);
    return ret;
}

/* Driver self-test without a camera: loads the camera list (ptp2 via the ltdl shim) and the
 * port list (libusb1 iolib), and looks up the Canon EOS 5D Mark II entry. */
JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_selfTest(JNIEnv *env, jclass cls)
{
    (void) cls;
    char buf[1024];
    CameraAbilitiesList *al = NULL;
    GPPortInfoList *pl = NULL;
    int models = -1, ports = -1, idx;
    CameraAbilities a;
    char model_info[256] = "Canon EOS 5D Mark II: NOT FOUND";

    if (gp_abilities_list_new(&al) == GP_OK) {
        gp_abilities_list_load(al, NULL);
        models = gp_abilities_list_count(al);
        idx = gp_abilities_list_lookup_model(al, "Canon EOS 5D Mark II");
        if (idx >= 0 && gp_abilities_list_get_abilities(al, idx, &a) == GP_OK)
            snprintf(model_info, sizeof model_info, "%s: driver %s, USB %04x:%04x, operations 0x%x",
                     a.model, a.library, a.usb_vendor, a.usb_product, (unsigned) a.operations);
        gp_abilities_list_free(al);
    }
    if (gp_port_info_list_new(&pl) == GP_OK) {
        gp_port_info_list_load(pl);
        ports = gp_port_info_list_count(pl);
        gp_port_info_list_free(pl);
    }
    snprintf(buf, sizeof buf, "driver self-test: %d camera models, %d port entries\n%s", models, ports, model_info);
    return jstr(env, buf);
}

JNIEXPORT jstring JNICALL
Java_org_cameracontroller_poc_GPhoto_resultString(JNIEnv *env, jclass cls, jint code)
{
    (void) cls;
    return jstr(env, gp_result_as_string(code));
}
