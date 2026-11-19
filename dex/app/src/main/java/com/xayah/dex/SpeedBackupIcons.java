package com.xayah.dex;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;

/** Shared notification alpha-mask derived from the supplied storage/lightning logo. */
public final class SpeedBackupIcons {
    private SpeedBackupIcons() {}
    public static Bitmap notificationBitmap(int size) {
        Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        // Match the supplied 512-unit mark, cropped with a small status-icon inset.
        canvas.scale(size / 384f, size / 384f);
        canvas.translate(-64f, -64f);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.WHITE);
        // SystemUI tints the alpha mask: use one solid tone, not translucent layers.
        paint.setAlpha(255);
        for (int y : new int[]{132, 222, 312})
            canvas.drawRoundRect(new RectF(116, y, 396, y + 68), 22, 22, paint);
        Path bolt = new Path();
        bolt.moveTo(300, 96); bolt.lineTo(204, 274); bolt.lineTo(262, 274);
        bolt.lineTo(232, 420); bolt.lineTo(340, 226); bolt.lineTo(280, 226); bolt.close();
        // Cut a transparent outline so the bolt stays distinct at status-bar size.
        paint.setXfermode(new android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.CLEAR));
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(28);
        paint.setStrokeJoin(Paint.Join.ROUND);
        canvas.drawPath(bolt, paint);
        paint.setXfermode(null);
        paint.setStyle(Paint.Style.FILL);
        canvas.drawPath(bolt, paint);
        return bitmap;
    }
}
