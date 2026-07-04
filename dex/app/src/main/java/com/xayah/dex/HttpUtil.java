package com.xayah.dex;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class HttpUtil {

    private static void onHelp() {
        System.out.println("HttpUtil commands:");
        System.out.println("  help");
        System.out.println();
        System.out.println("  get URL");
    }

    private static void onCommand(String cmd, String[] args) {
        switch (cmd) {
            case "get":
                get(args);
                break;
            case "help":
                onHelp();
                break;
            default:
                System.out.println("Unknown command: " + cmd);
                System.exit(1);
        }
    }

    public static void main(String[] args) {
        String cmd;
        if (args != null && args.length > 0) {
            cmd = args[0];
            onCommand(cmd, args);
        } else {
            onHelp();
        }
        System.exit(0);
    }

    private static void get(String[] args) {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(args[1]);
            connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(30000);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestProperty("User-Agent", "Android-DataBackup-Dex");
            connection.setRequestProperty("Accept", "*/*");

            int code = connection.getResponseCode();
            InputStream inputStream = code >= 400 ? connection.getErrorStream() : connection.getInputStream();
            if (inputStream != null) {
                byte[] buffer = new byte[8192];
                int length;
                while ((length = inputStream.read(buffer)) != -1) {
                    System.out.write(buffer, 0, length);
                }
                inputStream.close();
            }
            System.exit(code >= 200 && code < 400 ? 0 : 1);
        } catch (Exception e) {
            e.printStackTrace(System.out);
            System.exit(1);
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }
}
