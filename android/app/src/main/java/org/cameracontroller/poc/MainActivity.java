package org.cameracontroller.poc;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Typeface;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Proof of concept: control a Canon EOS 5D Mark II (or other PTP camera) over USB OTG with libgphoto2.
 * Connect -> summary, live view, capture + download, ISO / shutter speed / aperture.
 */
public class MainActivity extends Activity {

    private static final String ACTION_USB_PERMISSION = "org.cameracontroller.poc.USB_PERMISSION";
    private static final int CANON_VID = 0x04A9;
    private static final String[] CONFIG_KEYS = {"iso", "shutterspeed", "aperture"};
    private static final String[] CONFIG_LABELS = {"ISO", "快门", "光圈"};

    /** libgphoto2 is not thread-safe: every native call goes through this single thread. */
    private final ExecutorService gp = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());

    private UsbManager usbManager;
    private UsbDevice device;
    private UsbDeviceConnection connection;
    private volatile boolean connected;
    private volatile boolean previewOn;
    private boolean suppressSpinnerEvents;

    private TextView statusView;
    private TextView infoView;
    private ImageView imageView;
    private Button connectButton, captureButton, previewButton;
    private final Spinner[] spinners = new Spinner[CONFIG_KEYS.length];

    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        buildUi();

        IntentFilter filter = new IntentFilter();
        filter.addAction(ACTION_USB_PERMISSION);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(usbReceiver, filter);
        }

        String version;
        try {
            version = GPhoto.version();
        } catch (Throwable t) {
            version = "原生库加载失败: " + t;
        }
        appendInfo(version + "\nAndroid " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + "), "
                + Build.MANUFACTURER + " " + Build.MODEL + ", ABI " + Build.SUPPORTED_ABIS[0]);
        setStatus("请用 OTG 线连接相机并开机，然后点“连接相机”");
        gp.execute(() -> {
            String report;
            try {
                report = GPhoto.selfTest();
            } catch (Throwable t) {
                report = "driver self-test failed: " + t;
            }
            final String r = report;
            ui.post(() -> appendInfo(r));
        });
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        handleIntent(intent);
    }

    @Override
    protected void onDestroy() {
        previewOn = false;
        try {
            unregisterReceiver(usbReceiver);
        } catch (Exception ignored) {
        }
        gp.execute(GPhoto::close);
        gp.execute(() -> {
            if (connection != null) connection.close();
        });
        gp.shutdown();
        super.onDestroy();
    }

    private void handleIntent(Intent intent) {
        if (intent != null && "errorpaths".equals(intent.getStringExtra("cc_selftest"))) {
            runErrorPathSelfTest();
            return;
        }
        if (intent != null && UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(intent.getAction())) {
            UsbDevice d = getDeviceExtra(intent);
            if (d != null && !connected) {
                setStatus("检测到 USB 设备：" + describe(d));
                if (usbManager.hasPermission(d)) openDevice(d);
                else requestPermission(d);
            }
        }
    }

    // ------------------------------------------------------------------ USB

    private final BroadcastReceiver usbReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            UsbDevice d = getDeviceExtra(intent);
            if (ACTION_USB_PERMISSION.equals(action)) {
                if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false) && d != null) {
                    openDevice(d);
                } else {
                    setStatus("未获得 USB 权限，请重新点“连接相机”并选择允许");
                }
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                if (device != null && d != null && d.getDeviceName().equals(device.getDeviceName())) {
                    disconnect("相机已断开（USB 拔出或相机关机）");
                }
            }
        }
    };

    @SuppressWarnings("deprecation")
    private static UsbDevice getDeviceExtra(Intent intent) {
        if (Build.VERSION.SDK_INT >= 33) {
            return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class);
        }
        return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
    }

    /** Prefers a Canon device; otherwise any device with a still-image (PTP) interface. */
    private UsbDevice findCamera() {
        UsbDevice ptp = null;
        for (UsbDevice d : usbManager.getDeviceList().values()) {
            if (d.getVendorId() == CANON_VID) return d;
            for (int i = 0; i < d.getInterfaceCount(); i++) {
                UsbInterface itf = d.getInterface(i);
                if (itf.getInterfaceClass() == UsbConstants.USB_CLASS_STILL_IMAGE) ptp = d;
            }
        }
        return ptp;
    }

    private void requestPermission(UsbDevice d) {
        Intent intent = new Intent(ACTION_USB_PERMISSION).setPackage(getPackageName());
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE; // system adds the extras
        PendingIntent pi = PendingIntent.getBroadcast(this, 0, intent, flags);
        setStatus("请在弹出的对话框中允许访问 USB 相机");
        usbManager.requestPermission(d, pi);
    }

    private void onConnectClicked() {
        if (connected) {
            disconnect("已断开");
            return;
        }
        if (usbManager.getDeviceList().isEmpty()) {
            setStatus("没有检测到任何 USB 设备。请检查：OTG 线 / 手机是否支持 OTG（部分手机需在设置中开启 OTG）/ 相机是否开机");
            return;
        }
        UsbDevice d = findCamera();
        if (d == null) {
            StringBuilder sb = new StringBuilder("检测到 USB 设备但不是相机：");
            for (UsbDevice x : usbManager.getDeviceList().values()) sb.append("\n  ").append(describe(x));
            setStatus(sb.toString());
            return;
        }
        if (usbManager.hasPermission(d)) openDevice(d);
        else requestPermission(d);
    }

    private void openDevice(UsbDevice d) {
        if (connected) return;
        UsbDeviceConnection c = usbManager.openDevice(d);
        if (c == null) {
            setStatus("无法打开 USB 设备（可能被其他应用占用）");
            return;
        }
        device = d;
        connection = c;
        final int fd = c.getFileDescriptor();
        final String filesDir = getFilesDir().getAbsolutePath();
        setStatus("正在连接 " + describe(d) + " …");
        setButtonsEnabled(false);
        gp.execute(() -> {
            long t0 = System.currentTimeMillis();
            int r = GPhoto.open(fd, filesDir);
            if (r < 0) {
                String err = GPhoto.lastError();
                ui.post(() -> {
                    setStatus("连接失败：" + err + "\n可点“导出诊断日志”把日志发给开发者");
                    connectButton.setEnabled(true);
                    connection.close();
                    connection = null;
                    device = null;
                });
                return;
            }
            connected = true;
            String model = GPhoto.model();
            String summary = GPhoto.summary();
            final String[][] choices = new String[CONFIG_KEYS.length][];
            for (int i = 0; i < CONFIG_KEYS.length; i++) choices[i] = GPhoto.getChoices(CONFIG_KEYS[i]);
            long ms = System.currentTimeMillis() - t0;
            ui.post(() -> {
                setStatus("已连接：" + model + "（" + ms + " ms）");
                appendInfo("—— 相机信息 ——\n" + (summary == null ? GPhoto.lastError() : summary));
                for (int i = 0; i < CONFIG_KEYS.length; i++) fillSpinner(i, choices[i]);
                setButtonsEnabled(true);
                connectButton.setText("断开");
            });
        });
    }

    private void disconnect(String message) {
        connected = false;
        previewOn = false;
        gp.execute(() -> {
            GPhoto.close();
            ui.post(() -> {
                if (connection != null) connection.close();
                connection = null;
                device = null;
                setButtonsEnabled(false);
                connectButton.setEnabled(true);
                connectButton.setText("连接相机");
                previewButton.setText("实时预览");
                setStatus(message);
            });
        });
    }

    // ------------------------------------------------------------------ camera actions

    private void onCaptureClicked() {
        if (!connected) return;
        File dir = getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        if (dir == null) dir = getFilesDir();
        final File photoDir = dir;
        captureButton.setEnabled(false);
        setStatus("拍摄中…");
        gp.execute(() -> {
            long t0 = System.currentTimeMillis();
            String paths = GPhoto.capture(photoDir.getAbsolutePath());
            long ms = System.currentTimeMillis() - t0;
            if (paths == null) {
                String err = GPhoto.lastError();
                ui.post(() -> {
                    setStatus("拍摄失败：" + err + "\n（自动对焦失败时请把镜头切到 MF）");
                    captureButton.setEnabled(true);
                });
                return;
            }
            List<String> files = Arrays.asList(paths.split("\n"));
            Bitmap shown = null;
            StringBuilder sb = new StringBuilder();
            for (String p : files) {
                File f = new File(p);
                String gallery = publishToGallery(f);
                sb.append("\n  ").append(f.getName()).append(String.format(Locale.ROOT, "（%.1f MB）", f.length() / 1048576.0));
                if (gallery != null) sb.append(" → ").append(gallery);
                if (shown == null && isJpeg(p)) shown = decodeSampled(p, 2048);
            }
            final Bitmap bm = shown;
            ui.post(() -> {
                setStatus("拍摄完成（" + ms + " ms）" + sb + (bm == null ? "\nRAW 文件手机无法直接预览；想在手机上看图请把相机画质设为 JPEG" : ""));
                if (bm != null) imageView.setImageBitmap(bm);
                captureButton.setEnabled(true);
            });
        });
    }

    private void onPreviewClicked() {
        if (!connected) return;
        previewOn = !previewOn;
        previewButton.setText(previewOn ? "停止预览" : "实时预览");
        if (previewOn) {
            setStatus("实时预览中…");
            nextPreviewFrame(0, System.currentTimeMillis());
        } else {
            setStatus("预览已停止");
        }
    }

    /** One frame per task, re-queued at the end, so capture / settings can run in between. */
    private void nextPreviewFrame(final int frame, final long startMs) {
        gp.execute(() -> {
            if (!previewOn || !connected) return;
            byte[] jpeg = GPhoto.preview();
            Bitmap bm = jpeg == null ? null : BitmapFactory.decodeByteArray(jpeg, 0, jpeg.length);
            if (bm == null) {
                previewOn = false;
                String err = jpeg == null ? GPhoto.lastError() : "无法解码预览图像";
                ui.post(() -> {
                    previewButton.setText("实时预览");
                    setStatus("实时预览失败：" + err + "\n（请确认相机菜单中已启用“实时显示拍摄”）");
                });
                return;
            }
            final int n = frame + 1;
            ui.post(() -> {
                imageView.setImageBitmap(bm);
                if (n % 10 == 0) {
                    double fps = n * 1000.0 / Math.max(1, System.currentTimeMillis() - startMs);
                    setStatus(String.format(Locale.ROOT, "实时预览中… %d×%d，%.1f 帧/秒", bm.getWidth(), bm.getHeight(), fps));
                }
            });
            nextPreviewFrame(n, startMs);
        });
    }

    private void fillSpinner(int index, String[] choices) {
        Spinner sp = spinners[index];
        if (choices == null || choices.length < 2) {
            sp.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, new String[]{"（不可用）"}));
            sp.setEnabled(false);
            return;
        }
        List<String> items = new ArrayList<>(Arrays.asList(choices).subList(1, choices.length));
        int sel = items.indexOf(choices[0]);
        if (sel < 0) {
            items.add(0, choices[0]);
            sel = 0;
        }
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, items);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        suppressSpinnerEvents = true;
        sp.setAdapter(adapter);
        sp.setSelection(sel, false);
        sp.setEnabled(true);
        ui.post(() -> suppressSpinnerEvents = false);
    }

    private void onSpinnerChanged(int index, String value) {
        if (suppressSpinnerEvents || !connected) return;
        final String key = CONFIG_KEYS[index];
        gp.execute(() -> {
            int r = GPhoto.setConfig(key, value);
            String err = r < 0 ? GPhoto.lastError() : null;
            String[] fresh = GPhoto.getChoices(key);
            ui.post(() -> {
                if (err != null) {
                    toast(CONFIG_LABELS[index] + " 设置失败：" + err + "（模式转盘需在 M/Av/Tv 等创意区）");
                } else {
                    toast(CONFIG_LABELS[index] + " = " + value);
                }
                fillSpinner(index, fresh);
            });
        });
    }

    /**
     * Diagnostic (no camera needed), started with:
     * adb shell am start -n org.cameracontroller.poc/.MainActivity --es cc_selftest errorpaths
     * Feeds libgphoto2 file descriptors that are not USB devices (wrap must fail cleanly), switches
     * fds (re-wrap path), and fd -1 (no device). Every step must return an error, never crash.
     */
    private void runErrorPathSelfTest() {
        final String filesDir = getFilesDir().getAbsolutePath();
        final File bogus = new File(getCacheDir(), "not-a-usb-device");
        setStatus("错误路径自检中…");
        gp.execute(() -> {
            StringBuilder sb = new StringBuilder("—— error-path self-test ——");
            boolean ok = true;
            try {
                for (int round = 1; round <= 2; round++) {
                    try (android.os.ParcelFileDescriptor pfd = android.os.ParcelFileDescriptor.open(bogus,
                            android.os.ParcelFileDescriptor.MODE_CREATE | android.os.ParcelFileDescriptor.MODE_READ_WRITE)) {
                        int r = GPhoto.open(pfd.getFd(), filesDir);
                        sb.append("\nbogus fd #").append(round).append(" (").append(pfd.getFd()).append("): result ")
                                .append(r).append(" ").append(GPhoto.resultString(r)).append(" | ").append(GPhoto.lastError());
                        if (r >= 0) ok = false;
                        GPhoto.close();
                    }
                }
                int r = GPhoto.open(-1, filesDir);
                sb.append("\nfd -1: result ").append(r).append(" ").append(GPhoto.resultString(r)).append(" | ").append(GPhoto.lastError());
                if (r >= 0) ok = false;
                GPhoto.close();
                sb.append("\n").append(GPhoto.selfTest());
            } catch (Throwable t) {
                ok = false;
                sb.append("\nEXCEPTION: ").append(t);
            }
            sb.append(ok ? "\nERRORPATH_SELFTEST_PASS" : "\nERRORPATH_SELFTEST_FAIL");
            final String report = sb.toString();
            android.util.Log.i("CCSelfTest", report);
            ui.post(() -> {
                appendInfo(report);
                setStatus(report.endsWith("PASS") ? "错误路径自检通过" : "错误路径自检失败");
            });
        });
    }

    // ------------------------------------------------------------------ helpers

    private static boolean isJpeg(String p) {
        String l = p.toLowerCase(Locale.ROOT);
        return l.endsWith(".jpg") || l.endsWith(".jpeg");
    }

    private static Bitmap decodeSampled(String path, int maxSize) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(path, o);
        int sample = 1;
        while (Math.max(o.outWidth, o.outHeight) / sample > maxSize) sample *= 2;
        o = new BitmapFactory.Options();
        o.inSampleSize = sample;
        return BitmapFactory.decodeFile(path, o);
    }

    /** Copies the photo into Pictures/CameraController (Android 10+), so it shows up in the gallery. */
    private String publishToGallery(File f) {
        if (Build.VERSION.SDK_INT < 29) return null;
        String name = f.getName();
        String mime = isJpeg(name) ? "image/jpeg" : (name.toLowerCase(Locale.ROOT).endsWith(".cr2") ? "image/x-canon-cr2" : "image/*");
        ContentValues v = new ContentValues();
        v.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
        v.put(MediaStore.MediaColumns.MIME_TYPE, mime);
        v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/CameraController");
        ContentResolver cr = getContentResolver();
        try {
            Uri uri = cr.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
            if (uri == null) return null;
            try (InputStream in = new FileInputStream(f); OutputStream out = cr.openOutputStream(uri)) {
                byte[] buf = new byte[1 << 16];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
            return "相册/Pictures/CameraController";
        } catch (Exception e) {
            return null;
        }
    }

    private void exportLog() {
        File log = new File(getFilesDir(), "gphoto2.log");
        String text;
        try (RandomAccessFile raf = new RandomAccessFile(log, "r")) {
            long max = 200 * 1024;
            long start = Math.max(0, raf.length() - max);
            byte[] b = new byte[(int) (raf.length() - start)];
            raf.seek(start);
            raf.readFully(b);
            text = new String(b, StandardCharsets.UTF_8);
        } catch (Exception e) {
            text = "(还没有日志：请先点一次“连接相机”)";
        }
        String header = infoView.getText() + "\n\n—— 状态 ——\n" + statusView.getText() + "\n\n—— gphoto2.log ——\n";
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT, "CameraController PoC 诊断日志");
        send.putExtra(Intent.EXTRA_TEXT, header + text);
        startActivity(Intent.createChooser(send, "导出诊断日志"));
    }

    private static String describe(UsbDevice d) {
        String name = Build.VERSION.SDK_INT >= 21 && d.getProductName() != null ? d.getProductName() : d.getDeviceName();
        return String.format(Locale.ROOT, "%s [%04x:%04x]", name, d.getVendorId(), d.getProductId());
    }

    private void setStatus(String s) {
        statusView.setText(s);
    }

    private void appendInfo(String s) {
        CharSequence old = infoView.getText();
        infoView.setText(old.length() == 0 ? s : old + "\n\n" + s);
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_SHORT).show();
    }

    private void setButtonsEnabled(boolean on) {
        connectButton.setEnabled(on);
        captureButton.setEnabled(on && connected);
        previewButton.setEnabled(on && connected);
        for (Spinner s : spinners) s.setEnabled(on && connected);
    }

    // ------------------------------------------------------------------ UI (built in code, no layout XML)

    private void buildUi() {
        int pad = dp(12);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        statusView = new TextView(this);
        statusView.setTextSize(16);
        statusView.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(statusView, matchWrap());

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        connectButton = addButton(buttons, "连接相机", v -> onConnectClicked());
        captureButton = addButton(buttons, "拍照", v -> onCaptureClicked());
        previewButton = addButton(buttons, "实时预览", v -> onPreviewClicked());
        root.addView(buttons, matchWrap());

        for (int i = 0; i < CONFIG_KEYS.length; i++) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            TextView label = new TextView(this);
            label.setText(CONFIG_LABELS[i]);
            label.setMinWidth(dp(56));
            row.addView(label);
            Spinner sp = new Spinner(this);
            final int index = i;
            sp.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
                @Override
                public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                    onSpinnerChanged(index, (String) parent.getItemAtPosition(position));
                }

                @Override
                public void onNothingSelected(AdapterView<?> parent) {
                }
            });
            spinners[i] = sp;
            row.addView(sp, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            root.addView(row, matchWrap());
        }

        imageView = new ImageView(this);
        imageView.setAdjustViewBounds(true);
        imageView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        imageView.setMinimumHeight(dp(200));
        root.addView(imageView, matchWrap());

        LinearLayout tools = new LinearLayout(this);
        addButton(tools, "导出诊断日志", v -> exportLog());
        root.addView(tools, matchWrap());

        infoView = new TextView(this);
        infoView.setTypeface(Typeface.MONOSPACE);
        infoView.setTextSize(11);
        infoView.setTextIsSelectable(true);
        root.addView(infoView, matchWrap());

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentView(scroll);
        setButtonsEnabled(false);
        connectButton.setEnabled(true);
    }

    private Button addButton(LinearLayout parent, String text, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(text);
        b.setOnClickListener(l);
        parent.addView(b, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        return b;
    }

    private static LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
