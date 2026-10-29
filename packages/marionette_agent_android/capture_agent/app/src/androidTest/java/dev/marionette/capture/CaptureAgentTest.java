package dev.marionette.capture;

import android.hardware.display.DisplayManager;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.Display;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;
import java.io.*;
import java.net.*;
import org.json.*;
import org.junit.Test;

/** Device-side test runner. Only UiDevice takes pixels; the socket carries them. */
public final class CaptureAgentTest {
    private static void send(DataOutputStream output, JSONObject value) throws Exception {
        byte[] bytes = value.toString().getBytes("UTF-8");
        output.writeInt(bytes.length);
        output.write(bytes);
        output.flush();
    }

    private static JSONObject receive(DataInputStream input) throws Exception {
        int length = input.readInt();
        if (length < 2 || length > 8192) throw new IOException("Invalid frame");
        byte[] bytes = new byte[length]; input.readFully(bytes);
        return new JSONObject(new String(bytes, "UTF-8"));
    }
    private static String proof(String token, String message) throws Exception {
        byte[] key = new byte[32];
        for (int i=0;i<key.length;i++) key[i]=(byte)Integer.parseInt(token.substring(i*2,i*2+2),16);
        javax.crypto.Mac mac = javax.crypto.Mac.getInstance("HmacSHA256");
        mac.init(new javax.crypto.spec.SecretKeySpec(key, "HmacSHA256"));
        StringBuilder hex = new StringBuilder();
        for (byte value : mac.doFinal(message.getBytes("UTF-8"))) hex.append(String.format("%02x", value & 255));
        return hex.toString();
    }

    @Test public void serveCaptures() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        String identity = args.getString("captureDevice", "");
        String token = args.getString("captureToken", "");
        int port = Integer.parseInt(args.getString("capturePort", "0"));
        if (!identity.matches("[A-Za-z0-9][A-Za-z0-9_-]{0,63}") ||
                !token.matches("[a-f0-9]{64}") || port < 1024 || port > 65535) {
            throw new IllegalArgumentException("Private capture pairing arguments required");
        }
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        DisplayManager displays = (DisplayManager) InstrumentationRegistry.getInstrumentation()
                .getContext().getSystemService(android.content.Context.DISPLAY_SERVICE);
        long end = SystemClock.elapsedRealtime() + 30 * 60 * 1000;
        while (SystemClock.elapsedRealtime() < end) {
            Socket socket = new Socket();
            try {
                socket.connect(new InetSocketAddress("10.0.2.2", port), 500);
            } catch (IOException unavailable) {
                socket.close();
                SystemClock.sleep(200);
                continue; // Read-only pairing wait, never replay capture/UI requests.
            }
            try (Socket owned = socket) {
                owned.setSoTimeout(10000);
                DataInputStream input = new DataInputStream(owned.getInputStream());
                DataOutputStream output = new DataOutputStream(owned.getOutputStream());
                JSONObject challenge = receive(input);
                String nonce = challenge.optString("nonce");
                if (challenge.optInt("version") != 1 || !nonce.matches("[a-f0-9]{64}")) continue;
                JSONArray ids = new JSONArray();
                for (Display display : displays.getDisplays()) ids.put(display.getDisplayId());
                send(output, new JSONObject().put("version", 1).put("device", identity)
                        .put("proof", proof(token, "agent:" + nonce)).put("displays", ids)
                        .put("emulator", Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish")));
                JSONObject request = receive(input);
                String command = request.optString("command");
                if (request.optInt("version") != 1 || !java.security.MessageDigest.isEqual(
                        proof(token, "host:" + nonce + ":" + command).getBytes("UTF-8"),
                        request.optString("proof").getBytes("UTF-8"))) continue;
                if (request.optString("command").equals("stop")) {
                    send(output, new JSONObject().put("ok", true));
                    return;
                }
                if (!request.optString("command").equals("capture")) continue;
                if (ids.length() != 1 || ids.getInt(0) != 0) {
                    send(output, new JSONObject().put("ok", false).put("code", "UNSUPPORTED_CAPABILITY"));
                    continue;
                }
                File file = File.createTempFile("capture-", ".png",
                        InstrumentationRegistry.getInstrumentation().getTargetContext().getCacheDir());
                try {
                    // Direct AndroidX UI Automator API; no shell execution.
                    if (!device.takeScreenshot(file) || file.length() < 1 || file.length() > 32 * 1024 * 1024) {
                        send(output, new JSONObject().put("ok", false).put("code", "IO_ERROR"));
                        continue;
                    }
                    byte[] image = java.nio.file.Files.readAllBytes(file.toPath());
                    send(output, new JSONObject().put("ok", true).put("length", image.length));
                    output.write(image);
                    output.flush();
                } finally { file.delete(); }
            } catch (IOException disconnected) {
                // No retry of a received capture. A subsequent connection is a new host request.
            }
        }
    }
}
