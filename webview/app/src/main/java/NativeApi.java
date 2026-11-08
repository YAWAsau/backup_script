package io.github.yawasau.speedbackup.webview;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;

/** Authenticated loopback transport. Never accepts redirects or arbitrary URLs. */
final class NativeApi implements AutoCloseable {
    static final int MAX_BYTES = 8 * 1024 * 1024;
    final String origin;
    final String identity;
    private final String token;
    private final Set<HttpURLConnection> active = new HashSet<>();
    private boolean closed;
    volatile java.util.function.Consumer<String> diagnostic;

    NativeApi(String address) {
        try {
            URI uri = new URI(address);
            if (!"http".equals(uri.getScheme()) || !"127.0.0.1".equals(uri.getHost())
                    || uri.getPort() < 1 || uri.getPort() > 65535 || uri.getRawUserInfo() != null
                    || !"/".equals(uri.getRawPath()) || uri.getRawQuery() != null
                    || uri.getRawFragment() == null || !uri.getRawFragment().matches("[0-9a-f]{64}"))
                throw new IllegalArgumentException("Invalid local session");
            origin = "http://127.0.0.1:" + uri.getPort();
            token = uri.getRawFragment();
            identity = origin + "#" + token;
        } catch (java.net.URISyntaxException e) {
            throw new IllegalArgumentException("Invalid local session", e);
        }
    }

    NativeApi fork() { return new NativeApi(origin + "/#" + token); }

    String get(String route) throws IOException { return request(route, null); }
    String post(String route, String body) throws IOException {
        if (body == null) throw new IllegalArgumentException("Missing request body");
        return request(route, body);
    }

