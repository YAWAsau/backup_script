package com.xayah.dex;

import android.app.Application;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.IContentProvider;
import android.os.Build;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Looper;

import java.io.FileNotFoundException;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

public class HiddenApiHelper {
    private static final Object CONTEXT_LOCK = new Object();
    private static volatile Context sContext;
    private static volatile Object sActivityThread;

    public static Context initializeContext() throws ClassNotFoundException, NoSuchMethodException,
            InvocationTargetException, IllegalAccessException, NoSuchFieldException {
        return getContext();
    }

    public static Context getContext() throws ClassNotFoundException, NoSuchMethodException,
            InvocationTargetException, IllegalAccessException, NoSuchFieldException {
        Context cached = sContext;
        if (cached != null) return cached;
        synchronized (CONTEXT_LOCK) {
            cached = sContext;
            if (cached != null) return cached;

            Class<?> activityThreadClass = Class.forName("android.app.ActivityThread");
            Object thread = null;
            try {
                thread = activityThreadClass.getMethod("currentActivityThread").invoke(null);
            } catch (NoSuchMethodException ignored) {
                // Older vendor frameworks may not expose currentActivityThread().
            }

            if (thread == null) {
                if (Looper.myLooper() == null && Looper.getMainLooper() == null) {
                    Looper.prepareMainLooper();
                }
                if (Looper.myLooper() == null) {
                    throw new IllegalStateException(
                            "system Context must be initialized on the daemon main thread before workers start");
                }

                PrintStream originalStderr = System.err;
                PrintStream nullStderr = null;
                try {
                    nullStderr = new PrintStream("/dev/null");
                    System.setErr(nullStderr);
                    thread = activityThreadClass.getMethod("systemMain").invoke(null);
                } catch (FileNotFoundException ignored) {
                    thread = activityThreadClass.getMethod("systemMain").invoke(null);
                } finally {
                    System.setErr(originalStderr);
                    if (nullStderr != null) nullStderr.close();
                }
            }

            Context context = (Context) activityThreadClass.getMethod("getSystemContext").invoke(thread);
            if (context == null) throw new IllegalStateException("system Context is null");

            // Setup the fake initial Application once for hidden framework calls that require it.
            Application app = new Application();
            Field baseField = ContextWrapper.class.getDeclaredField("mBase");
            baseField.setAccessible(true);
            baseField.set(app, new FakeContext(context));
            Field initialApplicationField = activityThreadClass.getDeclaredField("mInitialApplication");
            initialApplicationField.setAccessible(true);
            if (initialApplicationField.get(thread) == null) {
                initialApplicationField.set(thread, app);
            }

            sActivityThread = thread;
            sContext = context;
            return context;
        }
    }

    /**
     * <a href="https://github.com/Genymobile/scrcpy/pull/5476">scrcpy #5476</a>
     */
    public static IContentProvider getContentProviderExternal(String name, IBinder token) {
        try {
            Method method;
            Object[] args;
            Class<?> cls = Class.forName("android.app.ActivityManagerNative");
            Method getDefaultMethod = cls.getDeclaredMethod("getDefault");
            IInterface am = (IInterface) getDefaultMethod.invoke(null);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                method = am.getClass().getMethod("getContentProviderExternal", String.class, int.class, IBinder.class, String.class);
                args = new Object[]{name, 0, token, null};
            } else {
                method = am.getClass().getMethod("getContentProviderExternal", String.class, int.class, IBinder.class);
                args = new Object[]{name, 0, token};
            }
            Object providerHolder = method.invoke(am, args);
            if (providerHolder == null) {
                return null;
            }
            Field providerField = providerHolder.getClass().getDeclaredField("provider");
            providerField.setAccessible(true);
            return (IContentProvider) providerField.get(providerHolder);
        } catch (ReflectiveOperationException e) {
            e.printStackTrace(System.err);
            return null;
        }
    }
}
