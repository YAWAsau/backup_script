package com.xayah.dex;

import android.system.Os;
import android.system.StructStat;
import com.google.gson.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.security.spec.*;
import java.util.*;
import java.util.concurrent.*;

/** Device-signed pairing independent of DAV login; short-lived token is memory-only. */
public final class PowerNotifyUtil {
    private static final File STORE = new File("/data/adb/speedbackup-power");
    private static final Gson JSON = new Gson();
    private static final Set<String> STATES = new HashSet<>(Arrays.asList(
            "waiting", "countdown", "deferred", "cancelled", "shutting_down", "error", "closed", "simulated"));

    public static void main(String[] args) {
        if (args.length == 3 && "coordinate".equals(args[0])) {
            FutureTask<Void> coordinator = new FutureTask<>(() -> { PowerCompletion.run(args[1], args[2], STORE); return null; });
            Thread owner = new Thread(coordinator, "power-completion"); owner.setDaemon(true); owner.start();
            try { coordinator.get(250, TimeUnit.SECONDS); }
            catch (Exception ignored) { coordinator.cancel(true); try { owner.join(1000); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
            System.exit(0);
        }
        // A daemon worker bounds DNS, TLS, response reads and retries together.
        FutureTask<String> task = new FutureTask<>(() -> execute(args, STORE));
        Thread thread = new Thread(task, "power-notify"); thread.setDaemon(true); thread.start();
        try { System.out.println(task.get(55, TimeUnit.SECONDS)); System.exit(0); }
        catch (Exception ignored) { task.cancel(true); System.out.println("UNAVAILABLE"); System.exit(1); }
    }

    private static void pruneExpiredJobs(File store) {
        File[] jobs = store.listFiles(); if (jobs == null) return;
        long cutoff = System.currentTimeMillis() - 604800000L;
        for (File dir : jobs) {
            if (!dir.getName().matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")) continue;
            try {
                secure(dir, true);
                if (dir.lastModified() >= cutoff) continue;
                File[] files = dir.listFiles(); if (files == null) continue;
                boolean known = true;
                for (File file : files) if (!Arrays.asList("job.json", "ready", "offered", "attempted").contains(file.getName())) known = false;
                if (!known) continue;
                for (File file : files) Files.deleteIfExists(file.toPath());
                Files.deleteIfExists(dir.toPath());
            } catch (Exception ignored) { /* Preserve unverified state. */ }
        }
    }

    static synchronized String localJob(String[] args) throws Exception {
        if(args.length==0 || !Arrays.asList("begin","problem","prepare").contains(args[0]))throw new IOException("local command");
        return execute(args,STORE);
    }
    static String execute(String[] args, File store) throws Exception {
        if (args.length == 0) throw new IOException();
        String command = args[0];
        if ("capabilities".equals(command)) return "power.manual_shutdown_v1";
        if ("begin".equals(command)) {
            if (args.length != 3 || !("backup".equals(args[1]) || "restore".equals(args[1]))) throw new IOException();
            String base = origin(args[2]); validateTransport(base, true);
            if (store.exists()) secure(store, true);
            else { if (!store.mkdirs()) throw new IOException(); Os.chmod(store.getPath(), 0700); }
            secure(store, true);
            pruneExpiredJobs(store);
            String id = UUID.randomUUID().toString();
            File dir = new File(store, id); if (!dir.mkdir()) throw new IOException();
            Os.chmod(dir.getPath(), 0700);
            JsonObject job = new JsonObject(); job.addProperty("job_id", id);
            job.addProperty("origin", base); job.addProperty("operation", args[1]);
            job.addProperty("created", System.currentTimeMillis());
            write(new File(dir, "job.json"), JSON.toJson(job));
            return id;
        }
        secure(store, true);
        boolean originCheck = "match-origin".equals(command) && args.length == 3;
        boolean preparation="prepare".equals(command)&&args.length==8;
        if ((!originCheck && !preparation && args.length != 2) || !args[1].matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")) throw new IOException();
        String id = args[1]; File dir = new File(store, id); secure(dir, true);
        JsonObject job = JsonParser.parseString(read(new File(dir, "job.json"), 2048)).getAsJsonObject();
        String base = origin(job.get("origin").getAsString()); validateTransport(base, true);
        if (!id.equals(job.get("job_id").getAsString())
                || System.currentTimeMillis() - job.get("created").getAsLong() > 604800000L) throw new IOException();
        if (originCheck) {
            if (!base.equals(origin(args[2]))) throw new IOException();
            return "MATCH";
        }
        if(preparation){
            Files.deleteIfExists(new File(dir,"ready").toPath());
            // Validate origin/result before publishing either workers or ready.
            if(!base.equals(origin(args[6])))throw new IOException("origin");
            Integer.parseInt(args[7]);
            File run=GuardLifecycle.runDirectory(new File(args[4]));
            String extras=PowerJobState.collectExtras(run,args[3],args[5]);
            PowerJobState.snapshot(dir,args[2],extras);
            return PowerJobState.ready(dir,base,args[6],args[7]);
        }
        if("problem".equals(command)){
            write(new File(dir,"issues"),"1\n");
            File ready=new File(dir,"ready");
            if(ready.exists() && read(ready,32).trim().equals("success"))write(ready,"partial\n");
            return "PROBLEM_RECORDED";
        }
        String outcome = read(new File(dir, "ready"), 32).trim();
        if (!Arrays.asList("success", "failed", "partial", "cancelled").contains(outcome)) throw new IOException();
        if ("offer".equals(command)) {
            Reply reply = request(base + "/api/v1/capabilities", null, null);
            if (reply.status != 200 || !capable(reply.body)) throw new IOException();
            write(new File(dir, "offered"), "1"); return "AVAILABLE";
        }
        if (!("complete".equals(command) || "complete-preview".equals(command)) || !new File(dir, "offered").isFile()) throw new IOException();
        // Claim before network I/O. A later invocation cannot restart a cancelled/completed job.
        if (new File(dir, "attempted").exists()) return "ALREADY_ATTEMPTED";
        JsonObject body = new JsonObject(); body.addProperty("job_id", id);
        body.addProperty("operation", job.get("operation").getAsString());
        body.addProperty("outcome", outcome); body.addProperty("user_confirmed", true);
        body.addProperty("preview", "complete-preview".equals(command));
        String credential = pairForJob(store, base, id);
        if (credential.startsWith("PAIRING_REQUIRED ")) return credential;
        if (!new File(dir, "attempted").createNewFile()) return "ALREADY_ATTEMPTED";
        Os.chmod(new File(dir, "attempted").getPath(), 0600);
        byte[] bytes = JSON.toJson(body).getBytes(StandardCharsets.UTF_8);
        for (int attempt = 0; attempt < 4; attempt++) {
            if (attempt > 0) Thread.sleep(new int[]{2000, 5000, 10000}[attempt - 1]);
            Reply reply;
            try { reply = request(base + "/api/v1/power/manual", credential, bytes); }
            catch (IOException failure) { continue; }
            if (reply.status == 200 || reply.status == 202) {
                JsonObject result = JsonParser.parseString(reply.body).getAsJsonObject();
                if (!id.equals(result.get("job_id").getAsString())) throw new IOException();
                String state = result.get("state").getAsString();
                if (!STATES.contains(state)) throw new IOException();
                return "STATE " + state; // Never echo untrusted server text or the response body.
            }
            if (reply.status < 500 || reply.status > 599) return "REJECTED " + reply.status;
        }
        return "NOTIFICATION_FAILED";
    }

    static String pairForJob(File store, String base, String id) throws Exception {
        KeyPair key = deviceKey(store);
        String encoded = Base64.getUrlEncoder().withoutPadding().encodeToString(key.getPublic().getEncoded());
        StringBuilder fingerprint = new StringBuilder();
        for (byte b : MessageDigest.getInstance("SHA-256").digest(key.getPublic().getEncoded())) fingerprint.append(String.format(Locale.ROOT, "%02x", b & 255));
        JsonObject challengeBody = new JsonObject(); challengeBody.addProperty("public_key", encoded);
        challengeBody.addProperty("device_name", "SpeedBackup Android");
        challengeBody.addProperty("job_id", id); challengeBody.addProperty("scope", "power:manual");
        Reply challenge = request(base + "/api/v1/power/challenge", null, JSON.toJson(challengeBody).getBytes(StandardCharsets.UTF_8));
        if (challenge.status != 200) throw new IOException();
        JsonObject c = JsonParser.parseString(challenge.body).getAsJsonObject();
        String message = c.get("message").getAsString();
        String expected = "SpeedBackup power device v1\n" + c.get("challenge_id").getAsString() + "\n" + fingerprint + "\n" + id + "\npower:manual";
        if (!expected.equals(message)) throw new IOException();
        if (!fingerprint.toString().equals(c.get("device_id").getAsString()) || message.length() > 4096
                || c.get("expires_unix").getAsLong() <= System.currentTimeMillis()/1000) throw new IOException();
        JsonObject proof = new JsonObject(); proof.addProperty("challenge_id", c.get("challenge_id").getAsString());
        proof.addProperty("signature", sign(key, message));
        Reply paired = request(base + "/api/v1/power/pair", null, JSON.toJson(proof).getBytes(StandardCharsets.UTF_8));
        if (paired.status != 200 && paired.status != 202) throw new IOException();
        JsonObject result = JsonParser.parseString(paired.body).getAsJsonObject();
        if (paired.status == 202) {
            if (!"approval_required".equals(result.get("state").getAsString())
                    || !fingerprint.toString().equals(result.get("device_id").getAsString())) throw new IOException();
            return "PAIRING_REQUIRED " + fingerprint;
        }
        if (!id.equals(result.get("job_id").getAsString()) || !"power:manual".equals(result.get("scope").getAsString())
                || result.get("expires_unix").getAsLong() <= System.currentTimeMillis()/1000) throw new IOException();
        String token = result.get("token").getAsString();
        if (!token.matches("[A-Za-z0-9._~+/-]{16,1024}={0,2}")) throw new IOException();
        return token;
    }
    // Device identity authorizes power independently of DAV access. No shared app secret.
    static KeyPair deviceKey(File store) throws Exception {
        File file = new File(store, "device-key.json");
        if (file.exists()) {
            JsonObject key = JsonParser.parseString(read(file, 8192)).getAsJsonObject();
            KeyFactory factory = KeyFactory.getInstance("EC");
            PrivateKey priv = factory.generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(key.get("private").getAsString())));
            PublicKey pub = factory.generatePublic(new X509EncodedKeySpec(Base64.getDecoder().decode(key.get("public").getAsString())));
            return new KeyPair(pub, priv);
        }
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        KeyPair pair = generator.generateKeyPair();
        JsonObject key = new JsonObject();
        key.addProperty("private", Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded()));
        key.addProperty("public", Base64.getEncoder().encodeToString(pair.getPublic().getEncoded()));
        write(file, JSON.toJson(key));
        return pair;
    }
    static String sign(KeyPair pair, String challenge) throws Exception {
        Signature signature = Signature.getInstance("SHA256withECDSA");
        signature.initSign(pair.getPrivate());
        signature.update(challenge.getBytes(StandardCharsets.UTF_8));
        return Base64.getUrlEncoder().withoutPadding().encodeToString(signature.sign());
    }
    static String origin(String input) throws Exception {
        URI uri = new URI(input);
        if (uri.getUserInfo() != null || uri.getHost() == null || uri.getFragment() != null
                || uri.getQuery() != null || !("http".equalsIgnoreCase(uri.getScheme())
                || "https".equalsIgnoreCase(uri.getScheme()))) throw new IOException();
        String scheme = uri.getScheme().toLowerCase(Locale.ROOT);
        int port = uri.getPort(); if (port == 0 || port > 65535) throw new IOException();
        if (("http".equals(scheme) && port == 80) || ("https".equals(scheme) && port == 443)) port = -1;
        return new URI(scheme, null, uri.getHost().toLowerCase(Locale.ROOT), port, null, null, null).toASCIIString();
    }
    static void validateTransport(String base, boolean trustedLan) throws Exception {
        if (base.startsWith("https://")) return;
        // HTTP is restricted to an explicitly trusted numeric private IPv4 origin.
        String host = new URI(base).getHost();
        if (!trustedLan || !host.matches("[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+")) throw new IOException();
        InetAddress address = InetAddress.getByName(host);
        if (!address.isSiteLocalAddress() && !address.isLoopbackAddress()) throw new IOException();
    }
    static boolean capable(String body) {
        try {
            JsonObject j = JsonParser.parseString(body).getAsJsonObject();
            return "SpeedBackup Server".equals(j.get("server").getAsString())
                    && j.getAsJsonObject("protocol").get("major").toString().equals("1")
                    && j.getAsJsonObject("features").get("manual_shutdown_v1").toString().equals("true")
                    && j.getAsJsonObject("features").get("manual_shutdown_device_pairing_v1").toString().equals("true");
        } catch (RuntimeException e) { return false; }
    }
    static Reply request(String url, String credential, byte[] body) throws Exception {
        return requestAuthorized(url, credential == null ? null : "Bearer " + credential, body);
    }
    static Reply requestAuthorized(String url, String authorization, byte[] body) throws Exception {
        FutureTask<Reply> call = new FutureTask<>(() -> {
            HttpURLConnection c = (HttpURLConnection)new URL(url).openConnection(Proxy.NO_PROXY);
            try {
                c.setInstanceFollowRedirects(false); c.setConnectTimeout(4000); c.setReadTimeout(4000);
                c.setUseCaches(false); c.setRequestProperty("Accept", "application/json");
                if (body != null) {
                    c.setRequestMethod("POST"); c.setDoOutput(true); c.setFixedLengthStreamingMode(body.length);
                    c.setRequestProperty("Content-Type", "application/json");
                    if (authorization != null) c.setRequestProperty("Authorization", authorization);
                    try (OutputStream out = c.getOutputStream()) { out.write(body); }
                }
                int status = c.getResponseCode();
                String text = "";
                if (status == 200 || status == 202) {
                    try (InputStream in = c.getInputStream()) {
                        ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buffer = new byte[1024]; int n;
                        while ((n = in.read(buffer)) != -1) { if (out.size()+n > 16384) throw new IOException(); out.write(buffer,0,n); }
                        text = out.toString("UTF-8");
                    }
                }
                return new Reply(status,text);
            } finally { c.disconnect(); }
        });
        Thread worker = new Thread(call, "power-http"); worker.setDaemon(true); worker.start();
        try { return call.get(8, TimeUnit.SECONDS); }
        catch (Exception e) { call.cancel(true); throw new IOException("request unavailable"); }
    }
    static final class Reply { final int status; final String body; Reply(int s,String b){status=s;body=b;} }
    static void secure(File file, boolean directory) throws Exception {
        StructStat stat = Os.lstat(file.getPath());
        if (stat.st_uid != 0 || (stat.st_mode & 0077) != 0
                || (stat.st_mode & 0170000) != (directory ? 0040000 : 0100000)) throw new IOException();
    }
    static String read(File file, int limit) throws Exception {
        secure(file,false); if(file.length()>limit) throw new IOException();
        return new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8);
    }
    static void write(File file,String value) throws Exception {
        File temp=File.createTempFile("power-", ".tmp",file.getParentFile()); Os.chmod(temp.getPath(),0600);
        try { Files.write(temp.toPath(),value.getBytes(StandardCharsets.UTF_8));
            Files.move(temp.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(temp.toPath()); }
    }
    static String readLine(BufferedReader in,int limit) throws IOException {
        StringBuilder value=new StringBuilder(); int c;
        while((c=in.read())!=-1 && c!='\n') { if(value.length()>=limit) throw new IOException(); value.append((char)c); }
        if(c==-1) throw new EOFException(); return value.toString();
    }
}
