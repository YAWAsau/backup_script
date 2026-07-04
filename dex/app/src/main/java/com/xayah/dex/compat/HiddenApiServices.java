package com.xayah.dex.compat;

import java.util.HashMap;
import java.util.Map;

/**
 * Central system-service registry. Binder lookup and Stub.asInterface are cached
 * for the lifetime of the app_process JVM.
 */
public final class HiddenApiServices {
    public static final String SERVICE_ACTIVITY = "activity";
    public static final String SERVICE_APP_OPS = "appops";
    public static final String SERVICE_DEVICE_IDLE = "deviceidle";
    public static final String SERVICE_NOTIFICATION = "notification";
    public static final String SERVICE_PACKAGE = "package";
    public static final String SERVICE_PERMISSION_MANAGER = "permissionmgr";

    private static final Map<String, Object> SERVICE_CACHE = new HashMap<>();

    private HiddenApiServices() {
    }

    public static Object binder(String serviceName) throws Exception {
        return HiddenApiReflection.invokeFlexible(
                HiddenApiReflection.classForNameCached("android.os.ServiceManager"), "getService", serviceName);
    }

    public static Object interfaceService(String serviceName, String stubClassName) throws Exception {
        String key = serviceName + "#" + stubClassName;
        Object cached = SERVICE_CACHE.get(key);
        if (cached != null) {
            return cached;
        }
        Object binder = binder(serviceName);
        if (binder == null) {
            throw new IllegalStateException("service binder is null: " + serviceName);
        }
        Object service = HiddenApiReflection.invokeFlexible(
                HiddenApiReflection.classForNameCached(stubClassName), "asInterface", binder);
        if (service == null) {
            throw new IllegalStateException("service interface is null: " + serviceName + " via " + stubClassName);
        }
        SERVICE_CACHE.put(key, service);
        return service;
    }

    public static Object activity() throws Exception {
        return interfaceService(SERVICE_ACTIVITY, "android.app.IActivityManager$Stub");
    }

    public static Object deviceIdle() throws Exception {
        return interfaceService(SERVICE_DEVICE_IDLE, "android.os.IDeviceIdleController$Stub");
    }

    public static Object notification() throws Exception {
        return interfaceService(SERVICE_NOTIFICATION, "android.app.INotificationManager$Stub");
    }
}
