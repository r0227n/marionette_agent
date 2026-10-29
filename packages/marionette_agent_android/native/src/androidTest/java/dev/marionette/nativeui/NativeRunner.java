package dev.marionette.nativeui;

import android.graphics.Rect;
import android.os.Bundle;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.Configurator;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import java.io.ByteArrayOutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

/** Direct UI Automator calls, serialized on the instrumentation thread. */
public final class NativeRunner {
    @Test public void serve() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        String token = args.getString("token", "");
        String identity = args.getString("device", "");
        int port = Integer.parseInt(args.getString("port", "0"));
        if (!token.matches("[A-Za-z0-9_-]{32,128}") || identity.isEmpty() || port < 1 || port > 65535) {
            throw new IllegalArgumentException("Invalid native runner configuration");
        }
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        Configurator.getInstance().setWaitForIdleTimeout(1000).setWaitForSelectorTimeout(0);
        try (ServerSocket server = new ServerSocket(port, 4, InetAddress.getByName("127.0.0.1"))) {
            while (!Thread.currentThread().isInterrupted()) {
                try (Socket client = server.accept()) {
                    client.setSoTimeout(2000);
                    JSONObject reply = new JSONObject().put("version", 1).put("platform", "android")
                        .put("device", identity).put("ok", false);
                    try {
                        JSONObject request = readRequest(client);
                        if (!token.equals(request.getString("token")) || !identity.equals(request.getString("device"))
                                || !"android".equals(request.getString("platform")) || request.getInt("version") != 1) {
                            throw new IllegalArgumentException();
                        }
                        checkDeadline(request);
                        switch (request.getString("action")) {
                            case "snapshot":
                                JSONArray rows = new JSONArray();
                                for (UiObject2 root : device.findObjects(By.depth(0))) flatten(root, rows);
                                checkDeadline(request);
                                reply.put("elements", rows);
                                break;
                            case "tap":
                                int x = coordinate(request, "x"), y = coordinate(request, "y");
                                checkDeadline(request);
                                if (!device.click(x, y)) throw new IllegalStateException();
                                break;
                            case "swipe":
                                int sx = coordinate(request, "startX"), sy = coordinate(request, "startY");
                                int ex = coordinate(request, "endX"), ey = coordinate(request, "endY");
                                if (sx == ex && sy == ey) throw new IllegalArgumentException();
                                checkDeadline(request);
                                if (!device.swipe(sx, sy, ex, ey, 60)) throw new IllegalStateException();
                                break;
                            default: throw new IllegalArgumentException();
                        }
                        reply.put("ok", true);
                    } catch (Expired e) {
                        reply.put("code", "TIMEOUT");
                    } catch (IllegalArgumentException e) {
                        reply.put("code", "INVALID_ARGUMENT");
                    } catch (Exception e) {
                        reply.put("code", "BACKEND_ERROR");
                    }
                    byte[] output = (reply.toString() + "\n").getBytes(StandardCharsets.UTF_8);
                    if (output.length <= 8 * 1024 * 1024) client.getOutputStream().write(output);
                } catch (java.io.IOException ignored) {
                    // A disconnected caller never causes replay of its operation.
                }
            }
        }
    }

    private static JSONObject readRequest(Socket socket) throws Exception {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        while (buffer.size() < 16384) {
            int value = socket.getInputStream().read();
            if (value < 0) throw new java.io.EOFException();
            if (value == 10) return new JSONObject(buffer.toString("UTF-8"));
            buffer.write(value);
        }
        throw new IllegalArgumentException();
    }
    private static void checkDeadline(JSONObject request) throws Exception {
        if (System.currentTimeMillis() >= request.getLong("deadline")) throw new Expired();
    }
    private static int coordinate(JSONObject request, String key) throws Exception {
        double value = request.getDouble(key);
        if (!Double.isFinite(value) || value < 0 || value > 10000000) throw new IllegalArgumentException();
        return (int) Math.round(value);
    }
    private static void flatten(UiObject2 node, JSONArray rows) throws Exception {
        if (rows.length() >= 10000) throw new IllegalStateException();
        Rect bounds = node.getVisibleBounds();
        String description = node.getContentDescription(), text = node.getText();
        rows.put(new JSONObject().put("type", node.getClassName())
            .put("text", text == null || text.isEmpty() ? nullable(description) : text)
            .put("identifier", nullable(node.getResourceName())).put("value", nullable(description))
            .put("package", nullable(node.getApplicationPackage())).put("enabled", node.isEnabled())
            .put("bounds", new JSONObject().put("x", bounds.left).put("y", bounds.top)
                .put("width", bounds.width()).put("height", bounds.height())));
        for (UiObject2 child : node.getChildren()) flatten(child, rows);
    }
    private static Object nullable(String value) { return value == null ? JSONObject.NULL : value; }
    private static final class Expired extends Exception {}
}
