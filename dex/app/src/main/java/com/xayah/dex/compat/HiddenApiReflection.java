package com.xayah.dex.compat;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Rikka HiddenApi style compatibility layer: keep reflection, service and SDK
 * signature fallbacks out of the command entry class.
 */
public final class HiddenApiReflection {
    private static final Map<String, Class<?>> CLASS_CACHE = new HashMap<>();
    private static final Map<String, Method> METHOD_CACHE = new HashMap<>();
    private static final Set<String> METHOD_MISS_CACHE = new HashSet<>();

    private HiddenApiReflection() {
    }

    public static Class<?> classForNameCached(String name) throws ClassNotFoundException {
        Class<?> cached = CLASS_CACHE.get(name);
        if (cached != null) {
            return cached;
        }
        Class<?> clazz = Class.forName(name);
        CLASS_CACHE.put(name, clazz);
        return clazz;
    }

    public static Object invokeRequired(Object target, String methodName, Object... args) throws Exception {
        return invokeFlexible(target, methodName, args);
    }

    public static Object invokeFlexible(Object target, String methodName, Object... args) throws Exception {
        if (target == null) {
            throw new NullPointerException("target == null for " + methodName);
        }
        if (args == null) {
            args = new Object[0];
        }
        Class<?> clazz = target instanceof Class<?> ? (Class<?>) target : target.getClass();
        String key = buildMethodKey(clazz, methodName, args);
        Method cached = METHOD_CACHE.get(key);
        if (cached != null) {
            return cached.invoke(target instanceof Class<?> ? null : target, args);
        }
        if (METHOD_MISS_CACHE.contains(key)) {
            throw new NoSuchMethodException(clazz.getName() + "." + methodName);
        }
        Method resolved = resolveMethod(clazz, methodName, args);
        if (resolved == null) {
            METHOD_MISS_CACHE.add(key);
            throw new NoSuchMethodException(clazz.getName() + "." + methodName);
        }
        METHOD_CACHE.put(key, resolved);
        return resolved.invoke(target instanceof Class<?> ? null : target, args);
    }

    public static Object callFirst(Object target, Call... calls) {
        Throwable last = null;
        if (calls != null) {
            for (Call call : calls) {
                try {
                    return invokeFlexible(target, call.methodName, call.args);
                } catch (Throwable throwable) {
                    last = throwable;
                }
            }
        }
        CompatDebug.throwable("callFirst all signatures failed", last);
        return null;
    }

    public static Object callRequired(Object target, Call... calls) throws Exception {
        Throwable last = null;
        if (calls != null) {
            for (Call call : calls) {
                try {
                    return invokeFlexible(target, call.methodName, call.args);
                } catch (Throwable throwable) {
                    last = throwable;
                }
            }
        }
        CompatDebug.throwable("callRequired all signatures failed", last);
        if (last instanceof Exception) {
            throw (Exception) last;
        }
        throw new IllegalStateException(last != null ? last.getMessage() : "No matching method");
    }

    public static Object fieldValue(Class<?> clazz, String name, Object fallback) {
        try {
            java.lang.reflect.Field field = clazz.getField(name);
            field.setAccessible(true);
            return field.get(null);
        } catch (Throwable throwable) {
            CompatDebug.throwable("fieldValue " + clazz.getName() + "." + name, throwable);
            return fallback;
        }
    }

    public static Integer intField(Class<?> clazz, String name, int fallback) {
        Object value = fieldValue(clazz, name, fallback);
        return value instanceof Integer ? (Integer) value : fallback;
    }

    private static String buildMethodKey(Class<?> clazz, String methodName, Object[] args) {
        StringBuilder builder = new StringBuilder(clazz.getName());
        builder.append('#').append(methodName).append('#').append(args.length);
        for (Object arg : args) {
            builder.append('#').append(arg == null ? "null" : arg.getClass().getName());
        }
        return builder.toString();
    }

    private static Method resolveMethod(Class<?> clazz, String methodName, Object[] args) {
        for (Method method : clazz.getMethods()) {
            if (matches(method, methodName, args)) {
                method.setAccessible(true);
                return method;
            }
        }
        for (Method method : clazz.getDeclaredMethods()) {
            if (matches(method, methodName, args)) {
                method.setAccessible(true);
                return method;
            }
        }
        return null;
    }

    private static boolean matches(Method method, String methodName, Object[] args) {
        if (!method.getName().equals(methodName)) {
            return false;
        }
        Class<?>[] paramTypes = method.getParameterTypes();
        if (paramTypes.length != args.length) {
            return false;
        }
        for (int i = 0; i < paramTypes.length; i++) {
            Object arg = args[i];
            if (arg == null) {
                if (paramTypes[i].isPrimitive()) {
                    return false;
                }
                continue;
            }
            if (!primitiveToWrapper(paramTypes[i]).isInstance(arg)) {
                return false;
            }
        }
        return true;
    }

    private static Class<?> primitiveToWrapper(Class<?> type) {
        if (!type.isPrimitive()) return type;
        if (type == int.class) return Integer.class;
        if (type == boolean.class) return Boolean.class;
        if (type == long.class) return Long.class;
        if (type == float.class) return Float.class;
        if (type == double.class) return Double.class;
        if (type == byte.class) return Byte.class;
        if (type == short.class) return Short.class;
        if (type == char.class) return Character.class;
        if (type == void.class) return Void.class;
        return type;
    }

    public static final class Call {
        final String methodName;
        final Object[] args;

        public Call(String methodName, Object... args) {
            this.methodName = methodName;
            this.args = args;
        }
    }
}
