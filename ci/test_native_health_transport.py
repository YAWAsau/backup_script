"""Exercise actual health HTTP framing, EOF handling and bounded event sizes."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SDK = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'AppData/Local/Android/Sdk')))
JAVA = r'''
package io.github.yawasau.speedbackup.webview;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.ArrayList;
public class HealthTransportTest {
    public static void main(String[] args) throws Exception {
        for (int size : new int[]{6000, 17000}) {
            String event = "{\"payload\":\"" + "x".repeat(size) + "\"}";
            String token = "a".repeat(64);
            HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/api/remote-health", exchange -> {
                if (!token.equals(exchange.getRequestHeaders().getFirst("X-SpeedBackup-Token"))) {
                    exchange.sendResponseHeaders(401, -1); exchange.close(); return;
                }
                byte[] data = (event + "\n").getBytes(StandardCharsets.UTF_8);
                exchange.sendResponseHeaders(200, data.length);
                try (var output = exchange.getResponseBody()) { output.write(data); }
            });
            server.start();
            var received = new ArrayList<String>();
            try (var api = new NativeApi("http://127.0.0.1:" + server.getAddress().getPort() + "/#" + token)) {
                try { api.remoteHealth(received::add); throw new AssertionError("EOF must invalidate health"); }
                catch (IOException error) {
                    String expected = size < 16000 ? "Health stream closed" : "Health event too large";
                    if (!expected.equals(error.getMessage())) throw new AssertionError(error);
                }
                if (size < 16000) {
                    if (received.size() != 1 || !event.equals(received.get(0))) throw new AssertionError("event truncated");
                } else if (!received.isEmpty()) throw new AssertionError("oversized event delivered");
            } finally { server.stop(0); }
        }
        System.out.println("PASS: 6 KB health event delivered; EOF invalidates; 17 KB rejected");
    }
}
'''

with tempfile.TemporaryDirectory(prefix='sb-health-transport-') as directory:
    work = Path(directory)
    test = work / 'HealthTransportTest.java'
    test.write_text(JAVA, encoding='utf-8')
    jar = SDK / 'platforms/android-36/android.jar'
    subprocess.run([shutil.which('javac'), '-encoding', 'UTF-8', '-cp', str(jar), '-d', str(work),
                    str(ROOT / 'webview/app/src/main/java/NativeApi.java'), str(test)], check=True)
    subprocess.run([shutil.which('java'), '-cp', str(work),
                    'io.github.yawasau.speedbackup.webview.HealthTransportTest'], check=True)
