package com.xayah.dex;

import java.util.HashMap;

public class CCHelper {
    // Product-specific UI wording, applied after the pinned OpenCC profiles.
    private static final String[][] TW_POLISH_PHRASES = new String[][]{
            {"快閃記憶體", "硬碟"},
            {"幹淨", "乾淨"},
            {"幹擾", "干擾"},
            {"上遊", "上游"},
            {"下遊", "下游"},
            {"遞回", "遞迴"},
            {"一並", "一併"},
            {"並發數", "併發數"},
            {"並發執行", "併發執行"},
            {"並發請求", "併發請求"},
            {"並發連線", "併發連線"},
            {"並發上限", "併發上限"},
            {"並發下載", "併發下載"},
            {"並發處理", "併發處理"},
            {"並發寫入", "併發寫入"},
            {"並發讀取", "併發讀取"},
            {"並發安裝", "併發安裝"},
            {"並發任務", "併發任務"},
            {"匯整", "彙整"},
            {"匯總", "彙總"},
            {"復制", "複製"},
            {"代碼復用", "程式碼複用"},
            {"可復用", "可複用"},
            {"復用快取", "複用快取"},
            {"自籤", "自簽"},
            {"籤名", "簽名"},
            {"籤章", "簽章"},
            {"衝刷", "沖刷"},
            {"重復", "重複"},
            {"合並", "合併"},
            {"配置文件", "設定檔"},
            {"設定文件", "設定檔"},
            {"壓縮包", "壓縮檔"},
            {"配置詳細", "設定詳細"},
            {"配置遺失", "設定遺失"},
            {"配置丟失", "設定遺失"},
            {"設定丟失", "設定遺失"},
            {"自定義", "自訂"},
            {"程序", "程式"},
            {"支持", "支援"},
            {"當前", "目前"},
            {"後臺", "後台"},
            {"意誌", "意志"},
            {"配置", "設定"}
    };

    private static final String[][] T2S_PHRASES = new String[][]{
            {"认证使用者名称", "认证用户名"},
            {"配置文件", "配置文件"},
            {"设定档", "配置文件"},
            {"設定檔", "配置文件"},
            {"设置档", "配置文件"},
            {"资料夹", "文件夹"},
            {"壓縮檔", "压缩包"},
            {"压缩档", "压缩包"},
            {"资料库", "数据库"},
            {"設定詳細", "配置详细"},
            {"设定详细", "配置详细"},
            {"設定遺失", "配置丢失"},
            {"设定遗失", "配置丢失"},
            {"預設", "默认"},
            {"预设", "默认"},
            {"资料", "数据"},
            {"档案", "文件"},
            {"远端", "远程"},
            {"自訂", "自定义"},
            {"自订", "自定义"},
            {"变数", "变量"},
            {"载入", "加载"},
            {"网路", "网络"},
            {"软体", "软件"},
            {"硬体", "硬件"},
            {"萤幕", "屏幕"},
            {"储存", "保存"},
            {"目前", "当前"},
            {"连结", "链接"},
            {"回圈", "循环"},
            {"設定", "配置"},
            {"设定", "配置"}
    };

    /**
     * Taiwan vocabulary, which the pinned OpenCC profiles keep intact: they normalise the
     * script (乾/干, 髮/发) but not the words, so 串流/呼叫/清單 reached the Simplified UI as
     * Simplified glyphs with Taiwan wording. OpenCC ships the missing stage as TWPhrases and
     * runs it before the character table in tw2sp; this converter applies the same order here.
     *
     * Longest key first. Compounds stay listed explicitly (檔案 beside 檔) so a shorter entry
     * cannot split them into 文件案, and entries overlap T2S_PHRASES on purpose: whatever this
     * table already turned into mainland wording simply falls through there unchanged.
     */
    private static final String[][] TW_TERMS = new String[][]{
            {"檔案名稱", "文件名"},
            {"伺服端", "服务端"},
            {"壓縮檔", "压缩包"},
            {"映像檔", "镜像"},
            {"正規化", "规范化"},
            {"用戶端", "客户端"},
            {"設定檔", "配置文件"},
            {"串流", "流式"},
            {"套件", "软件包"},
            {"封包", "数据包"},
            {"封存", "归档"},
            {"文檔", "文档"},
            {"檔名", "文件名"},
            {"檔案", "文件"},
            {"清單", "列表"},
            {"紀錄", "记录"},
            {"逾時", "超时"},
            {"預掃", "预扫描"},
            {"檔", "文件"}
    };

