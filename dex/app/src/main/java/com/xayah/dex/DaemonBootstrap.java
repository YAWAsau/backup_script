package com.xayah.dex;

import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.system.Os;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Shared AF_UNIX daemon bootstrap for the small CLI daemons.
 *
 * Owns only socket lifecycle, owner/idle watching and accept-loop policy; each utility keeps its
 * own wire protocol and request handler.  This keeps AppState/Notification/HiddenApi daemon
 * behavior synchronized without merging their business logic.
 */
final class DaemonBootstrap {
    static final int UNIX_SOCKET_MODE = 0660;
    static final int UNIX_PATH_MAX_BYTES = 100;

    interface ClientHandler {
        void handle(LocalSocket client) throws Exception;
    }

    private DaemonBootstrap() {
    }

    static void runUnixDaemon(String componentName,
                              String socketPath,
                              long idleTimeoutMs,
                              int ownerPid,
                              String readyLine,
                              boolean concurrentClients,
                              ClientHandler handler) {
        if (handler == null) throw new IllegalArgumentException("handler is null");
        DaemonHardening.protectSelf(componentName);
        if (idleTimeoutMs <= 0L) throw new IllegalArgumentException("idleTimeoutMs must be > 0");
        if (ownerPid > 1 && readProcStarttime(ownerPid) == null) {
            throw new IllegalArgumentException("ownerPid is not alive: " + ownerPid);
        }

        LocalSocket bindSocket = null;
        LocalServerSocket server = null;
        AtomicBoolean closed = new AtomicBoolean(false);
        AtomicLong lastActivity = new AtomicLong(System.currentTimeMillis());
        AtomicInteger activeRequests = new AtomicInteger(0);
        File socketFile = null;
        try {
            socketFile = validateSocketPath(socketPath);
            File parent = socketFile.getParentFile();
            if (parent == null) throw new IllegalArgumentException("socketPath has no parent");
            if (!parent.isDirectory() && !parent.mkdirs()) {
                throw new java.io.IOException("cannot create socket parent: " + parent.getAbsolutePath());
            }
            if (socketFile.exists() && !socketFile.delete()) {
                throw new java.io.IOException("cannot remove stale socket: " + socketFile.getAbsolutePath());
            }

            bindSocket = new LocalSocket(LocalSocket.SOCKET_STREAM);
            bindSocket.bind(new LocalSocketAddress(socketFile.getAbsolutePath(), LocalSocketAddress.Namespace.FILESYSTEM));
            server = new LocalServerSocket(bindSocket.getFileDescriptor());
            try { Os.chmod(socketFile.getAbsolutePath(), UNIX_SOCKET_MODE); } catch (Throwable ignored) {}

            final LocalSocket finalBind = bindSocket;
            final LocalServerSocket finalServer = server;
            final File finalSocketFile = socketFile;
            final AtomicBoolean finalClosed = closed;
            Runnable closeResources = () -> closeDaemon(finalClosed, finalServer, finalBind, finalSocketFile);
            Runtime.getRuntime().addShutdownHook(new Thread(closeResources));

            final Long ownerStart = ownerPid > 1 ? readProcStarttime(ownerPid) : null;
            final long timeoutMs = idleTimeoutMs;
            Thread watcher = new Thread(() -> {
                while (!finalClosed.get()) {
                    try { Thread.sleep(2000L); } catch (InterruptedException ignored) {}
                    boolean ownerGone = ownerPid > 1
                            && (ownerStart == null || !ownerStart.equals(readProcStarttime(ownerPid)));
                    boolean idle = activeRequests.get() == 0
                            && System.currentTimeMillis() - lastActivity.get() > timeoutMs;
                    if (ownerGone || idle) {
                        closeResources.run();
                        System.exit(0);
                    }
                }
            }, componentName.toLowerCase(java.util.Locale.ROOT) + "-daemon-watchdog");
            watcher.setDaemon(true);
            watcher.start();

            System.out.println(readyLine);
            System.out.flush();

            while (!closed.get()) {
                LocalSocket client;
                try {
                    client = server.accept();
                } catch (Throwable t) {
                    break;
                }
                lastActivity.set(System.currentTimeMillis());
                activeRequests.incrementAndGet();
                if (concurrentClients) {
                    final LocalSocket finalClient = client;
                    Thread worker = new Thread(() -> {
                        try {
                            handler.handle(finalClient);
                        } catch (Throwable t) {
                            System.err.println("[" + componentName.toLowerCase(java.util.Locale.ROOT)
                                    + "-daemon] " + t.getClass().getName() + ": " + sanitize(t.getMessage()));
                            try { finalClient.close(); } catch (Throwable ignored) {}
                        } finally {
                            activeRequests.decrementAndGet();
                            lastActivity.set(System.currentTimeMillis());
                        }
                    }, componentName.toLowerCase(java.util.Locale.ROOT) + "-daemon-client");
                    worker.setDaemon(true);
                    worker.start();
                } else {
                    try {
                        handler.handle(client);
                    } catch (Throwable t) {
                        System.err.println("[" + componentName.toLowerCase(java.util.Locale.ROOT)
                                + "-daemon] " + t.getClass().getName() + ": " + sanitize(t.getMessage()));
                        try { client.close(); } catch (Throwable ignored) {}
                    } finally {
                        activeRequests.decrementAndGet();
                        lastActivity.set(System.currentTimeMillis());
                    }
                }
            }
        } catch (Throwable t) {
            System.err.println(componentName + "_DAEMON_FAILED reason=" + t.getClass().getSimpleName()
                    + " message=" + sanitize(t.getMessage()));
            if (server != null) try { server.close(); } catch (Throwable ignored) {}
            if (bindSocket != null) try { bindSocket.close(); } catch (Throwable ignored) {}
            if (socketFile != null) try { socketFile.delete(); } catch (Throwable ignored) {}
            System.exit(1);
        } finally {
            closed.set(true);
        }
    }

