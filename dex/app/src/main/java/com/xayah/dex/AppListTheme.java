package com.xayah.dex;

import android.content.res.Resources;
import android.os.Build;
import dynamiccolor.ColorSpec.SpecVersion;
import dynamiccolor.DynamicScheme;
import hct.Hct;
import scheme.SchemeTonalSpot;
import java.util.Locale;

/** Read-only palette bridge. No wallpaper access or settings writes or APK required. */
public final class AppListTheme {
    private static int seed(Resources resources, boolean dark) {
        if (Build.VERSION.SDK_INT < 31) throw new IllegalStateException("no dynamic colors");
        String name = Build.VERSION.SDK_INT >= 34
                ? "system_primary_" + (dark ? "dark" : "light")
                : "system_accent1_" + (dark ? "200" : "600");
        int id = resources.getIdentifier(name, "color", "android");
        if (id == 0) throw new IllegalStateException("missing dynamic color");
        return resources.getColor(id, null);
    }

    private static void palette(StringBuilder out, boolean dark, int seed) {
        // KernelSU defaults: re-seed from the system primary, TonalSpot, 2025, phone, contrast 0.
        DynamicScheme s = new SchemeTonalSpot(Hct.fromInt(seed), dark, 0,
                SpecVersion.SPEC_2025, DynamicScheme.Platform.PHONE);
        String[] names = {"seed", "bg", "card", "field", "text", "muted", "line", "primary",
                "pressed", "footer", "danger", "selected", "on-primary", "accent"};
        int[] colors = {seed, s.getBackground(), s.getSurfaceBright(), s.getSurfaceContainerHighest(),
                s.getOnSurface(), s.getOnSurfaceVariant(), s.getOutline(), s.getPrimary(),
                s.getPrimaryContainer(), s.getSurfaceContainer(), s.getError(),
                s.getSecondaryContainer(), s.getOnPrimary(), s.getSecondaryContainer()};
        for (int i = 0; i < names.length; i++) {
            out.append(dark ? "dark." : "light.").append(names[i]).append('=')
                    .append(String.format(Locale.ROOT, "#%06x", colors[i] & 0xffffff)).append('\n');
        }
    }

    public static void main(String[] args) {
        if (args.length != 0) System.exit(2);
        boolean dynamic = true;
        int light = 0xff6750a4, dark = 0xffd0bcff;
        try {
            HiddenApiBypassBridge.installExemptionsOnce();
            Resources resources = HiddenApiHelper.getContext()
                    .createPackageContext("com.android.shell", 0).getResources();
            light = seed(resources, false); dark = seed(resources, true);
        }
        catch (Exception unavailable) { dynamic = false; }
        StringBuilder out = new StringBuilder(dynamic ? "source=system\n" : "source=fallback\n");
        palette(out, false, light);
        palette(out, true, dark);
        System.out.print(out);
        System.out.flush();
        System.exit(0);
    }
}
