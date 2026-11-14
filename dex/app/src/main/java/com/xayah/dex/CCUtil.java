package com.xayah.dex;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.BufferedWriter;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;

public class CCUtil {
    private static void human(String msg) { if ("1".equals(System.getenv("DEX_HUMAN_LOG"))) System.err.println("HUMAN " + msg); }

    private static void onHelp() {
        System.out.println("CCUtil commands:");
        System.out.println("  help");
        System.out.println();
        System.out.println("  s2t TEXT");
        System.out.println("  s2t-script (stdin; exact script-line restoration)");
        System.out.println();
        System.out.println("  t2s TEXT");
        System.out.println();
        System.out.println("  twpolish TEXT");
        System.out.println();
        System.out.println("  selftest");
    }

    private static void onCommand(String cmd, String[] args) {
        switch (cmd) {
            case "s2t-script":
            case "s2t":
                convert(cmd, args);
                break;
            case "t2s":
                convert(cmd, args);
                break;
            case "twpolish":
                convert(cmd, args);
                break;
            case "selftest":
                selftest();
                break;
            case "help":
                onHelp();
                break;
            default:
                System.out.println("UNKNOWN_COMMAND " + cmd.replaceAll("[\r\n\t ]+", "_"));
                human("繁簡轉換失敗: 未知指令 " + cmd);
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

    // One helper and buffered UTF-8 streams for the entire input, never a process per line.
    private static void convert(String mode, String[] args) {
        try {
            CCHelper helper = new CCHelper();
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8), 65536);
            if (args.length > 1) {
                writer.write(convertLine(helper, mode, args[1]));
                writer.write('\n');
            } else {
                BufferedReader reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8), 65536);
                String line;
                while ((line = reader.readLine()) != null) {
                    writer.write(convertLine(helper, mode, line));
                    writer.write('\n');
                }
            }
            writer.flush();
            if (System.out.checkError()) throw new java.io.IOException("translation output failed");
        } catch (Exception e) {
            human("繁簡轉換失敗: " + e.getMessage());
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static String convertLine(CCHelper helper, String mode, String text) {
        switch (mode) {
            case "s2t-script": return ScriptRoundTrip.restore(helper.s2t(text));
            case "s2t": return helper.s2t(text);
            case "t2s": return helper.t2s(text);
            default: return helper.twPolish(text);
        }
    }

    private static void selftest() {
        CCHelper ccHelper = new CCHelper();
        int failed = 0;
        failed += check("TW storage", "硬碟", ccHelper.s2t("闪存"));
        failed += check("TW storage repeated", "硬碟", ccHelper.s2t(ccHelper.s2t("快閃記憶體")));
        for (String label : new String[]{"閃存", "闪存", "快閃記憶體", "硬碟", "硬盘", "存儲", "存储"}) {
            failed += check("TW storage alias " + label, "硬碟", ccHelper.s2t(label));
            failed += check("CN storage alias " + label, "存储", ccHelper.t2s(label));
            failed += check("storage switch " + label, "硬碟", ccHelper.s2t(ccHelper.t2s(label)));
        }
        failed += check("storage sentence", "儲存空間", ccHelper.s2t("存储空间"));
        failed += check("S2T 默认", "預設", ccHelper.s2t("默认"));
        failed += check("S2T 文件夹", "資料夾", ccHelper.s2t("文件夹"));
        failed += check("S2T 认证用户名", "認證使用者名稱", ccHelper.s2t("认证用户名"));
        failed += check("S2T 日志", "日誌", ccHelper.s2t("日志"));
        failed += check("S2T 意志", "意志", ccHelper.s2t("意志"));
        failed += check("S2T 回圈", "迴圈", ccHelper.s2t("回圈"));
        failed += check("S2T 重复", "重複", ccHelper.s2t("重复"));
        failed += check("S2T 合并", "合併", ccHelper.s2t("合并"));
        failed += check("TW 自定義默認文件", "自訂預設檔案", ccHelper.twPolish("自定義默認文件"));
        failed += check("TW 重復合並", "重複合併", ccHelper.twPolish("重復合並"));
        failed += check("T2S 資料夾", "文件夹", ccHelper.t2s("資料夾"));
        failed += check("T2S 使用者", "用户", ccHelper.t2s("使用者"));
        failed += check("T2S 迴圈", "循环", ccHelper.t2s("迴圈"));
        failed += check("T2S 重複", "重复", ccHelper.t2s("重複"));
        failed += check("T2S 合併", "合并", ccHelper.t2s("合併"));
        failed += check("T2S repeat folder", "打开文件夹", ccHelper.t2s(ccHelper.t2s("開啟資料夾")));
        failed += check("T2S repeat config", "配置文件", ccHelper.t2s(ccHelper.t2s("設定檔")));
        failed += check("T2S document", "文档", ccHelper.t2s("文檔"));
        failed += check("S2T regional terms", "軟體 網路 滑鼠 影片 記憶體", ccHelper.s2t("软件 网络 鼠标 视频 内存"));
        failed += check("T2S regional terms", "软件 网络 鼠标 视频 内存", ccHelper.t2s("軟體 網路 滑鼠 影片 記憶體"));
        // TW_TERMS: Taiwan wording the tw2sp profiles still leave behind.
        failed += check("T2S 串流", "流式上传", ccHelper.t2s("串流上傳"));
        failed += check("T2S 遠端清單", "远程列表", ccHelper.t2s("遠端清單"));
        failed += check("T2S 紀錄", "记录", ccHelper.t2s("紀錄"));
        failed += check("T2S 逾時", "超时", ccHelper.t2s("逾時"));
        failed += check("T2S 預掃", "预扫描", ccHelper.t2s("預掃"));
        failed += check("T2S 正規化", "规范化", ccHelper.t2s("正規化"));
        failed += check("T2S 伺服端", "服务端", ccHelper.t2s("伺服端"));
        failed += check("T2S 封存", "归档", ccHelper.t2s("封存"));
        failed += check("T2S 套件", "软件包", ccHelper.t2s("套件"));
        failed += check("T2S 封包", "数据包", ccHelper.t2s("封包"));
        failed += check("T2S 原檔", "原文件", ccHelper.t2s("原檔"));
        failed += check("T2S 備份檔案", "备份文件", ccHelper.t2s("備份檔案"));
        failed += check("T2S 文檔", "文档", ccHelper.t2s("文檔"));
        failed += check("T2S 非串流檔案處理方式", "非流式文件处理方式", ccHelper.t2s("非串流檔案處理方式"));
        if (failed == 0) {
            System.out.println("CCUTIL_SELFTEST_OK cchelper.table_refresh.v1 zh_tw_polish.v1 repeat_merge_fix.v1");
            System.exit(0);
        }
        System.out.println("CCUTIL_SELFTEST_FAILED count=" + failed);
        System.exit(1);
    }

    private static int check(String name, String expected, String actual) {
        if (expected.equals(actual)) {
            System.out.println("OK " + name + " => " + actual);
            return 0;
        }
        System.out.println("FAIL " + name + " expected=" + expected + " actual=" + actual);
        return 1;
    }

}