    private static File validateSocketPath(String socketPath) {
        if (socketPath == null || socketPath.trim().isEmpty()) {
            throw new IllegalArgumentException("socketPath is empty");
        }
        if (socketPath.indexOf('\n') >= 0 || socketPath.indexOf('\r') >= 0 || socketPath.indexOf('\0') >= 0) {
            throw new IllegalArgumentException("socketPath contains invalid chars");
        }
        File socketFile = new File(socketPath);
        if (!socketFile.isAbsolute()) throw new IllegalArgumentException("socketPath must be absolute");
        String canonical = socketFile.getAbsolutePath();
        if (canonical.getBytes(StandardCharsets.UTF_8).length > UNIX_PATH_MAX_BYTES) {
            throw new IllegalArgumentException("socketPath too long");
        }
        return socketFile;
    }

    private static void closeDaemon(AtomicBoolean closed, LocalServerSocket server, LocalSocket bindSocket, File socketFile) {
        if (!closed.compareAndSet(false, true)) return;
        try { server.close(); } catch (Throwable ignored) {}
        try { bindSocket.close(); } catch (Throwable ignored) {}
        try { socketFile.delete(); } catch (Throwable ignored) {}
    }

    static Long readProcStarttime(int pid) {
        try {
            File f = new File("/proc/" + pid + "/stat");
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            try (FileInputStream input = new FileInputStream(f)) {
                byte[] buf = new byte[512];
                int n;
                while ((n = input.read(buf)) >= 0) out.write(buf, 0, n);
            }
            String text = out.toString("UTF-8");
            int idx = text.lastIndexOf(')');
            if (idx < 0) return null;
            String[] parts = text.substring(idx + 1).trim().split("\\s+");
            if (parts.length > 19) return Long.parseLong(parts[19]);
        } catch (Throwable ignored) {}
        return null;
    }

    private static String sanitize(String raw) {
        if (raw == null) return "";
        String value = raw.replace('\n', ' ').replace('\r', ' ').replace('\0', ' ');
        return value.length() > 180 ? value.substring(0, 180) : value;
    }
}
