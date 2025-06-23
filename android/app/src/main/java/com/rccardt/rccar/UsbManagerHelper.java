package com.rccardt.rccar;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbManager;
import android.os.Build;

import androidx.core.content.ContextCompat;

public class UsbManagerHelper {

    private Context context;
    private UsbManager usbManager;
    private UsbDevice usbDevice;
    private UsbDeviceConnection usbDeviceConnection;

    public UsbManagerHelper(Context context) {
        this.context = context;
        usbManager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
    }

    public void registerUsbReceiver() {
        IntentFilter filter = new IntentFilter();
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);

        // 适配 Android 8+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            context.registerReceiver(usbReceiver, filter);
        }
    }

    final BroadcastReceiver usbReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (action == null) return;

            if (action.equals(UsbManager.ACTION_USB_DEVICE_ATTACHED)) {
                UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                if (device != null) {
                    handleUsbDeviceAttached(device);
                }
            } else if (action.equals(UsbManager.ACTION_USB_DEVICE_DETACHED)) {
                UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
                if (device != null && device.equals(usbDevice)) {
                    handleUsbDeviceDetached(device);
                }
            }
        }
    };

    private void handleUsbDeviceAttached(UsbDevice device) {
        // 请求权限，并适配 Android 12+
        PendingIntent permissionIntent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissionIntent = PendingIntent.getBroadcast(context, 0,
                    new Intent("com.rccardt.rccar.USB_PERMISSION"),
                    PendingIntent.FLAG_IMMUTABLE);
        } else {
            permissionIntent = PendingIntent.getBroadcast(context, 0,
                    new Intent("com.rccardt.rccar.USB_PERMISSION"), PendingIntent.FLAG_IMMUTABLE);
        }

        usbManager.requestPermission(device, permissionIntent);
    }

    private void handleUsbDeviceDetached(UsbDevice device) {
        if (device != null && device.equals(usbDevice)) {
            closeUsbDevice();
        }
    }

    public void openUsbDevice(UsbDevice device) {
        if (usbManager.hasPermission(device)) {
            usbDeviceConnection = usbManager.openDevice(device);
            if (usbDeviceConnection != null) {
                usbDevice = device;
                initializeJoystickInput();
            }
        }
    }

    private void closeUsbDevice() {
        if (usbDeviceConnection != null) {
            usbDeviceConnection.close();
            usbDeviceConnection = null;
            usbDevice = null;
        }
    }

    private void initializeJoystickInput() {
        // 初始化手柄输入逻辑
    }
}
