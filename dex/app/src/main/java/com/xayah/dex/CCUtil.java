package com.xayah.dex;

import java.io.BufferedReader;
import java.io.InputStreamReader;

public class CCUtil {
    private static void human(String msg) { if ("1".equals(System.getenv("DEX_HUMAN_LOG"))) System.err.println("HUMAN " + msg); }

    private static void onHelp() {
        System.out.println("CCUtil commands:");
        System.out.println("  help");
        System.out.println();
        System.out.println("  s2t TEXT");
        System.out.println();
        System.out.println("  t2s TEXT");
        System.out.println();
        System.out.println("  twpolish TEXT");
        System.out.println();
        System.out.println("  selftest");
    }

    private static void onCommand(String cmd, String[] args) {
        switch (cmd) {
            case "s2t":
                s2t(args);
                break;
            case "t2s":
                t2s(args);
                break;
            case "twpolish":
                twPolish(args);
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

    /**
     * Simplified Chinese to Traditional Chinese (Taiwan standard + SpeedBackup glossary)
     */
    private static void s2t(String[] args) {
        if (args.length > 1) {
            try {
                String text = args[1];
                CCHelper ccHelper = new CCHelper();
                System.out.println(ccHelper.s2t(text));
                System.exit(0);
            } catch (Exception e) {
                human("繁簡轉換失敗: " + e.getMessage());
                e.printStackTrace(System.err);
                System.exit(1);
            }
        } else {
            CCHelper ccHelper = new CCHelper();
            try {
                if (System.in.available() > 0) {
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(System.in))) {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            System.out.println(ccHelper.s2t(line));
                        }
                        System.exit(0);
                    } catch (Exception e) {
                        human("繁簡轉換失敗: " + e.getMessage());
                e.printStackTrace(System.err);
                        System.exit(1);
                    }
                }
            } catch (Exception ignored) {
            }
        }
    }

    /**
     * Traditional Chinese to Simplified Chinese (SpeedBackup glossary)
     */
    private static void t2s(String[] args) {
        if (args.length > 1) {
            try {
                String text = args[1];
                CCHelper ccHelper = new CCHelper();
                System.out.println(ccHelper.t2s(text));
                System.exit(0);
            } catch (Exception e) {
                human("繁簡轉換失敗: " + e.getMessage());
                e.printStackTrace(System.err);
                System.exit(1);
            }
        } else {
            CCHelper ccHelper = new CCHelper();
            try {
                if (System.in.available() > 0) {
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(System.in))) {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            System.out.println(ccHelper.t2s(line));
                        }
                        System.exit(0);
                    } catch (Exception e) {
                        human("繁簡轉換失敗: " + e.getMessage());
                e.printStackTrace(System.err);
                        System.exit(1);
                    }
                }
            } catch (Exception ignored) {
            }
        }
    }
    /**
     * Traditional Chinese wording polish only; does not perform Simplified/Traditional conversion.
     */
    private static void twPolish(String[] args) {
        if (args.length > 1) {
            try {
                CCHelper ccHelper = new CCHelper();
                System.out.println(ccHelper.twPolish(args[1]));
                System.exit(0);
            } catch (Exception e) {
                human("繁體詞彙修正失敗: " + e.getMessage());
                e.printStackTrace(System.err);
                System.exit(1);
            }
        } else {
            CCHelper ccHelper = new CCHelper();
            try {
                if (System.in.available() > 0) {
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(System.in))) {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            System.out.println(ccHelper.twPolish(line));
                        }
                        System.exit(0);
                    } catch (Exception e) {
                        human("繁體詞彙修正失敗: " + e.getMessage());
                        e.printStackTrace(System.err);
                        System.exit(1);
                    }
                }
            } catch (Exception ignored) {
            }
        }
    }

    private static void selftest() {
        CCHelper ccHelper = new CCHelper();
        int failed = 0;
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
