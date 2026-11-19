# Builds libusb 1.0.30 + libgphoto2 2.5.34 (core, port, libusb1 iolib, ptp2 camlib) + JNI bridge
# into one shared library: libgphoto2bridge.so
cmake_minimum_required(VERSION 3.22)
project(gphoto2bridge C)

set(TP  ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(GP  ${TP}/libgphoto2-2.5.34)
set(USB ${TP}/libusb-1.0.30)
set(SHIM ${CMAKE_CURRENT_SOURCE_DIR}/ltdl-shim)

# Third-party code: keep the build log readable (errors are still reported)
set(THIRD_PARTY_FLAGS -w)

# Virtual "directories" of the built-in modules, see ltdl-shim/ltdl_shim.c
set(GP_DEFS
    _GPHOTO2_INTERNAL_CODE
    _GNU_SOURCE
    CAMLIBS="builtin-camlibs"
    IOLIBS="builtin-iolibs"
    LOCALEDIR="/nonexistent")

# ------------------------------------------------------------------ libusb
add_library(usb1 STATIC
    ${USB}/libusb/core.c
    ${USB}/libusb/descriptor.c
    ${USB}/libusb/hotplug.c
    ${USB}/libusb/io.c
    ${USB}/libusb/sync.c
    ${USB}/libusb/strerror.c
    ${USB}/libusb/os/linux_usbfs.c
    ${USB}/libusb/os/events_posix.c
    ${USB}/libusb/os/threads_posix.c
    ${USB}/libusb/os/linux_netlink.c)
target_include_directories(usb1 PRIVATE ${USB}/android ${USB}/libusb/os PUBLIC ${USB}/libusb)
target_compile_options(usb1 PRIVATE ${THIRD_PARTY_FLAGS} -pthread)
target_link_libraries(usb1 PUBLIC log)

# ------------------------------------------------------------------ libgphoto2_port + libusb1 iolib
add_library(gphoto2_port STATIC
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port-info-list.c
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port-locking.c
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port-log.c
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port-version.c
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port.c
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port-portability.c
    ${GP}/libgphoto2_port/libgphoto2_port/gphoto2-port-result.c
    ${GP}/libgphoto2_port/libusb1/libusb1.c)
target_include_directories(gphoto2_port
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/config/libgphoto2_port ${SHIM}
    PUBLIC ${GP} ${GP}/libgphoto2_port)
target_compile_definitions(gphoto2_port PRIVATE ${GP_DEFS})
target_compile_options(gphoto2_port PRIVATE ${THIRD_PARTY_FLAGS})
target_link_libraries(gphoto2_port PUBLIC usb1)

# ------------------------------------------------------------------ libgphoto2 core + ptp2 camlib
add_library(gphoto2 STATIC
    ${GP}/libgphoto2/gphoto2-abilities-list.c
    ${GP}/libgphoto2/ahd_bayer.c
    ${GP}/libgphoto2/bayer.c
    ${GP}/libgphoto2/gphoto2-camera.c
    ${GP}/libgphoto2/gphoto2-context.c
    ${GP}/libgphoto2/exif.c
    ${GP}/libgphoto2/gphoto2-file.c
    ${GP}/libgphoto2/gphoto2-filesys.c
    ${GP}/libgphoto2/gamma.c
    ${GP}/libgphoto2/jpeg.c
    ${GP}/libgphoto2/gphoto2-list.c
    ${GP}/libgphoto2/gphoto2-result.c
    ${GP}/libgphoto2/gphoto2-version.c
    ${GP}/libgphoto2/gphoto2-setting.c
    ${GP}/libgphoto2/gphoto2-widget.c
    ${GP}/camlibs/ptp2/ptp.c
    ${GP}/camlibs/ptp2/library.c
    ${GP}/camlibs/ptp2/usb.c
    ${GP}/camlibs/ptp2/ptpip.c
    ${GP}/camlibs/ptp2/config.c
    ${GP}/camlibs/ptp2/olympus-wrap.c
    ${GP}/camlibs/ptp2/chdk.c
    ${GP}/camlibs/ptp2/fujiptpip.c)
target_include_directories(gphoto2
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/config/libgphoto2 ${SHIM} ${GP}/libgphoto2 ${GP}/camlibs/ptp2)
target_compile_definitions(gphoto2 PRIVATE ${GP_DEFS})
target_compile_options(gphoto2 PRIVATE ${THIRD_PARTY_FLAGS})
target_link_libraries(gphoto2 PUBLIC gphoto2_port m)

# ------------------------------------------------------------------ JNI bridge (+ ltdl shim)
add_library(gphoto2bridge SHARED gp_jni.c ${SHIM}/ltdl_shim.c)
target_include_directories(gphoto2bridge PRIVATE ${SHIM})
target_compile_definitions(gphoto2bridge PRIVATE ${GP_DEFS})
target_compile_options(gphoto2bridge PRIVATE -Wall -Wno-unused-parameter)
target_link_libraries(gphoto2bridge gphoto2 gphoto2_port usb1 log m)