    private String request(String route, String body) throws IOException {
        if (route == null || !route.matches("[a-z][a-z0-9-]{0,63}"))
            throw new IllegalArgumentException("Invalid API route");
        byte[] input = body == null ? null : body.getBytes(StandardCharsets.UTF_8);
        if (input != null && input.length > MAX_BYTES) throw new IOException("Request too large");
        HttpURLConnection connection = (HttpURLConnection) URI.create(origin + "/api/" + route).toURL().openConnection(java.net.Proxy.NO_PROXY);
        synchronized (this) {
            if (closed) { connection.disconnect(); throw new IOException("Session closed"); }
            active.add(connection);
        }
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setUseCaches(false);
            connection.setConnectTimeout(5000);
            connection.setReadTimeout(18000);
            connection.setRequestProperty("X-SpeedBackup-Token", token);
            connection.setRequestProperty("Content-Type", "text/plain;charset=UTF-8");
            connection.setRequestProperty("Cache-Control", "no-store");
            connection.setRequestMethod(input == null ? "GET" : "POST");
            if (input != null) {
                connection.setDoOutput(true);
                connection.setFixedLengthStreamingMode(input.length);
                try (java.io.OutputStream out = connection.getOutputStream()) { out.write(input); }
            }
            int status = connection.getResponseCode();
            // A root endpoint must never forward session credentials to another origin.
            if (status >= 300 && status < 400) throw new IOException("API redirect rejected");
            if (connection.getContentLengthLong() > MAX_BYTES) throw new IOException("API response too large");
            InputStream stream = status >= 200 && status < 300 ? connection.getInputStream() : connection.getErrorStream();
            String text = stream == null ? "" : boundedRead(stream);
            synchronized (this) { if (closed) throw new IOException("Session closed"); }
            if (status < 200 || status >= 300) throw new ApiFailure(status, text);
            return text;
        } catch (IOException e) {
            java.util.function.Consumer<String> sink=diagnostic;
            if(sink!=null&&!"diagnostic".equals(route))try{sink.accept("native-transport:"+route+":"+(e instanceof ApiFailure?Integer.toString(((ApiFailure)e).status):e.getClass().getSimpleName()));}catch(RuntimeException ignored){}
            throw e;
        } finally {
            synchronized (this) { active.remove(connection); }
            connection.disconnect();
        }
    }

    // Event-driven Rust discovery stream. No LAN sockets, DNS or credentials here.
    void discovery(String id, java.util.function.Consumer<String> event) throws IOException {
        if(!id.matches("[0-9a-f]{32}"))throw new IOException("Invalid discovery id");
        HttpURLConnection c=(HttpURLConnection)URI.create(origin+"/api/discovery").toURL().openConnection(java.net.Proxy.NO_PROXY);
        synchronized(this){if(closed){c.disconnect();throw new IOException("Session closed");}active.add(c);}
        try {
            c.setInstanceFollowRedirects(false);c.setUseCaches(false);c.setConnectTimeout(5000);c.setReadTimeout(18000);
            c.setRequestProperty("X-SpeedBackup-Token",token);c.setRequestProperty("Content-Type","text/plain;charset=UTF-8");
            c.setRequestMethod("POST");c.setDoOutput(true);
            byte[] body=id.getBytes(StandardCharsets.UTF_8);c.setFixedLengthStreamingMode(body.length);
            try(java.io.OutputStream out=c.getOutputStream()){out.write(body);}
            int status=c.getResponseCode();if(status!=200)throw new ApiFailure(status,"Discovery unavailable");
            try(java.io.Reader reader=new java.io.BufferedReader(new java.io.InputStreamReader(c.getInputStream(),StandardCharsets.UTF_8))){
                StringBuilder line=new StringBuilder();int total=0;int value;
                while((value=reader.read())!=-1){
                    if(++total>16*1024*1024||line.length()>262144)throw new IOException("Discovery response too large");
                    if(value=='\n'){if(line.length()>0)event.accept(line.toString());line.setLength(0);}else line.append((char)value);
                }
                if(line.length()!=0)throw new IOException("Incomplete discovery event");
            }
        } finally {synchronized(this){active.remove(c);}c.disconnect();}
    }

    // Separate bounded binary transport; text APIs keep their smaller limit.
    void systemWallpaper(int userId, java.io.File target) throws IOException {
        if(userId<0 || userId>9999)throw new IOException("Invalid user");
        HttpURLConnection c=(HttpURLConnection)URI.create(origin+"/api/system-wallpaper").toURL().openConnection(java.net.Proxy.NO_PROXY);
        synchronized(this){if(closed){c.disconnect();throw new IOException("Session closed");}active.add(c);}
        try {
            c.setInstanceFollowRedirects(false);c.setUseCaches(false);c.setConnectTimeout(5000);c.setReadTimeout(18000);
            c.setRequestProperty("X-SpeedBackup-Token",token);c.setRequestProperty("Content-Type","text/plain;charset=UTF-8");
            c.setRequestMethod("POST");c.setDoOutput(true);
            byte[] body=Integer.toString(userId).getBytes(StandardCharsets.UTF_8);c.setFixedLengthStreamingMode(body.length);
            try(java.io.OutputStream out=c.getOutputStream()){out.write(body);}
            int status=c.getResponseCode();if(status!=200)throw new ApiFailure(status,"System wallpaper unavailable");
            long size=c.getContentLengthLong();if(size<1 || size>32L*1024*1024)throw new IOException("Invalid wallpaper size");
            long total=0;
            try(InputStream in=c.getInputStream();java.io.OutputStream out=new java.io.FileOutputStream(target)){
                byte[] buffer=new byte[65536];for(int n;(n=in.read(buffer))!=-1;){total+=n;if(total>size)throw new IOException("Wallpaper too large");out.write(buffer,0,n);}
            }
            if(total!=size)throw new IOException("Incomplete wallpaper");
            synchronized(this){if(closed)throw new IOException("Session closed");}
        }finally{synchronized(this){active.remove(c);}c.disconnect();}
    }

    private static String boundedRead(InputStream stream) throws IOException {
        try (InputStream in = stream; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[16384];
            for (int read; (read = in.read(buffer)) != -1;) {
                if (out.size() > MAX_BYTES - read) throw new IOException("API response too large");
                out.write(buffer, 0, read);
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    @Override public void close() {
        HttpURLConnection[] connections;
        synchronized (this) {
            closed = true;
            connections = active.toArray(new HttpURLConnection[0]);
            active.clear();
        }
        for (HttpURLConnection connection : connections) connection.disconnect();
    }

    static final class ApiFailure extends IOException {
        final int status;
        ApiFailure(int status, String reason) {
            super(reason.isEmpty() ? "API request failed (" + status + ")" : reason.substring(0, Math.min(reason.length(), 8192)));
            this.status = status;
        }
    }
}