    private static boolean asciiOnly(String text) {
        for (int i = 0; i < text.length(); i++) if (text.charAt(i) >= 128) return false;
        return true;
    }

    // Exact storage-info labels only: do not rename storage verbs in sentences.
    private static boolean storageLabel(String text) {
        return "閃存".equals(text) || "闪存".equals(text)
                || "快閃記憶體".equals(text) || "硬碟".equals(text)
                || "硬盘".equals(text) || "存儲".equals(text) || "存储".equals(text);
    }

    public String s2t(String text) {
        if (text == null || text.isEmpty()) return text == null ? "" : text;
        if (asciiOnly(text)) return text;
        return twPolish(text);
    }

    // Repair legacy files already damaged by the old cascading phrase replacement.
    private static final java.util.regex.Pattern REPEATED_ALGORITHM = java.util.regex.Pattern.compile("演{2,}算法");

    /** Product wording polish for already-Traditional Chinese text. */
    String twPolish(String text) {
        if (storageLabel(text)) return "硬碟";
        if (text != null) text = REPEATED_ALGORITHM.matcher(text).replaceAll("演算法");
        if (text == null || text.isEmpty()) return text == null ? "" : text;
        if (asciiOnly(text)) return text;
        return applyPhraseMap(OpenCcPhrases.convert(text, true), TW_POLISH_PHRASES);
    }

    /**
     * Traditional Chinese to Simplified Chinese
     */
    public String t2s(String text) {
        if (storageLabel(text)) return "存储";
        if (text != null) text = REPEATED_ALGORITHM.matcher(text).replaceAll("演算法");
        if (text == null || text.isEmpty()) return text == null ? "" : text;
        if (asciiOnly(text)) return text;
        // Vocabulary first, then the character table, then the project glossary - the same
        // order OpenCC uses for tw2sp. The 文件 guard below still sees the result.
        text = applyPhraseMap(text, TW_TERMS);
        // In this file-management product, 文件 is the Simplified target for
        // 檔案, not the Taiwan word for a document. Protect it before tw2sp so
        // already-localized model labels stay stable when rendered again.
        int file = text.indexOf("文件");
        if (file < 0) return applyPhraseMap(OpenCcPhrases.convert(text, false), T2S_PHRASES);
        StringBuilder converted = new StringBuilder(text.length());
        int start = 0;
        while (file >= 0) {
            converted.append(OpenCcPhrases.convert(text.substring(start, file), false)).append("文件");
            start = file + 2;
            file = text.indexOf("文件", start);
        }
        converted.append(OpenCcPhrases.convert(text.substring(start), false));
        return applyPhraseMap(converted.toString(), T2S_PHRASES);
    }

    private static final class PhraseNode {
        final HashMap<Character, PhraseNode> next = new HashMap<>();
        String value;
    }
    private static final java.util.IdentityHashMap<String[][], PhraseNode> PHRASE_TRIES = new java.util.IdentityHashMap<>();
    private static synchronized PhraseNode phraseTrie(String[][] phrases) {
        PhraseNode cached = PHRASE_TRIES.get(phrases);
        if (cached != null) return cached;
        PhraseNode root = new PhraseNode();
        // Targets are identity matches; explicit source mappings take precedence.
        for (String[] pair : phrases) insertPhrase(root, pair[1], pair[1]);
        for (String[] pair : phrases) insertPhrase(root, pair[0], pair[1]);
        PHRASE_TRIES.put(phrases, root);
        return root;
    }
    private static void insertPhrase(PhraseNode root, String key, String value) {
        if (key == null || key.isEmpty() || value == null) return;
        PhraseNode n = root;
        for (int i = 0; i < key.length(); i++) n = n.next.computeIfAbsent(key.charAt(i), ignored -> new PhraseNode());
        n.value = value;
    }
    private static String applyPhraseMap(String text, String[][] phrases) {
        if (text == null || text.isEmpty()) return text == null ? "" : text;
        if (asciiOnly(text)) return text;
        PhraseNode root = phraseTrie(phrases);
        StringBuilder out = new StringBuilder(text.length());
        for (int i = 0; i < text.length();) {
            PhraseNode n = root;
            String replacement = null;
            int end = i;
            for (int j = i; j < text.length(); j++) {
                n = n.next.get(text.charAt(j));
                if (n == null) break;
                if (n.value != null) { replacement = n.value; end = j + 1; }
            }
            if (replacement != null) { out.append(replacement); i = end; }
            else out.append(text.charAt(i++));
        }
        return out.toString();
    }
}
