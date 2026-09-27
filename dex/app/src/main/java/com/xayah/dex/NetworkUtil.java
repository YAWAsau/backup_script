package com.xayah.dex;

import android.content.Context;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManagerHidden;
import android.os.Build;

import com.google.gson.ExclusionStrategy;
import com.google.gson.FieldAttributes;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import java.io.File;
import java.io.InputStream;
import java.io.FileInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.rikka.tools.refine.Refine;

public class NetworkUtil {
    private static final boolean DEBUG = "1".equals(System.getenv("HIDDENAPI_DEBUG"))
            || "1".equals(System.getenv("DEX_DEBUG"));
    private static void human(String msg) { if ("1".equals(System.getenv("DEX_HUMAN_LOG"))) System.err.println("HUMAN " + msg); }
    private static void commandError(String command, Exception e) {
        System.err.println("ERROR_CODE=NETWORK_COMMAND_FAILED COMMAND=" + command
                + " REASON=" + e.getClass().getSimpleName());
        if (DEBUG) e.printStackTrace(System.err);
    }
    private static final String NETWORK_PREFIX = "network";
    private static final String NETWORK_SPLIT_SYMBOL = "_";
    private static final String[] SKIP_FIELDS = {"mNetworkSeclectionDisableCounter"};

    private static void onHelp() {
        System.out.println("NetworkUtil commands:");
        System.out.println("  help");
        System.out.println();
        System.out.println("  getNetworks");
        System.out.println("    Dump networks.");
        System.out.println();
        System.out.println("  saveNetworks");
        System.out.println("    Print all networks as JSON to standard output.");
        System.out.println();
        System.out.println("  restoreNetworks FILE");
        System.out.println("    Restore all networks from a JSON file.");
    }

    private static void onCommand(String cmd, String[] args) {
        switch (cmd) {
            case "getNetworks":
                getNetworks(args);
                break;
            case "saveNetworks":
                saveNetworks(args);
                break;
            case "restoreNetworks":
                restoreNetworks(args);
                break;
            case "validateNetworks":
                try {
                    WifiConfiguration[] n=readNetworks(args[1]); int compatible=0;
                    for(WifiConfiguration config:n)if(supportedSecurity(config))compatible++;
                    System.out.println("WIFI_VALID records="+n.length+" supported="+compatible+" unsupported="+(n.length-compatible));
                }
                catch(Exception e) { commandError("validateNetworks",e); System.exit(1); }
                break;
            case "help":
                onHelp();
                break;
            default:
                System.out.println("UNKNOWN_COMMAND " + cmd.replaceAll("[\r\n\t ]+", "_"));
                System.exit(1);
        }
    }

    public static void main(String[] args) {
        HiddenApiBypassBridge.installExemptionsOnce();
        String cmd;
        if (args != null && args.length > 0) {
            cmd = args[0];
            onCommand(cmd, args);
        } else {
            onHelp();
        }
        System.exit(0);
    }

