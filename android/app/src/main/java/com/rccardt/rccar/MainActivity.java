package com.rccardt.rccar;

import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.MethodCall;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.rccardt.rccar/usb_joystick";
    private MethodChannel methodChannel;
    private UsbManagerHelper usbManagerHelper;
    //单例模式访问数据包类
    DataPackage dataPackage = DataPackage.getInstance();

    static {
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            Log.e("GlobalException", "未捕获异常: ", throwable);
        });
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        methodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        methodChannel.setMethodCallHandler(new MethodCallHandler() {
            @Override
            public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
                if (call.method.equals("initializeUsbJoystick")) {
                    usbManagerHelper = new UsbManagerHelper(MainActivity.this);
                    usbManagerHelper.registerUsbReceiver();// 检查已连接的USB设备
                    UsbManager usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
                    for (String deviceName : usbManager.getDeviceList().keySet()) {
                        UsbDevice device = usbManager.getDeviceList().get(deviceName);
                        usbManagerHelper.openUsbDevice(device);
                    }
                    result.success("USB Joystick Initialized");
                } else {
                    result.notImplemented();
                }
            }
        });



//         启动一个后台线程用于定时发送手柄数据
        new Thread(new Runnable() {
            private final Handler mainHandler = new Handler(Looper.getMainLooper());

            @Override
            public void run() {
                while (!Thread.currentThread().isInterrupted()) {
                    try {
                        Thread.sleep(100); // 每100ms发送一次数据
                        if (usbManagerHelper != null) {
                            String joystickData = dataPackage.toString(); // 发送手柄json数据
                            if (joystickData != null && !joystickData.isEmpty() && !dataPackage.isAllFieldsEmpty()) {
                                // 切换到主线程执行 invokeMethod
                                mainHandler.post(() -> methodChannel.invokeMethod("onJoystickData", joystickData));
                            }
                        }
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt(); // 重新设置中断标志
                        break;
                    }
                }
            }
        }).start();

    }

    /**
     * 手柄摇杆监听
     */
    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        if ((event.getSource() & InputDevice.SOURCE_CLASS_JOYSTICK) == InputDevice.SOURCE_CLASS_JOYSTICK) {
            if (event.getDevice() == null) {
                return super.dispatchGenericMotionEvent(event); // 设备为空直接返回
            }
            InputDevice inputDevice = event.getDevice();
            float y0 = getCenteredAxis(event, inputDevice, MotionEvent.AXIS_Y);
            // 左摇杆 Y 轴（前进/后退）
            updateToControl(y0);

            // 右摇杆 X 轴（左/右控制）
            float x1 = getCenteredAxis(event, inputDevice, MotionEvent.AXIS_Z); // 多数手柄为 AXIS_Z 表示右摇杆 X 轴
            updateRightStick(x1);

            // LT 和 RT 压力检测（模拟半按/全按）
            float ltPressure = event.getAxisValue(MotionEvent.AXIS_LTRIGGER);
            float rtPressure = event.getAxisValue(MotionEvent.AXIS_RTRIGGER);
            updateTrigger(ltPressure, rtPressure);

            //十字键
//            float hatX = event.getAxisValue(MotionEvent.AXIS_HAT_X); // -1.0 (左), 0 (中立), 1.0 (右)
//            float hatY = event.getAxisValue(MotionEvent.AXIS_HAT_Y); // -1.0 (上), 0 (中立), 1.0 (下)
//            updateDPadFromAxis(hatX, hatY);

            // 阻止事件传递给系统(防止与手机系统交互)
            return true;
        }
        return super.dispatchGenericMotionEvent(event);
    }

    private float getCenteredAxis(MotionEvent event, InputDevice device, int axis) {
        if (device == null) return 0;

        final InputDevice.MotionRange range = device.getMotionRange(axis, event.getSource());
        if (range != null) {
            final float flat = range.getFlat();
            final float value = event.getAxisValue(axis);
            if (Math.abs(value) > flat) {
                return value;
            }
        }
        return 0;
    }


//    //十字键
//    private void updateDPadFromAxis(float x, float y) {
//        final float threshold = 0.5f;
//        String direction = "";
//
//        if (y < -threshold) {
//            direction = "UP";
//        } else if (y > threshold) {
//            direction = "DOWN";
//        } else if (x < -threshold) {
//            direction = "LEFT";
//        } else if (x > threshold) {
//            direction = "RIGHT";
//        }
//        dataPackage.setUdlr(direction);
//    }



    //数据百分化并进行控制传递，左摇杆
    private void updateToControl(float y0) {
//        System.out.println(String.format("%.2f", x0));
        double y= Double.parseDouble(String.format("%.2f", y0));
        double block=0;
        if (y == y0){
            dataPackage.setJoyaqh("P");
        }
        if (y < block) { // 前进
            dataPackage.setJoyaqh("D");
        }
        if (y > block) { // 后退
            dataPackage.setJoyaqh("R");
        }

    }

    //右摇杆
    private void updateRightStick(float x1) {
        double x = Double.parseDouble(String.format("%.2f", x1));
        double block = 0;

        if (Math.abs(x) < 0.1) {
            dataPackage.setJoybzy("FXP");
        } else if (x < block) {
            dataPackage.setJoybzy("FXZ");
        } else if (x > block) {
            dataPackage.setJoybzy("FXY");
        }
    }



    /**
     * 手柄按钮监听
     */
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int keyCode = event.getKeyCode();

        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            switch (keyCode) {
                case KeyEvent.KEYCODE_BUTTON_A:
                    dataPackage.setBtnabxy("A");
                    break;
                case KeyEvent.KEYCODE_BUTTON_B:
                    dataPackage.setBtnabxy("B");
                    break;
                case KeyEvent.KEYCODE_BUTTON_X:
                    dataPackage.setBtnabxy("X");
                    break;
                case KeyEvent.KEYCODE_BUTTON_Y:
                    dataPackage.setBtnabxy("Y");
                    break;
                case KeyEvent.KEYCODE_DPAD_UP:
                    dataPackage.setUdlr("UP");
                    break;
                case KeyEvent.KEYCODE_DPAD_DOWN:
                    dataPackage.setUdlr("DOWN");
                    break;
                case KeyEvent.KEYCODE_DPAD_LEFT:
                    dataPackage.setUdlr("LEFT");
                    break;
                case KeyEvent.KEYCODE_DPAD_RIGHT:
                    dataPackage.setUdlr("RIGHT");
            }
        }
        else {
            dataPackage.setBtnabxy("");
        }

        return true; // 表示事件已被消费
    }

    /**
     * LT,RT  监听
     */
    private void updateTrigger(float ltPressure, float rtPressure) {
        // 将 0.0 ~ 1.0 转换为 0 ~ 90，共 10 个等级（每级 +10）
        //0 9 18 27 45 63 81 90
        int ltLevel = Math.min(90, (int) ((Math.max(0f, ltPressure)) * 90));
        int rtLevel = Math.min(90, (int) ((Math.max(0f, rtPressure)) * 90));

        dataPackage.setLt(ltLevel);
        dataPackage.setRt(rtLevel);
    }


}
