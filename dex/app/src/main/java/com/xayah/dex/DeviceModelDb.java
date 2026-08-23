package com.xayah.dex;

import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Dex-builtin device model name database.
 *
 * r393: generated from the full uploaded tools/Device_List source with no
 * project override block. Runtime no longer reads or downloads tools/Device_List;
 * updating model names requires regenerating this file and rebuilding classes.dex.
 *
 * Source lines: 4368
 * Imported entries: 4364
 * Source SHA-256: 894bc0df1e63db747a61a208ae139c3a22e5660519147a3b7574febc325de7ea
 */
final class DeviceModelDb {
    static final String DB_VERSION = "r393-20260822-pure-device-list-import";
    static final int ENTRY_COUNT = 4364;
    static final int SOURCE_LINE_COUNT = 4368;
    static final String SOURCE_SHA256 = "894bc0df1e63db747a61a208ae139c3a22e5660519147a3b7574febc325de7ea";

    static final class Entry {
        final String modelKey;
        final String marketName;
        final String marketNameZh;
        final String maker;
        final String source;

        Entry(String modelKey, String marketName, String marketNameZh, String maker, String source) {
            this.modelKey = modelKey == null ? "" : modelKey;
            this.marketName = marketName == null ? "" : marketName;
            this.marketNameZh = marketNameZh == null ? "" : marketNameZh;
            this.maker = maker == null ? "" : maker;
            this.source = source == null ? "" : source;
        }
    }

    static final class Match {
        final Entry entry;
        final String source;
        final String confidence;
        final String matchedKey;
        final String matchedField;

        Match(Entry entry, String source, String confidence, String matchedKey, String matchedField) {
            this.entry = entry;
            this.source = source;
            this.confidence = confidence;
            this.matchedKey = matchedKey;
            this.matchedField = matchedField;
        }
    }

    private static final Map<String, Entry> BY_KEY = build();

    private DeviceModelDb() {}

    private static Map<String, Entry> build() {
        Map<String, Entry> m = new HashMap<>(5833);
        fill0(m);
        fill1(m);
        fill2(m);
        fill3(m);
        fill4(m);
        fill5(m);
        fill6(m);
        fill7(m);
        fill8(m);
        fill9(m);
        fill10(m);
        fill11(m);
        fill12(m);
        fill13(m);
        fill14(m);
        fill15(m);
        fill16(m);
        fill17(m);
        fill18(m);
        fill19(m);
        fill20(m);
        fill21(m);
        fill22(m);
        fill23(m);
        fill24(m);
        return Collections.unmodifiableMap(m);
    }

    static int entryCount() { return ENTRY_COUNT; }
    static int sourceLineCount() { return SOURCE_LINE_COUNT; }

    private static void fill0(Map<String, Entry> m) {
        put(m, "MI-ONE PLUS", "小米 1 聯通版", "小米 1 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L1
        put(m, "MI-ONE C1", "小米 1 電信版", "小米 1 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L2
        put(m, "MI-ONE", "小米 1 青春版", "小米 1 青春版", "Xiaomi", "device_list_full_import"); // Device_List:L3
        put(m, "2012051", "小米 1S 聯通版", "小米 1S 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L4
        put(m, "2012053", "小米 1S 電信版", "小米 1S 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L5
        put(m, "2012052", "小米 1S 青春版", "小米 1S 青春版", "Xiaomi", "device_list_full_import"); // Device_List:L6
        put(m, "2012061", "小米 2 聯通版", "小米 2 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L7
        put(m, "2012062", "小米 2 電信版", "小米 2 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L8
        put(m, "2013012", "小米 2S 聯通版", "小米 2S 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L9
        put(m, "2013021", "小米 2S 電信版", "小米 2S 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L10
        put(m, "2012121", "小米 2A 聯通版", "小米 2A 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L11
        put(m, "2013061", "小米 3 移動版", "小米 3 移動版", "Xiaomi", "device_list_full_import"); // Device_List:L12
        put(m, "2013062", "小米 3 聯通版", "小米 3 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L13
        put(m, "2013063", "小米 3 電信版", "小米 3 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L14
        put(m, "2014215", "小米 4 聯通 3G 版", "小米 4 聯通 3G 版", "Xiaomi", "device_list_full_import"); // Device_List:L15
        put(m, "2014218", "小米 4 電信 3G 版", "小米 4 電信 3G 版", "Xiaomi", "device_list_full_import"); // Device_List:L16
        put(m, "2014216", "小米 4 移動 4G 版", "小米 4 移動 4G 版", "Xiaomi", "device_list_full_import"); // Device_List:L17
        put(m, "2014719", "小米 4 聯通 4G 版", "小米 4 聯通 4G 版", "Xiaomi", "device_list_full_import"); // Device_List:L18
        put(m, "2014716", "小米 4 電信 4G 版", "小米 4 電信 4G 版", "Xiaomi", "device_list_full_import"); // Device_List:L19
        put(m, "2014726", "小米 4 電信 4G 合約版", "小米 4 電信 4G 合約版", "Xiaomi", "device_list_full_import"); // Device_List:L20
        put(m, "2015015", "小米 4i 國際版", "小米 4i 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L21
        put(m, "2015561", "小米 4c 全網通版", "小米 4c 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L22
        put(m, "2015562", "小米 4c 移動合約版", "小米 4c 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L23
        put(m, "2015911", "小米 4S", "小米 4S", "Xiaomi", "device_list_full_import"); // Device_List:L24
        put(m, "2015201", "小米 5 標準版", "小米 5 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L25
        put(m, "2015628", "小米 5 高配版 / 尊享版", "小米 5 高配版 / 尊享版", "Xiaomi", "device_list_full_import"); // Device_List:L26
        put(m, "2015105", "小米 5 國際版", "小米 5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L27
        put(m, "2015711", "小米 5s", "小米 5s", "Xiaomi", "device_list_full_import"); // Device_List:L28
        put(m, "2016070", "小米 5s Plus", "小米 5s Plus", "Xiaomi", "device_list_full_import"); // Device_List:L29
        put(m, "2016089", "小米 5c", "小米 5c", "Xiaomi", "device_list_full_import"); // Device_List:L30
        put(m, "MDE2", "小米 5X 全網通版", "小米 5X 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L31
        put(m, "MDT2", "小米 5X 移動 4G+ 版", "小米 5X 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L32
        put(m, "MCE16", "小米 6 全網通版", "小米 6 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L33
        put(m, "MCT1", "小米 6 移動 4G+ 版", "小米 6 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L34
        put(m, "M1804D2SE", "小米 6X 全網通版", "小米 6X 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L35
        put(m, "M1804D2ST", "小米 6X 移動 4G+ 版", "小米 6X 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L36
        put(m, "M1804D2SC", "小米 6X 聯通電信定制版", "小米 6X 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L37
        put(m, "M1803E1A", "小米 8 全網通版", "小米 8 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L38
        put(m, "M1803E1T", "小米 8 移動 4G+ 版", "小米 8 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L39
        put(m, "M1803E1C", "小米 8 聯通電信定制版", "小米 8 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L40
        put(m, "M1807E8S", "小米 8 透明探索版", "小米 8 透明探索版", "Xiaomi", "device_list_full_import"); // Device_List:L41
        put(m, "M1807E8A", "小米 8 螢幕指紋版", "小米 8 螢幕指紋版", "Xiaomi", "device_list_full_import"); // Device_List:L42
        put(m, "M1805E2A", "小米 8 SE", "小米 8 SE", "Xiaomi", "device_list_full_import"); // Device_List:L43
        put(m, "M1808D2TE", "小米 8 青春版 全網通版", "小米 8 青春版 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L44
        put(m, "M1808D2TT", "小米 8 青春版 移動 4G+ 版", "小米 8 青春版 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L45
        put(m, "M1808D2TC", "小米 8 青春版 聯通電信定制版", "小米 8 青春版 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L46
        put(m, "M1808D2TG", "小米 8 Lite 國際版", "小米 8 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L47
        put(m, "M1902F1A", "小米 9 全網通版", "小米 9 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L48
        put(m, "M1902F1T", "小米 9 移動 4G+ 版", "小米 9 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L49
        put(m, "M1902F1C", "小米 9 聯通電信定制版", "小米 9 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L50
        put(m, "M1902F1G", "小米 9 國際版", "小米 9 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L51
        put(m, "M1908F1XE", "小米 9 Pro 5G", "小米 9 Pro 5G", "Xiaomi", "device_list_full_import"); // Device_List:L52
        put(m, "M1903F2A", "小米 9 SE 國行版", "小米 9 SE 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L53
        put(m, "M1903F2G", "小米 9 SE 國際版", "小米 9 SE 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L54
        put(m, "M1903F10G", "小米 9T 國際版", "小米 9T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L55
        put(m, "M1903F11G", "小米 9T Pro 國際版", "小米 9T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L56
        put(m, "M1904F3BG", "小米 9 Lite 國際版", "小米 9 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L57
        put(m, "M2001J2C", "小米 10 國行版", "小米 10 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L58
        put(m, "M2001J2G", "小米 10 國際版", "小米 10 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L59
        put(m, "M2001J2I", "小米 10 印度版", "小米 10 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L60
        put(m, "M2001J1C", "小米 10 Pro 國行版", "小米 10 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L61
        put(m, "M2001J1G", "小米 10 Pro 國際版", "小米 10 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L62
        put(m, "M2002J9E", "小米 10 青春版 國行版", "小米 10 青春版 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L63
        put(m, "M2002J9G", "小米 10 Lite 國際版", "小米 10 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L64
        put(m, "M2002J9S", "小米 10 Lite 韓國版", "小米 10 Lite 韓國版", "Xiaomi", "device_list_full_import"); // Device_List:L65
        put(m, "XIG01", "小米 10 Lite 日本版 (KDDI)", "小米 10 Lite 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L66
        put(m, "M2007J1SC", "小米 10 至尊紀念版", "小米 10 至尊紀念版", "Xiaomi", "device_list_full_import"); // Device_List:L67
        put(m, "M2007J3SY", "小米 10T 國際版", "小米 10T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L68
        put(m, "M2007J3SP", "小米 10T 印度版", "小米 10T 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L69
        put(m, "M2007J3SG", "小米 10T Pro 國際版", "小米 10T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L70
        put(m, "M2007J3SI", "小米 10T Pro 印度版", "小米 10T Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L71
        put(m, "M2007J17G", "小米 10T Lite 國際版", "小米 10T Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L72
        put(m, "M2007J17I", "小米 10i 印度版", "小米 10i 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L73
        put(m, "M2102J2SC", "小米 10S", "小米 10S", "Xiaomi", "device_list_full_import"); // Device_List:L74
        put(m, "M2011K2C", "小米 11 國行版", "小米 11 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L75
        put(m, "M2011K2G", "小米 11 國際版", "小米 11 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L76
        put(m, "M2102K1AC", "小米 11 Pro", "小米 11 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L77
        put(m, "M2102K1C", "小米 11 Ultra 國行版", "小米 11 Ultra 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L78
        put(m, "M2102K1G", "小米 11 Ultra 國際版", "小米 11 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L79
        put(m, "M2101K9C", "小米 11 青春版 國行版", "小米 11 青春版 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L80
        put(m, "M2101K9G", "小米 11 Lite 5G 國際版", "小米 11 Lite 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L81
        put(m, "M2101K9R", "小米 11 Lite 5G 日本版", "小米 11 Lite 5G 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L82
        put(m, "M2101K9AG", "小米 11 Lite 4G 國際版", "小米 11 Lite 4G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L83
        put(m, "M2101K9AI", "小米 11 Lite 4G 印度版", "小米 11 Lite 4G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L84
        put(m, "2107119DC", "Xiaomi 11 青春活力版 國行版", "Xiaomi 11 青春活力版 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L85
        put(m, "2109119DG", "Xiaomi 11 Lite 5G NE 國際版", "Xiaomi 11 Lite 5G NE 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L86
        put(m, "2109119DI", "Xiaomi 11 Lite NE 5G 印度版", "Xiaomi 11 Lite NE 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L87
        put(m, "M2012K11G", "小米 11i 國際版", "小米 11i 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L88
        put(m, "M2012K11AI", "小米 11X 印度版", "小米 11X 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L89
        put(m, "M2012K11I", "小米 11X Pro 印度版", "小米 11X Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L90
        put(m, "21081111RG", "Xiaomi 11T 國際版", "Xiaomi 11T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L91
        put(m, "2107113SG", "Xiaomi 11T Pro 國際版", "Xiaomi 11T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L92
        put(m, "2107113SI", "Xiaomi 11T Pro 印度版", "Xiaomi 11T Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L93
        put(m, "2107113SR", "Xiaomi 11T Pro 日本版", "Xiaomi 11T Pro 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L94
        put(m, "21091116I", "Xiaomi 11i 印度版", "Xiaomi 11i 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L95
        put(m, "21091116UI", "Xiaomi 11i HyperCharge 印度版", "Xiaomi 11i HyperCharge 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L96
        put(m, "2201123C", "Xiaomi 12 國行版", "Xiaomi 12 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L97
        put(m, "2201123G", "Xiaomi 12 國際版", "Xiaomi 12 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L98
        put(m, "2112123AC", "Xiaomi 12X 國行版", "Xiaomi 12X 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L99
        put(m, "2112123AG", "Xiaomi 12X 國際版", "Xiaomi 12X 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L100
        put(m, "2201122C", "Xiaomi 12 Pro 國行版", "Xiaomi 12 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L101
        put(m, "2201122G", "Xiaomi 12 Pro 國際版", "Xiaomi 12 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L102
        put(m, "2207122MC", "Xiaomi 12 Pro 天璣版", "Xiaomi 12 Pro 天璣版", "Xiaomi", "device_list_full_import"); // Device_List:L103
        put(m, "2203129G", "Xiaomi 12 Lite 國際版", "Xiaomi 12 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L104
        put(m, "2203129I", "Xiaomi 12 Lite 印度版", "Xiaomi 12 Lite 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L105
        put(m, "2206123SC", "Xiaomi 12S", "Xiaomi 12S", "Xiaomi", "device_list_full_import"); // Device_List:L106
        put(m, "2206122SC", "Xiaomi 12S Pro", "Xiaomi 12S Pro", "Xiaomi", "device_list_full_import"); // Device_List:L107
        put(m, "2203121C", "Xiaomi 12S Ultra", "Xiaomi 12S Ultra", "Xiaomi", "device_list_full_import"); // Device_List:L108
        put(m, "22071212AG", "Xiaomi 12T 國際版", "Xiaomi 12T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L109
        put(m, "22081212UG", "Xiaomi 12T Pro 國際版", "Xiaomi 12T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L110
        put(m, "22200414R", "Xiaomi 12T Pro 日本版 (無鎖)", "Xiaomi 12T Pro 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L111
        put(m, "A201XM", "Xiaomi 12T Pro 日本版 (SoftBank)", "Xiaomi 12T Pro 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L112
        put(m, "2211133C", "Xiaomi 13 國行版", "Xiaomi 13 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L113
        put(m, "2211133G", "Xiaomi 13 國際版", "Xiaomi 13 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L114
        put(m, "2210132C", "Xiaomi 13 Pro 國行版", "Xiaomi 13 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L115
        put(m, "2210132G", "Xiaomi 13 Pro 國際版", "Xiaomi 13 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L116
        put(m, "2304FPN6DC", "Xiaomi 13 Ultra 國行版", "Xiaomi 13 Ultra 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L117
        put(m, "2304FPN6DG", "Xiaomi 13 Ultra 國際版", "Xiaomi 13 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L118
        put(m, "2210129SG", "Xiaomi 13 Lite 國際版", "Xiaomi 13 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L119
        put(m, "2306EPN60G", "Xiaomi 13T 國際版", "Xiaomi 13T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L120
        put(m, "2306EPN60R", "Xiaomi 13T 日本版 (無鎖)", "Xiaomi 13T 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L121
        put(m, "XIG04", "Xiaomi 13T 日本版 (KDDI)", "Xiaomi 13T 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L122
        put(m, "23078PND5G", "Xiaomi 13T Pro 國際版", "Xiaomi 13T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L123
        put(m, "23088PND5R", "Xiaomi 13T Pro 日本版 (無鎖)", "Xiaomi 13T Pro 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L124
        put(m, "A301XM", "Xiaomi 13T Pro 日本版 (SoftBank)", "Xiaomi 13T Pro 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L125
        put(m, "23127PN0CC", "Xiaomi 14 國行版", "Xiaomi 14 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L126
        put(m, "23127PN0CG", "Xiaomi 14 國際版", "Xiaomi 14 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L127
        put(m, "23116PN5BC", "Xiaomi 14 Pro / Xiaomi 14 Pro 鈦金屬版", "Xiaomi 14 Pro / Xiaomi 14 Pro 鈦金屬版", "Xiaomi", "device_list_full_import"); // Device_List:L128
        put(m, "2311BPN23C", "Xiaomi 14 Pro 鈦金屬版 (衛星通訊)", "Xiaomi 14 Pro 鈦金屬版 (衛星通訊)", "Xiaomi", "device_list_full_import"); // Device_List:L129
        put(m, "24031PN0DC", "Xiaomi 14 Ultra 國行版", "Xiaomi 14 Ultra 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L130
        put(m, "24030PN60G", "Xiaomi 14 Ultra 國際版", "Xiaomi 14 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L131
        put(m, "24053PY09I", "Xiaomi 14 Civi 印度版", "Xiaomi 14 Civi 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L132
        put(m, "2406APNFAG", "Xiaomi 14T 國際版", "Xiaomi 14T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L133
        put(m, "XIG07", "Xiaomi 14T 日本版 (KDDI)", "Xiaomi 14T 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L134
        put(m, "2407FPN8EG", "Xiaomi 14T Pro 國際版", "Xiaomi 14T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L135
        put(m, "2407FPN8ER", "Xiaomi 14T Pro 日本版 (無鎖)", "Xiaomi 14T Pro 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L136
        put(m, "XIG06", "Xiaomi 14T Pro 日本版 (KDDI)", "Xiaomi 14T Pro 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L137
        put(m, "A402XM", "Xiaomi 14T Pro 日本版 (SoftBank)", "Xiaomi 14T Pro 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L138
        put(m, "24129PN74C", "Xiaomi 15 國行版", "Xiaomi 15 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L139
        put(m, "24129PN74G", "Xiaomi 15 國際版", "Xiaomi 15 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L140
        put(m, "24129PN74I", "Xiaomi 15 印度版", "Xiaomi 15 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L141
        put(m, "2410DPN6CC", "Xiaomi 15 Pro", "Xiaomi 15 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L142
        put(m, "25019PNF3C", "Xiaomi 15 Ultra 國行版", "Xiaomi 15 Ultra 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L143
        put(m, "25010PN30C", "Xiaomi 15 Ultra 雙衛星版 國行版", "Xiaomi 15 Ultra 雙衛星版 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L144
        put(m, "25010PN30G", "Xiaomi 15 Ultra 國際版", "Xiaomi 15 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L145
        put(m, "25010PN30I", "Xiaomi 15 Ultra 印度版", "Xiaomi 15 Ultra 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L146
        put(m, "25042PN24C", "Xiaomi 15S Pro", "Xiaomi 15S Pro", "Xiaomi", "device_list_full_import"); // Device_List:L147
        put(m, "25069PTEBG", "Xiaomi 15T 國際版", "Xiaomi 15T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L148
        put(m, "2506BPN68G", "Xiaomi 15T Pro 國際版", "Xiaomi 15T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L149
        put(m, "2506BPN68R", "Xiaomi 15T Pro 日本版 (無鎖)", "Xiaomi 15T Pro 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L150
        put(m, "25113PN0EC", "Xiaomi 17 國行版", "Xiaomi 17 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L151
        put(m, "25113PN0EG", "Xiaomi 17 國際版", "Xiaomi 17 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L152
        put(m, "25113PN0EI", "Xiaomi 17 印度版", "Xiaomi 17 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L153
        put(m, "25098PN5AC", "Xiaomi 17 Pro", "Xiaomi 17 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L154
        put(m, "2509FPN0BC", "Xiaomi 17 Pro Max", "Xiaomi 17 Pro Max", "Xiaomi", "device_list_full_import"); // Device_List:L155
        put(m, "2512BPNDAC", "Xiaomi 17 Ultra 國行版 / Xiaomi 17 Ultra by Leica 國行版 (非衛星)", "Xiaomi 17 Ultra 國行版 / Xiaomi 17 Ultra by Leica 國行版 (非衛星)", "Xiaomi", "device_list_full_import"); // Device_List:L156
        put(m, "2512BPNDAG", "Xiaomi 17 Ultra 國際版", "Xiaomi 17 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L157
        put(m, "2512BPNDAI", "Xiaomi 17 Ultra 印度版", "Xiaomi 17 Ultra 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L158
        put(m, "25128PNA1C", "Xiaomi 17 Ultra by Leica 國行版 (衛星通訊)", "Xiaomi 17 Ultra by Leica 國行版 (衛星通訊)", "Xiaomi", "device_list_full_import"); // Device_List:L159
        put(m, "25128PNA1G", "Leica Leitzphone powered by Xiaomi 國際版", "Leica Leitzphone powered by Xiaomi 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L160
        put(m, "2605EPN8EC", "Xiaomi 17 Max", "Xiaomi 17 Max", "Xiaomi", "device_list_full_import"); // Device_List:L161
        put(m, "M531DA", "Xiaomi 17T 國行版", "Xiaomi 17T 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L162
        put(m, "2602DPT53G", "Xiaomi 17T 國際版", "Xiaomi 17T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L163
        put(m, "2602DPT53I", "Xiaomi 17T 印度版", "Xiaomi 17T 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L164
        put(m, "M025EC", "Xiaomi 17T Pro 國行版", "Xiaomi 17T Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L165
        put(m, "2602EPTC0G", "Xiaomi 17T Pro 國際版", "Xiaomi 17T Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L166
        put(m, "2602EPTC0R", "Xiaomi 17T Pro 日本版 (無鎖)", "Xiaomi 17T Pro 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L167
        put(m, "2014616", "小米 Note 雙網通版", "小米 Note 雙網通版", "Xiaomi", "device_list_full_import"); // Device_List:L168
        put(m, "2014619", "小米 Note 全網通版", "小米 Note 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L169
        put(m, "2014618", "小米 Note 移動合約版", "小米 Note 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L170
        put(m, "2014617", "小米 Note 聯通合約版", "小米 Note 聯通合約版", "Xiaomi", "device_list_full_import"); // Device_List:L171
        put(m, "2015011", "小米 Note 國際版", "小米 Note 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L172
        put(m, "2015021", "小米 Note 頂配版 雙網通版", "小米 Note 頂配版 雙網通版", "Xiaomi", "device_list_full_import"); // Device_List:L173
        put(m, "2015022", "小米 Note 頂配版 全網通版", "小米 Note 頂配版 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L174
        put(m, "2015501", "小米 Note 頂配版 移動合約版", "小米 Note 頂配版 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L175
        put(m, "2015211", "小米 Note 2 全網通版", "小米 Note 2 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L176
        put(m, "2015212", "小米 Note 2 移動 4G+ 版", "小米 Note 2 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L177
        put(m, "2015213", "小米 Note 2 (全球頻段)", "小米 Note 2 (全球頻段)", "Xiaomi", "device_list_full_import"); // Device_List:L178
        put(m, "MCE8", "小米 Note 3 全網通版", "小米 Note 3 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L179
        put(m, "MCT8", "小米 Note 3 移動 4G+ 版", "小米 Note 3 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L180
    }

    private static void fill1(Map<String, Entry> m) {
        put(m, "M1910F4G", "小米 Note 10 國際版", "小米 Note 10 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L181
        put(m, "M1910F4S", "小米 Note 10 Pro 國際版", "小米 Note 10 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L182
        put(m, "M2002F4LG", "小米 Note 10 Lite 國際版", "小米 Note 10 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L183
        put(m, "2016080", "小米 MIX", "小米 MIX", "Xiaomi", "device_list_full_import"); // Device_List:L184
        put(m, "MDE5", "小米 MIX 2 黑色陶瓷版 全網通版", "小米 MIX 2 黑色陶瓷版 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L185
        put(m, "MDT5", "小米 MIX 2 黑色陶瓷版 移動 4G+ 版", "小米 MIX 2 黑色陶瓷版 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L186
        put(m, "MDE5S", "小米 MIX 2 全陶瓷尊享版", "小米 MIX 2 全陶瓷尊享版", "Xiaomi", "device_list_full_import"); // Device_List:L187
        put(m, "M1803D5XE", "小米 MIX 2S 全網通版", "小米 MIX 2S 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L188
        put(m, "M1803D5XA", "小米 MIX 2S 尊享版 (全球頻段)", "小米 MIX 2S 尊享版 (全球頻段)", "Xiaomi", "device_list_full_import"); // Device_List:L189
        put(m, "M1803D5XT", "小米 MIX 2S 移動 4G+ 版", "小米 MIX 2S 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L190
        put(m, "M1803D5XC", "小米 MIX 2S 聯通電信定制版", "小米 MIX 2S 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L191
        put(m, "M1810E5E", "小米 MIX 3 國行版", "小米 MIX 3 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L192
        put(m, "M1810E5A", "小米 MIX 3 (全球頻段)", "小米 MIX 3 (全球頻段)", "Xiaomi", "device_list_full_import"); // Device_List:L193
        put(m, "M1810E5GG", "小米 MIX 3 5G", "小米 MIX 3 5G", "Xiaomi", "device_list_full_import"); // Device_List:L194
        put(m, "2106118C", "Xiaomi MIX 4", "Xiaomi MIX 4", "Xiaomi", "device_list_full_import"); // Device_List:L195
        put(m, "M2011J18C", "MIX FOLD 小米折疊屏手機", "MIX FOLD 小米折疊屏手機", "Xiaomi", "device_list_full_import"); // Device_List:L196
        put(m, "22061218C", "Xiaomi MIX Fold 2", "Xiaomi MIX Fold 2", "Xiaomi", "device_list_full_import"); // Device_List:L197
        put(m, "2308CPXD0C", "Xiaomi MIX Fold 3", "Xiaomi MIX Fold 3", "Xiaomi", "device_list_full_import"); // Device_List:L198
        put(m, "24072PX77C", "Xiaomi MIX Fold 4", "Xiaomi MIX Fold 4", "Xiaomi", "device_list_full_import"); // Device_List:L199
        put(m, "2405CPX3DC", "Xiaomi MIX Flip 國行版", "Xiaomi MIX Flip 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L200
        put(m, "2405CPX3DG", "Xiaomi MIX Flip 國際版", "Xiaomi MIX Flip 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L201
        put(m, "2505APX7BC", "Xiaomi MIX Flip 2 國行版", "Xiaomi MIX Flip 2 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L202
        put(m, "2016001", "小米 Max 標準版 國行版", "小米 Max 標準版 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L203
        put(m, "2016002", "小米 Max 標準版 國際版", "小米 Max 標準版 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L204
        put(m, "2016007", "小米 Max 高配版", "小米 Max 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L205
        put(m, "MDE40", "小米 Max 2 全網通版", "小米 Max 2 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L206
        put(m, "MDT4", "小米 Max 2 移動 4G+ 版", "小米 Max 2 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L207
        put(m, "MDI40", "小米 Max 2 印度版", "小米 Max 2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L208
        put(m, "M1804E4A", "小米 Max 3 全網通版", "小米 Max 3 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L209
        put(m, "M1804E4T", "小米 Max 3 移動 4G+ 版", "小米 Max 3 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L210
        put(m, "M1804E4C", "小米 Max 3 聯通電信定制版", "小米 Max 3 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L211
        put(m, "M1904F3BC", "小米 CC9", "小米 CC9", "Xiaomi", "device_list_full_import"); // Device_List:L212
        put(m, "M1904F3BT", "小米 CC9 美圖定制版", "小米 CC9 美圖定制版", "Xiaomi", "device_list_full_import"); // Device_List:L213
        put(m, "M1906F9SC", "小米 CC9e", "小米 CC9e", "Xiaomi", "device_list_full_import"); // Device_List:L214
        put(m, "M1910F4E", "小米 CC9 Pro", "小米 CC9 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L215
        put(m, "2109119BC", "Xiaomi Civi", "Xiaomi Civi", "Xiaomi", "device_list_full_import"); // Device_List:L216
        put(m, "2209129SC", "Xiaomi Civi 2", "Xiaomi Civi 2", "Xiaomi", "device_list_full_import"); // Device_List:L217
        put(m, "23046PNC9C", "Xiaomi Civi 3", "Xiaomi Civi 3", "Xiaomi", "device_list_full_import"); // Device_List:L218
        put(m, "24053PY09C", "Xiaomi Civi 4 Pro", "Xiaomi Civi 4 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L219
        put(m, "25067PYE3C", "Xiaomi Civi 5 Pro", "Xiaomi Civi 5 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L220
        put(m, "M1901F9E", "小米 Play 全網通版", "小米 Play 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L221
        put(m, "M1901F9T", "小米 Play 移動 4G+ 版", "小米 Play 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L222
        put(m, "MDG2", "小米 A1 國際版", "小米 A1 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L223
        put(m, "MDI2", "小米 A1 印度版", "小米 A1 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L224
        put(m, "M1804D2SG", "小米 A2 國際版", "小米 A2 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L225
        put(m, "M1804D2SI", "小米 A2 印度版", "小米 A2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L226
        put(m, "M1805D1SG", "小米 A2 Lite 國際版", "小米 A2 Lite 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L227
        put(m, "M1906F9SH", "小米 A3 國際版", "小米 A3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L228
        put(m, "M1906F9SI", "小米 A3 印度版", "小米 A3 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L229
        put(m, "A0101", "小米平板", "小米平板", "Xiaomi", "device_list_full_import"); // Device_List:L230
        put(m, "2015716", "小米平板 2", "小米平板 2", "Xiaomi", "device_list_full_import"); // Device_List:L231
        put(m, "MCE91", "小米平板 3", "小米平板 3", "Xiaomi", "device_list_full_import"); // Device_List:L232
        put(m, "M1806D9W", "小米平板 4 Wi-Fi 版", "小米平板 4 Wi-Fi 版", "Xiaomi", "device_list_full_import"); // Device_List:L233
        put(m, "M1806D9E", "小米平板 4 LTE 版", "小米平板 4 LTE 版", "Xiaomi", "device_list_full_import"); // Device_List:L234
        put(m, "M1806D9PE", "小米平板 4 Plus LTE 版", "小米平板 4 Plus LTE 版", "Xiaomi", "device_list_full_import"); // Device_List:L235
        put(m, "21051182C", "小米平板 5 國行版", "小米平板 5 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L236
        put(m, "21051182G", "小米平板 5 國際版", "小米平板 5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L237
        put(m, "M2105K81AC", "小米平板 5 Pro Wi-Fi 版", "小米平板 5 Pro Wi-Fi 版", "Xiaomi", "device_list_full_import"); // Device_List:L238
        put(m, "M2105K81C", "小米平板 5 Pro 5G", "小米平板 5 Pro 5G", "Xiaomi", "device_list_full_import"); // Device_List:L239
        put(m, "22081281AC", "小米平板 5 Pro 12.4 英寸", "小米平板 5 Pro 12.4 英寸", "Xiaomi", "device_list_full_import"); // Device_List:L240
        put(m, "23043RP34C", "Xiaomi Pad 6 國行版", "Xiaomi Pad 6 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L241
        put(m, "23043RP34G", "Xiaomi Pad 6 國際版", "Xiaomi Pad 6 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L242
        put(m, "23043RP34I", "Xiaomi Pad 6 印度版", "Xiaomi Pad 6 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L243
        put(m, "23046RP50C", "Xiaomi Pad 6 Pro", "Xiaomi Pad 6 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L244
        put(m, "2307BRPDCC", "Xiaomi Pad 6 Max 14", "Xiaomi Pad 6 Max 14", "Xiaomi", "device_list_full_import"); // Device_List:L245
        put(m, "24018RPACC", "Xiaomi Pad 6S Pro 12.4 國行版", "Xiaomi Pad 6S Pro 12.4 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L246
        put(m, "24018RPACG", "Xiaomi Pad 6S Pro 12.4 國際版", "Xiaomi Pad 6S Pro 12.4 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L247
        put(m, "2410CRP4CC", "Xiaomi Pad 7 國行版", "Xiaomi Pad 7 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L248
        put(m, "2410CRP4CG", "Xiaomi Pad 7 國際版", "Xiaomi Pad 7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L249
        put(m, "24091RPADC", "Xiaomi Pad 7 Pro 國行版", "Xiaomi Pad 7 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L250
        put(m, "24091RPADG", "Xiaomi Pad 7 Pro 國際版", "Xiaomi Pad 7 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L251
        put(m, "25032RP42C", "Xiaomi Pad 7 Ultra", "Xiaomi Pad 7 Ultra", "Xiaomi", "device_list_full_import"); // Device_List:L252
        put(m, "25053RP5CC", "Xiaomi Pad 7S Pro 12.5", "Xiaomi Pad 7S Pro 12.5", "Xiaomi", "device_list_full_import"); // Device_List:L253
        put(m, "25079RPDCG", "Xiaomi Pad Mini 國際版", "Xiaomi Pad Mini 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L254
        put(m, "25097RP43C", "Xiaomi Pad 8 國行版", "Xiaomi Pad 8 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L255
        put(m, "25097RP43G", "Xiaomi Pad 8 國際版", "Xiaomi Pad 8 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L256
        put(m, "25097RP43I", "Xiaomi Pad 8 印度版", "Xiaomi Pad 8 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L257
        put(m, "25091RP04C", "Xiaomi Pad 8 Pro 國行版", "Xiaomi Pad 8 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L258
        put(m, "25091RP04G", "Xiaomi Pad 8 Pro 國際版", "Xiaomi Pad 8 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L259
        put(m, "2013022", "紅米手機 移動版", "紅米手機 移動版", "Xiaomi", "device_list_full_import"); // Device_List:L260
        put(m, "2013023", "紅米手機 聯通版", "紅米手機 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L261
        put(m, "2013029", "紅米 1S 聯通版", "紅米 1S 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L262
        put(m, "2013028", "紅米 1S 電信版", "紅米 1S 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L263
        put(m, "2014011", "紅米 1S 移動 3G 版", "紅米 1S 移動 3G 版", "Xiaomi", "device_list_full_import"); // Device_List:L264
        put(m, "2014501", "紅米 1S 移動 4G 版", "紅米 1S 移動 4G 版", "Xiaomi", "device_list_full_import"); // Device_List:L265
        put(m, "2014813", "紅米 2 移動版", "紅米 2 移動版", "Xiaomi", "device_list_full_import"); // Device_List:L266
        put(m, "2014112", "紅米 2 移動合約版", "紅米 2 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L267
        put(m, "2014811", "紅米 2 聯通版", "紅米 2 聯通版", "Xiaomi", "device_list_full_import"); // Device_List:L268
        put(m, "2014812", "紅米 2 電信版", "紅米 2 電信版", "Xiaomi", "device_list_full_import"); // Device_List:L269
        put(m, "2014821", "紅米 2 電信合約版", "紅米 2 電信合約版", "Xiaomi", "device_list_full_import"); // Device_List:L270
        put(m, "2014817", "紅米 2 國際版", "紅米 2 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L271
        put(m, "2014818", "紅米 2 印度版", "紅米 2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L272
        put(m, "2014819", "紅米 2 巴西版", "紅米 2 巴西版", "Xiaomi", "device_list_full_import"); // Device_List:L273
        put(m, "2014502", "紅米 2A 標準版", "紅米 2A 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L274
        put(m, "2014055", "紅米 2A 增強版", "紅米 2A 增強版", "Xiaomi", "device_list_full_import"); // Device_List:L275
        put(m, "2014816", "紅米 2A 高配版", "紅米 2A 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L276
        put(m, "2015815", "紅米 3 全網通 標準版", "紅米 3 全網通 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L277
        put(m, "2015812", "紅米 3 移動合約 標準版", "紅米 3 移動合約 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L278
        put(m, "2015810", "紅米 3 聯通合約 標準版", "紅米 3 聯通合約 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L279
        put(m, "2015819", "紅米 3 全網通 高配版", "紅米 3 全網通 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L280
        put(m, "2015818", "紅米 3 聯通合約 高配版", "紅米 3 聯通合約 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L281
        put(m, "2015816", "紅米 3 國際版", "紅米 3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L282
        put(m, "2016030", "紅米 3S 國行版", "紅米 3S 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L283
        put(m, "2016031", "紅米 3S 國際版", "紅米 3S 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L284
        put(m, "2016032", "紅米 3S Prime 印度版", "紅米 3S Prime 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L285
        put(m, "2016037", "紅米 3S 印度版", "紅米 3S 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L286
        put(m, "2016036", "紅米 3X 全網通版", "紅米 3X 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L287
        put(m, "2016035", "紅米 3X 移動合約版", "紅米 3X 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L288
        put(m, "2016033", "紅米 3X 全網通版 (聯通定制)", "紅米 3X 全網通版 (聯通定制)", "Xiaomi", "device_list_full_import"); // Device_List:L289
        put(m, "2016090", "紅米 4 標準版", "紅米 4 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L290
        put(m, "2016060", "紅米 4 高配版", "紅米 4 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L291
        put(m, "2016111", "紅米 4A 全網通版", "紅米 4A 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L292
        put(m, "2016112", "紅米 4A 移動 4G+ 版", "紅米 4A 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L293
        put(m, "2016117", "紅米 4A 國際版", "紅米 4A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L294
        put(m, "2016116", "紅米 4A 印度版", "紅米 4A 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L295
        put(m, "MAE136", "紅米 4X 全網通版", "紅米 4X 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L296
        put(m, "MAT136", "紅米 4X 移動 4G+ 版", "紅米 4X 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L297
        put(m, "MAG138", "紅米 4X 國際版", "紅米 4X 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L298
        put(m, "MAI132", "紅米 4 印度版", "紅米 4 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L299
        put(m, "MDE1", "紅米 5 全網通版", "紅米 5 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L300
        put(m, "MDT1", "紅米 5 移動 4G+ 版", "紅米 5 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L301
        put(m, "MDG1", "紅米 5 國際版", "紅米 5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L302
        put(m, "MDI1", "紅米 5 印度版", "紅米 5 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L303
        put(m, "MEE7", "紅米 5 Plus 全網通版", "紅米 5 Plus 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L304
        put(m, "MET7", "紅米 5 Plus 移動 4G+ 版", "紅米 5 Plus 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L305
        put(m, "MEG7", "紅米 5 Plus 國際版", "紅米 5 Plus 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L306
        put(m, "MCE3B", "紅米 5A 全網通版", "紅米 5A 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L307
        put(m, "MCT3B", "紅米 5A 移動 4G+ 版", "紅米 5A 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L308
        put(m, "MCG3B", "紅米 5A 國際版", "紅米 5A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L309
        put(m, "MCI3B", "紅米 5A 印度版", "紅米 5A 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L310
        put(m, "M1804C3DE", "紅米 6 全網通版", "紅米 6 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L311
        put(m, "M1804C3DT", "紅米 6 移動 4G+ 版", "紅米 6 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L312
        put(m, "M1804C3DC", "紅米 6 聯通電信定制版", "紅米 6 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L313
        put(m, "M1804C3DH", "紅米 6 國際版", "紅米 6 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L314
        put(m, "M1804C3DI", "紅米 6 印度版", "紅米 6 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L315
        put(m, "M1805D1SE", "紅米 6 Pro 全網通版", "紅米 6 Pro 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L316
        put(m, "M1805D1ST", "紅米 6 Pro 移動 4G+ 版", "紅米 6 Pro 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L317
        put(m, "M1805D1SC", "紅米 6 Pro 聯通電信定制版", "紅米 6 Pro 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L318
        put(m, "M1805D1SI", "紅米 6 Pro 印度版", "紅米 6 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L319
        put(m, "M1804C3CE", "紅米 6A 全網通版", "紅米 6A 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L320
        put(m, "M1804C3CT", "紅米 6A 移動 4G+ 版", "紅米 6A 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L321
        put(m, "M1804C3CC", "紅米 6A 聯通電信定制版", "紅米 6A 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L322
        put(m, "M1804C3CH", "紅米 6A 國際版", "紅米 6A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L323
        put(m, "M1804C3CI", "紅米 6A 印度版", "紅米 6A 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L324
        put(m, "M1810F6LE", "Redmi 7 全網通版", "Redmi 7 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L325
        put(m, "M1810F6LT", "Redmi 7 運營商全網通版", "Redmi 7 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L326
        put(m, "M1810F6LH", "Redmi 7 國際版", "Redmi 7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L327
        put(m, "M1810F6LI", "Redmi 7 印度版", "Redmi 7 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L328
        put(m, "M1903C3EE", "Redmi 7A 全網通版", "Redmi 7A 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L329
        put(m, "M1903C3ET", "Redmi 7A 移動 4G+ 版", "Redmi 7A 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L330
        put(m, "M1903C3EC", "Redmi 7A 聯通電信定制版", "Redmi 7A 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L331
        put(m, "M1903C3EH", "Redmi 7A 國際版", "Redmi 7A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L332
        put(m, "M1903C3EI", "Redmi 7A 印度版", "Redmi 7A 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L333
        put(m, "M1908C3IE", "Redmi 8 全網通版", "Redmi 8 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L334
        put(m, "M1908C3IC", "Redmi 8 運營商全網通版", "Redmi 8 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L335
        put(m, "M1908C3IH", "Redmi 8 國際版", "Redmi 8 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L336
        put(m, "M1908C3II", "Redmi 8 印度版", "Redmi 8 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L337
        put(m, "M1908C3KE", "Redmi 8A 國行版", "Redmi 8A 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L338
        put(m, "M1908C3KH", "Redmi 8A 國際版", "Redmi 8A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L339
        put(m, "M1908C3KI", "Redmi 8A 印度版", "Redmi 8A 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L340
        put(m, "M2001C3K3I", "Redmi 8A Dual 印度版 / Redmi 8A Pro 國際版", "Redmi 8A Dual 印度版 / Redmi 8A Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L341
        put(m, "M2004J19C", "Redmi 9 國行版", "Redmi 9 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L342
        put(m, "M2004J19G", "Redmi 9 國際版", "Redmi 9 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L343
        put(m, "M2004J19I", "Redmi 9 Prime 印度版", "Redmi 9 Prime 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L344
        put(m, "M2004J19AG", "Redmi 9 國際版 (NFC)", "Redmi 9 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L345
        put(m, "M2006C3LC", "Redmi 9A 國行版", "Redmi 9A 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L346
        put(m, "M2006C3LG", "Redmi 9A 國際版", "Redmi 9A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L347
        put(m, "M2006C3LVG", "Redmi 9AT 國際版", "Redmi 9AT 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L348
        put(m, "M2006C3LI", "Redmi 9A 印度版 / Redmi 9A Sport 印度版", "Redmi 9A 印度版 / Redmi 9A Sport 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L349
        put(m, "M2006C3LII", "Redmi 9i 印度版 / Redmi 9i Sport 印度版", "Redmi 9i 印度版 / Redmi 9i Sport 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L350
        put(m, "M2006C3MG", "Redmi 9C 國際版", "Redmi 9C 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L351
        put(m, "M2006C3MT", "Redmi 9C 泰國版", "Redmi 9C 泰國版", "Xiaomi", "device_list_full_import"); // Device_List:L352
        put(m, "M2006C3MNG", "Redmi 9C NFC 國際版", "Redmi 9C NFC 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L353
        put(m, "M2006C3MII", "Redmi 9 印度版 / Redmi 9 Activ 印度版", "Redmi 9 印度版 / Redmi 9 Activ 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L354
        put(m, "M2010J19SG", "Redmi 9T 國際版", "Redmi 9T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L355
        put(m, "M2010J19SI", "Redmi 9 Power 印度版", "Redmi 9 Power 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L356
        put(m, "M2010J19SR", "Redmi 9T 日本版", "Redmi 9T 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L357
        put(m, "M2010J19ST", "Redmi 9T 泰國版", "Redmi 9T 泰國版", "Xiaomi", "device_list_full_import"); // Device_List:L358
        put(m, "M2010J19SY", "Redmi 9T 國際版 (NFC)", "Redmi 9T 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L359
        put(m, "M2010J19SL", "Redmi 9T 拉美版", "Redmi 9T 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L360
    }

    private static void fill2(Map<String, Entry> m) {
        put(m, "21061119AG", "Redmi 10 國際版", "Redmi 10 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L361
        put(m, "21061119AL", "Redmi 10 拉美版", "Redmi 10 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L362
        put(m, "21061119BI", "Redmi 10 Prime 印度版", "Redmi 10 Prime 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L363
        put(m, "21061119DG", "Redmi 10 國際版 (NFC)", "Redmi 10 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L364
        put(m, "21121119SG", "Redmi 10 2022 國際版", "Redmi 10 2022 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L365
        put(m, "21121119VL", "Redmi 10 2022 拉美版", "Redmi 10 2022 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L366
        put(m, "22011119TI", "Redmi 10 Prime 2022 印度版", "Redmi 10 Prime 2022 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L367
        put(m, "22011119UY", "Redmi 10 2022 國際版 (NFC)", "Redmi 10 2022 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L368
        put(m, "22041219G", "Redmi 10 5G 國際版", "Redmi 10 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L369
        put(m, "22041219I", "Redmi 11 Prime 5G 印度版", "Redmi 11 Prime 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L370
        put(m, "22041219NY", "Redmi 10 5G 國際版 (NFC)", "Redmi 10 5G 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L371
        put(m, "220333QAG", "Redmi 10C 國際版", "Redmi 10C 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L372
        put(m, "220333QBI", "Redmi 10 印度版 / Redmi 10 Power 印度版", "Redmi 10 印度版 / Redmi 10 Power 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L373
        put(m, "220333QNY", "Redmi 10C 國際版 (NFC)", "Redmi 10C 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L374
        put(m, "220333QL", "Redmi 10C 拉美版", "Redmi 10C 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L375
        put(m, "220233L2C", "Redmi 10A 國行版", "Redmi 10A 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L376
        put(m, "220233L2G", "Redmi 10A 國際版", "Redmi 10A 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L377
        put(m, "220233L2I", "Redmi 10A 印度版 / Redmi 10A Sport 印度版", "Redmi 10A 印度版 / Redmi 10A Sport 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L378
        put(m, "22071219AI", "Redmi 11 Prime 印度版", "Redmi 11 Prime 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L379
        put(m, "23053RN02A", "Redmi 12 國際版", "Redmi 12 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L380
        put(m, "23053RN02I", "Redmi 12 印度版", "Redmi 12 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L381
        put(m, "23053RN02L", "Redmi 12 拉美版", "Redmi 12 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L382
        put(m, "23053RN02Y", "Redmi 12 國際版 (NFC)", "Redmi 12 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L383
        put(m, "23077RABDC", "Redmi 12 5G 國行版", "Redmi 12 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L384
        put(m, "23076RN8DY", "Redmi 12 5G 國際版 (NFC)", "Redmi 12 5G 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L385
        put(m, "23076RA4BR", "Redmi 12 5G 日本版 (無鎖)", "Redmi 12 5G 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L386
        put(m, "XIG03", "Redmi 12 5G 日本版 (KDDI)", "Redmi 12 5G 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L387
        put(m, "A401XM", "Redmi 12 5G 日本版 (SoftBank)", "Redmi 12 5G 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L388
        put(m, "23076RN4BI", "Redmi 12 5G 印度版", "Redmi 12 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L389
        put(m, "23076RA4BC", "Redmi 12R", "Redmi 12R", "Xiaomi", "device_list_full_import"); // Device_List:L390
        put(m, "22120RN86C", "Redmi 12C 國行版", "Redmi 12C 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L391
        put(m, "22120RN86G", "Redmi 12C 國際版", "Redmi 12C 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L392
        put(m, "22120RN86I", "Redmi 12C 印度版", "Redmi 12C 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L393
        put(m, "2212ARNC4L", "Redmi 12C 拉美版 / 日本版", "Redmi 12C 拉美版 / 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L394
        put(m, "22126RN91Y", "Redmi 12C 國際版 (NFC)", "Redmi 12C 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L395
        put(m, "2404ARN45A", "Redmi 13 國際版 / REDMI 13x 國際版", "Redmi 13 國際版 / REDMI 13x 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L396
        put(m, "2404ARN45I", "Redmi 13 印度版", "Redmi 13 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L397
        put(m, "24049RN28L", "Redmi 13 拉美版 / REDMI 13x 拉美版", "Redmi 13 拉美版 / REDMI 13x 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L398
        put(m, "24040RN64Y", "Redmi 13 國際版 (NFC) / REDMI 13x 國際版 (NFC)", "Redmi 13 國際版 (NFC) / REDMI 13x 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L399
        put(m, "2406ERN9CI", "Redmi 13 5G 印度版", "Redmi 13 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L400
        put(m, "23106RN0DA", "Redmi 13C 國際版", "Redmi 13C 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L401
        put(m, "2311DRN14I", "Redmi 13C 印度版", "Redmi 13C 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L402
        put(m, "23100RN82L", "Redmi 13C 拉美版", "Redmi 13C 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L403
        put(m, "23108RN04Y", "Redmi 13C 國際版 (NFC)", "Redmi 13C 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L404
        put(m, "23124RN87C", "Redmi 13C 5G 國行版 / Redmi 13R 5G", "Redmi 13C 5G 國行版 / Redmi 13R 5G", "Xiaomi", "device_list_full_import"); // Device_List:L405
        put(m, "23124RN87I", "Redmi 13C 5G 印度版", "Redmi 13C 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L406
        put(m, "23124RN87G", "Redmi 13C 5G 國際版", "Redmi 13C 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L407
        put(m, "2409BRN2CC", "Redmi 14C 國行版 / REDMI 17C 國行版", "Redmi 14C 國行版 / REDMI 17C 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L408
        put(m, "2409BRN2CA", "Redmi 14C 國際版", "Redmi 14C 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L409
        put(m, "2409BRN2CI", "Redmi 14C 印度版", "Redmi 14C 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L410
        put(m, "2409BRN2CL", "Redmi 14C 拉美版 / 日韓版", "Redmi 14C 拉美版 / 日韓版", "Xiaomi", "device_list_full_import"); // Device_List:L411
        put(m, "2409BRN2CY", "Redmi 14C 國際版 (NFC)", "Redmi 14C 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L412
        put(m, "2411DRN47G", "Redmi 14C 5G 國際版", "Redmi 14C 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L413
        put(m, "2411DRN47R", "Redmi 14C 5G 日本版", "Redmi 14C 5G 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L414
        put(m, "2411DRN47C", "Redmi 14R 5G 國行版", "Redmi 14R 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L415
        put(m, "2411DRN47I", "Redmi 14C 5G 印度版", "Redmi 14C 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L416
        put(m, "25062RN2DA", "REDMI 15 國際版", "REDMI 15 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L417
        put(m, "25062RN2DY", "REDMI 15 國際版 (NFC)", "REDMI 15 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L418
        put(m, "25062RN2DE", "REDMI 15 歐洲版", "REDMI 15 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L419
        put(m, "25062RN2DL", "REDMI 15 拉美版", "REDMI 15 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L420
        put(m, "25057RN09G", "REDMI 15 5G 國際版", "REDMI 15 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L421
        put(m, "25057RN09E", "REDMI 15 5G 歐洲版", "REDMI 15 5G 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L422
        put(m, "25057RN09I", "REDMI 15 5G 印度版", "REDMI 15 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L423
        put(m, "25057RN09R", "REDMI 15 5G 日本版 (無鎖)", "REDMI 15 5G 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L424
        put(m, "A501XM", "REDMI 15 5G 日本版 (SoftBank)", "REDMI 15 5G 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L425
        put(m, "25078RA3EA", "REDMI 15C 國際版", "REDMI 15C 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L426
        put(m, "25078RA3EY", "REDMI 15C 國際版 (NFC)", "REDMI 15C 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L427
        put(m, "25078RA3EE", "REDMI 15C 歐洲版", "REDMI 15C 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L428
        put(m, "25078RA3EL", "REDMI 15C 拉美版", "REDMI 15C 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L429
        put(m, "2508CRN2BC", "REDMI 15C 5G 國行版", "REDMI 15C 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L430
        put(m, "2508CRN2BG", "REDMI 15C 5G 國際版", "REDMI 15C 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L431
        put(m, "2508CRN2BE", "REDMI 15C 5G 歐洲版", "REDMI 15C 5G 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L432
        put(m, "2508CRN2BI", "REDMI 15C 5G 印度版", "REDMI 15C 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L433
        put(m, "2508CRN2BR", "REDMI 15C 5G 日本版", "REDMI 15C 5G 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L434
        put(m, "25082RNC1C", "REDMI 15R 5G", "REDMI 15R 5G", "Xiaomi", "device_list_full_import"); // Device_List:L435
        put(m, "2602BRNA4I", "REDMI 15A 5G 印度版", "REDMI 15A 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L436
        put(m, "2014018", "紅米 Note 聯通 3G 標準版", "紅米 Note 聯通 3G 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L437
        put(m, "2013121", "紅米 Note 聯通 3G 增強版", "紅米 Note 聯通 3G 增強版", "Xiaomi", "device_list_full_import"); // Device_List:L438
        put(m, "2014017", "紅米 Note 移動 3G 標準版", "紅米 Note 移動 3G 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L439
        put(m, "2013122", "紅米 Note 移動 3G 增強版", "紅米 Note 移動 3G 增強版", "Xiaomi", "device_list_full_import"); // Device_List:L440
        put(m, "2014022", "紅米 Note 移動 4G 增強版", "紅米 Note 移動 4G 增強版", "Xiaomi", "device_list_full_import"); // Device_List:L441
        put(m, "2014021", "紅米 Note 聯通 4G 增強版", "紅米 Note 聯通 4G 增強版", "Xiaomi", "device_list_full_import"); // Device_List:L442
        put(m, "2014715", "紅米 Note 4G 國際版", "紅米 Note 4G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L443
        put(m, "2014712", "紅米 Note 4G 印度版", "紅米 Note 4G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L444
        put(m, "2014915", "紅米 Note 移動 4G 雙卡版", "紅米 Note 移動 4G 雙卡版", "Xiaomi", "device_list_full_import"); // Device_List:L445
        put(m, "2014912", "紅米 Note 聯通 4G 雙卡版", "紅米 Note 聯通 4G 雙卡版", "Xiaomi", "device_list_full_import"); // Device_List:L446
        put(m, "2014916", "紅米 Note 電信 4G 雙卡版", "紅米 Note 電信 4G 雙卡版", "Xiaomi", "device_list_full_import"); // Device_List:L447
        put(m, "2014911", "紅米 Note 移動 4G 雙卡合約版", "紅米 Note 移動 4G 雙卡合約版", "Xiaomi", "device_list_full_import"); // Device_List:L448
        put(m, "2014910", "紅米 Note 電信 4G 雙卡合約版", "紅米 Note 電信 4G 雙卡合約版", "Xiaomi", "device_list_full_import"); // Device_List:L449
        put(m, "2015052", "紅米 Note 2 移動版", "紅米 Note 2 移動版", "Xiaomi", "device_list_full_import"); // Device_List:L450
        put(m, "2015051", "紅米 Note 2 雙網通版", "紅米 Note 2 雙網通版", "Xiaomi", "device_list_full_import"); // Device_List:L451
        put(m, "2015712", "紅米 Note 2 雙網通高配版", "紅米 Note 2 雙網通高配版", "Xiaomi", "device_list_full_import"); // Device_List:L452
        put(m, "2015055", "紅米 Note 2 移動合約版", "紅米 Note 2 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L453
        put(m, "2015056", "紅米 Note 2 移動合約高配版", "紅米 Note 2 移動合約高配版", "Xiaomi", "device_list_full_import"); // Device_List:L454
        put(m, "2015617", "紅米 Note 3 雙網通版", "紅米 Note 3 雙網通版", "Xiaomi", "device_list_full_import"); // Device_List:L455
        put(m, "2015611", "紅米 Note 3 移動合約版", "紅米 Note 3 移動合約版", "Xiaomi", "device_list_full_import"); // Device_List:L456
        put(m, "2015115", "紅米 Note 3 國行版", "紅米 Note 3 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L457
        put(m, "2015116", "紅米 Note 3 國際版", "紅米 Note 3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L458
        put(m, "2015161", "紅米 Note 3 台灣特制版", "紅米 Note 3 台灣特制版", "Xiaomi", "device_list_full_import"); // Device_List:L459
        put(m, "2016050", "紅米 Note 4 全網通版", "紅米 Note 4 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L460
        put(m, "2016051", "紅米 Note 4 移動版", "紅米 Note 4 移動版", "Xiaomi", "device_list_full_import"); // Device_List:L461
        put(m, "2016101", "紅米 Note 4X 高通 全網通版", "紅米 Note 4X 高通 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L462
        put(m, "2016130", "紅米 Note 4X 高通 移動 4G+ 版", "紅米 Note 4X 高通 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L463
        put(m, "2016102", "紅米 Note 4 國際版 / 紅米 Note 4X 高通 國際版", "紅米 Note 4 國際版 / 紅米 Note 4X 高通 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L464
        put(m, "MBE6A5", "紅米 Note 4X MTK 全網通版", "紅米 Note 4X MTK 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L465
        put(m, "MBT6A5", "紅米 Note 4X MTK 移動 4G+ 版", "紅米 Note 4X MTK 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L466
        put(m, "MEI7", "紅米 Note 5 印度版", "紅米 Note 5 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L467
        put(m, "MEE7S", "紅米 Note 5 全網通版", "紅米 Note 5 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L468
        put(m, "MET7S", "紅米 Note 5 移動 4G+ 版", "紅米 Note 5 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L469
        put(m, "MEC7S", "紅米 Note 5 聯通電信定制版", "紅米 Note 5 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L470
        put(m, "M1803E7SH", "紅米 Note 5 國際版", "紅米 Note 5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L471
        put(m, "MEI7S", "紅米 Note 5 Pro 印度版", "紅米 Note 5 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L472
        put(m, "MDE6", "紅米 Note 5A 全網通 標準版", "紅米 Note 5A 全網通 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L473
        put(m, "MDT6", "紅米 Note 5A 移動 4G+ 標準版", "紅米 Note 5A 移動 4G+ 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L474
        put(m, "MDG6", "紅米 Note 5A 國際版 標準版", "紅米 Note 5A 國際版 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L475
        put(m, "MDI6", "紅米 Y1 Lite 印度版", "紅米 Y1 Lite 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L476
        put(m, "MDE6S", "紅米 Note 5A 全網通 高配版", "紅米 Note 5A 全網通 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L477
        put(m, "MDT6S", "紅米 Note 5A 移動 4G+ 高配版", "紅米 Note 5A 移動 4G+ 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L478
        put(m, "MDG6S", "紅米 Note 5A 國際版 高配版", "紅米 Note 5A 國際版 高配版", "Xiaomi", "device_list_full_import"); // Device_List:L479
        put(m, "MDI6S", "紅米 Y1 印度版", "紅米 Y1 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L480
        put(m, "M1806E7TH", "紅米 Note 6 Pro 國際版", "紅米 Note 6 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L481
        put(m, "M1806E7TI", "紅米 Note 6 Pro 印度版", "紅米 Note 6 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L482
        put(m, "M1901F7E", "Redmi Note 7 全網通版", "Redmi Note 7 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L483
        put(m, "M1901F7T", "Redmi Note 7 移動 4G+ 版", "Redmi Note 7 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L484
        put(m, "M1901F7C", "Redmi Note 7 聯通電信定制版", "Redmi Note 7 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L485
        put(m, "M1901F7H", "Redmi Note 7 國際版", "Redmi Note 7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L486
        put(m, "M1901F7I", "Redmi Note 7 印度版 / Redmi Note 7S 印度版", "Redmi Note 7 印度版 / Redmi Note 7S 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L487
        put(m, "M1901F7BE", "Redmi Note 7 Pro 國行版", "Redmi Note 7 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L488
        put(m, "M1901F7S", "Redmi Note 7 Pro 印度版", "Redmi Note 7 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L489
        put(m, "M1908C3JE", "Redmi Note 8 全網通版", "Redmi Note 8 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L490
        put(m, "M1908C3JC", "Redmi Note 8 運營商全網通版", "Redmi Note 8 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L491
        put(m, "M1908C3JH", "Redmi Note 8 國際版", "Redmi Note 8 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L492
        put(m, "M1908C3JI", "Redmi Note 8 印度版", "Redmi Note 8 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L493
        put(m, "M1908C3XG", "Redmi Note 8T 國際版", "Redmi Note 8T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L494
        put(m, "M1908C3JGG", "Redmi Note 8 (2021) 國際版", "Redmi Note 8 (2021) 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L495
        put(m, "M1906G7E", "Redmi Note 8 Pro 全網通版", "Redmi Note 8 Pro 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L496
        put(m, "M1906G7T", "Redmi Note 8 Pro 運營商全網通版", "Redmi Note 8 Pro 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L497
        put(m, "M1906G7G", "Redmi Note 8 Pro 國際版", "Redmi Note 8 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L498
        put(m, "M1906G7I", "Redmi Note 8 Pro 印度版", "Redmi Note 8 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L499
        put(m, "M2010J19SC", "Redmi Note 9 4G 國行版", "Redmi Note 9 4G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L500
        put(m, "M2007J22C", "Redmi Note 9 5G 國行版", "Redmi Note 9 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L501
        put(m, "M2003J15SS", "Redmi Note 9 國際版", "Redmi Note 9 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L502
        put(m, "M2003J15SI", "Redmi Note 9 印度版", "Redmi Note 9 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L503
        put(m, "M2003J15SG", "Redmi Note 9 國際版 (NFC)", "Redmi Note 9 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L504
        put(m, "M2007J22G", "Redmi Note 9T 5G 國際版", "Redmi Note 9T 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L505
        put(m, "A001XM", "Redmi Note 9T 5G 日本版 (SoftBank)", "Redmi Note 9T 5G 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L506
        put(m, "M2007J17C", "Redmi Note 9 Pro 5G 國行版", "Redmi Note 9 Pro 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L507
        put(m, "M2003J6A1G", "Redmi Note 9S 國際版", "Redmi Note 9S 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L508
        put(m, "M2003J6A1R", "Redmi Note 9S 日韓版", "Redmi Note 9S 日韓版", "Xiaomi", "device_list_full_import"); // Device_List:L509
        put(m, "M2003J6A1I", "Redmi Note 9 Pro 印度版", "Redmi Note 9 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L510
        put(m, "M2003J6B1I", "Redmi Note 9 Pro Max 印度版", "Redmi Note 9 Pro Max 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L511
        put(m, "M2003J6B2G", "Redmi Note 9 Pro 國際版", "Redmi Note 9 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L512
        put(m, "M2101K7AG", "Redmi Note 10 國際版", "Redmi Note 10 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L513
        put(m, "M2101K7AI", "Redmi Note 10 印度版", "Redmi Note 10 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L514
        put(m, "M2101K7BG", "Redmi Note 10S 國際版", "Redmi Note 10S 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L515
        put(m, "M2101K7BI", "Redmi Note 10S 印度版", "Redmi Note 10S 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L516
        put(m, "M2101K7BNY", "Redmi Note 10S 國際版 (NFC)", "Redmi Note 10S 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L517
        put(m, "M2101K7BL", "Redmi Note 10S 拉美版", "Redmi Note 10S 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L518
        put(m, "M2103K19C", "Redmi Note 10 5G 國行版 / Redmi Note 11SE 國行版", "Redmi Note 10 5G 國行版 / Redmi Note 11SE 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L519
        put(m, "M2103K19I", "Redmi Note 10T 5G 印度版", "Redmi Note 10T 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L520
        put(m, "M2103K19G", "Redmi Note 10 5G 國際版", "Redmi Note 10 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L521
        put(m, "M2103K19Y", "Redmi Note 10T 國際版", "Redmi Note 10T 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L522
        put(m, "XIG02", "Redmi Note 10 JE 日本版 (KDDI)", "Redmi Note 10 JE 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L523
        put(m, "22021119KR", "Redmi Note 10T 日本版 (無鎖)", "Redmi Note 10T 日本版 (無鎖)", "Xiaomi", "device_list_full_import"); // Device_List:L524
        put(m, "A101XM", "Redmi Note 10T 日本版 (SoftBank)", "Redmi Note 10T 日本版 (SoftBank)", "Xiaomi", "device_list_full_import"); // Device_List:L525
        put(m, "M2101K6G", "Redmi Note 10 Pro 國際版", "Redmi Note 10 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L526
        put(m, "M2101K6T", "Redmi Note 10 Pro 泰國版", "Redmi Note 10 Pro 泰國版", "Xiaomi", "device_list_full_import"); // Device_List:L527
        put(m, "M2101K6R", "Redmi Note 10 Pro 日本版", "Redmi Note 10 Pro 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L528
        put(m, "M2101K6P", "Redmi Note 10 Pro 印度版", "Redmi Note 10 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L529
        put(m, "M2101K6I", "Redmi Note 10 Pro Max 印度版", "Redmi Note 10 Pro Max 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L530
        put(m, "M2104K10AC", "Redmi Note 10 Pro 5G 國行版", "Redmi Note 10 Pro 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L531
        put(m, "2109106A1I", "Redmi Note 10 Lite 印度版", "Redmi Note 10 Lite 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L532
        put(m, "21121119SC", "Redmi Note 11 4G 國行版", "Redmi Note 11 4G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L533
        put(m, "2201117TG", "Redmi Note 11 國際版", "Redmi Note 11 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L534
        put(m, "2201117TI", "Redmi Note 11 印度版", "Redmi Note 11 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L535
        put(m, "2201117TL", "Redmi Note 11 拉美版", "Redmi Note 11 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L536
        put(m, "2201117TY", "Redmi Note 11 國際版 (NFC)", "Redmi Note 11 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L537
        put(m, "21091116AC", "Redmi Note 11 5G 國行版", "Redmi Note 11 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L538
        put(m, "21091116AI", "Redmi Note 11T 5G 印度版", "Redmi Note 11T 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L539
        put(m, "22041219C", "Redmi Note 11E 5G", "Redmi Note 11E 5G", "Xiaomi", "device_list_full_import"); // Device_List:L540
    }

    private static void fill3(Map<String, Entry> m) {
        put(m, "2201117SG", "Redmi Note 11S 國際版", "Redmi Note 11S 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L541
        put(m, "2201117SI", "Redmi Note 11S 印度版", "Redmi Note 11S 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L542
        put(m, "2201117SL", "Redmi Note 11S 拉美版", "Redmi Note 11S 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L543
        put(m, "2201117SY", "Redmi Note 11S 國際版 (NFC)", "Redmi Note 11S 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L544
        put(m, "22087RA4DI", "Redmi Note 11 SE 印度版", "Redmi Note 11 SE 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L545
        put(m, "22031116BG", "Redmi Note 11S 5G 國際版", "Redmi Note 11S 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L546
        put(m, "21091116C", "Redmi Note 11 Pro 國行版", "Redmi Note 11 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L547
        put(m, "2201116TG", "Redmi Note 11 Pro 國際版", "Redmi Note 11 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L548
        put(m, "2201116TI", "Redmi Note 11 Pro 印度版", "Redmi Note 11 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L549
        put(m, "2201116SC", "Redmi Note 11E Pro 國行版", "Redmi Note 11E Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L550
        put(m, "2201116SG", "Redmi Note 11 Pro 5G 國際版", "Redmi Note 11 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L551
        put(m, "2201116SR", "Redmi Note 11 Pro 5G 日本版", "Redmi Note 11 Pro 5G 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L552
        put(m, "2201116SI", "Redmi Note 11 Pro+ 5G 印度版", "Redmi Note 11 Pro+ 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L553
        put(m, "21091116UC", "Redmi Note 11 Pro+ 國行版", "Redmi Note 11 Pro+ 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L554
        put(m, "21091116UG", "Redmi Note 11 Pro+ 5G 國際版", "Redmi Note 11 Pro+ 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L555
        put(m, "22041216C", "Redmi Note 11T Pro", "Redmi Note 11T Pro", "Xiaomi", "device_list_full_import"); // Device_List:L556
        put(m, "22041216UC", "Redmi Note 11T Pro+", "Redmi Note 11T Pro+", "Xiaomi", "device_list_full_import"); // Device_List:L557
        put(m, "22095RA98C", "Redmi Note 11R 5G", "Redmi Note 11R 5G", "Xiaomi", "device_list_full_import"); // Device_List:L558
        put(m, "23021RAAEG", "Redmi Note 12 國際版", "Redmi Note 12 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L559
        put(m, "23027RAD4I", "Redmi Note 12 印度版", "Redmi Note 12 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L560
        put(m, "23028RA60L", "Redmi Note 12 拉美版", "Redmi Note 12 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L561
        put(m, "23021RAA2Y", "Redmi Note 12 國際版 (NFC)", "Redmi Note 12 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L562
        put(m, "22101317C", "Redmi Note 12 5G 國行版 / Redmi Note 12R Pro", "Redmi Note 12 5G 國行版 / Redmi Note 12R Pro", "Xiaomi", "device_list_full_import"); // Device_List:L563
        put(m, "22111317G", "Redmi Note 12 5G 國際版", "Redmi Note 12 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L564
        put(m, "22111317I", "Redmi Note 12 5G 印度版", "Redmi Note 12 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L565
        put(m, "2303CRA44A", "Redmi Note 12S 國際版", "Redmi Note 12S 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L566
        put(m, "2303ERA42L", "Redmi Note 12S 拉美版", "Redmi Note 12S 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L567
        put(m, "23030RAC7Y", "Redmi Note 12S 國際版 (NFC)", "Redmi Note 12S 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L568
        put(m, "2209116AG", "Redmi Note 12 Pro 國際版", "Redmi Note 12 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L569
        put(m, "22101316C", "Redmi Note 12 Pro 國行版", "Redmi Note 12 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L570
        put(m, "22101316G", "Redmi Note 12 Pro 5G 國際版", "Redmi Note 12 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L571
        put(m, "22101316I", "Redmi Note 12 Pro 5G 印度版", "Redmi Note 12 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L572
        put(m, "22101316UCP", "Redmi Note 12 Pro+ 國行版", "Redmi Note 12 Pro+ 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L573
        put(m, "22101316UG", "Redmi Note 12 Pro+ 5G 國際版", "Redmi Note 12 Pro+ 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L574
        put(m, "22101316UP", "Redmi Note 12 Pro+ 5G 印度版", "Redmi Note 12 Pro+ 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L575
        put(m, "22101316UC", "Redmi Note 12 探索版", "Redmi Note 12 探索版", "Xiaomi", "device_list_full_import"); // Device_List:L576
        put(m, "22101320C", "Redmi Note 12 Pro 極速版", "Redmi Note 12 Pro 極速版", "Xiaomi", "device_list_full_import"); // Device_List:L577
        put(m, "23054RA19C", "Redmi Note 12T Pro", "Redmi Note 12T Pro", "Xiaomi", "device_list_full_import"); // Device_List:L578
        put(m, "23049RAD8C", "Redmi Note 12 Turbo", "Redmi Note 12 Turbo", "Xiaomi", "device_list_full_import"); // Device_List:L579
        put(m, "23129RAA4G", "Redmi Note 13 國際版", "Redmi Note 13 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L580
        put(m, "23129RA5FL", "Redmi Note 13 拉美版", "Redmi Note 13 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L581
        put(m, "23124RA7EO", "Redmi Note 13 國際版 (NFC)", "Redmi Note 13 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L582
        put(m, "2312DRAABC", "Redmi Note 13 5G 國行版", "Redmi Note 13 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L583
        put(m, "2312DRAABI", "Redmi Note 13 5G 印度版", "Redmi Note 13 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L584
        put(m, "2312DRAABG", "Redmi Note 13 5G 國際版", "Redmi Note 13 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L585
        put(m, "23117RA68G", "Redmi Note 13 Pro 國際版", "Redmi Note 13 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L586
        put(m, "2312DRA50G", "Redmi Note 13 Pro 5G 國際版", "Redmi Note 13 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L587
        put(m, "2312DRA50I", "Redmi Note 13 Pro 5G 印度版", "Redmi Note 13 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L588
        put(m, "XIG05", "Redmi Note 13 Pro 5G 日本版 (KDDI)", "Redmi Note 13 Pro 5G 日本版 (KDDI)", "Xiaomi", "device_list_full_import"); // Device_List:L589
        put(m, "2312CRAD3C", "Redmi Note 13 Pro 國行版 (LPDDR5 + UFS 3.1)", "Redmi Note 13 Pro 國行版 (LPDDR5 + UFS 3.1)", "Xiaomi", "device_list_full_import"); // Device_List:L590
        put(m, "23090RA98C", "Redmi Note 13 Pro+ 國行版", "Redmi Note 13 Pro+ 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L591
        put(m, "23090RA98G", "Redmi Note 13 Pro+ 5G 國際版", "Redmi Note 13 Pro+ 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L592
        put(m, "23090RA98I", "Redmi Note 13 Pro+ 5G 印度版", "Redmi Note 13 Pro+ 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L593
        put(m, "24040RA98R", "Redmi Note 13 Pro+ 5G 日本版", "Redmi Note 13 Pro+ 5G 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L594
        put(m, "2406ERN9CC", "Redmi Note 13R", "Redmi Note 13R", "Xiaomi", "device_list_full_import"); // Device_List:L595
        put(m, "2311FRAFDC", "Redmi Note 13R Pro", "Redmi Note 13R Pro", "Xiaomi", "device_list_full_import"); // Device_List:L596
        put(m, "24117RN76G", "Redmi Note 14 國際版", "Redmi Note 14 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L597
        put(m, "24117RN76E", "Redmi Note 14 歐洲版", "Redmi Note 14 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L598
        put(m, "24117RN76L", "Redmi Note 14 拉美版", "Redmi Note 14 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L599
        put(m, "24117RN76O", "Redmi Note 14 國際版 (NFC)", "Redmi Note 14 國際版 (NFC)", "Xiaomi", "device_list_full_import"); // Device_List:L600
        put(m, "24094RAD4C", "Redmi Note 14 5G 國行版 / REDMI Note 15R Pro 國行版", "Redmi Note 14 5G 國行版 / REDMI Note 15R Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L601
        put(m, "24094RAD4I", "Redmi Note 14 5G 印度版 / Redmi Note 14 SE 5G 印度版", "Redmi Note 14 5G 印度版 / Redmi Note 14 SE 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L602
        put(m, "24094RAD4G", "Redmi Note 14 5G 國際版", "Redmi Note 14 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L603
        put(m, "2502FRA65G", "Redmi Note 14S 國際版", "Redmi Note 14S 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L604
        put(m, "24116RACCG", "Redmi Note 14 Pro 國際版", "Redmi Note 14 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L605
        put(m, "24090RA29C", "Redmi Note 14 Pro 國行版", "Redmi Note 14 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L606
        put(m, "24090RA29G", "Redmi Note 14 Pro 5G 國際版", "Redmi Note 14 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L607
        put(m, "24090RA29I", "Redmi Note 14 Pro 5G 印度版", "Redmi Note 14 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L608
        put(m, "24115RA8EC", "Redmi Note 14 Pro+ 國行版", "Redmi Note 14 Pro+ 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L609
        put(m, "24115RA8EG", "Redmi Note 14 Pro+ 5G 國際版", "Redmi Note 14 Pro+ 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L610
        put(m, "24115RA8EI", "Redmi Note 14 Pro+ 5G 印度版", "Redmi Note 14 Pro+ 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L611
        put(m, "2510DRA23G", "REDMI Note 15 國際版", "REDMI Note 15 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L612
        put(m, "2510DRA23E", "REDMI Note 15 歐洲版", "REDMI Note 15 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L613
        put(m, "2510DRA23L", "REDMI Note 15 拉美版", "REDMI Note 15 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L614
        put(m, "25098RA98C", "REDMI Note 15 國行版", "REDMI Note 15 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L615
        put(m, "25098RA98G", "REDMI Note 15 5G 國際版", "REDMI Note 15 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L616
        put(m, "25098RA98E", "REDMI Note 15 5G 歐洲版", "REDMI Note 15 5G 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L617
        put(m, "25098RA98I", "REDMI Note 15 5G 印度版", "REDMI Note 15 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L618
        put(m, "25098RA98T", "REDMI Note 15 5G 沙特版", "REDMI Note 15 5G 沙特版", "Xiaomi", "device_list_full_import"); // Device_List:L619
        put(m, "26022PCACI", "REDMI Note 15 SE 5G 印度版", "REDMI Note 15 SE 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L620
        put(m, "25100RA69G", "REDMI Note 15 Pro 國際版", "REDMI Note 15 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L621
        put(m, "25080RABDC", "REDMI Note 15 Pro 國行版", "REDMI Note 15 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L622
        put(m, "25080RABDG", "REDMI Note 15 Pro 5G 國際版", "REDMI Note 15 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L623
        put(m, "25080RABDI", "REDMI Note 15 Pro 5G 印度版", "REDMI Note 15 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L624
        put(m, "25080RABDR", "REDMI Note 15 Pro 5G 日本版", "REDMI Note 15 Pro 5G 日本版", "Xiaomi", "device_list_full_import"); // Device_List:L625
        put(m, "25080RABDT", "REDMI Note 15 Pro 5G 沙特版", "REDMI Note 15 Pro 5G 沙特版", "Xiaomi", "device_list_full_import"); // Device_List:L626
        put(m, "2510ERA8BC", "REDMI Note 15 Pro+ 國行版", "REDMI Note 15 Pro+ 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L627
        put(m, "2510ERA8BG", "REDMI Note 15 Pro+ 5G 國際版", "REDMI Note 15 Pro+ 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L628
        put(m, "2510ERA8BI", "REDMI Note 15 Pro+ 5G 印度版", "REDMI Note 15 Pro+ 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L629
        put(m, "2510ERA8BT", "REDMI Note 15 Pro+ 5G 沙特版", "REDMI Note 15 Pro+ 5G 沙特版", "Xiaomi", "device_list_full_import"); // Device_List:L630
        put(m, "25104RADAC", "REDMI Note 15 Pro+ 衛星消息版", "REDMI Note 15 Pro+ 衛星消息版", "Xiaomi", "device_list_full_import"); // Device_List:L631
        put(m, "25057RA09C", "REDMI Note 15R", "REDMI Note 15R", "Xiaomi", "device_list_full_import"); // Device_List:L632
        put(m, "26021RN18C", "REDMI Note 17 國行版", "REDMI Note 17 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L633
        put(m, "2607DRA18C", "REDMI Note 17 Pro 國行版", "REDMI Note 17 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L634
        put(m, "M2004J7AC", "Redmi 10X 5G", "Redmi 10X 5G", "Xiaomi", "device_list_full_import"); // Device_List:L635
        put(m, "M2004J7BC", "Redmi 10X Pro 5G", "Redmi 10X Pro 5G", "Xiaomi", "device_list_full_import"); // Device_List:L636
        put(m, "M2003J15SC", "Redmi 10X 4G", "Redmi 10X 4G", "Xiaomi", "device_list_full_import"); // Device_List:L637
        put(m, "24069RA21C", "Redmi Turbo 3", "Redmi Turbo 3", "Xiaomi", "device_list_full_import"); // Device_List:L638
        put(m, "24129RT7CC", "REDMI Turbo 4", "REDMI Turbo 4", "Xiaomi", "device_list_full_import"); // Device_List:L639
        put(m, "25053RT47C", "REDMI Turbo 4 Pro", "REDMI Turbo 4 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L640
        put(m, "2511FRT34C", "REDMI Turbo 5 國行版", "REDMI Turbo 5 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L641
        put(m, "2606FRT34I", "REDMI Turbo 5 印度版", "REDMI Turbo 5 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L642
        put(m, "2602BRT18C", "REDMI Turbo 5 Max", "REDMI Turbo 5 Max", "Xiaomi", "device_list_full_import"); // Device_List:L643
        put(m, "M1903F10A", "Redmi K20 全網通版", "Redmi K20 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L644
        put(m, "M1903F10C", "Redmi K20 運營商全網通版", "Redmi K20 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L645
        put(m, "M1903F10I", "Redmi K20 印度版", "Redmi K20 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L646
        put(m, "M1903F11A", "Redmi K20 Pro 全網通版", "Redmi K20 Pro 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L647
        put(m, "M1903F11C", "Redmi K20 Pro 運營商全網通版", "Redmi K20 Pro 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L648
        put(m, "M1903F11I", "Redmi K20 Pro 印度版", "Redmi K20 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L649
        put(m, "M2001G7AE", "Redmi K30 5G / Redmi K30 5G 極速版", "Redmi K30 5G / Redmi K30 5G 極速版", "Xiaomi", "device_list_full_import"); // Device_List:L650
        put(m, "M2001G7AC", "Redmi K30 5G", "Redmi K30 5G", "Xiaomi", "device_list_full_import"); // Device_List:L651
        put(m, "M1912G7BE", "Redmi K30 4G 全網通版", "Redmi K30 4G 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L652
        put(m, "M1912G7BC", "Redmi K30 4G 運營商全網通版", "Redmi K30 4G 運營商全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L653
        put(m, "M2001J11C", "Redmi K30 Pro", "Redmi K30 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L654
        put(m, "M2001J11E", "Redmi K30 Pro 變焦版", "Redmi K30 Pro 變焦版", "Xiaomi", "device_list_full_import"); // Device_List:L655
        put(m, "M2006J10C", "Redmi K30 至尊紀念版", "Redmi K30 至尊紀念版", "Xiaomi", "device_list_full_import"); // Device_List:L656
        put(m, "M2007J3SC", "Redmi K30S 至尊紀念版", "Redmi K30S 至尊紀念版", "Xiaomi", "device_list_full_import"); // Device_List:L657
        put(m, "M2012K11AC", "Redmi K40", "Redmi K40", "Xiaomi", "device_list_full_import"); // Device_List:L658
        put(m, "M2012K11C", "Redmi K40 Pro", "Redmi K40 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L659
        put(m, "M2012K10C", "Redmi K40 遊戲增強版", "Redmi K40 遊戲增強版", "Xiaomi", "device_list_full_import"); // Device_List:L660
        put(m, "22021211RC", "Redmi K40S", "Redmi K40S", "Xiaomi", "device_list_full_import"); // Device_List:L661
        put(m, "22041211AC", "Redmi K50", "Redmi K50", "Xiaomi", "device_list_full_import"); // Device_List:L662
        put(m, "22011211C", "Redmi K50 Pro", "Redmi K50 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L663
        put(m, "21121210C", "Redmi K50 電競版", "Redmi K50 電競版", "Xiaomi", "device_list_full_import"); // Device_List:L664
        put(m, "22081212C", "Redmi K50 至尊版", "Redmi K50 至尊版", "Xiaomi", "device_list_full_import"); // Device_List:L665
        put(m, "22041216I", "Redmi K50i 印度版", "Redmi K50i 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L666
        put(m, "23013RK75C", "Redmi K60", "Redmi K60", "Xiaomi", "device_list_full_import"); // Device_List:L667
        put(m, "22127RK46C", "Redmi K60 Pro", "Redmi K60 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L668
        put(m, "22122RK93C", "Redmi K60E", "Redmi K60E", "Xiaomi", "device_list_full_import"); // Device_List:L669
        put(m, "23078RKD5C", "Redmi K60 至尊版", "Redmi K60 至尊版", "Xiaomi", "device_list_full_import"); // Device_List:L670
        put(m, "23113RKC6C", "Redmi K70", "Redmi K70", "Xiaomi", "device_list_full_import"); // Device_List:L671
        put(m, "23117RK66C", "Redmi K70 Pro", "Redmi K70 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L672
        put(m, "2311DRK48C", "Redmi K70E", "Redmi K70E", "Xiaomi", "device_list_full_import"); // Device_List:L673
        put(m, "2407FRK8EC", "Redmi K70 至尊版", "Redmi K70 至尊版", "Xiaomi", "device_list_full_import"); // Device_List:L674
        put(m, "24117RK2CC", "REDMI K80", "REDMI K80", "Xiaomi", "device_list_full_import"); // Device_List:L675
        put(m, "24122RKC7C", "REDMI K80 Pro", "REDMI K80 Pro", "Xiaomi", "device_list_full_import"); // Device_List:L676
        put(m, "24127RK2CC", "REDMI K80 Pro 冠軍版", "REDMI K80 Pro 冠軍版", "Xiaomi", "device_list_full_import"); // Device_List:L677
        put(m, "25060RK16C", "REDMI K80 至尊版", "REDMI K80 至尊版", "Xiaomi", "device_list_full_import"); // Device_List:L678
        put(m, "2510DRK44C", "REDMI K90", "REDMI K90", "Xiaomi", "device_list_full_import"); // Device_List:L679
        put(m, "25102RKBEC", "REDMI K90 Pro Max", "REDMI K90 Pro Max", "Xiaomi", "device_list_full_import"); // Device_List:L680
        put(m, "25102RK69C", "REDMI K90 Pro Max 冠軍版", "REDMI K90 Pro Max 冠軍版", "Xiaomi", "device_list_full_import"); // Device_List:L681
        put(m, "2604FRK1EC", "REDMI K90 Max", "REDMI K90 Max", "Xiaomi", "device_list_full_import"); // Device_List:L682
        put(m, "M332BF", "REDMI K90 至尊版", "REDMI K90 至尊版", "Xiaomi", "device_list_full_import"); // Device_List:L683
        put(m, "2016020", "紅米 Pro 標準版", "紅米 Pro 標準版", "Xiaomi", "device_list_full_import"); // Device_List:L684
        put(m, "2016021", "紅米 Pro 高配版 / 尊享版", "紅米 Pro 高配版 / 尊享版", "Xiaomi", "device_list_full_import"); // Device_List:L685
        put(m, "M1803E6E", "紅米 S2 全網通版", "紅米 S2 全網通版", "Xiaomi", "device_list_full_import"); // Device_List:L686
        put(m, "M1803E6T", "紅米 S2 移動 4G+ 版", "紅米 S2 移動 4G+ 版", "Xiaomi", "device_list_full_import"); // Device_List:L687
        put(m, "M1803E6C", "紅米 S2 聯通電信定制版", "紅米 S2 聯通電信定制版", "Xiaomi", "device_list_full_import"); // Device_List:L688
        put(m, "M1803E6H", "紅米 S2 國際版", "紅米 S2 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L689
        put(m, "M1803E6I", "紅米 Y2 印度版", "紅米 Y2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L690
        put(m, "M1810F6G", "Redmi Y3 國際版", "Redmi Y3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L691
        put(m, "M1810F6I", "Redmi Y3 印度版", "Redmi Y3 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L692
        put(m, "M1903C3GH", "Redmi Go 國際版", "Redmi Go 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L693
        put(m, "M1903C3GI", "Redmi Go 印度版", "Redmi Go 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L694
        put(m, "220733SG", "Redmi A1 國際版", "Redmi A1 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L695
        put(m, "220733SI", "Redmi A1 印度版", "Redmi A1 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L696
        put(m, "220733SL", "Redmi A1 拉美版", "Redmi A1 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L697
        put(m, "220733SFG", "Redmi A1+ 國際版", "Redmi A1+ 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L698
        put(m, "220743FI", "Redmi A1+ 印度版", "Redmi A1+ 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L699
        put(m, "23028RN4DG", "Redmi A2 國際版", "Redmi A2 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L700
        put(m, "23028RN4DI", "Redmi A2 印度版", "Redmi A2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L701
        put(m, "23026RN54G", "Redmi A2 拉美版", "Redmi A2 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L702
        put(m, "23028RNCAG", "Redmi A2+ 國際版", "Redmi A2+ 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L703
        put(m, "23028RNCAI", "Redmi A2+ 印度版", "Redmi A2+ 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L704
        put(m, "23129RN51X", "Redmi A3 國際版", "Redmi A3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L705
        put(m, "23129RN51H", "Redmi A3 印度版", "Redmi A3 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L706
        put(m, "2312CRNCCL", "Redmi A3 拉美版", "Redmi A3 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L707
        put(m, "24048RN6CG", "Redmi A3x 國際版", "Redmi A3x 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L708
        put(m, "24048RN6CI", "Redmi A3x 印度版", "Redmi A3x 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L709
        put(m, "24044RN32L", "Redmi A3x 拉美版", "Redmi A3x 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L710
        put(m, "2409BRN2CG", "Redmi A3 Pro 國際版", "Redmi A3 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L711
        put(m, "24116RNC1I", "Redmi A4 5G 印度版", "Redmi A4 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L712
        put(m, "25028RN03Y", "REDMI A5 國際版", "REDMI A5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L713
        put(m, "25028RN03I", "REDMI A5 印度版", "REDMI A5 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L714
        put(m, "25028RN03L", "REDMI A5 拉美版", "REDMI A5 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L715
        put(m, "26020RNB4A", "REDMI A7 國際版", "REDMI A7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L716
        put(m, "26020RNB4I", "REDMI A7 印度版", "REDMI A7 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L717
        put(m, "26020RNB4L", "REDMI A7 拉美版", "REDMI A7 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L718
        put(m, "25128RN17Y", "REDMI A7 Pro 國際版", "REDMI A7 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L719
        put(m, "25128RN17I", "REDMI A7 Pro 印度版", "REDMI A7 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L720
    }

    private static void fill4(Map<String, Entry> m) {
        put(m, "25128RN17L", "REDMI A7 Pro 拉美版", "REDMI A7 Pro 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L721
        put(m, "26020RN1AC", "REDMI R70 5G 國行版 / REDMI R70m 5G 國行版", "REDMI R70 5G 國行版 / REDMI R70m 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L722
        put(m, "26020RN1AI", "REDMI A7 Pro 5G 印度版", "REDMI A7 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L723
        put(m, "22081283C", "Redmi Pad 國行版", "Redmi Pad 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L724
        put(m, "22081283G", "Redmi Pad 國際版", "Redmi Pad 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L725
        put(m, "23073RPBFC", "Redmi Pad SE 國行版", "Redmi Pad SE 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L726
        put(m, "23073RPBFG", "Redmi Pad SE 國際版", "Redmi Pad SE 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L727
        put(m, "23073RPBFL", "Redmi Pad SE 拉美版", "Redmi Pad SE 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L728
        put(m, "2405CRPFDC", "Redmi Pad Pro Wi-Fi 國行版", "Redmi Pad Pro Wi-Fi 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L729
        put(m, "2405CRPFDG", "Redmi Pad Pro Wi-Fi 國際版", "Redmi Pad Pro Wi-Fi 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L730
        put(m, "2405CRPFDI", "Redmi Pad Pro Wi-Fi 印度版", "Redmi Pad Pro Wi-Fi 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L731
        put(m, "2405CRPFDL", "Redmi Pad Pro Wi-Fi 拉美版 / 韓國版", "Redmi Pad Pro Wi-Fi 拉美版 / 韓國版", "Xiaomi", "device_list_full_import"); // Device_List:L732
        put(m, "24074RPD2C", "Redmi Pad Pro 5G 國行版", "Redmi Pad Pro 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L733
        put(m, "24074RPD2G", "Redmi Pad Pro 5G 國際版", "Redmi Pad Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L734
        put(m, "24074RPD2I", "Redmi Pad Pro 5G 印度版", "Redmi Pad Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L735
        put(m, "24075RP89G", "Redmi Pad SE 8.7 Wi-Fi 國際版", "Redmi Pad SE 8.7 Wi-Fi 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L736
        put(m, "24076RP19G", "Redmi Pad SE 8.7 4G 國際版", "Redmi Pad SE 8.7 4G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L737
        put(m, "24076RP19I", "Redmi Pad SE 4G 印度版", "Redmi Pad SE 4G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L738
        put(m, "25040RP0AC", "REDMI Pad 2 國行版", "REDMI Pad 2 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L739
        put(m, "25040RP0AG", "REDMI Pad 2 國際版", "REDMI Pad 2 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L740
        put(m, "25040RP0AI", "REDMI Pad 2 印度版", "REDMI Pad 2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L741
        put(m, "25040RP0AE", "REDMI Pad 2 歐洲版", "REDMI Pad 2 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L742
        put(m, "25040RP0AL", "REDMI Pad 2 拉美版", "REDMI Pad 2 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L743
        put(m, "2505DRP06G", "REDMI Pad 2 4G 國際版", "REDMI Pad 2 4G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L744
        put(m, "2505DRP06I", "REDMI Pad 2 4G 印度版", "REDMI Pad 2 4G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L745
        put(m, "2505DRP06E", "REDMI Pad 2 4G 歐洲版", "REDMI Pad 2 4G 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L746
        put(m, "25099RP13C", "REDMI Pad 2 Pro 國行版", "REDMI Pad 2 Pro 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L747
        put(m, "25099RP13G", "REDMI Pad 2 Pro 國際版", "REDMI Pad 2 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L748
        put(m, "25099RP13I", "REDMI Pad 2 Pro 印度版", "REDMI Pad 2 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L749
        put(m, "2509BRP2DC", "REDMI Pad 2 Pro 5G 國行版", "REDMI Pad 2 Pro 5G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L750
        put(m, "2509BRP2DG", "REDMI Pad 2 Pro 5G 國際版", "REDMI Pad 2 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L751
        put(m, "2509BRP2DI", "REDMI Pad 2 Pro 5G 印度版", "REDMI Pad 2 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L752
        put(m, "2603ARP14C", "REDMI Pad 2 SE 國行版", "REDMI Pad 2 SE 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L753
        put(m, "2603ARP14G", "REDMI Pad 2 9.7 國際版", "REDMI Pad 2 9.7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L754
        put(m, "2604ERP4DC", "REDMI Pad 2 SE 4G 國行版", "REDMI Pad 2 SE 4G 國行版", "Xiaomi", "device_list_full_import"); // Device_List:L755
        put(m, "2604ERP4DG", "REDMI Pad 2 9.7 4G 國際版", "REDMI Pad 2 9.7 4G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L756
        put(m, "2604ERP4DI", "REDMI Pad 2 9.7 4G 印度版", "REDMI Pad 2 9.7 4G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L757
        put(m, "25079RPDCC", "REDMI K Pad", "REDMI K Pad", "Xiaomi", "device_list_full_import"); // Device_List:L758
        put(m, "26048RP6AC", "REDMI K Pad 2", "REDMI K Pad 2", "Xiaomi", "device_list_full_import"); // Device_List:L759
        put(m, "M1805E10A", "POCO F1", "POCO F1", "Xiaomi", "device_list_full_import"); // Device_List:L760
        put(m, "M2004J11G", "POCO F2 Pro 國際版", "POCO F2 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L761
        put(m, "M2012K11AG", "POCO F3 國際版", "POCO F3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L762
        put(m, "M2104K10I", "POCO F3 GT 印度版", "POCO F3 GT 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L763
        put(m, "22021211RG", "POCO F4 國際版", "POCO F4 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L764
        put(m, "22021211RI", "POCO F4 印度版", "POCO F4 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L765
        put(m, "21121210G", "POCO F4 GT 國際版", "POCO F4 GT 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L766
        put(m, "23049PCD8G", "POCO F5 國際版", "POCO F5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L767
        put(m, "23049PCD8I", "POCO F5 印度版", "POCO F5 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L768
        put(m, "23013PC75G", "POCO F5 Pro 國際版", "POCO F5 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L769
        put(m, "24069PC21G", "POCO F6 國際版", "POCO F6 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L770
        put(m, "24069PC21I", "POCO F6 印度版", "POCO F6 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L771
        put(m, "23113RKC6G", "POCO F6 Pro 國際版", "POCO F6 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L772
        put(m, "25053PC47G", "POCO F7 國際版", "POCO F7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L773
        put(m, "25053PC47I", "POCO F7 印度版", "POCO F7 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L774
        put(m, "24117RK2CG", "POCO F7 Pro 國際版", "POCO F7 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L775
        put(m, "24122RKC7G", "POCO F7 Ultra 國際版", "POCO F7 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L776
        put(m, "2510DPC44G", "POCO F8 Pro 國際版", "POCO F8 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L777
        put(m, "25102PCBEG", "POCO F8 Ultra 國際版", "POCO F8 Ultra 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L778
        put(m, "M1912G7BI", "POCO X2 印度版", "POCO X2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L779
        put(m, "M2007J20CI", "POCO X3 印度版", "POCO X3 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L780
        put(m, "M2007J20CG", "POCO X3 NFC 國際版", "POCO X3 NFC 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L781
        put(m, "M2007J20CT", "POCO X3 NFC 泰國版", "POCO X3 NFC 泰國版", "Xiaomi", "device_list_full_import"); // Device_List:L782
        put(m, "M2102J20SG", "POCO X3 Pro 國際版", "POCO X3 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L783
        put(m, "M2102J20SI", "POCO X3 Pro 印度版", "POCO X3 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L784
        put(m, "21061110AG", "POCO X3 GT 國際版", "POCO X3 GT 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L785
        put(m, "2201116PG", "POCO X4 Pro 5G 國際版", "POCO X4 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L786
        put(m, "2201116PI", "POCO X4 Pro 5G 印度版", "POCO X4 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L787
        put(m, "22041216G", "POCO X4 GT 國際版", "POCO X4 GT 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L788
        put(m, "22111317PG", "POCO X5 5G 國際版", "POCO X5 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L789
        put(m, "22111317PI", "POCO X5 5G 印度版", "POCO X5 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L790
        put(m, "22101320G", "POCO X5 Pro 5G 國際版", "POCO X5 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L791
        put(m, "22101320I", "POCO X5 Pro 5G 印度版", "POCO X5 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L792
        put(m, "23122PCD1G", "POCO X6 5G 國際版", "POCO X6 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L793
        put(m, "23122PCD1I", "POCO X6 5G 印度版", "POCO X6 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L794
        put(m, "2311DRK48G", "POCO X6 Pro 5G 國際版", "POCO X6 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L795
        put(m, "2311DRK48I", "POCO X6 Pro 5G 印度版", "POCO X6 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L796
        put(m, "2312FRAFDI", "POCO X6 Neo 印度版", "POCO X6 Neo 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L797
        put(m, "24095PCADG", "POCO X7 國際版", "POCO X7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L798
        put(m, "24095PCADI", "POCO X7 印度版", "POCO X7 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L799
        put(m, "2412DPC0AG", "POCO X7 Pro 國際版", "POCO X7 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L800
        put(m, "2412DPC0AI", "POCO X7 Pro 印度版", "POCO X7 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L801
        put(m, "2511FPC34G", "POCO X8 Pro 國際版", "POCO X8 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L802
        put(m, "2511FPC34I", "POCO X8 Pro 印度版", "POCO X8 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L803
        put(m, "2602BPC18G", "POCO X8 Pro Max 國際版", "POCO X8 Pro Max 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L804
        put(m, "2602BPC18I", "POCO X8 Pro Max 印度版", "POCO X8 Pro Max 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L805
        put(m, "M2004J19PI", "POCO M2 印度版", "POCO M2 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L806
        put(m, "M2003J6CI", "POCO M2 Pro 印度版", "POCO M2 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L807
        put(m, "M2010J19CG", "POCO M3 國際版", "POCO M3 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L808
        put(m, "M2010J19CT", "POCO M3 泰國版", "POCO M3 泰國版", "Xiaomi", "device_list_full_import"); // Device_List:L809
        put(m, "M2010J19CI", "POCO M3 印度版", "POCO M3 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L810
        put(m, "M2103K19PY", "POCO M3 Pro 5G 國際版", "POCO M3 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L811
        put(m, "M2103K19PI", "POCO M3 Pro 5G 印度版", "POCO M3 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L812
        put(m, "22041219PG", "POCO M4 5G 國際版", "POCO M4 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L813
        put(m, "22041219PI", "POCO M4 5G 印度版", "POCO M4 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L814
        put(m, "2201117PG", "POCO M4 Pro 國際版", "POCO M4 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L815
        put(m, "2201117PI", "POCO M4 Pro 印度版", "POCO M4 Pro 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L816
        put(m, "21091116AG", "POCO M4 Pro 5G 國際版", "POCO M4 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L817
        put(m, "22031116AI", "POCO M4 Pro 5G 印度版", "POCO M4 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L818
        put(m, "22071219CG", "POCO M5 國際版", "POCO M5 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L819
        put(m, "22071219CI", "POCO M5 印度版", "POCO M5 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L820
        put(m, "2207117BPG", "POCO M5s 國際版", "POCO M5s 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L821
        put(m, "2404APC5FG", "POCO M6 國際版", "POCO M6 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L822
        put(m, "23128PC33I", "POCO M6 5G 印度版", "POCO M6 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L823
        put(m, "24066PC95I", "POCO M6 Plus 5G 印度版", "POCO M6 Plus 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L824
        put(m, "2312FPCA6G", "POCO M6 Pro 國際版", "POCO M6 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L825
        put(m, "23076PC4BI", "POCO M6 Pro 5G 印度版", "POCO M6 Pro 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L826
        put(m, "25062PC34G", "POCO M7 國際版", "POCO M7 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L827
        put(m, "25062PC34E", "POCO M7 歐洲版", "POCO M7 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L828
        put(m, "24108PCE2I", "POCO M7 5G 印度版", "POCO M7 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L829
        put(m, "25057PC09I", "POCO M7 Plus 5G 印度版", "POCO M7 Plus 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L830
        put(m, "26067PC09G", "POCO M8s 5G 國際版", "POCO M8s 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L831
        put(m, "26067PC09E", "POCO M8s 5G 歐洲版", "POCO M8s 5G 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L832
        put(m, "2409FPCC4G", "POCO M7 Pro 5G 國際版", "POCO M7 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L833
        put(m, "25118PC98G", "POCO M8 5G 國際版", "POCO M8 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L834
        put(m, "25118PC98I", "POCO M8 5G 印度版", "POCO M8 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L835
        put(m, "2510EPC8BG", "POCO M8 Pro 5G 國際版", "POCO M8 Pro 5G 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L836
        put(m, "M2006C3MI", "POCO C3 印度版", "POCO C3 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L837
        put(m, "211033MI", "POCO C31 印度版", "POCO C31 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L838
        put(m, "220333QPG", "POCO C40 國際版", "POCO C40 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L839
        put(m, "220333QPI", "POCO C40 印度版", "POCO C40 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L840
        put(m, "220733SPI", "POCO C50 印度版", "POCO C50 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L841
        put(m, "2305EPCC4G", "POCO C51 國際版", "POCO C51 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L842
        put(m, "2302EPCC4I", "POCO C51 印度版", "POCO C51 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L843
        put(m, "22127PC95G", "POCO C55 國際版", "POCO C55 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L844
        put(m, "22127PC95I", "POCO C55 印度版", "POCO C55 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L845
        put(m, "2312BPC51X", "POCO C61 國際版", "POCO C61 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L846
        put(m, "2312BPC51H", "POCO C61 印度版", "POCO C61 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L847
        put(m, "2310FPCA4G", "POCO C65 國際版", "POCO C65 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L848
        put(m, "2310FPCA4I", "POCO C65 印度版", "POCO C65 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L849
        put(m, "25028PC03Y", "POCO C71 國際版", "POCO C71 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L850
        put(m, "25028PC03I", "POCO C71 印度版", "POCO C71 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L851
        put(m, "25028PC03L", "POCO C71 拉美版", "POCO C71 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L852
        put(m, "2410FPCC5G", "POCO C75 國際版", "POCO C75 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L853
        put(m, "2410FPCC5I", "POCO C75 印度版", "POCO C75 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L854
        put(m, "24116PCC1I", "POCO C75 5G 印度版", "POCO C75 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L855
        put(m, "25128PC17Y", "POCO C81 Pro 國際版", "POCO C81 Pro 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L856
        put(m, "25128PC17L", "POCO C81 Pro 拉美版", "POCO C81 Pro 拉美版", "Xiaomi", "device_list_full_import"); // Device_List:L857
        put(m, "25128PC17I", "POCO C81 印度版", "POCO C81 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L858
        put(m, "26020PCB4I", "POCO C81x 印度版", "POCO C81x 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L859
        put(m, "25078PC3EG", "POCO C85 國際版", "POCO C85 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L860
        put(m, "25078PC3EE", "POCO C85 歐洲版", "POCO C85 歐洲版", "Xiaomi", "device_list_full_import"); // Device_List:L861
        put(m, "2508CPC2BI", "POCO C85 5G 印度版", "POCO C85 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L862
        put(m, "26020PC1AI", "POCO C85x 5G 印度版", "POCO C85x 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L863
        put(m, "2405CPCFBG", "POCO Pad Wi-Fi 國際版", "POCO Pad Wi-Fi 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L864
        put(m, "24074PCD2I", "POCO Pad 5G 印度版", "POCO Pad 5G 印度版", "Xiaomi", "device_list_full_import"); // Device_List:L865
        put(m, "25099RP08G", "POCO Pad X1 國際版", "POCO Pad X1 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L866
        put(m, "2509ARPBDG", "POCO Pad M1 國際版", "POCO Pad M1 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L867
        put(m, "2603APC14G", "POCO Pad C1 國際版", "POCO Pad C1 國際版", "Xiaomi", "device_list_full_import"); // Device_List:L868
        put(m, "FYJ01QP", "小米米家翻譯機", "小米米家翻譯機", "Xiaomi", "device_list_full_import"); // Device_List:L869
        put(m, "21051191C", "CyberDog 仿生四足機器人", "CyberDog 仿生四足機器人", "", "device_list_full_import"); // Device_List:L870
        put(m, "2405AVPB7C", "小米澎湃智能座艙 (第一代 SU7/SU7 Ultra)", "小米澎湃智能座艙 (第一代 SU7/SU7 Ultra)", "Xiaomi", "device_list_full_import"); // Device_List:L871
        put(m, "25033VP3FC", "小米澎湃智能座艙 (YU7/新一代 SU7)", "小米澎湃智能座艙 (YU7/新一代 SU7)", "Xiaomi", "device_list_full_import"); // Device_List:L872
        put(m, "2503CVPC6C", "小米汽車後排移動控制屏", "小米汽車後排移動控制屏", "Xiaomi", "device_list_full_import"); // Device_List:L873
        put(m, "2312DRA50C", "Redmi Note 13 Pro 5G China (LPDDR4x + UFS 2.2)", "Redmi Note 13 Pro 5G China (LPDDR4x + UFS 2.2)", "Xiaomi", "device_list_full_import"); // Device_List:L875
        put(m, "GT-I9000", "Galaxy S 公開版", "Galaxy S 公開版", "Samsung", "device_list_full_import"); // Device_List:L876
        put(m, "GT-I9018", "Galaxy S 移動定制版", "Galaxy S 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L877
        put(m, "SCH-i909", "Galaxy S 電信定制版", "Galaxy S 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L878
        put(m, "GT-I9100", "Galaxy S2 (Exynos)", "Galaxy S2 (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L879
        put(m, "GT-I9100G", "Galaxy S2 (德州儀器)", "Galaxy S2 (德州儀器)", "Samsung", "device_list_full_import"); // Device_List:L880
        put(m, "GT-I9108", "Galaxy S2 移動定制版", "Galaxy S2 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L881
        put(m, "SCH-I919", "Galaxy S Duos 電信定制版", "Galaxy S Duos 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L882
        put(m, "GT-I9300", "Galaxy S3 公開版", "Galaxy S3 公開版", "Samsung", "device_list_full_import"); // Device_List:L883
        put(m, "GT-I9308", "Galaxy S3 移動定制版", "Galaxy S3 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L884
        put(m, "SCH-I939", "Galaxy S3 電信定制版", "Galaxy S3 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L885
        put(m, "SCH-I939D", "Galaxy S3 電信雙卡定制版", "Galaxy S3 電信雙卡定制版", "Samsung", "device_list_full_import"); // Device_List:L886
        put(m, "GT-I9300I", "Galaxy S3 Neo+ 公開版", "Galaxy S3 Neo+ 公開版", "Samsung", "device_list_full_import"); // Device_List:L887
        put(m, "GT-I9308I", "Galaxy S3 Neo+ 移動定制版", "Galaxy S3 Neo+ 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L888
        put(m, "SCH-I939I", "Galaxy S3 Neo+ 電信定制版", "Galaxy S3 Neo+ 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L889
        put(m, "GT-I8190N", "Galaxy S3 Mini", "Galaxy S3 Mini", "Samsung", "device_list_full_import"); // Device_List:L890
        put(m, "GT-I9500", "Galaxy S4 公開版", "Galaxy S4 公開版", "Samsung", "device_list_full_import"); // Device_List:L891
        put(m, "GT-I9502", "Galaxy S4 聯通定制版", "Galaxy S4 聯通定制版", "Samsung", "device_list_full_import"); // Device_List:L892
        put(m, "GT-I9508", "Galaxy S4 移動定制版", "Galaxy S4 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L893
        put(m, "SCH-I959", "Galaxy S4 電信定制版", "Galaxy S4 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L894
        put(m, "GT-I9507V", "Galaxy S4 聯通 4G 定制版", "Galaxy S4 聯通 4G 定制版", "Samsung", "device_list_full_import"); // Device_List:L895
        put(m, "GT-I9508V", "Galaxy S4 移動 4G 定制版", "Galaxy S4 移動 4G 定制版", "Samsung", "device_list_full_import"); // Device_List:L896
        put(m, "SM-C101", "Galaxy S4 zoom", "Galaxy S4 zoom", "Samsung", "device_list_full_import"); // Device_List:L897
        put(m, "SM-G9009D", "Galaxy S5 電信 3G 雙卡版", "Galaxy S5 電信 3G 雙卡版", "Samsung", "device_list_full_import"); // Device_List:L898
        put(m, "SM-G9006V", "Galaxy S5 聯通 4G 單卡版", "Galaxy S5 聯通 4G 單卡版", "Samsung", "device_list_full_import"); // Device_List:L899
        put(m, "SM-G9008V", "Galaxy S5 移動 4G 單卡版", "Galaxy S5 移動 4G 單卡版", "Samsung", "device_list_full_import"); // Device_List:L900
        put(m, "SM-G9006W", "Galaxy S5 聯通 4G 雙卡版", "Galaxy S5 聯通 4G 雙卡版", "Samsung", "device_list_full_import"); // Device_List:L901
    }

    private static void fill5(Map<String, Entry> m) {
        put(m, "SM-G9008W", "Galaxy S5 移動 4G 雙卡版", "Galaxy S5 移動 4G 雙卡版", "Samsung", "device_list_full_import"); // Device_List:L902
        put(m, "SM-G9009W", "Galaxy S5 電信 4G 雙卡版", "Galaxy S5 電信 4G 雙卡版", "Samsung", "device_list_full_import"); // Device_List:L903
        put(m, "SM-G9200", "Galaxy S6 全網通版", "Galaxy S6 全網通版", "Samsung", "device_list_full_import"); // Device_List:L904
        put(m, "SM-G9208", "Galaxy S6 移動定制版", "Galaxy S6 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L905
        put(m, "SM-G9209", "Galaxy S6 電信定制版", "Galaxy S6 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L906
        put(m, "SM-G9250", "Galaxy S6 edge", "Galaxy S6 edge", "Samsung", "device_list_full_import"); // Device_List:L907
        put(m, "SM-G9280", "Galaxy S6 edge+", "Galaxy S6 edge+", "Samsung", "device_list_full_import"); // Device_List:L908
        put(m, "SM-G9300", "Galaxy S7 全網通版", "Galaxy S7 全網通版", "Samsung", "device_list_full_import"); // Device_List:L909
        put(m, "SM-G9308", "Galaxy S7 移動定制版", "Galaxy S7 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L910
        put(m, "SM-G9350", "Galaxy S7 edge", "Galaxy S7 edge", "Samsung", "device_list_full_import"); // Device_List:L911
        put(m, "SM-G9500", "Galaxy S8 全網通版", "Galaxy S8 全網通版", "Samsung", "device_list_full_import"); // Device_List:L912
        put(m, "SM-G9508", "Galaxy S8 4G+", "Galaxy S8 4G+", "Samsung", "device_list_full_import"); // Device_List:L913
        put(m, "SM-G9550", "Galaxy S8+", "Galaxy S8+", "Samsung", "device_list_full_import"); // Device_List:L914
        put(m, "SM-G9600/DS", "Galaxy S9 全網通版", "Galaxy S9 全網通版", "Samsung", "device_list_full_import"); // Device_List:L915
        put(m, "SM-G9608/DS", "Galaxy S9 4G+", "Galaxy S9 4G+", "Samsung", "device_list_full_import"); // Device_List:L916
        put(m, "SM-G9650/DS", "Galaxy S9+", "Galaxy S9+", "Samsung", "device_list_full_import"); // Device_List:L917
        put(m, "SM-G8750", "Galaxy S 輕奢版", "Galaxy S 輕奢版", "Samsung", "device_list_full_import"); // Device_List:L918
        put(m, "SM-G9700", "Galaxy S10e 全網通版", "Galaxy S10e 全網通版", "Samsung", "device_list_full_import"); // Device_List:L919
        put(m, "SM-G9708", "Galaxy S10e 4G+", "Galaxy S10e 4G+", "Samsung", "device_list_full_import"); // Device_List:L920
        put(m, "SM-G9730", "Galaxy S10 全網通版", "Galaxy S10 全網通版", "Samsung", "device_list_full_import"); // Device_List:L921
        put(m, "SM-G9738", "Galaxy S10 4G+", "Galaxy S10 4G+", "Samsung", "device_list_full_import"); // Device_List:L922
        put(m, "SM-G9750", "Galaxy S10+ 全網通版", "Galaxy S10+ 全網通版", "Samsung", "device_list_full_import"); // Device_List:L923
        put(m, "SM-G9758", "Galaxy S10+ 4G+", "Galaxy S10+ 4G+", "Samsung", "device_list_full_import"); // Device_List:L924
        put(m, "SM-G9810", "Galaxy S20 5G", "Galaxy S20 5G", "Samsung", "device_list_full_import"); // Device_List:L925
        put(m, "SM-G9860", "Galaxy S20+ 5G", "Galaxy S20+ 5G", "Samsung", "device_list_full_import"); // Device_List:L926
        put(m, "SM-G9880", "Galaxy S20 Ultra 5G", "Galaxy S20 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L927
        put(m, "SM-G7810", "Galaxy S20 FE 5G", "Galaxy S20 FE 5G", "Samsung", "device_list_full_import"); // Device_List:L928
        put(m, "SM-G9910", "Galaxy S21 5G", "Galaxy S21 5G", "Samsung", "device_list_full_import"); // Device_List:L929
        put(m, "SM-G9960", "Galaxy S21+ 5G", "Galaxy S21+ 5G", "Samsung", "device_list_full_import"); // Device_List:L930
        put(m, "SM-G9980", "Galaxy S21 Ultra 5G", "Galaxy S21 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L931
        put(m, "SM-G9900", "Galaxy S21 FE 5G", "Galaxy S21 FE 5G", "Samsung", "device_list_full_import"); // Device_List:L932
        put(m, "SM-S9010", "Galaxy S22", "Galaxy S22", "Samsung", "device_list_full_import"); // Device_List:L933
        put(m, "SM-S9060", "Galaxy S22+", "Galaxy S22+", "Samsung", "device_list_full_import"); // Device_List:L934
        put(m, "SM-S9080", "Galaxy S22 Ultra", "Galaxy S22 Ultra", "Samsung", "device_list_full_import"); // Device_List:L935
        put(m, "SM-S9110", "Galaxy S23", "Galaxy S23", "Samsung", "device_list_full_import"); // Device_List:L936
        put(m, "SM-S9160", "Galaxy S23+", "Galaxy S23+", "Samsung", "device_list_full_import"); // Device_List:L937
        put(m, "SM-S9180", "Galaxy S23 Ultra", "Galaxy S23 Ultra", "Samsung", "device_list_full_import"); // Device_List:L938
        put(m, "SM-S7110", "Galaxy S23 FE", "Galaxy S23 FE", "Samsung", "device_list_full_import"); // Device_List:L939
        put(m, "SM-S9210", "Galaxy S24", "Galaxy S24", "Samsung", "device_list_full_import"); // Device_List:L940
        put(m, "SM-S9260", "Galaxy S24+", "Galaxy S24+", "Samsung", "device_list_full_import"); // Device_List:L941
        put(m, "SM-S9280", "Galaxy S24 Ultra", "Galaxy S24 Ultra", "Samsung", "device_list_full_import"); // Device_List:L942
        put(m, "SM-S9310", "Galaxy S25", "Galaxy S25", "Samsung", "device_list_full_import"); // Device_List:L943
        put(m, "SM-S9360", "Galaxy S25+", "Galaxy S25+", "Samsung", "device_list_full_import"); // Device_List:L944
        put(m, "SM-S9370", "Galaxy S25 Edge", "Galaxy S25 Edge", "Samsung", "device_list_full_import"); // Device_List:L945
        put(m, "SM-S9380", "Galaxy S25 Ultra", "Galaxy S25 Ultra", "Samsung", "device_list_full_import"); // Device_List:L946
        put(m, "SM-S9420", "Galaxy S26", "Galaxy S26", "Samsung", "device_list_full_import"); // Device_List:L947
        put(m, "SM-S9470", "Galaxy S26+", "Galaxy S26+", "Samsung", "device_list_full_import"); // Device_List:L948
        put(m, "SM-S9480", "Galaxy S26 Ultra", "Galaxy S26 Ultra", "Samsung", "device_list_full_import"); // Device_List:L949
        put(m, "GT-I9220", "Galaxy Note 公開版", "Galaxy Note 公開版", "Samsung", "device_list_full_import"); // Device_List:L950
        put(m, "GT-I9228", "Galaxy Note 移動定制版", "Galaxy Note 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L951
        put(m, "SCH-I889", "Galaxy Note 電信定制版", "Galaxy Note 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L952
        put(m, "GT-N7100", "Galaxy Note2 公開版", "Galaxy Note2 公開版", "Samsung", "device_list_full_import"); // Device_List:L953
        put(m, "GT-N7102i", "Galaxy Note2 聯通定制版", "Galaxy Note2 聯通定制版", "Samsung", "device_list_full_import"); // Device_List:L954
        put(m, "GT-N7108", "Galaxy Note2 移動定制版", "Galaxy Note2 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L955
        put(m, "GT-N7108D", "Galaxy Note2 移動 4G 定制版", "Galaxy Note2 移動 4G 定制版", "Samsung", "device_list_full_import"); // Device_List:L956
        put(m, "SCH-N719", "Galaxy Note2 電信定制版", "Galaxy Note2 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L957
        put(m, "SM-N9002", "Galaxy Note3 聯通定制版", "Galaxy Note3 聯通定制版", "Samsung", "device_list_full_import"); // Device_List:L958
        put(m, "SM-N9006", "Galaxy Note3 公開版", "Galaxy Note3 公開版", "Samsung", "device_list_full_import"); // Device_List:L959
        put(m, "SM-N9008", "Galaxy Note3 移動定制版", "Galaxy Note3 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L960
        put(m, "SM-N9008V", "Galaxy Note3 移動 4G 定制版", "Galaxy Note3 移動 4G 定制版", "Samsung", "device_list_full_import"); // Device_List:L961
        put(m, "SM-N9008S", "Galaxy Note3 4G 公開版", "Galaxy Note3 4G 公開版", "Samsung", "device_list_full_import"); // Device_List:L962
        put(m, "SM-N9009", "Galaxy Note3 電信定制版", "Galaxy Note3 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L963
        put(m, "SM-N7506V", "Galaxy Note3 Lite 聯通定制版", "Galaxy Note3 Lite 聯通定制版", "Samsung", "device_list_full_import"); // Device_List:L964
        put(m, "SM-N7508V", "Galaxy Note3 Lite 移動定制版", "Galaxy Note3 Lite 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L965
        put(m, "SM-N7509V", "Galaxy Note3 Lite 電信定制版", "Galaxy Note3 Lite 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L966
        put(m, "SM-N9100", "Galaxy Note4 公開版", "Galaxy Note4 公開版", "Samsung", "device_list_full_import"); // Device_List:L967
        put(m, "SM-N9106W", "Galaxy Note4 聯通定制版", "Galaxy Note4 聯通定制版", "Samsung", "device_list_full_import"); // Device_List:L968
        put(m, "SM-N9108V", "Galaxy Note4 移動定制版", "Galaxy Note4 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L969
        put(m, "SM-N9109W", "Galaxy Note4 電信定制版", "Galaxy Note4 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L970
        put(m, "SM-N9150", "Galaxy Note Edge", "Galaxy Note Edge", "Samsung", "device_list_full_import"); // Device_List:L971
        put(m, "SM-N9200", "Galaxy Note5 全網通版", "Galaxy Note5 全網通版", "Samsung", "device_list_full_import"); // Device_List:L972
        put(m, "SM-N9208", "Galaxy Note5 移動定制版", "Galaxy Note5 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L973
        put(m, "SM-N9300", "Galaxy Note7", "Galaxy Note7", "Samsung", "device_list_full_import"); // Device_List:L974
        put(m, "SM-N9500", "Galaxy Note8 全網通版", "Galaxy Note8 全網通版", "Samsung", "device_list_full_import"); // Device_List:L975
        put(m, "SM-N9508", "Galaxy Note8 4G+", "Galaxy Note8 4G+", "Samsung", "device_list_full_import"); // Device_List:L976
        put(m, "SM-N9600", "Galaxy Note9 全網通版", "Galaxy Note9 全網通版", "Samsung", "device_list_full_import"); // Device_List:L977
        put(m, "SM-N9608", "Galaxy Note9 4G+", "Galaxy Note9 4G+", "Samsung", "device_list_full_import"); // Device_List:L978
        put(m, "SM-N9700", "Galaxy Note10", "Galaxy Note10", "Samsung", "device_list_full_import"); // Device_List:L979
        put(m, "SM-N9760", "Galaxy Note10+ 5G", "Galaxy Note10+ 5G", "Samsung", "device_list_full_import"); // Device_List:L980
        put(m, "SM-N9810", "Galaxy Note20 5G", "Galaxy Note20 5G", "Samsung", "device_list_full_import"); // Device_List:L981
        put(m, "SM-N9860", "Galaxy Note20 Ultra 5G", "Galaxy Note20 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L982
        put(m, "SM-F9000", "Galaxy Fold", "Galaxy Fold", "Samsung", "device_list_full_import"); // Device_List:L983
        put(m, "SM-F9160", "Galaxy Z Fold2 5G", "Galaxy Z Fold2 5G", "Samsung", "device_list_full_import"); // Device_List:L984
        put(m, "SM-F9260", "Galaxy Z Fold3 5G", "Galaxy Z Fold3 5G", "Samsung", "device_list_full_import"); // Device_List:L985
        put(m, "SM-F9360", "Galaxy Z Fold4", "Galaxy Z Fold4", "Samsung", "device_list_full_import"); // Device_List:L986
        put(m, "SM-F9460", "Galaxy Z Fold5", "Galaxy Z Fold5", "Samsung", "device_list_full_import"); // Device_List:L987
        put(m, "SM-F9560", "Galaxy Z Fold6", "Galaxy Z Fold6", "Samsung", "device_list_full_import"); // Device_List:L988
        put(m, "SM-F9660", "Galaxy Z Fold7", "Galaxy Z Fold7", "Samsung", "device_list_full_import"); // Device_List:L989
        put(m, "SM-F9680", "Galaxy Z TriFold", "Galaxy Z TriFold", "Samsung", "device_list_full_import"); // Device_List:L990
        put(m, "SM-F7000", "Galaxy Z Flip", "Galaxy Z Flip", "Samsung", "device_list_full_import"); // Device_List:L991
        put(m, "SM-F7070", "Galaxy Z Flip 5G", "Galaxy Z Flip 5G", "Samsung", "device_list_full_import"); // Device_List:L992
        put(m, "SM-F7110", "Galaxy Z Flip3 5G", "Galaxy Z Flip3 5G", "Samsung", "device_list_full_import"); // Device_List:L993
        put(m, "SM-F7210", "Galaxy Z Flip4", "Galaxy Z Flip4", "Samsung", "device_list_full_import"); // Device_List:L994
        put(m, "SM-F7310", "Galaxy Z Flip5", "Galaxy Z Flip5", "Samsung", "device_list_full_import"); // Device_List:L995
        put(m, "SM-F7410", "Galaxy Z Flip6", "Galaxy Z Flip6", "Samsung", "device_list_full_import"); // Device_List:L996
        put(m, "SM-F7660", "Galaxy Z Flip7", "Galaxy Z Flip7", "Samsung", "device_list_full_import"); // Device_List:L997
        put(m, "SM-F7610", "Galaxy Z Flip7 FE", "Galaxy Z Flip7 FE", "Samsung", "device_list_full_import"); // Device_List:L998
        put(m, "SM-A3000", "Galaxy A3 公開版", "Galaxy A3 公開版", "Samsung", "device_list_full_import"); // Device_List:L999
        put(m, "SM-A3009", "Galaxy A3 電信定制版", "Galaxy A3 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1000
        put(m, "SM-A5000", "Galaxy A5 公開版", "Galaxy A5 公開版", "Samsung", "device_list_full_import"); // Device_List:L1001
        put(m, "SM-A5009", "Galaxy A5 電信定制版", "Galaxy A5 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1002
        put(m, "SM-A7000", "Galaxy A7 公開版", "Galaxy A7 公開版", "Samsung", "device_list_full_import"); // Device_List:L1003
        put(m, "SM-A7009", "Galaxy A7 電信定制版", "Galaxy A7 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1004
        put(m, "SM-A8000", "Galaxy A8", "Galaxy A8", "Samsung", "device_list_full_import"); // Device_List:L1005
        put(m, "SM-A5100", "Galaxy A5 (2016) 全網通版", "Galaxy A5 (2016) 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1006
        put(m, "SM-A5108", "Galaxy A5 (2016) 移動定制疾速版", "Galaxy A5 (2016) 移動定制疾速版", "Samsung", "device_list_full_import"); // Device_List:L1007
        put(m, "SM-A7100", "Galaxy A7 (2016) 全網通版", "Galaxy A7 (2016) 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1008
        put(m, "SM-A7108", "Galaxy A7 (2016) 移動定制疾速版", "Galaxy A7 (2016) 移動定制疾速版", "Samsung", "device_list_full_import"); // Device_List:L1009
        put(m, "SM-A9000", "Galaxy A9 (2016)", "Galaxy A9 (2016)", "Samsung", "device_list_full_import"); // Device_List:L1010
        put(m, "SM-A9100", "Galaxy A9 高配版", "Galaxy A9 高配版", "Samsung", "device_list_full_import"); // Device_List:L1011
        put(m, "SM-G8850", "Galaxy A9 Star 全網通版", "Galaxy A9 Star 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1012
        put(m, "SM-G8858", "Galaxy A9 Star 4G+", "Galaxy A9 Star 4G+", "Samsung", "device_list_full_import"); // Device_List:L1013
        put(m, "SM-A6050", "Galaxy A9 Star Lite 全網通版", "Galaxy A9 Star Lite 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1014
        put(m, "SM-A6058", "Galaxy A9 Star Lite 4G+", "Galaxy A9 Star Lite 4G+", "Samsung", "device_list_full_import"); // Device_List:L1015
        put(m, "SM-G6200", "Galaxy A6s", "Galaxy A6s", "Samsung", "device_list_full_import"); // Device_List:L1016
        put(m, "SM-G8870", "Galaxy A8s", "Galaxy A8s", "Samsung", "device_list_full_import"); // Device_List:L1017
        put(m, "SM-A9200", "Galaxy A9s", "Galaxy A9s", "Samsung", "device_list_full_import"); // Device_List:L1018
        put(m, "SM-A2070", "Galaxy A20s", "Galaxy A20s", "Samsung", "device_list_full_import"); // Device_List:L1019
        put(m, "SM-A3050", "Galaxy A40s 全網通版", "Galaxy A40s 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1020
        put(m, "SM-A3058", "Galaxy A40s 4G+", "Galaxy A40s 4G+", "Samsung", "device_list_full_import"); // Device_List:L1021
        put(m, "SM-A5070", "Galaxy A50s", "Galaxy A50s", "Samsung", "device_list_full_import"); // Device_List:L1022
        put(m, "SM-A6060", "Galaxy A60", "Galaxy A60", "Samsung", "device_list_full_import"); // Device_List:L1023
        put(m, "SM-A7050", "Galaxy A70", "Galaxy A70", "Samsung", "device_list_full_import"); // Device_List:L1024
        put(m, "SM-A7070", "Galaxy A70s", "Galaxy A70s", "Samsung", "device_list_full_import"); // Device_List:L1025
        put(m, "SM-A8050", "Galaxy A80", "Galaxy A80", "Samsung", "device_list_full_import"); // Device_List:L1026
        put(m, "SM-A9080", "Galaxy A90 5G", "Galaxy A90 5G", "Samsung", "device_list_full_import"); // Device_List:L1027
        put(m, "SM-A5160", "Galaxy A51 5G", "Galaxy A51 5G", "Samsung", "device_list_full_import"); // Device_List:L1028
        put(m, "SM-A7160", "Galaxy A71 5G", "Galaxy A71 5G", "Samsung", "device_list_full_import"); // Device_List:L1029
        put(m, "SM-A5260", "Galaxy A52 5G", "Galaxy A52 5G", "Samsung", "device_list_full_import"); // Device_List:L1030
        put(m, "SM-A5360", "Galaxy A53 5G", "Galaxy A53 5G", "Samsung", "device_list_full_import"); // Device_List:L1031
        put(m, "SM-A5460", "Galaxy A54 5G", "Galaxy A54 5G", "Samsung", "device_list_full_import"); // Device_List:L1032
        put(m, "SM-A5560", "Galaxy A55 5G", "Galaxy A55 5G", "Samsung", "device_list_full_import"); // Device_List:L1033
        put(m, "SM-A5660", "Galaxy A56 5G", "Galaxy A56 5G", "Samsung", "device_list_full_import"); // Device_List:L1034
        put(m, "SM-A5760", "Galaxy A57 5G", "Galaxy A57 5G", "Samsung", "device_list_full_import"); // Device_List:L1035
        put(m, "SM-E5260", "Galaxy F52 5G", "Galaxy F52 5G", "Samsung", "device_list_full_import"); // Device_List:L1036
        put(m, "SM-M3070", "Galaxy M30s", "Galaxy M30s", "Samsung", "device_list_full_import"); // Device_List:L1037
        put(m, "SM-C5000", "Galaxy C5", "Galaxy C5", "Samsung", "device_list_full_import"); // Device_List:L1038
        put(m, "SM-C5010", "Galaxy C5 Pro 全網通版", "Galaxy C5 Pro 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1039
        put(m, "SM-C5018", "Galaxy C5 Pro 4G+", "Galaxy C5 Pro 4G+", "Samsung", "device_list_full_import"); // Device_List:L1040
        put(m, "SM-C7000", "Galaxy C7", "Galaxy C7", "Samsung", "device_list_full_import"); // Device_List:L1041
        put(m, "SM-C7010", "Galaxy C7 Pro 全網通版", "Galaxy C7 Pro 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1042
        put(m, "SM-C7018", "Galaxy C7 Pro 4G+", "Galaxy C7 Pro 4G+", "Samsung", "device_list_full_import"); // Device_List:L1043
        put(m, "SM-C7100", "Galaxy C8 全網通版", "Galaxy C8 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1044
        put(m, "SM-C7108", "Galaxy C8 4G+", "Galaxy C8 4G+", "Samsung", "device_list_full_import"); // Device_List:L1045
        put(m, "SM-C9000", "Galaxy C9 Pro 全網通版", "Galaxy C9 Pro 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1046
        put(m, "SM-C9008", "Galaxy C9 Pro 4G+", "Galaxy C9 Pro 4G+", "Samsung", "device_list_full_import"); // Device_List:L1047
        put(m, "SM-C5560", "Galaxy C55 5G", "Galaxy C55 5G", "Samsung", "device_list_full_import"); // Device_List:L1048
        put(m, "SM-J3109", "Galaxy J3 電信定制版", "Galaxy J3 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1049
        put(m, "SM-J5008", "Galaxy J5 移動定制版", "Galaxy J5 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L1050
        put(m, "SM-J7008", "Galaxy J7 移動定制版", "Galaxy J7 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L1051
        put(m, "SM-J3110", "Galaxy J3 Pro 公開版", "Galaxy J3 Pro 公開版", "Samsung", "device_list_full_import"); // Device_List:L1052
        put(m, "SM-J3119", "Galaxy J3 Pro 電信定制版", "Galaxy J3 Pro 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1053
        put(m, "SM-J3119S", "Galaxy J3 Pro 增強版 電信定制版", "Galaxy J3 Pro 增強版 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1054
        put(m, "SM-J5108", "Galaxy J5 (2016) 移動定制版", "Galaxy J5 (2016) 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L1055
        put(m, "SM-J7108", "Galaxy J7 (2016) 移動定制版", "Galaxy J7 (2016) 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L1056
        put(m, "SM-J7109", "Galaxy J7 (2016) 電信定制版", "Galaxy J7 (2016) 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1057
        put(m, "SM-J3300", "Galaxy J3 (2017) 全網通版", "Galaxy J3 (2017) 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1058
        put(m, "SM-J3308", "Galaxy J3 (2017) 4G+", "Galaxy J3 (2017) 4G+", "Samsung", "device_list_full_import"); // Device_List:L1059
        put(m, "SM-G5500", "Galaxy On5", "Galaxy On5", "Samsung", "device_list_full_import"); // Device_List:L1060
        put(m, "SM-G6000", "Galaxy On7", "Galaxy On7", "Samsung", "device_list_full_import"); // Device_List:L1061
        put(m, "SM-G5700", "Galaxy On5 (2016) 全網通版", "Galaxy On5 (2016) 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1062
        put(m, "SM-G5510", "Galaxy On5 (2016) 青春版 全網通版", "Galaxy On5 (2016) 青春版 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1063
        put(m, "SM-G5520", "Galaxy On5 (2016) 時尚版 全網通版", "Galaxy On5 (2016) 時尚版 全網通版", "Samsung", "device_list_full_import"); // Device_List:L1064
        put(m, "SM-G5528", "Galaxy On5 (2016) 時尚版 移動定制版", "Galaxy On5 (2016) 時尚版 移動定制版", "Samsung", "device_list_full_import"); // Device_List:L1065
        put(m, "SM-G6100", "Galaxy On7 (2016)", "Galaxy On7 (2016)", "Samsung", "device_list_full_import"); // Device_List:L1066
        put(m, "SCH-W699", "三星 W699", "三星 W699", "Samsung", "device_list_full_import"); // Device_List:L1067
        put(m, "SCH-W799", "三星 W799", "三星 W799", "Samsung", "device_list_full_import"); // Device_List:L1068
        put(m, "SCH-W899", "三星 W899", "三星 W899", "Samsung", "device_list_full_import"); // Device_List:L1069
        put(m, "SCH-W999", "三星 W999", "三星 W999", "Samsung", "device_list_full_import"); // Device_List:L1070
        put(m, "SCH-W2013", "三星 W2013", "三星 W2013", "Samsung", "device_list_full_import"); // Device_List:L1071
        put(m, "SM-W2014", "三星 W2014", "三星 W2014", "Samsung", "device_list_full_import"); // Device_List:L1072
        put(m, "SM-W2015", "三星 W2015", "三星 W2015", "Samsung", "device_list_full_import"); // Device_List:L1073
        put(m, "SM-W2016", "三星 W2016", "三星 W2016", "Samsung", "device_list_full_import"); // Device_List:L1074
        put(m, "SM-W2017", "三星 W2017", "三星 W2017", "Samsung", "device_list_full_import"); // Device_List:L1075
        put(m, "SM-W2018", "三星 W2018", "三星 W2018", "Samsung", "device_list_full_import"); // Device_List:L1076
        put(m, "SM-W2019", "三星 W2019", "三星 W2019", "Samsung", "device_list_full_import"); // Device_List:L1077
        put(m, "SM-W2020", "三星 W20 5G", "三星 W20 5G", "Samsung", "device_list_full_import"); // Device_List:L1078
        put(m, "SM-W2021", "三星 W21 5G", "三星 W21 5G", "Samsung", "device_list_full_import"); // Device_List:L1079
        put(m, "SM-W2022", "三星 W22 5G", "三星 W22 5G", "Samsung", "device_list_full_import"); // Device_List:L1080
        put(m, "SM-W9023", "三星 W23", "三星 W23", "Samsung", "device_list_full_import"); // Device_List:L1081
    }

    private static void fill6(Map<String, Entry> m) {
        put(m, "SM-W7023", "三星 W23 Flip", "三星 W23 Flip", "Samsung", "device_list_full_import"); // Device_List:L1082
        put(m, "SM-W9024", "三星 W24", "三星 W24", "Samsung", "device_list_full_import"); // Device_List:L1083
        put(m, "SM-W7024", "三星 W24 Flip", "三星 W24 Flip", "Samsung", "device_list_full_import"); // Device_List:L1084
        put(m, "SM-W9025", "三星 W25", "三星 W25", "Samsung", "device_list_full_import"); // Device_List:L1085
        put(m, "SM-W7025", "三星 W25 Flip", "三星 W25 Flip", "Samsung", "device_list_full_import"); // Device_List:L1086
        put(m, "SM-W9026", "三星 W26", "三星 W26", "Samsung", "device_list_full_import"); // Device_List:L1087
        put(m, "SM-G1600", "Galaxy Folder", "Galaxy Folder", "Samsung", "device_list_full_import"); // Device_List:L1088
        put(m, "SM-G1650", "Galaxy Folder 2", "Galaxy Folder 2", "Samsung", "device_list_full_import"); // Device_List:L1089
        put(m, "SM-G8508S", "Galaxy Alpha", "Galaxy Alpha", "Samsung", "device_list_full_import"); // Device_List:L1090
        put(m, "SM-E7000", "Galaxy E7 公開版", "Galaxy E7 公開版", "Samsung", "device_list_full_import"); // Device_List:L1091
        put(m, "SM-E7009", "Galaxy E7 電信定制版", "Galaxy E7 電信定制版", "Samsung", "device_list_full_import"); // Device_List:L1092
        put(m, "SM-T700", "Galaxy Tab S 8.4 WLAN", "Galaxy Tab S 8.4 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1093
        put(m, "SM-T705C", "Galaxy Tab S 8.4 LTE", "Galaxy Tab S 8.4 LTE", "Samsung", "device_list_full_import"); // Device_List:L1094
        put(m, "SM-T800", "Galaxy Tab S 10.5 WLAN", "Galaxy Tab S 10.5 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1095
        put(m, "SM-T805C", "Galaxy Tab S 10.5 LTE", "Galaxy Tab S 10.5 LTE", "Samsung", "device_list_full_import"); // Device_List:L1096
        put(m, "SM-T710", "Galaxy Tab S2 8.0 WLAN (Exynos)", "Galaxy Tab S2 8.0 WLAN (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1097
        put(m, "SM-T715C", "Galaxy Tab S2 8.0 LTE (Exynos)", "Galaxy Tab S2 8.0 LTE (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1098
        put(m, "SM-T713", "Galaxy Tab S2 8.0 WLAN (高通)", "Galaxy Tab S2 8.0 WLAN (高通)", "Samsung", "device_list_full_import"); // Device_List:L1099
        put(m, "SM-T719C", "Galaxy Tab S2 8.0 LTE (高通)", "Galaxy Tab S2 8.0 LTE (高通)", "Samsung", "device_list_full_import"); // Device_List:L1100
        put(m, "SM-T810", "Galaxy Tab S2 9.7 WLAN (Exynos)", "Galaxy Tab S2 9.7 WLAN (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1101
        put(m, "SM-T815C", "Galaxy Tab S2 9.7 LTE (Exynos)", "Galaxy Tab S2 9.7 LTE (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1102
        put(m, "SM-T813", "Galaxy Tab S2 9.7 WLAN (高通)", "Galaxy Tab S2 9.7 WLAN (高通)", "Samsung", "device_list_full_import"); // Device_List:L1103
        put(m, "SM-T819C", "Galaxy Tab S2 9.7 LTE (高通)", "Galaxy Tab S2 9.7 LTE (高通)", "Samsung", "device_list_full_import"); // Device_List:L1104
        put(m, "SM-T820", "Galaxy Tab S3 WLAN", "Galaxy Tab S3 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1105
        put(m, "SM-T825C", "Galaxy Tab S3 LTE", "Galaxy Tab S3 LTE", "Samsung", "device_list_full_import"); // Device_List:L1106
        put(m, "SM-T830", "Galaxy Tab S4 WLAN", "Galaxy Tab S4 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1107
        put(m, "SM-T835C", "Galaxy Tab S4 LTE", "Galaxy Tab S4 LTE", "Samsung", "device_list_full_import"); // Device_List:L1108
        put(m, "SM-T720", "Galaxy Tab S5e WLAN", "Galaxy Tab S5e WLAN", "Samsung", "device_list_full_import"); // Device_List:L1109
        put(m, "SM-T725C", "Galaxy Tab S5e LTE", "Galaxy Tab S5e LTE", "Samsung", "device_list_full_import"); // Device_List:L1110
        put(m, "SM-T860", "Galaxy Tab S6 WLAN", "Galaxy Tab S6 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1111
        put(m, "SM-P610", "Galaxy Tab S6 Lite WLAN", "Galaxy Tab S6 Lite WLAN", "Samsung", "device_list_full_import"); // Device_List:L1112
        put(m, "SM-P615C", "Galaxy Tab S6 Lite LTE", "Galaxy Tab S6 Lite LTE", "Samsung", "device_list_full_import"); // Device_List:L1113
        put(m, "SM-T870", "Galaxy Tab S7 WLAN", "Galaxy Tab S7 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1114
        put(m, "SM-T970", "Galaxy Tab S7+ WLAN", "Galaxy Tab S7+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1115
        put(m, "SM-T730", "Galaxy Tab S7 FE WLAN (驍龍 750G)", "Galaxy Tab S7 FE WLAN (驍龍 750G)", "Samsung", "device_list_full_import"); // Device_List:L1116
        put(m, "SM-T733", "Galaxy Tab S7 FE WLAN (驍龍 778G)", "Galaxy Tab S7 FE WLAN (驍龍 778G)", "Samsung", "device_list_full_import"); // Device_List:L1117
        put(m, "SM-T735C", "Galaxy Tab S7 FE LTE", "Galaxy Tab S7 FE LTE", "Samsung", "device_list_full_import"); // Device_List:L1118
        put(m, "SM-X700", "Galaxy Tab S8 WLAN", "Galaxy Tab S8 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1119
        put(m, "SM-X706C", "Galaxy Tab S8 5G", "Galaxy Tab S8 5G", "Samsung", "device_list_full_import"); // Device_List:L1120
        put(m, "SM-X800", "Galaxy Tab S8+ WLAN", "Galaxy Tab S8+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1121
        put(m, "SM-X806C", "Galaxy Tab S8+ 5G", "Galaxy Tab S8+ 5G", "Samsung", "device_list_full_import"); // Device_List:L1122
        put(m, "SM-X900", "Galaxy Tab S8 Ultra WLAN", "Galaxy Tab S8 Ultra WLAN", "Samsung", "device_list_full_import"); // Device_List:L1123
        put(m, "SM-X906C", "Galaxy Tab S8 Ultra 5G", "Galaxy Tab S8 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L1124
        put(m, "SM-X710", "Galaxy Tab S9 WLAN", "Galaxy Tab S9 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1125
        put(m, "SM-X810", "Galaxy Tab S9+ WLAN", "Galaxy Tab S9+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1126
        put(m, "SM-X910", "Galaxy Tab S9 Ultra WLAN", "Galaxy Tab S9 Ultra WLAN", "Samsung", "device_list_full_import"); // Device_List:L1127
        put(m, "SM-X916C", "Galaxy Tab S9 Ultra 5G", "Galaxy Tab S9 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L1128
        put(m, "SM-X510", "Galaxy Tab S9 FE WLAN", "Galaxy Tab S9 FE WLAN", "Samsung", "device_list_full_import"); // Device_List:L1129
        put(m, "SM-X516C", "Galaxy Tab S9 FE 5G", "Galaxy Tab S9 FE 5G", "Samsung", "device_list_full_import"); // Device_List:L1130
        put(m, "SM-X610", "Galaxy Tab S9 FE+ WLAN", "Galaxy Tab S9 FE+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1131
        put(m, "SM-X616C", "Galaxy Tab S9 FE+ 5G", "Galaxy Tab S9 FE+ 5G", "Samsung", "device_list_full_import"); // Device_List:L1132
        put(m, "SM-X820", "Galaxy Tab S10+ WLAN", "Galaxy Tab S10+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1133
        put(m, "SM-X920", "Galaxy Tab S10 Ultra WLAN", "Galaxy Tab S10 Ultra WLAN", "Samsung", "device_list_full_import"); // Device_List:L1134
        put(m, "SM-X926C", "Galaxy Tab S10 Ultra 5G", "Galaxy Tab S10 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L1135
        put(m, "SM-X520", "Galaxy Tab S10 FE WLAN", "Galaxy Tab S10 FE WLAN", "Samsung", "device_list_full_import"); // Device_List:L1136
        put(m, "SM-X526C", "Galaxy Tab S10 FE 5G", "Galaxy Tab S10 FE 5G", "Samsung", "device_list_full_import"); // Device_List:L1137
        put(m, "SM-X620", "Galaxy Tab S10 FE+ WLAN", "Galaxy Tab S10 FE+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1138
        put(m, "SM-X626C", "Galaxy Tab S10 FE+ 5G", "Galaxy Tab S10 FE+ 5G", "Samsung", "device_list_full_import"); // Device_List:L1139
        put(m, "SM-X400", "Galaxy Tab S10 Lite WLAN", "Galaxy Tab S10 Lite WLAN", "Samsung", "device_list_full_import"); // Device_List:L1140
        put(m, "SM-X730", "Galaxy Tab S11 WLAN", "Galaxy Tab S11 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1141
        put(m, "SM-X736C", "Galaxy Tab S11 5G", "Galaxy Tab S11 5G", "Samsung", "device_list_full_import"); // Device_List:L1142
        put(m, "SM-X930", "Galaxy Tab S11 Ultra WLAN", "Galaxy Tab S11 Ultra WLAN", "Samsung", "device_list_full_import"); // Device_List:L1143
        put(m, "SM-X936C", "Galaxy Tab S11 Ultra 5G", "Galaxy Tab S11 Ultra 5G", "Samsung", "device_list_full_import"); // Device_List:L1144
        put(m, "SM-T350", "Galaxy Tab A 8.0 WLAN", "Galaxy Tab A 8.0 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1145
        put(m, "SM-T355C", "Galaxy Tab A 8.0 LTE", "Galaxy Tab A 8.0 LTE", "Samsung", "device_list_full_import"); // Device_List:L1146
        put(m, "SM-T550", "Galaxy Tab A 9.7 WLAN", "Galaxy Tab A 9.7 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1147
        put(m, "SM-T555C", "Galaxy Tab A 9.7 LTE", "Galaxy Tab A 9.7 LTE", "Samsung", "device_list_full_import"); // Device_List:L1148
        put(m, "SM-T580", "Galaxy Tab A (2016) 10.1 WLAN", "Galaxy Tab A (2016) 10.1 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1149
        put(m, "SM-T585C", "Galaxy Tab A (2016) 10.1 LTE", "Galaxy Tab A (2016) 10.1 LTE", "Samsung", "device_list_full_import"); // Device_List:L1150
        put(m, "SM-P583", "Galaxy Tab A (2016) with S Pen 10.1 WLAN", "Galaxy Tab A (2016) with S Pen 10.1 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1151
        put(m, "SM-P588C", "Galaxy Tab A (2016) with S Pen 10.1 LTE", "Galaxy Tab A (2016) with S Pen 10.1 LTE", "Samsung", "device_list_full_import"); // Device_List:L1152
        put(m, "SM-T380", "Galaxy Tab A (2017) 8.0 WLAN", "Galaxy Tab A (2017) 8.0 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1153
        put(m, "SM-T385C", "Galaxy Tab A (2017) 8.0 LTE", "Galaxy Tab A (2017) 8.0 LTE", "Samsung", "device_list_full_import"); // Device_List:L1154
        put(m, "SM-T590", "Galaxy Tab A (2018) 10.5 WLAN", "Galaxy Tab A (2018) 10.5 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1155
        put(m, "SM-T595C", "Galaxy Tab A (2018) 10.5 LTE", "Galaxy Tab A (2018) 10.5 LTE", "Samsung", "device_list_full_import"); // Device_List:L1156
        put(m, "SM-T290", "Galaxy Tab A (2019) 8.0 WLAN", "Galaxy Tab A (2019) 8.0 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1157
        put(m, "SM-T295C", "Galaxy Tab A (2019) 8.0 LTE", "Galaxy Tab A (2019) 8.0 LTE", "Samsung", "device_list_full_import"); // Device_List:L1158
        put(m, "SM-T510", "Galaxy Tab A (2019) 10.1 WLAN", "Galaxy Tab A (2019) 10.1 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1159
        put(m, "SM-T500", "Galaxy Tab A7 10.4 WLAN", "Galaxy Tab A7 10.4 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1160
        put(m, "SM-T505C", "Galaxy Tab A7 10.4 LTE", "Galaxy Tab A7 10.4 LTE", "Samsung", "device_list_full_import"); // Device_List:L1161
        put(m, "SM-T220", "Galaxy Tab A7 Lite 8.7 WLAN", "Galaxy Tab A7 Lite 8.7 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1162
        put(m, "SM-T225C", "Galaxy Tab A7 Lite 8.7 LTE", "Galaxy Tab A7 Lite 8.7 LTE", "Samsung", "device_list_full_import"); // Device_List:L1163
        put(m, "SM-X200", "Galaxy Tab A8 WLAN", "Galaxy Tab A8 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1164
        put(m, "SM-X205C", "Galaxy Tab A8 LTE", "Galaxy Tab A8 LTE", "Samsung", "device_list_full_import"); // Device_List:L1165
        put(m, "SM-X210", "Galaxy Tab A9+ WLAN", "Galaxy Tab A9+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1166
        put(m, "SM-X216C", "Galaxy Tab A9+ 5G", "Galaxy Tab A9+ 5G", "Samsung", "device_list_full_import"); // Device_List:L1167
        put(m, "SM-X230", "Galaxy Tab A11+ WLAN", "Galaxy Tab A11+ WLAN", "Samsung", "device_list_full_import"); // Device_List:L1168
        put(m, "SM-X236C", "Galaxy Tab A11+ 5H", "Galaxy Tab A11+ 5H", "Samsung", "device_list_full_import"); // Device_List:L1169
        put(m, "SM-T230", "Galaxy Tab4 7.0 WLAN", "Galaxy Tab4 7.0 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1170
        put(m, "SM-T231", "Galaxy Tab4 7.0 3G", "Galaxy Tab4 7.0 3G", "Samsung", "device_list_full_import"); // Device_List:L1171
        put(m, "SM-T239C", "Galaxy Tab4 7.0 VE LTE", "Galaxy Tab4 7.0 VE LTE", "Samsung", "device_list_full_import"); // Device_List:L1172
        put(m, "SM-T330", "Galaxy Tab4 8.0 WLAN", "Galaxy Tab4 8.0 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1173
        put(m, "SM-T331", "Galaxy Tab4 8.0 3G", "Galaxy Tab4 8.0 3G", "Samsung", "device_list_full_import"); // Device_List:L1174
        put(m, "SM-T530", "Galaxy Tab4 10.1 WLAN", "Galaxy Tab4 10.1 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1175
        put(m, "SM-T531", "Galaxy Tab4 10.1 3G", "Galaxy Tab4 10.1 3G", "Samsung", "device_list_full_import"); // Device_List:L1176
        put(m, "SM-T320", "Galaxy Tab PRO 8.4 WLAN", "Galaxy Tab PRO 8.4 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1177
        put(m, "SM-T321", "Galaxy Tab PRO 8.4 3G", "Galaxy Tab PRO 8.4 3G", "Samsung", "device_list_full_import"); // Device_List:L1178
        put(m, "SM-T520", "Galaxy Tab PRO 10.1 WLAN", "Galaxy Tab PRO 10.1 WLAN", "Samsung", "device_list_full_import"); // Device_List:L1179
        put(m, "SM-W700", "Galaxy TabPro S WLAN", "Galaxy TabPro S WLAN", "Samsung", "device_list_full_import"); // Device_List:L1180
        put(m, "SM-R860", "Galaxy Watch4 藍牙版 40mm", "Galaxy Watch4 藍牙版 40mm", "Samsung", "device_list_full_import"); // Device_List:L1181
        put(m, "SM-R870", "Galaxy Watch4 藍牙版 44mm", "Galaxy Watch4 藍牙版 44mm", "Samsung", "device_list_full_import"); // Device_List:L1182
        put(m, "SM-R880", "Galaxy Watch4 Classic 藍牙版 42mm", "Galaxy Watch4 Classic 藍牙版 42mm", "Samsung", "device_list_full_import"); // Device_List:L1183
        put(m, "SM-R890", "Galaxy Watch4 Classic 藍牙版 46mm", "Galaxy Watch4 Classic 藍牙版 46mm", "Samsung", "device_list_full_import"); // Device_List:L1184
        put(m, "SM-R8950", "Galaxy Watch4 Classic LTE 46mm", "Galaxy Watch4 Classic LTE 46mm", "Samsung", "device_list_full_import"); // Device_List:L1185
        put(m, "SM-R900", "Galaxy Watch5 藍牙版 40mm", "Galaxy Watch5 藍牙版 40mm", "Samsung", "device_list_full_import"); // Device_List:L1186
        put(m, "SM-R910", "Galaxy Watch5 藍牙版 44mm", "Galaxy Watch5 藍牙版 44mm", "Samsung", "device_list_full_import"); // Device_List:L1187
        put(m, "SM-R9150", "Galaxy Watch5 LTE 44mm", "Galaxy Watch5 LTE 44mm", "Samsung", "device_list_full_import"); // Device_List:L1188
        put(m, "SM-R920", "Galaxy Watch5 Pro 藍牙版 45mm", "Galaxy Watch5 Pro 藍牙版 45mm", "Samsung", "device_list_full_import"); // Device_List:L1189
        put(m, "SM-R930", "Galaxy Watch6 藍牙版 40mm", "Galaxy Watch6 藍牙版 40mm", "Samsung", "device_list_full_import"); // Device_List:L1190
        put(m, "SM-R940", "Galaxy Watch6 藍牙版 44mm", "Galaxy Watch6 藍牙版 44mm", "Samsung", "device_list_full_import"); // Device_List:L1191
        put(m, "SM-R9450", "Galaxy Watch6 LTE 44mm", "Galaxy Watch6 LTE 44mm", "Samsung", "device_list_full_import"); // Device_List:L1192
        put(m, "SM-R950", "Galaxy Watch6 Classic 藍牙版 43mm", "Galaxy Watch6 Classic 藍牙版 43mm", "Samsung", "device_list_full_import"); // Device_List:L1193
        put(m, "SM-R960", "Galaxy Watch6 Classic 藍牙版 47mm", "Galaxy Watch6 Classic 藍牙版 47mm", "Samsung", "device_list_full_import"); // Device_List:L1194
        put(m, "SM-R9650", "Galaxy Watch6 Classic LTE 47mm", "Galaxy Watch6 Classic LTE 47mm", "Samsung", "device_list_full_import"); // Device_List:L1195
        put(m, "SM-L300", "Galaxy Watch7 藍牙版 40mm", "Galaxy Watch7 藍牙版 40mm", "Samsung", "device_list_full_import"); // Device_List:L1196
        put(m, "SM-L310", "Galaxy Watch7 藍牙版 44mm", "Galaxy Watch7 藍牙版 44mm", "Samsung", "device_list_full_import"); // Device_List:L1197
        put(m, "SM-L3150", "Galaxy Watch7 LTE 44mm", "Galaxy Watch7 LTE 44mm", "Samsung", "device_list_full_import"); // Device_List:L1198
        put(m, "SM-L7050", "Galaxy Watch Ultra LTE 47mm", "Galaxy Watch Ultra LTE 47mm", "Samsung", "device_list_full_import"); // Device_List:L1199
        put(m, "SM-L320", "Galaxy Watch8 藍牙版 40mm", "Galaxy Watch8 藍牙版 40mm", "Samsung", "device_list_full_import"); // Device_List:L1200
        put(m, "SM-L330", "Galaxy Watch8 藍牙版 44mm", "Galaxy Watch8 藍牙版 44mm", "Samsung", "device_list_full_import"); // Device_List:L1201
        put(m, "SM-L3350", "Galaxy Watch8 LTE 44mm", "Galaxy Watch8 LTE 44mm", "Samsung", "device_list_full_import"); // Device_List:L1202
        put(m, "SM-L500", "Galaxy Watch8 Classic 藍牙版 46mm", "Galaxy Watch8 Classic 藍牙版 46mm", "Samsung", "device_list_full_import"); // Device_List:L1203
        put(m, "SM-L5050", "Galaxy Watch8 Classic LTE 46mm", "Galaxy Watch8 Classic LTE 46mm", "Samsung", "device_list_full_import"); // Device_List:L1204
        put(m, "SM-G970F", "Galaxy S10e Global", "Galaxy S10e Global", "Samsung", "device_list_full_import"); // Device_List:L1205
        put(m, "SM-G970N", "Galaxy S10e South Korea", "Galaxy S10e South Korea", "Samsung", "device_list_full_import"); // Device_List:L1206
        put(m, "SM-G970U", "Galaxy S10e US Carrier", "Galaxy S10e US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1207
        put(m, "SM-G970U1", "Galaxy S10e US Unlocked", "Galaxy S10e US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1208
        put(m, "SM-G970W", "Galaxy S10e Canada", "Galaxy S10e Canada", "Samsung", "device_list_full_import"); // Device_List:L1209
        put(m, "SM-G973F", "Galaxy S10 Global", "Galaxy S10 Global", "Samsung", "device_list_full_import"); // Device_List:L1210
        put(m, "SM-G973N", "Galaxy S10 South Korea", "Galaxy S10 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1211
        put(m, "SM-G973U", "Galaxy S10 US Carrier", "Galaxy S10 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1212
        put(m, "SM-G973U1", "Galaxy S10 US Unlocked", "Galaxy S10 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1213
        put(m, "SM-G973W", "Galaxy S10 Canada", "Galaxy S10 Canada", "Samsung", "device_list_full_import"); // Device_List:L1214
        put(m, "SM-G973C", "Galaxy S10 Japan (Rakuten Mobile)", "Galaxy S10 Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1215
        put(m, "SCV41", "Galaxy S10 Japan (au)", "Galaxy S10 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1216
        put(m, "SC-03L", "Galaxy S10 Japan (NTT Docomo)", "Galaxy S10 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1217
        put(m, "SM-G975F", "Galaxy S10+ Global", "Galaxy S10+ Global", "Samsung", "device_list_full_import"); // Device_List:L1218
        put(m, "SM-G975N", "Galaxy S10+ South Korea", "Galaxy S10+ South Korea", "Samsung", "device_list_full_import"); // Device_List:L1219
        put(m, "SM-G975U", "Galaxy S10+ US Carrier", "Galaxy S10+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1220
        put(m, "SM-G975U1", "Galaxy S10+ US Unlocked", "Galaxy S10+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1221
        put(m, "SM-G975W", "Galaxy S10+ Canada", "Galaxy S10+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1222
        put(m, "SCV42", "Galaxy S10+ Japan (au)", "Galaxy S10+ Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1223
        put(m, "SC-04L", "Galaxy S10+ Japan (NTT Docomo)", "Galaxy S10+ Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1224
        put(m, "SC-05L", "Galaxy S10+ Olympic Games Edition Japan (NTT Docomo)", "Galaxy S10+ Olympic Games Edition Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1225
        put(m, "SM-G977B", "Galaxy S10 5G Global", "Galaxy S10 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1226
        put(m, "SM-G977N", "Galaxy S10 5G South Korea", "Galaxy S10 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1227
        put(m, "SM-G977U", "Galaxy S10 5G US Carrier", "Galaxy S10 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1228
        put(m, "SM-G977T", "Galaxy S10 5G T-Mobile", "Galaxy S10 5G T-Mobile", "Samsung", "device_list_full_import"); // Device_List:L1229
        put(m, "SM-G977P", "Galaxy S10 5G Sprint", "Galaxy S10 5G Sprint", "Samsung", "device_list_full_import"); // Device_List:L1230
        put(m, "SM-G770F", "Galaxy S10 Lite Global", "Galaxy S10 Lite Global", "Samsung", "device_list_full_import"); // Device_List:L1231
        put(m, "SM-G770U1", "Galaxy S10 Lite US Unlocked", "Galaxy S10 Lite US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1232
        put(m, "SM-G980F", "Galaxy S20 Global", "Galaxy S20 Global", "Samsung", "device_list_full_import"); // Device_List:L1233
        put(m, "SM-G981B", "Galaxy S20 5G Global", "Galaxy S20 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1234
        put(m, "SM-G981U", "Galaxy S20 5G US Carrier", "Galaxy S20 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1235
        put(m, "SM-G981U1", "Galaxy S20 5G US Unlocked", "Galaxy S20 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1236
        put(m, "SM-G981V", "Galaxy S20 5G UW Verizon", "Galaxy S20 5G UW Verizon", "Samsung", "device_list_full_import"); // Device_List:L1237
        put(m, "SM-G981W", "Galaxy S20 5G Canada", "Galaxy S20 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1238
        put(m, "SM-G981N", "Galaxy S20 5G South Korea", "Galaxy S20 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1239
        put(m, "SCG01", "Galaxy S20 5G Japan (au)", "Galaxy S20 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1240
        put(m, "SC51Aa", "Galaxy S20 5G Japan (NTT Docomo)", "Galaxy S20 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1241
        put(m, "SM-G985F", "Galaxy S20+ Global", "Galaxy S20+ Global", "Samsung", "device_list_full_import"); // Device_List:L1242
        put(m, "SM-G986B", "Galaxy S20+ 5G Global", "Galaxy S20+ 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1243
        put(m, "SM-G986U", "Galaxy S20+ 5G US Carrier", "Galaxy S20+ 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1244
        put(m, "SM-G986U1", "Galaxy S20+ 5G US Unlocked", "Galaxy S20+ 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1245
        put(m, "SM-G986W", "Galaxy S20+ 5G Canada", "Galaxy S20+ 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1246
        put(m, "SM-G986N", "Galaxy S20+ 5G South Korea", "Galaxy S20+ 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1247
        put(m, "SCG02", "Galaxy S20+ 5G Japan (au)", "Galaxy S20+ 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1248
        put(m, "SC-52A", "Galaxy S20+ 5G Japan (NTT Docomo)", "Galaxy S20+ 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1249
        put(m, "SM-G988B", "Galaxy S20 Ultra 5G Global", "Galaxy S20 Ultra 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1250
        put(m, "SM-G988U", "Galaxy S20 Ultra 5G US Carrier", "Galaxy S20 Ultra 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1251
        put(m, "SM-G988U1", "Galaxy S20 Ultra 5G US Unlocked", "Galaxy S20 Ultra 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1252
        put(m, "SM-G988W", "Galaxy S20 Ultra 5G Canada", "Galaxy S20 Ultra 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1253
        put(m, "SM-G988N", "Galaxy S20 Ultra 5G South Korea", "Galaxy S20 Ultra 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1254
        put(m, "SM-G988Q", "Galaxy S20 Ultra 5G Japan (SIM Free)", "Galaxy S20 Ultra 5G Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1255
        put(m, "SCG03", "Galaxy S20 Ultra 5G Japan (au)", "Galaxy S20 Ultra 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1256
        put(m, "SM-G780F", "Galaxy S20 FE Global (Exynos)", "Galaxy S20 FE Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1257
        put(m, "SM-G780G", "Galaxy S20 FE Global (Snapdragon)", "Galaxy S20 FE Global (Snapdragon)", "Samsung", "device_list_full_import"); // Device_List:L1258
        put(m, "SM-G781B", "Galaxy S20 FE 5G Global", "Galaxy S20 FE 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1259
        put(m, "SM-G781U", "Galaxy S20 FE 5G US Carrier", "Galaxy S20 FE 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1260
        put(m, "SM-G781U1", "Galaxy S20 FE 5G US Unlocked", "Galaxy S20 FE 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1261
    }

    private static void fill7(Map<String, Entry> m) {
        put(m, "SM-G781V", "Galaxy S20 FE 5G UW Verizon", "Galaxy S20 FE 5G UW Verizon", "Samsung", "device_list_full_import"); // Device_List:L1262
        put(m, "SM-G781W", "Galaxy S20 FE 5G Canada", "Galaxy S20 FE 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1263
        put(m, "SM-G781N", "Galaxy S20 FE 5G South Korea", "Galaxy S20 FE 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1264
        put(m, "SM-G991B", "Galaxy S21 5G Global", "Galaxy S21 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1265
        put(m, "SM-G991N", "Galaxy S21 5G South Korea", "Galaxy S21 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1266
        put(m, "SM-G991U", "Galaxy S21 5G US Carrier", "Galaxy S21 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1267
        put(m, "SM-G991U1", "Galaxy S21 5G US Unlocked", "Galaxy S21 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1268
        put(m, "SM-G991W", "Galaxy S21 5G Canada", "Galaxy S21 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1269
        put(m, "SCG09", "Galaxy S21 5G Japan (au)", "Galaxy S21 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1270
        put(m, "SC-51B", "Galaxy S21 5G Japan (NTT Docomo)", "Galaxy S21 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1271
        put(m, "SM-G996B", "Galaxy S21+ 5G Global", "Galaxy S21+ 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1272
        put(m, "SM-G996N", "Galaxy S21+ 5G South Korea", "Galaxy S21+ 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1273
        put(m, "SM-G996U", "Galaxy S21+ 5G US Carrier", "Galaxy S21+ 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1274
        put(m, "SM-G996U1", "Galaxy S21+ 5G US Unlocked", "Galaxy S21+ 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1275
        put(m, "SM-G996W", "Galaxy S21+ 5G Canada", "Galaxy S21+ 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1276
        put(m, "SCG10", "Galaxy S21+ 5G Japan (au)", "Galaxy S21+ 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1277
        put(m, "SM-G998B", "Galaxy S21 Ultra 5G Global", "Galaxy S21 Ultra 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1278
        put(m, "SM-G998N", "Galaxy S21 Ultra 5G South Korea", "Galaxy S21 Ultra 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1279
        put(m, "SM-G998U", "Galaxy S21 Ultra 5G US Carrier", "Galaxy S21 Ultra 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1280
        put(m, "SM-G998U1", "Galaxy S21 Ultra 5G US Unlocked", "Galaxy S21 Ultra 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1281
        put(m, "SM-G998W", "Galaxy S21 Ultra 5G Canada", "Galaxy S21 Ultra 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1282
        put(m, "SC-52B", "Galaxy S21 Ultra 5G Japan (NTT Docomo)", "Galaxy S21 Ultra 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1283
        put(m, "SM-G990B", "Galaxy S21 FE 5G Global", "Galaxy S21 FE 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1284
        put(m, "SM-G990B2", "Galaxy S21 FE 5G EU", "Galaxy S21 FE 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1285
        put(m, "SM-G990U2", "Galaxy S21 FE 5G US Carrier", "Galaxy S21 FE 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1286
        put(m, "SM-G990U3", "Galaxy S21 FE 5G US Unlocked", "Galaxy S21 FE 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1287
        put(m, "SM-G990W2", "Galaxy S21 FE 5G Canada", "Galaxy S21 FE 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1288
        put(m, "SM-G990E", "Galaxy S21 FE 5G (Exynos)", "Galaxy S21 FE 5G (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1289
        put(m, "SM-S901E", "Galaxy S22 Global (Snapdragon)", "Galaxy S22 Global (Snapdragon)", "Samsung", "device_list_full_import"); // Device_List:L1290
        put(m, "SM-S901U", "Galaxy S22 US Carrier", "Galaxy S22 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1291
        put(m, "SM-S901U1", "Galaxy S22 US Unlocked", "Galaxy S22 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1292
        put(m, "SM-S901W", "Galaxy S22 Canada", "Galaxy S22 Canada", "Samsung", "device_list_full_import"); // Device_List:L1293
        put(m, "SM-S901N", "Galaxy S22 South Korea", "Galaxy S22 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1294
        put(m, "SCG13", "Galaxy S22 Japan (au)", "Galaxy S22 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1295
        put(m, "SC-51C", "Galaxy S22 Japan (NTT Docomo)", "Galaxy S22 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1296
        put(m, "SM-S901B", "Galaxy S22 Global (Exynos)", "Galaxy S22 Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1297
        put(m, "SM-S906E", "Galaxy S22+ Global (Snapdragon)", "Galaxy S22+ Global (Snapdragon)", "Samsung", "device_list_full_import"); // Device_List:L1298
        put(m, "SM-S906U", "Galaxy S22+ US Carrier", "Galaxy S22+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1299
        put(m, "SM-S906U1", "Galaxy S22+ US Unlocked", "Galaxy S22+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1300
        put(m, "SM-S906W", "Galaxy S22+ Canada", "Galaxy S22+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1301
        put(m, "SM-S906N", "Galaxy S22+ South Korea", "Galaxy S22+ South Korea", "Samsung", "device_list_full_import"); // Device_List:L1302
        put(m, "SM-S906B", "Galaxy S22+ Global (Exynos)", "Galaxy S22+ Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1303
        put(m, "SM-S908E", "Galaxy S22 Ultra Global (Snapdragon)", "Galaxy S22 Ultra Global (Snapdragon)", "Samsung", "device_list_full_import"); // Device_List:L1304
        put(m, "SM-S908U", "Galaxy S22 Ultra US Carrier", "Galaxy S22 Ultra US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1305
        put(m, "SM-S908U1", "Galaxy S22 Ultra US Unlocked", "Galaxy S22 Ultra US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1306
        put(m, "SM-S908W", "Galaxy S22 Ultra Canada", "Galaxy S22 Ultra Canada", "Samsung", "device_list_full_import"); // Device_List:L1307
        put(m, "SM-S908N", "Galaxy S22 Ultra South Korea", "Galaxy S22 Ultra South Korea", "Samsung", "device_list_full_import"); // Device_List:L1308
        put(m, "SCG14", "Galaxy S22 Ultra Japan (au)", "Galaxy S22 Ultra Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1309
        put(m, "SC-52C", "Galaxy S22 Ultra Japan (NTT Docomo)", "Galaxy S22 Ultra Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1310
        put(m, "SM-S908B", "Galaxy S22 Ultra Global (Exynos)", "Galaxy S22 Ultra Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1311
        put(m, "SM-S911B", "Galaxy S23 Global", "Galaxy S23 Global", "Samsung", "device_list_full_import"); // Device_List:L1312
        put(m, "SM-S911U", "Galaxy S23 US Carrier", "Galaxy S23 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1313
        put(m, "SM-S911U1", "Galaxy S23 US Unlocked", "Galaxy S23 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1314
        put(m, "SM-S911W", "Galaxy S23 Canada", "Galaxy S23 Canada", "Samsung", "device_list_full_import"); // Device_List:L1315
        put(m, "SM-S911N", "Galaxy S23 South Korea", "Galaxy S23 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1316
        put(m, "SM-S911C", "Galaxy S23 Japan (Rakuten Mobile)", "Galaxy S23 Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1317
        put(m, "SCG19", "Galaxy S23 Japan (au)", "Galaxy S23 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1318
        put(m, "SC-51D", "Galaxy S23 Japan (NTT Docomo)", "Galaxy S23 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1319
        put(m, "SM-S916B", "Galaxy S23+ Global", "Galaxy S23+ Global", "Samsung", "device_list_full_import"); // Device_List:L1320
        put(m, "SM-S916U", "Galaxy S23+ US Carrier", "Galaxy S23+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1321
        put(m, "SM-S916U1", "Galaxy S23+ US Unlocked", "Galaxy S23+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1322
        put(m, "SM-S916W", "Galaxy S23+ Canada", "Galaxy S23+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1323
        put(m, "SM-S916N", "Galaxy S23+ South Korea", "Galaxy S23+ South Korea", "Samsung", "device_list_full_import"); // Device_List:L1324
        put(m, "SM-S918B", "Galaxy S23 Ultra Global", "Galaxy S23 Ultra Global", "Samsung", "device_list_full_import"); // Device_List:L1325
        put(m, "SM-S918U", "Galaxy S23 Ultra US Carrier", "Galaxy S23 Ultra US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1326
        put(m, "SM-S918U1", "Galaxy S23 Ultra US Unlocked", "Galaxy S23 Ultra US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1327
        put(m, "SM-S918W", "Galaxy S23 Ultra Canada", "Galaxy S23 Ultra Canada", "Samsung", "device_list_full_import"); // Device_List:L1328
        put(m, "SM-S918N", "Galaxy S23 Ultra South Korea", "Galaxy S23 Ultra South Korea", "Samsung", "device_list_full_import"); // Device_List:L1329
        put(m, "SM-S918Q", "Galaxy S23 Ultra Japan (SIM Free)", "Galaxy S23 Ultra Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1330
        put(m, "SCG20", "Galaxy S23 Ultra Japan (au)", "Galaxy S23 Ultra Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1331
        put(m, "SC-52D", "Galaxy S23 Ultra Japan (NTT Docomo)", "Galaxy S23 Ultra Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1332
        put(m, "SM-S711U", "Galaxy S23 FE US Carrier", "Galaxy S23 FE US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1333
        put(m, "SM-S711U1", "Galaxy S23 FE US Unlocked", "Galaxy S23 FE US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1334
        put(m, "SM-S711W", "Galaxy S23 FE Canada", "Galaxy S23 FE Canada", "Samsung", "device_list_full_import"); // Device_List:L1335
        put(m, "SCG24", "Galaxy S23 FE Japan (au)", "Galaxy S23 FE Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1336
        put(m, "SM-S711B", "Galaxy S23 FE Global", "Galaxy S23 FE Global", "Samsung", "device_list_full_import"); // Device_List:L1337
        put(m, "SM-S711N", "Galaxy S23 FE South Korea", "Galaxy S23 FE South Korea", "Samsung", "device_list_full_import"); // Device_List:L1338
        put(m, "SM-S921B", "Galaxy S24 Global", "Galaxy S24 Global", "Samsung", "device_list_full_import"); // Device_List:L1339
        put(m, "SM-S921N", "Galaxy S24 South Korea", "Galaxy S24 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1340
        put(m, "SM-S921U", "Galaxy S24 US Carrier", "Galaxy S24 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1341
        put(m, "SM-S921U1", "Galaxy S24 US Unlocked", "Galaxy S24 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1342
        put(m, "SM-S921W", "Galaxy S24 Canada", "Galaxy S24 Canada", "Samsung", "device_list_full_import"); // Device_List:L1343
        put(m, "SM-S921Q", "Galaxy S24 Japan (SIM Free)", "Galaxy S24 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1344
        put(m, "SCG25", "Galaxy S24 Japan (au)", "Galaxy S24 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1345
        put(m, "SC-51E", "Galaxy S24 Japan (NTT Docomo)", "Galaxy S24 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1346
        put(m, "SM-S926B", "Galaxy S24+ Global", "Galaxy S24+ Global", "Samsung", "device_list_full_import"); // Device_List:L1347
        put(m, "SM-S926N", "Galaxy S24+ South Korea", "Galaxy S24+ South Korea", "Samsung", "device_list_full_import"); // Device_List:L1348
        put(m, "SM-S926U", "Galaxy S24+ US Carrier", "Galaxy S24+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1349
        put(m, "SM-S926U1", "Galaxy S24+ US Unlocked", "Galaxy S24+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1350
        put(m, "SM-S926W", "Galaxy S24+ Canada", "Galaxy S24+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1351
        put(m, "SM-S928B", "Galaxy S24 Ultra Global", "Galaxy S24 Ultra Global", "Samsung", "device_list_full_import"); // Device_List:L1352
        put(m, "SM-S928U", "Galaxy S24 Ultra US Carrier", "Galaxy S24 Ultra US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1353
        put(m, "SM-S928U1", "Galaxy S24 Ultra US Unlocked", "Galaxy S24 Ultra US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1354
        put(m, "SM-S928W", "Galaxy S24 Ultra Canada", "Galaxy S24 Ultra Canada", "Samsung", "device_list_full_import"); // Device_List:L1355
        put(m, "SM-S928N", "Galaxy S24 Ultra South Korea", "Galaxy S24 Ultra South Korea", "Samsung", "device_list_full_import"); // Device_List:L1356
        put(m, "SM-S928Q", "Galaxy S24 Ultra Japan (SIM Free)", "Galaxy S24 Ultra Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1357
        put(m, "SCG26", "Galaxy S24 Ultra Japan (au)", "Galaxy S24 Ultra Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1358
        put(m, "SC-52E", "Galaxy S24 Ultra Japan (NTT Docomo)", "Galaxy S24 Ultra Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1359
        put(m, "SM-S721B", "Galaxy S24 FE Global", "Galaxy S24 FE Global", "Samsung", "device_list_full_import"); // Device_List:L1360
        put(m, "SM-S721U", "Galaxy S24 FE US Carrier", "Galaxy S24 FE US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1361
        put(m, "SM-S721U1", "Galaxy S24 FE US Unlocked", "Galaxy S24 FE US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1362
        put(m, "SM-S721W", "Galaxy S24 FE Canada", "Galaxy S24 FE Canada", "Samsung", "device_list_full_import"); // Device_List:L1363
        put(m, "SM-S7210", "Galaxy S24 FE HK & TW", "Galaxy S24 FE HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1364
        put(m, "SM-S721Q", "Galaxy S24 FE Japan (SIM Free)", "Galaxy S24 FE Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1365
        put(m, "SCG30", "Galaxy S24 FE Japan (au)", "Galaxy S24 FE Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1366
        put(m, "SM-S721N", "Galaxy S24 FE South Korea", "Galaxy S24 FE South Korea", "Samsung", "device_list_full_import"); // Device_List:L1367
        put(m, "SM-S931B", "Galaxy S25 Global", "Galaxy S25 Global", "Samsung", "device_list_full_import"); // Device_List:L1368
        put(m, "SM-S931U", "Galaxy S25 US Carrier", "Galaxy S25 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1369
        put(m, "SM-S931U1", "Galaxy S25 US Unlocked", "Galaxy S25 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1370
        put(m, "SM-S931W", "Galaxy S25 Canada", "Galaxy S25 Canada", "Samsung", "device_list_full_import"); // Device_List:L1371
        put(m, "SM-S931N", "Galaxy S25 South Korea", "Galaxy S25 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1372
        put(m, "SM-S931Q", "Galaxy S25 Japan (SIM Free)", "Galaxy S25 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1373
        put(m, "SM-S931Z", "Galaxy S25 Japan (SoftBank)", "Galaxy S25 Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1374
        put(m, "SCG31", "Galaxy S25 Japan (au)", "Galaxy S25 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1375
        put(m, "SC-51F", "Galaxy S25 Japan (NTT Docomo)", "Galaxy S25 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1376
        put(m, "SM-S936B", "Galaxy S25+ Global", "Galaxy S25+ Global", "Samsung", "device_list_full_import"); // Device_List:L1377
        put(m, "SM-S936U", "Galaxy S25+ US Carrier", "Galaxy S25+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1378
        put(m, "SM-S936U1", "Galaxy S25+ US Unlocked", "Galaxy S25+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1379
        put(m, "SM-S936W", "Galaxy S25+ Canada", "Galaxy S25+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1380
        put(m, "SM-S936N", "Galaxy S25+ South Korea", "Galaxy S25+ South Korea", "Samsung", "device_list_full_import"); // Device_List:L1381
        put(m, "SM-S938B", "Galaxy S25 Ultra Global", "Galaxy S25 Ultra Global", "Samsung", "device_list_full_import"); // Device_List:L1382
        put(m, "SM-S938U", "Galaxy S25 Ultra US Carrier", "Galaxy S25 Ultra US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1383
        put(m, "SM-S938U1", "Galaxy S25 Ultra US Unlocked", "Galaxy S25 Ultra US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1384
        put(m, "SM-S938W", "Galaxy S25 Ultra Canada", "Galaxy S25 Ultra Canada", "Samsung", "device_list_full_import"); // Device_List:L1385
        put(m, "SM-S938N", "Galaxy S25 Ultra South Korea", "Galaxy S25 Ultra South Korea", "Samsung", "device_list_full_import"); // Device_List:L1386
        put(m, "SM-S938Q", "Galaxy S25 Ultra Japan (SIM Free)", "Galaxy S25 Ultra Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1387
        put(m, "SM-S938Z", "Galaxy S25 Ultra Japan (SoftBank)", "Galaxy S25 Ultra Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1388
        put(m, "SCG32", "Galaxy S25 Ultra Japan (au)", "Galaxy S25 Ultra Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1389
        put(m, "SC-52F", "Galaxy S25 Ultra Japan (NTT Docomo)", "Galaxy S25 Ultra Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1390
        put(m, "SM-S937B", "Galaxy S25 Edge Global", "Galaxy S25 Edge Global", "Samsung", "device_list_full_import"); // Device_List:L1391
        put(m, "SM-S937U", "Galaxy S25 Edge US Carrier", "Galaxy S25 Edge US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1392
        put(m, "SM-S937U1", "Galaxy S25 Edge US Unlocked", "Galaxy S25 Edge US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1393
        put(m, "SM-S937W", "Galaxy S25 Edge Canada", "Galaxy S25 Edge Canada", "Samsung", "device_list_full_import"); // Device_List:L1394
        put(m, "SM-S937N", "Galaxy S25 Edge South Korea", "Galaxy S25 Edge South Korea", "Samsung", "device_list_full_import"); // Device_List:L1395
        put(m, "SM-S731B", "Galaxy S25 FE Global", "Galaxy S25 FE Global", "Samsung", "device_list_full_import"); // Device_List:L1396
        put(m, "SM-S731U", "Galaxy S25 FE US Carrier", "Galaxy S25 FE US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1397
        put(m, "SM-S731U1", "Galaxy S25 FE US Unlocked", "Galaxy S25 FE US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1398
        put(m, "SM-S731W", "Galaxy S25 FE Canada", "Galaxy S25 FE Canada", "Samsung", "device_list_full_import"); // Device_List:L1399
        put(m, "SM-S731N", "Galaxy S25 FE South Korea", "Galaxy S25 FE South Korea", "Samsung", "device_list_full_import"); // Device_List:L1400
        put(m, "SM-S942B", "Galaxy S26 Global", "Galaxy S26 Global", "Samsung", "device_list_full_import"); // Device_List:L1401
        put(m, "SM-S942N", "Galaxy S26 South Korea", "Galaxy S26 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1402
        put(m, "SM-S942U", "Galaxy S26 US Carrier", "Galaxy S26 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1403
        put(m, "SM-S942U1", "Galaxy S26 US Unlocked", "Galaxy S26 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1404
        put(m, "SM-S942W", "Galaxy S26 Canada", "Galaxy S26 Canada", "Samsung", "device_list_full_import"); // Device_List:L1405
        put(m, "SM-S942Q", "Galaxy S26 Japan (SIM Free)", "Galaxy S26 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1406
        put(m, "SM-S942Z", "Galaxy S26 Japan (SoftBank)", "Galaxy S26 Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1407
        put(m, "SM-S942C", "Galaxy S26 Japan (Rakuten Mobile)", "Galaxy S26 Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1408
        put(m, "SCG36", "Galaxy S26 Japan (au)", "Galaxy S26 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1409
        put(m, "SC-51G", "Galaxy S26 Japan (NTT Docomo)", "Galaxy S26 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1410
        put(m, "SM-S947B", "Galaxy S26+ Global", "Galaxy S26+ Global", "Samsung", "device_list_full_import"); // Device_List:L1411
        put(m, "SM-S947N", "Galaxy S26+ South Korea", "Galaxy S26+ South Korea", "Samsung", "device_list_full_import"); // Device_List:L1412
        put(m, "SM-S947U", "Galaxy S26+ US Carrier", "Galaxy S26+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1413
        put(m, "SM-S947U1", "Galaxy S26+ US Unlocked", "Galaxy S26+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1414
        put(m, "SM-S947W", "Galaxy S26+ Canada", "Galaxy S26+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1415
        put(m, "SM-S947Q", "Galaxy S26+ Japan (SIM Free)", "Galaxy S26+ Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1416
        put(m, "SM-S947Z", "Galaxy S26+ Japan (SoftBank)", "Galaxy S26+ Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1417
        put(m, "SM-S947C", "Galaxy S26+ Japan (Rakuten Mobile)", "Galaxy S26+ Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1418
        put(m, "SCG38", "Galaxy S26+ Japan (au)", "Galaxy S26+ Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1419
        put(m, "SC-52G", "Galaxy S26+ Japan (NTT Docomo)", "Galaxy S26+ Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1420
        put(m, "SM-S948B", "Galaxy S26 Ultra Global", "Galaxy S26 Ultra Global", "Samsung", "device_list_full_import"); // Device_List:L1421
        put(m, "SM-S948U", "Galaxy S26 Ultra US Carrier", "Galaxy S26 Ultra US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1422
        put(m, "SM-S948U1", "Galaxy S26 Ultra US Unlocked", "Galaxy S26 Ultra US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1423
        put(m, "SM-S948W", "Galaxy S26 Ultra Canada", "Galaxy S26 Ultra Canada", "Samsung", "device_list_full_import"); // Device_List:L1424
        put(m, "SM-S948N", "Galaxy S26 Ultra South Korea", "Galaxy S26 Ultra South Korea", "Samsung", "device_list_full_import"); // Device_List:L1425
        put(m, "SM-S948Q", "Galaxy S26 Ultra Japan (SIM Free)", "Galaxy S26 Ultra Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1426
        put(m, "SM-S948Z", "Galaxy S26 Ultra Japan (SoftBank)", "Galaxy S26 Ultra Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1427
        put(m, "SM-S948C", "Galaxy S26 Ultra Japan (Rakuten Mobile)", "Galaxy S26 Ultra Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1428
        put(m, "SCG37", "Galaxy S26 Ultra Japan (au)", "Galaxy S26 Ultra Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1429
        put(m, "SC-53G", "Galaxy S26 Ultra Japan (NTT Docomo)", "Galaxy S26 Ultra Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1430
        put(m, "SM-N960F", "Galaxy Note9 Global", "Galaxy Note9 Global", "Samsung", "device_list_full_import"); // Device_List:L1431
        put(m, "SM-N960U", "Galaxy Note9 US Carrier", "Galaxy Note9 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1432
        put(m, "SM-N960U1", "Galaxy Note9 US Unlocked", "Galaxy Note9 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1433
        put(m, "SM-N960W", "Galaxy Note9 Canada", "Galaxy Note9 Canada", "Samsung", "device_list_full_import"); // Device_List:L1434
        put(m, "SM-N960N", "Galaxy Note9 South Korea", "Galaxy Note9 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1435
        put(m, "SCV40", "Galaxy Note9 Japan (au)", "Galaxy Note9 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1436
        put(m, "SC-01L", "Galaxy Note9 Japan (NTT Docomo)", "Galaxy Note9 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1437
        put(m, "SM-N970F", "Galaxy Note10 Global", "Galaxy Note10 Global", "Samsung", "device_list_full_import"); // Device_List:L1438
        put(m, "SM-N970U", "Galaxy Note10 US Carrier", "Galaxy Note10 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1439
        put(m, "SM-N970U1", "Galaxy Note10 US Unlocked", "Galaxy Note10 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1440
        put(m, "SM-N970W", "Galaxy Note10 Canada", "Galaxy Note10 Canada", "Samsung", "device_list_full_import"); // Device_List:L1441
    }

    private static void fill8(Map<String, Entry> m) {
        put(m, "SM-N971N", "Galaxy Note10 5G South Korea", "Galaxy Note10 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1442
        put(m, "SM-N975F", "Galaxy Note 10+ Global", "Galaxy Note 10+ Global", "Samsung", "device_list_full_import"); // Device_List:L1443
        put(m, "SM-N975U", "Galaxy Note 10+ US Carrier", "Galaxy Note 10+ US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1444
        put(m, "SM-N975U1", "Galaxy Note 10+ US Unlocked", "Galaxy Note 10+ US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1445
        put(m, "SM-N975W", "Galaxy Note 10+ Canada", "Galaxy Note 10+ Canada", "Samsung", "device_list_full_import"); // Device_List:L1446
        put(m, "SM-N9750", "Galaxy Note 10+ HK & TW", "Galaxy Note 10+ HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1447
        put(m, "SM-N975C", "Galaxy Note 10+ Japan (Rakuten Mobile)", "Galaxy Note 10+ Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1448
        put(m, "SCV45", "Galaxy Note 10+ Japan (au)", "Galaxy Note 10+ Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1449
        put(m, "SC-01M", "Galaxy Note 10+ Japan (NTT Docomo)", "Galaxy Note 10+ Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1450
        put(m, "SM-N976B", "Galaxy Note10+ 5G Global (Exynos)", "Galaxy Note10+ 5G Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1451
        put(m, "SM-N976N", "Galaxy Note10+ 5G South Korea", "Galaxy Note10+ 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1452
        put(m, "SM-N976Q", "Galaxy Note10+ 5G Global (Snapdragon)", "Galaxy Note10+ 5G Global (Snapdragon)", "Samsung", "device_list_full_import"); // Device_List:L1453
        put(m, "SM-N976V", "Galaxy Note10+ 5G Verizon", "Galaxy Note10+ 5G Verizon", "Samsung", "device_list_full_import"); // Device_List:L1454
        put(m, "SM-N976U", "Galaxy Note10+ 5G US Carrier", "Galaxy Note10+ 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1455
        put(m, "SM-N770X", "Galaxy Note10 Lite Global", "Galaxy Note10 Lite Global", "Samsung", "device_list_full_import"); // Device_List:L1456
        put(m, "SM-N980F", "Galaxy Note20 Global", "Galaxy Note20 Global", "Samsung", "device_list_full_import"); // Device_List:L1457
        put(m, "SM-N981B", "Galaxy Note20 5G Global", "Galaxy Note20 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1458
        put(m, "SM-N981U", "Galaxy Note20 5G US Carrier", "Galaxy Note20 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1459
        put(m, "SM-N981U1", "Galaxy Note20 5G US Unlocked", "Galaxy Note20 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1460
        put(m, "SM-N981W", "Galaxy Note20 5G Canada", "Galaxy Note20 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1461
        put(m, "SM-N981N", "Galaxy Note20 5G South Korea", "Galaxy Note20 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1462
        put(m, "SM-N985F", "Galaxy Note20 Ultra Global", "Galaxy Note20 Ultra Global", "Samsung", "device_list_full_import"); // Device_List:L1463
        put(m, "SM-N986B", "Galaxy Note20 Ultra 5G Global", "Galaxy Note20 Ultra 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1464
        put(m, "SM-N986U", "Galaxy Note20 Ultra 5G US Carrier", "Galaxy Note20 Ultra 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1465
        put(m, "SM-N986U1", "Galaxy Note20 Ultra 5G US Unlocked", "Galaxy Note20 Ultra 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1466
        put(m, "SM-N986W", "Galaxy Note20 Ultra 5G Canada", "Galaxy Note20 Ultra 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1467
        put(m, "SM-N986N", "Galaxy Note20 Ultra 5G South Korea", "Galaxy Note20 Ultra 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1468
        put(m, "SCG06", "Galaxy Note20 Ultra 5G Japan (au)", "Galaxy Note20 Ultra 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1469
        put(m, "SC-53A", "Galaxy Note20 Ultra 5G Japan (NTT Docomo)", "Galaxy Note20 Ultra 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1470
        put(m, "SM-F900F", "Galaxy Fold Global", "Galaxy Fold Global", "Samsung", "device_list_full_import"); // Device_List:L1471
        put(m, "SM-F900U", "Galaxy Fold US Carrier", "Galaxy Fold US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1472
        put(m, "SM-F900U1", "Galaxy Fold US Unlocked", "Galaxy Fold US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1473
        put(m, "SM-F900W", "Galaxy Fold Canada", "Galaxy Fold Canada", "Samsung", "device_list_full_import"); // Device_List:L1474
        put(m, "SCV44", "Galaxy Fold Japan (au)", "Galaxy Fold Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1475
        put(m, "SM-F907B", "Galaxy Fold 5G Global", "Galaxy Fold 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1476
        put(m, "SM-F907N", "Galaxy Fold 5G South Korea", "Galaxy Fold 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1477
        put(m, "SM-F916B", "Galaxy Z Fold2 5G Global", "Galaxy Z Fold2 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1478
        put(m, "SM-F916U", "Galaxy Z Fold2 5G US Carrier", "Galaxy Z Fold2 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1479
        put(m, "SM-F916U1", "Galaxy Z Fold2 5G US Unlocked", "Galaxy Z Fold2 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1480
        put(m, "SM-F916W", "Galaxy Z Fold2 5G Canada", "Galaxy Z Fold2 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1481
        put(m, "SM-F916N", "Galaxy Z Fold2 5G South Korea", "Galaxy Z Fold2 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1482
        put(m, "SM-F916Q", "Galaxy Z Fold2 5G Japan (SIM Free)", "Galaxy Z Fold2 5G Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1483
        put(m, "SM-F926B", "Galaxy Z Fold3 5G Global", "Galaxy Z Fold3 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1484
        put(m, "SM-F926U", "Galaxy Z Fold3 5G US Carrier", "Galaxy Z Fold3 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1485
        put(m, "SM-F926U1", "Galaxy Z Fold3 5G US Unlocked", "Galaxy Z Fold3 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1486
        put(m, "SM-F926W", "Galaxy Z Fold3 5G Canada", "Galaxy Z Fold3 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1487
        put(m, "SM-F926N", "Galaxy Z Fold3 5G South Korea", "Galaxy Z Fold3 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1488
        put(m, "SCG11", "Galaxy Z Fold3 5G Japan (au)", "Galaxy Z Fold3 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1489
        put(m, "SC-55B", "Galaxy Z Fold3 5G Japan (NTT Docomo)", "Galaxy Z Fold3 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1490
        put(m, "SM-F936B", "Galaxy Z Fold4 Global", "Galaxy Z Fold4 Global", "Samsung", "device_list_full_import"); // Device_List:L1491
        put(m, "SM-F936U", "Galaxy Z Fold4 US Carrier", "Galaxy Z Fold4 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1492
        put(m, "SM-F936U1", "Galaxy Z Fold4 US Unlocked", "Galaxy Z Fold4 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1493
        put(m, "SM-F936W", "Galaxy Z Fold4 Canada", "Galaxy Z Fold4 Canada", "Samsung", "device_list_full_import"); // Device_List:L1494
        put(m, "SM-F936N", "Galaxy Z Fold4 South Korea", "Galaxy Z Fold4 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1495
        put(m, "SCG16", "Galaxy Z Fold4 Japan (au)", "Galaxy Z Fold4 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1496
        put(m, "SC-55C", "Galaxy Z Fold4 Japan (NTT Docomo)", "Galaxy Z Fold4 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1497
        put(m, "SM-F946B", "Galaxy Z Fold5 Global", "Galaxy Z Fold5 Global", "Samsung", "device_list_full_import"); // Device_List:L1498
        put(m, "SM-F946U", "Galaxy Z Fold5 US Carrier", "Galaxy Z Fold5 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1499
        put(m, "SM-F946U1", "Galaxy Z Fold5 US Unlocked", "Galaxy Z Fold5 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1500
        put(m, "SM-F946W", "Galaxy Z Fold5 Canada", "Galaxy Z Fold5 Canada", "Samsung", "device_list_full_import"); // Device_List:L1501
        put(m, "SM-F946N", "Galaxy Z Fold5 South Korea", "Galaxy Z Fold5 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1502
        put(m, "SM-F946Q", "Galaxy Z Fold5 Japan (SIM Free)", "Galaxy Z Fold5 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1503
        put(m, "SCG22", "Galaxy Z Fold5 Japan (au)", "Galaxy Z Fold5 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1504
        put(m, "SC-55D", "Galaxy Z Fold5 Japan (NTT Docomo)", "Galaxy Z Fold5 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1505
        put(m, "SM-F956B", "Galaxy Z Fold6 Global", "Galaxy Z Fold6 Global", "Samsung", "device_list_full_import"); // Device_List:L1506
        put(m, "SM-F956U", "Galaxy Z Fold6 US Carrier", "Galaxy Z Fold6 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1507
        put(m, "SM-F956U1", "Galaxy Z Fold6 US Unlocked", "Galaxy Z Fold6 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1508
        put(m, "SM-F956W", "Galaxy Z Fold6 Canada", "Galaxy Z Fold6 Canada", "Samsung", "device_list_full_import"); // Device_List:L1509
        put(m, "SM-F956N", "Galaxy Z Fold6 South Korea", "Galaxy Z Fold6 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1510
        put(m, "SM-F956Q", "Galaxy Z Fold6 Japan (SIM Free)", "Galaxy Z Fold6 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1511
        put(m, "SCG28", "Galaxy Z Fold6 Japan (au)", "Galaxy Z Fold6 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1512
        put(m, "SC-55E", "Galaxy Z Fold6 Japan (NTT Docomo)", "Galaxy Z Fold6 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1513
        put(m, "SM-F958N", "Galaxy Z Fold Special Edition South Korea", "Galaxy Z Fold Special Edition South Korea", "Samsung", "device_list_full_import"); // Device_List:L1514
        put(m, "SM-F966B", "Galaxy Z Fold7 Global", "Galaxy Z Fold7 Global", "Samsung", "device_list_full_import"); // Device_List:L1515
        put(m, "SM-F966U", "Galaxy Z Fold7 US Carrier", "Galaxy Z Fold7 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1516
        put(m, "SM-F966U1", "Galaxy Z Fold7 US Unlocked", "Galaxy Z Fold7 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1517
        put(m, "SM-F966W", "Galaxy Z Fold7 Canada", "Galaxy Z Fold7 Canada", "Samsung", "device_list_full_import"); // Device_List:L1518
        put(m, "SM-F966N", "Galaxy Z Fold7 South Korea", "Galaxy Z Fold7 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1519
        put(m, "SM-F966Q", "Galaxy Z Fold7 Japan (SIM Free)", "Galaxy Z Fold7 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1520
        put(m, "SM-F966Z", "Galaxy Z Fold7 Japan (SoftBank)", "Galaxy Z Fold7 Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1521
        put(m, "SCG34", "Galaxy Z Fold7 Japan (au)", "Galaxy Z Fold7 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1522
        put(m, "SC-56F", "Galaxy Z Fold7 Japan (NTT Docomo)", "Galaxy Z Fold7 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1523
        put(m, "SM-F968B", "Galaxy Z TriFold Global", "Galaxy Z TriFold Global", "Samsung", "device_list_full_import"); // Device_List:L1524
        put(m, "SM-F968U1", "Galaxy Z TriFold US Unlocked", "Galaxy Z TriFold US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1525
        put(m, "SM-F968N", "Galaxy Z TriFold South Korea", "Galaxy Z TriFold South Korea", "Samsung", "device_list_full_import"); // Device_List:L1526
        put(m, "SM-F700F", "Galaxy Z Flip Global", "Galaxy Z Flip Global", "Samsung", "device_list_full_import"); // Device_List:L1527
        put(m, "SM-F700U", "Galaxy Z Flip US Carrier", "Galaxy Z Flip US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1528
        put(m, "SM-F700U1", "Galaxy Z Flip US Unlocked", "Galaxy Z Flip US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1529
        put(m, "SM-F700W", "Galaxy Z Flip Canada", "Galaxy Z Flip Canada", "Samsung", "device_list_full_import"); // Device_List:L1530
        put(m, "SM-F700N", "Galaxy Z Flip South Korea", "Galaxy Z Flip South Korea", "Samsung", "device_list_full_import"); // Device_List:L1531
        put(m, "SCV47", "Galaxy Z Flip Japan (au)", "Galaxy Z Flip Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1532
        put(m, "SM-F707B", "Galaxy Z Flip 5G Global", "Galaxy Z Flip 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1533
        put(m, "SM-F707U", "Galaxy Z Flip 5G US Carrier", "Galaxy Z Flip 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1534
        put(m, "SM-F707U1", "Galaxy Z Flip 5G US Unlocked", "Galaxy Z Flip 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1535
        put(m, "SM-F707W", "Galaxy Z Flip 5G Canada", "Galaxy Z Flip 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1536
        put(m, "SM-F707N", "Galaxy Z Flip 5G South Korea", "Galaxy Z Flip 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1537
        put(m, "SCG04", "Galaxy Z Flip 5G Japan (au)", "Galaxy Z Flip 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1538
        put(m, "SM-F711B", "Galaxy Z Flip3 5G Global", "Galaxy Z Flip3 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1539
        put(m, "SM-F711U", "Galaxy Z Flip3 5G US Carrier", "Galaxy Z Flip3 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1540
        put(m, "SM-F711U1", "Galaxy Z Flip3 5G US Unlocked", "Galaxy Z Flip3 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1541
        put(m, "SM-F711W", "Galaxy Z Flip3 5G Canada", "Galaxy Z Flip3 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1542
        put(m, "SM-F711N", "Galaxy Z Flip3 5G South Korea", "Galaxy Z Flip3 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1543
        put(m, "SCG12", "Galaxy Z Flip3 5G Japan (au)", "Galaxy Z Flip3 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1544
        put(m, "SC-54B", "Galaxy Z Flip3 5G Japan (NTT Docomo)", "Galaxy Z Flip3 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1545
        put(m, "SM-F721B", "Galaxy Z Flip4 Global", "Galaxy Z Flip4 Global", "Samsung", "device_list_full_import"); // Device_List:L1546
        put(m, "SM-F721U", "Galaxy Z Flip4 US Carrier", "Galaxy Z Flip4 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1547
        put(m, "SM-F721U1", "Galaxy Z Flip4 US Unlocked", "Galaxy Z Flip4 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1548
        put(m, "SM-F721W", "Galaxy Z Flip4 Canada", "Galaxy Z Flip4 Canada", "Samsung", "device_list_full_import"); // Device_List:L1549
        put(m, "SM-F721N", "Galaxy Z Flip4 South Korea", "Galaxy Z Flip4 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1550
        put(m, "SM-F721C", "Galaxy Z Flip4 Japan (Rakuten Mobile)", "Galaxy Z Flip4 Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1551
        put(m, "SCG17", "Galaxy Z Flip4 Japan (au)", "Galaxy Z Flip4 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1552
        put(m, "SC-54C", "Galaxy Z Flip4 Japan (NTT Docomo)", "Galaxy Z Flip4 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1553
        put(m, "SM-F731B", "Galaxy Z Flip5 Global", "Galaxy Z Flip5 Global", "Samsung", "device_list_full_import"); // Device_List:L1554
        put(m, "SM-F731U", "Galaxy Z Flip5 US Carrier", "Galaxy Z Flip5 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1555
        put(m, "SM-F731U1", "Galaxy Z Flip5 US Unlocked", "Galaxy Z Flip5 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1556
        put(m, "SM-F731W", "Galaxy Z Flip5 Canada", "Galaxy Z Flip5 Canada", "Samsung", "device_list_full_import"); // Device_List:L1557
        put(m, "SM-F731N", "Galaxy Z Flip5 South Korea", "Galaxy Z Flip5 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1558
        put(m, "SM-F731Q", "Galaxy Z Flip5 Japan (SIM Free)", "Galaxy Z Flip5 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1559
        put(m, "SCG23", "Galaxy Z Flip5 Japan (au)", "Galaxy Z Flip5 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1560
        put(m, "SC-54D", "Galaxy Z Flip5 Japan (NTT Docomo)", "Galaxy Z Flip5 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1561
        put(m, "SM-F741B", "Galaxy Z Flip6 Global", "Galaxy Z Flip6 Global", "Samsung", "device_list_full_import"); // Device_List:L1562
        put(m, "SM-F741U", "Galaxy Z Flip6 US Carrier", "Galaxy Z Flip6 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1563
        put(m, "SM-F741U1", "Galaxy Z Flip6 US Unlocked", "Galaxy Z Flip6 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1564
        put(m, "SM-F741W", "Galaxy Z Flip6 Canada", "Galaxy Z Flip6 Canada", "Samsung", "device_list_full_import"); // Device_List:L1565
        put(m, "SM-F741N", "Galaxy Z Flip6 South Korea", "Galaxy Z Flip6 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1566
        put(m, "SM-F741Q", "Galaxy Z Flip6 Japan (SIM Free)", "Galaxy Z Flip6 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1567
        put(m, "SCG29", "Galaxy Z Flip6 Japan (au)", "Galaxy Z Flip6 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1568
        put(m, "SC-54E", "Galaxy Z Flip6 Japan (NTT Docomo)", "Galaxy Z Flip6 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1569
        put(m, "SM-F766B", "Galaxy Z Flip7 Global", "Galaxy Z Flip7 Global", "Samsung", "device_list_full_import"); // Device_List:L1570
        put(m, "SM-F766U", "Galaxy Z Flip7 US Carrier", "Galaxy Z Flip7 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1571
        put(m, "SM-F766U1", "Galaxy Z Flip7 US Unlocked", "Galaxy Z Flip7 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1572
        put(m, "SM-F766W", "Galaxy Z Flip7 Canada", "Galaxy Z Flip7 Canada", "Samsung", "device_list_full_import"); // Device_List:L1573
        put(m, "SM-F766N", "Galaxy Z Flip7 South Korea", "Galaxy Z Flip7 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1574
        put(m, "SM-F766Q", "Galaxy Z Flip7 Japan (SIM Free)", "Galaxy Z Flip7 Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1575
        put(m, "SM-F766Z", "Galaxy Z Flip7 Japan (SoftBank)", "Galaxy Z Flip7 Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1576
        put(m, "SCG35", "Galaxy Z Flip7 Japan (au)", "Galaxy Z Flip7 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1577
        put(m, "SC-55F", "Galaxy Z Flip7 Japan (NTT Docomo)", "Galaxy Z Flip7 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1578
        put(m, "SM-F761B", "Galaxy Z Flip7 FE Global", "Galaxy Z Flip7 FE Global", "Samsung", "device_list_full_import"); // Device_List:L1579
        put(m, "SM-F761U", "Galaxy Z Flip7 FE US Carrier", "Galaxy Z Flip7 FE US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1580
        put(m, "SM-F761U1", "Galaxy Z Flip7 FE US Unlocked", "Galaxy Z Flip7 FE US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1581
        put(m, "SM-F761N", "Galaxy Z Flip7 FE South Korea", "Galaxy Z Flip7 FE South Korea", "Samsung", "device_list_full_import"); // Device_List:L1582
        put(m, "SM-A015F", "Galaxy A01 Global", "Galaxy A01 Global", "Samsung", "device_list_full_import"); // Device_List:L1583
        put(m, "SM-A015U", "Galaxy A01 US Carrier", "Galaxy A01 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1584
        put(m, "SM-A015U1", "Galaxy A01 US Unlocked", "Galaxy A01 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1585
        put(m, "SM-A015A", "Galaxy A01 AT&T", "Galaxy A01 AT&T", "Samsung", "device_list_full_import"); // Device_List:L1586
        put(m, "SM-A015AZ", "Galaxy A01 Cricket", "Galaxy A01 Cricket", "Samsung", "device_list_full_import"); // Device_List:L1587
        put(m, "SM-A015T1", "Galaxy A01 T-Mobile", "Galaxy A01 T-Mobile", "Samsung", "device_list_full_import"); // Device_List:L1588
        put(m, "SM-A015V", "Galaxy A01 Verizon", "Galaxy A01 Verizon", "Samsung", "device_list_full_import"); // Device_List:L1589
        put(m, "SM-S111DL", "Galaxy A01 TracFone", "Galaxy A01 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1590
        put(m, "SM-A015G", "Galaxy A01 India", "Galaxy A01 India", "Samsung", "device_list_full_import"); // Device_List:L1591
        put(m, "SM-A015M", "Galaxy A01 Latin America", "Galaxy A01 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1592
        put(m, "SM-A013G", "Galaxy A01 Core Global", "Galaxy A01 Core Global", "Samsung", "device_list_full_import"); // Device_List:L1593
        put(m, "SM-A013M", "Galaxy A01 Core Latin America", "Galaxy A01 Core Latin America", "Samsung", "device_list_full_import"); // Device_List:L1594
        put(m, "SM-A022G", "Galaxy A02 Global", "Galaxy A02 Global", "Samsung", "device_list_full_import"); // Device_List:L1595
        put(m, "SM-A022M", "Galaxy A02 Latin America", "Galaxy A02 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1596
        put(m, "SM-A025F", "Galaxy A02s Global", "Galaxy A02s Global", "Samsung", "device_list_full_import"); // Device_List:L1597
        put(m, "SM-A025G", "Galaxy A02s EU", "Galaxy A02s EU", "Samsung", "device_list_full_import"); // Device_List:L1598
        put(m, "SM-A025U", "Galaxy A02s US Carrier", "Galaxy A02s US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1599
        put(m, "SM-A025U1", "Galaxy A02s US Unlocked", "Galaxy A02s US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1600
        put(m, "SM-A025A", "Galaxy A02s AT&T", "Galaxy A02s AT&T", "Samsung", "device_list_full_import"); // Device_List:L1601
        put(m, "SM-A025AZ", "Galaxy A02s Cricket", "Galaxy A02s Cricket", "Samsung", "device_list_full_import"); // Device_List:L1602
        put(m, "SM-A025V", "Galaxy A02s Verizon", "Galaxy A02s Verizon", "Samsung", "device_list_full_import"); // Device_List:L1603
        put(m, "SM-S124DL", "Galaxy A02s TracFone", "Galaxy A02s TracFone", "Samsung", "device_list_full_import"); // Device_List:L1604
        put(m, "SM-A025M", "Galaxy A02s Latin America", "Galaxy A02s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1605
        put(m, "SM-A035F", "Galaxy A03 Global", "Galaxy A03 Global", "Samsung", "device_list_full_import"); // Device_List:L1606
        put(m, "SM-A035G", "Galaxy A03 EU", "Galaxy A03 EU", "Samsung", "device_list_full_import"); // Device_List:L1607
        put(m, "SM-A035M", "Galaxy A03 Latin America", "Galaxy A03 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1608
        put(m, "SM-A032F", "Galaxy A03 Core Global", "Galaxy A03 Core Global", "Samsung", "device_list_full_import"); // Device_List:L1609
        put(m, "SM-A032M", "Galaxy A03 Core Latin America", "Galaxy A03 Core Latin America", "Samsung", "device_list_full_import"); // Device_List:L1610
        put(m, "SM-A037F", "Galaxy A03s Global", "Galaxy A03s Global", "Samsung", "device_list_full_import"); // Device_List:L1611
        put(m, "SM-A037G", "Galaxy A03s EU", "Galaxy A03s EU", "Samsung", "device_list_full_import"); // Device_List:L1612
        put(m, "SM-A037M", "Galaxy A03s Latin America", "Galaxy A03s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1613
        put(m, "SM-A037U", "Galaxy A03s US Carrier", "Galaxy A03s US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1614
        put(m, "SM-A037U1", "Galaxy A03s US Unlocked", "Galaxy A03s US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1615
        put(m, "SM-S134DL", "Galaxy A03s TracFone", "Galaxy A03s TracFone", "Samsung", "device_list_full_import"); // Device_List:L1616
        put(m, "SM-A037W", "Galaxy A03s Canada", "Galaxy A03s Canada", "Samsung", "device_list_full_import"); // Device_List:L1617
        put(m, "SM-A045F", "Galaxy A04 Global", "Galaxy A04 Global", "Samsung", "device_list_full_import"); // Device_List:L1618
        put(m, "SM-A045M", "Galaxy A04 Latin America", "Galaxy A04 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1619
        put(m, "SM-A042F", "Galaxy A04e Global", "Galaxy A04e Global", "Samsung", "device_list_full_import"); // Device_List:L1620
        put(m, "SM-A042M", "Galaxy A04e Latin America", "Galaxy A04e Latin America", "Samsung", "device_list_full_import"); // Device_List:L1621
    }

    private static void fill9(Map<String, Entry> m) {
        put(m, "SM-A047F", "Galaxy A04s Global", "Galaxy A04s Global", "Samsung", "device_list_full_import"); // Device_List:L1622
        put(m, "SM-A047M", "Galaxy A04s Latin America", "Galaxy A04s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1623
        put(m, "SM-A055F", "Galaxy A05 Global", "Galaxy A05 Global", "Samsung", "device_list_full_import"); // Device_List:L1624
        put(m, "SM-A055M", "Galaxy A05 Latin America", "Galaxy A05 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1625
        put(m, "SM-A057F", "Galaxy A05s Global", "Galaxy A05s Global", "Samsung", "device_list_full_import"); // Device_List:L1626
        put(m, "SM-A057G", "Galaxy A05s EU", "Galaxy A05s EU", "Samsung", "device_list_full_import"); // Device_List:L1627
        put(m, "SM-A057M", "Galaxy A05s Latin America", "Galaxy A05s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1628
        put(m, "SM-A065F", "Galaxy A06 Global", "Galaxy A06 Global", "Samsung", "device_list_full_import"); // Device_List:L1629
        put(m, "SM-A065M", "Galaxy A06 Latin America", "Galaxy A06 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1630
        put(m, "SM-A066B", "Galaxy A06 5G Global", "Galaxy A06 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1631
        put(m, "SM-A066M", "Galaxy A06 5G Latin America", "Galaxy A06 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1632
        put(m, "SM-A075F", "Galaxy A07 Global", "Galaxy A07 Global", "Samsung", "device_list_full_import"); // Device_List:L1633
        put(m, "SM-A075M", "Galaxy A07 Latin America", "Galaxy A07 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1634
        put(m, "SM-A076B", "Galaxy A07 5G Global", "Galaxy A07 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1635
        put(m, "SM-A076M", "Galaxy A07 5G Latin America", "Galaxy A07 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1636
        put(m, "SM-A105M", "Galaxy A10 Latin America", "Galaxy A10 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1637
        put(m, "SM-A105N", "Galaxy A10 South Korea", "Galaxy A10 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1638
        put(m, "SM-A102U", "Galaxy A10e US Carrier", "Galaxy A10e US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1639
        put(m, "SM-A102U1", "Galaxy A10e US Unlocked", "Galaxy A10e US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1640
        put(m, "SM-S102DL", "Galaxy A10e TracFone", "Galaxy A10e TracFone", "Samsung", "device_list_full_import"); // Device_List:L1641
        put(m, "SM-A102W", "Galaxy A10e Canada", "Galaxy A10e Canada", "Samsung", "device_list_full_import"); // Device_List:L1642
        put(m, "SM-A102N", "Galaxy A10e South Korea", "Galaxy A10e South Korea", "Samsung", "device_list_full_import"); // Device_List:L1643
        put(m, "SM-A107F", "Galaxy A10s Global", "Galaxy A10s Global", "Samsung", "device_list_full_import"); // Device_List:L1644
        put(m, "SM-A107M", "Galaxy A10s Latin America", "Galaxy A10s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1645
        put(m, "SM-A115F", "Galaxy A11 Global", "Galaxy A11 Global", "Samsung", "device_list_full_import"); // Device_List:L1646
        put(m, "SM-A115U", "Galaxy A11 US Carrier", "Galaxy A11 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1647
        put(m, "SM-A115U1", "Galaxy A11 US Unlocked", "Galaxy A11 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1648
        put(m, "SM-A115AP", "Galaxy A11 AT&T", "Galaxy A11 AT&T", "Samsung", "device_list_full_import"); // Device_List:L1649
        put(m, "SM-A115AZ", "Galaxy A11 Cricket", "Galaxy A11 Cricket", "Samsung", "device_list_full_import"); // Device_List:L1650
        put(m, "SM-S115DL", "Galaxy A11 TracFone", "Galaxy A11 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1651
        put(m, "SM-A115W", "Galaxy A11 Canada", "Galaxy A11 Canada", "Samsung", "device_list_full_import"); // Device_List:L1652
        put(m, "SM-A115M", "Galaxy A11 Latin America", "Galaxy A11 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1653
        put(m, "SM-A125F", "Galaxy A12 Global", "Galaxy A12 Global", "Samsung", "device_list_full_import"); // Device_List:L1654
        put(m, "SM-A125M", "Galaxy A12 Latin America", "Galaxy A12 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1655
        put(m, "SM-A125N", "Galaxy A12 South Korea", "Galaxy A12 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1656
        put(m, "SM-A125U", "Galaxy A12 US Carrier", "Galaxy A12 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1657
        put(m, "SM-A125U1", "Galaxy A12 US Unlocked", "Galaxy A12 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1658
        put(m, "SM-S127DL", "Galaxy A12 TracFone", "Galaxy A12 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1659
        put(m, "SM-A125W", "Galaxy A12 Canada", "Galaxy A12 Canada", "Samsung", "device_list_full_import"); // Device_List:L1660
        put(m, "SM-A127F", "Galaxy A12 Nacho Global", "Galaxy A12 Nacho Global", "Samsung", "device_list_full_import"); // Device_List:L1661
        put(m, "SM-A127M", "Galaxy A12 Nacho Latin America", "Galaxy A12 Nacho Latin America", "Samsung", "device_list_full_import"); // Device_List:L1662
        put(m, "SM-A135F", "Galaxy A13 Global (Exynos)", "Galaxy A13 Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1663
        put(m, "SM-A135U", "Galaxy A13 US Carrier", "Galaxy A13 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1664
        put(m, "SM-A135U1", "Galaxy A13 US Unlocked", "Galaxy A13 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1665
        put(m, "SM-A135M", "Galaxy A13 Latin America", "Galaxy A13 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1666
        put(m, "SM-A135N", "Galaxy A13 South Korea", "Galaxy A13 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1667
        put(m, "SM-A137F", "Galaxy A13 Global (MediaTek)", "Galaxy A13 Global (MediaTek)", "Samsung", "device_list_full_import"); // Device_List:L1668
        put(m, "SM-A136B", "Galaxy A13 5G Global", "Galaxy A13 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1669
        put(m, "SM-A136U", "Galaxy A13 5G US Carrier", "Galaxy A13 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1670
        put(m, "SM-A136U1", "Galaxy A13 5G US Unlocked", "Galaxy A13 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1671
        put(m, "SM-S136DL", "Galaxy A13 5G TracFone", "Galaxy A13 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1672
        put(m, "SM-A136W", "Galaxy A13 5G Canada", "Galaxy A13 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1673
        put(m, "SM-A136M", "Galaxy A13 5G Latin America", "Galaxy A13 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1674
        put(m, "SM-A145FB", "Galaxy A14 Global (Exynos)", "Galaxy A14 Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1675
        put(m, "SM-A145MB", "Galaxy A14 Latin America", "Galaxy A14 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1676
        put(m, "SM-A145P", "Galaxy A14 MEA (MediaTek)", "Galaxy A14 MEA (MediaTek)", "Samsung", "device_list_full_import"); // Device_List:L1677
        put(m, "SM-A145R", "Galaxy A14 EU (MediaTek)", "Galaxy A14 EU (MediaTek)", "Samsung", "device_list_full_import"); // Device_List:L1678
        put(m, "SM-A146B", "Galaxy A14 5G Global (Exynos)", "Galaxy A14 5G Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1679
        put(m, "SM-A146M", "Galaxy A14 5G Latin America", "Galaxy A14 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1680
        put(m, "SM-A146P", "Galaxy A14 5G Global (MediaTek)", "Galaxy A14 5G Global (MediaTek)", "Samsung", "device_list_full_import"); // Device_List:L1681
        put(m, "SM-A146U", "Galaxy A14 5G US Carrier", "Galaxy A14 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1682
        put(m, "SM-A146U1", "Galaxy A14 5G US Unlocked", "Galaxy A14 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1683
        put(m, "SM-S146VL", "Galaxy A14 5G TracFone", "Galaxy A14 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1684
        put(m, "SM-A146W", "Galaxy A14 5G Canada", "Galaxy A14 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1685
        put(m, "SM-A155F", "Galaxy A15 Global", "Galaxy A15 Global", "Samsung", "device_list_full_import"); // Device_List:L1686
        put(m, "SM-A155M", "Galaxy A15 Latin America", "Galaxy A15 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1687
        put(m, "SM-A155N", "Galaxy A15 South Korea", "Galaxy A15 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1688
        put(m, "SM-A156E", "Galaxy A15 5G Global", "Galaxy A15 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1689
        put(m, "SM-A156B", "Galaxy A15 5G EU", "Galaxy A15 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1690
        put(m, "SM-A156U", "Galaxy A15 5G US Carrier", "Galaxy A15 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1691
        put(m, "SM-A156U1", "Galaxy A15 5G US Unlocked", "Galaxy A15 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1692
        put(m, "SM-S156V", "Galaxy A15 5G TracFone", "Galaxy A15 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1693
        put(m, "SM-A156W", "Galaxy A15 5G Canada", "Galaxy A15 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1694
        put(m, "SM-A156M", "Galaxy A15 5G Latin America", "Galaxy A15 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1695
        put(m, "SM-A1560", "Galaxy A15 5G HK & TW", "Galaxy A15 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1696
        put(m, "SM-A165F", "Galaxy A16 Global", "Galaxy A16 Global", "Samsung", "device_list_full_import"); // Device_List:L1697
        put(m, "SM-A165M", "Galaxy A16 Latin America", "Galaxy A16 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1698
        put(m, "SM-A165N", "Galaxy A16 South Korea", "Galaxy A16 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1699
        put(m, "SM-A166E", "Galaxy A16 5G Global (Exynos)", "Galaxy A16 5G Global (Exynos)", "Samsung", "device_list_full_import"); // Device_List:L1700
        put(m, "SM-A166B", "Galaxy A16 5G EU", "Galaxy A16 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1701
        put(m, "SM-A166U", "Galaxy A16 5G US Carrier", "Galaxy A16 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1702
        put(m, "SM-A166U1", "Galaxy A16 5G US Unlocked", "Galaxy A16 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1703
        put(m, "SM-S166V", "Galaxy A16 5G TracFone", "Galaxy A16 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1704
        put(m, "SM-A166W", "Galaxy A16 5G Canada", "Galaxy A16 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1705
        put(m, "SM-A166M", "Galaxy A16 5G Latin America", "Galaxy A16 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1706
        put(m, "SM-A1660", "Galaxy A16 5G HK & TW", "Galaxy A16 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1707
        put(m, "SM-A166P", "Galaxy A16 5G Global (MediaTek)", "Galaxy A16 5G Global (MediaTek)", "Samsung", "device_list_full_import"); // Device_List:L1708
        put(m, "SM-A175F", "Galaxy A17 Global", "Galaxy A17 Global", "Samsung", "device_list_full_import"); // Device_List:L1709
        put(m, "SM-A175N", "Galaxy A17 South Korea", "Galaxy A17 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1710
        put(m, "SM-A176B", "Galaxy A17 5G Global", "Galaxy A17 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1711
        put(m, "SM-A176U", "Galaxy A17 5G US Carrier", "Galaxy A17 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1712
        put(m, "SM-A176U1", "Galaxy A17 5G US Unlocked", "Galaxy A17 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1713
        put(m, "SM-S176V", "Galaxy A17 5G TracFone", "Galaxy A17 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1714
        put(m, "SM-A176W", "Galaxy A17 5G Canada", "Galaxy A17 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1715
        put(m, "SM-A1760", "Galaxy A17 5G HK & TW", "Galaxy A17 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1716
        put(m, "SM-A260F", "Galaxy A2 Core Global", "Galaxy A2 Core Global", "Samsung", "device_list_full_import"); // Device_List:L1717
        put(m, "SM-A260G", "Galaxy A2 Core India", "Galaxy A2 Core India", "Samsung", "device_list_full_import"); // Device_List:L1718
        put(m, "SM-A205F", "Galaxy A20 Global", "Galaxy A20 Global", "Samsung", "device_list_full_import"); // Device_List:L1719
        put(m, "SM-A205FN", "Galaxy A20 EU", "Galaxy A20 EU", "Samsung", "device_list_full_import"); // Device_List:L1720
        put(m, "SM-A205G", "Galaxy A20 Latin America", "Galaxy A20 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1721
        put(m, "SM-A205GN", "Galaxy A20 Southeast Asia", "Galaxy A20 Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1722
        put(m, "SM-A205W", "Galaxy A20 Canada", "Galaxy A20 Canada", "Samsung", "device_list_full_import"); // Device_List:L1723
        put(m, "SM-A205YN", "Galaxy A20 Australia & New Zealand", "Galaxy A20 Australia & New Zealand", "Samsung", "device_list_full_import"); // Device_List:L1724
        put(m, "SCV46", "Galaxy A20 Japan (au)", "Galaxy A20 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1725
        put(m, "SC-02M", "Galaxy A20 Japan (NTT Docomo)", "Galaxy A20 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1726
        put(m, "SM-A205U", "Galaxy A20 US Carrier", "Galaxy A20 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1727
        put(m, "SM-A205U1", "Galaxy A20 US Unlocked", "Galaxy A20 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1728
        put(m, "SM-S205DL", "Galaxy A20 TracFone", "Galaxy A20 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1729
        put(m, "SM-A202F", "Galaxy A20e Global", "Galaxy A20e Global", "Samsung", "device_list_full_import"); // Device_List:L1730
        put(m, "SM-A207F", "Galaxy A20s Global", "Galaxy A20s Global", "Samsung", "device_list_full_import"); // Device_List:L1731
        put(m, "SM-A207W", "Galaxy A20s Latin America", "Galaxy A20s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1732
        put(m, "SM-A215U", "Galaxy A21 US Carrier", "Galaxy A21 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1733
        put(m, "SM-A215U1", "Galaxy A21 US Unlocked", "Galaxy A21 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1734
        put(m, "SM-S215DL", "Galaxy A21 TracFone", "Galaxy A21 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1735
        put(m, "SM-A215W", "Galaxy A21 Canada", "Galaxy A21 Canada", "Samsung", "device_list_full_import"); // Device_List:L1736
        put(m, "SCV49", "Galaxy A21 Japan (au)", "Galaxy A21 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1737
        put(m, "SC-42A", "Galaxy A21 Japan (NTT Docomo)", "Galaxy A21 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1738
        put(m, "SM-A217F", "Galaxy A21s Global", "Galaxy A21s Global", "Samsung", "device_list_full_import"); // Device_List:L1739
        put(m, "SM-A217M", "Galaxy A21s Latin America", "Galaxy A21s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1740
        put(m, "SM-A217N", "Galaxy A21s South Korea", "Galaxy A21s South Korea", "Samsung", "device_list_full_import"); // Device_List:L1741
        put(m, "SM-A225F", "Galaxy A22 Global", "Galaxy A22 Global", "Samsung", "device_list_full_import"); // Device_List:L1742
        put(m, "SM-A225M", "Galaxy A22 Latin America", "Galaxy A22 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1743
        put(m, "SM-A226BR", "Galaxy A22 5G Global", "Galaxy A22 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1744
        put(m, "SC-56B", "Galaxy A22 5G Japan (NTT DOcomo)", "Galaxy A22 5G Japan (NTT DOcomo)", "Samsung", "device_list_full_import"); // Device_List:L1745
        put(m, "SM-A226B", "Galaxy A22s 5G Global", "Galaxy A22s 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1746
        put(m, "SM-A235F", "Galaxy A23 Global", "Galaxy A23 Global", "Samsung", "device_list_full_import"); // Device_List:L1747
        put(m, "SM-A235M", "Galaxy A23 Latin America", "Galaxy A23 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1748
        put(m, "SM-A235N", "Galaxy A23 South Korea", "Galaxy A23 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1749
        put(m, "SM-A235E", "Galaxy A23 5G Global", "Galaxy A23 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1750
        put(m, "SM-A236B", "Galaxy A23 5G EU", "Galaxy A23 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1751
        put(m, "SM-A236U", "Galaxy A23 5G US Carrier", "Galaxy A23 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1752
        put(m, "SM-A236U1", "Galaxy A23 5G US Unlocked", "Galaxy A23 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1753
        put(m, "SM-A236V", "Galaxy A23 5G UW Verizon", "Galaxy A23 5G UW Verizon", "Samsung", "device_list_full_import"); // Device_List:L1754
        put(m, "SM-S237VL", "Galaxy A23 5G TracFone", "Galaxy A23 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1755
        put(m, "SM-A236M", "Galaxy A23 5G Latin America", "Galaxy A23 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1756
        put(m, "SM-A2360", "Galaxy A23 5G HK", "Galaxy A23 5G HK", "Samsung", "device_list_full_import"); // Device_List:L1757
        put(m, "SCG18", "Galaxy A23 5G Japan (au)", "Galaxy A23 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1758
        put(m, "SC-56C", "Galaxy A23 5G Japan (NTT Docomo)", "Galaxy A23 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1759
        put(m, "SM-A233C", "Galaxy A23 5G Japan (Rakuten Mobile)", "Galaxy A23 5G Japan (Rakuten Mobile)", "Samsung", "device_list_full_import"); // Device_List:L1760
        put(m, "SM-A245F", "Galaxy A24 Global", "Galaxy A24 Global", "Samsung", "device_list_full_import"); // Device_List:L1761
        put(m, "SM-A245M", "Galaxy A24 Latin America", "Galaxy A24 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1762
        put(m, "SM-A245N", "Galaxy A24 South Korea", "Galaxy A24 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1763
        put(m, "SM-A256E", "Galaxy A25 5G Global", "Galaxy A25 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1764
        put(m, "SM-A256B", "Galaxy A25 5G EU", "Galaxy A25 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1765
        put(m, "SM-A256U", "Galaxy A25 5G US Carrier", "Galaxy A25 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1766
        put(m, "SM-A256U1", "Galaxy A25 5G US Unlocked", "Galaxy A25 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1767
        put(m, "SM-S256VL", "Galaxy A25 5G TracFone", "Galaxy A25 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1768
        put(m, "SM-A2560", "Galaxy A25 5G HK", "Galaxy A25 5G HK", "Samsung", "device_list_full_import"); // Device_List:L1769
        put(m, "SM-A256N", "Galaxy A25 5G South Korea", "Galaxy A25 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1770
        put(m, "SM-A253Q", "Galaxy A25 5G Japan (SIM Free)", "Galaxy A25 5G Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1771
        put(m, "SM-A253Z", "Galaxy A25 5G Japan (SoftBank)", "Galaxy A25 5G Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1772
        put(m, "SCG33", "Galaxy A25 5G Japan (au)", "Galaxy A25 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1773
        put(m, "SC-53F", "Galaxy A25 5G Japan (NTT Docomo)", "Galaxy A25 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1774
        put(m, "SM-A266B", "Galaxy A26 5G Global", "Galaxy A26 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1775
        put(m, "SM-A266U", "Galaxy A26 5G US Carrier", "Galaxy A26 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1776
        put(m, "SM-A266U1", "Galaxy A26 5G US Unlocked", "Galaxy A26 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1777
        put(m, "SM-S266V", "Galaxy A26 5G TracFone", "Galaxy A26 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1778
        put(m, "SM-A266M", "Galaxy A26 5G Latin America", "Galaxy A26 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1779
        put(m, "SM-A276B", "Galaxy A27 5G Global", "Galaxy A27 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1780
        put(m, "SM-A276U", "Galaxy A27 5G US Carrier", "Galaxy A27 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1781
        put(m, "SM-A276U1", "Galaxy A27 5G US Unlocked", "Galaxy A27 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1782
        put(m, "SM-S276V", "Galaxy A27 5G TracFone", "Galaxy A27 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1783
        put(m, "SM-A2760", "Galaxy A27 5G HK", "Galaxy A27 5G HK", "Samsung", "device_list_full_import"); // Device_List:L1784
        put(m, "SM-A305F", "Galaxy A30 Global", "Galaxy A30 Global", "Samsung", "device_list_full_import"); // Device_List:L1785
        put(m, "SM-A305FN", "Galaxy A30 EU", "Galaxy A30 EU", "Samsung", "device_list_full_import"); // Device_List:L1786
        put(m, "SM-A305G", "Galaxy A30 Latin America", "Galaxy A30 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1787
        put(m, "SM-A305GN", "Galaxy A30 Southeast Asia", "Galaxy A30 Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1788
        put(m, "SM-A305GT", "Galaxy A30 Brazil", "Galaxy A30 Brazil", "Samsung", "device_list_full_import"); // Device_List:L1789
        put(m, "SM-A305N", "Galaxy A30 South Korea", "Galaxy A30 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1790
        put(m, "SM-A305YN", "Galaxy A30 Australia & New Zealand", "Galaxy A30 Australia & New Zealand", "Samsung", "device_list_full_import"); // Device_List:L1791
        put(m, "SCV43", "Galaxy A30 Japan (au)", "Galaxy A30 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1792
        put(m, "SM-A307FN", "Galaxy A30s Global", "Galaxy A30s Global", "Samsung", "device_list_full_import"); // Device_List:L1793
        put(m, "SM-A307G", "Galaxy A30s Latin America", "Galaxy A30s Latin America", "Samsung", "device_list_full_import"); // Device_List:L1794
        put(m, "SM-A307GN", "Galaxy A30s Southeast Asia", "Galaxy A30s Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1795
        put(m, "SM-A307GT", "Galaxy A30s Brazil", "Galaxy A30s Brazil", "Samsung", "device_list_full_import"); // Device_List:L1796
        put(m, "SM-A315G", "Galaxy A31 Global", "Galaxy A31 Global", "Samsung", "device_list_full_import"); // Device_List:L1797
        put(m, "SM-A315N", "Galaxy A31 South Korea", "Galaxy A31 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1798
        put(m, "SM-A325F", "Galaxy A32 Global", "Galaxy A32 Global", "Samsung", "device_list_full_import"); // Device_List:L1799
        put(m, "SM-A325M", "Galaxy A32 Latin America", "Galaxy A32 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1800
        put(m, "SM-A325N", "Galaxy A32 South Korea", "Galaxy A32 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1801
    }

    private static void fill10(Map<String, Entry> m) {
        put(m, "SM-A326BR", "Galaxy A32 5G Global", "Galaxy A32 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1802
        put(m, "SM-A326U", "Galaxy A32 5G US Carrier", "Galaxy A32 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1803
        put(m, "SM-A326U1", "Galaxy A32 5G US Unlocked", "Galaxy A32 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1804
        put(m, "SM-S326DL", "Galaxy A32 5G TracFone", "Galaxy A32 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1805
        put(m, "SM-A326W", "Galaxy A32 5G Canada", "Galaxy A32 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1806
        put(m, "SCG08", "Galaxy A32 5G Japan (au)", "Galaxy A32 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1807
        put(m, "SM-A336E", "Galaxy A33 5G Global", "Galaxy A33 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1808
        put(m, "SM-A336B", "Galaxy A33 5G EU", "Galaxy A33 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1809
        put(m, "SM-A336M", "Galaxy A33 5G Latin America", "Galaxy A33 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1810
        put(m, "SM-A3360", "Galaxy A33 5G HK", "Galaxy A33 5G HK", "Samsung", "device_list_full_import"); // Device_List:L1811
        put(m, "SM-A336N", "Galaxy A33 5G South Korea", "Galaxy A33 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1812
        put(m, "SM-A346E", "Galaxy A34 5G Global", "Galaxy A34 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1813
        put(m, "SM-A346B", "Galaxy A34 5G EU", "Galaxy A34 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1814
        put(m, "SM-A346M", "Galaxy A34 5G Latin America", "Galaxy A34 5G Latin America", "Samsung", "device_list_full_import"); // Device_List:L1815
        put(m, "SM-A3460", "Galaxy A34 5G HK & TW", "Galaxy A34 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1816
        put(m, "SM-A346N", "Galaxy A34 5G South Korea", "Galaxy A34 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1817
        put(m, "SM-A356E", "Galaxy A35 5G Global", "Galaxy A35 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1818
        put(m, "SM-A356B", "Galaxy A35 5G EU", "Galaxy A35 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1819
        put(m, "SM-A356U", "Galaxy A35 5G US Carrier", "Galaxy A35 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1820
        put(m, "SM-A356U1", "Galaxy A35 5G US Unlocked", "Galaxy A35 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1821
        put(m, "SM-S356V", "Galaxy A35 5G TracFone", "Galaxy A35 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1822
        put(m, "SM-A356W", "Galaxy A35 5G Canada", "Galaxy A35 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1823
        put(m, "SM-A3560", "Galaxy A35 5G HK & TW", "Galaxy A35 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1824
        put(m, "SM-A356N", "Galaxy A35 5G South Korea", "Galaxy A35 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1825
        put(m, "SM-A366E", "Galaxy A36 5G Global", "Galaxy A36 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1826
        put(m, "SM-A366B", "Galaxy A36 5G EU", "Galaxy A36 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1827
        put(m, "SM-A366U", "Galaxy A36 5G US Carrier", "Galaxy A36 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1828
        put(m, "SM-A366U1", "Galaxy A36 5G US Unlocked", "Galaxy A36 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1829
        put(m, "SM-S366V", "Galaxy A36 5G TracFone", "Galaxy A36 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1830
        put(m, "SM-A366W", "Galaxy A36 5G Canada", "Galaxy A36 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1831
        put(m, "SM-A3660", "Galaxy A36 5G HK & TW", "Galaxy A36 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1832
        put(m, "SM-A366N", "Galaxy A36 5G South Korea", "Galaxy A36 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1833
        put(m, "SM-A376E", "Galaxy A37 5G Global", "Galaxy A37 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1834
        put(m, "SM-A376B", "Galaxy A37 5G EU", "Galaxy A37 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1835
        put(m, "SM-A376U", "Galaxy A37 5G US Carrier", "Galaxy A37 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1836
        put(m, "SM-A376U1", "Galaxy A37 5G US Unlocked", "Galaxy A37 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1837
        put(m, "SM-S376V", "Galaxy A37 5G TracFone", "Galaxy A37 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1838
        put(m, "SM-A376W", "Galaxy A37 5G Canada", "Galaxy A37 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1839
        put(m, "SM-A3760", "Galaxy A37 5G HK & TW", "Galaxy A37 5G HK & TW", "Samsung", "device_list_full_import"); // Device_List:L1840
        put(m, "SM-A405FN", "Galaxy A40 Global", "Galaxy A40 Global", "Samsung", "device_list_full_import"); // Device_List:L1841
        put(m, "SM-A405FM", "Galaxy A40 Russia", "Galaxy A40 Russia", "Samsung", "device_list_full_import"); // Device_List:L1842
        put(m, "SM-A405S", "Galaxy A40 South Korea (SK Telecom)", "Galaxy A40 South Korea (SK Telecom)", "Samsung", "device_list_full_import"); // Device_List:L1843
        put(m, "SM-A3051", "Galaxy A40s TW", "Galaxy A40s TW", "Samsung", "device_list_full_import"); // Device_List:L1844
        put(m, "SM-A415F", "Galaxy A41 Global", "Galaxy A41 Global", "Samsung", "device_list_full_import"); // Device_List:L1845
        put(m, "SCV48", "Galaxy A41 Japan (au)", "Galaxy A41 Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1846
        put(m, "SC-41A", "Galaxy A41 Japan (NTT Docomo)", "Galaxy A41 Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1847
        put(m, "SM-A426B", "Galaxy A42 5G Global", "Galaxy A42 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1848
        put(m, "SM-A4260", "Galaxy A42 5G HK", "Galaxy A42 5G HK", "Samsung", "device_list_full_import"); // Device_List:L1849
        put(m, "SM-A426N", "Galaxy A42 5G South Korea", "Galaxy A42 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1850
        put(m, "SM-A426U", "Galaxy A42 5G US Carrier", "Galaxy A42 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1851
        put(m, "SM-A426U1", "Galaxy A42 5G US Unlocked", "Galaxy A42 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1852
        put(m, "SM-S426DL", "Galaxy A42 5G TracFone", "Galaxy A42 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1853
        put(m, "SM-A505F", "Galaxy A50 Global", "Galaxy A50 Global", "Samsung", "device_list_full_import"); // Device_List:L1854
        put(m, "SM-A505FN", "Galaxy A50 EU", "Galaxy A50 EU", "Samsung", "device_list_full_import"); // Device_List:L1855
        put(m, "SM-A505FM", "Galaxy A50 Russia", "Galaxy A50 Russia", "Samsung", "device_list_full_import"); // Device_List:L1856
        put(m, "SM-A505G", "Galaxy A50 Latin America", "Galaxy A50 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1857
        put(m, "SM-A505GN", "Galaxy A50 Southeast Asia", "Galaxy A50 Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1858
        put(m, "SM-A505GT", "Galaxy A50 Brazil", "Galaxy A50 Brazil", "Samsung", "device_list_full_import"); // Device_List:L1859
        put(m, "SM-A505U", "Galaxy A50 US Carrier", "Galaxy A50 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1860
        put(m, "SM-A505U1", "Galaxy A50 US Unlocked", "Galaxy A50 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1861
        put(m, "SM-S506DL", "Galaxy A50 TracFone", "Galaxy A50 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1862
        put(m, "SM-A505W", "Galaxy A50 Canada", "Galaxy A50 Canada", "Samsung", "device_list_full_import"); // Device_List:L1863
        put(m, "SM-A505N", "Galaxy A50 South Korea", "Galaxy A50 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1864
        put(m, "SM-A505YN", "Galaxy A50 Australia & New Zealand", "Galaxy A50 Australia & New Zealand", "Samsung", "device_list_full_import"); // Device_List:L1865
        put(m, "SM-A507FN", "Galaxy A50s Global", "Galaxy A50s Global", "Samsung", "device_list_full_import"); // Device_List:L1866
        put(m, "SM-A515X", "Galaxy A51 Global", "Galaxy A51 Global", "Samsung", "device_list_full_import"); // Device_List:L1867
        put(m, "SM-A515U", "Galaxy A51 US Carrier", "Galaxy A51 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1868
        put(m, "SM-A515U1", "Galaxy A51 US Unlocked", "Galaxy A51 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1869
        put(m, "SM-S515DL", "Galaxy A51 TracFone", "Galaxy A51 TracFone", "Samsung", "device_list_full_import"); // Device_List:L1870
        put(m, "SM-A515W", "Galaxy A51 Canada", "Galaxy A51 Canada", "Samsung", "device_list_full_import"); // Device_List:L1871
        put(m, "SM-A516B", "Galaxy A51 5G Global", "Galaxy A51 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1872
        put(m, "SM-A516U", "Galaxy A51 5G US Carrier", "Galaxy A51 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1873
        put(m, "SM-A516U1", "Galaxy A51 5G US Unlocked", "Galaxy A51 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1874
        put(m, "SM-A516N", "Galaxy A51 5G South Korea", "Galaxy A51 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1875
        put(m, "SM-A516V", "Galaxy A51 5G UW Verizon", "Galaxy A51 5G UW Verizon", "Samsung", "device_list_full_import"); // Device_List:L1876
        put(m, "SM-A525F", "Galaxy A52 Global", "Galaxy A52 Global", "Samsung", "device_list_full_import"); // Device_List:L1877
        put(m, "SM-A525M", "Galaxy A52 Latin America", "Galaxy A52 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1878
        put(m, "SM-A526B", "Galaxy A52 5G Global", "Galaxy A52 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1879
        put(m, "SM-A526U", "Galaxy A52 5G US Carrier", "Galaxy A52 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1880
        put(m, "SM-A526U1", "Galaxy A52 5G US Unlocked", "Galaxy A52 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1881
        put(m, "SM-A526W", "Galaxy A52 5G Canada", "Galaxy A52 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1882
        put(m, "SM-A526N", "Galaxy A52 5G South Korea", "Galaxy A52 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1883
        put(m, "SC-53B", "Galaxy A52 5G Japan (NTT Docomo)", "Galaxy A52 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1884
        put(m, "SM-A528B", "Galaxy A52s 5G Global", "Galaxy A52s 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1885
        put(m, "SM-A528N", "Galaxy A52s 5G South Korea", "Galaxy A52s 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1886
        put(m, "SM-A536E", "Galaxy A53 5G Global", "Galaxy A53 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1887
        put(m, "SM-A536B", "Galaxy A53 5G EU", "Galaxy A53 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1888
        put(m, "SM-A536U", "Galaxy A53 5G US Carrier", "Galaxy A53 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1889
        put(m, "SM-A536U1", "Galaxy A53 5G US Unlocked", "Galaxy A53 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1890
        put(m, "SM-A536V", "Galaxy A53 5G UW Verizon", "Galaxy A53 5G UW Verizon", "Samsung", "device_list_full_import"); // Device_List:L1891
        put(m, "SM-S536DL", "Galaxy A53 5G TracFone", "Galaxy A53 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1892
        put(m, "SM-A536W", "Galaxy A53 5G Canada", "Galaxy A53 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1893
        put(m, "SM-A536N", "Galaxy A53 5G South Korea", "Galaxy A53 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1894
        put(m, "SCG15", "Galaxy A53 5G Japan (au)", "Galaxy A53 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1895
        put(m, "SC-53C", "Galaxy A53 5G Japan (NTT Docomo)", "Galaxy A53 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1896
        put(m, "SM-A546E", "Galaxy A54 5G Global", "Galaxy A54 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1897
        put(m, "SM-A546B", "Galaxy A54 5G EU", "Galaxy A54 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1898
        put(m, "SM-A546U", "Galaxy A54 5G US Carrier", "Galaxy A54 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1899
        put(m, "SM-A546U1", "Galaxy A54 5G US Unlocked", "Galaxy A54 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1900
        put(m, "SM-A546V", "Galaxy A54 5G Verizon", "Galaxy A54 5G Verizon", "Samsung", "device_list_full_import"); // Device_List:L1901
        put(m, "SM-S546VL", "Galaxy A54 5G TracFone", "Galaxy A54 5G TracFone", "Samsung", "device_list_full_import"); // Device_List:L1902
        put(m, "SM-A546W", "Galaxy A54 5G Canada", "Galaxy A54 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1903
        put(m, "SCG21", "Galaxy A54 5G Japan (au)", "Galaxy A54 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1904
        put(m, "SC-53D", "Galaxy A54 5G Japan (NTT Docomo)", "Galaxy A54 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1905
        put(m, "SM-A546S", "Galaxy Quantum4 South Korea", "Galaxy Quantum4 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1906
        put(m, "SM-A556E", "Galaxy A55 5G Global", "Galaxy A55 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1907
        put(m, "SM-A556B", "Galaxy A55 5G EU", "Galaxy A55 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1908
        put(m, "SCG27", "Galaxy A55 5G Japan (au)", "Galaxy A55 5G Japan (au)", "Samsung", "device_list_full_import"); // Device_List:L1909
        put(m, "SC-53E", "Galaxy A55 5G Japan (NTT Docomo)", "Galaxy A55 5G Japan (NTT Docomo)", "Samsung", "device_list_full_import"); // Device_List:L1910
        put(m, "SM-A556S", "Galaxy Quantum5 South Korea", "Galaxy Quantum5 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1911
        put(m, "SM-A566E", "Galaxy A56 5G Global", "Galaxy A56 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1912
        put(m, "SM-A566B", "Galaxy A56 5G EU", "Galaxy A56 5G EU", "Samsung", "device_list_full_import"); // Device_List:L1913
        put(m, "SM-A566U1", "Galaxy A56 5G US Unlocked", "Galaxy A56 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1914
        put(m, "SM-A566S", "Galaxy Quantum6 South Korea", "Galaxy Quantum6 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1915
        put(m, "SM-A576B", "Galaxy A57 5G Global", "Galaxy A57 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1916
        put(m, "SM-A576U1", "Galaxy A57 5G US Unlocked", "Galaxy A57 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1917
        put(m, "SM-A576W", "Galaxy A57 5G Canada", "Galaxy A57 5G Canada", "Samsung", "device_list_full_import"); // Device_List:L1918
        put(m, "SM-A576Q", "Galaxy A57 5G Japan (SIM Free)", "Galaxy A57 5G Japan (SIM Free)", "Samsung", "device_list_full_import"); // Device_List:L1919
        put(m, "SM-A576Z", "Galaxy A57 5G Japan (SoftBank)", "Galaxy A57 5G Japan (SoftBank)", "Samsung", "device_list_full_import"); // Device_List:L1920
        put(m, "SM-A606F", "Galaxy A60 Global", "Galaxy A60 Global", "Samsung", "device_list_full_import"); // Device_List:L1921
        put(m, "SM-A606Y", "Galaxy A60 TW", "Galaxy A60 TW", "Samsung", "device_list_full_import"); // Device_List:L1922
        put(m, "SM-A705FN", "Galaxy A70 Global", "Galaxy A70 Global", "Samsung", "device_list_full_import"); // Device_List:L1923
        put(m, "SM-A705GM", "Galaxy A70 India", "Galaxy A70 India", "Samsung", "device_list_full_import"); // Device_List:L1924
        put(m, "SM-A705MN", "Galaxy A70 Latin America", "Galaxy A70 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1925
        put(m, "SM-A705U", "Galaxy A70 US Carrier", "Galaxy A70 US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1926
        put(m, "SM-A705U1", "Galaxy A70 US Unlocked", "Galaxy A70 US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1927
        put(m, "SM-A705W", "Galaxy A70 Canada", "Galaxy A70 Canada", "Samsung", "device_list_full_import"); // Device_List:L1928
        put(m, "SM-A705YN", "Galaxy A70 Australia & New Zealand", "Galaxy A70 Australia & New Zealand", "Samsung", "device_list_full_import"); // Device_List:L1929
        put(m, "SM-A707F", "Galaxy A70s Global", "Galaxy A70s Global", "Samsung", "device_list_full_import"); // Device_List:L1930
        put(m, "SM-A715X", "Galaxy A71 Global", "Galaxy A71 Global", "Samsung", "device_list_full_import"); // Device_List:L1931
        put(m, "SM-A715W", "Galaxy A71 Canada", "Galaxy A71 Canada", "Samsung", "device_list_full_import"); // Device_List:L1932
        put(m, "SM-A716B", "Galaxy A71 5G Global", "Galaxy A71 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1933
        put(m, "SM-A716U", "Galaxy A71 5G US Carrier", "Galaxy A71 5G US Carrier", "Samsung", "device_list_full_import"); // Device_List:L1934
        put(m, "SM-A716U1", "Galaxy A71 5G US Unlocked", "Galaxy A71 5G US Unlocked", "Samsung", "device_list_full_import"); // Device_List:L1935
        put(m, "SM-A716V", "Galaxy A71 5G UW Verizon", "Galaxy A71 5G UW Verizon", "Samsung", "device_list_full_import"); // Device_List:L1936
        put(m, "SM-A725F", "Galaxy A72 Global", "Galaxy A72 Global", "Samsung", "device_list_full_import"); // Device_List:L1937
        put(m, "SM-A725M", "Galaxy A72 Latin America", "Galaxy A72 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1938
        put(m, "SM-A736B", "Galaxy A73 5G Global", "Galaxy A73 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1939
        put(m, "SM-A805F", "Galaxy A80 Global", "Galaxy A80 Global", "Samsung", "device_list_full_import"); // Device_List:L1940
        put(m, "SM-A805N", "Galaxy A80 South Korea", "Galaxy A80 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1941
        put(m, "SM-A908B", "Galaxy A90 5G Global", "Galaxy A90 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1942
        put(m, "SM-A908N", "Galaxy A90 5G South Korea", "Galaxy A90 5G South Korea", "Samsung", "device_list_full_import"); // Device_List:L1943
        put(m, "SM-A826S", "Galaxy Quantom2 South Korea", "Galaxy Quantom2 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1944
        put(m, "SM-M015G", "Galaxy M01", "Galaxy M01", "Samsung", "device_list_full_import"); // Device_List:L1945
        put(m, "SM-M013F", "Galaxy M01 Core", "Galaxy M01 Core", "Samsung", "device_list_full_import"); // Device_List:L1946
        put(m, "SM-M022F", "Galaxy M02 India", "Galaxy M02 India", "Samsung", "device_list_full_import"); // Device_List:L1947
        put(m, "SM-M022G", "Galaxy M02 India (2GB RAM)", "Galaxy M02 India (2GB RAM)", "Samsung", "device_list_full_import"); // Device_List:L1948
        put(m, "SM-M022M", "Galaxy M02 Latin America", "Galaxy M02 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1949
        put(m, "SM-M025F", "Galaxy M02s", "Galaxy M02s", "Samsung", "device_list_full_import"); // Device_List:L1950
        put(m, "SM-M045F", "Galaxy M04", "Galaxy M04", "Samsung", "device_list_full_import"); // Device_List:L1951
        put(m, "SM-M055F", "Galaxy M05", "Galaxy M05", "Samsung", "device_list_full_import"); // Device_List:L1952
        put(m, "SM-M066B", "Galaxy M06 5G", "Galaxy M06 5G", "Samsung", "device_list_full_import"); // Device_List:L1953
        put(m, "SM-M075F", "Galaxy M07", "Galaxy M07", "Samsung", "device_list_full_import"); // Device_List:L1954
        put(m, "SM-M105G", "Galaxy M10 Global", "Galaxy M10 Global", "Samsung", "device_list_full_import"); // Device_List:L1955
        put(m, "SM-M105F", "Galaxy M10 India", "Galaxy M10 India", "Samsung", "device_list_full_import"); // Device_List:L1956
        put(m, "SM-M105M", "Galaxy M10 Latin America", "Galaxy M10 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1957
        put(m, "SM-M105Y", "Galaxy M10 Philippines", "Galaxy M10 Philippines", "Samsung", "device_list_full_import"); // Device_List:L1958
        put(m, "SM-M107F", "Galaxy M10s", "Galaxy M10s", "Samsung", "device_list_full_import"); // Device_List:L1959
        put(m, "SM-M115F", "Galaxy M11 India", "Galaxy M11 India", "Samsung", "device_list_full_import"); // Device_List:L1960
        put(m, "SM-M115M", "Galaxy M11 Latin America", "Galaxy M11 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1961
        put(m, "SM-M127G", "Galaxy M12 India", "Galaxy M12 India", "Samsung", "device_list_full_import"); // Device_List:L1962
        put(m, "SM-M127F", "Galaxy M12 Latin America", "Galaxy M12 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1963
        put(m, "SM-M127N", "Galaxy M12 South Korea", "Galaxy M12 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1964
        put(m, "SM-M135F", "Galaxy M13 EU", "Galaxy M13 EU", "Samsung", "device_list_full_import"); // Device_List:L1965
        put(m, "SM-M135FU", "Galaxy M13 India", "Galaxy M13 India", "Samsung", "device_list_full_import"); // Device_List:L1966
        put(m, "SM-M135M", "Galaxy M13 Latin America", "Galaxy M13 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1967
        put(m, "SM-M136B", "Galaxy M13 5G", "Galaxy M13 5G", "Samsung", "device_list_full_import"); // Device_List:L1968
        put(m, "SM-M145F", "Galaxy M14", "Galaxy M14", "Samsung", "device_list_full_import"); // Device_List:L1969
        put(m, "SM-M146B", "Galaxy M14 5G", "Galaxy M14 5G", "Samsung", "device_list_full_import"); // Device_List:L1970
        put(m, "SM-M156B", "Galaxy M15 5G", "Galaxy M15 5G", "Samsung", "device_list_full_import"); // Device_List:L1971
        put(m, "SM-M166P", "Galaxy M16 5G", "Galaxy M16 5G", "Samsung", "device_list_full_import"); // Device_List:L1972
        put(m, "SM-M176B", "Galaxy M17 5G", "Galaxy M17 5G", "Samsung", "device_list_full_import"); // Device_List:L1973
        put(m, "SM-M076B", "Galaxy M17e 5G", "Galaxy M17e 5G", "Samsung", "device_list_full_import"); // Device_List:L1974
        put(m, "SM-M205N", "Galaxy M20 South Korea", "Galaxy M20 South Korea", "Samsung", "device_list_full_import"); // Device_List:L1975
        put(m, "SM-M205F", "Galaxy M20 Global", "Galaxy M20 Global", "Samsung", "device_list_full_import"); // Device_List:L1976
        put(m, "SM-M205FN", "Galaxy M20 EU", "Galaxy M20 EU", "Samsung", "device_list_full_import"); // Device_List:L1977
        put(m, "SM-M205G", "Galaxy M20 Southeast Asia", "Galaxy M20 Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1978
        put(m, "SM-M205M", "Galaxy M20 Latin America", "Galaxy M20 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1979
        put(m, "SM-M215F", "Galaxy M21", "Galaxy M21", "Samsung", "device_list_full_import"); // Device_List:L1980
        put(m, "SM-M215G", "Galaxy M21 2021 Edition", "Galaxy M21 2021 Edition", "Samsung", "device_list_full_import"); // Device_List:L1981
    }

    private static void fill11(Map<String, Entry> m) {
        put(m, "SM-M225FV", "Galaxy M22", "Galaxy M22", "Samsung", "device_list_full_import"); // Device_List:L1982
        put(m, "SM-M236B", "Galaxy M23 5G Global", "Galaxy M23 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1983
        put(m, "SM-M236Q", "Galaxy M23 5G Japan", "Galaxy M23 5G Japan", "Samsung", "device_list_full_import"); // Device_List:L1984
        put(m, "SM-M305F", "Galaxy M30 Global", "Galaxy M30 Global", "Samsung", "device_list_full_import"); // Device_List:L1985
        put(m, "SM-M305M", "Galaxy M30 Latin America", "Galaxy M30 Latin America", "Samsung", "device_list_full_import"); // Device_List:L1986
        put(m, "SM-M307F", "Galaxy M30s Southeast Asia", "Galaxy M30s Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1987
        put(m, "SM-M307FN", "Galaxy M30s Global", "Galaxy M30s Global", "Samsung", "device_list_full_import"); // Device_List:L1988
        put(m, "SM-M315F", "Galaxy M31", "Galaxy M31", "Samsung", "device_list_full_import"); // Device_List:L1989
        put(m, "SM-M317F", "Galaxy M31s", "Galaxy M31s", "Samsung", "device_list_full_import"); // Device_List:L1990
        put(m, "SM-M325F", "Galaxy M32 India", "Galaxy M32 India", "Samsung", "device_list_full_import"); // Device_List:L1991
        put(m, "SM-M325FV", "Galaxy M32 Southeast Asia", "Galaxy M32 Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1992
        put(m, "SM-M326B", "Galaxy M32 5G", "Galaxy M32 5G", "Samsung", "device_list_full_import"); // Device_List:L1993
        put(m, "SM-M336B", "Galaxy M33 5G Global", "Galaxy M33 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1994
        put(m, "SM-M336BU", "Galaxy M33 5G India", "Galaxy M33 5G India", "Samsung", "device_list_full_import"); // Device_List:L1995
        put(m, "SM-M346B", "Galaxy M34 5G India", "Galaxy M34 5G India", "Samsung", "device_list_full_import"); // Device_List:L1996
        put(m, "SM-M346B1", "Galaxy M34 5G Southeast Asia", "Galaxy M34 5G Southeast Asia", "Samsung", "device_list_full_import"); // Device_List:L1997
        put(m, "SM-M346B2", "Galaxy M34 5G Global", "Galaxy M34 5G Global", "Samsung", "device_list_full_import"); // Device_List:L1998
        put(m, "SM-M356B", "Galaxy M35 5G", "Galaxy M35 5G", "Samsung", "device_list_full_import"); // Device_List:L1999
        put(m, "SM-M366B", "Galaxy M36 5G", "Galaxy M36 5G", "Samsung", "device_list_full_import"); // Device_List:L2000
        put(m, "SM-M405F", "Galaxy M40", "Galaxy M40", "Samsung", "device_list_full_import"); // Device_List:L2001
        put(m, "SM-M426B", "Galaxy M42 5G", "Galaxy M42 5G", "Samsung", "device_list_full_import"); // Device_List:L2002
        put(m, "SM-M515F", "Galaxy M51", "Galaxy M51", "Samsung", "device_list_full_import"); // Device_List:L2003
        put(m, "SM-M526BR", "Galaxy M52 5G", "Galaxy M52 5G", "Samsung", "device_list_full_import"); // Device_List:L2004
        put(m, "SM-M536B", "Galaxy M53 5G", "Galaxy M53 5G", "Samsung", "device_list_full_import"); // Device_List:L2005
        put(m, "SM-M536S", "Galaxy Quantum3 South Korea", "Galaxy Quantum3 South Korea", "Samsung", "device_list_full_import"); // Device_List:L2006
        put(m, "SM-M546B", "Galaxy M54 5G", "Galaxy M54 5G", "Samsung", "device_list_full_import"); // Device_List:L2007
        put(m, "SM-M556B", "Galaxy M55 5G India", "Galaxy M55 5G India", "Samsung", "device_list_full_import"); // Device_List:L2008
        put(m, "SM-M556E", "Galaxy M55 5G Global", "Galaxy M55 5G Global", "Samsung", "device_list_full_import"); // Device_List:L2009
        put(m, "SM-M558B", "Galaxy M55s 5G", "Galaxy M55s 5G", "Samsung", "device_list_full_import"); // Device_List:L2010
        put(m, "SM-M566B", "Galaxy M56 5G", "Galaxy M56 5G", "Samsung", "device_list_full_import"); // Device_List:L2011
        put(m, "SM-M625F", "Galaxy M62", "Galaxy M62", "Samsung", "device_list_full_import"); // Device_List:L2012
        put(m, "SM-E025F", "Galaxy F02s", "Galaxy F02s", "Samsung", "device_list_full_import"); // Device_List:L2013
        put(m, "SM-E045F", "Galaxy F04", "Galaxy F04", "Samsung", "device_list_full_import"); // Device_List:L2014
        put(m, "SM-E055F", "Galaxy F05", "Galaxy F05", "Samsung", "device_list_full_import"); // Device_List:L2015
        put(m, "SM-E066B", "Galaxy F06 5G", "Galaxy F06 5G", "Samsung", "device_list_full_import"); // Device_List:L2016
        put(m, "SM-E075F", "Galaxy F07", "Galaxy F07", "Samsung", "device_list_full_import"); // Device_List:L2017
        put(m, "SM-F127G", "Galaxy F12", "Galaxy F12", "Samsung", "device_list_full_import"); // Device_List:L2018
        put(m, "SM-E135F", "Galaxy F13", "Galaxy F13", "Samsung", "device_list_full_import"); // Device_List:L2019
        put(m, "SM-E145F", "Galaxy F14", "Galaxy F14", "Samsung", "device_list_full_import"); // Device_List:L2020
        put(m, "SM-E146B", "Galaxy F14 5G", "Galaxy F14 5G", "Samsung", "device_list_full_import"); // Device_List:L2021
        put(m, "SM-E156B", "Galaxy F15 5G", "Galaxy F15 5G", "Samsung", "device_list_full_import"); // Device_List:L2022
        put(m, "SM-E166P", "Galaxy F16 5G", "Galaxy F16 5G", "Samsung", "device_list_full_import"); // Device_List:L2023
        put(m, "SM-E176B", "Galaxy F17 5G", "Galaxy F17 5G", "Samsung", "device_list_full_import"); // Device_List:L2024
        put(m, "SM-E225F", "Galaxy F22", "Galaxy F22", "Samsung", "device_list_full_import"); // Device_List:L2025
        put(m, "SM-E236B", "Galaxy F23 5G", "Galaxy F23 5G", "Samsung", "device_list_full_import"); // Device_List:L2026
        put(m, "SM-E346B", "Galaxy F34 5G", "Galaxy F34 5G", "Samsung", "device_list_full_import"); // Device_List:L2027
        put(m, "SM-E366B", "Galaxy F36 5G", "Galaxy F36 5G", "Samsung", "device_list_full_import"); // Device_List:L2028
        put(m, "SM-F415F", "Galaxy F41", "Galaxy F41", "Samsung", "device_list_full_import"); // Device_List:L2029
        put(m, "SM-E426B", "Galaxy F42 5G", "Galaxy F42 5G", "Samsung", "device_list_full_import"); // Device_List:L2030
        put(m, "SM-E546B", "Galaxy F54 5G", "Galaxy F54 5G", "Samsung", "device_list_full_import"); // Device_List:L2031
        put(m, "SM-E556B", "Galaxy F55 5G", "Galaxy F55 5G", "Samsung", "device_list_full_import"); // Device_List:L2032
        put(m, "SM-E566B", "Galaxy F56 5G", "Galaxy F56 5G", "Samsung", "device_list_full_import"); // Device_List:L2033
        put(m, "SM-E625F", "Galaxy F62", "Galaxy F62", "Samsung", "device_list_full_import"); // Device_List:L2034
        put(m, "SM-E076B", "Galaxy F70e 5G", "Galaxy F70e 5G", "Samsung", "device_list_full_import"); // Device_List:L2035
        put(m, "ASUS_Z01QD", "ROG 遊戲手機", "ROG 遊戲手機", "ASUS", "device_list_full_import"); // Device_List:L2036
        put(m, "ASUS_I001DB", "ROG 遊戲手機 2", "ROG 遊戲手機 2", "ASUS", "device_list_full_import"); // Device_List:L2037
        put(m, "ASUS_I003DD", "ROG 遊戲手機 3", "ROG 遊戲手機 3", "ASUS", "device_list_full_import"); // Device_List:L2038
        put(m, "ASUS_I005DA", "騰訊 ROG 遊戲手機 5", "騰訊 ROG 遊戲手機 5", "ASUS", "device_list_full_import"); // Device_List:L2039
        put(m, "ASUS_I005DB", "騰訊 ROG 遊戲手機 5 Pro", "騰訊 ROG 遊戲手機 5 Pro", "ASUS", "device_list_full_import"); // Device_List:L2040
        put(m, "ASUS_AI2201_A", "騰訊 ROG 遊戲手機 6", "騰訊 ROG 遊戲手機 6", "ASUS", "device_list_full_import"); // Device_List:L2041
        put(m, "ASUS_AI2201_B", "騰訊 ROG 遊戲手機 6 Pro", "騰訊 ROG 遊戲手機 6 Pro", "ASUS", "device_list_full_import"); // Device_List:L2042
        put(m, "ASUS_AI2203_A", "騰訊 ROG 遊戲手機 6 天璣版", "騰訊 ROG 遊戲手機 6 天璣版", "ASUS", "device_list_full_import"); // Device_List:L2043
        put(m, "ASUS_AI2203_B", "騰訊 ROG 遊戲手機 6 天璣至尊版", "騰訊 ROG 遊戲手機 6 天璣至尊版", "ASUS", "device_list_full_import"); // Device_List:L2044
        put(m, "ASUS_AI2205_A", "騰訊 ROG 遊戲手機 7", "騰訊 ROG 遊戲手機 7", "ASUS", "device_list_full_import"); // Device_List:L2045
        put(m, "ASUS_AI2205_B", "騰訊 ROG 遊戲手機 7 Pro", "騰訊 ROG 遊戲手機 7 Pro", "ASUS", "device_list_full_import"); // Device_List:L2046
        put(m, "ASUS_AI2401_A", "ROG 遊戲手機 8 / ROG 遊戲手機 8 Pro", "ROG 遊戲手機 8 / ROG 遊戲手機 8 Pro", "ASUS", "device_list_full_import"); // Device_List:L2047
        put(m, "ASUSAI2501A", "ROG 遊戲手機 9 / ROG 遊戲手機 9 Pro", "ROG 遊戲手機 9 / ROG 遊戲手機 9 Pro", "ASUS", "device_list_full_import"); // Device_List:L2048
        put(m, "ASUS_I007D", "Smartphone for Snapdragon Insiders", "Smartphone for Snapdragon Insiders", "ASUS", "device_list_full_import"); // Device_List:L2049
        put(m, "SKR-A0", "黑鯊遊戲手機 全網通版", "黑鯊遊戲手機 全網通版", "", "device_list_full_import"); // Device_List:L2050
        put(m, "SKR-H0", "黑鯊遊戲手機 國際版", "黑鯊遊戲手機 國際版", "", "device_list_full_import"); // Device_List:L2051
        put(m, "AWM-A0", "黑鯊遊戲手機 Helo", "黑鯊遊戲手機 Helo", "", "device_list_full_import"); // Device_List:L2052
        put(m, "SKW-A0", "黑鯊遊戲手機 2 全網通版", "黑鯊遊戲手機 2 全網通版", "", "device_list_full_import"); // Device_List:L2053
        put(m, "SKW-H0", "黑鯊遊戲手機 2 國際版", "黑鯊遊戲手機 2 國際版", "", "device_list_full_import"); // Device_List:L2054
        put(m, "DLT-A0", "黑鯊遊戲手機 2 Pro 全網通版", "黑鯊遊戲手機 2 Pro 全網通版", "", "device_list_full_import"); // Device_List:L2055
        put(m, "DLT-H0", "黑鯊遊戲手機 2 Pro 國際版", "黑鯊遊戲手機 2 Pro 國際版", "", "device_list_full_import"); // Device_List:L2056
        put(m, "SHARK KLE-A0", "騰訊黑鯊遊戲手機 3 全網通版", "騰訊黑鯊遊戲手機 3 全網通版", "", "device_list_full_import"); // Device_List:L2057
        put(m, "SHARK KLE-H0", "黑鯊遊戲手機 3 國際版", "黑鯊遊戲手機 3 國際版", "", "device_list_full_import"); // Device_List:L2058
        put(m, "SHARK MBU-A0", "騰訊黑鯊遊戲手機 3 Pro 全網通版", "騰訊黑鯊遊戲手機 3 Pro 全網通版", "", "device_list_full_import"); // Device_List:L2059
        put(m, "SHARK MBU-H0", "黑鯊遊戲手機 3 Pro 國際版", "黑鯊遊戲手機 3 Pro 國際版", "", "device_list_full_import"); // Device_List:L2060
        put(m, "SHARK PRS-A0", "黑鯊 4 全網通版", "黑鯊 4 全網通版", "", "device_list_full_import"); // Device_List:L2061
        put(m, "SHARK PRS-H0", "黑鯊 4 國際版", "黑鯊 4 國際版", "", "device_list_full_import"); // Device_List:L2062
        put(m, "SHARK KSR-A0", "黑鯊 4 Pro 全網通版", "黑鯊 4 Pro 全網通版", "", "device_list_full_import"); // Device_List:L2063
        put(m, "SHARK KSR-H0", "黑鯊 4 Pro 國際版", "黑鯊 4 Pro 國際版", "", "device_list_full_import"); // Device_List:L2064
        put(m, "SHARK PAR-A0", "黑鯊 5 全網通版 / 黑鯊 5 高能版", "黑鯊 5 全網通版 / 黑鯊 5 高能版", "", "device_list_full_import"); // Device_List:L2065
        put(m, "SHARK PAR-H0", "黑鯊 5 國際版", "黑鯊 5 國際版", "", "device_list_full_import"); // Device_List:L2066
        put(m, "SHARK KTUS-A0", "黑鯊 5 Pro 全網通版", "黑鯊 5 Pro 全網通版", "", "device_list_full_import"); // Device_List:L2067
        put(m, "SHARK KTUS-H0", "黑鯊 5 Pro 國際版", "黑鯊 5 Pro 國際版", "", "device_list_full_import"); // Device_List:L2068
        put(m, "G-2PW4100", "Pixel (North America)", "Pixel (North America)", "Google", "device_list_full_import"); // Device_List:L2069
        put(m, "G-2PW4200", "Pixel (Rest of the world)", "Pixel (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2070
        put(m, "G-2PW2100", "Pixel XL (North America)", "Pixel XL (North America)", "Google", "device_list_full_import"); // Device_List:L2071
        put(m, "G-2PW2200", "Pixel XL (Rest of the world)", "Pixel XL (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2072
        put(m, "G011A", "Pixel 2", "Pixel 2", "Google", "device_list_full_import"); // Device_List:L2073
        put(m, "G011C", "Pixel 2 XL", "Pixel 2 XL", "Google", "device_list_full_import"); // Device_List:L2074
        put(m, "G013A", "Pixel 3", "Pixel 3", "Google", "device_list_full_import"); // Device_List:L2075
        put(m, "G013B", "Pixel 3 (Japan)", "Pixel 3 (Japan)", "Google", "device_list_full_import"); // Device_List:L2076
        put(m, "G013C", "Pixel 3 XL", "Pixel 3 XL", "Google", "device_list_full_import"); // Device_List:L2077
        put(m, "G013D", "Pixel 3 XL (Japan)", "Pixel 3 XL (Japan)", "Google", "device_list_full_import"); // Device_List:L2078
        put(m, "G020E", "Pixel 3a (Verizon)", "Pixel 3a (Verizon)", "Google", "device_list_full_import"); // Device_List:L2079
        put(m, "G020F", "Pixel 3a (UK, Europe, and APAC)", "Pixel 3a (UK, Europe, and APAC)", "Google", "device_list_full_import"); // Device_List:L2080
        put(m, "G020G", "Pixel 3a (North America)", "Pixel 3a (North America)", "Google", "device_list_full_import"); // Device_List:L2081
        put(m, "G020H", "Pixel 3a (Japan)", "Pixel 3a (Japan)", "Google", "device_list_full_import"); // Device_List:L2082
        put(m, "G020A", "Pixel 3a XL (Verizon)", "Pixel 3a XL (Verizon)", "Google", "device_list_full_import"); // Device_List:L2083
        put(m, "G020B", "Pixel 3a XL (UK, Europe, and APAC)", "Pixel 3a XL (UK, Europe, and APAC)", "Google", "device_list_full_import"); // Device_List:L2084
        put(m, "G020C", "Pixel 3a XL (North America)", "Pixel 3a XL (North America)", "Google", "device_list_full_import"); // Device_List:L2085
        put(m, "G020D", "Pixel 3a XL (Japan)", "Pixel 3a XL (Japan)", "Google", "device_list_full_import"); // Device_List:L2086
        put(m, "G020I", "Pixel 4 (North America, TW)", "Pixel 4 (North America, TW)", "Google", "device_list_full_import"); // Device_List:L2087
        put(m, "G020M", "Pixel 4 (Rest of the world)", "Pixel 4 (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2088
        put(m, "G020N", "Pixel 4 (Japan)", "Pixel 4 (Japan)", "Google", "device_list_full_import"); // Device_List:L2089
        put(m, "G020J", "Pixel 4 XL (North America, TW)", "Pixel 4 XL (North America, TW)", "Google", "device_list_full_import"); // Device_List:L2090
        put(m, "G020P", "Pixel 4 XL (Rest of the world)", "Pixel 4 XL (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2091
        put(m, "G020Q", "Pixel 4 XL (Japan)", "Pixel 4 XL (Japan)", "Google", "device_list_full_import"); // Device_List:L2092
        put(m, "G025J", "Pixel 4a (North America, TW)", "Pixel 4a (North America, TW)", "Google", "device_list_full_import"); // Device_List:L2093
        put(m, "G025N", "Pixel 4a (Rest of the world)", "Pixel 4a (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2094
        put(m, "G025M", "Pixel 4a (Japan)", "Pixel 4a (Japan)", "Google", "device_list_full_import"); // Device_List:L2095
        put(m, "G025E", "Pixel 4a 5G (North America, TW)", "Pixel 4a 5G (North America, TW)", "Google", "device_list_full_import"); // Device_List:L2096
        put(m, "G6QU3", "Pixel 4a 5G (Verizon)", "Pixel 4a 5G (Verizon)", "Google", "device_list_full_import"); // Device_List:L2097
        put(m, "G025I", "Pixel 4a 5G (Rest of the world)", "Pixel 4a 5G (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2098
        put(m, "G025H", "Pixel 4a 5G (Japan)", "Pixel 4a 5G (Japan)", "Google", "device_list_full_import"); // Device_List:L2099
        put(m, "GD1YQ", "Pixel 5 (US)", "Pixel 5 (US)", "Google", "device_list_full_import"); // Device_List:L2100
        put(m, "GTT9Q", "Pixel 5 (Rest of the world)", "Pixel 5 (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2101
        put(m, "G5NZ6", "Pixel 5 (Japan)", "Pixel 5 (Japan)", "Google", "device_list_full_import"); // Device_List:L2102
        put(m, "G1F8F", "Pixel 5a 5G (US)", "Pixel 5a 5G (US)", "Google", "device_list_full_import"); // Device_List:L2103
        put(m, "G4S1M", "Pixel 5a 5G (Japan)", "Pixel 5a 5G (Japan)", "Google", "device_list_full_import"); // Device_List:L2104
        put(m, "G9S9B", "Pixel 6 (US, mmWave)", "Pixel 6 (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2105
        put(m, "GB7N6", "Pixel 6 (Rest of the world)", "Pixel 6 (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2106
        put(m, "GR1YH", "Pixel 6 (Japan)", "Pixel 6 (Japan)", "Google", "device_list_full_import"); // Device_List:L2107
        put(m, "G8VOU", "Pixel 6 Pro (US, AU) (mmWave)", "Pixel 6 Pro (US, AU) (mmWave)", "Google", "device_list_full_import"); // Device_List:L2108
        put(m, "GLUOG", "Pixel 6 Pro (Rest of the world)", "Pixel 6 Pro (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2109
        put(m, "GF5KQ", "Pixel 6 Pro (Japan)", "Pixel 6 Pro (Japan)", "Google", "device_list_full_import"); // Device_List:L2110
        put(m, "GB62Z", "Pixel 6a (US, mmWave)", "Pixel 6a (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2111
        put(m, "GX7AS", "Pixel 6a (North America, TW)", "Pixel 6a (North America, TW)", "Google", "device_list_full_import"); // Device_List:L2112
        put(m, "G1AZG", "Pixel 6a (Rest of the world)", "Pixel 6a (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2113
        put(m, "GB17L", "Pixel 6a (Japan)", "Pixel 6a (Japan)", "Google", "device_list_full_import"); // Device_List:L2114
        put(m, "GQML3", "Pixel 7 (US, mmWave)", "Pixel 7 (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2115
        put(m, "GVU6C", "Pixel 7 (Rest of the world)", "Pixel 7 (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2116
        put(m, "G03Z5", "Pixel 7 (Japan)", "Pixel 7 (Japan)", "Google", "device_list_full_import"); // Device_List:L2117
        put(m, "GE2AE", "Pixel 7 Pro (US, AU) (mmWave)", "Pixel 7 Pro (US, AU) (mmWave)", "Google", "device_list_full_import"); // Device_List:L2118
        put(m, "GP4BC", "Pixel 7 Pro (Rest of the world)", "Pixel 7 Pro (Rest of the world)", "Google", "device_list_full_import"); // Device_List:L2119
        put(m, "GFE4J", "Pixel 7 Pro (Japan)", "Pixel 7 Pro (Japan)", "Google", "device_list_full_import"); // Device_List:L2120
        put(m, "G0DZQ", "Pixel 7a (mmWave)", "Pixel 7a (mmWave)", "Google", "device_list_full_import"); // Device_List:L2121
        put(m, "GWKK3", "Pixel 7a (North America, EU)", "Pixel 7a (North America, EU)", "Google", "device_list_full_import"); // Device_List:L2122
        put(m, "GHL1X", "Pixel 7a (Global)", "Pixel 7a (Global)", "Google", "device_list_full_import"); // Device_List:L2123
        put(m, "G82U8", "Pixel 7a (Japan)", "Pixel 7a (Japan)", "Google", "device_list_full_import"); // Device_List:L2124
        put(m, "GKWS6", "Pixel 8 (mmWave)", "Pixel 8 (mmWave)", "Google", "device_list_full_import"); // Device_List:L2125
        put(m, "G9BQD", "Pixel 8 (US, Sub 6GHz)", "Pixel 8 (US, Sub 6GHz)", "Google", "device_list_full_import"); // Device_List:L2126
        put(m, "GPJ41", "Pixel 8 (Global)", "Pixel 8 (Global)", "Google", "device_list_full_import"); // Device_List:L2127
        put(m, "GZPFO", "Pixel 8 (Japan)", "Pixel 8 (Japan)", "Google", "device_list_full_import"); // Device_List:L2128
        put(m, "G1MNW", "Pixel 8 Pro (mmWave)", "Pixel 8 Pro (mmWave)", "Google", "device_list_full_import"); // Device_List:L2129
        put(m, "GC3VE", "Pixel 8 Pro (Global)", "Pixel 8 Pro (Global)", "Google", "device_list_full_import"); // Device_List:L2130
        put(m, "GE9DP", "Pixel 8 Pro (Japan)", "Pixel 8 Pro (Japan)", "Google", "device_list_full_import"); // Device_List:L2131
        put(m, "G8HNN", "Pixel 8a (mmWave)", "Pixel 8a (mmWave)", "Google", "device_list_full_import"); // Device_List:L2132
        put(m, "GKV4X", "Pixel 8a (North America, Sub 6GHz)", "Pixel 8a (North America, Sub 6GHz)", "Google", "device_list_full_import"); // Device_List:L2133
        put(m, "G6GPR", "Pixel 8a (Global)", "Pixel 8a (Global)", "Google", "device_list_full_import"); // Device_List:L2134
        put(m, "G576D", "Pixel 8a (Japan)", "Pixel 8a (Japan)", "Google", "device_list_full_import"); // Device_List:L2135
        put(m, "G9FPL", "Pixel Fold (US, EU)", "Pixel Fold (US, EU)", "Google", "device_list_full_import"); // Device_List:L2136
        put(m, "G0B96", "Pixel Fold (Japan)", "Pixel Fold (Japan)", "Google", "device_list_full_import"); // Device_List:L2137
        put(m, "G2YBB", "Pixel 9 (US, mmWave)", "Pixel 9 (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2138
        put(m, "GUR25", "Pixel 9 (Global)", "Pixel 9 (Global)", "Google", "device_list_full_import"); // Device_List:L2139
        put(m, "G1B60", "Pixel 9 (Japan)", "Pixel 9 (Japan)", "Google", "device_list_full_import"); // Device_List:L2140
        put(m, "GR83Y", "Pixel 9 Pro (US, mmWave)", "Pixel 9 Pro (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2141
        put(m, "GEC77", "Pixel 9 Pro (Global)", "Pixel 9 Pro (Global)", "Google", "device_list_full_import"); // Device_List:L2142
        put(m, "GWVK6", "Pixel 9 Pro (Japan)", "Pixel 9 Pro (Japan)", "Google", "device_list_full_import"); // Device_List:L2143
        put(m, "GGX8B", "Pixel 9 Pro XL (US, mmWave)", "Pixel 9 Pro XL (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2144
        put(m, "GZC4K", "Pixel 9 Pro XL (Global)", "Pixel 9 Pro XL (Global)", "Google", "device_list_full_import"); // Device_List:L2145
        put(m, "GQ57S", "Pixel 9 Pro XL (Japan)", "Pixel 9 Pro XL (Japan)", "Google", "device_list_full_import"); // Device_List:L2146
        put(m, "GGH2X", "Pixel 9 Pro Fold (Global)", "Pixel 9 Pro Fold (Global)", "Google", "device_list_full_import"); // Device_List:L2147
        put(m, "GC15S", "Pixel 9 Pro Fold (Japan)", "Pixel 9 Pro Fold (Japan)", "Google", "device_list_full_import"); // Device_List:L2148
        put(m, "GXQ96", "Pixel 9a (US)", "Pixel 9a (US)", "Google", "device_list_full_import"); // Device_List:L2149
        put(m, "GTF7P", "Pixel 9a (Global)", "Pixel 9a (Global)", "Google", "device_list_full_import"); // Device_List:L2150
        put(m, "G3Y12", "Pixel 9a (Japan)", "Pixel 9a (Japan)", "Google", "device_list_full_import"); // Device_List:L2151
        put(m, "GLBW0", "Pixel 10 (US, mmWave)", "Pixel 10 (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2152
        put(m, "GK2MP", "Pixel 10 (Global)", "Pixel 10 (Global)", "Google", "device_list_full_import"); // Device_List:L2153
        put(m, "GL066", "Pixel 10 (Japan)", "Pixel 10 (Japan)", "Google", "device_list_full_import"); // Device_List:L2154
        put(m, "G4QUR", "Pixel 10 Pro (US, mmWave)", "Pixel 10 Pro (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2155
        put(m, "GEHN3", "Pixel 10 Pro (Global)", "Pixel 10 Pro (Global)", "Google", "device_list_full_import"); // Device_List:L2156
        put(m, "GN4F5", "Pixel 10 Pro (Japan)", "Pixel 10 Pro (Japan)", "Google", "device_list_full_import"); // Device_List:L2157
        put(m, "GUL82", "Pixel 10 Pro XL (US, mmWave)", "Pixel 10 Pro XL (US, mmWave)", "Google", "device_list_full_import"); // Device_List:L2158
        put(m, "G45RY", "Pixel 10 Pro XL (Global)", "Pixel 10 Pro XL (Global)", "Google", "device_list_full_import"); // Device_List:L2159
        put(m, "GYPW4", "Pixel 10 Pro XL (Japan)", "Pixel 10 Pro XL (Japan)", "Google", "device_list_full_import"); // Device_List:L2160
        put(m, "GU0NP", "Pixel 10 Pro Fold (Global)", "Pixel 10 Pro Fold (Global)", "Google", "device_list_full_import"); // Device_List:L2161
    }

    private static void fill12(Map<String, Entry> m) {
        put(m, "GM66V", "Pixel 10 Pro Fold (Japan)", "Pixel 10 Pro Fold (Japan)", "Google", "device_list_full_import"); // Device_List:L2162
        put(m, "GE1GQ", "Pixel 10a (US)", "Pixel 10a (US)", "Google", "device_list_full_import"); // Device_List:L2163
        put(m, "G4H7L", "Pixel 10a (Global)", "Pixel 10a (Global)", "Google", "device_list_full_import"); // Device_List:L2164
        put(m, "GV0BP", "Pixel 10a (Japan)", "Pixel 10a (Japan)", "Google", "device_list_full_import"); // Device_List:L2165
        put(m, "C1502W", "Pixel C", "Pixel C", "Google", "device_list_full_import"); // Device_List:L2166
        put(m, "GTU8P", "Pixel Tablet", "Pixel Tablet", "Google", "device_list_full_import"); // Device_List:L2167
        put(m, "GQF4C", "Pixel Watch Bluetooth & Wi-Fi", "Pixel Watch Bluetooth & Wi-Fi", "Google", "device_list_full_import"); // Device_List:L2168
        put(m, "GWT9R", "Pixel Watch LTE (US)", "Pixel Watch LTE (US)", "Google", "device_list_full_import"); // Device_List:L2169
        put(m, "GBZ4S", "Pixel Watch LTE (Global)", "Pixel Watch LTE (Global)", "Google", "device_list_full_import"); // Device_List:L2170
        put(m, "G4TSL", "Pixel Watch 2 Bluetooth & Wi-Fi", "Pixel Watch 2 Bluetooth & Wi-Fi", "Google", "device_list_full_import"); // Device_List:L2171
        put(m, "GD2WG", "Pixel Watch 2 LTE (US)", "Pixel Watch 2 LTE (US)", "Google", "device_list_full_import"); // Device_List:L2172
        put(m, "GC3G8", "Pixel Watch 2 LTE (Global)", "Pixel Watch 2 LTE (Global)", "Google", "device_list_full_import"); // Device_List:L2173
        put(m, "GG3HH", "Pixel Watch 3 Bluetooth & Wi-Fi (41mm)", "Pixel Watch 3 Bluetooth & Wi-Fi (41mm)", "Google", "device_list_full_import"); // Device_List:L2174
        put(m, "GBDU9", "Pixel Watch 3 LTE (41mm)", "Pixel Watch 3 LTE (41mm)", "Google", "device_list_full_import"); // Device_List:L2175
        put(m, "GGE4J", "Pixel Watch 3 Bluetooth & Wi-Fi (45mm)", "Pixel Watch 3 Bluetooth & Wi-Fi (45mm)", "Google", "device_list_full_import"); // Device_List:L2176
        put(m, "GRY0E", "Pixel Watch 3 LTE (45mm)", "Pixel Watch 3 LTE (45mm)", "Google", "device_list_full_import"); // Device_List:L2177
        put(m, "GHH4K", "Pixel Watch 4 Bluetooth & Wi-Fi (41mm)", "Pixel Watch 4 Bluetooth & Wi-Fi (41mm)", "Google", "device_list_full_import"); // Device_List:L2178
        put(m, "GWSQ2", "Pixel Watch 4 LTE (41mm)", "Pixel Watch 4 LTE (41mm)", "Google", "device_list_full_import"); // Device_List:L2179
        put(m, "G8AK3", "Pixel Watch 4 Bluetooth & Wi-Fi (45mm)", "Pixel Watch 4 Bluetooth & Wi-Fi (45mm)", "Google", "device_list_full_import"); // Device_List:L2180
        put(m, "G1KAW", "Pixel Watch 4 LTE (45mm)", "Pixel Watch 4 LTE (45mm)", "Google", "device_list_full_import"); // Device_List:L2181
        put(m, "Lenovo L78012", "聯想 Z5", "聯想 Z5", "OnePlus", "device_list_full_import"); // Device_List:L2182
        put(m, "Lenovo L78031", "聯想 Z5 Pro", "聯想 Z5 Pro", "OnePlus", "device_list_full_import"); // Device_List:L2183
        put(m, "Lenovo L78032", "聯想 Z5 Pro GT", "聯想 Z5 Pro GT", "OnePlus", "device_list_full_import"); // Device_List:L2184
        put(m, "Lenovo L78071", "聯想 Z5s", "聯想 Z5s", "OnePlus", "device_list_full_import"); // Device_List:L2185
        put(m, "Lenovo L78051", "聯想 Z6 Pro", "聯想 Z6 Pro", "OnePlus", "device_list_full_import"); // Device_List:L2186
        put(m, "Lenovo L79041", "聯想 Z6 Pro 5G", "聯想 Z6 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L2187
        put(m, "Lenovo L78121", "聯想 Z6", "聯想 Z6", "OnePlus", "device_list_full_import"); // Device_List:L2188
        put(m, "Lenovo L38111", "聯想 Z6 青春版", "聯想 Z6 青春版", "OnePlus", "device_list_full_import"); // Device_List:L2189
        put(m, "Lenovo K520", "聯想 S5", "聯想 S5", "OnePlus", "device_list_full_import"); // Device_List:L2190
        put(m, "Lenovo K520t", "聯想 S5 移動版", "聯想 S5 移動版", "OnePlus", "device_list_full_import"); // Device_List:L2191
        put(m, "Lenovo L58041", "聯想 S5 Pro", "聯想 S5 Pro", "OnePlus", "device_list_full_import"); // Device_List:L2192
        put(m, "Lenovo L58091", "聯想 S5 Pro GT", "聯想 S5 Pro GT", "OnePlus", "device_list_full_import"); // Device_List:L2193
        put(m, "Lenovo K350t", "聯想 K5", "聯想 K5", "OnePlus", "device_list_full_import"); // Device_List:L2194
        put(m, "Lenovo L38012", "聯想 K5 Note", "聯想 K5 Note", "OnePlus", "device_list_full_import"); // Device_List:L2195
        put(m, "Lenovo L38011", "聯想 K5 Play", "聯想 K5 Play", "OnePlus", "device_list_full_import"); // Device_List:L2196
        put(m, "Lenovo L38021", "聯想 K5 Play 移動版", "聯想 K5 Play 移動版", "OnePlus", "device_list_full_import"); // Device_List:L2197
        put(m, "Lenovo L38031", "聯想 K5s", "聯想 K5s", "OnePlus", "device_list_full_import"); // Device_List:L2198
        put(m, "Lenovo L38041", "聯想 K5 Pro", "聯想 K5 Pro", "OnePlus", "device_list_full_import"); // Device_List:L2199
        put(m, "Lenovo L38082", "聯想 K6 暢享版", "聯想 K6 暢享版", "OnePlus", "device_list_full_import"); // Device_List:L2200
        put(m, "Lenovo L18011", "聯想 A5", "聯想 A5", "OnePlus", "device_list_full_import"); // Device_List:L2201
        put(m, "Lenovo K320t", "聯想 K320t", "聯想 K320t", "OnePlus", "device_list_full_import"); // Device_List:L2202
        put(m, "Lenovo L79031", "拯救者電競手機 Pro", "拯救者電競手機 Pro", "OnePlus", "device_list_full_import"); // Device_List:L2203
        put(m, "Lenovo L70081", "拯救者電競手機 2 Pro", "拯救者電競手機 2 Pro", "OnePlus", "device_list_full_import"); // Device_List:L2204
        put(m, "Lenovo L71091", "聯想拯救者 Y70", "聯想拯救者 Y70", "OnePlus", "device_list_full_import"); // Device_List:L2205
        put(m, "Lenovo L71061", "聯想拯救者 Y90", "聯想拯救者 Y90", "OnePlus", "device_list_full_import"); // Device_List:L2206
        put(m, "XT2611-1", "聯想拯救者 Y70 新一代", "聯想拯救者 Y70 新一代", "Motorola", "device_list_full_import"); // Device_List:L2207
        put(m, "XT2081-4", "聯想樂檬 K12", "聯想樂檬 K12", "Motorola", "device_list_full_import"); // Device_List:L2208
        put(m, "XT2091-7", "聯想樂檬 K12 Pro", "聯想樂檬 K12 Pro", "Motorola", "device_list_full_import"); // Device_List:L2209
        put(m, "Z1221", "ZUK Z1", "ZUK Z1", "", "device_list_full_import"); // Device_List:L2210
        put(m, "Z2131", "ZUK Z2", "ZUK Z2", "", "device_list_full_import"); // Device_List:L2211
        put(m, "Z2122", "ZUK Z2 Pro", "ZUK Z2 Pro", "", "device_list_full_import"); // Device_List:L2212
        put(m, "Z2151", "ZUK Edge", "ZUK Edge", "", "device_list_full_import"); // Device_List:L2213
        put(m, "Lenovo TB-8804F", "小新平板 8 英寸", "小新平板 8 英寸", "OnePlus", "device_list_full_import"); // Device_List:L2214
        put(m, "Lenovo TB-X804F", "小新平板 10 英寸", "小新平板 10 英寸", "OnePlus", "device_list_full_import"); // Device_List:L2215
        put(m, "Lenovo TB-J606F", "小新 Pad", "小新 Pad", "OnePlus", "device_list_full_import"); // Device_List:L2216
        put(m, "TB128FU", "小新 Pad 2022", "小新 Pad 2022", "", "device_list_full_import"); // Device_List:L2217
        put(m, "TB331FC", "小新 Pad 2024", "小新 Pad 2024", "", "device_list_full_import"); // Device_List:L2218
        put(m, "TB335FC", "小新平板 11", "小新平板 11", "", "device_list_full_import"); // Device_List:L2219
        put(m, "TB335ZC", "小新平板 11 5G", "小新平板 11 5G", "", "device_list_full_import"); // Device_List:L2220
        put(m, "TB365FC", "小新平板 12.1", "小新平板 12.1", "", "device_list_full_import"); // Device_List:L2221
        put(m, "Lenovo TB-J607F", "小新 Pad Plus", "小新 Pad Plus", "OnePlus", "device_list_full_import"); // Device_List:L2222
        put(m, "Lenovo TB-J607Z", "小新 Pad Plus 5G", "小新 Pad Plus 5G", "OnePlus", "device_list_full_import"); // Device_List:L2223
        put(m, "TB350XC", "小新 Pad Plus 2023", "小新 Pad Plus 2023", "", "device_list_full_import"); // Device_List:L2224
        put(m, "TB372FC", "小新 Pad Plus 12.7 舒視版", "小新 Pad Plus 12.7 舒視版", "", "device_list_full_import"); // Device_List:L2225
        put(m, "Lenovo TB-J706F", "小新 Pad Pro (2020)", "小新 Pad Pro (2020)", "OnePlus", "device_list_full_import"); // Device_List:L2226
        put(m, "Lenovo TB-J716F", "小新 Pad Pro 2021", "小新 Pad Pro 2021", "OnePlus", "device_list_full_import"); // Device_List:L2227
        put(m, "Lenovo TB-Q706F", "小新 Pad Pro 12.6", "小新 Pad Pro 12.6", "OnePlus", "device_list_full_import"); // Device_List:L2228
        put(m, "TB138FC", "小新 Pad Pro 2022 驍龍版", "小新 Pad Pro 2022 驍龍版", "", "device_list_full_import"); // Device_List:L2229
        put(m, "TB132FU", "小新 Pad Pro 2022 迅鯤版", "小新 Pad Pro 2022 迅鯤版", "", "device_list_full_import"); // Device_List:L2230
        put(m, "TB371FC", "小新 Pad Pro 12.7 驍龍版", "小新 Pad Pro 12.7 驍龍版", "", "device_list_full_import"); // Device_List:L2231
        put(m, "TB370FU", "小新 Pad Pro 12.7 天璣版", "小新 Pad Pro 12.7 天璣版", "", "device_list_full_import"); // Device_List:L2232
        put(m, "TB375FC", "小新 Pad Pro 12.7 2025", "小新 Pad Pro 12.7 2025", "", "device_list_full_import"); // Device_List:L2233
        put(m, "TB710FU", "小新平板 Pro GT", "小新平板 Pro GT", "", "device_list_full_import"); // Device_List:L2234
        put(m, "TB376FC", "聯想 AI 平板 小新 Pro 13", "聯想 AI 平板 小新 Pro 13", "", "device_list_full_import"); // Device_List:L2235
        put(m, "TB378FC", "聯想 AI 平板 小新 Pro GT 13", "聯想 AI 平板 小新 Pro GT 13", "", "device_list_full_import"); // Device_List:L2236
        put(m, "TB351FU", "小新 Pad Studio", "小新 Pad Studio", "", "device_list_full_import"); // Device_List:L2237
        put(m, "Lenovo YT3-850F", "YOGA Tab 3 8” Wi-Fi 版", "YOGA Tab 3 8” Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2238
        put(m, "Lenovo YT3-850L", "YOGA Tab 3 8” LTE 版", "YOGA Tab 3 8” LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2239
        put(m, "Lenovo YT3-X50F", "YOGA Tab 3 10” Wi-Fi 版", "YOGA Tab 3 10” Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2240
        put(m, "Lenovo YT3-X50L", "YOGA Tab 3 10” LTE 版", "YOGA Tab 3 10” LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2241
        put(m, "Lenovo YT-X703F", "YOGA Tab 3 Plus Wi-Fi 版", "YOGA Tab 3 Plus Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2242
        put(m, "Lenovo YT-X703L", "YOGA Tab 3 Plus LTE 版", "YOGA Tab 3 Plus LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2243
        put(m, "Lenovo YT3-X90F", "YOGA Tab 3 PRO 10” Wi-Fi 版", "YOGA Tab 3 PRO 10” Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2244
        put(m, "Lenovo YT3-X90L", "YOGA Tab 3 PRO 10” LTE 版", "YOGA Tab 3 PRO 10” LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2245
        put(m, "Lenovo YT-K606F", "YOGA Pad Pro", "YOGA Pad Pro", "OnePlus", "device_list_full_import"); // Device_List:L2246
        put(m, "TB520FU", "YOGA Pad Pro 12.7 / YOGA Pad Pro AI 元啟版", "YOGA Pad Pro 12.7 / YOGA Pad Pro AI 元啟版", "", "device_list_full_import"); // Device_List:L2247
        put(m, "TB571FU", "YOGA Pad Pro 14.5 AI 元啟版", "YOGA Pad Pro 14.5 AI 元啟版", "", "device_list_full_import"); // Device_List:L2248
        put(m, "SP101FU", "YOGA Paper 墨水平板", "YOGA Paper 墨水平板", "", "device_list_full_import"); // Device_List:L2249
        put(m, "Lenovo TB-9707F", "拯救者平板 Y700 (2022)", "拯救者平板 Y700 (2022)", "OnePlus", "device_list_full_import"); // Device_List:L2250
        put(m, "TB320FC", "拯救者平板 Y700 2023", "拯救者平板 Y700 2023", "", "device_list_full_import"); // Device_List:L2251
        put(m, "TB321FU", "拯救者平板 Y700 2025", "拯救者平板 Y700 2025", "", "device_list_full_import"); // Device_List:L2252
        put(m, "TB322FC", "拯救者平板 Y700 四代", "拯救者平板 Y700 四代", "", "device_list_full_import"); // Device_List:L2253
        put(m, "TB323FU", "聯想 AI 平板 拯救者 Y700 五代", "聯想 AI 平板 拯救者 Y700 五代", "", "device_list_full_import"); // Device_List:L2254
        put(m, "TB570ZU", "拯救者平板 Y900", "拯救者平板 Y900", "", "device_list_full_import"); // Device_List:L2255
        put(m, "TB711FU", "聯想 AI 平板 拯救者 Y900 11", "聯想 AI 平板 拯救者 Y900 11", "", "device_list_full_import"); // Device_List:L2256
        put(m, "TB522FU", "聯想 AI 平板 拯救者 Y900 13", "聯想 AI 平板 拯救者 Y900 13", "", "device_list_full_import"); // Device_List:L2257
        put(m, "Lenovo TB-J616N", "聯想天驕平板電腦", "聯想天驕平板電腦", "OnePlus", "device_list_full_import"); // Device_List:L2258
        put(m, "Lenovo TB-8504F", "聯想 TAB4 8 英寸 Wi-Fi 版", "聯想 TAB4 8 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2259
        put(m, "Lenovo TB-8504N", "聯想 TAB4 8 英寸 LTE 版", "聯想 TAB4 8 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2260
        put(m, "Lenovo TB-8X04F", "聯想 TAB4 8 英寸 REL", "聯想 TAB4 8 英寸 REL", "OnePlus", "device_list_full_import"); // Device_List:L2261
        put(m, "Lenovo TB-X304F", "聯想 TAB4 10.1 英寸 Wi-Fi 版", "聯想 TAB4 10.1 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2262
        put(m, "Lenovo TB-X304N", "聯想 TAB4 10.1 英寸 LTE 版", "聯想 TAB4 10.1 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2263
        put(m, "Lenovo TB-X504F", "聯想 TAB4 10.1 英寸 REL", "聯想 TAB4 10.1 英寸 REL", "OnePlus", "device_list_full_import"); // Device_List:L2264
        put(m, "Lenovo TB-8704F", "聯想 TAB4 Plus 8 英寸 Wi-Fi 版", "聯想 TAB4 Plus 8 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2265
        put(m, "Lenovo TB-8704N", "聯想 TAB4 Plus 8 英寸 LTE 版", "聯想 TAB4 Plus 8 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2266
        put(m, "Lenovo TB-X704F", "聯想 TAB4 Plus 10.1 英寸 Wi-Fi 版", "聯想 TAB4 Plus 10.1 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2267
        put(m, "Lenovo TB-X704N", "聯想 TAB4 Plus 10.1 英寸 LTE 版", "聯想 TAB4 Plus 10.1 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2268
        put(m, "Lenovo TB-8705F", "聯想 M8 8 英寸 Wi-Fi 版", "聯想 M8 8 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2269
        put(m, "Lenovo TB-8705N", "聯想 M8 8 英寸 LTE 版", "聯想 M8 8 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2270
        put(m, "Lenovo TB-8505F", "聯想 M8 8 英寸 Wi-Fi 版 (商用)", "聯想 M8 8 英寸 Wi-Fi 版 (商用)", "OnePlus", "device_list_full_import"); // Device_List:L2271
        put(m, "Lenovo TB-8505N", "聯想 M8 8 英寸 LTE 版 (商用)", "聯想 M8 8 英寸 LTE 版 (商用)", "OnePlus", "device_list_full_import"); // Device_List:L2272
        put(m, "Lenovo TB-X306FC", "聯想 M10 HD 10.1 英寸 Wi-Fi 版", "聯想 M10 HD 10.1 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2273
        put(m, "Lenovo TB-X306NC", "聯想 M10 HD 10.1 英寸 LTE 版", "聯想 M10 HD 10.1 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2274
        put(m, "Lenovo TB-X605FC", "聯想 M10 FHD-REL 10.1 英寸 Wi-Fi 版", "聯想 M10 FHD-REL 10.1 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2275
        put(m, "Lenovo TB-X605LC", "聯想 M10 FHD-REL 10.1 英寸 LTE 版", "聯想 M10 FHD-REL 10.1 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2276
        put(m, "Lenovo TB-X616F", "聯想 M10 PLUS 10.3 英寸 Wi-Fi 版", "聯想 M10 PLUS 10.3 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2277
        put(m, "Lenovo TB-X616M", "聯想 M10 PLUS 10.3 英寸 LTE 版", "聯想 M10 PLUS 10.3 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2278
        put(m, "Lenovo TB-8506F", "聯想啟天 K8 8 英寸 Wi-Fi 版", "聯想啟天 K8 8 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2279
        put(m, "Lenovo TB-8506N", "聯想啟天 K8 8 英寸 LTE 版", "聯想啟天 K8 8 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2280
        put(m, "TB310FU", "聯想啟天 K9 9 英寸 Wi-Fi 版", "聯想啟天 K9 9 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2281
        put(m, "TB310XC", "聯想啟天 K9 9 英寸 LTE 版", "聯想啟天 K9 9 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2282
        put(m, "Lenovo TB-X6C6F", "聯想啟天 K10 10.3 英寸 Wi-Fi 版", "聯想啟天 K10 10.3 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2283
        put(m, "Lenovo TB-X6C6NBF", "聯想啟天 K10 10.3 英寸 無電池版本", "聯想啟天 K10 10.3 英寸 無電池版本", "OnePlus", "device_list_full_import"); // Device_List:L2284
        put(m, "Lenovo TB-X6C6X", "聯想啟天 K10 10.3 英寸 LTE 版", "聯想啟天 K10 10.3 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2285
        put(m, "Lenovo TB-X6E6F", "聯想啟天 K10c 10.3 英寸 Wi-Fi 版", "聯想啟天 K10c 10.3 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2286
        put(m, "Lenovo TB-X6E6N", "聯想啟天 K10c 10.3 英寸 LTE 版", "聯想啟天 K10c 10.3 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2287
        put(m, "Lenovo TB-X6E6FC", "聯想啟天 E10c 10.3 英寸 Wi-Fi 版", "聯想啟天 E10c 10.3 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2288
        put(m, "TB223FC", "聯想啟天 K10 Pro 10.61 英寸 Wi-Fi 版", "聯想啟天 K10 Pro 10.61 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2289
        put(m, "TB226XC", "聯想啟天 K10 Pro 10.61 英寸 LTE 版", "聯想啟天 K10 Pro 10.61 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2290
        put(m, "TB360ZU", "聯想啟天 K10 Pro 10.61 英寸 5G 版", "聯想啟天 K10 Pro 10.61 英寸 5G 版", "", "device_list_full_import"); // Device_List:L2291
        put(m, "Lenovo TB-J6C6F", "聯想啟天 K11 11 英寸 Wi-Fi 版", "聯想啟天 K11 11 英寸 Wi-Fi 版", "OnePlus", "device_list_full_import"); // Device_List:L2292
        put(m, "Lenovo TB-J6C6X", "聯想啟天 K11 11 英寸 LTE 版", "聯想啟天 K11 11 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2293
        put(m, "TB230FC", "聯想啟天 K11 Gen2 11.5 英寸 Wi-Fi 版", "聯想啟天 K11 Gen2 11.5 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2294
        put(m, "TB230XC", "聯想啟天 K11 Gen2 11.5 英寸 LTE 版", "聯想啟天 K11 Gen2 11.5 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2295
        put(m, "TB240FC", "聯想啟天 K12 12.7 英寸 Wi-Fi 版", "聯想啟天 K12 12.7 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2296
        put(m, "SP523FC", "聯想啟天 SmartPaper 10.3 英寸 Wi-Fi 版", "聯想啟天 SmartPaper 10.3 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2297
        put(m, "TB305FU", "聯想昭陽 K9 (二代) 8.7 英寸 Wi-Fi 版", "聯想昭陽 K9 (二代) 8.7 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2298
        put(m, "TB305XC", "聯想昭陽 K9 (二代) 8.7 英寸 LTE 版", "聯想昭陽 K9 (二代) 8.7 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2299
        put(m, "TB330FU", "聯想昭陽 K10 10.95 英寸 Wi-Fi 版", "聯想昭陽 K10 10.95 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2300
        put(m, "TB330XC", "聯想昭陽 K10 10.95 英寸 LTE 版", "聯想昭陽 K10 10.95 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2301
        put(m, "TB311FU", "聯想昭陽 K10c 10.1 英寸 Wi-Fi 版", "聯想昭陽 K10c 10.1 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2302
        put(m, "TB311XC", "聯想昭陽 K10c 10.1 英寸 LTE 版", "聯想昭陽 K10c 10.1 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2303
        put(m, "TB352FC", "聯想昭陽 K11 11.5 英寸 Wi-Fi 版", "聯想昭陽 K11 11.5 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2304
        put(m, "TB352XC", "聯想昭陽 K11 11.5 英寸 LTE 版", "聯想昭陽 K11 11.5 英寸 LTE 版", "", "device_list_full_import"); // Device_List:L2305
        put(m, "TB336FU", "聯想昭陽 K11 (二代) 11 英寸 Wi-Fi 版", "聯想昭陽 K11 (二代) 11 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2306
        put(m, "TB336ZC", "聯想昭陽 K11 (二代) 11 英寸 5G 版", "聯想昭陽 K11 (二代) 11 英寸 5G 版", "", "device_list_full_import"); // Device_List:L2307
        put(m, "TB337FU", "聯想昭陽 K11c 10.95 英寸 Wi-Fi 版", "聯想昭陽 K11c 10.95 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2308
        put(m, "TB373FU", "聯想昭陽 K12 (二代) 12.7 英寸 Wi-Fi 版", "聯想昭陽 K12 (二代) 12.7 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2309
        put(m, "TB373ZC", "聯想昭陽 K12 (二代) 12.7 英寸 5G 版", "聯想昭陽 K12 (二代) 12.7 英寸 5G 版", "", "device_list_full_import"); // Device_List:L2310
        put(m, "TB361FU", "聯想昭陽 K12c 12.1 英寸 Wi-Fi 版", "聯想昭陽 K12c 12.1 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2311
        put(m, "TB361ZU", "聯想昭陽 K12c 12.1 英寸 5G 版", "聯想昭陽 K12c 12.1 英寸 5G 版", "", "device_list_full_import"); // Device_List:L2312
        put(m, "TB391FC", "聯想昭陽 K13 13 英寸 Wi-Fi 版", "聯想昭陽 K13 13 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2313
        put(m, "TB-X802F", "聯想昭陽 G11 10.95 英寸 Wi-Fi 版", "聯想昭陽 G11 10.95 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2314
        put(m, "TB-X903F", "聯想昭陽 G12 11.5 英寸 Wi-Fi 版", "聯想昭陽 G12 11.5 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2315
        put(m, "TBY11", "聯想昭陽 Y11 10.95 英寸 Wi-Fi 版", "聯想昭陽 Y11 10.95 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2316
        put(m, "Lenovo TB-J606N", "聯想平板電腦 K11 11 英寸 LTE 版", "聯想平板電腦 K11 11 英寸 LTE 版", "OnePlus", "device_list_full_import"); // Device_List:L2317
        put(m, "QBH10", "聯想平板電腦 S11 10.95 英寸 Wi-Fi 版", "聯想平板電腦 S11 10.95 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2318
        put(m, "QBH11", "聯想平板電腦 S11 Pro 11.5 英寸 Wi-Fi 版", "聯想平板電腦 S11 Pro 11.5 英寸 Wi-Fi 版", "", "device_list_full_import"); // Device_List:L2319
        put(m, "TB610FU", "ThinkBook Plus Hybrid 2024 (平板)", "ThinkBook Plus Hybrid 2024 (平板)", "", "device_list_full_import"); // Device_List:L2320
        put(m, "M8", "魅族 M8", "魅族 M8", "MEIZU", "device_list_full_import"); // Device_List:L2321
        put(m, "M8SE", "魅族 M8 SE", "魅族 M8 SE", "MEIZU", "device_list_full_import"); // Device_List:L2322
        put(m, "M9", "魅族 M9", "魅族 M9", "MEIZU", "device_list_full_import"); // Device_List:L2323
        put(m, "M030", "魅族 MX 雙核", "魅族 MX 雙核", "MEIZU", "device_list_full_import"); // Device_List:L2324
        put(m, "M031", "魅族 MX 雙核新版", "魅族 MX 雙核新版", "MEIZU", "device_list_full_import"); // Device_List:L2325
        put(m, "M032", "魅族 MX 四核", "魅族 MX 四核", "MEIZU", "device_list_full_import"); // Device_List:L2326
        put(m, "M040", "魅族 MX2 聯通版", "魅族 MX2 聯通版", "MEIZU", "device_list_full_import"); // Device_List:L2327
        put(m, "M045", "魅族 MX2 移動版", "魅族 MX2 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2328
        put(m, "M351", "魅族 MX3 聯通版 (16GB)", "魅族 MX3 聯通版 (16GB)", "MEIZU", "device_list_full_import"); // Device_List:L2329
        put(m, "M353", "魅族 MX3 聯通版 (32GB/64GB)", "魅族 MX3 聯通版 (32GB/64GB)", "MEIZU", "device_list_full_import"); // Device_List:L2330
        put(m, "M355", "魅族 MX3 移動版 (16GB)", "魅族 MX3 移動版 (16GB)", "MEIZU", "device_list_full_import"); // Device_List:L2331
        put(m, "M356", "魅族 MX3 移動版 (32GB/64GB)", "魅族 MX3 移動版 (32GB/64GB)", "MEIZU", "device_list_full_import"); // Device_List:L2332
        put(m, "M460", "魅族 MX4 移動版", "魅族 MX4 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2333
        put(m, "M460A", "魅族 MX4 YunOS 版", "魅族 MX4 YunOS 版", "MEIZU", "device_list_full_import"); // Device_List:L2334
        put(m, "M461", "魅族 MX4 聯通版", "魅族 MX4 聯通版", "MEIZU", "device_list_full_import"); // Device_List:L2335
        put(m, "M460H", "魅族 MX4 國際版", "魅族 MX4 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2336
        put(m, "M462", "魅族 MX4 Pro 移動版", "魅族 MX4 Pro 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2337
        put(m, "M462U", "魅族 MX4 Pro 聯通版", "魅族 MX4 Pro 聯通版", "MEIZU", "device_list_full_import"); // Device_List:L2338
        put(m, "M462H", "魅族 MX4 Pro 國際版", "魅族 MX4 Pro 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2339
        put(m, "M575", "魅族 MX5 公開版", "魅族 MX5 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2340
        put(m, "M575M", "魅族 MX5 移動版", "魅族 MX5 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2341
    }

    private static void fill13(Map<String, Entry> m) {
        put(m, "M575U", "魅族 MX5 聯通版", "魅族 MX5 聯通版", "MEIZU", "device_list_full_import"); // Device_List:L2342
        put(m, "M575H", "魅族 MX5 國際版", "魅族 MX5 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2343
        put(m, "M685Q", "魅族 MX6 公開版", "魅族 MX6 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2344
        put(m, "M685M", "魅族 MX6 移動版", "魅族 MX6 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2345
        put(m, "M685U", "魅族 MX6 聯通版", "魅族 MX6 聯通版", "MEIZU", "device_list_full_import"); // Device_List:L2346
        put(m, "M685C", "魅族 MX6 電信版", "魅族 MX6 電信版", "MEIZU", "device_list_full_import"); // Device_List:L2347
        put(m, "M685H", "魅族 MX6 國際版", "魅族 MX6 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2348
        put(m, "M576", "魅族 PRO 5 公開版", "魅族 PRO 5 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2349
        put(m, "M576U", "魅族 PRO 5 聯通版", "魅族 PRO 5 聯通版", "MEIZU", "device_list_full_import"); // Device_List:L2350
        put(m, "M576H", "魅族 PRO 5 國際版", "魅族 PRO 5 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2351
        put(m, "M570Q", "魅族 PRO 6 公開版", "魅族 PRO 6 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2352
        put(m, "M570M", "魅族 PRO 6 移動版", "魅族 PRO 6 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2353
        put(m, "M570C", "魅族 PRO 6 電信版", "魅族 PRO 6 電信版", "MEIZU", "device_list_full_import"); // Device_List:L2354
        put(m, "M570H", "魅族 PRO 6 國際版", "魅族 PRO 6 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2355
        put(m, "M570Q-S", "魅族 PRO 6s", "魅族 PRO 6s", "MEIZU", "device_list_full_import"); // Device_List:L2356
        put(m, "M686", "魅族 PRO 6 Plus (64GB)", "魅族 PRO 6 Plus (64GB)", "MEIZU", "device_list_full_import"); // Device_List:L2357
        put(m, "M686G", "魅族 PRO 6 Plus (128GB)", "魅族 PRO 6 Plus (128GB)", "MEIZU", "device_list_full_import"); // Device_List:L2358
        put(m, "M686H", "魅族 PRO 6 Plus 國際版", "魅族 PRO 6 Plus 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2359
        put(m, "M792Q-L", "魅族 PRO 7 公開版 (64GB)", "魅族 PRO 7 公開版 (64GB)", "MEIZU", "device_list_full_import"); // Device_List:L2360
        put(m, "M792M-L", "魅族 PRO 7 移動版 (64GB)", "魅族 PRO 7 移動版 (64GB)", "MEIZU", "device_list_full_import"); // Device_List:L2361
        put(m, "M792C-L", "魅族 PRO 7 電信版 (64GB)", "魅族 PRO 7 電信版 (64GB)", "MEIZU", "device_list_full_import"); // Device_List:L2362
        put(m, "M792H", "魅族 PRO 7 國際版", "魅族 PRO 7 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2363
        put(m, "M792Q", "魅族 PRO 7 公開版 (128GB)", "魅族 PRO 7 公開版 (128GB)", "MEIZU", "device_list_full_import"); // Device_List:L2364
        put(m, "M792C", "魅族 PRO 7 電信版 (128GB)", "魅族 PRO 7 電信版 (128GB)", "MEIZU", "device_list_full_import"); // Device_List:L2365
        put(m, "M793Q", "魅族 PRO 7 Plus 公開版", "魅族 PRO 7 Plus 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2366
        put(m, "M793H", "魅族 PRO 7 Plus 國際版", "魅族 PRO 7 Plus 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2367
        put(m, "M881Q", "魅族 15 公開版", "魅族 15 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2368
        put(m, "M881M", "魅族 15 移動版", "魅族 15 移動版", "MEIZU", "device_list_full_import"); // Device_List:L2369
        put(m, "M881H", "魅族 15 國際版", "魅族 15 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2370
        put(m, "M891Q", "魅族 15 Plus 公開版", "魅族 15 Plus 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2371
        put(m, "M891H", "魅族 15 Plus 國際版", "魅族 15 Plus 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2372
        put(m, "M871Q", "魅族 M15 公開版", "魅族 M15 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2373
        put(m, "M871H", "魅族 15 Lite 國際版", "魅族 15 Lite 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2374
        put(m, "M882Q", "魅族 16th 公開版", "魅族 16th 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2375
        put(m, "M882H", "魅族 16th 國際版", "魅族 16th 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2376
        put(m, "M892Q", "魅族 16th Plus 公開版", "魅族 16th Plus 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2377
        put(m, "M872Q", "魅族 16 X 公開版", "魅族 16 X 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2378
        put(m, "M872H", "魅族 16 國際版", "魅族 16 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2379
        put(m, "M971Q", "魅族 16s 公開版", "魅族 16s 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2380
        put(m, "M971H", "魅族 16s 國際版", "魅族 16s 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2381
        put(m, "M926Q", "魅族 16Xs 公開版", "魅族 16Xs 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2382
        put(m, "M926H", "魅族 16Xs 國際版", "魅族 16Xs 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2383
        put(m, "M973Q", "魅族 16s Pro 公開版", "魅族 16s Pro 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2384
        put(m, "M928Q", "魅族 16T 公開版", "魅族 16T 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2385
        put(m, "M081Q", "魅族 17 公開版", "魅族 17 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2386
        put(m, "M081M", "魅族 17 運營商定制版", "魅族 17 運營商定制版", "MEIZU", "device_list_full_import"); // Device_List:L2387
        put(m, "M091Q", "魅族 17 Pro 公開版", "魅族 17 Pro 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2388
        put(m, "M091M", "魅族 17 Pro 運營商定制版", "魅族 17 Pro 運營商定制版", "MEIZU", "device_list_full_import"); // Device_List:L2389
        put(m, "M181Q", "魅族 18", "魅族 18", "MEIZU", "device_list_full_import"); // Device_List:L2390
        put(m, "M191Q", "魅族 18 Pro", "魅族 18 Pro", "MEIZU", "device_list_full_import"); // Device_List:L2391
        put(m, "M172Q", "魅族 18X", "魅族 18X", "MEIZU", "device_list_full_import"); // Device_List:L2392
        put(m, "M182Q", "魅族 18s", "魅族 18s", "MEIZU", "device_list_full_import"); // Device_List:L2393
        put(m, "M192Q", "魅族 18s", "魅族 18s", "MEIZU", "device_list_full_import"); // Device_List:L2394
        put(m, "M381Q", "魅族 20 / 魅族 20 Classic", "魅族 20 / 魅族 20 Classic", "MEIZU", "device_list_full_import"); // Device_List:L2395
        put(m, "M391Q", "魅族 20 PRO", "魅族 20 PRO", "MEIZU", "device_list_full_import"); // Device_List:L2396
        put(m, "M392Q", "魅族 20 INFINITY 無界版", "魅族 20 INFINITY 無界版", "MEIZU", "device_list_full_import"); // Device_List:L2397
        put(m, "M461Q", "魅族 21 公開版", "魅族 21 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2398
        put(m, "M461H", "魅族 21 國際版", "魅族 21 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2399
        put(m, "M481Q", "魅族 21 PRO", "魅族 21 PRO", "MEIZU", "device_list_full_import"); // Device_List:L2400
        put(m, "M481S", "魅族 21 PRO Flyme 鈦好用版", "魅族 21 PRO Flyme 鈦好用版", "MEIZU", "device_list_full_import"); // Device_List:L2401
        put(m, "M468Q", "魅族 21 Note 公開版", "魅族 21 Note 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2402
        put(m, "M468H", "魅族 21 Note 國際版", "魅族 21 Note 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2403
        put(m, "M582Q", "魅族 22", "魅族 22", "MEIZU", "device_list_full_import"); // Device_List:L2404
        put(m, "M582V", "魅族 22 (16GB+1TB)", "魅族 22 (16GB+1TB)", "MEIZU", "device_list_full_import"); // Device_List:L2405
        put(m, "M431Q", "魅族 Lucky 08 公開版", "魅族 Lucky 08 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2406
        put(m, "M852Q", "魅族 X8 公開版", "魅族 X8 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2407
        put(m, "M852H", "魅族 X8 國際版", "魅族 X8 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2408
        put(m, "M813Q", "魅族 V8 高配版", "魅族 V8 高配版", "MEIZU", "device_list_full_import"); // Device_List:L2409
        put(m, "M813H", "魅族 M8 國際版", "魅族 M8 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2410
        put(m, "M816Q", "魅族 V8 標配版", "魅族 V8 標配版", "MEIZU", "device_list_full_import"); // Device_List:L2411
        put(m, "M816H", "魅族 M8 Lite 國際版", "魅族 M8 Lite 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2412
        put(m, "M822Q", "魅族 Note8 公開版", "魅族 Note8 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2413
        put(m, "M822H", "魅族 Note8 國際版", "魅族 Note8 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2414
        put(m, "M923Q", "魅族 Note9 公開版", "魅族 Note9 公開版", "MEIZU", "device_list_full_import"); // Device_List:L2415
        put(m, "M923H", "魅族 Note9 國際版", "魅族 Note9 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2416
        put(m, "M521Q", "魅族 Note 16", "魅族 Note 16", "MEIZU", "device_list_full_import"); // Device_List:L2417
        put(m, "M531Q", "魅族 Note 16 Pro", "魅族 Note 16 Pro", "MEIZU", "device_list_full_import"); // Device_List:L2418
        put(m, "M411L", "魅族 Note 21 國際版", "魅族 Note 21 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2419
        put(m, "M412H", "魅族 Note 21 Pro 國際版", "魅族 Note 21 Pro 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2420
        put(m, "M513H", "魅族 Note 22 國際版", "魅族 Note 22 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2421
        put(m, "M810H", "魅族 M8c 國際版", "魅族 M8c 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2422
        put(m, "M818H", "魅族 C9 國際版", "魅族 C9 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2423
        put(m, "M819H", "魅族 C9 Pro 國際版", "魅族 C9 Pro 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2424
        put(m, "M918H", "魅族 M10 國際版", "魅族 M10 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2425
        put(m, "M463M", "魅藍 note 移動版", "魅藍 note 移動版", "", "device_list_full_import"); // Device_List:L2426
        put(m, "M463U", "魅藍 note 聯通版", "魅藍 note 聯通版", "", "device_list_full_import"); // Device_List:L2427
        put(m, "M463C", "魅藍 note 電信版", "魅藍 note 電信版", "", "device_list_full_import"); // Device_List:L2428
        put(m, "M463H", "魅族 m1 note 國際版", "魅族 m1 note 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2429
        put(m, "M571", "魅藍 note2 公開版", "魅藍 note2 公開版", "", "device_list_full_import"); // Device_List:L2430
        put(m, "M571M", "魅藍 note2 移動版", "魅藍 note2 移動版", "", "device_list_full_import"); // Device_List:L2431
        put(m, "M571U", "魅藍 note2 聯通版", "魅藍 note2 聯通版", "", "device_list_full_import"); // Device_List:L2432
        put(m, "M571C", "魅藍 note2 電信版", "魅藍 note2 電信版", "", "device_list_full_import"); // Device_List:L2433
        put(m, "M571H", "魅族 m2 note 國際版", "魅族 m2 note 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2434
        put(m, "L681Q", "魅藍 Note3 公開版", "魅藍 Note3 公開版", "", "device_list_full_import"); // Device_List:L2435
        put(m, "L681M", "魅藍 Note3 移動版", "魅藍 Note3 移動版", "", "device_list_full_import"); // Device_List:L2436
        put(m, "L681C", "魅藍 Note3 電信版", "魅藍 Note3 電信版", "", "device_list_full_import"); // Device_List:L2437
        put(m, "L681H", "魅族 M3 note 國際版", "魅族 M3 note 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2438
        put(m, "M621Q", "魅藍 Note5 公開版", "魅藍 Note5 公開版", "", "device_list_full_import"); // Device_List:L2439
        put(m, "M621M", "魅藍 Note5 移動版", "魅藍 Note5 移動版", "", "device_list_full_import"); // Device_List:L2440
        put(m, "M621C-S", "魅藍 Note5 電信版", "魅藍 Note5 電信版", "", "device_list_full_import"); // Device_List:L2441
        put(m, "M621H", "魅族 M5 Note 國際版", "魅族 M5 Note 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2442
        put(m, "M721Q", "魅藍 Note6 公開版", "魅藍 Note6 公開版", "", "device_list_full_import"); // Device_List:L2443
        put(m, "M721M", "魅藍 Note6 移動版", "魅藍 Note6 移動版", "", "device_list_full_import"); // Device_List:L2444
        put(m, "M721C", "魅藍 Note6 電信版", "魅藍 Note6 電信版", "", "device_list_full_import"); // Device_List:L2445
        put(m, "M721H", "魅族 M6 Note 國際版", "魅族 M6 Note 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2446
        put(m, "A680Q", "魅藍 E 公開版", "魅藍 E 公開版", "", "device_list_full_import"); // Device_List:L2447
        put(m, "A680M", "魅藍 E 移動版", "魅藍 E 移動版", "", "device_list_full_import"); // Device_List:L2448
        put(m, "A680H", "魅族 M3E 國際版", "魅族 M3E 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2449
        put(m, "M741A", "魅藍 E2 公開版", "魅藍 E2 公開版", "", "device_list_full_import"); // Device_List:L2450
        put(m, "M741Y", "魅藍 E2 移動版", "魅藍 E2 移動版", "", "device_list_full_import"); // Device_List:L2451
        put(m, "M851Q", "魅藍 E3 公開版", "魅藍 E3 公開版", "", "device_list_full_import"); // Device_List:L2452
        put(m, "M851M", "魅藍 E3 移動版", "魅藍 E3 移動版", "", "device_list_full_import"); // Device_List:L2453
        put(m, "M682Q", "魅藍 X", "魅藍 X", "", "device_list_full_import"); // Device_List:L2454
        put(m, "M465M", "魅藍 移動版", "魅藍 移動版", "", "device_list_full_import"); // Device_List:L2455
        put(m, "M465A", "魅藍 YunOS 版", "魅藍 YunOS 版", "", "device_list_full_import"); // Device_List:L2456
        put(m, "M578", "魅藍 2 公開版", "魅藍 2 公開版", "", "device_list_full_import"); // Device_List:L2457
        put(m, "M578A", "魅藍 2 YunOS 公開版", "魅藍 2 YunOS 公開版", "", "device_list_full_import"); // Device_List:L2458
        put(m, "M578M", "魅藍 2 移動版", "魅藍 2 移動版", "", "device_list_full_import"); // Device_List:L2459
        put(m, "M578MA", "魅藍 2 YunOS 移動版", "魅藍 2 YunOS 移動版", "", "device_list_full_import"); // Device_List:L2460
        put(m, "M578U", "魅藍 2 聯通版", "魅藍 2 聯通版", "", "device_list_full_import"); // Device_List:L2461
        put(m, "M578C", "魅藍 2 電信版", "魅藍 2 電信版", "", "device_list_full_import"); // Device_List:L2462
        put(m, "M578CA", "魅藍 2 YunOS 電信版", "魅藍 2 YunOS 電信版", "", "device_list_full_import"); // Device_List:L2463
        put(m, "M578CE", "魅藍 2 電信定制版", "魅藍 2 電信定制版", "", "device_list_full_import"); // Device_List:L2464
        put(m, "M578H", "魅族 m2 國際版", "魅族 m2 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2465
        put(m, "M688Q", "魅藍 3 公開版", "魅藍 3 公開版", "", "device_list_full_import"); // Device_List:L2466
        put(m, "M688M", "魅藍 3 移動定制版", "魅藍 3 移動定制版", "", "device_list_full_import"); // Device_List:L2467
        put(m, "M688U", "魅藍 3 聯通版", "魅藍 3 聯通版", "", "device_list_full_import"); // Device_List:L2468
        put(m, "M688C", "魅藍 3 電信版", "魅藍 3 電信版", "", "device_list_full_import"); // Device_List:L2469
        put(m, "Y685Q", "魅藍 3s 公開版", "魅藍 3s 公開版", "", "device_list_full_import"); // Device_List:L2470
        put(m, "Y685M", "魅藍 3s 移動版", "魅藍 3s 移動版", "", "device_list_full_import"); // Device_List:L2471
        put(m, "Y685C", "魅藍 3s 電信版", "魅藍 3s 電信版", "", "device_list_full_import"); // Device_List:L2472
        put(m, "Y685H", "魅族 M3s 國際版", "魅族 M3s 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2473
        put(m, "M611A", "魅藍 5 公開版", "魅藍 5 公開版", "", "device_list_full_import"); // Device_List:L2474
        put(m, "M611Y", "魅藍 5 移動版", "魅藍 5 移動版", "", "device_list_full_import"); // Device_List:L2475
        put(m, "M611D", "魅藍 5 電信版", "魅藍 5 電信版", "", "device_list_full_import"); // Device_List:L2476
        put(m, "M611H", "魅族 M5 國際版", "魅族 M5 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2477
        put(m, "M612Q", "魅藍 5s 公開版", "魅藍 5s 公開版", "", "device_list_full_import"); // Device_List:L2478
        put(m, "M612M", "魅藍 5s 移動版", "魅藍 5s 移動版", "", "device_list_full_import"); // Device_List:L2479
        put(m, "M612C", "魅藍 5s 電信版", "魅藍 5s 電信版", "", "device_list_full_import"); // Device_List:L2480
        put(m, "M612H", "魅族 M5s 國際版", "魅族 M5s 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2481
        put(m, "M711Q", "魅藍 6 公開版", "魅藍 6 公開版", "", "device_list_full_import"); // Device_List:L2482
        put(m, "M711M", "魅藍 6 移動版", "魅藍 6 移動版", "", "device_list_full_import"); // Device_List:L2483
        put(m, "M711C", "魅藍 6 電信版", "魅藍 6 電信版", "", "device_list_full_import"); // Device_List:L2484
        put(m, "M711H", "魅族 M6 國際版", "魅族 M6 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2485
        put(m, "M712Q-B", "魅藍 S6 公開版", "魅藍 S6 公開版", "", "device_list_full_import"); // Device_List:L2486
        put(m, "M712M", "魅藍 S6 移動版", "魅藍 S6 移動版", "", "device_list_full_import"); // Device_List:L2487
        put(m, "M712C", "魅藍 S6 電信版", "魅藍 S6 電信版", "", "device_list_full_import"); // Device_List:L2488
        put(m, "M712H", "魅族 M6s 國際版", "魅族 M6s 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2489
        put(m, "M811Q", "魅藍 6T 公開版", "魅藍 6T 公開版", "", "device_list_full_import"); // Device_List:L2490
        put(m, "M811H", "魅族 M6T 國際版", "魅族 M6T 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2491
        put(m, "M2112", "魅藍 10", "魅藍 10", "", "device_list_full_import"); // Device_List:L2492
        put(m, "M2111", "魅藍 10s", "魅藍 10s", "", "device_list_full_import"); // Device_List:L2493
        put(m, "M421Q", "魅藍 20 / 魅藍 20C / 魅族 M20", "魅藍 20 / 魅藍 20C / 魅族 M20", "MEIZU", "device_list_full_import"); // Device_List:L2494
        put(m, "M416L", "魅族 Mblu 21 國際版", "魅族 Mblu 21 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2495
        put(m, "M511H", "魅族 Mblu 22 國際版", "魅族 Mblu 22 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2496
        put(m, "M512H", "魅族 Mblu 22 Pro 國際版", "魅族 Mblu 22 Pro 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2497
        put(m, "S685Q", "魅藍 Max 公開版", "魅藍 Max 公開版", "", "device_list_full_import"); // Device_List:L2498
        put(m, "S685M", "魅藍 Max 移動版", "魅藍 Max 移動版", "", "device_list_full_import"); // Device_List:L2499
        put(m, "S685C", "魅藍 Max 電信版", "魅藍 Max 電信版", "", "device_list_full_import"); // Device_List:L2500
        put(m, "S685H", "魅族 M3 Max 國際版", "魅族 M3 Max 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2501
        put(m, "U680A", "魅藍 U10 公開版", "魅藍 U10 公開版", "", "device_list_full_import"); // Device_List:L2502
        put(m, "U680Y", "魅藍 U10 移動版", "魅藍 U10 移動版", "", "device_list_full_import"); // Device_List:L2503
        put(m, "U680D", "魅藍 U10 電信版", "魅藍 U10 電信版", "", "device_list_full_import"); // Device_List:L2504
        put(m, "U680H", "魅藍 U10 國際版", "魅藍 U10 國際版", "", "device_list_full_import"); // Device_List:L2505
        put(m, "U685Q", "魅藍 U20 公開版", "魅藍 U20 公開版", "", "device_list_full_import"); // Device_List:L2506
        put(m, "U685M", "魅藍 U20 移動版", "魅藍 U20 移動版", "", "device_list_full_import"); // Device_List:L2507
        put(m, "U685C", "魅藍 U20 電信版", "魅藍 U20 電信版", "", "device_list_full_import"); // Device_List:L2508
        put(m, "U685H", "魅藍 U20 國際版", "魅藍 U20 國際版", "", "device_list_full_import"); // Device_List:L2509
        put(m, "M57A", "魅藍 metal 公開版", "魅藍 metal 公開版", "", "device_list_full_import"); // Device_List:L2510
        put(m, "M57AM", "魅藍 metal 移動版", "魅藍 metal 移動版", "", "device_list_full_import"); // Device_List:L2511
        put(m, "M57AU", "魅藍 metal 聯通版", "魅藍 metal 聯通版", "", "device_list_full_import"); // Device_List:L2512
        put(m, "M57AC", "魅藍 metal 電信版", "魅藍 metal 電信版", "", "device_list_full_import"); // Device_List:L2513
        put(m, "M710M", "魅藍 A5 移動定制版", "魅藍 A5 移動定制版", "", "device_list_full_import"); // Device_List:L2514
        put(m, "M710H", "魅族 M5c 國際版", "魅族 M5c 國際版", "MEIZU", "device_list_full_import"); // Device_List:L2515
        put(m, "M481R", "HongQi Wonder", "HongQi Wonder", "", "device_list_full_import"); // Device_List:L2516
        put(m, "XT1085", "Moto X", "Moto X", "Motorola", "device_list_full_import"); // Device_List:L2520
        put(m, "XT1079", "Moto G LTE 移動/聯通版", "Moto G LTE 移動/聯通版", "Motorola", "device_list_full_import"); // Device_List:L2521
        put(m, "XT1077", "Moto G LTE 電信/聯通版", "Moto G LTE 電信/聯通版", "Motorola", "device_list_full_import"); // Device_List:L2522
        put(m, "XT1115", "Moto X Pro", "Moto X Pro", "Motorola", "device_list_full_import"); // Device_List:L2523
        put(m, "XT1570", "Moto X Style", "Moto X Style", "Motorola", "device_list_full_import"); // Device_List:L2524
    }

    private static void fill14(Map<String, Entry> m) {
        put(m, "XT1561", "Moto X Play", "Moto X Play", "Motorola", "device_list_full_import"); // Device_List:L2525
        put(m, "XT1581", "Moto X 極", "Moto X 極", "Motorola", "device_list_full_import"); // Device_List:L2526
        put(m, "XT1635-03", "Moto Z Play", "Moto Z Play", "Motorola", "device_list_full_import"); // Device_List:L2527
        put(m, "XT1662", "Moto M", "Moto M", "Motorola", "device_list_full_import"); // Device_List:L2528
        put(m, "XT1650-05", "Moto Z", "Moto Z", "Motorola", "device_list_full_import"); // Device_List:L2529
        put(m, "XT1710-08", "Moto Z2 Play", "Moto Z2 Play", "Motorola", "device_list_full_import"); // Device_List:L2530
        put(m, "XT1710-11", "Moto Z2 Play 移動定制版", "Moto Z2 Play 移動定制版", "Motorola", "device_list_full_import"); // Device_List:L2531
        put(m, "XT1799-2", "moto 青柚", "moto 青柚", "Motorola", "device_list_full_import"); // Device_List:L2532
        put(m, "XT1789-05", "moto Z 2018", "moto Z 2018", "Motorola", "device_list_full_import"); // Device_List:L2533
        put(m, "XT1925-10", "moto 青柚 1s", "moto 青柚 1s", "Motorola", "device_list_full_import"); // Device_List:L2534
        put(m, "XT1929-15", "motorola Z3", "motorola Z3", "Motorola", "device_list_full_import"); // Device_List:L2535
        put(m, "XT1924-9", "motorola e5 plus", "motorola e5 plus", "Motorola", "device_list_full_import"); // Device_List:L2536
        put(m, "XT1943-1", "motorola p30", "motorola p30", "Motorola", "device_list_full_import"); // Device_List:L2537
        put(m, "XT1942-1", "motorola p30 note", "motorola p30 note", "Motorola", "device_list_full_import"); // Device_List:L2538
        put(m, "XT1941-2", "motorola p30 play", "motorola p30 play", "Motorola", "device_list_full_import"); // Device_List:L2539
        put(m, "XT1965-6", "motorola g7 plus", "motorola g7 plus", "Motorola", "device_list_full_import"); // Device_List:L2540
        put(m, "XT1970-5", "motorola p50", "motorola p50", "Motorola", "device_list_full_import"); // Device_List:L2541
        put(m, "XT2071-4", "motorola razr 5G", "motorola razr 5G", "Motorola", "device_list_full_import"); // Device_List:L2542
        put(m, "XT2125-4", "motorola edge s", "motorola edge s", "Motorola", "device_list_full_import"); // Device_List:L2543
        put(m, "XT2143-1", "motorola edge 輕奢版", "motorola edge 輕奢版", "Motorola", "device_list_full_import"); // Device_List:L2544
        put(m, "XT2153-1", "motorola edge s pro", "motorola edge s pro", "Motorola", "device_list_full_import"); // Device_List:L2545
        put(m, "XT2137-2", "motorola g50", "motorola g50", "Motorola", "device_list_full_import"); // Device_List:L2546
        put(m, "XT2171-3", "moto g51", "moto g51", "Motorola", "device_list_full_import"); // Device_List:L2547
        put(m, "XT2169-2", "moto g71", "moto g71", "Motorola", "device_list_full_import"); // Device_List:L2548
        put(m, "XT2225-2", "moto g71s", "moto g71s", "Motorola", "device_list_full_import"); // Device_List:L2549
        put(m, "XT2175-2", "moto edge S30", "moto edge S30", "Motorola", "device_list_full_import"); // Device_List:L2550
        put(m, "XT2201-2", "moto edge X30", "moto edge X30", "Motorola", "device_list_full_import"); // Device_List:L2551
        put(m, "XT2201-6", "moto edge X30 屏下攝像版", "moto edge X30 屏下攝像版", "Motorola", "device_list_full_import"); // Device_List:L2552
        put(m, "XT2241-1", "moto X30 Pro", "moto X30 Pro", "Motorola", "device_list_full_import"); // Device_List:L2553
        put(m, "XT2243-2", "moto S30 Pro", "moto S30 Pro", "Motorola", "device_list_full_import"); // Device_List:L2554
        put(m, "XT2251-1", "moto razr 2022", "moto razr 2022", "Motorola", "device_list_full_import"); // Device_List:L2555
        put(m, "XT2301-5", "moto X40", "moto X40", "Motorola", "device_list_full_import"); // Device_List:L2556
        put(m, "XT2335-3", "moto g53", "moto g53", "Motorola", "device_list_full_import"); // Device_List:L2557
        put(m, "XT2323-3", "moto razr 40", "moto razr 40", "Motorola", "device_list_full_import"); // Device_List:L2558
        put(m, "XT2321-2", "moto razr 40 Ultra", "moto razr 40 Ultra", "Motorola", "device_list_full_import"); // Device_List:L2559
        put(m, "XT2343-3", "moto g54", "moto g54", "Motorola", "device_list_full_import"); // Device_List:L2560
        put(m, "XT2363-4", "moto g34 / moto g34s", "moto g34 / moto g34s", "Motorola", "device_list_full_import"); // Device_List:L2561
        put(m, "XT2401-2", "moto X50 Ultra", "moto X50 Ultra", "Motorola", "device_list_full_import"); // Device_List:L2562
        put(m, "XT2409-5", "moto S50", "moto S50", "Motorola", "device_list_full_import"); // Device_List:L2563
        put(m, "XT2427-4", "moto S50 Neo", "moto S50 Neo", "Motorola", "device_list_full_import"); // Device_List:L2564
        put(m, "XT2453-2", "moto razr 50", "moto razr 50", "Motorola", "device_list_full_import"); // Device_List:L2565
        put(m, "XT2451-4", "moto razr 50 Ultra", "moto razr 50 Ultra", "Motorola", "device_list_full_import"); // Device_List:L2566
        put(m, "XT2435-3", "moto g55", "moto g55", "Motorola", "device_list_full_import"); // Device_List:L2567
        put(m, "XT2437-4", "moto g75", "moto g75", "Motorola", "device_list_full_import"); // Device_List:L2568
        put(m, "XT2505-4", "moto edge 60", "moto edge 60", "Motorola", "device_list_full_import"); // Device_List:L2569
        put(m, "XT2503-3", "moto edge 60s", "moto edge 60s", "Motorola", "device_list_full_import"); // Device_List:L2570
        put(m, "XT2507-5", "moto edge 60 Pro", "moto edge 60 Pro", "Motorola", "device_list_full_import"); // Device_List:L2571
        put(m, "XT2553-2", "moto razr 60", "moto razr 60", "Motorola", "device_list_full_import"); // Device_List:L2572
        put(m, "XT2557-1", "moto razr 60 Pro", "moto razr 60 Pro", "Motorola", "device_list_full_import"); // Device_List:L2573
        put(m, "XT2551-3", "moto razr 60 Ultra", "moto razr 60 Ultra", "Motorola", "device_list_full_import"); // Device_List:L2574
        put(m, "XT2527-3", "moto g100 Pro", "moto g100 Pro", "Motorola", "device_list_full_import"); // Device_List:L2575
        put(m, "XT2533-4", "moto g100", "moto g100", "Motorola", "device_list_full_import"); // Device_List:L2576
        put(m, "XT2537-4", "moto g100s", "moto g100s", "Motorola", "device_list_full_import"); // Device_List:L2577
        put(m, "XT2601-1", "moto X70 Air", "moto X70 Air", "Motorola", "device_list_full_import"); // Device_List:L2578
        put(m, "XT2603-1", "moto X70 Air Pro", "moto X70 Air Pro", "Motorola", "device_list_full_import"); // Device_List:L2579
        put(m, "XT2651-4", "moto razr fold", "moto razr fold", "Motorola", "device_list_full_import"); // Device_List:L2580
        put(m, "XT2655-4", "moto razr 70 Ultra", "moto razr 70 Ultra", "Motorola", "device_list_full_import"); // Device_List:L2581
        put(m, "TA-1000", "Nokia 6", "Nokia 6", "Nokia", "device_list_full_import"); // Device_List:L2582
        put(m, "TA-1054", "Nokia 6 (第二代)", "Nokia 6 (第二代)", "Nokia", "device_list_full_import"); // Device_List:L2583
        put(m, "TA-1041", "Nokia 7", "Nokia 7", "Nokia", "device_list_full_import"); // Device_List:L2584
        put(m, "TA-1062", "Nokia 7 Plus", "Nokia 7 Plus", "Nokia", "device_list_full_import"); // Device_List:L2585
        put(m, "TA-1042", "Nokia 8 Sirocco", "Nokia 8 Sirocco", "Nokia", "device_list_full_import"); // Device_List:L2586
        put(m, "TA-1094", "Nokia 9 PureView", "Nokia 9 PureView", "Nokia", "device_list_full_import"); // Device_List:L2587
        put(m, "TA-1109", "Nokia X5", "Nokia X5", "Nokia", "device_list_full_import"); // Device_List:L2588
        put(m, "TA-1099", "Nokia X6", "Nokia X6", "Nokia", "device_list_full_import"); // Device_List:L2589
        put(m, "TA-1131", "Nokia X7", "Nokia X7", "Nokia", "device_list_full_import"); // Device_List:L2590
        put(m, "TA-1172", "Nokia X71", "Nokia X71", "Nokia", "device_list_full_import"); // Device_List:L2591
        put(m, "TA-1117", "Nokia 3.1 Plus", "Nokia 3.1 Plus", "Nokia", "device_list_full_import"); // Device_List:L2592
        put(m, "TA-1335", "Nokia C1 Plus", "Nokia C1 Plus", "Nokia", "device_list_full_import"); // Device_List:L2593
        put(m, "TA-1258", "Nokia C3", "Nokia C3", "Nokia", "device_list_full_import"); // Device_List:L2594
        put(m, "TA-1388", "Nokia C20 Plus", "Nokia C20 Plus", "Nokia", "device_list_full_import"); // Device_List:L2595
        put(m, "TA-1361", "Nokia G50", "Nokia G50", "Nokia", "device_list_full_import"); // Device_List:L2596
        put(m, "TA-1392", "Nokia T20", "Nokia T20", "Nokia", "device_list_full_import"); // Device_List:L2597
        put(m, "TA-1511", "Nokia C31", "Nokia C31", "Nokia", "device_list_full_import"); // Device_List:L2598
        put(m, "A063", "Nothing Phone (1)", "Nothing Phone (1)", "Nothing", "device_list_full_import"); // Device_List:L2599
        put(m, "A065", "Nothing Phone (2) Global", "Nothing Phone (2) Global", "Nothing", "device_list_full_import"); // Device_List:L2600
        put(m, "AIN065", "Nothing Phone (2) India", "Nothing Phone (2) India", "ASUS", "device_list_full_import"); // Device_List:L2601
        put(m, "A142", "Nothing Phone (2a)", "Nothing Phone (2a)", "Nothing", "device_list_full_import"); // Device_List:L2602
        put(m, "A142P", "Nothing Phone (2a) Plus", "Nothing Phone (2a) Plus", "Nothing", "device_list_full_import"); // Device_List:L2603
        put(m, "A024", "Nothing Phone (3)", "Nothing Phone (3)", "Nothing", "device_list_full_import"); // Device_List:L2604
        put(m, "A059", "Nothing Phone (3a)", "Nothing Phone (3a)", "Nothing", "device_list_full_import"); // Device_List:L2605
        put(m, "A059P", "Nothing Phone (3a) Pro", "Nothing Phone (3a) Pro", "Nothing", "device_list_full_import"); // Device_List:L2606
        put(m, "A001T", "Nothing Phone (3a) Lite", "Nothing Phone (3a) Lite", "Nothing", "device_list_full_import"); // Device_List:L2607
        put(m, "A069", "Nothing Phone (4a)", "Nothing Phone (4a)", "Nothing", "device_list_full_import"); // Device_List:L2608
        put(m, "A069P", "Nothing Phone (4a) Pro", "Nothing Phone (4a) Pro", "Nothing", "device_list_full_import"); // Device_List:L2609
        put(m, "A009P", "Nothing Phone (4b)", "Nothing Phone (4b)", "Nothing", "device_list_full_import"); // Device_List:L2610
        put(m, "A015", "CMF Phone 1", "CMF Phone 1", "Nothing", "device_list_full_import"); // Device_List:L2611
        put(m, "A001", "CMF Phone 2 Pro", "CMF Phone 2 Pro", "Nothing", "device_list_full_import"); // Device_List:L2612
        put(m, "NX501", "nubia Z5", "nubia Z5", "nubia", "device_list_full_import"); // Device_List:L2613
        put(m, "NX402", "nubia Z5 mini", "nubia Z5 mini", "nubia", "device_list_full_import"); // Device_List:L2614
        put(m, "NX503J", "nubia Z5S", "nubia Z5S", "nubia", "device_list_full_import"); // Device_List:L2615
        put(m, "NX403A", "nubia Z5S mini", "nubia Z5S mini", "nubia", "device_list_full_import"); // Device_List:L2616
        put(m, "NX506J", "nubia Z7", "nubia Z7", "nubia", "device_list_full_import"); // Device_List:L2617
        put(m, "NX507J", "nubia Z7 mini 全網通版", "nubia Z7 mini 全網通版", "nubia", "device_list_full_import"); // Device_List:L2618
        put(m, "NX507H", "nubia Z7 mini 雙 4G 版", "nubia Z7 mini 雙 4G 版", "nubia", "device_list_full_import"); // Device_List:L2619
        put(m, "NX505J", "nubia Z7 Max 全網通版", "nubia Z7 Max 全網通版", "nubia", "device_list_full_import"); // Device_List:L2620
        put(m, "NX505H", "nubia Z7 Max 雙 4G 版", "nubia Z7 Max 雙 4G 版", "nubia", "device_list_full_import"); // Device_List:L2621
        put(m, "NX508J", "nubia Z9 全網通版", "nubia Z9 全網通版", "nubia", "device_list_full_import"); // Device_List:L2622
        put(m, "NX508H", "nubia Z9 雙 4G 版", "nubia Z9 雙 4G 版", "nubia", "device_list_full_import"); // Device_List:L2623
        put(m, "NX511J", "nubia Z9 mini 全網通版", "nubia Z9 mini 全網通版", "nubia", "device_list_full_import"); // Device_List:L2624
        put(m, "NX511H", "nubia Z9 mini 雙 4G 版", "nubia Z9 mini 雙 4G 版", "nubia", "device_list_full_import"); // Device_List:L2625
        put(m, "NX510J", "nubia Z9 Max 全網通版", "nubia Z9 Max 全網通版", "nubia", "device_list_full_import"); // Device_List:L2626
        put(m, "NX512H", "nubia Z9 Max 雙 4G 版", "nubia Z9 Max 雙 4G 版", "nubia", "device_list_full_import"); // Device_List:L2627
        put(m, "NX512J", "nubia Z9 Max 極速版", "nubia Z9 Max 極速版", "nubia", "device_list_full_import"); // Device_List:L2628
        put(m, "NX518J", "nubia Z9 Max 精英版", "nubia Z9 Max 精英版", "nubia", "device_list_full_import"); // Device_List:L2629
        put(m, "NX531J", "nubia Z11", "nubia Z11", "nubia", "device_list_full_import"); // Device_List:L2630
        put(m, "NX529J", "nubia Z11 mini", "nubia Z11 mini", "nubia", "device_list_full_import"); // Device_List:L2631
        put(m, "NX523J", "nubia Z11 Max", "nubia Z11 Max", "nubia", "device_list_full_import"); // Device_List:L2632
        put(m, "NX535J", "nubia Z11 Max 經典版", "nubia Z11 Max 經典版", "nubia", "device_list_full_import"); // Device_List:L2633
        put(m, "NX549J", "nubia Z11 miniS", "nubia Z11 miniS", "nubia", "device_list_full_import"); // Device_List:L2634
        put(m, "NX563J", "nubia Z17", "nubia Z17", "nubia", "device_list_full_import"); // Device_List:L2635
        put(m, "NX591J", "nubia Z17 暢享版", "nubia Z17 暢享版", "nubia", "device_list_full_import"); // Device_List:L2636
        put(m, "NX569J", "nubia Z17 mini 標準版", "nubia Z17 mini 標準版", "nubia", "device_list_full_import"); // Device_List:L2637
        put(m, "NX569H", "nubia Z17 mini 高配版", "nubia Z17 mini 高配版", "nubia", "device_list_full_import"); // Device_List:L2638
        put(m, "NX595J", "nubia Z17S", "nubia Z17S", "nubia", "device_list_full_import"); // Device_List:L2639
        put(m, "NX589J", "nubia Z17 miniS", "nubia Z17 miniS", "nubia", "device_list_full_import"); // Device_List:L2640
        put(m, "NX606J", "nubia Z18", "nubia Z18", "nubia", "device_list_full_import"); // Device_List:L2641
        put(m, "NX611J", "nubia Z18 mini", "nubia Z18 mini", "nubia", "device_list_full_import"); // Device_List:L2642
        put(m, "NX627J", "nubia Z20", "nubia Z20", "nubia", "device_list_full_import"); // Device_List:L2643
        put(m, "NX667J", "nubia Z30 Pro", "nubia Z30 Pro", "nubia", "device_list_full_import"); // Device_List:L2644
        put(m, "NX701J", "nubia Z40 Pro", "nubia Z40 Pro", "nubia", "device_list_full_import"); // Device_List:L2645
        put(m, "NX702J", "nubia Z40S Pro", "nubia Z40S Pro", "nubia", "device_list_full_import"); // Device_List:L2646
        put(m, "NX711J", "nubia Z50 / nubia Z50S", "nubia Z50 / nubia Z50S", "nubia", "device_list_full_import"); // Device_List:L2647
        put(m, "NX712J", "nubia Z50 Ultra", "nubia Z50 Ultra", "nubia", "device_list_full_import"); // Device_List:L2648
        put(m, "NX713J", "nubia Z50S Pro", "nubia Z50S Pro", "nubia", "device_list_full_import"); // Device_List:L2649
        put(m, "NX715J", "nubia Z50 SE", "nubia Z50 SE", "nubia", "device_list_full_import"); // Device_List:L2650
        put(m, "NX721J", "nubia Z60 Ultra / nubia Z60 Ultra 領先版", "nubia Z60 Ultra / nubia Z60 Ultra 領先版", "nubia", "device_list_full_import"); // Device_List:L2651
        put(m, "NX725J", "nubia Z60S Pro", "nubia Z60S Pro", "nubia", "device_list_full_import"); // Device_List:L2652
        put(m, "NX733J", "nubia Z70 Ultra", "nubia Z70 Ultra", "nubia", "device_list_full_import"); // Device_List:L2653
        put(m, "NX736J", "nubia Z70 Ultra 星空典藏版 (衛星通信)", "nubia Z70 Ultra 星空典藏版 (衛星通信)", "nubia", "device_list_full_import"); // Device_List:L2654
        put(m, "NX737J", "nubia Z70S Ultra 攝影師版", "nubia Z70S Ultra 攝影師版", "nubia", "device_list_full_import"); // Device_List:L2655
        put(m, "NX741J", "nubia Z80 Ultra", "nubia Z80 Ultra", "nubia", "device_list_full_import"); // Device_List:L2656
        put(m, "NX601J", "nubia X6", "nubia X6", "nubia", "device_list_full_import"); // Device_List:L2657
        put(m, "NX616J", "nubia X", "nubia X", "nubia", "device_list_full_import"); // Device_List:L2658
        put(m, "NX612J", "nubia V18", "nubia V18", "nubia", "device_list_full_import"); // Device_List:L2659
        put(m, "NX651J", "nubia Play", "nubia Play", "nubia", "device_list_full_import"); // Device_List:L2660
        put(m, "NX724J", "nubia Flip 5G / nubia Flip 5G S", "nubia Flip 5G / nubia Flip 5G S", "nubia", "device_list_full_import"); // Device_List:L2661
        put(m, "NX732J", "nubia Flip 2 國行版", "nubia Flip 2 國行版", "nubia", "device_list_full_import"); // Device_List:L2662
        put(m, "A404ZT", "nubia Flip 2 SoftBank", "nubia Flip 2 SoftBank", "nubia", "device_list_full_import"); // Device_List:L2663
        put(m, "Z8900CA", "nubia Flip 2 eSIM", "nubia Flip 2 eSIM", "nubia", "device_list_full_import"); // Device_List:L2664
        put(m, "NX302J", "nubia 小牛", "nubia 小牛", "nubia", "device_list_full_import"); // Device_List:L2665
        put(m, "NX513J", "nubia My 布拉格 全網通版", "nubia My 布拉格 全網通版", "nubia", "device_list_full_import"); // Device_List:L2666
        put(m, "NX513H", "nubia My 布拉格 雙 4G 版", "nubia My 布拉格 雙 4G 版", "nubia", "device_list_full_import"); // Device_List:L2667
        put(m, "NX551J", "nubia M2", "nubia M2", "nubia", "device_list_full_import"); // Device_List:L2668
        put(m, "NX573J", "nubia M2 青春版", "nubia M2 青春版", "nubia", "device_list_full_import"); // Device_List:L2669
        put(m, "NX907J", "nubia M2 暢玩版", "nubia M2 暢玩版", "nubia", "device_list_full_import"); // Device_List:L2670
        put(m, "P0110", "nubia M153 豆包手機助手技術預覽版", "nubia M153 豆包手機助手技術預覽版", "nubia", "device_list_full_import"); // Device_List:L2671
        put(m, "NX541J", "nubia N1", "nubia N1", "nubia", "device_list_full_import"); // Device_List:L2672
        put(m, "NX575J", "nubia N2", "nubia N2", "nubia", "device_list_full_import"); // Device_List:L2673
        put(m, "NX617J", "nubia N3", "nubia N3", "nubia", "device_list_full_import"); // Device_List:L2674
        put(m, "NX301J", "nubia N5", "nubia N5", "nubia", "device_list_full_import"); // Device_List:L2675
        put(m, "nubia 8150N", "nubia Neo 5G", "nubia Neo 5G", "nubia", "device_list_full_import"); // Device_List:L2676
        put(m, "Z2352N", "nubia Neo 2 5G", "nubia Neo 2 5G", "nubia", "device_list_full_import"); // Device_List:L2677
        put(m, "Z2461", "nubia Neo 3", "nubia Neo 3", "nubia", "device_list_full_import"); // Device_List:L2678
        put(m, "Z2464N", "nubia Neo 3 5G", "nubia Neo 3 5G", "nubia", "device_list_full_import"); // Device_List:L2679
        put(m, "Z2465N", "nubia Neo 3 GT 5G", "nubia Neo 3 GT 5G", "nubia", "device_list_full_import"); // Device_List:L2680
        put(m, "Z2571N", "nubia Neo 5 5G", "nubia Neo 5 5G", "nubia", "device_list_full_import"); // Device_List:L2681
        put(m, "Z2570N", "nubia Neo 5 GT 5G", "nubia Neo 5 GT 5G", "nubia", "device_list_full_import"); // Device_List:L2682
        put(m, "Z2353", "nubia Music", "nubia Music", "nubia", "device_list_full_import"); // Device_List:L2683
        put(m, "Z2460", "nubia Music 2 / nubia Music Pro", "nubia Music 2 / nubia Music Pro", "nubia", "device_list_full_import"); // Device_List:L2684
        put(m, "Z2455", "nubia Focus", "nubia Focus", "nubia", "device_list_full_import"); // Device_List:L2685
        put(m, "Z2462N", "nubia Focus 2 5G", "nubia Focus 2 5G", "nubia", "device_list_full_import"); // Device_List:L2686
        put(m, "Z2463N", "nubia Focus 2 Ultra 5G", "nubia Focus 2 Ultra 5G", "nubia", "device_list_full_import"); // Device_List:L2687
        put(m, "A502ZT", "nubia Fold SoftBank", "nubia Fold SoftBank", "nubia", "device_list_full_import"); // Device_List:L2688
        put(m, "Z2468N", "nubia Air", "nubia Air", "nubia", "device_list_full_import"); // Device_List:L2689
        put(m, "Z2473", "nubia A56", "nubia A56", "nubia", "device_list_full_import"); // Device_List:L2690
        put(m, "Z6255CA", "nubia A75", "nubia A75", "nubia", "device_list_full_import"); // Device_List:L2691
        put(m, "Z6657CA", "nubia A76", "nubia A76", "nubia", "device_list_full_import"); // Device_List:L2692
        put(m, "Z2469N", "nubia A76 5G", "nubia A76 5G", "nubia", "device_list_full_import"); // Device_List:L2693
        put(m, "nubia 8550", "nubia V50 Vita", "nubia V50 Vita", "nubia", "device_list_full_import"); // Device_List:L2694
        put(m, "Z2356", "nubia V60", "nubia V60", "nubia", "device_list_full_import"); // Device_List:L2695
        put(m, "Z2350", "nubia V60 Design", "nubia V60 Design", "nubia", "device_list_full_import"); // Device_List:L2696
        put(m, "Z2459", "nubia V70", "nubia V70", "nubia", "device_list_full_import"); // Device_List:L2697
        put(m, "Z2458", "nubia V70 Design", "nubia V70 Design", "nubia", "device_list_full_import"); // Device_List:L2698
        put(m, "Z2467", "nubia V70 Max", "nubia V70 Max", "nubia", "device_list_full_import"); // Device_List:L2699
        put(m, "A403ZT", "nubia S 5G SoftBank", "nubia S 5G SoftBank", "nubia", "device_list_full_import"); // Device_List:L2700
        put(m, "A507ZT", "nubia S2e SoftBank", "nubia S2e SoftBank", "nubia", "device_list_full_import"); // Device_List:L2701
        put(m, "Z6305R", "nubia S2R", "nubia S2R", "nubia", "device_list_full_import"); // Device_List:L2702
        put(m, "LPD-20W", "nubia Pad 3D", "nubia Pad 3D", "nubia", "device_list_full_import"); // Device_List:L2703
        put(m, "NP02J", "nubia Pad 3D II", "nubia Pad 3D II", "nubia", "device_list_full_import"); // Device_List:L2704
    }

    private static void fill15(Map<String, Entry> m) {
        put(m, "K99J", "nubia Pad SE", "nubia Pad SE", "nubia", "device_list_full_import"); // Device_List:L2705
        put(m, "NT01", "nubia Pad Pro", "nubia Pad Pro", "nubia", "device_list_full_import"); // Device_List:L2706
        put(m, "NX609J", "紅魔電競遊戲手機", "紅魔電競遊戲手機", "", "device_list_full_import"); // Device_List:L2707
        put(m, "NX619J", "紅魔 Mars 電競手機", "紅魔 Mars 電競手機", "", "device_list_full_import"); // Device_List:L2708
        put(m, "NX629J", "紅魔 3", "紅魔 3", "", "device_list_full_import"); // Device_List:L2709
        put(m, "NX659J", "紅魔 5G", "紅魔 5G", "", "device_list_full_import"); // Device_List:L2710
        put(m, "NX669J", "騰訊紅魔遊戲手機 6", "騰訊紅魔遊戲手機 6", "", "device_list_full_import"); // Device_List:L2711
        put(m, "NX669J-P", "騰訊紅魔遊戲手機 6 Pro", "騰訊紅魔遊戲手機 6 Pro", "", "device_list_full_import"); // Device_List:L2712
        put(m, "NX666J", "騰訊紅魔遊戲手機 6R", "騰訊紅魔遊戲手機 6R", "", "device_list_full_import"); // Device_List:L2713
        put(m, "NX669J-S", "騰訊紅魔遊戲手機 6S Pro", "騰訊紅魔遊戲手機 6S Pro", "", "device_list_full_import"); // Device_List:L2714
        put(m, "NX679J", "紅魔 7", "紅魔 7", "", "device_list_full_import"); // Device_List:L2715
        put(m, "NX709J", "紅魔 7 Pro", "紅魔 7 Pro", "", "device_list_full_import"); // Device_List:L2716
        put(m, "NX679S", "紅魔 7S", "紅魔 7S", "", "device_list_full_import"); // Device_List:L2717
        put(m, "NX709S", "紅魔 7S Pro", "紅魔 7S Pro", "", "device_list_full_import"); // Device_List:L2718
        put(m, "NX729J", "紅魔 8 Pro / 紅魔 8 Pro+", "紅魔 8 Pro / 紅魔 8 Pro+", "", "device_list_full_import"); // Device_List:L2719
        put(m, "NX729S", "紅魔 8S Pro / 紅魔 8S Pro+", "紅魔 8S Pro / 紅魔 8S Pro+", "", "device_list_full_import"); // Device_List:L2720
        put(m, "NX769J", "紅魔 9 Pro / 紅魔 9 Pro+", "紅魔 9 Pro / 紅魔 9 Pro+", "", "device_list_full_import"); // Device_List:L2721
        put(m, "NX789J", "紅魔 10 Pro / 紅魔 10 Pro+", "紅魔 10 Pro / 紅魔 10 Pro+", "", "device_list_full_import"); // Device_List:L2722
        put(m, "NX779J", "紅魔 10 Air", "紅魔 10 Air", "", "device_list_full_import"); // Device_List:L2723
        put(m, "NX809J", "紅魔 11 Pro / 紅魔 11 Pro+", "紅魔 11 Pro / 紅魔 11 Pro+", "", "device_list_full_import"); // Device_List:L2724
        put(m, "NX799J", "紅魔 11 Air", "紅魔 11 Air", "", "device_list_full_import"); // Device_List:L2725
        put(m, "NP01J", "紅魔電競平板 5G", "紅魔電競平板 5G", "", "device_list_full_import"); // Device_List:L2726
        put(m, "NP03J", "紅魔電競平板 Pro", "紅魔電競平板 Pro", "", "device_list_full_import"); // Device_List:L2727
        put(m, "NP05J", "紅魔電競平板 3 Pro", "紅魔電競平板 3 Pro", "", "device_list_full_import"); // Device_List:L2728
        put(m, "NP06J", "紅魔遊戲平板 5 Pro", "紅魔遊戲平板 5 Pro", "", "device_list_full_import"); // Device_List:L2729
        put(m, "ONE A0001", "一加手機 全網通版 / 移動版 / 國際版", "一加手機 全網通版 / 移動版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2730
        put(m, "ONE A1001", "一加手機 聯通版", "一加手機 聯通版", "OnePlus", "device_list_full_import"); // Device_List:L2731
        put(m, "ONE A2001", "一加手機 2", "一加手機 2", "OnePlus", "device_list_full_import"); // Device_List:L2732
        put(m, "ONE A2003", "一加手機 2 國際版", "一加手機 2 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2733
        put(m, "ONE A2005", "一加手機 2 北美版", "一加手機 2 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2734
        put(m, "ONE E1000", "一加手機 X 全網通版", "一加手機 X 全網通版", "OnePlus", "device_list_full_import"); // Device_List:L2735
        put(m, "ONE E1001", "一加手機 X 移動版 / 聯通版", "一加手機 X 移動版 / 聯通版", "OnePlus", "device_list_full_import"); // Device_List:L2736
        put(m, "ONE E1003", "一加手機 X 國際版", "一加手機 X 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2737
        put(m, "ONE E1005", "一加手機 X 北美版", "一加手機 X 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2738
        put(m, "ONEPLUS A3000", "一加手機 3 國行版", "一加手機 3 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2739
        put(m, "ONEPLUS A3003", "一加手機 3 國際版", "一加手機 3 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2740
        put(m, "ONEPLUS A3010", "一加手機 3T 國行版", "一加手機 3T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2741
        put(m, "ONEPLUS A3013", "一加手機 3T 國際版", "一加手機 3T 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2742
        put(m, "ONEPLUS A5000", "一加 5", "一加 5", "OnePlus", "device_list_full_import"); // Device_List:L2743
        put(m, "ONEPLUS A5010", "一加 5T", "一加 5T", "OnePlus", "device_list_full_import"); // Device_List:L2744
        put(m, "ONEPLUS A6000", "一加 6 國行版", "一加 6 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2745
        put(m, "ONEPLUS A6003", "一加 6 國際版", "一加 6 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2746
        put(m, "ONEPLUS A6010", "一加 6T 國行版", "一加 6T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2747
        put(m, "ONEPLUS A6013", "一加 6T 國際版", "一加 6T 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2748
        put(m, "GM1900", "一加 7 國行版", "一加 7 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2749
        put(m, "GM1901", "一加 7 印度版", "一加 7 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2750
        put(m, "GM1903", "一加 7 歐洲版", "一加 7 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2751
        put(m, "GM1905", "一加 7 北美版 / 國際版", "一加 7 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2752
        put(m, "GM1910", "一加 7 Pro 國行版", "一加 7 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2753
        put(m, "GM1911", "一加 7 Pro 印度版", "一加 7 Pro 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2754
        put(m, "GM1913", "一加 7 Pro 歐洲版", "一加 7 Pro 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2755
        put(m, "GM1915", "一加 7 Pro 北美版 / 國際版", "一加 7 Pro 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2756
        put(m, "GM1917", "一加 7 Pro T-Mobile 版", "一加 7 Pro T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2757
        put(m, "GM1920", "一加 7 Pro 5G 歐洲版", "一加 7 Pro 5G 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2758
        put(m, "GM1925", "一加 7 Pro 5G Sprint 版", "一加 7 Pro 5G Sprint 版", "OnePlus", "device_list_full_import"); // Device_List:L2759
        put(m, "HD1900", "一加 7T 國行版", "一加 7T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2760
        put(m, "HD1901", "一加 7T 印度版", "一加 7T 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2761
        put(m, "HD1903", "一加 7T 歐洲版", "一加 7T 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2762
        put(m, "HD1905", "一加 7T 北美版 / 國際版", "一加 7T 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2763
        put(m, "HD1907", "一加 7T T-Mobile 版", "一加 7T T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2764
        put(m, "HD1910", "一加 7T Pro 國行版", "一加 7T Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2765
        put(m, "HD1911", "一加 7T Pro 印度版", "一加 7T Pro 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2766
        put(m, "HD1913", "一加 7T Pro 歐洲版 / 國際版", "一加 7T Pro 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2767
        put(m, "HD1925", "一加 7T Pro 5G T-Mobile 版 / 一加 Concept One", "一加 7T Pro 5G T-Mobile 版 / 一加 Concept One", "OnePlus", "device_list_full_import"); // Device_List:L2768
        put(m, "IN2010", "一加 8 國行版", "一加 8 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2769
        put(m, "IN2011", "一加 8 印度版", "一加 8 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2770
        put(m, "IN2013", "一加 8 歐洲版", "一加 8 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2771
        put(m, "IN2015", "一加 8 北美版 / 國際版", "一加 8 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2772
        put(m, "IN2017", "一加 8 T-Mobile 版", "一加 8 T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2773
        put(m, "IN2019", "一加 8 Visible 版 / Verizon 版", "一加 8 Visible 版 / Verizon 版", "OnePlus", "device_list_full_import"); // Device_List:L2774
        put(m, "IN2020", "一加 8 Pro 國行版", "一加 8 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2775
        put(m, "IN2021", "一加 8 Pro 印度版", "一加 8 Pro 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2776
        put(m, "IN2023", "一加 8 Pro 歐洲版", "一加 8 Pro 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2777
        put(m, "IN2025", "一加 8 Pro 北美版 / 國際版", "一加 8 Pro 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2778
        put(m, "KB2000", "一加 8T 國行版", "一加 8T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2779
        put(m, "KB2001", "一加 8T 印度版", "一加 8T 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2780
        put(m, "KB2003", "一加 8T 歐洲版", "一加 8T 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2781
        put(m, "KB2005", "一加 8T 北美版 / 國際版 / 一加 8T Concept", "一加 8T 北美版 / 國際版 / 一加 8T Concept", "OnePlus", "device_list_full_import"); // Device_List:L2782
        put(m, "KB2007", "一加 8T+ T-Mobile 版", "一加 8T+ T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2783
        put(m, "LE2100", "一加 9R 國行版", "一加 9R 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2784
        put(m, "LE2101", "一加 9R 印度版", "一加 9R 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2785
        put(m, "LE2110", "一加 9 國行版", "一加 9 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2786
        put(m, "LE2111", "一加 9 印度版", "一加 9 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2787
        put(m, "LE2113", "一加 9 歐洲版", "一加 9 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2788
        put(m, "LE2115", "一加 9 北美版 / 國際版", "一加 9 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2789
        put(m, "LE2117", "一加 9 T-Mobile 版", "一加 9 T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2790
        put(m, "LE2119", "一加 9 Verzion 版", "一加 9 Verzion 版", "OnePlus", "device_list_full_import"); // Device_List:L2791
        put(m, "LE2120", "一加 9 Pro 國行版", "一加 9 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2792
        put(m, "LE2121", "一加 9 Pro 印度版", "一加 9 Pro 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2793
        put(m, "LE2123", "一加 9 Pro 歐洲版", "一加 9 Pro 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2794
        put(m, "LE2125", "一加 9 Pro 北美版 / 國際版", "一加 9 Pro 北美版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2795
        put(m, "LE2127", "一加 9 Pro T-Mobile 版", "一加 9 Pro T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2796
        put(m, "MT2110", "一加 9RT 國行版", "一加 9RT 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2797
        put(m, "MT2111", "一加 9RT 印度版", "一加 9RT 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2798
        put(m, "NE2210", "一加 10 Pro 國行版", "一加 10 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2799
        put(m, "NE2211", "一加 10 Pro 印度版", "一加 10 Pro 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2800
        put(m, "NE2213", "一加 10 Pro 歐洲版 / 國際版", "一加 10 Pro 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2801
        put(m, "NE2215", "一加 10 Pro 北美版", "一加 10 Pro 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2802
        put(m, "NE2217", "一加 10 Pro T-Mobile 版", "一加 10 Pro T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2803
        put(m, "PGKM10", "一加 Ace 國行版", "一加 Ace 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2804
        put(m, "CPH2423", "一加 10R 印度版", "一加 10R 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2805
        put(m, "CPH2411", "一加 10R 長壽版 印度版", "一加 10R 長壽版 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2806
        put(m, "PGZ110", "一加 Ace 競速版 國行版", "一加 Ace 競速版 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2807
        put(m, "PGP110", "一加 Ace Pro 國行版 / 原神限定版", "一加 Ace Pro 國行版 / 原神限定版", "OnePlus", "device_list_full_import"); // Device_List:L2808
        put(m, "CPH2413", "一加 10T 印度版", "一加 10T 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2809
        put(m, "CPH2415", "一加 10T 歐洲版 / 國際版", "一加 10T 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2810
        put(m, "CPH2417", "一加 10T 北美版", "一加 10T 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2811
        put(m, "CPH2419", "一加 10T T-Mobile 版", "一加 10T T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2812
        put(m, "PHB110", "一加 11 國行版", "一加 11 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2813
        put(m, "CPH2447", "一加 11 印度版", "一加 11 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2814
        put(m, "CPH2449", "一加 11 歐洲版 / 國際版 / 一加 11 Concept", "一加 11 歐洲版 / 國際版 / 一加 11 Concept", "OnePlus", "device_list_full_import"); // Device_List:L2815
        put(m, "CPH2451", "一加 11 北美版", "一加 11 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2816
        put(m, "PHK110", "一加 Ace 2 國行版 / 原神定制禮盒", "一加 Ace 2 國行版 / 原神定制禮盒", "OnePlus", "device_list_full_import"); // Device_List:L2817
        put(m, "CPH2487", "一加 11R 印度版", "一加 11R 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2818
        put(m, "PHP110", "一加 Ace 2V 國行版", "一加 Ace 2V 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2819
        put(m, "CPH2491", "一加 Nord 3 印度版", "一加 Nord 3 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2820
        put(m, "CPH2493", "一加 Nord 3 歐洲版", "一加 Nord 3 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2821
        put(m, "PJA110", "一加 Ace 2 Pro 國行版 / 原神派蒙主題禮盒", "一加 Ace 2 Pro 國行版 / 原神派蒙主題禮盒", "OnePlus", "device_list_full_import"); // Device_List:L2822
        put(m, "PJD110", "一加 12 國行版", "一加 12 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2823
        put(m, "CPH2573", "一加 12 印度版", "一加 12 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2824
        put(m, "CPH2581", "一加 12 歐洲版 / 國際版", "一加 12 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2825
        put(m, "CPH2583", "一加 12 北美版", "一加 12 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2826
        put(m, "PJE110", "一加 Ace 3 國行版 / 原神刻晴定制機", "一加 Ace 3 國行版 / 原神刻晴定制機", "OnePlus", "device_list_full_import"); // Device_List:L2827
        put(m, "CPH2585", "一加 12R 印度版 / 原神刻晴定制機", "一加 12R 印度版 / 原神刻晴定制機", "OnePlus", "device_list_full_import"); // Device_List:L2828
        put(m, "CPH2609", "一加 12R 歐洲版 / 國際版 / 原神刻晴定制機", "一加 12R 歐洲版 / 國際版 / 原神刻晴定制機", "OnePlus", "device_list_full_import"); // Device_List:L2829
        put(m, "CPH2611", "一加 12R 北美版 / 原神刻晴定制機", "一加 12R 北美版 / 原神刻晴定制機", "OnePlus", "device_list_full_import"); // Device_List:L2830
        put(m, "PJF110", "一加 Ace 3V 國行版", "一加 Ace 3V 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2831
        put(m, "PJX110", "一加 Ace 3 Pro 國行版", "一加 Ace 3 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2832
        put(m, "PJZ110", "一加 13 國行版", "一加 13 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2833
        put(m, "CPH2649", "一加 13 印度版", "一加 13 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2834
        put(m, "CPH2653", "一加 13 歐洲版 / 國際版", "一加 13 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2835
        put(m, "CPH2655", "一加 13 北美版", "一加 13 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2836
        put(m, "PKG110", "一加 Ace 5 國行版", "一加 Ace 5 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2837
        put(m, "CPH2645", "一加 13R 歐洲版 / 國際版", "一加 13R 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2838
        put(m, "CPH2647", "一加 13R 北美版", "一加 13R 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2839
        put(m, "CPH2691", "一加 13R 印度版", "一加 13R 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2840
        put(m, "PKR110", "一加 Ace 5 Pro 國行版", "一加 Ace 5 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2841
        put(m, "PKX110", "一加 13T 國行版", "一加 13T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2842
        put(m, "CPH2723", "一加 13s 印度版", "一加 13s 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2843
        put(m, "PLC110", "一加 Ace 5 至尊版 國行版", "一加 Ace 5 至尊版 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2844
        put(m, "PLF110", "一加 Ace 5 競速版 國行版", "一加 Ace 5 競速版 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2845
        put(m, "PLK110", "一加 15 國行版", "一加 15 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2846
        put(m, "CPH2745", "一加 15 印度版", "一加 15 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2847
        put(m, "CPH2747", "一加 15 歐洲版 / 國際版", "一加 15 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2848
        put(m, "CPH2749", "一加 15 北美版", "一加 15 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2849
        put(m, "PLQ110", "一加 Ace 6 國行版", "一加 Ace 6 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2850
        put(m, "PLR110", "一加 Ace 6T 國行版", "一加 Ace 6T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2851
        put(m, "CPH2767", "一加 15R 印度版", "一加 15R 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2852
        put(m, "CPH2769", "一加 15R 歐洲版 / 國際版", "一加 15R 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2853
        put(m, "CPH2771", "一加 15R 北美版", "一加 15R 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2854
        put(m, "PLZ110", "一加 15T 國行版", "一加 15T 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2855
        put(m, "PMB110", "一加 Ace 6 至尊版 國行版", "一加 Ace 6 至尊版 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2856
        put(m, "PLU110", "一加 Turbo 6 國行版", "一加 Turbo 6 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2857
        put(m, "CPH2793", "一加 Nord 6 印度版", "一加 Nord 6 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2858
        put(m, "CPH2795", "一加 Nord 6 國際版", "一加 Nord 6 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2859
        put(m, "PLY110", "一加 Turbo 6V 國行版", "一加 Turbo 6V 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2860
        put(m, "CPH2805", "一加 Nord CE 6 印度版", "一加 Nord CE 6 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2861
        put(m, "CPH2807", "一加 Nord CE 6 國際版", "一加 Nord CE 6 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2862
        put(m, "PYS110", "一加 Turbo 6X 國行版", "一加 Turbo 6X 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2863
        put(m, "PYR110", "一加 Turbo 6X Pro 國行版", "一加 Turbo 6X Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2864
        put(m, "AC2001", "一加 Nord 印度版", "一加 Nord 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2865
        put(m, "AC2003", "一加 Nord 歐洲版 / 國際版", "一加 Nord 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2866
        put(m, "DN2101", "一加 Nord 2 印度版", "一加 Nord 2 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2867
        put(m, "DN2103", "一加 Nord 2 歐洲版", "一加 Nord 2 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2868
        put(m, "CPH2399", "一加 Nord 2T 國際版", "一加 Nord 2T 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2869
        put(m, "CPH2401", "一加 Nord 2T 印度版", "一加 Nord 2T 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2870
        put(m, "CPH2661", "一加 Nord 4 印度版", "一加 Nord 4 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2871
        put(m, "CPH2663", "一加 Nord 4 歐洲版 / 國際版", "一加 Nord 4 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2872
        put(m, "CPH2707", "一加 Nord 5 印度版", "一加 Nord 5 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2873
        put(m, "CPH2709", "一加 Nord 5 國際版", "一加 Nord 5 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2874
        put(m, "EB2101", "一加 Nord CE 印度版", "一加 Nord CE 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2875
        put(m, "EB2103", "一加 Nord CE 歐洲版 / 國際版", "一加 Nord CE 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2876
        put(m, "IV2201", "一加 Nord CE 2 印度版", "一加 Nord CE 2 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2877
        put(m, "CPH2381", "一加 Nord CE 2 Lite 印度版", "一加 Nord CE 2 Lite 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2878
        put(m, "CPH2409", "一加 Nord CE 2 Lite 歐洲版 / 國際版", "一加 Nord CE 2 Lite 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2879
        put(m, "CPH2569", "一加 Nord CE 3 印度版", "一加 Nord CE 3 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2880
        put(m, "CPH2465", "一加 Nord CE 3 Lite 國際版", "一加 Nord CE 3 Lite 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2881
        put(m, "CPH2467", "一加 Nord CE 3 Lite 印度版", "一加 Nord CE 3 Lite 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2882
        put(m, "CPH2513", "一加 Nord N30 北美版", "一加 Nord N30 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2883
        put(m, "CPH2515", "一加 Nord N30 T-Mobile 版", "一加 Nord N30 T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2884
    }

    private static void fill16(Map<String, Entry> m) {
        put(m, "CPH2613", "一加 Nord CE 4 印度版", "一加 Nord CE 4 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2885
        put(m, "CPH2619", "一加 Nord CE 4 Lite 印度版", "一加 Nord CE 4 Lite 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2886
        put(m, "CPH2621", "一加 Nord CE 4 Lite 歐洲版 / 國際版", "一加 Nord CE 4 Lite 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2887
        put(m, "CPH2717", "一加 Nord CE 5 印度版", "一加 Nord CE 5 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2888
        put(m, "CPH2719", "一加 Nord CE 5 國際版", "一加 Nord CE 5 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2889
        put(m, "CPH2943", "一加 Nord CE 6 Lite 印度版", "一加 Nord CE 6 Lite 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2890
        put(m, "CPH2955", "一加 N6 印度版", "一加 N6 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2891
        put(m, "BE2025", "一加 Nord N10 Metro 版", "一加 Nord N10 Metro 版", "OnePlus", "device_list_full_import"); // Device_List:L2892
        put(m, "BE2026", "一加 Nord N10 北美版", "一加 Nord N10 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2893
        put(m, "BE2029", "一加 Nord N10 歐洲版 / 國際版", "一加 Nord N10 歐洲版 / 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2894
        put(m, "BE2028", "一加 Nord N10 T-Mobile 版", "一加 Nord N10 T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2895
        put(m, "BE2011", "一加 Nord N100 北美版", "一加 Nord N100 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2896
        put(m, "BE2012", "一加 Nord N100 T-Mobile 版", "一加 Nord N100 T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2897
        put(m, "BE2013", "一加 Nord N100 國際版", "一加 Nord N100 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2898
        put(m, "BE2015", "一加 Nord N100 Metro 版", "一加 Nord N100 Metro 版", "OnePlus", "device_list_full_import"); // Device_List:L2899
        put(m, "GN2200", "一加 Nord N20", "一加 Nord N20", "OnePlus", "device_list_full_import"); // Device_List:L2900
        put(m, "CPH2459", "一加 Nord N20", "一加 Nord N20", "OnePlus", "device_list_full_import"); // Device_List:L2901
        put(m, "CPH2469", "一加 Nord N20 SE", "一加 Nord N20 SE", "OnePlus", "device_list_full_import"); // Device_List:L2902
        put(m, "CPH2605", "一加 Nord N30 SE 歐洲版", "一加 Nord N30 SE 歐洲版", "OnePlus", "device_list_full_import"); // Device_List:L2903
        put(m, "DE2117", "一加 Nord N200 北美版", "一加 Nord N200 北美版", "OnePlus", "device_list_full_import"); // Device_List:L2904
        put(m, "DE2118", "一加 Nord N200 T-Mobile 版", "一加 Nord N200 T-Mobile 版", "OnePlus", "device_list_full_import"); // Device_List:L2905
        put(m, "CPH2389", "一加 Nord N300", "一加 Nord N300", "OnePlus", "device_list_full_import"); // Device_List:L2906
        put(m, "CPH2551", "一加 Open", "一加 Open", "OnePlus", "device_list_full_import"); // Device_List:L2907
        put(m, "OPD2203", "一加平板 (2023) 國際版", "一加平板 (2023) 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2908
        put(m, "OPD2304", "一加平板 Go LTE", "一加平板 Go LTE", "OnePlus", "device_list_full_import"); // Device_List:L2909
        put(m, "OPD2305", "一加平板 Go Wi-Fi", "一加平板 Go Wi-Fi", "OnePlus", "device_list_full_import"); // Device_List:L2910
        put(m, "OPD2407", "一加平板 (2024) 國行版", "一加平板 (2024) 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2911
        put(m, "OPD2404", "一加平板 Pro 國行版", "一加平板 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2912
        put(m, "OPD2403", "一加平板 2 (2024) 國際版", "一加平板 2 (2024) 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2913
        put(m, "OPD2413", "一加平板 2 Pro 國行版", "一加平板 2 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2914
        put(m, "OPD2415", "一加平板 3 國際版", "一加平板 3 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2915
        put(m, "OPD2480", "一加平板 Lite Wi-Fi", "一加平板 Lite Wi-Fi", "OnePlus", "device_list_full_import"); // Device_List:L2916
        put(m, "OPD2481", "一加平板 Lite LTE", "一加平板 Lite LTE", "OnePlus", "device_list_full_import"); // Device_List:L2917
        put(m, "OPD2504", "一加平板 Go 2 Wi-Fi", "一加平板 Go 2 Wi-Fi", "OnePlus", "device_list_full_import"); // Device_List:L2918
        put(m, "OPD2505", "一加平板 Go 2 5G", "一加平板 Go 2 5G", "OnePlus", "device_list_full_import"); // Device_List:L2919
        put(m, "OPD2508", "一加平板 2 (2025) 國行版", "一加平板 2 (2025) 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2920
        put(m, "OPD2513", "一加平板 3 Pro 國行版", "一加平板 3 Pro 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2921
        put(m, "OPD2514", "一加平板 4 國際版", "一加平板 4 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2922
        put(m, "W101IN", "一加 Band 印度版", "一加 Band 印度版", "OnePlus", "device_list_full_import"); // Device_List:L2923
        put(m, "OPBBE221", "一加 Nord Watch", "一加 Nord Watch", "OnePlus", "device_list_full_import"); // Device_List:L2924
        put(m, "W301CN", "一加手表 國行版 / Cyberpunk 2077 限定版", "一加手表 國行版 / Cyberpunk 2077 限定版", "OnePlus", "device_list_full_import"); // Device_List:L2925
        put(m, "W501CN", "一加手表 鈷合金限定版 (國行)", "一加手表 鈷合金限定版 (國行)", "OnePlus", "device_list_full_import"); // Device_List:L2926
        put(m, "W301GB", "一加手表 國際版 / 鈷合金限定版 (國際) / 哈利波特限定版", "一加手表 國際版 / 鈷合金限定版 (國際) / 哈利波特限定版", "OnePlus", "device_list_full_import"); // Device_List:L2927
        put(m, "OPWW234", "一加手表 2 國行版", "一加手表 2 國行版", "OnePlus", "device_list_full_import"); // Device_List:L2928
        put(m, "OPWWE234", "一加手表 2R 國際版", "一加手表 2R 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2929
        put(m, "OPWWE231", "一加手表 2 國際版", "一加手表 2 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2930
        put(m, "OPWW251", "一加手表 3 國行版~", "一加手表 3 國行版~", "OnePlus", "device_list_full_import"); // Device_List:L2931
        put(m, "OPWWE251", "一加手表 3 國際版", "一加手表 3 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2932
        put(m, "OPWE242", "一加手表 3 43mm 國際版", "一加手表 3 43mm 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2933
        put(m, "OPWWE261", "一加手表 4 國際版", "一加手表 4 國際版", "OnePlus", "device_list_full_import"); // Device_List:L2934
        put(m, "E6683", "Xperia Z5 dual", "Xperia Z5 dual", "Sony", "device_list_full_import"); // Device_List:L2935
        put(m, "E6883", "Xperia Z5 Premium", "Xperia Z5 Premium", "Sony", "device_list_full_import"); // Device_List:L2936
        put(m, "F8332", "Xperia XZ", "Xperia XZ", "Sony", "device_list_full_import"); // Device_List:L2937
        put(m, "G8142", "Xperia XZ Premium", "Xperia XZ Premium", "Sony", "device_list_full_import"); // Device_List:L2938
        put(m, "G8232", "Xperia XZs", "Xperia XZs", "Sony", "device_list_full_import"); // Device_List:L2939
        put(m, "G8342", "Xperia XZ1", "Xperia XZ1", "Sony", "device_list_full_import"); // Device_List:L2940
        put(m, "G8441", "Xperia XZ1 Compact", "Xperia XZ1 Compact", "Sony", "device_list_full_import"); // Device_List:L2941
        put(m, "H4233", "Xperia XA2 Ultra", "Xperia XA2 Ultra", "Sony", "device_list_full_import"); // Device_List:L2942
        put(m, "H8296", "Xperia XZ2", "Xperia XZ2", "Sony", "device_list_full_import"); // Device_List:L2943
        put(m, "H8166", "Xperia XZ2 Premium", "Xperia XZ2 Premium", "Sony", "device_list_full_import"); // Device_List:L2944
        put(m, "H9493", "Xperia XZ3", "Xperia XZ3", "Sony", "device_list_full_import"); // Device_List:L2945
        put(m, "J9110", "Xperia 1", "Xperia 1", "Sony", "device_list_full_import"); // Device_List:L2946
        put(m, "J9180", "Xperia 1 Professional Editon", "Xperia 1 Professional Editon", "Sony", "device_list_full_import"); // Device_List:L2947
        put(m, "J9210", "Xperia 5", "Xperia 5", "Sony", "device_list_full_import"); // Device_List:L2948
        put(m, "I4293", "Xperia 10 Plus", "Xperia 10 Plus", "Sony", "device_list_full_import"); // Device_List:L2949
        put(m, "XQ-AT72", "Xperia 1 II", "Xperia 1 II", "Sony", "device_list_full_import"); // Device_List:L2950
        put(m, "XQ-AS72", "Xperia 5 II", "Xperia 5 II", "Sony", "device_list_full_import"); // Device_List:L2951
        put(m, "XQ-BC72", "Xperia 1 III", "Xperia 1 III", "Sony", "device_list_full_import"); // Device_List:L2952
        put(m, "XQ-BQ72", "Xperia 5 III", "Xperia 5 III", "Sony", "device_list_full_import"); // Device_List:L2953
        put(m, "XQ-BE72", "Xperia PRO-I", "Xperia PRO-I", "Sony", "device_list_full_import"); // Device_List:L2954
        put(m, "XQ-CT72", "Xperia 1 IV", "Xperia 1 IV", "Sony", "device_list_full_import"); // Device_List:L2955
        put(m, "XQ-CQ72", "Xperia 5 IV", "Xperia 5 IV", "Sony", "device_list_full_import"); // Device_List:L2956
        put(m, "XQ-DQ72", "Xperia 1 V", "Xperia 1 V", "Sony", "device_list_full_import"); // Device_List:L2957
        put(m, "XQ-DE72", "Xperia 5 V", "Xperia 5 V", "Sony", "device_list_full_import"); // Device_List:L2958
        put(m, "RMX1901", "真我 X", "真我 X", "realme", "device_list_full_import"); // Device_List:L2959
        put(m, "RMX1851", "真我 X 青春版", "真我 X 青春版", "realme", "device_list_full_import"); // Device_List:L2960
        put(m, "RMX1991", "真我 X2", "真我 X2", "realme", "device_list_full_import"); // Device_List:L2961
        put(m, "RMX1931", "真我 X2 Pro", "真我 X2 Pro", "realme", "device_list_full_import"); // Device_List:L2962
        put(m, "RMX2051", "真我 X50 5G 全網通版", "真我 X50 5G 全網通版", "realme", "device_list_full_import"); // Device_List:L2963
        put(m, "RMX2025", "真我 X50 5G 移動版", "真我 X50 5G 移動版", "realme", "device_list_full_import"); // Device_List:L2964
        put(m, "RMX2071", "真我 X50 Pro 5G", "真我 X50 Pro 5G", "realme", "device_list_full_import"); // Device_List:L2965
        put(m, "RMX2072", "真我 X50 Pro 玩家版", "真我 X50 Pro 玩家版", "realme", "device_list_full_import"); // Device_List:L2966
        put(m, "RMX2141", "真我 X50m 5G", "真我 X50m 5G", "realme", "device_list_full_import"); // Device_List:L2967
        put(m, "RMX2142", "真我 X50m 5G 運營商定制版", "真我 X50m 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L2968
        put(m, "RMX2052", "真我 X50t 5G 電信合作版", "真我 X50t 5G 電信合作版", "realme", "device_list_full_import"); // Device_List:L2969
        put(m, "RMX2176", "真我 X7 5G", "真我 X7 5G", "realme", "device_list_full_import"); // Device_List:L2970
        put(m, "RMX2121", "真我 X7 Pro 5G", "真我 X7 Pro 5G", "realme", "device_list_full_import"); // Device_List:L2971
        put(m, "RMX3115", "真我 X7 Pro 至尊版 5G 全網通版", "真我 X7 Pro 至尊版 5G 全網通版", "realme", "device_list_full_import"); // Device_List:L2972
        put(m, "RMX3116", "真我 X7 Pro 至尊版 5G 運營商定制版", "真我 X7 Pro 至尊版 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L2973
        put(m, "RMX2202", "真我 GT 5G", "真我 GT 5G", "realme", "device_list_full_import"); // Device_List:L2974
        put(m, "RMX3361", "真我 GT 大師版", "真我 GT 大師版", "realme", "device_list_full_import"); // Device_List:L2975
        put(m, "RMX3366", "真我 GT 大師探索版", "真我 GT 大師探索版", "realme", "device_list_full_import"); // Device_List:L2976
        put(m, "RMX3310", "真我 GT2", "真我 GT2", "realme", "device_list_full_import"); // Device_List:L2977
        put(m, "RMX3300", "真我 GT2 Pro", "真我 GT2 Pro", "realme", "device_list_full_import"); // Device_List:L2978
        put(m, "RMX3551", "真我 GT2 大師探索版", "真我 GT2 大師探索版", "realme", "device_list_full_import"); // Device_List:L2979
        put(m, "RMX3820", "真我 GT5", "真我 GT5", "realme", "device_list_full_import"); // Device_List:L2980
        put(m, "RMX3823", "真我 GT5 240W", "真我 GT5 240W", "realme", "device_list_full_import"); // Device_List:L2981
        put(m, "RMX3888", "真我 GT5 Pro", "真我 GT5 Pro", "realme", "device_list_full_import"); // Device_List:L2982
        put(m, "RMX3800", "真我 GT6", "真我 GT6", "realme", "device_list_full_import"); // Device_List:L2983
        put(m, "RMX6688", "真我 GT7 / 真我 GT7 阿斯頓馬丁 F1 限量版", "真我 GT7 / 真我 GT7 阿斯頓馬丁 F1 限量版", "realme", "device_list_full_import"); // Device_List:L2984
        put(m, "RMX5010", "真我 GT7 Pro", "真我 GT7 Pro", "realme", "device_list_full_import"); // Device_List:L2985
        put(m, "RMX5090", "真我 GT7 Pro 競速版", "真我 GT7 Pro 競速版", "realme", "device_list_full_import"); // Device_List:L2986
        put(m, "RMX6699", "真我 GT8", "真我 GT8", "realme", "device_list_full_import"); // Device_List:L2987
        put(m, "RMX5200", "真我 GT8 Pro / 真我 GT8 Pro 阿斯頓馬丁 F1 限量版", "真我 GT8 Pro / 真我 GT8 Pro 阿斯頓馬丁 F1 限量版", "realme", "device_list_full_import"); // Device_List:L2988
        put(m, "RMX3031", "真我 GT Neo 5G", "真我 GT Neo 5G", "realme", "device_list_full_import"); // Device_List:L2989
        put(m, "RMX3350", "真我 GT Neo 閃速版", "真我 GT Neo 閃速版", "realme", "device_list_full_import"); // Device_List:L2990
        put(m, "RMX3370", "真我 GT Neo2 / 真我 GT Neo2 龍珠定制版", "真我 GT Neo2 / 真我 GT Neo2 龍珠定制版", "realme", "device_list_full_import"); // Device_List:L2991
        put(m, "RMX3357", "真我 GT Neo2T", "真我 GT Neo2T", "realme", "device_list_full_import"); // Device_List:L2992
        put(m, "RMX3560", "真我 GT Neo3", "真我 GT Neo3", "realme", "device_list_full_import"); // Device_List:L2993
        put(m, "RMX3562", "真我 GT Neo3 150W / 真我 GT Neo3 火影限定版", "真我 GT Neo3 150W / 真我 GT Neo3 火影限定版", "realme", "device_list_full_import"); // Device_List:L2994
        put(m, "RMX3706", "真我 GT Neo5", "真我 GT Neo5", "realme", "device_list_full_import"); // Device_List:L2995
        put(m, "RMX3708", "真我 GT Neo5 240W", "真我 GT Neo5 240W", "realme", "device_list_full_import"); // Device_List:L2996
        put(m, "RMX3700", "真我 GT Neo5 SE", "真我 GT Neo5 SE", "realme", "device_list_full_import"); // Device_List:L2997
        put(m, "RMX3852", "真我 GT Neo6 / 真我 GT Neo6 《完美世界》動畫雲曦限定禮盒", "真我 GT Neo6 / 真我 GT Neo6 《完美世界》動畫雲曦限定禮盒", "realme", "device_list_full_import"); // Device_List:L2998
        put(m, "RMX3850", "真我 GT Neo6 SE", "真我 GT Neo6 SE", "realme", "device_list_full_import"); // Device_List:L2999
        put(m, "RMX5060", "真我 Neo7 / 真我 Neo7 《畫江湖之不良人》限定禮盒", "真我 Neo7 / 真我 Neo7 《畫江湖之不良人》限定禮盒", "realme", "device_list_full_import"); // Device_List:L3000
        put(m, "RMX5062", "真我 Neo7 Turbo / 真我 Neo7 Turbo AI版", "真我 Neo7 Turbo / 真我 Neo7 Turbo AI版", "realme", "device_list_full_import"); // Device_List:L3001
        put(m, "RMX5080", "真我 Neo7 SE", "真我 Neo7 SE", "realme", "device_list_full_import"); // Device_List:L3002
        put(m, "RMX5071", "真我 Neo7x", "真我 Neo7x", "realme", "device_list_full_import"); // Device_List:L3003
        put(m, "RMX8899", "真我 Neo8", "真我 Neo8", "realme", "device_list_full_import"); // Device_List:L3004
        put(m, "RMX1971", "真我 Q", "真我 Q", "realme", "device_list_full_import"); // Device_List:L3005
        put(m, "RMX2117", "真我 Q2 5G", "真我 Q2 5G", "realme", "device_list_full_import"); // Device_List:L3006
        put(m, "RMX2173", "真我 Q2 Pro 5G", "真我 Q2 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3007
        put(m, "RMX2200", "真我 Q2i 5G", "真我 Q2i 5G", "realme", "device_list_full_import"); // Device_List:L3008
        put(m, "RMX3161", "真我 Q3 5G", "真我 Q3 5G", "realme", "device_list_full_import"); // Device_List:L3009
        put(m, "RMX2205", "真我 Q3 Pro 5G", "真我 Q3 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3010
        put(m, "RMX3142", "真我 Q3 Pro 狂歡版", "真我 Q3 Pro 狂歡版", "realme", "device_list_full_import"); // Device_List:L3011
        put(m, "RMX3042", "真我 Q3i 5G", "真我 Q3i 5G", "realme", "device_list_full_import"); // Device_List:L3012
        put(m, "RMX3461", "真我 Q3s", "真我 Q3s", "realme", "device_list_full_import"); // Device_List:L3013
        put(m, "RMX3462", "真我 Q3t", "真我 Q3t", "realme", "device_list_full_import"); // Device_List:L3014
        put(m, "RMX3478", "真我 Q5", "真我 Q5", "realme", "device_list_full_import"); // Device_List:L3015
        put(m, "RMX3372", "真我 Q5 Pro", "真我 Q5 Pro", "realme", "device_list_full_import"); // Device_List:L3016
        put(m, "RMX3574", "真我 Q5i", "真我 Q5i", "realme", "device_list_full_import"); // Device_List:L3017
        put(m, "RMX3616", "真我 Q5x", "真我 Q5x", "realme", "device_list_full_import"); // Device_List:L3018
        put(m, "RMX3615", "真我 10", "真我 10", "realme", "device_list_full_import"); // Device_List:L3019
        put(m, "RMX3617", "真我 10s", "真我 10s", "realme", "device_list_full_import"); // Device_List:L3020
        put(m, "RMX3663", "真我 10 Pro", "真我 10 Pro", "realme", "device_list_full_import"); // Device_List:L3021
        put(m, "RMX3687", "真我 10 Pro+", "真我 10 Pro+", "realme", "device_list_full_import"); // Device_List:L3022
        put(m, "RMX3751", "真我 11", "真我 11", "realme", "device_list_full_import"); // Device_List:L3023
        put(m, "RMX3770", "真我 11 Pro", "真我 11 Pro", "realme", "device_list_full_import"); // Device_List:L3024
        put(m, "RMX3740", "真我 11 Pro+", "真我 11 Pro+", "realme", "device_list_full_import"); // Device_List:L3025
        put(m, "RMX3992", "真我 12", "真我 12", "realme", "device_list_full_import"); // Device_List:L3026
        put(m, "RMX3993", "真我 12x", "真我 12x", "realme", "device_list_full_import"); // Device_List:L3027
        put(m, "RMX3843", "真我 12 Pro / 真我 12 Pro 至尊版", "真我 12 Pro / 真我 12 Pro 至尊版", "realme", "device_list_full_import"); // Device_List:L3028
        put(m, "RMX3841", "真我 12 Pro+", "真我 12 Pro+", "realme", "device_list_full_import"); // Device_List:L3029
        put(m, "RMX3952", "真我 13", "真我 13", "realme", "device_list_full_import"); // Device_List:L3030
        put(m, "RMX5002", "真我 13 Pro", "真我 13 Pro", "realme", "device_list_full_import"); // Device_List:L3031
        put(m, "RMX3989", "真我 13 Pro 至尊版", "真我 13 Pro 至尊版", "realme", "device_list_full_import"); // Device_List:L3032
        put(m, "RMX3920", "真我 13 Pro+", "真我 13 Pro+", "realme", "device_list_full_import"); // Device_List:L3033
        put(m, "RMX5075", "真我 14", "真我 14", "realme", "device_list_full_import"); // Device_List:L3034
        put(m, "RMX5055", "真我 14 Pro", "真我 14 Pro", "realme", "device_list_full_import"); // Device_List:L3035
        put(m, "RMX5050", "真我 14 Pro+", "真我 14 Pro+", "realme", "device_list_full_import"); // Device_List:L3036
        put(m, "RMX5105", "真我 15", "真我 15", "realme", "device_list_full_import"); // Device_List:L3037
        put(m, "RMX5100", "真我 15 Pro / 真我 15 Pro 《權力的遊戲》限定版", "真我 15 Pro / 真我 15 Pro 《權力的遊戲》限定版", "realme", "device_list_full_import"); // Device_List:L3038
        put(m, "RMX5112", "真我 15T", "真我 15T", "realme", "device_list_full_import"); // Device_List:L3039
        put(m, "RMX2201", "真我 V3 5G 運營商定制版", "真我 V3 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L3040
        put(m, "RMX2111", "真我 V5 5G 全網通版", "真我 V5 5G 全網通版", "realme", "device_list_full_import"); // Device_List:L3041
        put(m, "RMX2112", "真我 V5 5G 運營商定制版", "真我 V5 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L3042
        put(m, "RMX3121", "真我 V11 5G 全網通版", "真我 V11 5G 全網通版", "realme", "device_list_full_import"); // Device_List:L3043
        put(m, "RMX3122", "真我 V11 5G 運營商定制版", "真我 V11 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L3044
        put(m, "RMX3125", "真我 V11s 5G", "真我 V11s 5G", "realme", "device_list_full_import"); // Device_List:L3045
        put(m, "RMX3041", "真我 V13 5G 全網通版", "真我 V13 5G 全網通版", "realme", "device_list_full_import"); // Device_List:L3046
        put(m, "RMX3043", "真我 V13 5G 運營商定制版", "真我 V13 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L3047
        put(m, "RMX3092", "真我 V15 5G 全網通版", "真我 V15 5G 全網通版", "realme", "device_list_full_import"); // Device_List:L3048
        put(m, "RMX3093", "真我 V15 5G 運營商定制版", "真我 V15 5G 運營商定制版", "realme", "device_list_full_import"); // Device_List:L3049
        put(m, "RMX3611", "真我 V20", "真我 V20", "realme", "device_list_full_import"); // Device_List:L3050
        put(m, "RMX3571", "真我 V23", "真我 V23", "realme", "device_list_full_import"); // Device_List:L3051
        put(m, "RMX3576", "真我 V23i", "真我 V23i", "realme", "device_list_full_import"); // Device_List:L3052
        put(m, "RMX3475", "真我 V25", "真我 V25", "realme", "device_list_full_import"); // Device_List:L3053
        put(m, "RMX3619", "真我 V30", "真我 V30", "realme", "device_list_full_import"); // Device_List:L3054
        put(m, "RMX3618", "真我 V30t", "真我 V30t", "realme", "device_list_full_import"); // Device_List:L3055
        put(m, "RMX3783", "真我 V50", "真我 V50", "realme", "device_list_full_import"); // Device_List:L3056
        put(m, "RMX3781", "真我 V50s", "真我 V50s", "realme", "device_list_full_import"); // Device_List:L3057
        put(m, "RMX3995", "真我 V60", "真我 V60", "realme", "device_list_full_import"); // Device_List:L3058
        put(m, "RMX3996", "真我 V60s", "真我 V60s", "realme", "device_list_full_import"); // Device_List:L3059
        put(m, "RMX3953", "真我 V60 Pro", "真我 V60 Pro", "realme", "device_list_full_import"); // Device_List:L3060
        put(m, "RMX3946", "真我 V70", "真我 V70", "realme", "device_list_full_import"); // Device_List:L3061
        put(m, "RMX3948", "真我 V70s", "真我 V70s", "realme", "device_list_full_import"); // Device_List:L3062
        put(m, "RMP2108", "真我平板 X", "真我平板 X", "", "device_list_full_import"); // Device_List:L3063
        put(m, "CPH1861", "realme 1", "realme 1", "OnePlus", "device_list_full_import"); // Device_List:L3064
    }

    private static void fill17(Map<String, Entry> m) {
        put(m, "RMX1805", "realme 2", "realme 2", "realme", "device_list_full_import"); // Device_List:L3065
        put(m, "RMX1801", "realme 2 Pro", "realme 2 Pro", "realme", "device_list_full_import"); // Device_List:L3066
        put(m, "RMX1825", "realme 3", "realme 3", "realme", "device_list_full_import"); // Device_List:L3067
        put(m, "RMX1827", "realme 3i", "realme 3i", "realme", "device_list_full_import"); // Device_List:L3068
        put(m, "RMX1853", "realme 3 Pro", "realme 3 Pro", "realme", "device_list_full_import"); // Device_List:L3069
        put(m, "RMX1927", "realme 5", "realme 5", "realme", "device_list_full_import"); // Device_List:L3070
        put(m, "RMX1925", "realme 5s", "realme 5s", "realme", "device_list_full_import"); // Device_List:L3071
        put(m, "RMX2032", "realme 5i", "realme 5i", "realme", "device_list_full_import"); // Device_List:L3072
        put(m, "RMX1973", "realme 5 Pro", "realme 5 Pro", "realme", "device_list_full_import"); // Device_List:L3073
        put(m, "RMX2003", "realme 6", "realme 6", "realme", "device_list_full_import"); // Device_List:L3074
        put(m, "RMX2063", "realme 6 Pro", "realme 6 Pro", "realme", "device_list_full_import"); // Device_List:L3075
        put(m, "RMX2002", "realme 6s Global", "realme 6s Global", "realme", "device_list_full_import"); // Device_List:L3076
        put(m, "RMX2040", "realme 6i EU", "realme 6i EU", "realme", "device_list_full_import"); // Device_List:L3077
        put(m, "RMX2042", "realme 6i Global", "realme 6i Global", "realme", "device_list_full_import"); // Device_List:L3078
        put(m, "RMX2151", "realme 7 India", "realme 7 India", "realme", "device_list_full_import"); // Device_List:L3079
        put(m, "RMX2155", "realme 7 Global", "realme 7 Global", "realme", "device_list_full_import"); // Device_List:L3080
        put(m, "RMX2170", "realme 7 Pro", "realme 7 Pro", "realme", "device_list_full_import"); // Device_List:L3081
        put(m, "RMX2104", "realme 7i India", "realme 7i India", "realme", "device_list_full_import"); // Device_List:L3082
        put(m, "RMX2193", "realme 7i Global", "realme 7i Global", "realme", "device_list_full_import"); // Device_List:L3083
        put(m, "RMX3085", "realme 8", "realme 8", "realme", "device_list_full_import"); // Device_List:L3084
        put(m, "RMX3081", "realme 8 Pro", "realme 8 Pro", "realme", "device_list_full_import"); // Device_List:L3085
        put(m, "RMX3241", "realme 8 5G", "realme 8 5G", "realme", "device_list_full_import"); // Device_List:L3086
        put(m, "RMX3151", "realme 8i", "realme 8i", "realme", "device_list_full_import"); // Device_List:L3087
        put(m, "RMX3381", "realme 8s 5G", "realme 8s 5G", "realme", "device_list_full_import"); // Device_List:L3088
        put(m, "RMX3521", "realme 9", "realme 9", "realme", "device_list_full_import"); // Device_List:L3089
        put(m, "RMX3491", "realme 9i India / Global", "realme 9i India / Global", "realme", "device_list_full_import"); // Device_List:L3090
        put(m, "RMX3492", "realme 9i", "realme 9i", "realme", "device_list_full_import"); // Device_List:L3091
        put(m, "RMX3493", "realme 9i EU", "realme 9i EU", "realme", "device_list_full_import"); // Device_List:L3092
        put(m, "RMX3388", "realme 9 5G India", "realme 9 5G India", "realme", "device_list_full_import"); // Device_List:L3093
        put(m, "RMX3474", "realme 9 5G EU", "realme 9 5G EU", "realme", "device_list_full_import"); // Device_List:L3094
        put(m, "RMX3612", "realme 9i 5G", "realme 9i 5G", "realme", "device_list_full_import"); // Device_List:L3095
        put(m, "RMX3471", "realme 9 Pro 5G India", "realme 9 Pro 5G India", "realme", "device_list_full_import"); // Device_List:L3096
        put(m, "RMX3472", "realme 9 Pro 5G Global", "realme 9 Pro 5G Global", "realme", "device_list_full_import"); // Device_List:L3097
        put(m, "RMX3392", "realme 9 Pro+ 5G India", "realme 9 Pro+ 5G India", "realme", "device_list_full_import"); // Device_List:L3098
        put(m, "RMX3393", "realme 9 Pro+ 5G Global", "realme 9 Pro+ 5G Global", "realme", "device_list_full_import"); // Device_List:L3099
        put(m, "RMX3630", "realme 10", "realme 10", "realme", "device_list_full_import"); // Device_List:L3100
        put(m, "RMX3660", "realme 10 Pro 5G India / realme 10 Pro 5G Coca-Cola® Edition", "realme 10 Pro 5G India / realme 10 Pro 5G Coca-Cola® Edition", "realme", "device_list_full_import"); // Device_List:L3101
        put(m, "RMX3661", "realme 10 Pro 5G Global / realme 10 Pro 5G Coca-Cola® Edition", "realme 10 Pro 5G Global / realme 10 Pro 5G Coca-Cola® Edition", "realme", "device_list_full_import"); // Device_List:L3102
        put(m, "RMX3686", "realme 10 Pro+ 5G", "realme 10 Pro+ 5G", "realme", "device_list_full_import"); // Device_List:L3103
        put(m, "RMX3636", "realme 11", "realme 11", "realme", "device_list_full_import"); // Device_List:L3104
        put(m, "RMX3780", "realme 11 5G", "realme 11 5G", "realme", "device_list_full_import"); // Device_List:L3105
        put(m, "RMX3785", "realme 11x 5G", "realme 11x 5G", "realme", "device_list_full_import"); // Device_List:L3106
        put(m, "RMX3771", "realme 11 Pro 5G", "realme 11 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3107
        put(m, "RMX3741", "realme 11 Pro+ 5G", "realme 11 Pro+ 5G", "realme", "device_list_full_import"); // Device_List:L3108
        put(m, "RMX3871", "realme 12 4G", "realme 12 4G", "realme", "device_list_full_import"); // Device_List:L3109
        put(m, "RMX3999", "realme 12 5G", "realme 12 5G", "realme", "device_list_full_import"); // Device_List:L3110
        put(m, "RMX3998", "realme 12x 5G", "realme 12x 5G", "realme", "device_list_full_import"); // Device_List:L3111
        put(m, "RMX3867", "realme 12+ 5G", "realme 12+ 5G", "realme", "device_list_full_import"); // Device_List:L3112
        put(m, "RMX3842", "realme 12 Pro 5G", "realme 12 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3113
        put(m, "RMX3840", "realme 12 Pro+ 5G", "realme 12 Pro+ 5G", "realme", "device_list_full_import"); // Device_List:L3114
        put(m, "RMX3951", "realme 13 5G", "realme 13 5G", "realme", "device_list_full_import"); // Device_List:L3115
        put(m, "RMX5000", "realme 13+ 5G", "realme 13+ 5G", "realme", "device_list_full_import"); // Device_List:L3116
        put(m, "RMX3990", "realme 13 Pro 5G / realme 14 Pro Lite 5G", "realme 13 Pro 5G / realme 14 Pro Lite 5G", "realme", "device_list_full_import"); // Device_List:L3117
        put(m, "RMX3921", "realme 13 Pro+ 5G", "realme 13 Pro+ 5G", "realme", "device_list_full_import"); // Device_List:L3118
        put(m, "RMX5070", "realme 14 5G Global", "realme 14 5G Global", "realme", "device_list_full_import"); // Device_List:L3119
        put(m, "RMX3940", "realme 14x 5G India", "realme 14x 5G India", "realme", "device_list_full_import"); // Device_List:L3120
        put(m, "RMX3943", "realme 14x 5G Global", "realme 14x 5G Global", "realme", "device_list_full_import"); // Device_List:L3121
        put(m, "RMX5074", "realme 14T 5G Global", "realme 14T 5G Global", "realme", "device_list_full_import"); // Device_List:L3122
        put(m, "RMX5078", "realme 14T 5G India", "realme 14T 5G India", "realme", "device_list_full_import"); // Device_List:L3123
        put(m, "RMX5056", "realme 14 Pro 5G India", "realme 14 Pro 5G India", "realme", "device_list_full_import"); // Device_List:L3124
        put(m, "RMX5057", "realme 14 Pro 5G Global", "realme 14 Pro 5G Global", "realme", "device_list_full_import"); // Device_List:L3125
        put(m, "RMX5051", "realme 14 Pro+ 5G India", "realme 14 Pro+ 5G India", "realme", "device_list_full_import"); // Device_List:L3126
        put(m, "RMX5054", "realme 14 Pro+ 5G Global", "realme 14 Pro+ 5G Global", "realme", "device_list_full_import"); // Device_List:L3127
        put(m, "RMX5106", "realme 15 5G", "realme 15 5G", "realme", "device_list_full_import"); // Device_List:L3128
        put(m, "RMX5101", "realme 15 Pro 5G / realme 15 Pro 5G Game of Thrones Limited Edition", "realme 15 Pro 5G / realme 15 Pro 5G Game of Thrones Limited Edition", "realme", "device_list_full_import"); // Device_List:L3129
        put(m, "RMX5111", "realme 15T 5G", "realme 15T 5G", "realme", "device_list_full_import"); // Device_List:L3130
        put(m, "RMX5250", "realme 15x 5G", "realme 15x 5G", "realme", "device_list_full_import"); // Device_List:L3131
        put(m, "RMX5171", "realme 16 5G", "realme 16 5G", "realme", "device_list_full_import"); // Device_List:L3132
        put(m, "RMX5120", "realme 16 Pro 5G", "realme 16 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3133
        put(m, "RMX5131", "realme 16 Pro+ 5G", "realme 16 Pro+ 5G", "realme", "device_list_full_import"); // Device_List:L3134
        put(m, "RMX5268", "realme 16T 5G", "realme 16T 5G", "realme", "device_list_full_import"); // Device_List:L3135
        put(m, "RMX1921", "realme XT Global", "realme XT Global", "realme", "device_list_full_import"); // Device_List:L3136
        put(m, "RMX1922", "realme XT India", "realme XT India", "realme", "device_list_full_import"); // Device_List:L3137
        put(m, "RMX1992", "realme X2 India", "realme X2 India", "realme", "device_list_full_import"); // Device_List:L3138
        put(m, "RMX1993", "realme X2 Global", "realme X2 Global", "realme", "device_list_full_import"); // Device_List:L3139
        put(m, "RMX2081", "realme X3 India", "realme X3 India", "realme", "device_list_full_import"); // Device_List:L3140
        put(m, "RMX2083", "realme X3 Global", "realme X3 Global", "realme", "device_list_full_import"); // Device_List:L3141
        put(m, "RMX2085", "realme X3 SuperZoom India", "realme X3 SuperZoom India", "realme", "device_list_full_import"); // Device_List:L3142
        put(m, "RMX2086", "realme X3 SuperZoom Global", "realme X3 SuperZoom Global", "realme", "device_list_full_import"); // Device_List:L3143
        put(m, "RMX2144", "realme X50 Global", "realme X50 Global", "realme", "device_list_full_import"); // Device_List:L3144
        put(m, "RMX2075", "realme X50 Pro Global", "realme X50 Pro Global", "realme", "device_list_full_import"); // Device_List:L3145
        put(m, "RMX2076", "realme X50 Pro India", "realme X50 Pro India", "realme", "device_list_full_import"); // Device_List:L3146
        put(m, "RMX3363", "realme GT Master Edition", "realme GT Master Edition", "realme", "device_list_full_import"); // Device_List:L3147
        put(m, "RMX3312", "realme GT 2 5G", "realme GT 2 5G", "realme", "device_list_full_import"); // Device_List:L3148
        put(m, "RMX3301", "realme GT 2 Pro 5G", "realme GT 2 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3149
        put(m, "RMX3561", "realme GT NEO 3", "realme GT NEO 3", "realme", "device_list_full_import"); // Device_List:L3150
        put(m, "RMX3563", "realme GT NEO 3 150W", "realme GT NEO 3 150W", "realme", "device_list_full_import"); // Device_List:L3151
        put(m, "RMX3371", "realme GT NEO 3T", "realme GT NEO 3T", "realme", "device_list_full_import"); // Device_List:L3152
        put(m, "RMX3701", "realme GT Neo5 SE", "realme GT Neo5 SE", "realme", "device_list_full_import"); // Device_List:L3153
        put(m, "RMX3709", "realme GT 3 240W", "realme GT 3 240W", "realme", "device_list_full_import"); // Device_List:L3154
        put(m, "RMX3851", "realme GT 6", "realme GT 6", "realme", "device_list_full_import"); // Device_List:L3155
        put(m, "RMX3853", "realme GT 6T", "realme GT 6T", "realme", "device_list_full_import"); // Device_List:L3156
        put(m, "RMX5061", "realme GT 7 / realme GT 7 Dream Edition", "realme GT 7 / realme GT 7 Dream Edition", "realme", "device_list_full_import"); // Device_List:L3157
        put(m, "RMX5085", "realme GT 7T", "realme GT 7T", "realme", "device_list_full_import"); // Device_List:L3158
        put(m, "RMX5011", "realme GT 7 Pro", "realme GT 7 Pro", "realme", "device_list_full_import"); // Device_List:L3159
        put(m, "RMX5210", "realme GT 8 Pro / realme GT 8 Pro Dream Edition", "realme GT 8 Pro / realme GT 8 Pro Dream Edition", "realme", "device_list_full_import"); // Device_List:L3160
        put(m, "RMX1946", "realme C2", "realme C2", "realme", "device_list_full_import"); // Device_List:L3161
        put(m, "RMX2022", "realme C3 Global", "realme C3 Global", "realme", "device_list_full_import"); // Device_List:L3162
        put(m, "RMX2027", "realme C3 India", "realme C3 India", "realme", "device_list_full_import"); // Device_List:L3163
        put(m, "RMX2186", "realme C11", "realme C11", "realme", "device_list_full_import"); // Device_List:L3164
        put(m, "RMX3231", "realme C11 2021", "realme C11 2021", "realme", "device_list_full_import"); // Device_List:L3165
        put(m, "RMX2189", "realme C12", "realme C12", "realme", "device_list_full_import"); // Device_List:L3166
        put(m, "RMX2183", "realme C15", "realme C15", "realme", "device_list_full_import"); // Device_List:L3167
        put(m, "RMX2195", "realme C15 Qualcomm Edition", "realme C15 Qualcomm Edition", "realme", "device_list_full_import"); // Device_List:L3168
        put(m, "RMX2101", "realme C17", "realme C17", "realme", "device_list_full_import"); // Device_List:L3169
        put(m, "RMX3063", "realme C20", "realme C20", "realme", "device_list_full_import"); // Device_List:L3170
        put(m, "RMX3203", "realme C21", "realme C21", "realme", "device_list_full_import"); // Device_List:L3171
        put(m, "RMX3263", "realme C21Y", "realme C21Y", "realme", "device_list_full_import"); // Device_List:L3172
        put(m, "RMX3193", "realme C25", "realme C25", "realme", "device_list_full_import"); // Device_List:L3173
        put(m, "RMX3197", "realme C25s", "realme C25s", "realme", "device_list_full_import"); // Device_List:L3174
        put(m, "RMX3269", "realme C25Y", "realme C25Y", "realme", "device_list_full_import"); // Device_List:L3175
        put(m, "RMX3623", "realme C30", "realme C30", "realme", "device_list_full_import"); // Device_List:L3176
        put(m, "RMX3690", "realme C30s", "realme C30s", "realme", "device_list_full_import"); // Device_List:L3177
        put(m, "RMX3503", "realme C31", "realme C31", "realme", "device_list_full_import"); // Device_List:L3178
        put(m, "RMX3624", "realme C33", "realme C33", "realme", "device_list_full_import"); // Device_List:L3179
        put(m, "RMX3627", "realme C33 2023", "realme C33 2023", "realme", "device_list_full_import"); // Device_List:L3180
        put(m, "RMX3513", "realme C35", "realme C35", "realme", "device_list_full_import"); // Device_List:L3181
        put(m, "RMX3830", "realme C51", "realme C51", "realme", "device_list_full_import"); // Device_List:L3182
        put(m, "RMX3765", "realme C51s", "realme C51s", "realme", "device_list_full_import"); // Device_List:L3183
        put(m, "RMX3760", "realme C53 Global", "realme C53 Global", "realme", "device_list_full_import"); // Device_List:L3184
        put(m, "RMX3762", "realme C53 India", "realme C53 India", "realme", "device_list_full_import"); // Device_List:L3185
        put(m, "RMX3710", "realme C55", "realme C55", "realme", "device_list_full_import"); // Device_List:L3186
        put(m, "RMX3834", "realme C60", "realme C60", "realme", "device_list_full_import"); // Device_List:L3187
        put(m, "RMX3930", "realme C61 Global", "realme C61 Global", "realme", "device_list_full_import"); // Device_List:L3188
        put(m, "RMX3939", "realme C61 Global", "realme C61 Global", "realme", "device_list_full_import"); // Device_List:L3189
        put(m, "RMX3933", "realme C61 India", "realme C61 India", "realme", "device_list_full_import"); // Device_List:L3190
        put(m, "RMX3950", "realme C63 5G", "realme C63 5G", "realme", "device_list_full_import"); // Device_List:L3191
        put(m, "RMX3910", "realme C65", "realme C65", "realme", "device_list_full_import"); // Device_List:L3192
        put(m, "RMX3997", "realme C65 5G", "realme C65 5G", "realme", "device_list_full_import"); // Device_List:L3193
        put(m, "RMX3890", "realme C67", "realme C67", "realme", "device_list_full_import"); // Device_List:L3194
        put(m, "RMX3782", "realme C67 5G", "realme C67 5G", "realme", "device_list_full_import"); // Device_List:L3195
        put(m, "RMX5303", "realme C71", "realme C71", "realme", "device_list_full_import"); // Device_List:L3196
        put(m, "RMX3945", "realme C73 5G", "realme C73 5G", "realme", "device_list_full_import"); // Device_List:L3197
        put(m, "RMX3941", "realme C75", "realme C75", "realme", "device_list_full_import"); // Device_List:L3198
        put(m, "RMX3963", "realme C75 5G Global", "realme C75 5G Global", "realme", "device_list_full_import"); // Device_List:L3199
        put(m, "RMX5020", "realme C75x", "realme C75x", "realme", "device_list_full_import"); // Device_List:L3200
        put(m, "RMX5256", "realme C83 5G", "realme C83 5G", "realme", "device_list_full_import"); // Device_List:L3201
        put(m, "RMX5566", "realme C85", "realme C85", "realme", "device_list_full_import"); // Device_List:L3202
        put(m, "RMX5253", "realme C85 5G", "realme C85 5G", "realme", "device_list_full_import"); // Device_List:L3203
        put(m, "RMX5555", "realme C85 Pro", "realme C85 Pro", "realme", "device_list_full_import"); // Device_List:L3204
        put(m, "RMX5353", "realme C100", "realme C100", "realme", "device_list_full_import"); // Device_List:L3205
        put(m, "RMX5258", "realme C100 5G", "realme C100 5G", "realme", "device_list_full_import"); // Device_List:L3206
        put(m, "RMX5377", "realme C100i", "realme C100i", "realme", "device_list_full_import"); // Device_List:L3207
        put(m, "RMX5366", "realme C100x", "realme C100x", "realme", "device_list_full_import"); // Device_List:L3208
        put(m, "RMX3938", "realme Note 60x", "realme Note 60x", "realme", "device_list_full_import"); // Device_List:L3209
        put(m, "RMX5313", "realme Note 70 / realme Note 70T / realme Note 70s", "realme Note 70 / realme Note 70T / realme Note 70s", "realme", "device_list_full_import"); // Device_List:L3210
        put(m, "RMX5388", "realme Note 80 / realme Note 80s", "realme Note 80 / realme Note 80s", "realme", "device_list_full_import"); // Device_List:L3211
        put(m, "RMX1833", "realme U1", "realme U1", "realme", "device_list_full_import"); // Device_List:L3212
        put(m, "RMX3870", "realme P1 5G", "realme P1 5G", "realme", "device_list_full_import"); // Device_List:L3213
        put(m, "RMX3844", "realme P1 Pro 5G", "realme P1 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3214
        put(m, "RMX5004", "realme P1 Speed 5G", "realme P1 Speed 5G", "realme", "device_list_full_import"); // Device_List:L3215
        put(m, "RMX3987", "realme P2 Pro 5G", "realme P2 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3216
        put(m, "RMX5079", "realme P3 5G", "realme P3 5G", "realme", "device_list_full_import"); // Device_List:L3217
        put(m, "RMX3944", "realme P3x 5G", "realme P3x 5G", "realme", "device_list_full_import"); // Device_List:L3218
        put(m, "RMX5032", "realme P3 Pro 5G", "realme P3 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3219
        put(m, "RMX5031", "realme P3 Ultra 5G", "realme P3 Ultra 5G", "realme", "device_list_full_import"); // Device_List:L3220
        put(m, "RMX5300", "realme P3 Lite", "realme P3 Lite", "realme", "device_list_full_import"); // Device_List:L3221
        put(m, "RMX5110", "realme P4 5G", "realme P4 5G", "realme", "device_list_full_import"); // Device_List:L3222
        put(m, "RMX5116", "realme P4 Pro 5G", "realme P4 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3223
        put(m, "RMX5367", "realme P4x", "realme P4x", "realme", "device_list_full_import"); // Device_List:L3224
        put(m, "RMX5108", "realme P4x 5G", "realme P4x 5G", "realme", "device_list_full_import"); // Device_List:L3225
        put(m, "RMX5107", "realme P4 Power 5G", "realme P4 Power 5G", "realme", "device_list_full_import"); // Device_List:L3226
        put(m, "RMX5261", "realme P4 Lite 5G", "realme P4 Lite 5G", "realme", "device_list_full_import"); // Device_List:L3227
        put(m, "RMX5266", "realme P4R 5G", "realme P4R 5G", "realme", "device_list_full_import"); // Device_List:L3228
        put(m, "RMX2020", "realme Narzo 10A India", "realme Narzo 10A India", "realme", "device_list_full_import"); // Device_List:L3229
        put(m, "RMX2191", "realme Narzo 20 Global", "realme Narzo 20 Global", "realme", "device_list_full_import"); // Device_List:L3230
        put(m, "RMX2161", "realme Narzo 20 Pro India", "realme Narzo 20 Pro India", "realme", "device_list_full_import"); // Device_List:L3231
        put(m, "RMX2163", "realme Narzo 20 Pro Global", "realme Narzo 20 Pro Global", "realme", "device_list_full_import"); // Device_List:L3232
        put(m, "RMX2050", "realme Narzo 20A", "realme Narzo 20A", "realme", "device_list_full_import"); // Device_List:L3233
        put(m, "RMX2156", "realme Narzo 30", "realme Narzo 30", "realme", "device_list_full_import"); // Device_List:L3234
        put(m, "RMX3242", "realme Narzo 30 5G", "realme Narzo 30 5G", "realme", "device_list_full_import"); // Device_List:L3235
        put(m, "RMX3171", "realme Narzo 30A", "realme Narzo 30A", "realme", "device_list_full_import"); // Device_List:L3236
        put(m, "RMX3286", "realme Narzo 50", "realme Narzo 50", "realme", "device_list_full_import"); // Device_List:L3237
        put(m, "RMX3572", "realme Narzo 50 5G Global", "realme Narzo 50 5G Global", "realme", "device_list_full_import"); // Device_List:L3238
        put(m, "RMX3395", "realme Narzo 50 Pro 5G India", "realme Narzo 50 Pro 5G India", "realme", "device_list_full_import"); // Device_List:L3239
        put(m, "RMX3396", "realme Narzo 50 Pro 5G Global", "realme Narzo 50 Pro 5G Global", "realme", "device_list_full_import"); // Device_List:L3240
        put(m, "RMX3430", "realme Narzo 50A", "realme Narzo 50A", "realme", "device_list_full_import"); // Device_List:L3241
        put(m, "RMX3517", "realme Narzo 50A Prime", "realme Narzo 50A Prime", "realme", "device_list_full_import"); // Device_List:L3242
        put(m, "RMX3235", "realme Narzo 50i Global", "realme Narzo 50i Global", "realme", "device_list_full_import"); // Device_List:L3243
        put(m, "RMX3506", "realme Narzo 50i Prime", "realme Narzo 50i Prime", "realme", "device_list_full_import"); // Device_List:L3244
    }

    private static void fill18(Map<String, Entry> m) {
        put(m, "RMX3761", "realme Narzo N53", "realme Narzo N53", "realme", "device_list_full_import"); // Device_List:L3245
        put(m, "RMX3750", "realme Narzo 60 5G", "realme Narzo 60 5G", "realme", "device_list_full_import"); // Device_List:L3246
        put(m, "RMX3869", "realme NARZO 70 5G", "realme NARZO 70 5G", "realme", "device_list_full_import"); // Device_List:L3247
        put(m, "RMX3868", "realme NARZO 70 Pro 5G", "realme NARZO 70 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3248
        put(m, "RMX5003", "realme NARZO 70 Turbo 5G", "realme NARZO 70 Turbo 5G", "realme", "device_list_full_import"); // Device_List:L3249
        put(m, "RMX5033", "realme NARZO 80 Pro 5G", "realme NARZO 80 Pro 5G", "realme", "device_list_full_import"); // Device_List:L3250
        put(m, "RMX5264", "realme NARZO 90x 5G", "realme NARZO 90x 5G", "realme", "device_list_full_import"); // Device_List:L3251
        put(m, "RMP2102", "realme Pad LTE", "realme Pad LTE", "realme", "device_list_full_import"); // Device_List:L3252
        put(m, "RMP2103", "realme Pad Wi-Fi", "realme Pad Wi-Fi", "realme", "device_list_full_import"); // Device_List:L3253
        put(m, "RMP2105", "realme Pad mini LTE", "realme Pad mini LTE", "realme", "device_list_full_import"); // Device_List:L3254
        put(m, "RMP2106", "realme Pad mini Wi-Fi", "realme Pad mini Wi-Fi", "realme", "device_list_full_import"); // Device_List:L3255
        put(m, "RMP2107", "realme Pad X 5G", "realme Pad X 5G", "realme", "device_list_full_import"); // Device_List:L3256
        put(m, "RMP2204", "realme Pad 2 LTE", "realme Pad 2 LTE", "realme", "device_list_full_import"); // Device_List:L3257
        put(m, "RMP2205", "realme Pad 2 Wi-Fi", "realme Pad 2 Wi-Fi", "realme", "device_list_full_import"); // Device_List:L3258
        put(m, "RMP2402", "realme Pad 2 Lite", "realme Pad 2 Lite", "realme", "device_list_full_import"); // Device_List:L3259
        put(m, "RMP2501", "realme Pad 3 5G", "realme Pad 3 5G", "realme", "device_list_full_import"); // Device_List:L3260
        put(m, "RMP2502", "realme Pad 3 Wi-Fi", "realme Pad 3 Wi-Fi", "realme", "device_list_full_import"); // Device_List:L3261
        put(m, "V1821A", "vivo NEX 雙屏版 全網通版", "vivo NEX 雙屏版 全網通版", "vivo", "device_list_full_import"); // Device_List:L3262
        put(m, "V1821T", "vivo NEX 雙屏版 移動全網通版", "vivo NEX 雙屏版 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3263
        put(m, "V1923A", "vivo NEX 3 全網通版", "vivo NEX 3 全網通版", "vivo", "device_list_full_import"); // Device_List:L3264
        put(m, "V1923T", "vivo NEX 3 移動全網通版", "vivo NEX 3 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3265
        put(m, "V1924A", "vivo NEX 3 5G 全網通版", "vivo NEX 3 5G 全網通版", "vivo", "device_list_full_import"); // Device_List:L3266
        put(m, "V1924T", "vivo NEX 3 5G 移動全網通版", "vivo NEX 3 5G 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3267
        put(m, "V1950A", "vivo NEX 3S 5G", "vivo NEX 3S 5G", "vivo", "device_list_full_import"); // Device_List:L3268
        put(m, "V1814A", "vivo X21s 全網通版", "vivo X21s 全網通版", "vivo", "device_list_full_import"); // Device_List:L3269
        put(m, "V1814T", "vivo X21s 移動全網通版", "vivo X21s 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3270
        put(m, "V1809A", "vivo X23 全網通版", "vivo X23 全網通版", "vivo", "device_list_full_import"); // Device_List:L3271
        put(m, "V1809T", "vivo X23 移動全網通版", "vivo X23 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3272
        put(m, "V1816A", "vivo X23 幻彩版 全網通版", "vivo X23 幻彩版 全網通版", "vivo", "device_list_full_import"); // Device_List:L3273
        put(m, "V1816T", "vivo X23 幻彩版 移動全網通版", "vivo X23 幻彩版 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3274
        put(m, "V1829A", "vivo X27 8GB+256GB 全網通版", "vivo X27 8GB+256GB 全網通版", "vivo", "device_list_full_import"); // Device_List:L3275
        put(m, "V1829T", "vivo X27 8GB+256GB 移動全網通版", "vivo X27 8GB+256GB 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3276
        put(m, "V1838A", "vivo X27 8GB+128GB 全網通版", "vivo X27 8GB+128GB 全網通版", "vivo", "device_list_full_import"); // Device_List:L3277
        put(m, "V1838T", "vivo X27 8GB+128GB 移動全網通版", "vivo X27 8GB+128GB 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3278
        put(m, "V1836A", "vivo X27 Pro 全網通版", "vivo X27 Pro 全網通版", "vivo", "device_list_full_import"); // Device_List:L3279
        put(m, "V1836T", "vivo X27 Pro 移動全網通版", "vivo X27 Pro 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3280
        put(m, "V1938CA", "vivo X30 5G 全網通版", "vivo X30 5G 全網通版", "vivo", "device_list_full_import"); // Device_List:L3281
        put(m, "V1938CT", "vivo X30 5G 移動全網通版", "vivo X30 5G 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3282
        put(m, "V1938A", "vivo X30 Pro 5G 全網通版", "vivo X30 Pro 5G 全網通版", "vivo", "device_list_full_import"); // Device_List:L3283
        put(m, "V1938T", "vivo X30 Pro 5G 移動全網通版", "vivo X30 Pro 5G 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3284
        put(m, "V2001A", "vivo X50", "vivo X50", "vivo", "device_list_full_import"); // Device_List:L3285
        put(m, "V2005A", "vivo X50 Pro", "vivo X50 Pro", "vivo", "device_list_full_import"); // Device_List:L3286
        put(m, "V2011A", "vivo X50 Pro+", "vivo X50 Pro+", "vivo", "device_list_full_import"); // Device_List:L3287
        put(m, "V2046A", "vivo X60", "vivo X60", "vivo", "device_list_full_import"); // Device_List:L3288
        put(m, "V2059A", "vivo X60 曲屏版", "vivo X60 曲屏版", "vivo", "device_list_full_import"); // Device_List:L3289
        put(m, "V2085A", "vivo X60t", "vivo X60t", "vivo", "device_list_full_import"); // Device_List:L3290
        put(m, "V2047A", "vivo X60 Pro", "vivo X60 Pro", "vivo", "device_list_full_import"); // Device_List:L3291
        put(m, "V2120A", "vivo X60t Pro", "vivo X60t Pro", "vivo", "device_list_full_import"); // Device_List:L3292
        put(m, "V2056A", "vivo X60 Pro+", "vivo X60 Pro+", "vivo", "device_list_full_import"); // Device_List:L3293
        put(m, "V2133A", "vivo X70", "vivo X70", "vivo", "device_list_full_import"); // Device_List:L3294
        put(m, "V2132A", "vivo X70t", "vivo X70t", "vivo", "device_list_full_import"); // Device_List:L3295
        put(m, "V2134A", "vivo X70 Pro", "vivo X70 Pro", "vivo", "device_list_full_import"); // Device_List:L3296
        put(m, "V2145A", "vivo X70 Pro+", "vivo X70 Pro+", "vivo", "device_list_full_import"); // Device_List:L3297
        put(m, "V2178A", "vivo X Fold", "vivo X Fold", "vivo", "device_list_full_import"); // Device_List:L3298
        put(m, "V2170A", "vivo X Note", "vivo X Note", "vivo", "device_list_full_import"); // Device_List:L3299
        put(m, "V2183A", "vivo X80", "vivo X80", "vivo", "device_list_full_import"); // Device_List:L3300
        put(m, "V2185A", "vivo X80 Pro", "vivo X80 Pro", "vivo", "device_list_full_import"); // Device_List:L3301
        put(m, "V2186A", "vivo X80 Pro 天璣 9000 版", "vivo X80 Pro 天璣 9000 版", "vivo", "device_list_full_import"); // Device_List:L3302
        put(m, "V2229A", "vivo X Fold+", "vivo X Fold+", "vivo", "device_list_full_import"); // Device_List:L3303
        put(m, "V2241A", "vivo X90", "vivo X90", "vivo", "device_list_full_import"); // Device_List:L3304
        put(m, "V2241HA", "vivo X90s", "vivo X90s", "vivo", "device_list_full_import"); // Device_List:L3305
        put(m, "V2242A", "vivo X90 Pro", "vivo X90 Pro", "vivo", "device_list_full_import"); // Device_List:L3306
        put(m, "V2227A", "vivo X90 Pro+", "vivo X90 Pro+", "vivo", "device_list_full_import"); // Device_List:L3307
        put(m, "V2266A", "vivo X Fold2", "vivo X Fold2", "vivo", "device_list_full_import"); // Device_List:L3308
        put(m, "V2256A", "vivo X Flip", "vivo X Flip", "vivo", "device_list_full_import"); // Device_List:L3309
        put(m, "V2309A", "vivo X100", "vivo X100", "vivo", "device_list_full_import"); // Device_List:L3310
        put(m, "V2324A", "vivo X100 Pro", "vivo X100 Pro", "vivo", "device_list_full_import"); // Device_List:L3311
        put(m, "V2303A", "vivo X Fold3", "vivo X Fold3", "vivo", "device_list_full_import"); // Device_List:L3312
        put(m, "V2337A", "vivo X Fold3 Pro", "vivo X Fold3 Pro", "vivo", "device_list_full_import"); // Device_List:L3313
        put(m, "V2359A", "vivo X100s", "vivo X100s", "vivo", "device_list_full_import"); // Device_List:L3314
        put(m, "V2324HA", "vivo X100s Pro", "vivo X100s Pro", "vivo", "device_list_full_import"); // Device_List:L3315
        put(m, "V2366GA", "vivo X100 Ultra", "vivo X100 Ultra", "vivo", "device_list_full_import"); // Device_List:L3316
        put(m, "V2366HA", "vivo X100 Ultra 衛星通信版", "vivo X100 Ultra 衛星通信版", "vivo", "device_list_full_import"); // Device_List:L3317
        put(m, "V2415A", "vivo X200", "vivo X200", "vivo", "device_list_full_import"); // Device_List:L3318
        put(m, "V2405A", "vivo X200 Pro", "vivo X200 Pro", "vivo", "device_list_full_import"); // Device_List:L3319
        put(m, "V2405DA", "vivo X200 Pro 衛星通信版", "vivo X200 Pro 衛星通信版", "vivo", "device_list_full_import"); // Device_List:L3320
        put(m, "V2419A", "vivo X200 Pro mini", "vivo X200 Pro mini", "vivo", "device_list_full_import"); // Device_List:L3321
        put(m, "V2458A", "vivo X200s", "vivo X200s", "vivo", "device_list_full_import"); // Device_List:L3322
        put(m, "V2454A", "vivo X200 Ultra", "vivo X200 Ultra", "vivo", "device_list_full_import"); // Device_List:L3323
        put(m, "V2454DA", "vivo X200 Ultra 衛星通信版", "vivo X200 Ultra 衛星通信版", "vivo", "device_list_full_import"); // Device_List:L3324
        put(m, "V2436A", "vivo X Fold5", "vivo X Fold5", "vivo", "device_list_full_import"); // Device_List:L3325
        put(m, "V2509A", "vivo X300", "vivo X300", "vivo", "device_list_full_import"); // Device_List:L3326
        put(m, "V2502A", "vivo X300 Pro", "vivo X300 Pro", "vivo", "device_list_full_import"); // Device_List:L3327
        put(m, "V2502DA", "vivo X300 Pro 衛星通信版", "vivo X300 Pro 衛星通信版", "vivo", "device_list_full_import"); // Device_List:L3328
        put(m, "V2548A", "vivo X300s", "vivo X300s", "vivo", "device_list_full_import"); // Device_List:L3329
        put(m, "V2547A", "vivo X300 Ultra", "vivo X300 Ultra", "vivo", "device_list_full_import"); // Device_List:L3330
        put(m, "V2547DA", "vivo X300 Ultra 衛星通信版", "vivo X300 Ultra 衛星通信版", "vivo", "device_list_full_import"); // Device_List:L3331
        put(m, "V2545A", "vivo X Fold6", "vivo X Fold6", "vivo", "device_list_full_import"); // Device_List:L3332
        put(m, "V1831A", "vivo S1 全網通版", "vivo S1 全網通版", "vivo", "device_list_full_import"); // Device_List:L3333
        put(m, "V1831T", "vivo S1 移動全網通版", "vivo S1 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3334
        put(m, "V1832A", "vivo S1 Pro 全網通版", "vivo S1 Pro 全網通版", "vivo", "device_list_full_import"); // Device_List:L3335
        put(m, "V1832T", "vivo S1 Pro 移動全網通版", "vivo S1 Pro 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3336
        put(m, "V1932A", "vivo S5 全網通版", "vivo S5 全網通版", "vivo", "device_list_full_import"); // Device_List:L3337
        put(m, "V1932T", "vivo S5 移動全網通版", "vivo S5 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3338
        put(m, "V1962A", "vivo S6", "vivo S6", "vivo", "device_list_full_import"); // Device_List:L3339
        put(m, "V2020CA", "vivo S7", "vivo S7", "vivo", "device_list_full_import"); // Device_List:L3340
        put(m, "V2080A", "vivo S7t", "vivo S7t", "vivo", "device_list_full_import"); // Device_List:L3341
        put(m, "V2031A", "vivo S7e", "vivo S7e", "vivo", "device_list_full_import"); // Device_List:L3342
        put(m, "V2031EA", "vivo S7e 活力版", "vivo S7e 活力版", "vivo", "device_list_full_import"); // Device_List:L3343
        put(m, "V2072A", "vivo S9", "vivo S9", "vivo", "device_list_full_import"); // Device_List:L3344
        put(m, "V2048A", "vivo S9e", "vivo S9e", "vivo", "device_list_full_import"); // Device_List:L3345
        put(m, "V2121A", "vivo S10", "vivo S10", "vivo", "device_list_full_import"); // Device_List:L3346
        put(m, "V2130A", "vivo S10e", "vivo S10e", "vivo", "device_list_full_import"); // Device_List:L3347
        put(m, "V2162A", "vivo S12", "vivo S12", "vivo", "device_list_full_import"); // Device_List:L3348
        put(m, "V2163A", "vivo S12 Pro", "vivo S12 Pro", "vivo", "device_list_full_import"); // Device_List:L3349
        put(m, "V2203A", "vivo S15", "vivo S15", "vivo", "device_list_full_import"); // Device_List:L3350
        put(m, "V2207A", "vivo S15 Pro", "vivo S15 Pro", "vivo", "device_list_full_import"); // Device_List:L3351
        put(m, "V2190A", "vivo S15e", "vivo S15e", "vivo", "device_list_full_import"); // Device_List:L3352
        put(m, "V2244A", "vivo S16", "vivo S16", "vivo", "device_list_full_import"); // Device_List:L3353
        put(m, "V2245A", "vivo S16 Pro", "vivo S16 Pro", "vivo", "device_list_full_import"); // Device_List:L3354
        put(m, "V2239A", "vivo S16e", "vivo S16e", "vivo", "device_list_full_import"); // Device_List:L3355
        put(m, "V2283A", "vivo S17", "vivo S17", "vivo", "device_list_full_import"); // Device_List:L3356
        put(m, "V2282A", "vivo S17t", "vivo S17t", "vivo", "device_list_full_import"); // Device_List:L3357
        put(m, "V2284A", "vivo S17 Pro", "vivo S17 Pro", "vivo", "device_list_full_import"); // Device_List:L3358
        put(m, "V2285A", "vivo S17e", "vivo S17e", "vivo", "device_list_full_import"); // Device_List:L3359
        put(m, "V2323A", "vivo S18", "vivo S18", "vivo", "device_list_full_import"); // Device_List:L3360
        put(m, "V2344A", "vivo S18 Pro", "vivo S18 Pro", "vivo", "device_list_full_import"); // Device_List:L3361
        put(m, "V2334A", "vivo S18e", "vivo S18e", "vivo", "device_list_full_import"); // Device_List:L3362
        put(m, "V2364A", "vivo S19", "vivo S19", "vivo", "device_list_full_import"); // Device_List:L3363
        put(m, "V2362A", "vivo S19 Pro", "vivo S19 Pro", "vivo", "device_list_full_import"); // Device_List:L3364
        put(m, "V2429A", "vivo S20", "vivo S20", "vivo", "device_list_full_import"); // Device_List:L3365
        put(m, "V2430A", "vivo S20 Pro", "vivo S20 Pro", "vivo", "device_list_full_import"); // Device_List:L3366
        put(m, "V2464A", "vivo S30", "vivo S30", "vivo", "device_list_full_import"); // Device_List:L3367
        put(m, "V2465A", "vivo S30 Pro mini", "vivo S30 Pro mini", "vivo", "device_list_full_import"); // Device_List:L3368
        put(m, "V2528A", "vivo S50 / vivo S50t", "vivo S50 / vivo S50t", "vivo", "device_list_full_import"); // Device_List:L3369
        put(m, "V2527A", "vivo S50 Pro mini", "vivo S50 Pro mini", "vivo", "device_list_full_import"); // Device_List:L3370
        put(m, "V2571A", "vivo S60", "vivo S60", "vivo", "device_list_full_import"); // Device_List:L3371
        put(m, "V2572A", "vivo S60 元氣版", "vivo S60 元氣版", "vivo", "device_list_full_import"); // Device_List:L3372
        put(m, "V1901A", "vivo Y3 全網通版", "vivo Y3 全網通版", "vivo", "device_list_full_import"); // Device_List:L3373
        put(m, "V1901T", "vivo Y3 移動全網通版", "vivo Y3 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3374
        put(m, "V1930A", "vivo Y3 標準版 全網通版", "vivo Y3 標準版 全網通版", "vivo", "device_list_full_import"); // Device_List:L3375
        put(m, "V1930T", "vivo Y3 標準版 移動全網通版", "vivo Y3 標準版 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3376
        put(m, "V1934A", "vivo Y5s 全網通版", "vivo Y5s 全網通版", "vivo", "device_list_full_import"); // Device_List:L3377
        put(m, "V1934T", "vivo Y5s 移動全網通版", "vivo Y5s 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3378
        put(m, "V1913A", "vivo Y7s 全網通版", "vivo Y7s 全網通版", "vivo", "device_list_full_import"); // Device_List:L3379
        put(m, "V1913T", "vivo Y7s 移動全網通版", "vivo Y7s 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3380
        put(m, "V1945A", "vivo Y9s 全網通版", "vivo Y9s 全網通版", "vivo", "device_list_full_import"); // Device_List:L3381
        put(m, "V1945T", "vivo Y9s 移動全網通版", "vivo Y9s 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3382
        put(m, "V2140A", "vivo Y10", "vivo Y10", "vivo", "device_list_full_import"); // Device_List:L3383
        put(m, "V2168A", "vivo Y10 (t1 版)", "vivo Y10 (t1 版)", "vivo", "device_list_full_import"); // Device_List:L3384
        put(m, "V2180A", "vivo Y10 (t2 版)", "vivo Y10 (t2 版)", "vivo", "device_list_full_import"); // Device_List:L3385
        put(m, "V2236A", "vivo Y11", "vivo Y11", "vivo", "device_list_full_import"); // Device_List:L3386
        put(m, "V2317A", "vivo Y12", "vivo Y12", "vivo", "device_list_full_import"); // Device_List:L3387
        put(m, "V2034A", "vivo Y30", "vivo Y30", "vivo", "device_list_full_import"); // Device_List:L3388
        put(m, "V2036A", "vivo Y30 標準版", "vivo Y30 標準版", "vivo", "device_list_full_import"); // Device_List:L3389
        put(m, "V2099A", "vivo Y30 2021", "vivo Y30 2021", "vivo", "device_list_full_import"); // Device_List:L3390
        put(m, "V2066A", "vivo Y30 活力版", "vivo Y30 活力版", "vivo", "device_list_full_import"); // Device_List:L3391
        put(m, "V2066BA", "vivo Y30g", "vivo Y30g", "vivo", "device_list_full_import"); // Device_List:L3392
        put(m, "V2054A", "vivo Y31s 5G", "vivo Y31s 5G", "vivo", "device_list_full_import"); // Device_List:L3393
        put(m, "V2068A", "vivo Y31s 標準版 5G", "vivo Y31s 標準版 5G", "vivo", "device_list_full_import"); // Device_List:L3394
        put(m, "V2158A", "vivo Y32", "vivo Y32", "vivo", "device_list_full_import"); // Device_List:L3395
        put(m, "V2166A", "vivo Y33s 5G", "vivo Y33s 5G", "vivo", "device_list_full_import"); // Device_List:L3396
        put(m, "V2230A", "vivo Y35 5G / vivo Y35m 5G", "vivo Y35 5G / vivo Y35m 5G", "vivo", "device_list_full_import"); // Device_List:L3397
        put(m, "V2279A", "vivo Y35+ 5G / vivo Y35m+ 5G", "vivo Y35+ 5G / vivo Y35m+ 5G", "vivo", "device_list_full_import"); // Device_List:L3398
        put(m, "V2318A", "vivo Y36 5G / vivo Y36m 5G / vivo Y36i 5G / vivo Y36s 5G", "vivo Y36 5G / vivo Y36m 5G / vivo Y36i 5G / vivo Y36s 5G", "vivo", "device_list_full_import"); // Device_List:L3399
        put(m, "V2327A", "vivo Y36t", "vivo Y36t", "vivo", "device_list_full_import"); // Device_List:L3400
        put(m, "V2357A", "vivo Y36c 5G / vivo Y37 5G", "vivo Y36c 5G / vivo Y37 5G", "vivo", "device_list_full_import"); // Device_List:L3401
        put(m, "V2357EA", "vivo Y37m 5G", "vivo Y37m 5G", "vivo", "device_list_full_import"); // Device_List:L3402
        put(m, "V2354A", "vivo Y37 Pro 5G", "vivo Y37 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3403
        put(m, "V2442A", "vivo Y37c", "vivo Y37c", "vivo", "device_list_full_import"); // Device_List:L3404
        put(m, "V1965A", "vivo Y50", "vivo Y50", "vivo", "device_list_full_import"); // Device_List:L3405
        put(m, "V2023EA", "vivo Y50t", "vivo Y50t", "vivo", "device_list_full_import"); // Device_List:L3406
        put(m, "V2443A", "vivo Y37t 5G / vivo Y37+ 5G / vivo Y50 5G / vivo Y50i 5G / vivo Y50e 5G / vivo Y50s 5G", "vivo Y37t 5G / vivo Y37+ 5G / vivo Y50 5G / vivo Y50i 5G / vivo Y50e 5G / vivo Y50s 5G", "vivo", "device_list_full_import"); // Device_List:L3407
        put(m, "V2443BA", "vivo Y50m 5G / vivo Y50c 5G", "vivo Y50m 5G / vivo Y50c 5G", "vivo", "device_list_full_import"); // Device_List:L3408
        put(m, "V2002A", "vivo Y51s 5G", "vivo Y51s 5G", "vivo", "device_list_full_import"); // Device_List:L3409
        put(m, "V2057A", "vivo Y52s 5G", "vivo Y52s 5G", "vivo", "device_list_full_import"); // Device_List:L3410
        put(m, "V2111A", "vivo Y53s 5G", "vivo Y53s 5G", "vivo", "device_list_full_import"); // Device_List:L3411
        put(m, "V2069A", "vivo Y53s (t1 版) 5G", "vivo Y53s (t1 版) 5G", "vivo", "device_list_full_import"); // Device_List:L3412
        put(m, "V2123A", "vivo Y53s (t2 版) 5G", "vivo Y53s (t2 版) 5G", "vivo", "device_list_full_import"); // Device_List:L3413
        put(m, "V2045A", "vivo Y54s 5G", "vivo Y54s 5G", "vivo", "device_list_full_import"); // Device_List:L3414
        put(m, "V2164A", "vivo Y55s 5G", "vivo Y55s 5G", "vivo", "device_list_full_import"); // Device_List:L3415
        put(m, "V2541A", "vivo Y6c", "vivo Y6c", "vivo", "device_list_full_import"); // Device_List:L3416
        put(m, "V2559A", "vivo Y60 / vivo Y6t / vivo Y6e", "vivo Y60 / vivo Y6t / vivo Y6e", "vivo", "device_list_full_import"); // Device_List:L3417
        put(m, "V2559BA", "vivo Y60m / vivo Y60s m 版", "vivo Y60m / vivo Y60s m 版", "vivo", "device_list_full_import"); // Device_List:L3418
        put(m, "V2532BA", "vivo Y6m", "vivo Y6m", "vivo", "device_list_full_import"); // Device_List:L3419
        put(m, "V2542A", "vivo Y60i / vivo Y60i m 版 / vivo Y6t m 版", "vivo Y60i / vivo Y60i m 版 / vivo Y6t m 版", "vivo", "device_list_full_import"); // Device_List:L3420
        put(m, "V1731CA", "vivo Y71s", "vivo Y71s", "vivo", "device_list_full_import"); // Device_List:L3421
        put(m, "V2102A", "vivo Y71t 5G", "vivo Y71t 5G", "vivo", "device_list_full_import"); // Device_List:L3422
        put(m, "V2164PA", "vivo Y73t 5G", "vivo Y73t 5G", "vivo", "device_list_full_import"); // Device_List:L3423
        put(m, "V2009A", "vivo Y74s 5G", "vivo Y74s 5G", "vivo", "device_list_full_import"); // Device_List:L3424
    }

    private static void fill19(Map<String, Entry> m) {
        put(m, "V2069BA", "vivo Y75s 5G", "vivo Y75s 5G", "vivo", "device_list_full_import"); // Device_List:L3425
        put(m, "V2156A", "vivo Y76s 5G", "vivo Y76s 5G", "vivo", "device_list_full_import"); // Device_List:L3426
        put(m, "V2156FA", "vivo Y76s (t1 版) 5G", "vivo Y76s (t1 版) 5G", "vivo", "device_list_full_import"); // Device_List:L3427
        put(m, "V2219A", "vivo Y77 5G", "vivo Y77 5G", "vivo", "device_list_full_import"); // Device_List:L3428
        put(m, "V2166BA", "vivo Y77e 5G / vivo Y77e (t1 版) 5G", "vivo Y77e 5G / vivo Y77e (t1 版) 5G", "vivo", "device_list_full_import"); // Device_List:L3429
        put(m, "V2278A", "vivo Y77t 5G / vivo Y78 5G / vivo Y78m 5G", "vivo Y77t 5G / vivo Y78 5G / vivo Y78m 5G", "vivo", "device_list_full_import"); // Device_List:L3430
        put(m, "V2271A", "vivo Y78+ 5G / vivo Y78+ (t1) 5G", "vivo Y78+ 5G / vivo Y78+ (t1) 5G", "vivo", "device_list_full_import"); // Device_List:L3431
        put(m, "V2312BA", "vivo Y78t 5G", "vivo Y78t 5G", "vivo", "device_list_full_import"); // Device_List:L3432
        put(m, "V1732A", "vivo Y81 全網通版", "vivo Y81 全網通版", "vivo", "device_list_full_import"); // Device_List:L3433
        put(m, "V1732T", "vivo Y81 移動全網通版", "vivo Y81 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3434
        put(m, "V1730EA", "vivo Y89", "vivo Y89", "vivo", "device_list_full_import"); // Device_List:L3435
        put(m, "V1818CA", "vivo Y91 全網通版", "vivo Y91 全網通版", "vivo", "device_list_full_import"); // Device_List:L3436
        put(m, "V1818CT", "vivo Y91 移動全網通版", "vivo Y91 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3437
        put(m, "V1818A", "vivo Y93 全網通版", "vivo Y93 全網通版", "vivo", "device_list_full_import"); // Device_List:L3438
        put(m, "V1818T", "vivo Y93 移動全網通版", "vivo Y93 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3439
        put(m, "V1813A", "vivo Y97 全網通版", "vivo Y97 全網通版", "vivo", "device_list_full_import"); // Device_List:L3440
        put(m, "V1813T", "vivo Y97 移動全網通版", "vivo Y97 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3441
        put(m, "V2313A", "vivo Y100 5G", "vivo Y100 5G", "vivo", "device_list_full_import"); // Device_List:L3442
        put(m, "V2314DA", "vivo Y100t 5G", "vivo Y100t 5G", "vivo", "device_list_full_import"); // Device_List:L3443
        put(m, "V2343A", "vivo Y200 5G", "vivo Y200 5G", "vivo", "device_list_full_import"); // Device_List:L3444
        put(m, "V2361GA", "vivo Y200 GT 5G / vivo Y200 Pro 企業定制版", "vivo Y200 GT 5G / vivo Y200 Pro 企業定制版", "vivo", "device_list_full_import"); // Device_List:L3445
        put(m, "V2353DA", "vivo Y200t 5G", "vivo Y200t 5G", "vivo", "device_list_full_import"); // Device_List:L3446
        put(m, "V2435A", "vivo Y300 5G / vivo Y300c", "vivo Y300 5G / vivo Y300c", "vivo", "device_list_full_import"); // Device_List:L3447
        put(m, "V2444A", "vivo Y300i 5G", "vivo Y300i 5G", "vivo", "device_list_full_import"); // Device_List:L3448
        put(m, "V2410A", "vivo Y300 Pro", "vivo Y300 Pro", "vivo", "device_list_full_import"); // Device_List:L3449
        put(m, "V2456A", "vivo Y300 Pro+", "vivo Y300 Pro+", "vivo", "device_list_full_import"); // Device_List:L3450
        put(m, "V2445EA", "vivo Y300t / vivo Y300+", "vivo Y300t / vivo Y300+", "vivo", "device_list_full_import"); // Device_List:L3451
        put(m, "V2452GA", "vivo Y300 GT", "vivo Y300 GT", "vivo", "device_list_full_import"); // Device_List:L3452
        put(m, "V2506A", "vivo Y500", "vivo Y500", "vivo", "device_list_full_import"); // Device_List:L3453
        put(m, "V2516A", "vivo Y500 Pro", "vivo Y500 Pro", "vivo", "device_list_full_import"); // Device_List:L3454
        put(m, "V2531A", "vivo Y500i / vivo Y500s / vivo Y6 / vivo Y6a", "vivo Y500i / vivo Y500s / vivo Y6 / vivo Y6a", "vivo", "device_list_full_import"); // Device_List:L3455
        put(m, "V2561A", "vivo Y600 Pro", "vivo Y600 Pro", "vivo", "device_list_full_import"); // Device_List:L3456
        put(m, "V2553A", "vivo Y600 Turbo", "vivo Y600 Turbo", "vivo", "device_list_full_import"); // Device_List:L3457
        put(m, "V2115A", "vivo T1", "vivo T1", "vivo", "device_list_full_import"); // Device_List:L3458
        put(m, "V2199GA", "vivo T2", "vivo T2", "vivo", "device_list_full_import"); // Device_List:L3459
        put(m, "V2188A", "vivo T2x", "vivo T2x", "vivo", "device_list_full_import"); // Device_List:L3460
        put(m, "V1801A0", "vivo Z1", "vivo Z1", "vivo", "device_list_full_import"); // Device_List:L3461
        put(m, "V1730DA", "vivo Z1i 全網通版", "vivo Z1i 全網通版", "vivo", "device_list_full_import"); // Device_List:L3462
        put(m, "V1730DT", "vivo Z1i 移動全網通版", "vivo Z1i 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3463
        put(m, "V1813BA", "vivo Z3 全網通版 (驍龍 670)", "vivo Z3 全網通版 (驍龍 670)", "vivo", "device_list_full_import"); // Device_List:L3464
        put(m, "V1813BT", "vivo Z3 全網通版 (驍龍 710)", "vivo Z3 全網通版 (驍龍 710)", "vivo", "device_list_full_import"); // Device_List:L3465
        put(m, "V1730GA", "vivo Z3x", "vivo Z3x", "vivo", "device_list_full_import"); // Device_List:L3466
        put(m, "V1921A", "vivo Z5 全網通版", "vivo Z5 全網通版", "vivo", "device_list_full_import"); // Device_List:L3467
        put(m, "V1921T", "vivo Z5 移動全網通版", "vivo Z5 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3468
        put(m, "V1911A", "vivo Z5x 全網通版", "vivo Z5x 全網通版", "vivo", "device_list_full_import"); // Device_List:L3469
        put(m, "V1919A", "vivo Z5x 移動全網通版", "vivo Z5x 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3470
        put(m, "V1990A", "vivo Z5x 712 版", "vivo Z5x 712 版", "vivo", "device_list_full_import"); // Device_List:L3471
        put(m, "V1941A", "vivo Z5i 全網通版", "vivo Z5i 全網通版", "vivo", "device_list_full_import"); // Device_List:L3472
        put(m, "V1941T", "vivo Z5i 移動全網通版", "vivo Z5i 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3473
        put(m, "V1963A", "vivo Z6 5G", "vivo Z6 5G", "vivo", "device_list_full_import"); // Device_List:L3474
        put(m, "V1928A", "vivo U3x 全網通版", "vivo U3x 全網通版", "vivo", "device_list_full_import"); // Device_List:L3475
        put(m, "V1928T", "vivo U3x 移動全網通版", "vivo U3x 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3476
        put(m, "V1962BA", "vivo G1", "vivo G1", "vivo", "device_list_full_import"); // Device_List:L3477
        put(m, "V1824BA", "iQOO (6GB+128GB)", "iQOO (6GB+128GB)", "vivo", "device_list_full_import"); // Device_List:L3478
        put(m, "V1824A", "iQOO (8GB+128GB/8GB+256GB/12GB+128GB/12GB+256GB)", "iQOO (8GB+128GB/8GB+256GB/12GB+128GB/12GB+256GB)", "vivo", "device_list_full_import"); // Device_List:L3479
        put(m, "V1922A", "iQOO Pro 全網通版", "iQOO Pro 全網通版", "vivo", "device_list_full_import"); // Device_List:L3480
        put(m, "V1922T", "iQOO Pro 移動全網通版", "iQOO Pro 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3481
        put(m, "V1916A", "iQOO Pro 5G 全網通版", "iQOO Pro 5G 全網通版", "vivo", "device_list_full_import"); // Device_List:L3482
        put(m, "V1916T", "iQOO Pro 5G 移動全網通版", "iQOO Pro 5G 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3483
        put(m, "V1955A", "iQOO 3", "iQOO 3", "vivo", "device_list_full_import"); // Device_List:L3484
        put(m, "V2024A", "iQOO 5", "iQOO 5", "vivo", "device_list_full_import"); // Device_List:L3485
        put(m, "V2025A", "iQOO 5 Pro", "iQOO 5 Pro", "vivo", "device_list_full_import"); // Device_List:L3486
        put(m, "V2049A", "iQOO 7", "iQOO 7", "vivo", "device_list_full_import"); // Device_List:L3487
        put(m, "V2136A", "iQOO 8", "iQOO 8", "vivo", "device_list_full_import"); // Device_List:L3488
        put(m, "V2141A", "iQOO 8 Pro", "iQOO 8 Pro", "vivo", "device_list_full_import"); // Device_List:L3489
        put(m, "V2171A", "iQOO 9", "iQOO 9", "vivo", "device_list_full_import"); // Device_List:L3490
        put(m, "V2172A", "iQOO 9 Pro", "iQOO 9 Pro", "vivo", "device_list_full_import"); // Device_List:L3491
        put(m, "V2217A", "iQOO 10", "iQOO 10", "vivo", "device_list_full_import"); // Device_List:L3492
        put(m, "V2218A", "iQOO 10 Pro", "iQOO 10 Pro", "vivo", "device_list_full_import"); // Device_List:L3493
        put(m, "V2243A", "iQOO 11", "iQOO 11", "vivo", "device_list_full_import"); // Device_List:L3494
        put(m, "V2254A", "iQOO 11 Pro", "iQOO 11 Pro", "vivo", "device_list_full_import"); // Device_List:L3495
        put(m, "V2304A", "iQOO 11S", "iQOO 11S", "vivo", "device_list_full_import"); // Device_List:L3496
        put(m, "V2307A", "iQOO 12", "iQOO 12", "vivo", "device_list_full_import"); // Device_List:L3497
        put(m, "V2329A", "iQOO 12 Pro", "iQOO 12 Pro", "vivo", "device_list_full_import"); // Device_List:L3498
        put(m, "V2408A", "iQOO 13", "iQOO 13", "vivo", "device_list_full_import"); // Device_List:L3499
        put(m, "V2505A", "iQOO 15", "iQOO 15", "vivo", "device_list_full_import"); // Device_List:L3500
        put(m, "V2546A", "iQOO 15 Ultra", "iQOO 15 Ultra", "vivo", "device_list_full_import"); // Device_List:L3501
        put(m, "V2564A", "iQOO 15T", "iQOO 15T", "vivo", "device_list_full_import"); // Device_List:L3502
        put(m, "V1914A", "iQOO Neo 全網通版", "iQOO Neo 全網通版", "vivo", "device_list_full_import"); // Device_List:L3503
        put(m, "V1914T", "iQOO Neo 移動全網通版", "iQOO Neo 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3504
        put(m, "V1936A", "iQOO Neo 855 版 全網通版", "iQOO Neo 855 版 全網通版", "vivo", "device_list_full_import"); // Device_List:L3505
        put(m, "V1936T", "iQOO Neo 855 版 移動全網通版", "iQOO Neo 855 版 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3506
        put(m, "V1936AL", "iQOO Neo 855 競速版 全網通版", "iQOO Neo 855 競速版 全網通版", "vivo", "device_list_full_import"); // Device_List:L3507
        put(m, "V1936TL", "iQOO Neo 855 競速版 移動全網通版", "iQOO Neo 855 競速版 移動全網通版", "vivo", "device_list_full_import"); // Device_List:L3508
        put(m, "V1981A", "iQOO Neo3", "iQOO Neo3", "vivo", "device_list_full_import"); // Device_List:L3509
        put(m, "V2055A", "iQOO Neo5", "iQOO Neo5", "vivo", "device_list_full_import"); // Device_List:L3510
        put(m, "V2118A", "iQOO Neo5 活力版", "iQOO Neo5 活力版", "vivo", "device_list_full_import"); // Device_List:L3511
        put(m, "V2154A", "iQOO Neo5S", "iQOO Neo5S", "vivo", "device_list_full_import"); // Device_List:L3512
        put(m, "V2157A", "iQOO Neo5 SE", "iQOO Neo5 SE", "vivo", "device_list_full_import"); // Device_List:L3513
        put(m, "V2196A", "iQOO Neo6", "iQOO Neo6", "vivo", "device_list_full_import"); // Device_List:L3514
        put(m, "V2199A", "iQOO Neo6 SE", "iQOO Neo6 SE", "vivo", "device_list_full_import"); // Device_List:L3515
        put(m, "V2231A", "iQOO Neo7", "iQOO Neo7", "vivo", "device_list_full_import"); // Device_List:L3516
        put(m, "V2232A", "iQOO Neo7 競速版", "iQOO Neo7 競速版", "vivo", "device_list_full_import"); // Device_List:L3517
        put(m, "V2238A", "iQOO Neo7 SE", "iQOO Neo7 SE", "vivo", "device_list_full_import"); // Device_List:L3518
        put(m, "V2301A", "iQOO Neo8", "iQOO Neo8", "vivo", "device_list_full_import"); // Device_List:L3519
        put(m, "V2302A", "iQOO Neo8 Pro", "iQOO Neo8 Pro", "vivo", "device_list_full_import"); // Device_List:L3520
        put(m, "V2338A", "iQOO Neo9", "iQOO Neo9", "vivo", "device_list_full_import"); // Device_List:L3521
        put(m, "V2339A", "iQOO Neo9 Pro", "iQOO Neo9 Pro", "vivo", "device_list_full_import"); // Device_List:L3522
        put(m, "V2339FA", "iQOO Neo9S Pro", "iQOO Neo9S Pro", "vivo", "device_list_full_import"); // Device_List:L3523
        put(m, "V2403A", "iQOO Neo9S Pro+", "iQOO Neo9S Pro+", "vivo", "device_list_full_import"); // Device_List:L3524
        put(m, "V2425A", "iQOO Neo10", "iQOO Neo10", "vivo", "device_list_full_import"); // Device_List:L3525
        put(m, "V2426A", "iQOO Neo10 Pro", "iQOO Neo10 Pro", "vivo", "device_list_full_import"); // Device_List:L3526
        put(m, "V2463A", "iQOO Neo10 Pro+", "iQOO Neo10 Pro+", "vivo", "device_list_full_import"); // Device_List:L3527
        put(m, "V2520A", "iQOO Neo11", "iQOO Neo11", "vivo", "device_list_full_import"); // Device_List:L3528
        put(m, "V1986A", "iQOO Z1", "iQOO Z1", "vivo", "device_list_full_import"); // Device_List:L3529
        put(m, "V2012A", "iQOO Z1x", "iQOO Z1x", "vivo", "device_list_full_import"); // Device_List:L3530
        put(m, "V2073A", "iQOO Z3", "iQOO Z3", "vivo", "device_list_full_import"); // Device_List:L3531
        put(m, "V2148A", "iQOO Z5", "iQOO Z5", "vivo", "device_list_full_import"); // Device_List:L3532
        put(m, "V2131A", "iQOO Z5x", "iQOO Z5x", "vivo", "device_list_full_import"); // Device_List:L3533
        put(m, "V2220A", "iQOO Z6 / iQOO Z6 活力版", "iQOO Z6 / iQOO Z6 活力版", "vivo", "device_list_full_import"); // Device_List:L3534
        put(m, "V2164KA", "iQOO Z6x", "iQOO Z6x", "vivo", "device_list_full_import"); // Device_List:L3535
        put(m, "V2270A", "iQOO Z7", "iQOO Z7", "vivo", "device_list_full_import"); // Device_List:L3536
        put(m, "V2272A", "iQOO Z7x", "iQOO Z7x", "vivo", "device_list_full_import"); // Device_List:L3537
        put(m, "V2230EA", "iQOO Z7i", "iQOO Z7i", "vivo", "device_list_full_import"); // Device_List:L3538
        put(m, "V2314A", "iQOO Z8", "iQOO Z8", "vivo", "device_list_full_import"); // Device_List:L3539
        put(m, "V2312A", "iQOO Z8x", "iQOO Z8x", "vivo", "device_list_full_import"); // Device_List:L3540
        put(m, "V2361A", "iQOO Z9", "iQOO Z9", "vivo", "device_list_full_import"); // Device_List:L3541
        put(m, "V2352A", "iQOO Z9 Turbo", "iQOO Z9 Turbo", "vivo", "device_list_full_import"); // Device_List:L3542
        put(m, "V2352GA", "iQOO Z9 Turbo 長續航版", "iQOO Z9 Turbo 長續航版", "vivo", "device_list_full_import"); // Device_List:L3543
        put(m, "V2417A", "iQOO Z9 Turbo+", "iQOO Z9 Turbo+", "vivo", "device_list_full_import"); // Device_List:L3544
        put(m, "V2353A", "iQOO Z9x", "iQOO Z9x", "vivo", "device_list_full_import"); // Device_List:L3545
        put(m, "V2452A", "iQOO Z10 Turbo", "iQOO Z10 Turbo", "vivo", "device_list_full_import"); // Device_List:L3546
        put(m, "V2453A", "iQOO Z10 Turbo Pro", "iQOO Z10 Turbo Pro", "vivo", "device_list_full_import"); // Device_List:L3547
        put(m, "V2507A", "iQOO Z10 Turbo+", "iQOO Z10 Turbo+", "vivo", "device_list_full_import"); // Device_List:L3548
        put(m, "V2445A", "iQOO Z10x", "iQOO Z10x", "vivo", "device_list_full_import"); // Device_List:L3549
        put(m, "V2536A", "iQOO Z11 Turbo", "iQOO Z11 Turbo", "vivo", "device_list_full_import"); // Device_List:L3550
        put(m, "V2551A", "iQOO Z11", "iQOO Z11", "vivo", "device_list_full_import"); // Device_List:L3551
        put(m, "V2532A", "iQOO Z11x", "iQOO Z11x", "vivo", "device_list_full_import"); // Device_List:L3552
        put(m, "V2559UA", "iQOO Z11i", "iQOO Z11i", "vivo", "device_list_full_import"); // Device_List:L3553
        put(m, "V2023A", "iQOO U1", "iQOO U1", "vivo", "device_list_full_import"); // Device_List:L3554
        put(m, "V2065A", "iQOO U1x", "iQOO U1x", "vivo", "device_list_full_import"); // Device_List:L3555
        put(m, "V2061A", "iQOO U3 5G", "iQOO U3 5G", "vivo", "device_list_full_import"); // Device_List:L3556
        put(m, "V2106A", "iQOO U3x 5G", "iQOO U3x 5G", "vivo", "device_list_full_import"); // Device_List:L3557
        put(m, "V2143A", "iQOO U3x 標準版", "iQOO U3x 標準版", "vivo", "device_list_full_import"); // Device_List:L3558
        put(m, "V2165A", "iQOO U5 5G", "iQOO U5 5G", "vivo", "device_list_full_import"); // Device_List:L3559
        put(m, "V2180GA", "iQOO U5x", "iQOO U5x", "vivo", "device_list_full_import"); // Device_List:L3560
        put(m, "V2197A", "iQOO U5e 5G", "iQOO U5e 5G", "vivo", "device_list_full_import"); // Device_List:L3561
        put(m, "PA2170", "vivo Pad", "vivo Pad", "vivo", "device_list_full_import"); // Device_List:L3562
        put(m, "PA2373", "vivo Pad2", "vivo Pad2", "vivo", "device_list_full_import"); // Device_List:L3563
        put(m, "PA2353", "vivo Pad Air", "vivo Pad Air", "vivo", "device_list_full_import"); // Device_List:L3564
        put(m, "PA2455", "vivo Pad3", "vivo Pad3", "vivo", "device_list_full_import"); // Device_List:L3565
        put(m, "PA2473", "vivo Pad3 Pro", "vivo Pad3 Pro", "vivo", "device_list_full_import"); // Device_List:L3566
        put(m, "PA2553", "vivo Pad5", "vivo Pad5", "vivo", "device_list_full_import"); // Device_List:L3567
        put(m, "PA2573", "vivo Pad5 Pro", "vivo Pad5 Pro", "vivo", "device_list_full_import"); // Device_List:L3568
        put(m, "PA2535", "vivo Pad5e / vivo Pad5c", "vivo Pad5e / vivo Pad5c", "vivo", "device_list_full_import"); // Device_List:L3569
        put(m, "PA2511", "vivo Pad SE", "vivo Pad SE", "vivo", "device_list_full_import"); // Device_List:L3570
        put(m, "PA2671", "vivo Pad6 Pro", "vivo Pad6 Pro", "vivo", "device_list_full_import"); // Device_List:L3571
        put(m, "iPA2375", "iQOO Pad", "iQOO Pad", "vivo", "device_list_full_import"); // Device_List:L3572
        put(m, "iPA2451", "iQOO Pad Air", "iQOO Pad Air", "vivo", "device_list_full_import"); // Device_List:L3573
        put(m, "iPA2453", "iQOO Pad2", "iQOO Pad2", "vivo", "device_list_full_import"); // Device_List:L3574
        put(m, "iPA2475", "iQOO Pad2 Pro", "iQOO Pad2 Pro", "vivo", "device_list_full_import"); // Device_List:L3575
        put(m, "iPA2556", "iQOO Pad5", "iQOO Pad5", "vivo", "device_list_full_import"); // Device_List:L3576
        put(m, "iPA2575", "iQOO Pad5 Pro", "iQOO Pad5 Pro", "vivo", "device_list_full_import"); // Device_List:L3577
        put(m, "iPA2537", "iQOO Pad5e / iQOO Pad5c", "iQOO Pad5e / iQOO Pad5c", "vivo", "device_list_full_import"); // Device_List:L3578
        put(m, "iPA2673", "iQOO Pad6 Pro", "iQOO Pad6 Pro", "vivo", "device_list_full_import"); // Device_List:L3579
        put(m, "WA2052", "vivo WATCH 42mm", "vivo WATCH 42mm", "vivo", "device_list_full_import"); // Device_List:L3580
        put(m, "WA2056", "vivo WATCH 46mm", "vivo WATCH 46mm", "vivo", "device_list_full_import"); // Device_List:L3581
        put(m, "WA2156A", "vivo WATCH 2 eSIM 版", "vivo WATCH 2 eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3582
        put(m, "WA2356A", "vivo WATCH 3 eSIM 版 / ECG 版", "vivo WATCH 3 eSIM 版 / ECG 版", "vivo", "device_list_full_import"); // Device_List:L3583
        put(m, "WA2356C", "vivo WATCH 3 藍牙版", "vivo WATCH 3 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3584
        put(m, "WA2456A", "vivo WATCH GT eSIM 版", "vivo WATCH GT eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3585
        put(m, "WA2456C", "vivo WATCH GT 藍牙版", "vivo WATCH GT 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3586
        put(m, "WA2556A", "vivo WATCH 5 藍牙版", "vivo WATCH 5 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3587
        put(m, "WA2556B", "vivo WATCH 5 eSIM 版", "vivo WATCH 5 eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3588
        put(m, "WA2536A", "vivo WATCH GT 2 藍牙版", "vivo WATCH GT 2 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3589
        put(m, "WA2536B", "vivo WATCH GT 2 eSIM 版", "vivo WATCH GT 2 eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3590
        put(m, "iWA2356A", "iQOO WATCH eSIM 版", "iQOO WATCH eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3591
        put(m, "iWA2356C", "iQOO WATCH 藍牙版", "iQOO WATCH 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3592
        put(m, "iWA2456A", "iQOO WATCH GT eSIM 版", "iQOO WATCH GT eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3593
        put(m, "iWA2456C", "iQOO WATCH GT 藍牙版", "iQOO WATCH GT 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3594
        put(m, "iWA2556A", "iQOO WATCH 5 藍牙版", "iQOO WATCH 5 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3595
        put(m, "iWA2556B", "iQOO WATCH 5 eSIM 版", "iQOO WATCH 5 eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3596
        put(m, "iWA2536A", "iQOO WATCH GT 2 藍牙版", "iQOO WATCH GT 2 藍牙版", "vivo", "device_list_full_import"); // Device_List:L3597
        put(m, "iWA2536C", "iQOO WATCH GT 2 eSIM 版", "iQOO WATCH GT 2 eSIM 版", "vivo", "device_list_full_import"); // Device_List:L3598
        put(m, "vivo 2005", "vivo X50", "vivo X50", "vivo", "device_list_full_import"); // Device_List:L3599
        put(m, "V2006", "vivo X50 Pro", "vivo X50 Pro", "vivo", "device_list_full_import"); // Device_List:L3600
        put(m, "V1930", "vivo X50e 5G", "vivo X50e 5G", "vivo", "device_list_full_import"); // Device_List:L3601
        put(m, "V1937", "vivo X50 Lite", "vivo X50 Lite", "vivo", "device_list_full_import"); // Device_List:L3602
        put(m, "V2045", "vivo X60", "vivo X60", "vivo", "device_list_full_import"); // Device_List:L3603
        put(m, "V2046", "vivo X60 Pro", "vivo X60 Pro", "vivo", "device_list_full_import"); // Device_List:L3604
    }

    private static void fill20(Map<String, Entry> m) {
        put(m, "V2047", "vivo X60 Pro+", "vivo X60 Pro+", "vivo", "device_list_full_import"); // Device_List:L3605
        put(m, "V2104", "vivo X70", "vivo X70", "vivo", "device_list_full_import"); // Device_List:L3606
        put(m, "V2105", "vivo X70 Pro", "vivo X70 Pro", "vivo", "device_list_full_import"); // Device_List:L3607
        put(m, "V2114", "vivo X70 Pro+", "vivo X70 Pro+", "vivo", "device_list_full_import"); // Device_List:L3608
        put(m, "V2144", "vivo X80", "vivo X80", "vivo", "device_list_full_import"); // Device_List:L3609
        put(m, "V2145", "vivo X80 Pro", "vivo X80 Pro", "vivo", "device_list_full_import"); // Device_List:L3610
        put(m, "V2208", "vivo X80 Lite 5G", "vivo X80 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3611
        put(m, "V2218", "vivo X90", "vivo X90", "vivo", "device_list_full_import"); // Device_List:L3612
        put(m, "V2219", "vivo X90 Pro", "vivo X90 Pro", "vivo", "device_list_full_import"); // Device_List:L3613
        put(m, "V2308", "vivo X100", "vivo X100", "vivo", "device_list_full_import"); // Device_List:L3614
        put(m, "V2309", "vivo X100 Pro", "vivo X100 Pro", "vivo", "device_list_full_import"); // Device_List:L3615
        put(m, "V2330", "vivo X Fold3 Pro", "vivo X Fold3 Pro", "vivo", "device_list_full_import"); // Device_List:L3616
        put(m, "V2415", "vivo X200", "vivo X200", "vivo", "device_list_full_import"); // Device_List:L3617
        put(m, "V2413", "vivo X200 Pro", "vivo X200 Pro", "vivo", "device_list_full_import"); // Device_List:L3618
        put(m, "V2505", "vivo X200 FE", "vivo X200 FE", "vivo", "device_list_full_import"); // Device_List:L3619
        put(m, "V2561", "vivo X200T", "vivo X200T", "vivo", "device_list_full_import"); // Device_List:L3620
        put(m, "V2429", "vivo X Fold5", "vivo X Fold5", "vivo", "device_list_full_import"); // Device_List:L3621
        put(m, "V2515", "vivo X300", "vivo X300", "vivo", "device_list_full_import"); // Device_List:L3622
        put(m, "V2514", "vivo X300 Pro", "vivo X300 Pro", "vivo", "device_list_full_import"); // Device_List:L3623
        put(m, "V2633", "vivo X300 FE", "vivo X300 FE", "vivo", "device_list_full_import"); // Device_List:L3624
        put(m, "V2562", "vivo X300 Ultra", "vivo X300 Ultra", "vivo", "device_list_full_import"); // Device_List:L3625
        put(m, "vivo 1819", "vivo V15", "vivo V15", "vivo", "device_list_full_import"); // Device_List:L3626
        put(m, "vivo 1920", "vivo V17", "vivo V17", "vivo", "device_list_full_import"); // Device_List:L3627
        put(m, "vivo 1907", "vivo V17 Neo", "vivo V17 Neo", "vivo", "device_list_full_import"); // Device_List:L3628
        put(m, "V2025", "vivo V20", "vivo V20", "vivo", "device_list_full_import"); // Device_List:L3629
        put(m, "vivo 2018", "vivo V20 Pro", "vivo V20 Pro", "vivo", "device_list_full_import"); // Device_List:L3630
        put(m, "V2023", "vivo V20 SE", "vivo V20 SE", "vivo", "device_list_full_import"); // Device_List:L3631
        put(m, "V2040", "vivo V20 2021", "vivo V20 2021", "vivo", "device_list_full_import"); // Device_List:L3632
        put(m, "V2108", "vivo V21 5G", "vivo V21 5G", "vivo", "device_list_full_import"); // Device_List:L3633
        put(m, "V2061", "vivo V21e", "vivo V21e", "vivo", "device_list_full_import"); // Device_List:L3634
        put(m, "V2055", "vivo V21e 5G", "vivo V21e 5G", "vivo", "device_list_full_import"); // Device_List:L3635
        put(m, "V2130", "vivo V23 5G", "vivo V23 5G", "vivo", "device_list_full_import"); // Device_List:L3636
        put(m, "V2132", "vivo V23 Pro", "vivo V23 Pro", "vivo", "device_list_full_import"); // Device_List:L3637
        put(m, "V2116", "vivo V23e", "vivo V23e", "vivo", "device_list_full_import"); // Device_List:L3638
        put(m, "V2126", "vivo V23e 5G", "vivo V23e 5G", "vivo", "device_list_full_import"); // Device_List:L3639
        put(m, "V2228", "vivo V25", "vivo V25", "vivo", "device_list_full_import"); // Device_List:L3640
        put(m, "V2158", "vivo V25 Pro", "vivo V25 Pro", "vivo", "device_list_full_import"); // Device_List:L3641
        put(m, "V2242", "vivo V25e", "vivo V25e", "vivo", "device_list_full_import"); // Device_List:L3642
        put(m, "V2246", "vivo V27", "vivo V27", "vivo", "device_list_full_import"); // Device_List:L3643
        put(m, "V2230", "vivo V27 Pro", "vivo V27 Pro", "vivo", "device_list_full_import"); // Device_List:L3644
        put(m, "V2237", "vivo V27e", "vivo V27e", "vivo", "device_list_full_import"); // Device_List:L3645
        put(m, "V2250", "vivo V29", "vivo V29", "vivo", "device_list_full_import"); // Device_List:L3646
        put(m, "V2251", "vivo V29 Pro", "vivo V29 Pro", "vivo", "device_list_full_import"); // Device_List:L3647
        put(m, "V2317", "vivo V29e 5G Global", "vivo V29e 5G Global", "vivo", "device_list_full_import"); // Device_List:L3648
        put(m, "V2303", "vivo V29e 5G India", "vivo V29e 5G India", "vivo", "device_list_full_import"); // Device_List:L3649
        put(m, "V2244", "vivo V29 Lite 5G", "vivo V29 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3650
        put(m, "V2318", "vivo V30", "vivo V30", "vivo", "device_list_full_import"); // Device_List:L3651
        put(m, "V2319", "vivo V30 Pro", "vivo V30 Pro", "vivo", "device_list_full_import"); // Device_List:L3652
        put(m, "V2340", "vivo V30e", "vivo V30e", "vivo", "device_list_full_import"); // Device_List:L3653
        put(m, "V2342", "vivo V30 Lite", "vivo V30 Lite", "vivo", "device_list_full_import"); // Device_List:L3654
        put(m, "V2314", "vivo V30 Lite 5G Global", "vivo V30 Lite 5G Global", "vivo", "device_list_full_import"); // Device_List:L3655
        put(m, "V2327", "vivo V30 Lite 5G (ME)", "vivo V30 Lite 5G (ME)", "vivo", "device_list_full_import"); // Device_List:L3656
        put(m, "V2349", "vivo V30 SE", "vivo V30 SE", "vivo", "device_list_full_import"); // Device_List:L3657
        put(m, "V2348", "vivo V40", "vivo V40", "vivo", "device_list_full_import"); // Device_List:L3658
        put(m, "V2347", "vivo V40 Pro", "vivo V40 Pro", "vivo", "device_list_full_import"); // Device_List:L3659
        put(m, "V2403", "vivo V40e", "vivo V40e", "vivo", "device_list_full_import"); // Device_List:L3660
        put(m, "V2424", "vivo V40 Lite Indonesia", "vivo V40 Lite Indonesia", "vivo", "device_list_full_import"); // Device_List:L3661
        put(m, "V2341", "vivo V40 Lite 5G Global", "vivo V40 Lite 5G Global", "vivo", "device_list_full_import"); // Device_List:L3662
        put(m, "V2418", "vivo V40 Lite 5G Indonesia", "vivo V40 Lite 5G Indonesia", "vivo", "device_list_full_import"); // Device_List:L3663
        put(m, "V2337", "vivo V40 SE 5G", "vivo V40 SE 5G", "vivo", "device_list_full_import"); // Device_List:L3664
        put(m, "V2451", "vivo V50", "vivo V50", "vivo", "device_list_full_import"); // Device_List:L3665
        put(m, "V2428", "vivo V50e", "vivo V50e", "vivo", "device_list_full_import"); // Device_List:L3666
        put(m, "V2441", "vivo V50 Lite", "vivo V50 Lite", "vivo", "device_list_full_import"); // Device_List:L3667
        put(m, "V2453", "vivo V50 Lite 5G", "vivo V50 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3668
        put(m, "V2512", "vivo V60", "vivo V60", "vivo", "device_list_full_import"); // Device_List:L3669
        put(m, "V2549", "vivo V60 Lite", "vivo V60 Lite", "vivo", "device_list_full_import"); // Device_List:L3670
        put(m, "V2529", "vivo V60 Lite 5G", "vivo V60 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3671
        put(m, "V2513", "vivo V60e", "vivo V60e", "vivo", "device_list_full_import"); // Device_List:L3672
        put(m, "V2540", "vivo V70", "vivo V70", "vivo", "device_list_full_import"); // Device_List:L3673
        put(m, "V2548", "vivo V70 Elite", "vivo V70 Elite", "vivo", "device_list_full_import"); // Device_List:L3674
        put(m, "V2558", "vivo V70 FE", "vivo V70 FE", "vivo", "device_list_full_import"); // Device_List:L3675
        put(m, "V2637", "vivo V70 Lite 5G", "vivo V70 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3676
        put(m, "vivo 1920_20", "vivo S1 Pro", "vivo S1 Pro", "vivo", "device_list_full_import"); // Device_List:L3677
        put(m, "V2168", "vivo T1", "vivo T1", "vivo", "device_list_full_import"); // Device_List:L3678
        put(m, "V2157", "vivo T1 5G", "vivo T1 5G", "vivo", "device_list_full_import"); // Device_List:L3679
        put(m, "V2143", "vivo T1x", "vivo T1x", "vivo", "device_list_full_import"); // Device_List:L3680
        put(m, "V2151", "vivo T1 Pro 5G", "vivo T1 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3681
        put(m, "V2320", "vivo T2", "vivo T2", "vivo", "device_list_full_import"); // Device_List:L3682
        put(m, "V2240", "vivo T2 5G", "vivo T2 5G", "vivo", "device_list_full_import"); // Device_List:L3683
        put(m, "V2321", "vivo T2 Pro 5G", "vivo T2 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3684
        put(m, "V2312", "vivo T2x 5G", "vivo T2x 5G", "vivo", "device_list_full_import"); // Device_List:L3685
        put(m, "V2334", "vivo T3 5G", "vivo T3 5G", "vivo", "device_list_full_import"); // Device_List:L3686
        put(m, "V2338", "vivo T3x 5G", "vivo T3x 5G", "vivo", "device_list_full_import"); // Device_List:L3687
        put(m, "V2404", "vivo T3 Pro 5G", "vivo T3 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3688
        put(m, "V2356", "vivo T3 Lite 5G", "vivo T3 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3689
        put(m, "V2426", "vivo T3 Ultra 5G", "vivo T3 Ultra 5G", "vivo", "device_list_full_import"); // Device_List:L3690
        put(m, "V2502", "vivo T4 5G", "vivo T4 5G", "vivo", "device_list_full_import"); // Device_List:L3691
        put(m, "V2437", "vivo T4x 5G", "vivo T4x 5G", "vivo", "device_list_full_import"); // Device_List:L3692
        put(m, "V2509", "vivo T4 Lite 5G", "vivo T4 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3693
        put(m, "V2518", "vivo T4R 5G", "vivo T4R 5G", "vivo", "device_list_full_import"); // Device_List:L3694
        put(m, "V2510", "vivo T4 Pro", "vivo T4 Pro", "vivo", "device_list_full_import"); // Device_List:L3695
        put(m, "V2504", "vivo T4 Ultra", "vivo T4 Ultra", "vivo", "device_list_full_import"); // Device_List:L3696
        put(m, "V2583", "vivo T5", "vivo T5", "vivo", "device_list_full_import"); // Device_List:L3697
        put(m, "V2602", "vivo T5 Pro", "vivo T5 Pro", "vivo", "device_list_full_import"); // Device_List:L3698
        put(m, "V2545", "vivo T5x 5G", "vivo T5x 5G", "vivo", "device_list_full_import"); // Device_List:L3699
        put(m, "V2628", "vivo T5e", "vivo T5e", "vivo", "device_list_full_import"); // Device_List:L3700
        put(m, "V2603", "vivo T5 Lite 5G", "vivo T5 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3701
        put(m, "V2557", "vivo T5 Lite 44W 5G", "vivo T5 Lite 44W 5G", "vivo", "device_list_full_import"); // Device_List:L3702
        put(m, "vivo 2015_21", "vivo Y1s", "vivo Y1s", "vivo", "device_list_full_import"); // Device_List:L3703
        put(m, "V2044", "vivo Y3s", "vivo Y3s", "vivo", "device_list_full_import"); // Device_List:L3704
        put(m, "vivo 1902", "vivo Y5", "vivo Y5", "vivo", "device_list_full_import"); // Device_List:L3705
        put(m, "V2118", "vivo Y01", "vivo Y01", "vivo", "device_list_full_import"); // Device_List:L3706
        put(m, "V2166", "vivo Y01A", "vivo Y01A", "vivo", "device_list_full_import"); // Device_List:L3707
        put(m, "V2236", "vivo Y02", "vivo Y02", "vivo", "device_list_full_import"); // Device_List:L3708
        put(m, "V2234", "vivo Y02A", "vivo Y02A", "vivo", "device_list_full_import"); // Device_List:L3709
        put(m, "V2229", "vivo Y02s", "vivo Y02s", "vivo", "device_list_full_import"); // Device_List:L3710
        put(m, "V2325", "vivo Y02t", "vivo Y02t", "vivo", "device_list_full_import"); // Device_List:L3711
        put(m, "V2406", "vivo Y03", "vivo Y03", "vivo", "device_list_full_import"); // Device_List:L3712
        put(m, "V2409", "vivo Y03t", "vivo Y03t", "vivo", "device_list_full_import"); // Device_List:L3713
        put(m, "V2547", "vivo Y04", "vivo Y04", "vivo", "device_list_full_import"); // Device_List:L3714
        put(m, "V2532", "vivo Y04e", "vivo Y04e", "vivo", "device_list_full_import"); // Device_List:L3715
        put(m, "V2531", "vivo Y04s", "vivo Y04s", "vivo", "device_list_full_import"); // Device_List:L3716
        put(m, "V2565", "vivo Y05", "vivo Y05", "vivo", "device_list_full_import"); // Device_List:L3717
        put(m, "V2606", "vivo Y05e", "vivo Y05e", "vivo", "device_list_full_import"); // Device_List:L3718
        put(m, "V2575", "vivo Y11 5G", "vivo Y11 5G", "vivo", "device_list_full_import"); // Device_List:L3719
        put(m, "V2028", "vivo Y11s", "vivo Y11s", "vivo", "device_list_full_import"); // Device_List:L3720
        put(m, "V2646", "vivo Y11d", "vivo Y11d", "vivo", "device_list_full_import"); // Device_List:L3721
        put(m, "V2577", "vivo Y11e", "vivo Y11e", "vivo", "device_list_full_import"); // Device_List:L3722
        put(m, "vivo 1904", "vivo Y12", "vivo Y12", "vivo", "device_list_full_import"); // Device_List:L3723
        put(m, "V2026", "vivo Y12A", "vivo Y12A", "vivo", "device_list_full_import"); // Device_List:L3724
        put(m, "V2048", "vivo Y12D", "vivo Y12D", "vivo", "device_list_full_import"); // Device_List:L3725
        put(m, "V2026_21", "vivo Y12s", "vivo Y12s", "vivo", "device_list_full_import"); // Device_List:L3726
        put(m, "V2042", "vivo Y12s", "vivo Y12s", "vivo", "device_list_full_import"); // Device_List:L3727
        put(m, "vivo 1901", "vivo Y15", "vivo Y15", "vivo", "device_list_full_import"); // Device_List:L3728
        put(m, "V2134", "vivo Y15A", "vivo Y15A", "vivo", "device_list_full_import"); // Device_List:L3729
        put(m, "V2212", "vivo Y15C", "vivo Y15C", "vivo", "device_list_full_import"); // Device_List:L3730
        put(m, "V2139", "vivo Y15s", "vivo Y15s", "vivo", "device_list_full_import"); // Device_List:L3731
        put(m, "V2305", "vivo Y16", "vivo Y16", "vivo", "device_list_full_import"); // Device_List:L3732
        put(m, "V2331", "vivo Y17s", "vivo Y17s", "vivo", "device_list_full_import"); // Device_List:L3733
        put(m, "V2345", "vivo Y18", "vivo Y18", "vivo", "device_list_full_import"); // Device_List:L3734
        put(m, "V2410", "vivo Y18s", "vivo Y18s", "vivo", "device_list_full_import"); // Device_List:L3735
        put(m, "V2408", "vivo Y18t", "vivo Y18t", "vivo", "device_list_full_import"); // Device_List:L3736
        put(m, "V2350", "vivo Y18e", "vivo Y18e", "vivo", "device_list_full_import"); // Device_List:L3737
        put(m, "V2414", "vivo Y18i", "vivo Y18i", "vivo", "device_list_full_import"); // Device_List:L3738
        put(m, "vivo 1915", "vivo Y19", "vivo Y19", "vivo", "device_list_full_import"); // Device_List:L3739
        put(m, "V2432", "vivo Y19 5G", "vivo Y19 5G", "vivo", "device_list_full_import"); // Device_List:L3740
        put(m, "V2423", "vivo Y19s", "vivo Y19s", "vivo", "device_list_full_import"); // Device_List:L3741
        put(m, "V2541", "vivo Y19s 5G", "vivo Y19s 5G", "vivo", "device_list_full_import"); // Device_List:L3742
        put(m, "V2519", "vivo Y19s Pro", "vivo Y19s Pro", "vivo", "device_list_full_import"); // Device_List:L3743
        put(m, "V2526", "vivo Y19s GT 5G", "vivo Y19s GT 5G", "vivo", "device_list_full_import"); // Device_List:L3744
        put(m, "V2431", "vivo Y19e", "vivo Y19e", "vivo", "device_list_full_import"); // Device_List:L3745
        put(m, "V2027", "vivo Y20", "vivo Y20", "vivo", "device_list_full_import"); // Device_List:L3746
        put(m, "V2037", "vivo Y20G", "vivo Y20G", "vivo", "device_list_full_import"); // Device_List:L3747
        put(m, "V2032", "vivo Y20i", "vivo Y20i", "vivo", "device_list_full_import"); // Device_List:L3748
        put(m, "V2029", "vivo Y20s", "vivo Y20s", "vivo", "device_list_full_import"); // Device_List:L3749
        put(m, "V2038", "vivo Y20s [G]", "vivo Y20s [G]", "vivo", "device_list_full_import"); // Device_List:L3750
        put(m, "V2129", "vivo Y20T", "vivo Y20T", "vivo", "device_list_full_import"); // Device_List:L3751
        put(m, "V2043_21", "vivo Y20 2021", "vivo Y20 2021", "vivo", "device_list_full_import"); // Device_List:L3752
        put(m, "V2065", "vivo Y20G 2021", "vivo Y20G 2021", "vivo", "device_list_full_import"); // Device_List:L3753
        put(m, "V2111", "vivo Y21", "vivo Y21", "vivo", "device_list_full_import"); // Device_List:L3754
        put(m, "V2111-EG", "vivo Y21A", "vivo Y21A", "vivo", "device_list_full_import"); // Device_List:L3755
        put(m, "V2140", "vivo Y21e (2022)", "vivo Y21e (2022)", "vivo", "device_list_full_import"); // Device_List:L3756
        put(m, "V2152", "vivo Y21G", "vivo Y21G", "vivo", "device_list_full_import"); // Device_List:L3757
        put(m, "V2136", "vivo Y21s", "vivo Y21s", "vivo", "device_list_full_import"); // Device_List:L3758
        put(m, "V2135", "vivo Y21T", "vivo Y21T", "vivo", "device_list_full_import"); // Device_List:L3759
        put(m, "V2560", "vivo Y21d", "vivo Y21d", "vivo", "device_list_full_import"); // Device_List:L3760
        put(m, "V2525", "vivo Y21e (2025)", "vivo Y21e (2025)", "vivo", "device_list_full_import"); // Device_List:L3761
        put(m, "V2554", "vivo Y21 5G", "vivo Y21 5G", "vivo", "device_list_full_import"); // Device_List:L3762
        put(m, "V2238", "vivo Y22", "vivo Y22", "vivo", "device_list_full_import"); // Device_List:L3763
        put(m, "V2206", "vivo Y22s", "vivo Y22s", "vivo", "device_list_full_import"); // Device_List:L3764
        put(m, "V2313", "vivo Y22t", "vivo Y22t", "vivo", "device_list_full_import"); // Device_List:L3765
        put(m, "V2249", "vivo Y27", "vivo Y27", "vivo", "device_list_full_import"); // Device_List:L3766
        put(m, "V2302", "vivo Y27 5G", "vivo Y27 5G", "vivo", "device_list_full_import"); // Device_List:L3767
        put(m, "V2335", "vivo Y27s", "vivo Y27s", "vivo", "device_list_full_import"); // Device_List:L3768
        put(m, "V2353", "vivo Y28", "vivo Y28", "vivo", "device_list_full_import"); // Device_List:L3769
        put(m, "V2315", "vivo Y28 5G", "vivo Y28 5G", "vivo", "device_list_full_import"); // Device_List:L3770
        put(m, "V2351", "vivo Y28s 5G", "vivo Y28s 5G", "vivo", "device_list_full_import"); // Device_List:L3771
        put(m, "V2407", "vivo Y28e 5G", "vivo Y28e 5G", "vivo", "device_list_full_import"); // Device_List:L3772
        put(m, "V2435", "vivo Y29", "vivo Y29", "vivo", "device_list_full_import"); // Device_List:L3773
        put(m, "V2420", "vivo Y29 5G", "vivo Y29 5G", "vivo", "device_list_full_import"); // Device_List:L3774
        put(m, "V2446", "vivo Y29s 5G", "vivo Y29s 5G", "vivo", "device_list_full_import"); // Device_List:L3775
        put(m, "V2527", "vivo Y29t 5G", "vivo Y29t 5G", "vivo", "device_list_full_import"); // Device_List:L3776
        put(m, "V2160", "vivo Y30 5G", "vivo Y30 5G", "vivo", "device_list_full_import"); // Device_List:L3777
        put(m, "V2036_21", "vivo Y31", "vivo Y31", "vivo", "device_list_full_import"); // Device_List:L3778
        put(m, "V2521", "vivo Y31 5G", "vivo Y31 5G", "vivo", "device_list_full_import"); // Device_List:L3779
        put(m, "V2534", "vivo Y31 Pro 5G", "vivo Y31 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3780
        put(m, "V2636", "vivo Y31d", "vivo Y31d", "vivo", "device_list_full_import"); // Device_List:L3781
        put(m, "V2543", "vivo Y31d Pro", "vivo Y31d Pro", "vivo", "device_list_full_import"); // Device_List:L3782
        put(m, "V2533", "vivo Y31e 5G", "vivo Y31e 5G", "vivo", "device_list_full_import"); // Device_List:L3783
        put(m, "V2614", "vivo Y31s 5G", "vivo Y31s 5G", "vivo", "device_list_full_import"); // Device_List:L3784
    }

    private static void fill21(Map<String, Entry> m) {
        put(m, "V2057", "vivo Y33", "vivo Y33", "vivo", "device_list_full_import"); // Device_List:L3785
        put(m, "V2109-EG", "vivo Y33A", "vivo Y33A", "vivo", "device_list_full_import"); // Device_List:L3786
        put(m, "V2109", "vivo Y33s", "vivo Y33s", "vivo", "device_list_full_import"); // Device_List:L3787
        put(m, "V2146", "vivo Y33T", "vivo Y33T", "vivo", "device_list_full_import"); // Device_List:L3788
        put(m, "V2205", "vivo Y35", "vivo Y35", "vivo", "device_list_full_import"); // Device_List:L3789
        put(m, "V2324", "vivo Y36", "vivo Y36", "vivo", "device_list_full_import"); // Device_List:L3790
        put(m, "V2248", "vivo Y36 5G", "vivo Y36 5G", "vivo", "device_list_full_import"); // Device_List:L3791
        put(m, "V2343", "vivo Y38 5G", "vivo Y38 5G", "vivo", "device_list_full_import"); // Device_List:L3792
        put(m, "V2447", "vivo Y39 5G", "vivo Y39 5G", "vivo", "device_list_full_import"); // Device_List:L3793
        put(m, "V2035", "vivo Y51", "vivo Y51", "vivo", "device_list_full_import"); // Device_List:L3794
        put(m, "V2031_21", "vivo Y51s", "vivo Y51s", "vivo", "device_list_full_import"); // Device_List:L3795
        put(m, "V2613", "vivo Y51 Pro 5G", "vivo Y51 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3796
        put(m, "V2053", "vivo Y52 5G", "vivo Y52 5G", "vivo", "device_list_full_import"); // Device_List:L3797
        put(m, "V2058", "vivo Y53s", "vivo Y53s", "vivo", "device_list_full_import"); // Device_List:L3798
        put(m, "V2154", "vivo Y55", "vivo Y55", "vivo", "device_list_full_import"); // Device_List:L3799
        put(m, "V2127", "vivo Y55 5G", "vivo Y55 5G", "vivo", "device_list_full_import"); // Device_List:L3800
        put(m, "V2311", "vivo Y56 5G", "vivo Y56 5G", "vivo", "device_list_full_import"); // Device_List:L3801
        put(m, "V2355", "vivo Y58 5G", "vivo Y58 5G", "vivo", "device_list_full_import"); // Device_List:L3802
        put(m, "V2443", "vivo Y59 5G", "vivo Y59 5G", "vivo", "device_list_full_import"); // Device_List:L3803
        put(m, "V2041", "vivo Y72 5G Global", "vivo Y72 5G Global", "vivo", "device_list_full_import"); // Device_List:L3804
        put(m, "V2060", "vivo Y72 5G India", "vivo Y72 5G India", "vivo", "device_list_full_import"); // Device_List:L3805
        put(m, "V2059-EG", "vivo Y73", "vivo Y73", "vivo", "device_list_full_import"); // Device_List:L3806
        put(m, "V2117", "vivo Y75", "vivo Y75", "vivo", "device_list_full_import"); // Device_List:L3807
        put(m, "V2142", "vivo Y75 5G", "vivo Y75 5G", "vivo", "device_list_full_import"); // Device_List:L3808
        put(m, "V2124", "vivo Y76 5G", "vivo Y76 5G", "vivo", "device_list_full_import"); // Device_List:L3809
        put(m, "V2169", "vivo Y77 5G", "vivo Y77 5G", "vivo", "device_list_full_import"); // Device_List:L3810
        put(m, "V2412", "vivo Y100", "vivo Y100", "vivo", "device_list_full_import"); // Device_List:L3811
        put(m, "V2222", "vivo Y100A 5G", "vivo Y100A 5G", "vivo", "device_list_full_import"); // Device_List:L3812
        put(m, "V2425", "vivo Y200", "vivo Y200", "vivo", "device_list_full_import"); // Device_List:L3813
        put(m, "V2307", "vivo Y200 5G", "vivo Y200 5G", "vivo", "device_list_full_import"); // Device_List:L3814
        put(m, "V2401", "vivo Y200 Pro 5G", "vivo Y200 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3815
        put(m, "V2336", "vivo Y200e 5G", "vivo Y200e 5G", "vivo", "device_list_full_import"); // Device_List:L3816
        put(m, "V2416", "vivo Y300 5G", "vivo Y300 5G", "vivo", "device_list_full_import"); // Device_List:L3817
        put(m, "V2422", "vivo Y300+ 5G", "vivo Y300+ 5G", "vivo", "device_list_full_import"); // Device_List:L3818
        put(m, "V2402", "vivo Y300 Pro 5G", "vivo Y300 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3819
        put(m, "V2455", "vivo Y400", "vivo Y400", "vivo", "device_list_full_import"); // Device_List:L3820
        put(m, "V2506", "vivo Y400 5G", "vivo Y400 5G", "vivo", "device_list_full_import"); // Device_List:L3821
        put(m, "V2439", "vivo Y400 Pro 5G", "vivo Y400 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3822
        put(m, "I1927", "iQOO 3 4G", "iQOO 3 4G", "vivo", "device_list_full_import"); // Device_List:L3823
        put(m, "I1928", "iQOO 3 5G", "iQOO 3 5G", "vivo", "device_list_full_import"); // Device_List:L3824
        put(m, "I2009", "iQOO 7 Global", "iQOO 7 Global", "vivo", "device_list_full_import"); // Device_List:L3825
        put(m, "I2012", "iQOO 7 India", "iQOO 7 India", "vivo", "device_list_full_import"); // Device_List:L3826
        put(m, "I2017", "iQOO 9", "iQOO 9", "vivo", "device_list_full_import"); // Device_List:L3827
        put(m, "I2022", "iQOO 9 Pro", "iQOO 9 Pro", "vivo", "device_list_full_import"); // Device_List:L3828
        put(m, "I2019", "iQOO 9 SE", "iQOO 9 SE", "vivo", "device_list_full_import"); // Device_List:L3829
        put(m, "I2201", "iQOO 9T", "iQOO 9T", "vivo", "device_list_full_import"); // Device_List:L3830
        put(m, "I2212", "iQOO 11", "iQOO 11", "vivo", "device_list_full_import"); // Device_List:L3831
        put(m, "I2220", "iQOO 12", "iQOO 12", "vivo", "device_list_full_import"); // Device_List:L3832
        put(m, "I2401", "iQOO 13", "iQOO 13", "vivo", "device_list_full_import"); // Device_List:L3833
        put(m, "I2501", "iQOO 15", "iQOO 15", "vivo", "device_list_full_import"); // Device_List:L3834
        put(m, "I2508", "iQOO 15R", "iQOO 15R", "vivo", "device_list_full_import"); // Device_List:L3835
        put(m, "I2202", "iQOO Neo6", "iQOO Neo6", "vivo", "device_list_full_import"); // Device_List:L3836
        put(m, "I2214", "iQOO Neo7", "iQOO Neo7", "vivo", "device_list_full_import"); // Device_List:L3837
        put(m, "I2217", "iQOO Neo7 Pro", "iQOO Neo7 Pro", "vivo", "device_list_full_import"); // Device_List:L3838
        put(m, "I2304", "iQOO Neo9 Pro", "iQOO Neo9 Pro", "vivo", "device_list_full_import"); // Device_List:L3839
        put(m, "I2408", "iQOO Neo 10", "iQOO Neo 10", "vivo", "device_list_full_import"); // Device_List:L3840
        put(m, "I2221", "iQOO Neo 10R", "iQOO Neo 10R", "vivo", "device_list_full_import"); // Device_List:L3841
        put(m, "I2011", "iQOO Z3 5G", "iQOO Z3 5G", "vivo", "device_list_full_import"); // Device_List:L3842
        put(m, "I2018", "iQOO Z5", "iQOO Z5", "vivo", "device_list_full_import"); // Device_List:L3843
        put(m, "I2127", "iQOO Z6 5G", "iQOO Z6 5G", "vivo", "device_list_full_import"); // Device_List:L3844
        put(m, "I2206", "iQOO Z6 44W", "iQOO Z6 44W", "vivo", "device_list_full_import"); // Device_List:L3845
        put(m, "I2126", "iQOO Z6 Pro 5G", "iQOO Z6 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3846
        put(m, "I2208", "iQOO Z6 Lite 5G", "iQOO Z6 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3847
        put(m, "I2213", "iQOO Z7 5G Global", "iQOO Z7 5G Global", "vivo", "device_list_full_import"); // Device_List:L3848
        put(m, "I2207", "iQOO Z7 5G India", "iQOO Z7 5G India", "vivo", "device_list_full_import"); // Device_List:L3849
        put(m, "I2223", "iQOO Z7s 5G", "iQOO Z7s 5G", "vivo", "device_list_full_import"); // Device_List:L3850
        put(m, "I2216", "iQOO Z7x 5G", "iQOO Z7x 5G", "vivo", "device_list_full_import"); // Device_List:L3851
        put(m, "I2301", "iQOO Z7 Pro 5G", "iQOO Z7 Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3852
        put(m, "I2302", "iQOO Z9 5G", "iQOO Z9 5G", "vivo", "device_list_full_import"); // Device_List:L3853
        put(m, "I2219", "iQOO Z9x 5G", "iQOO Z9x 5G", "vivo", "device_list_full_import"); // Device_List:L3854
        put(m, "I2306", "iQOO Z9 Lite 5G", "iQOO Z9 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3855
        put(m, "I2403", "iQOO Z9s 5G", "iQOO Z9s 5G", "vivo", "device_list_full_import"); // Device_List:L3856
        put(m, "I2305", "iQOO Z9s Pro 5G", "iQOO Z9s Pro 5G", "vivo", "device_list_full_import"); // Device_List:L3857
        put(m, "I2407", "iQOO Z10 5G", "iQOO Z10 5G", "vivo", "device_list_full_import"); // Device_List:L3858
        put(m, "I2404", "iQOO Z10x 5G", "iQOO Z10x 5G", "vivo", "device_list_full_import"); // Device_List:L3859
        put(m, "I2409", "iQOO Z10 Lite 5G", "iQOO Z10 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3860
        put(m, "I2502", "iQOO Z10 Lite", "iQOO Z10 Lite", "vivo", "device_list_full_import"); // Device_List:L3861
        put(m, "I2410", "iQOO Z10R 5G India", "iQOO Z10R 5G India", "vivo", "device_list_full_import"); // Device_List:L3862
        put(m, "I2505", "iQOO Z10R 5G Global", "iQOO Z10R 5G Global", "vivo", "device_list_full_import"); // Device_List:L3863
        put(m, "I2512", "iQOO Z11 5G", "iQOO Z11 5G", "vivo", "device_list_full_import"); // Device_List:L3864
        put(m, "I2507", "iQOO Z11x 5G", "iQOO Z11x 5G", "vivo", "device_list_full_import"); // Device_List:L3865
        put(m, "I2510", "iQOO Z11 Lite 5G", "iQOO Z11 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3866
        put(m, "I2515", "iQOO Z11 Lite 44W 5G", "iQOO Z11 Lite 44W 5G", "vivo", "device_list_full_import"); // Device_List:L3867
        put(m, "J2505", "JOVI X300 FE", "JOVI X300 FE", "", "device_list_full_import"); // Device_List:L3868
        put(m, "J2510", "JOVI X300 Ultra", "JOVI X300 Ultra", "", "device_list_full_import"); // Device_List:L3869
        put(m, "V2427", "JOVI V50", "JOVI V50", "vivo", "device_list_full_import"); // Device_List:L3870
        put(m, "V2440", "JOVI V50 Lite 5G", "JOVI V50 Lite 5G", "vivo", "device_list_full_import"); // Device_List:L3871
        put(m, "J2507", "JOVI V70 5G", "JOVI V70 5G", "", "device_list_full_import"); // Device_List:L3872
        put(m, "J2502", "JOVI T1 5G", "JOVI T1 5G", "", "device_list_full_import"); // Device_List:L3873
        put(m, "V2454", "JOVI Y19s", "JOVI Y19s", "vivo", "device_list_full_import"); // Device_List:L3874
        put(m, "J2503", "JOVI Y21", "JOVI Y21", "", "device_list_full_import"); // Device_List:L3875
        put(m, "J2508", "JOVI Y21 5G", "JOVI Y21 5G", "", "device_list_full_import"); // Device_List:L3876
        put(m, "V2445", "JOVI Y29", "JOVI Y29", "vivo", "device_list_full_import"); // Device_List:L3877
        put(m, "V2459", "JOVI Y29s 5G", "JOVI Y29s 5G", "vivo", "device_list_full_import"); // Device_List:L3878
        put(m, "J2506", "JOVI Y31", "JOVI Y31", "", "device_list_full_import"); // Device_List:L3879
        put(m, "V2444", "JOVI Y39 5G", "JOVI Y39 5G", "vivo", "device_list_full_import"); // Device_List:L3880
        put(m, "PAFM00", "OPPO Find X 標準版 全網通版", "OPPO Find X 標準版 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3881
        put(m, "PAFT00", "OPPO Find X 標準版 移動版", "OPPO Find X 標準版 移動版", "OPPO", "device_list_full_import"); // Device_List:L3882
        put(m, "PAHM00", "OPPO Find X 超級閃充版/蘭博基尼版 全網通版", "OPPO Find X 超級閃充版/蘭博基尼版 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3883
        put(m, "PAFT10", "OPPO Find X 超級閃充版 移動版", "OPPO Find X 超級閃充版 移動版", "OPPO", "device_list_full_import"); // Device_List:L3884
        put(m, "PDEM10", "OPPO Find X2 全網通版", "OPPO Find X2 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3885
        put(m, "PDET10", "OPPO Find X2 移動版", "OPPO Find X2 移動版", "OPPO", "device_list_full_import"); // Device_List:L3886
        put(m, "PDEM30", "OPPO Find X2 Pro", "OPPO Find X2 Pro", "OPPO", "device_list_full_import"); // Device_List:L3887
        put(m, "PEDM00", "OPPO Find X3", "OPPO Find X3", "OPPO", "device_list_full_import"); // Device_List:L3888
        put(m, "PEEM00", "OPPO Find X3 Pro", "OPPO Find X3 Pro", "OPPO", "device_list_full_import"); // Device_List:L3889
        put(m, "PFFM10", "OPPO Find X5", "OPPO Find X5", "OPPO", "device_list_full_import"); // Device_List:L3890
        put(m, "PFEM10", "OPPO Find X5 Pro", "OPPO Find X5 Pro", "OPPO", "device_list_full_import"); // Device_List:L3891
        put(m, "PFFM20", "OPPO Find X5 Pro 天璣版", "OPPO Find X5 Pro 天璣版", "OPPO", "device_list_full_import"); // Device_List:L3892
        put(m, "PGFM10", "OPPO Find X6", "OPPO Find X6", "OPPO", "device_list_full_import"); // Device_List:L3893
        put(m, "PGEM10", "OPPO Find X6 Pro", "OPPO Find X6 Pro", "OPPO", "device_list_full_import"); // Device_List:L3894
        put(m, "PHZ110", "OPPO Find X7", "OPPO Find X7", "OPPO", "device_list_full_import"); // Device_List:L3895
        put(m, "PHY110", "OPPO Find X7 Ultra", "OPPO Find X7 Ultra", "OPPO", "device_list_full_import"); // Device_List:L3896
        put(m, "PHY120", "OPPO Find X7 Ultra 衛星通信版", "OPPO Find X7 Ultra 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3897
        put(m, "PKB110", "OPPO Find X8", "OPPO Find X8", "OPPO", "device_list_full_import"); // Device_List:L3898
        put(m, "PKC110", "OPPO Find X8 Pro", "OPPO Find X8 Pro", "OPPO", "device_list_full_import"); // Device_List:L3899
        put(m, "PKC130", "OPPO Find X8 Pro 衛星通信版", "OPPO Find X8 Pro 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3900
        put(m, "PKT110", "OPPO Find X8s", "OPPO Find X8s", "OPPO", "device_list_full_import"); // Device_List:L3901
        put(m, "PLB110", "OPPO Find X8s+", "OPPO Find X8s+", "OPPO", "device_list_full_import"); // Device_List:L3902
        put(m, "PKJ110", "OPPO Find X8 Ultra", "OPPO Find X8 Ultra", "OPPO", "device_list_full_import"); // Device_List:L3903
        put(m, "PKU110", "OPPO Find X8 Ultra 衛星通信版", "OPPO Find X8 Ultra 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3904
        put(m, "PLJ110", "OPPO Find X9", "OPPO Find X9", "OPPO", "device_list_full_import"); // Device_List:L3905
        put(m, "PLG110", "OPPO Find X9 Pro", "OPPO Find X9 Pro", "OPPO", "device_list_full_import"); // Device_List:L3906
        put(m, "PLG120", "OPPO Find X9 Pro 衛星通信版", "OPPO Find X9 Pro 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3907
        put(m, "PME110", "OPPO Find X9s Pro", "OPPO Find X9s Pro", "OPPO", "device_list_full_import"); // Device_List:L3908
        put(m, "PMA110", "OPPO Find X9 Ultra", "OPPO Find X9 Ultra", "OPPO", "device_list_full_import"); // Device_List:L3909
        put(m, "PMA120", "OPPO Find X9 Ultra 衛星通信版", "OPPO Find X9 Ultra 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3910
        put(m, "PEUM00", "OPPO Find N", "OPPO Find N", "OPPO", "device_list_full_import"); // Device_List:L3911
        put(m, "PGU110", "OPPO Find N2", "OPPO Find N2", "OPPO", "device_list_full_import"); // Device_List:L3912
        put(m, "PGT110", "OPPO Find N2 Flip", "OPPO Find N2 Flip", "OPPO", "device_list_full_import"); // Device_List:L3913
        put(m, "PHN110", "OPPO Find N3 / OPPO Find N3 典藏版", "OPPO Find N3 / OPPO Find N3 典藏版", "OPPO", "device_list_full_import"); // Device_List:L3914
        put(m, "PHT110", "OPPO Find N3 Flip", "OPPO Find N3 Flip", "OPPO", "device_list_full_import"); // Device_List:L3915
        put(m, "PKH110", "OPPO Find N5", "OPPO Find N5", "OPPO", "device_list_full_import"); // Device_List:L3916
        put(m, "PKH120", "OPPO Find N5 衛星通信版", "OPPO Find N5 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3917
        put(m, "PLP110", "OPPO Find N6", "OPPO Find N6", "OPPO", "device_list_full_import"); // Device_List:L3918
        put(m, "PLP120", "OPPO Find N6 衛星通信版", "OPPO Find N6 衛星通信版", "OPPO", "device_list_full_import"); // Device_List:L3919
        put(m, "PCAM00", "OPPO Reno 全網通版", "OPPO Reno 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3920
        put(m, "PCAT00", "OPPO Reno 移動版", "OPPO Reno 移動版", "OPPO", "device_list_full_import"); // Device_List:L3921
        put(m, "PCCM00", "OPPO Reno 10 倍變焦版 全網通版", "OPPO Reno 10 倍變焦版 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3922
        put(m, "PCCT00", "OPPO Reno 10 倍變焦版 移動版", "OPPO Reno 10 倍變焦版 移動版", "OPPO", "device_list_full_import"); // Device_List:L3923
        put(m, "PCDM10", "OPPO Reno Z 全網通版", "OPPO Reno Z 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3924
        put(m, "PCDT10", "OPPO Reno Z 移動版", "OPPO Reno Z 移動版", "OPPO", "device_list_full_import"); // Device_List:L3925
        put(m, "PCKM00", "OPPO Reno2 全網通版", "OPPO Reno2 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3926
        put(m, "PCKT00", "OPPO Reno2 移動版", "OPPO Reno2 移動版", "OPPO", "device_list_full_import"); // Device_List:L3927
        put(m, "PCKM80", "OPPO Reno2 Z 全網通版", "OPPO Reno2 Z 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3928
        put(m, "PCKT80", "OPPO Reno2 Z 移動版", "OPPO Reno2 Z 移動版", "OPPO", "device_list_full_import"); // Device_List:L3929
        put(m, "PDCM00", "OPPO Reno3 全網通版", "OPPO Reno3 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3930
        put(m, "PDCT00", "OPPO Reno3 移動版", "OPPO Reno3 移動版", "OPPO", "device_list_full_import"); // Device_List:L3931
        put(m, "PCRM00", "OPPO Reno3 Pro 全網通版", "OPPO Reno3 Pro 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3932
        put(m, "PCRT00", "OPPO Reno3 Pro 移動版", "OPPO Reno3 Pro 移動版", "OPPO", "device_list_full_import"); // Device_List:L3933
        put(m, "PCLM50", "OPPO Reno3 元氣版 全網通版", "OPPO Reno3 元氣版 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3934
        put(m, "PCRT01", "OPPO Reno3 元氣版 移動版", "OPPO Reno3 元氣版 移動版", "OPPO", "device_list_full_import"); // Device_List:L3935
        put(m, "PDPM00", "OPPO Reno4 全網通版", "OPPO Reno4 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3936
        put(m, "PDPT00", "OPPO Reno4 移動版", "OPPO Reno4 移動版", "OPPO", "device_list_full_import"); // Device_List:L3937
        put(m, "PDNM00", "OPPO Reno4 Pro 全網通版", "OPPO Reno4 Pro 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3938
        put(m, "PDNT00", "OPPO Reno4 Pro 移動版", "OPPO Reno4 Pro 移動版", "OPPO", "device_list_full_import"); // Device_List:L3939
        put(m, "PEAM00", "OPPO Reno4 SE 全網通版", "OPPO Reno4 SE 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3940
        put(m, "PEAT00", "OPPO Reno4 SE 移動版", "OPPO Reno4 SE 移動版", "OPPO", "device_list_full_import"); // Device_List:L3941
        put(m, "PEGM00", "OPPO Reno5 全網通版", "OPPO Reno5 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3942
        put(m, "PEGT00", "OPPO Reno5 移動版", "OPPO Reno5 移動版", "OPPO", "device_list_full_import"); // Device_List:L3943
        put(m, "PEGM10", "OPPO Reno5 K 全網通版", "OPPO Reno5 K 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3944
        put(m, "PEGT10", "OPPO Reno5 K 移動版", "OPPO Reno5 K 移動版", "OPPO", "device_list_full_import"); // Device_List:L3945
        put(m, "PDSM00", "OPPO Reno5 Pro 全網通版", "OPPO Reno5 Pro 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3946
        put(m, "PDST00", "OPPO Reno5 Pro 移動版", "OPPO Reno5 Pro 移動版", "OPPO", "device_list_full_import"); // Device_List:L3947
        put(m, "PDRM00", "OPPO Reno5 Pro+", "OPPO Reno5 Pro+", "OPPO", "device_list_full_import"); // Device_List:L3948
        put(m, "PEQM00", "OPPO Reno6", "OPPO Reno6", "OPPO", "device_list_full_import"); // Device_List:L3949
        put(m, "PEPM00", "OPPO Reno6 Pro", "OPPO Reno6 Pro", "OPPO", "device_list_full_import"); // Device_List:L3950
        put(m, "PENM00", "OPPO Reno6 Pro+", "OPPO Reno6 Pro+", "OPPO", "device_list_full_import"); // Device_List:L3951
        put(m, "PFJM10", "OPPO Reno7", "OPPO Reno7", "OPPO", "device_list_full_import"); // Device_List:L3952
        put(m, "PFDM00", "OPPO Reno7 Pro", "OPPO Reno7 Pro", "OPPO", "device_list_full_import"); // Device_List:L3953
        put(m, "PFCM00", "OPPO Reno7 SE", "OPPO Reno7 SE", "OPPO", "device_list_full_import"); // Device_List:L3954
        put(m, "PGBM10", "OPPO Reno8", "OPPO Reno8", "OPPO", "device_list_full_import"); // Device_List:L3955
        put(m, "PGAM10", "OPPO Reno8 Pro", "OPPO Reno8 Pro", "OPPO", "device_list_full_import"); // Device_List:L3956
        put(m, "PFZM10", "OPPO Reno8 Pro+", "OPPO Reno8 Pro+", "OPPO", "device_list_full_import"); // Device_List:L3957
        put(m, "PHM110", "OPPO Reno9", "OPPO Reno9", "OPPO", "device_list_full_import"); // Device_List:L3958
        put(m, "PGX110", "OPPO Reno9 Pro", "OPPO Reno9 Pro", "OPPO", "device_list_full_import"); // Device_List:L3959
        put(m, "PGW110", "OPPO Reno9 Pro+", "OPPO Reno9 Pro+", "OPPO", "device_list_full_import"); // Device_List:L3960
        put(m, "PHW110", "OPPO Reno10", "OPPO Reno10", "OPPO", "device_list_full_import"); // Device_List:L3961
        put(m, "PHV110", "OPPO Reno10 Pro", "OPPO Reno10 Pro", "OPPO", "device_list_full_import"); // Device_List:L3962
        put(m, "PHU110", "OPPO Reno10 Pro+", "OPPO Reno10 Pro+", "OPPO", "device_list_full_import"); // Device_List:L3963
        put(m, "PJH110", "OPPO Reno11", "OPPO Reno11", "OPPO", "device_list_full_import"); // Device_List:L3964
    }

    private static void fill22(Map<String, Entry> m) {
        put(m, "PJJ110", "OPPO Reno11 Pro", "OPPO Reno11 Pro", "OPPO", "device_list_full_import"); // Device_List:L3965
        put(m, "PJV110", "OPPO Reno12", "OPPO Reno12", "OPPO", "device_list_full_import"); // Device_List:L3966
        put(m, "PJW110", "OPPO Reno12 Pro", "OPPO Reno12 Pro", "OPPO", "device_list_full_import"); // Device_List:L3967
        put(m, "PKM110", "OPPO Reno13", "OPPO Reno13", "OPPO", "device_list_full_import"); // Device_List:L3968
        put(m, "PKK110", "OPPO Reno13 Pro", "OPPO Reno13 Pro", "OPPO", "device_list_full_import"); // Device_List:L3969
        put(m, "PLA110", "OPPO Reno14", "OPPO Reno14", "OPPO", "device_list_full_import"); // Device_List:L3970
        put(m, "PKZ110", "OPPO Reno14 Pro", "OPPO Reno14 Pro", "OPPO", "device_list_full_import"); // Device_List:L3971
        put(m, "PLW110", "OPPO Reno15", "OPPO Reno15", "OPPO", "device_list_full_import"); // Device_List:L3972
        put(m, "PLV110", "OPPO Reno15 Pro", "OPPO Reno15 Pro", "OPPO", "device_list_full_import"); // Device_List:L3973
        put(m, "PMD110", "OPPO Reno15c", "OPPO Reno15c", "OPPO", "device_list_full_import"); // Device_List:L3974
        put(m, "PMM110", "OPPO Reno16", "OPPO Reno16", "OPPO", "device_list_full_import"); // Device_List:L3975
        put(m, "PMK110", "OPPO Reno16 Pro", "OPPO Reno16 Pro", "OPPO", "device_list_full_import"); // Device_List:L3976
        put(m, "PCLM10", "OPPO Reno Ace", "OPPO Reno Ace", "OPPO", "device_list_full_import"); // Device_List:L3977
        put(m, "PDHM00", "OPPO Ace2", "OPPO Ace2", "OPPO", "device_list_full_import"); // Device_List:L3978
        put(m, "PACM00", "OPPO R15 全網通版", "OPPO R15 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3979
        put(m, "PACT00", "OPPO R15 移動版", "OPPO R15 移動版", "OPPO", "device_list_full_import"); // Device_List:L3980
        put(m, "PAAM00", "OPPO R15 夢鏡版 全網通版", "OPPO R15 夢鏡版 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3981
        put(m, "PAAT00", "OPPO R15 夢鏡版 移動版", "OPPO R15 夢鏡版 移動版", "OPPO", "device_list_full_import"); // Device_List:L3982
        put(m, "PBCM10", "OPPO R15x 全網通版", "OPPO R15x 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3983
        put(m, "PBCT10", "OPPO R15x 移動版", "OPPO R15x 移動版", "OPPO", "device_list_full_import"); // Device_List:L3984
        put(m, "PBEM00", "OPPO R17 全網通版", "OPPO R17 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3985
        put(m, "PBET00", "OPPO R17 移動版", "OPPO R17 移動版", "OPPO", "device_list_full_import"); // Device_List:L3986
        put(m, "PBDM00", "OPPO R17 Pro 全網通版", "OPPO R17 Pro 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3987
        put(m, "PBDT00", "OPPO R17 Pro 移動版", "OPPO R17 Pro 移動版", "OPPO", "device_list_full_import"); // Device_List:L3988
        put(m, "PADM00", "OPPO A3 全網通版", "OPPO A3 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3989
        put(m, "PADT00", "OPPO A3 移動版", "OPPO A3 移動版", "OPPO", "device_list_full_import"); // Device_List:L3990
        put(m, "PBBM30", "OPPO A5 全網通版", "OPPO A5 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3991
        put(m, "PBBT30", "OPPO A5 移動版", "OPPO A5 移動版", "OPPO", "device_list_full_import"); // Device_List:L3992
        put(m, "PBFM00", "OPPO A7 全網通版", "OPPO A7 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3993
        put(m, "PBFT00", "OPPO A7 移動版", "OPPO A7 移動版", "OPPO", "device_list_full_import"); // Device_List:L3994
        put(m, "PBBM00", "OPPO A7x 全網通版", "OPPO A7x 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3995
        put(m, "PBBT00", "OPPO A7x 移動版", "OPPO A7x 移動版", "OPPO", "device_list_full_import"); // Device_List:L3996
        put(m, "PCDM00", "OPPO A7n 全網通版", "OPPO A7n 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3997
        put(m, "PCDT00", "OPPO A7n 移動版", "OPPO A7n 移動版", "OPPO", "device_list_full_import"); // Device_List:L3998
        put(m, "PDBM00", "OPPO A8 全網通版", "OPPO A8 全網通版", "OPPO", "device_list_full_import"); // Device_List:L3999
        put(m, "PDBT00", "OPPO A8 移動版", "OPPO A8 移動版", "OPPO", "device_list_full_import"); // Device_List:L4000
        put(m, "PCAM10", "OPPO A9 全網通版", "OPPO A9 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4001
        put(m, "PCAT10", "OPPO A9 移動版", "OPPO A9 移動版", "OPPO", "device_list_full_import"); // Device_List:L4002
        put(m, "PCEM00", "OPPO A9x 全網通版", "OPPO A9x 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4003
        put(m, "PCET00", "OPPO A9x 移動版", "OPPO A9x 移動版", "OPPO", "device_list_full_import"); // Device_List:L4004
        put(m, "PCHM10", "OPPO A11 全網通版", "OPPO A11 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4005
        put(m, "PCHT10", "OPPO A11 移動版", "OPPO A11 移動版", "OPPO", "device_list_full_import"); // Device_List:L4006
        put(m, "PCHM30", "OPPO A11x 全網通版", "OPPO A11x 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4007
        put(m, "PCHT30", "OPPO A11x 移動版", "OPPO A11x 移動版", "OPPO", "device_list_full_import"); // Device_List:L4008
        put(m, "PCHM00", "OPPO A11n 全網通版", "OPPO A11n 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4009
        put(m, "PCHT00", "OPPO A11n 移動版", "OPPO A11n 移動版", "OPPO", "device_list_full_import"); // Device_List:L4010
        put(m, "PDVM00", "OPPO A11s", "OPPO A11s", "OPPO", "device_list_full_import"); // Device_List:L4011
        put(m, "PEFM00", "OPPO A35", "OPPO A35", "OPPO", "device_list_full_import"); // Device_List:L4012
        put(m, "PESM10", "OPPO A36", "OPPO A36", "OPPO", "device_list_full_import"); // Device_List:L4013
        put(m, "PDAM10", "OPPO A52 全網通版", "OPPO A52 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4014
        put(m, "PDAT10", "OPPO A52 移動版", "OPPO A52 移動版", "OPPO", "device_list_full_import"); // Device_List:L4015
        put(m, "PECM30", "OPPO A53 (2020) 全網通版", "OPPO A53 (2020) 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4016
        put(m, "PECT30", "OPPO A53 (2020) 移動版", "OPPO A53 (2020) 移動版", "OPPO", "device_list_full_import"); // Device_List:L4017
        put(m, "PEMM20", "OPPO A55 全網通版", "OPPO A55 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4018
        put(m, "PEMT20", "OPPO A55 移動版", "OPPO A55 移動版", "OPPO", "device_list_full_import"); // Device_List:L4019
        put(m, "PEMM00", "OPPO A55s", "OPPO A55s", "OPPO", "device_list_full_import"); // Device_List:L4020
        put(m, "PFVM10", "OPPO A56", "OPPO A56", "OPPO", "device_list_full_import"); // Device_List:L4021
        put(m, "PFTM20", "OPPO A56s", "OPPO A56s", "OPPO", "device_list_full_import"); // Device_List:L4022
        put(m, "PHJ110", "OPPO A58", "OPPO A58", "OPPO", "device_list_full_import"); // Device_List:L4023
        put(m, "PDYM20", "OPPO A72 全網通版", "OPPO A72 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4024
        put(m, "PDYT20", "OPPO A72 移動版", "OPPO A72 移動版", "OPPO", "device_list_full_import"); // Device_List:L4025
        put(m, "PDYM10", "OPPO A72n", "OPPO A72n", "OPPO", "device_list_full_import"); // Device_List:L4026
        put(m, "PCPM00", "OPPO A91 全網通版", "OPPO A91 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4027
        put(m, "PCPT00", "OPPO A91 移動版", "OPPO A91 移動版", "OPPO", "device_list_full_import"); // Device_List:L4028
        put(m, "PDKM00", "OPPO A92s 全網通版", "OPPO A92s 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4029
        put(m, "PDKT00", "OPPO A92s 移動版", "OPPO A92s 移動版", "OPPO", "device_list_full_import"); // Device_List:L4030
        put(m, "PEHM00", "OPPO A93 全網通版", "OPPO A93 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4031
        put(m, "PEHT00", "OPPO A93 移動版", "OPPO A93 移動版", "OPPO", "device_list_full_import"); // Device_List:L4032
        put(m, "PFGM00", "OPPO A93s", "OPPO A93s", "OPPO", "device_list_full_import"); // Device_List:L4033
        put(m, "PELM00", "OPPO A95", "OPPO A95", "OPPO", "device_list_full_import"); // Device_List:L4034
        put(m, "PFUM10", "OPPO A96", "OPPO A96", "OPPO", "device_list_full_import"); // Device_List:L4035
        put(m, "PHA120", "OPPO A96", "OPPO A96", "OPPO", "device_list_full_import"); // Device_List:L4036
        put(m, "PFTM10", "OPPO A97", "OPPO A97", "OPPO", "device_list_full_import"); // Device_List:L4037
        put(m, "PHS110", "OPPO A1 5G (2023)", "OPPO A1 5G (2023)", "OPPO", "device_list_full_import"); // Device_List:L4038
        put(m, "PHQ110", "OPPO A1 Pro", "OPPO A1 Pro", "OPPO", "device_list_full_import"); // Device_List:L4039
        put(m, "PJB110", "OPPO A1s / OPPO A2", "OPPO A1s / OPPO A2", "OPPO", "device_list_full_import"); // Device_List:L4040
        put(m, "PJU110", "OPPO A1i / OPPO A2m", "OPPO A1i / OPPO A2m", "OPPO", "device_list_full_import"); // Device_List:L4041
        put(m, "PJS110", "OPPO A2x", "OPPO A2x", "OPPO", "device_list_full_import"); // Device_List:L4042
        put(m, "PJG110", "OPPO A2 Pro", "OPPO A2 Pro", "OPPO", "device_list_full_import"); // Device_List:L4043
        put(m, "PKA110", "OPPO A3 5G (2024) / OPPO A3i Plus", "OPPO A3 5G (2024) / OPPO A3i Plus", "OPPO", "device_list_full_import"); // Device_List:L4044
        put(m, "PKD110", "OPPO A3 活力版", "OPPO A3 活力版", "OPPO", "device_list_full_import"); // Device_List:L4045
        put(m, "PKD120", "OPPO A3m", "OPPO A3m", "OPPO", "device_list_full_import"); // Device_List:L4046
        put(m, "PKD130", "OPPO A3x", "OPPO A3x", "OPPO", "device_list_full_import"); // Device_List:L4047
        put(m, "PKL110", "OPPO A3i", "OPPO A3i", "OPPO", "device_list_full_import"); // Device_List:L4048
        put(m, "PJY110", "OPPO A3 Pro / OPPO A5 Plus", "OPPO A3 Pro / OPPO A5 Plus", "OPPO", "device_list_full_import"); // Device_List:L4049
        put(m, "PKQ110", "OPPO A5 5G (2025) / OPPO A6 Plus", "OPPO A5 5G (2025) / OPPO A6 Plus", "OPPO", "device_list_full_import"); // Device_List:L4050
        put(m, "PKV110", "OPPO A5 活力版", "OPPO A5 活力版", "OPPO", "device_list_full_import"); // Device_List:L4051
        put(m, "PKW110", "OPPO A5x / OPPO A5m", "OPPO A5x / OPPO A5m", "OPPO", "device_list_full_import"); // Device_List:L4052
        put(m, "PKP110", "OPPO A5 Pro", "OPPO A5 Pro", "OPPO", "device_list_full_import"); // Device_List:L4053
        put(m, "PLS120", "OPPO A6", "OPPO A6", "OPPO", "device_list_full_import"); // Device_List:L4054
        put(m, "PLL110", "OPPO A6 GT / OPPO A6 Max / OPPO A6l", "OPPO A6 GT / OPPO A6 Max / OPPO A6l", "OPPO", "device_list_full_import"); // Device_List:L4055
        put(m, "PLN110", "OPPO A6 Pro", "OPPO A6 Pro", "OPPO", "device_list_full_import"); // Device_List:L4056
        put(m, "PKW120", "OPPO A6i", "OPPO A6i", "OPPO", "device_list_full_import"); // Device_List:L4057
        put(m, "PLT120", "OPPO A6s / OPPO A6i+ / OPPO A6k", "OPPO A6s / OPPO A6i+ / OPPO A6k", "OPPO", "device_list_full_import"); // Device_List:L4058
        put(m, "PMT110", "OPPO A6s Pro", "OPPO A6s Pro", "OPPO", "device_list_full_import"); // Device_List:L4059
        put(m, "PLT130", "OPPO A6v", "OPPO A6v", "OPPO", "device_list_full_import"); // Device_List:L4060
        put(m, "PLT140", "OPPO A6x / OPPO A6m", "OPPO A6x / OPPO A6m", "OPPO", "device_list_full_import"); // Device_List:L4061
        put(m, "PMC110", "OPPO A6c", "OPPO A6c", "OPPO", "device_list_full_import"); // Device_List:L4062
        put(m, "PBCM30", "OPPO K1", "OPPO K1", "OPPO", "device_list_full_import"); // Device_List:L4063
        put(m, "PCGM00", "OPPO K3 全網通版", "OPPO K3 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4064
        put(m, "PCGT00", "OPPO K3 移動版", "OPPO K3 移動版", "OPPO", "device_list_full_import"); // Device_List:L4065
        put(m, "PCNM00", "OPPO K5 全網通版", "OPPO K5 全網通版", "OPPO", "device_list_full_import"); // Device_List:L4066
        put(m, "PCNT00", "OPPO K5 移動版", "OPPO K5 移動版", "OPPO", "device_list_full_import"); // Device_List:L4067
        put(m, "PERM00", "OPPO K7x", "OPPO K7x", "OPPO", "device_list_full_import"); // Device_List:L4068
        put(m, "PEXM00", "OPPO K9", "OPPO K9", "OPPO", "device_list_full_import"); // Device_List:L4069
        put(m, "PERM10", "OPPO K9s / OPPO K10 活力版", "OPPO K9s / OPPO K10 活力版", "OPPO", "device_list_full_import"); // Device_List:L4070
        put(m, "PEYM00", "OPPO K9 Pro", "OPPO K9 Pro", "OPPO", "device_list_full_import"); // Device_List:L4071
        put(m, "PGCM10", "OPPO K9x", "OPPO K9x", "OPPO", "device_list_full_import"); // Device_List:L4072
        put(m, "PGJM10", "OPPO K10", "OPPO K10", "OPPO", "device_list_full_import"); // Device_List:L4073
        put(m, "PGIM10", "OPPO K10 Pro", "OPPO K10 Pro", "OPPO", "device_list_full_import"); // Device_List:L4074
        put(m, "PGGM10", "OPPO K10x", "OPPO K10x", "OPPO", "device_list_full_import"); // Device_List:L4075
        put(m, "PJC110", "OPPO K11", "OPPO K11", "OPPO", "device_list_full_import"); // Device_List:L4076
        put(m, "PHF110", "OPPO K11x", "OPPO K11x", "OPPO", "device_list_full_import"); // Device_List:L4077
        put(m, "PJR110", "OPPO K12", "OPPO K12", "OPPO", "device_list_full_import"); // Device_List:L4078
        put(m, "PKS110", "OPPO K12 Plus", "OPPO K12 Plus", "OPPO", "device_list_full_import"); // Device_List:L4079
        put(m, "PJT110", "OPPO K12x", "OPPO K12x", "OPPO", "device_list_full_import"); // Device_List:L4080
        put(m, "PLD110", "OPPO K12s", "OPPO K12s", "OPPO", "device_list_full_import"); // Device_List:L4081
        put(m, "PLM110", "OPPO K13 Turbo", "OPPO K13 Turbo", "OPPO", "device_list_full_import"); // Device_List:L4082
        put(m, "PLE110", "OPPO K13 Turbo Pro", "OPPO K13 Turbo Pro", "OPPO", "device_list_full_import"); // Device_List:L4083
        put(m, "PMH110", "OPPO K15 Pro", "OPPO K15 Pro", "OPPO", "device_list_full_import"); // Device_List:L4084
        put(m, "PMG110", "OPPO K15 Pro+", "OPPO K15 Pro+", "OPPO", "device_list_full_import"); // Device_List:L4085
        put(m, "OPD2101", "OPPO Pad", "OPPO Pad", "OPPO", "device_list_full_import"); // Device_List:L4086
        put(m, "OPD2102", "OPPO Pad Air", "OPPO Pad Air", "OPPO", "device_list_full_import"); // Device_List:L4087
        put(m, "OPD2201", "OPPO Pad 2", "OPPO Pad 2", "OPPO", "device_list_full_import"); // Device_List:L4088
        put(m, "OPD2301", "OPPO Pad Air2", "OPPO Pad Air2", "OPPO", "device_list_full_import"); // Device_List:L4089
        put(m, "OPD2405", "OPPO Pad 3", "OPPO Pad 3", "OPPO", "device_list_full_import"); // Device_List:L4090
        put(m, "OPD2401", "OPPO Pad 3 Pro", "OPPO Pad 3 Pro", "OPPO", "device_list_full_import"); // Device_List:L4091
        put(m, "OPD2409", "OPPO Pad 4 Pro", "OPPO Pad 4 Pro", "OPPO", "device_list_full_import"); // Device_List:L4092
        put(m, "OPD2417", "OPPO Pad SE", "OPPO Pad SE", "OPPO", "device_list_full_import"); // Device_List:L4093
        put(m, "OPD2506", "OPPO Pad 5", "OPPO Pad 5", "OPPO", "device_list_full_import"); // Device_List:L4094
        put(m, "OPD2501", "OPPO Pad Air5", "OPPO Pad Air5", "OPPO", "device_list_full_import"); // Device_List:L4095
        put(m, "OPD2511", "OPPO Pad 5 Pro", "OPPO Pad 5 Pro", "OPPO", "device_list_full_import"); // Device_List:L4096
        put(m, "OPD2515", "OPPO Pad Mini", "OPPO Pad Mini", "OPPO", "device_list_full_import"); // Device_List:L4097
        put(m, "OPD2601", "OPPO Pad 6", "OPPO Pad 6", "OPPO", "device_list_full_import"); // Device_List:L4098
        put(m, "OB19O1", "OPPO Band 運動版", "OPPO Band 運動版", "OPPO", "device_list_full_import"); // Device_List:L4099
        put(m, "OB19O3", "OPPO Band 運動版 (國際版)", "OPPO Band 運動版 (國際版)", "OPPO", "device_list_full_import"); // Device_List:L4100
        put(m, "OB19O7", "OPPO Band 活力版", "OPPO Band 活力版", "OPPO", "device_list_full_import"); // Device_List:L4101
        put(m, "OB19O0", "OPPO Band 時尚版 (NFC 版)", "OPPO Band 時尚版 (NFC 版)", "OPPO", "device_list_full_import"); // Device_List:L4102
        put(m, "OB19O2", "OPPO Band EVA 限定版", "OPPO Band EVA 限定版", "OPPO", "device_list_full_import"); // Device_List:L4103
        put(m, "OB19O8", "OPPO Band 名偵探柯南限定版", "OPPO Band 名偵探柯南限定版", "OPPO", "device_list_full_import"); // Device_List:L4104
        put(m, "OBB211", "OPPO Band 2 標準版", "OPPO Band 2 標準版", "OPPO", "device_list_full_import"); // Device_List:L4105
        put(m, "OBB213", "OPPO Band 2 NFC 版", "OPPO Band 2 NFC 版", "OPPO", "device_list_full_import"); // Device_List:L4106
        put(m, "OR19R1", "OPPO Watch RX / 英雄聯盟限定版", "OPPO Watch RX / 英雄聯盟限定版", "OPPO", "device_list_full_import"); // Device_List:L4107
        put(m, "OWW206", "OPPO Watch Free 標準版", "OPPO Watch Free 標準版", "OPPO", "device_list_full_import"); // Device_List:L4108
        put(m, "OWW208", "OPPO Watch Free NFC 版", "OPPO Watch Free NFC 版", "OPPO", "device_list_full_import"); // Device_List:L4109
        put(m, "OW19W1", "OPPO Watch 46mm / EVA 限定版 / 故宮新禧版", "OPPO Watch 46mm / EVA 限定版 / 故宮新禧版", "OPPO", "device_list_full_import"); // Device_List:L4110
        put(m, "OW19W2", "OPPO Watch 41mm", "OPPO Watch 41mm", "OPPO", "device_list_full_import"); // Device_List:L4111
        put(m, "OW19W3", "OPPO Watch ECG / 精鋼版", "OPPO Watch ECG / 精鋼版", "OPPO", "device_list_full_import"); // Device_List:L4112
        put(m, "OWW202", "OPPO Watch 2 42mm 藍牙版", "OPPO Watch 2 42mm 藍牙版", "OPPO", "device_list_full_import"); // Device_List:L4113
        put(m, "OW20W1", "OPPO Watch 2 46mm eSIM 版 / 李寧限定版", "OPPO Watch 2 46mm eSIM 版 / 李寧限定版", "OPPO", "device_list_full_import"); // Device_List:L4114
        put(m, "OW20W2", "OPPO Watch 2 42mm eSIM 版 / 名偵探柯南限定版", "OPPO Watch 2 42mm eSIM 版 / 名偵探柯南限定版", "OPPO", "device_list_full_import"); // Device_List:L4115
        put(m, "OW20W3", "OPPO Watch 2 46mm ECG", "OPPO Watch 2 46mm ECG", "OPPO", "device_list_full_import"); // Device_List:L4116
        put(m, "OWW213", "OPPO Watch SE", "OPPO Watch SE", "OPPO", "device_list_full_import"); // Device_List:L4117
        put(m, "OWW212", "OPPO Watch 3", "OPPO Watch 3", "OPPO", "device_list_full_import"); // Device_List:L4118
        put(m, "OWW211", "OPPO Watch 3 Pro", "OPPO Watch 3 Pro", "OPPO", "device_list_full_import"); // Device_List:L4119
        put(m, "OWW221", "OPPO Watch 4 Pro", "OPPO Watch 4 Pro", "OPPO", "device_list_full_import"); // Device_List:L4120
        put(m, "OWW231", "OPPO Watch X", "OPPO Watch X", "OPPO", "device_list_full_import"); // Device_List:L4121
        put(m, "OWW235", "OPPO Watch Sport", "OPPO Watch Sport", "OPPO", "device_list_full_import"); // Device_List:L4122
        put(m, "OWW242", "OPPO Watch X2 Mini", "OPPO Watch X2 Mini", "OPPO", "device_list_full_import"); // Device_List:L4123
        put(m, "OWW251", "OPPO Watch X2", "OPPO Watch X2", "OPPO", "device_list_full_import"); // Device_List:L4124
        put(m, "OWW262", "OPPO Watch S", "OPPO Watch S", "OPPO", "device_list_full_import"); // Device_List:L4125
        put(m, "OWW261", "OPPO Watch X3", "OPPO Watch X3", "OPPO", "device_list_full_import"); // Device_List:L4126
        put(m, "OWW263", "OPPO Watch X3 Mini", "OPPO Watch X3 Mini", "OPPO", "device_list_full_import"); // Device_List:L4127
        put(m, "CPH1875", "OPPO Find X", "OPPO Find X", "OnePlus", "device_list_full_import"); // Device_List:L4128
        put(m, "CPH2023", "OPPO Find X2", "OPPO Find X2", "OnePlus", "device_list_full_import"); // Device_List:L4129
        put(m, "CPH2025", "OPPO Find X2 Pro", "OPPO Find X2 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4130
        put(m, "OPG01", "OPPO Find X2 Pro (KDDI)", "OPPO Find X2 Pro (KDDI)", "OPPO", "device_list_full_import"); // Device_List:L4131
        put(m, "CPH2005", "OPPO Find X2 Lite", "OPPO Find X2 Lite", "OnePlus", "device_list_full_import"); // Device_List:L4132
        put(m, "CPH2009", "OPPO Find X2 Neo", "OPPO Find X2 Neo", "OnePlus", "device_list_full_import"); // Device_List:L4133
        put(m, "CPH2173", "OPPO Find X3 Pro", "OPPO Find X3 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4134
        put(m, "OPG03", "OPPO Find X3 Pro (KDDI)", "OPPO Find X3 Pro (KDDI)", "OPPO", "device_list_full_import"); // Device_List:L4135
        put(m, "CPH2145", "OPPO Find X3 Lite", "OPPO Find X3 Lite", "OnePlus", "device_list_full_import"); // Device_List:L4136
        put(m, "CPH2207", "OPPO Find X3 Neo", "OPPO Find X3 Neo", "OnePlus", "device_list_full_import"); // Device_List:L4137
        put(m, "CPH2307", "OPPO Find X5", "OPPO Find X5", "OnePlus", "device_list_full_import"); // Device_List:L4138
        put(m, "CPH2305", "OPPO Find X5 Pro", "OPPO Find X5 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4139
        put(m, "CPH2371", "OPPO Find X5 Lite", "OPPO Find X5 Lite", "OnePlus", "device_list_full_import"); // Device_List:L4140
        put(m, "CPH2651", "OPPO Find X8", "OPPO Find X8", "OnePlus", "device_list_full_import"); // Device_List:L4141
        put(m, "CPH2659", "OPPO Find X8 Pro", "OPPO Find X8 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4142
        put(m, "CPH2797", "OPPO Find X9", "OPPO Find X9", "OnePlus", "device_list_full_import"); // Device_List:L4143
        put(m, "OPG07", "OPPO Find X9 (KDDI)", "OPPO Find X9 (KDDI)", "OPPO", "device_list_full_import"); // Device_List:L4144
    }

    private static void fill23(Map<String, Entry> m) {
        put(m, "CPH2791", "OPPO Find X9 Pro", "OPPO Find X9 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4145
        put(m, "CPH2873", "OPPO Find X9s", "OPPO Find X9s", "OnePlus", "device_list_full_import"); // Device_List:L4146
        put(m, "CPH2841", "OPPO Find X9 Ultra", "OPPO Find X9 Ultra", "OnePlus", "device_list_full_import"); // Device_List:L4147
        put(m, "CPH2439", "OPPO Find N2", "OPPO Find N2", "OnePlus", "device_list_full_import"); // Device_List:L4148
        put(m, "CPH2437", "OPPO Find N2 Flip", "OPPO Find N2 Flip", "OnePlus", "device_list_full_import"); // Device_List:L4149
        put(m, "CPH2499", "OPPO Find N3", "OPPO Find N3", "OnePlus", "device_list_full_import"); // Device_List:L4150
        put(m, "CPH2519", "OPPO Find N3 Flip", "OPPO Find N3 Flip", "OnePlus", "device_list_full_import"); // Device_List:L4151
        put(m, "CPH2671", "OPPO Find N5", "OPPO Find N5", "OnePlus", "device_list_full_import"); // Device_List:L4152
        put(m, "CPH2765", "OPPO Find N6", "OPPO Find N6", "OnePlus", "device_list_full_import"); // Device_List:L4153
        put(m, "CPH1917", "OPPO Reno", "OPPO Reno", "OnePlus", "device_list_full_import"); // Device_List:L4154
        put(m, "CPH1921", "OPPO Reno 5G", "OPPO Reno 5G", "OnePlus", "device_list_full_import"); // Device_List:L4155
        put(m, "CPH1919", "OPPO Reno 10x Zoom", "OPPO Reno 10x Zoom", "OnePlus", "device_list_full_import"); // Device_List:L4156
        put(m, "CPH1983", "OPPO Reno A", "OPPO Reno A", "OnePlus", "device_list_full_import"); // Device_List:L4157
        put(m, "CPH1979", "OPPO Reno Z", "OPPO Reno Z", "OnePlus", "device_list_full_import"); // Device_List:L4158
        put(m, "CPH1907", "OPPO Reno2", "OPPO Reno2", "OnePlus", "device_list_full_import"); // Device_List:L4159
        put(m, "CPH1951RU", "OPPO Reno2 Z", "OPPO Reno2 Z", "OnePlus", "device_list_full_import"); // Device_List:L4160
        put(m, "CPH1989", "OPPO Reno2 F", "OPPO Reno2 F", "OnePlus", "device_list_full_import"); // Device_List:L4161
        put(m, "CPH2043", "OPPO Reno3", "OPPO Reno3", "OnePlus", "device_list_full_import"); // Device_List:L4162
        put(m, "A001OP", "OPPO Reno3 (SoftBank)", "OPPO Reno3 (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4163
        put(m, "CPH2037", "OPPO Reno3 Pro Global", "OPPO Reno3 Pro Global", "OnePlus", "device_list_full_import"); // Device_List:L4164
        put(m, "CPH2013", "OPPO Reno3 A", "OPPO Reno3 A", "OnePlus", "device_list_full_import"); // Device_List:L4165
        put(m, "A002OP", "OPPO Reno3 A (SoftBank)", "OPPO Reno3 A (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4166
        put(m, "CPH2113", "OPPO Reno4", "OPPO Reno4", "OnePlus", "device_list_full_import"); // Device_List:L4167
        put(m, "CPH2109", "OPPO Reno4 Pro", "OPPO Reno4 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4168
        put(m, "CPH2125", "OPPO Reno4 Lite", "OPPO Reno4 Lite", "OnePlus", "device_list_full_import"); // Device_List:L4169
        put(m, "CPH2209", "OPPO Reno4 F", "OPPO Reno4 F", "OnePlus", "device_list_full_import"); // Device_List:L4170
        put(m, "CPH2065", "OPPO Reno4 Z", "OPPO Reno4 Z", "OnePlus", "device_list_full_import"); // Device_List:L4171
        put(m, "CPH2159", "OPPO Reno5", "OPPO Reno5", "OnePlus", "device_list_full_import"); // Device_List:L4172
        put(m, "CPH2201", "OPPO Reno5 Pro", "OPPO Reno5 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4173
        put(m, "CPH2205", "OPPO Reno5 Lite", "OPPO Reno5 Lite", "OnePlus", "device_list_full_import"); // Device_List:L4174
        put(m, "CPH2199", "OPPO Reno5 A", "OPPO Reno5 A", "OnePlus", "device_list_full_import"); // Device_List:L4175
        put(m, "A101OP", "OPPO Reno5 A (SoftBank)", "OPPO Reno5 A (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4176
        put(m, "CPH2217", "OPPO Reno5 F", "OPPO Reno5 F", "OnePlus", "device_list_full_import"); // Device_List:L4177
        put(m, "CPH2213", "OPPO Reno5 Z", "OPPO Reno5 Z", "OnePlus", "device_list_full_import"); // Device_List:L4178
        put(m, "CPH2235", "OPPO Reno6", "OPPO Reno6", "OnePlus", "device_list_full_import"); // Device_List:L4179
        put(m, "CPH2251", "OPPO Reno6 5G", "OPPO Reno6 5G", "OnePlus", "device_list_full_import"); // Device_List:L4180
        put(m, "CPH2249", "OPPO Reno6 Pro 5G", "OPPO Reno6 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4181
        put(m, "CPH2237", "OPPO Reno6 Z", "OPPO Reno6 Z", "OnePlus", "device_list_full_import"); // Device_List:L4182
        put(m, "CPH2365", "OPPO Reno6 Lite", "OPPO Reno6 Lite", "OnePlus", "device_list_full_import"); // Device_List:L4183
        put(m, "CPH2363", "OPPO Reno7", "OPPO Reno7", "OnePlus", "device_list_full_import"); // Device_List:L4184
        put(m, "CPH2293", "OPPO Reno7 Pro 5G", "OPPO Reno7 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4185
        put(m, "CPH2353", "OPPO Reno7 A", "OPPO Reno7 A", "OnePlus", "device_list_full_import"); // Device_List:L4186
        put(m, "A201OP", "OPPO Reno7 A (SoftBank)", "OPPO Reno7 A (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4187
        put(m, "OPG04", "OPPO Reno7 A (KDDI)", "OPPO Reno7 A (KDDI)", "OPPO", "device_list_full_import"); // Device_List:L4188
        put(m, "CPH2343", "OPPO Reno7 Z 5G / OPPO Reno7 Lite 5G / OPPO Reno8 Lite 5G", "OPPO Reno7 Z 5G / OPPO Reno7 Lite 5G / OPPO Reno8 Lite 5G", "OnePlus", "device_list_full_import"); // Device_List:L4189
        put(m, "CPH2461", "OPPO Reno8", "OPPO Reno8", "OnePlus", "device_list_full_import"); // Device_List:L4190
        put(m, "CPH2359", "OPPO Reno8 5G", "OPPO Reno8 5G", "OnePlus", "device_list_full_import"); // Device_List:L4191
        put(m, "CPH2357", "OPPO Reno8 Pro 5G", "OPPO Reno8 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4192
        put(m, "CPH2457", "OPPO Reno8 Z 5G", "OPPO Reno8 Z 5G", "OnePlus", "device_list_full_import"); // Device_List:L4193
        put(m, "CPH2481", "OPPO Reno8 T", "OPPO Reno8 T", "OnePlus", "device_list_full_import"); // Device_List:L4194
        put(m, "CPH2505", "OPPO Reno8 T 5G", "OPPO Reno8 T 5G", "OnePlus", "device_list_full_import"); // Device_List:L4195
        put(m, "CPH2523", "OPPO Reno9 A", "OPPO Reno9 A", "OnePlus", "device_list_full_import"); // Device_List:L4196
        put(m, "A301OP", "OPPO Reno9 A (SoftBank)", "OPPO Reno9 A (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4197
        put(m, "CPH2531", "OPPO Reno10 5G", "OPPO Reno10 5G", "OnePlus", "device_list_full_import"); // Device_List:L4198
        put(m, "CPH2525", "OPPO Reno10 Pro 5G", "OPPO Reno10 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4199
        put(m, "CPH2541", "OPPO Reno10 Pro 5G (Japan)", "OPPO Reno10 Pro 5G (Japan)", "OnePlus", "device_list_full_import"); // Device_List:L4200
        put(m, "CPH2521", "OPPO Reno10 Pro+ 5G", "OPPO Reno10 Pro+ 5G", "OnePlus", "device_list_full_import"); // Device_List:L4201
        put(m, "CPH2599", "OPPO Reno11 5G", "OPPO Reno11 5G", "OnePlus", "device_list_full_import"); // Device_List:L4202
        put(m, "CPH2607", "OPPO Reno11 Pro 5G", "OPPO Reno11 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4203
        put(m, "CPH2603", "OPPO Reno11 F 5G / OPPO Reno11 A", "OPPO Reno11 F 5G / OPPO Reno11 A", "OnePlus", "device_list_full_import"); // Device_List:L4204
        put(m, "CPH2625", "OPPO Reno12 5G", "OPPO Reno12 5G", "OnePlus", "device_list_full_import"); // Device_List:L4205
        put(m, "CPH2629", "OPPO Reno12 Pro 5G", "OPPO Reno12 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4206
        put(m, "CPH2637", "OPPO Reno12 F 5G / OPPO Reno12 FS 5G", "OPPO Reno12 F 5G / OPPO Reno12 FS 5G", "OnePlus", "device_list_full_import"); // Device_List:L4207
        put(m, "CPH2689", "OPPO Reno13 5G", "OPPO Reno13 5G", "OnePlus", "device_list_full_import"); // Device_List:L4208
        put(m, "CPH2697", "OPPO Reno13 Pro 5G", "OPPO Reno13 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4209
        put(m, "CPH2701", "OPPO Reno13 F", "OPPO Reno13 F", "OnePlus", "device_list_full_import"); // Device_List:L4210
        put(m, "CPH2699", "OPPO Reno13 F 5G / OPPO Reno13 FS 5G / OPPO Reno13 A", "OPPO Reno13 F 5G / OPPO Reno13 FS 5G / OPPO Reno13 A", "OnePlus", "device_list_full_import"); // Device_List:L4211
        put(m, "CPH2737", "OPPO Reno14 5G", "OPPO Reno14 5G", "OnePlus", "device_list_full_import"); // Device_List:L4212
        put(m, "CPH2739", "OPPO Reno14 Pro 5G", "OPPO Reno14 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4213
        put(m, "CPH2743", "OPPO Reno14 F 5G / OPPO Reno14 FS 5G", "OPPO Reno14 F 5G / OPPO Reno14 FS 5G", "OnePlus", "device_list_full_import"); // Device_List:L4214
        put(m, "CPH2825", "OPPO Reno15 5G", "OPPO Reno15 5G", "OnePlus", "device_list_full_import"); // Device_List:L4215
        put(m, "CPH2813", "OPPO Reno15 Pro 5G / OPPO Reno15 Pro Mini 5G", "OPPO Reno15 Pro 5G / OPPO Reno15 Pro Mini 5G", "OnePlus", "device_list_full_import"); // Device_List:L4216
        put(m, "CPH2811", "OPPO Reno15 Pro 5G / OPPO Reno15 Pro Max 5G", "OPPO Reno15 Pro 5G / OPPO Reno15 Pro Max 5G", "OnePlus", "device_list_full_import"); // Device_List:L4217
        put(m, "CPH2801", "OPPO Reno15 F 5G / OPPO Reno15 FS 5G / OPPO Reno15c 5G / OPPO Reno15 A", "OPPO Reno15 F 5G / OPPO Reno15 FS 5G / OPPO Reno15c 5G / OPPO Reno15 A", "OnePlus", "device_list_full_import"); // Device_List:L4218
        put(m, "CPH2865", "OPPO Reno16 5G", "OPPO Reno16 5G", "OnePlus", "device_list_full_import"); // Device_List:L4219
        put(m, "CPH2859", "OPPO Reno16 F 5G / OPPO Reno16 FS 5G / OPPO Reno16c 5G", "OPPO Reno16 F 5G / OPPO Reno16 FS 5G / OPPO Reno16c 5G", "OnePlus", "device_list_full_import"); // Device_List:L4220
        put(m, "CPH1821", "OPPO F7", "OPPO F7", "OnePlus", "device_list_full_import"); // Device_List:L4221
        put(m, "CPH1859", "OPPO F7 Youth", "OPPO F7 Youth", "OnePlus", "device_list_full_import"); // Device_List:L4222
        put(m, "CPH1881", "OPPO F9", "OPPO F9", "OnePlus", "device_list_full_import"); // Device_List:L4223
        put(m, "CPH1911", "OPPO F11", "OPPO F11", "OnePlus", "device_list_full_import"); // Device_List:L4224
        put(m, "CPH1987", "OPPO F11 Pro", "OPPO F11 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4225
        put(m, "CPH2001", "OPPO F15", "OPPO F15", "OnePlus", "device_list_full_import"); // Device_List:L4226
        put(m, "CPH2095", "OPPO F17", "OPPO F17", "OnePlus", "device_list_full_import"); // Device_List:L4227
        put(m, "CPH2119", "OPPO F17 Pro", "OPPO F17 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4228
        put(m, "CPH2219", "OPPO F19", "OPPO F19", "OnePlus", "device_list_full_import"); // Device_List:L4229
        put(m, "CPH2285", "OPPO F19 Pro", "OPPO F19 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4230
        put(m, "CPH2223", "OPPO F19s", "OPPO F19s", "OnePlus", "device_list_full_import"); // Device_List:L4231
        put(m, "CPH2455", "OPPO F21s Pro 5G", "OPPO F21s Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4232
        put(m, "CPH2527", "OPPO F23 5G", "OPPO F23 5G", "OnePlus", "device_list_full_import"); // Device_List:L4233
        put(m, "CPH2643", "OPPO F27 Pro+ 5G", "OPPO F27 Pro+ 5G", "OnePlus", "device_list_full_import"); // Device_List:L4234
        put(m, "CPH2721", "OPPO F29 5G", "OPPO F29 5G", "OnePlus", "device_list_full_import"); // Device_List:L4235
        put(m, "CPH2705", "OPPO F29 Pro 5G", "OPPO F29 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4236
        put(m, "CPH2781", "OPPO F31 5G", "OPPO F31 5G", "OnePlus", "device_list_full_import"); // Device_List:L4237
        put(m, "CPH2763", "OPPO F31 Pro 5G", "OPPO F31 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4238
        put(m, "CPH2757", "OPPO F31 Pro+ 5G", "OPPO F31 Pro+ 5G", "OnePlus", "device_list_full_import"); // Device_List:L4239
        put(m, "CPH2777", "OPPO F33 5G", "OPPO F33 5G", "OnePlus", "device_list_full_import"); // Device_List:L4240
        put(m, "CPH2835", "OPPO F33 Pro 5G", "OPPO F33 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4241
        put(m, "CPH1835", "OPPO R15", "OPPO R15", "OnePlus", "device_list_full_import"); // Device_List:L4242
        put(m, "CPH1833", "OPPO R15 Pro", "OPPO R15 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4243
        put(m, "CPH1879", "OPPO R17", "OPPO R17", "OnePlus", "device_list_full_import"); // Device_List:L4244
        put(m, "CPH1877", "OPPO R17 Pro", "OPPO R17 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4245
        put(m, "CPH1893RU", "OPPO R17 Neo", "OPPO R17 Neo", "OnePlus", "device_list_full_import"); // Device_List:L4246
        put(m, "CPH1923RU", "OPPO A1k", "OPPO A1k", "OnePlus", "device_list_full_import"); // Device_List:L4247
        put(m, "CPH1837", "OPPO A3", "OPPO A3", "OnePlus", "device_list_full_import"); // Device_List:L4248
        put(m, "CPH2669", "OPPO A3 (2024)", "OPPO A3 (2024)", "OnePlus", "device_list_full_import"); // Device_List:L4249
        put(m, "CPH2683", "OPPO A3 5G", "OPPO A3 5G", "OnePlus", "device_list_full_import"); // Device_List:L4250
        put(m, "A402OP", "OPPO A3 5G (SoftBank)", "OPPO A3 5G (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4251
        put(m, "CPH1805", "OPPO A3s", "OPPO A3s", "OnePlus", "device_list_full_import"); // Device_List:L4252
        put(m, "CPH2641", "OPPO A3x", "OPPO A3x", "OnePlus", "device_list_full_import"); // Device_List:L4253
        put(m, "CPH2681", "OPPO A3x 5G", "OPPO A3x 5G", "OnePlus", "device_list_full_import"); // Device_List:L4254
        put(m, "CPH2665", "OPPO A3 Pro 5G", "OPPO A3 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4255
        put(m, "CPH1809", "OPPO A5", "OPPO A5", "OnePlus", "device_list_full_import"); // Device_List:L4256
        put(m, "CPH1912", "OPPO A5s", "OPPO A5s", "OnePlus", "device_list_full_import"); // Device_List:L4257
        put(m, "CPH1851", "OPPO AX5", "OPPO AX5", "OnePlus", "device_list_full_import"); // Device_List:L4258
        put(m, "CPH1920", "OPPO AX5s", "OPPO AX5s", "OnePlus", "device_list_full_import"); // Device_List:L4259
        put(m, "CPH1943", "OPPO A5 2020", "OPPO A5 2020", "OnePlus", "device_list_full_import"); // Device_List:L4260
        put(m, "CPH2751", "OPPO A5 5G", "OPPO A5 5G", "OnePlus", "device_list_full_import"); // Device_List:L4261
        put(m, "A502OP", "OPPO A5 5G (SoftBank)", "OPPO A5 5G (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4262
        put(m, "CPH2727", "OPPO A5 (2025) / OPPO A5m", "OPPO A5 (2025) / OPPO A5m", "OnePlus", "device_list_full_import"); // Device_List:L4263
        put(m, "CPH2711", "OPPO A5 Pro", "OPPO A5 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4264
        put(m, "CPH2695", "OPPO A5 Pro 5G", "OPPO A5 Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4265
        put(m, "CPH2773", "OPPO A5i", "OPPO A5i", "OnePlus", "device_list_full_import"); // Device_List:L4266
        put(m, "CPH2755", "OPPO A5i Pro", "OPPO A5i Pro", "OnePlus", "device_list_full_import"); // Device_List:L4267
        put(m, "CPH2821", "OPPO A5i Pro 5G", "OPPO A5i Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4268
        put(m, "CPH2725", "OPPO A5x", "OPPO A5x", "OnePlus", "device_list_full_import"); // Device_List:L4269
        put(m, "CPH2733", "OPPO A5x 5G", "OPPO A5x 5G", "OnePlus", "device_list_full_import"); // Device_List:L4270
        put(m, "CPH2817", "OPPO A6", "OPPO A6", "OnePlus", "device_list_full_import"); // Device_List:L4271
        put(m, "CPH2831", "OPPO A6 5G Global", "OPPO A6 5G Global", "OnePlus", "device_list_full_import"); // Device_List:L4272
        put(m, "CPH2785", "OPPO A6 5G India", "OPPO A6 5G India", "OnePlus", "device_list_full_import"); // Device_List:L4273
        put(m, "CPH2799", "OPPO A6 Pro", "OPPO A6 Pro", "OnePlus", "device_list_full_import"); // Device_List:L4274
        put(m, "CPH2827", "OPPO A6 Pro 5G India", "OPPO A6 Pro 5G India", "OnePlus", "device_list_full_import"); // Device_List:L4275
        put(m, "CPH2815", "OPPO A6s", "OPPO A6s", "OnePlus", "device_list_full_import"); // Device_List:L4276
        put(m, "CPH2789", "OPPO A6s 5G Global", "OPPO A6s 5G Global", "OnePlus", "device_list_full_import"); // Device_List:L4277
        put(m, "CPH2889", "OPPO A6s 5G India", "OPPO A6s 5G India", "OnePlus", "device_list_full_import"); // Device_List:L4278
        put(m, "CPH2819", "OPPO A6x", "OPPO A6x", "OnePlus", "device_list_full_import"); // Device_List:L4279
        put(m, "CPH2783", "OPPO A6x 5G Global", "OPPO A6x 5G Global", "OnePlus", "device_list_full_import"); // Device_List:L4280
        put(m, "CPH2823", "OPPO A6x 5G India", "OPPO A6x 5G India", "OnePlus", "device_list_full_import"); // Device_List:L4281
        put(m, "CPH2847", "OPPO A6t", "OPPO A6t", "OnePlus", "device_list_full_import"); // Device_List:L4282
        put(m, "CPH2853", "OPPO A6t 5G", "OPPO A6t 5G", "OnePlus", "device_list_full_import"); // Device_List:L4283
        put(m, "CPH2849", "OPPO A6t Pro", "OPPO A6t Pro", "OnePlus", "device_list_full_import"); // Device_List:L4284
        put(m, "CPH2851", "OPPO A6t Pro 5G", "OPPO A6t Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4285
        put(m, "CPH2895", "OPPO A6c", "OPPO A6c", "OnePlus", "device_list_full_import"); // Device_List:L4286
        put(m, "CPH1905", "OPPO A7", "OPPO A7", "OnePlus", "device_list_full_import"); // Device_List:L4287
        put(m, "CPH1903", "OPPO AX7", "OPPO AX7", "OnePlus", "device_list_full_import"); // Device_List:L4288
        put(m, "CPH1938", "OPPO A9", "OPPO A9", "OnePlus", "device_list_full_import"); // Device_List:L4289
        put(m, "CPH1941", "OPPO A9 2020", "OPPO A9 2020", "OnePlus", "device_list_full_import"); // Device_List:L4290
        put(m, "CPH2083", "OPPO A11k", "OPPO A11k", "OnePlus", "device_list_full_import"); // Device_List:L4291
        put(m, "CPH2185", "OPPO A15", "OPPO A15", "OnePlus", "device_list_full_import"); // Device_List:L4292
        put(m, "CPH2179", "OPPO A15s", "OPPO A15s", "OnePlus", "device_list_full_import"); // Device_List:L4293
        put(m, "CPH2275", "OPPO A16", "OPPO A16", "OnePlus", "device_list_full_import"); // Device_List:L4294
        put(m, "CPH2351", "OPPO A16k", "OPPO A16k", "OnePlus", "device_list_full_import"); // Device_List:L4295
        put(m, "CPH2271", "OPPO A16s", "OPPO A16s", "OnePlus", "device_list_full_import"); // Device_List:L4296
        put(m, "CPH2421", "OPPO A16e", "OPPO A16e", "OnePlus", "device_list_full_import"); // Device_List:L4297
        put(m, "CPH2477", "OPPO A17", "OPPO A17", "OnePlus", "device_list_full_import"); // Device_List:L4298
        put(m, "CPH2471", "OPPO A17k", "OPPO A17k", "OnePlus", "device_list_full_import"); // Device_List:L4299
        put(m, "CPH2591", "OPPO A18", "OPPO A18", "OnePlus", "device_list_full_import"); // Device_List:L4300
        put(m, "CPH2081", "OPPO A31", "OPPO A31", "OnePlus", "device_list_full_import"); // Device_List:L4301
        put(m, "CPH2137", "OPPO A33", "OPPO A33", "OnePlus", "device_list_full_import"); // Device_List:L4302
        put(m, "CPH2579", "OPPO A38", "OPPO A38", "OnePlus", "device_list_full_import"); // Device_List:L4303
        put(m, "CPH2069", "OPPO A52", "OPPO A52", "OnePlus", "device_list_full_import"); // Device_List:L4304
        put(m, "CPH2139", "OPPO A53", "OPPO A53", "OnePlus", "device_list_full_import"); // Device_List:L4305
        put(m, "CPH2135", "OPPO A53s", "OPPO A53s", "OnePlus", "device_list_full_import"); // Device_List:L4306
        put(m, "CPH2321", "OPPO A53s 5G", "OPPO A53s 5G", "OnePlus", "device_list_full_import"); // Device_List:L4307
        put(m, "CPH2239", "OPPO A54", "OPPO A54", "OnePlus", "device_list_full_import"); // Device_List:L4308
        put(m, "CPH2303", "OPPO A54 5G", "OPPO A54 5G", "OnePlus", "device_list_full_import"); // Device_List:L4309
        put(m, "OPG02", "OPPO A54 5G (KDDI)", "OPPO A54 5G (KDDI)", "OPPO", "device_list_full_import"); // Device_List:L4310
        put(m, "CPH2273", "OPPO A54s", "OPPO A54s", "OnePlus", "device_list_full_import"); // Device_List:L4311
        put(m, "CPH2325", "OPPO A55", "OPPO A55", "OnePlus", "device_list_full_import"); // Device_List:L4312
        put(m, "CPH2309", "OPPO A55s 5G", "OPPO A55s 5G", "OnePlus", "device_list_full_import"); // Device_List:L4313
        put(m, "A102OP", "OPPO A55s 5G (SoftBank)", "OPPO A55s 5G (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4314
        put(m, "CPH1701", "OPPO A57 (2016)", "OPPO A57 (2016)", "OnePlus", "device_list_full_import"); // Device_List:L4315
        put(m, "CPH2407", "OPPO A57", "OPPO A57", "OnePlus", "device_list_full_import"); // Device_List:L4316
        put(m, "CPH2385", "OPPO A57s", "OPPO A57s", "OnePlus", "device_list_full_import"); // Device_List:L4317
        put(m, "CPH2577", "OPPO A58", "OPPO A58", "OnePlus", "device_list_full_import"); // Device_List:L4318
        put(m, "CPH2617", "OPPO A59 5G", "OPPO A59 5G", "OnePlus", "device_list_full_import"); // Device_List:L4319
        put(m, "CPH3669", "OPPO A60", "OPPO A60", "OnePlus", "device_list_full_import"); // Device_List:L4320
        put(m, "CPH2067", "OPPO A72", "OPPO A72", "OnePlus", "device_list_full_import"); // Device_List:L4321
        put(m, "CPH2099", "OPPO A73", "OPPO A73", "OnePlus", "device_list_full_import"); // Device_List:L4322
        put(m, "CPH2161", "OPPO A73 5G", "OPPO A73 5G", "OnePlus", "device_list_full_import"); // Device_List:L4323
        put(m, "CPH2263", "OPPO A74 5G", "OPPO A74 5G", "OnePlus", "device_list_full_import"); // Device_List:L4324
    }

    private static void fill24(Map<String, Entry> m) {
        put(m, "CPH2375", "OPPO A76", "OPPO A76", "OnePlus", "device_list_full_import"); // Device_List:L4325
        put(m, "CPH2339", "OPPO A77 5G", "OPPO A77 5G", "OnePlus", "device_list_full_import"); // Device_List:L4326
        put(m, "CPH2473", "OPPO A77s", "OPPO A77s", "OnePlus", "device_list_full_import"); // Device_List:L4327
        put(m, "CPH2565", "OPPO A78", "OPPO A78", "OnePlus", "device_list_full_import"); // Device_List:L4328
        put(m, "CPH2495", "OPPO A78 5G", "OPPO A78 5G", "OnePlus", "device_list_full_import"); // Device_List:L4329
        put(m, "CPH2557", "OPPO A79 5G", "OPPO A79 5G", "OnePlus", "device_list_full_import"); // Device_List:L4330
        put(m, "A303OP", "OPPO A79 5G (SoftBank)", "OPPO A79 5G (SoftBank)", "OPPO", "device_list_full_import"); // Device_List:L4331
        put(m, "CPH2639", "OPPO A80 5G", "OPPO A80 5G", "OnePlus", "device_list_full_import"); // Device_List:L4332
        put(m, "CPH2021", "OPPO A91", "OPPO A91", "OnePlus", "device_list_full_import"); // Device_List:L4333
        put(m, "CPH2059", "OPPO A92", "OPPO A92", "OnePlus", "device_list_full_import"); // Device_List:L4334
        put(m, "CPH2123", "OPPO A93", "OPPO A93", "OnePlus", "device_list_full_import"); // Device_List:L4335
        put(m, "CPH2203", "OPPO A94", "OPPO A94", "OnePlus", "device_list_full_import"); // Device_List:L4336
        put(m, "CPH2211", "OPPO A94 5G", "OPPO A94 5G", "OnePlus", "device_list_full_import"); // Device_List:L4337
        put(m, "CPH2333", "OPPO A96", "OPPO A96", "OnePlus", "device_list_full_import"); // Device_List:L4338
        put(m, "CPH2529", "OPPO A98 5G", "OPPO A98 5G", "OnePlus", "device_list_full_import"); // Device_List:L4339
        put(m, "CPH1955", "OPPO K3", "OPPO K3", "OnePlus", "device_list_full_import"); // Device_List:L4340
        put(m, "CPH2373", "OPPO K10", "OPPO K10", "OnePlus", "device_list_full_import"); // Device_List:L4341
        put(m, "CPH2667", "OPPO K12x 5G", "OPPO K12x 5G", "OnePlus", "device_list_full_import"); // Device_List:L4342
        put(m, "CPH2729", "OPPO K13 5G", "OPPO K13 5G", "OnePlus", "device_list_full_import"); // Device_List:L4343
        put(m, "CPH2753", "OPPO K13x 5G", "OPPO K13x 5G", "OnePlus", "device_list_full_import"); // Device_List:L4344
        put(m, "CPH2761", "OPPO K13 Turbo 5G", "OPPO K13 Turbo 5G", "OnePlus", "device_list_full_import"); // Device_List:L4345
        put(m, "CPH2731", "OPPO K13 Turbo Pro 5G", "OPPO K13 Turbo Pro 5G", "OnePlus", "device_list_full_import"); // Device_List:L4346
        put(m, "CPH2869", "OPPO K14 5G", "OPPO K14 5G", "OnePlus", "device_list_full_import"); // Device_List:L4347
        put(m, "CPH2871", "OPPO K14x 5G", "OPPO K14x 5G", "OnePlus", "device_list_full_import"); // Device_List:L4348
        put(m, "OPD2102A", "OPPO Pad Air", "OPPO Pad Air", "OPPO", "device_list_full_import"); // Device_List:L4349
        put(m, "OPD2202", "OPPO Pad 2", "OPPO Pad 2", "OPPO", "device_list_full_import"); // Device_List:L4350
        put(m, "OPD2302", "OPPO Pad Neo Wi-Fi", "OPPO Pad Neo Wi-Fi", "OPPO", "device_list_full_import"); // Device_List:L4351
        put(m, "OPD2303", "OPPO Pad Neo LTE", "OPPO Pad Neo LTE", "OPPO", "device_list_full_import"); // Device_List:L4352
        put(m, "OPD2406", "OPPO Pad 3", "OPPO Pad 3", "OPPO", "device_list_full_import"); // Device_List:L4353
        put(m, "OPD2402", "OPPO Pad 3 Pro", "OPPO Pad 3 Pro", "OPPO", "device_list_full_import"); // Device_List:L4354
        put(m, "OPD2502", "OPPO Pad 5 Wi-Fi", "OPPO Pad 5 Wi-Fi", "OPPO", "device_list_full_import"); // Device_List:L4355
        put(m, "OPD2503", "OPPO Pad 5 5G", "OPPO Pad 5 5G", "OPPO", "device_list_full_import"); // Device_List:L4356
        put(m, "OPD2419", "OPPO Pad SE Wi-Fi", "OPPO Pad SE Wi-Fi", "OPPO", "device_list_full_import"); // Device_List:L4357
        put(m, "OPD2420", "OPPO Pad SE LTE", "OPPO Pad SE LTE", "OPPO", "device_list_full_import"); // Device_List:L4358
        put(m, "OBBE215", "OPPO Band 2 Japan", "OPPO Band 2 Japan", "OPPO", "device_list_full_import"); // Device_List:L4359
        put(m, "OWWE201", "OPPO Watch Free", "OPPO Watch Free", "OPPO", "device_list_full_import"); // Device_List:L4360
        put(m, "OW19W6", "OPPO Watch 41mm", "OPPO Watch 41mm", "OPPO", "device_list_full_import"); // Device_List:L4361
        put(m, "OW19W8", "OPPO Watch 46mm", "OPPO Watch 46mm", "OPPO", "device_list_full_import"); // Device_List:L4362
        put(m, "OW19W12", "OPPO Watch 46mm LTE", "OPPO Watch 46mm LTE", "OPPO", "device_list_full_import"); // Device_List:L4363
        put(m, "OWWE231", "OPPO Watch X", "OPPO Watch X", "OPPO", "device_list_full_import"); // Device_List:L4364
        put(m, "OWWE251", "OPPO Watch X2", "OPPO Watch X2", "OPPO", "device_list_full_import"); // Device_List:L4365
        put(m, "OWWE242", "OPPO Watch X2 Mini", "OPPO Watch X2 Mini", "OPPO", "device_list_full_import"); // Device_List:L4366
        put(m, "OWWE261", "OPPO Watch X3", "OPPO Watch X3", "OPPO", "device_list_full_import"); // Device_List:L4367
        put(m, "OWWE262", "OPPO Watch S", "OPPO Watch S", "OPPO", "device_list_full_import"); // Device_List:L4368
    }

    private static void put(Map<String, Entry> m, String key, String marketName, String marketNameZh, String maker, String source) {
        Entry e = new Entry(key, marketName, marketNameZh, maker, source);
        m.put(normalize(key), e);
    }

    static Match match(String[][] candidates) {
        if (candidates == null) return null;
        for (String[] candidate : candidates) {
            if (candidate == null || candidate.length < 2) continue;
            Match exact = exact(candidate[1], candidate[0]);
            if (exact != null) return exact;
        }
        for (String[] candidate : candidates) {
            if (candidate == null || candidate.length < 2) continue;
            Match prefix = prefix(candidate[1], candidate[0]);
            if (prefix != null) return prefix;
        }
        return null;
    }

    private static Match exact(String raw, String field) {
        String key = normalize(raw);
        if (key.isEmpty()) return null;
        Entry e = BY_KEY.get(key);
        if (e == null) return null;
        String src = e.source.isEmpty() ? "dex_builtin_model_db" : e.source;
        return new Match(e, src, "exact_" + field, e.modelKey, field);
    }

    private static Match prefix(String raw, String field) {
        String key = normalize(raw);
        if (key.length() < 5) return null;
        for (Map.Entry<String, Entry> item : BY_KEY.entrySet()) {
            String dbKey = item.getKey();
            if (dbKey.length() < 5) continue;
            if (key.startsWith(dbKey) || dbKey.startsWith(key)) {
                Entry e = item.getValue();
                String src = e.source.isEmpty() ? "dex_builtin_model_db" : e.source;
                return new Match(e, src, "prefix_" + field, e.modelKey, field);
            }
        }
        return null;
    }

    private static String join(String a, String b) {
        String left = a == null ? "" : a.trim();
        String right = b == null ? "" : b.trim();
        if (left.isEmpty()) return right;
        if (right.isEmpty()) return left;
        return left + " " + right;
    }

    static String normalize(String raw) {
        if (raw == null) return "";
        StringBuilder out = new StringBuilder(raw.length());
        String upper = raw.trim().toUpperCase(Locale.ROOT);
        for (int i = 0; i < upper.length(); i++) {
            char c = upper.charAt(i);
            if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) out.append(c);
        }
        return out.toString();
    }
}
