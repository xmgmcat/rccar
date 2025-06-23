package com.rccardt.rccar;

//import com.alibaba.fastjson.JSONObject;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * 数据包类
 * 单例模式确保一个类只有一个实例，并提供一个全局访问点。
 */
public class DataPackage {
    private static DataPackage instance;

    @Override
    public String toString() {
        JSONObject jsonObject = new JSONObject();
        try {
            jsonObject.put("joyaqh", joyaqh);
            jsonObject.put("joybzy", joybzy);
            jsonObject.put("btnabxy", btnabxy);
            jsonObject.put("udlr", udlr);
            jsonObject.put("lt", lt);
            jsonObject.put("rt", rt);
        } catch (JSONException e) {
            throw new RuntimeException(e);
        }
        return jsonObject.toString();
    }


    private String joyaqh = "";
    private String joybzy = "";
    private String btnabxy =  "";
    private String udlr="";
    private int lt=0;
    private int rt=0;

    public static void setInstance(DataPackage instance) {
        DataPackage.instance = instance;
    }

    public String getJoyaqh() {
        return joyaqh;
    }

    public void setJoyaqh(String joyaqh) {
        this.joyaqh = joyaqh;
    }

    public String getJoybzy() {
        return joybzy;
    }

    public void setJoybzy(String joybzy) {
        this.joybzy = joybzy;
    }

    public String getBtnabxy() {
        return btnabxy;
    }

    public void setBtnabxy(String btnabxy) {
        this.btnabxy = btnabxy;
    }


    public String getUdlr() {
        return udlr;
    }

    public void setUdlr(String udlr) {
        this.udlr = udlr;
    }


    public float getLt() {
        return lt;
    }

    public void setLt(int lt) {
        this.lt = lt;
    }

    public int getRt() {
        return rt;
    }

    public void setRt(int rt) {
        this.rt = rt;
    }

    // 无参构造函数
    public DataPackage() {
    }

    // 有参构造函数
    public DataPackage(String joyaqh, String joybzy, String btnabxy, String udlr, int lt, int rt) {
        this.joyaqh = joyaqh;
        this.joybzy = joybzy;
        this.btnabxy = btnabxy;
        this.udlr = udlr;
        this.lt = lt;
        this.rt = rt;
    }

    public static synchronized DataPackage getInstance() {
        if (instance == null) {
            instance = new DataPackage();
        }
        return instance;
    }

    /**
     * 判断所有字段是否为空或0
     */
    boolean isAllFieldsEmpty() {
        return (joyaqh == null || joyaqh.isEmpty()) &&
                (joybzy == null || joybzy.isEmpty()) &&
                (btnabxy == null || btnabxy.isEmpty()) &&
                (udlr == null || udlr.isEmpty()) &&
                lt == 0 &&
                rt == 0;
    }



}
