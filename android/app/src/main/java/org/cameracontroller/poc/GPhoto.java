package org.cameracontroller.poc;

/** JNI wrapper around libgphoto2 (src/main/cpp/gp_jni.c). Call from ONE thread only. */
final class GPhoto {
    static {
        System.loadLibrary("gphoto2bridge");
    }

    private GPhoto() {}

    static native String version();

    /** Opens the camera on the fd of an open UsbDeviceConnection. Returns a gphoto2 result code (>= 0 = OK). */
    static native int open(int usbFd, String filesDir);

    static native void close();

    static native String lastError();

    static native String model();

    static native String summary();

    /** One live-view frame (JPEG), or null. */
    static native byte[] preview();

    /** Takes a picture, downloads it into dir; returns saved paths separated by '\n', or null. */
    static native String capture(String dir);

    /** { current, choice1, choice2, ... } for a radio/menu setting, or null. */
    static native String[] getChoices(String key);

    static native int setConfig(String key, String value);

    static native String resultString(int code);

    /** Loads the camera / port lists without a camera; returns a short report. */
    static native String selfTest();
}