    private static void getNetworks(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            WifiManagerHidden wifiManager = Refine.unsafeCast(ctx.getSystemService(Context.WIFI_SERVICE));
            List<WifiConfiguration> networks = wifiManager.getPrivilegedConfiguredNetworks();
            human("讀取WiFi設定成功: 共 " + networks.size() + " 筆");
            Set<Integer> networkIds = new HashSet<>();
            for (int i = 0; i < networks.size(); i++) {
                WifiConfiguration network = networks.get(i);
                int networkId = network.networkId;
                if (!networkIds.contains(networkId)) {
                    String ssid = network.SSID;
                    String preSharedKey = network.preSharedKey;
                    StringBuilder out = new StringBuilder();
                    out.append(networkId).append(" ").append(ssid);
                    if (preSharedKey != null) {
                        out.append(" ").append(preSharedKey);
                    }
                    System.out.println(out);
                    networkIds.add(networkId);
                }
            }
            System.exit(0);
        } catch (Exception e) {
            human("WiFi操作失敗: " + e.getMessage());
            commandError("getNetworks", e);
            System.exit(1);
        }
    }

    private static void saveNetworks(String[] args) {
        try {
            Context ctx = HiddenApiHelper.getContext();
            WifiManagerHidden wifiManager = Refine.unsafeCast(ctx.getSystemService(Context.WIFI_SERVICE));
            List<WifiConfiguration> networks = wifiManager.getPrivilegedConfiguredNetworks();
            Gson gson = new Gson();
            human("WiFi JSON備份成功: 共 " + networks.size() + " 筆");
            String json = gson.toJson(networks);
            // Base64 is the legacy wire format, NOT encryption or access control.
            String encoded = Base64.getEncoder().encodeToString(json.getBytes(StandardCharsets.UTF_8));
            System.out.println(encoded);
            System.exit(0);
        } catch (Exception e) {
            human("WiFi操作失敗: " + e.getMessage());
            commandError("saveNetworks", e);
            System.exit(1);
        }
    }

    public static class NetworkStrategy implements ExclusionStrategy {
        @Override
        public boolean shouldSkipField(FieldAttributes f) {
            return Arrays.asList(SKIP_FIELDS).contains(f.getName());
        }

        @Override
        public boolean shouldSkipClass(Class<?> clazz) {
            return false;
        }
    }

    private static WifiConfiguration[] readNetworks(String path) throws Exception {
        // Consume the complete bounded input before making any system changes.
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        try (InputStream input="-".equals(path)?System.in:new FileInputStream(path)) {
            byte[] buffer=new byte[8192]; int count;
            while((count=input.read(buffer))!=-1) {
                if(bytes.size()+count>16*1024*1024)throw new IllegalArgumentException("WIFI_INPUT_TOO_LARGE");
                bytes.write(buffer,0,count);
            }
        }
        String text=new String(bytes.toByteArray(),StandardCharsets.UTF_8).trim();
        // Keep existing Base64 backups and accept the author's original JSON arrays.
        String json=text.startsWith("[")?text:new String(Base64.getDecoder().decode(text),StandardCharsets.UTF_8);
        Gson gson=new GsonBuilder().addDeserializationExclusionStrategy(new NetworkStrategy()).create();
        WifiConfiguration[] configs=gson.fromJson(json,WifiConfiguration[].class);
        if(configs==null)throw new IllegalArgumentException("NULL_WIFI_ARRAY");
        for(WifiConfiguration config:configs) {
            if(config==null || config.SSID==null || config.SSID.trim().isEmpty() || config.allowedKeyManagement==null)
                throw new IllegalArgumentException("INVALID_WIFI_RECORD");
        }
        return configs;
    }

    private static boolean supportedSecurity(WifiConfiguration config) throws Exception {
        String[] known=(String[])WifiConfiguration.KeyMgmt.class.getField("strings").get(null);
        return known.length>0 && !config.allowedKeyManagement.isEmpty() && config.allowedKeyManagement.nextSetBit(known.length)<0;
    }

    private static void restoreNetworks(String[] args) {
        try {
            int status = 0;
            String jsonPath = args[1];
            Context ctx = HiddenApiHelper.getContext();
            WifiManagerHidden wifiManager = Refine.unsafeCast(ctx.getSystemService(Context.WIFI_SERVICE));
            Set<Integer> networkIds = new HashSet<>();
            try {
                WifiConfiguration[] networks = readNetworks(jsonPath);
                for (WifiConfiguration network : networks) {
                    try {
                        if(!supportedSecurity(network)) {
                            System.err.println("WIFI_SKIPPED reason=UNSUPPORTED_SECURITY"); status=1; continue;
                        }
                        int networkId = network.networkId;
                        network.networkId = -1;
                        int restoredId=wifiManager.addNetwork(network);
                        if(restoredId<0)throw new IllegalStateException("ADD_NETWORK_FAILED");
                        android.net.wifi.WifiManager manager=Refine.unsafeCast(wifiManager);
                        if(!manager.enableNetwork(restoredId,false))throw new IllegalStateException("ENABLE_NETWORK_FAILED");
                        if(Build.VERSION.SDK_INT>=30) {
                            boolean autojoin=WifiConfiguration.class.getField("allowAutojoin").getBoolean(network);
                            manager.getClass().getMethod("allowAutojoin",int.class,boolean.class).invoke(manager,restoredId,autojoin);
                        }
                        if(Build.VERSION.SDK_INT<26 && !manager.saveConfiguration())throw new IllegalStateException("SAVE_NETWORK_FAILED");
                        if (!networkIds.contains(networkId)) {
                            networkIds.add(networkId);
                            System.out.println(network.SSID + " restored");
                            human("WiFi項目已還原: " + network.SSID);
                        }
                    } catch (Exception e) {
                        human("WiFi操作失敗: " + e.getMessage());
                        commandError("restoreNetworks.item", e);
                        status = 1;
                    }

                }
            } catch (Exception e) {
                human("WiFi操作失敗: " + e.getMessage());
                commandError("restoreNetworks.payload", e);
                status = 1;
            }
            System.exit(status);
        } catch (Exception e) {
            human("WiFi操作失敗: " + e.getMessage());
            commandError("restoreNetworks", e);
            System.exit(1);
        }
    }
}
