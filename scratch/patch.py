import sys

file_path = r"c:\Users\ASUST\OneDrive\Documents\PlatformIO\Projects\Robotics\src\main.cpp"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Includes
content = content.replace("#include <WebServer.h>\n#include <WiFiUDP.h>", "#include <WebSocketsClient.h>\n#include <ArduinoJson.h>")

# 2. Remove multipart boundary stuff and add WebSocket config
old_http_stuff = """#define PART_BOUNDARY "123456789000000000000987654321"
static const char* _STREAM_CONTENT_TYPE = "multipart/x-mixed-replace;boundary=" PART_BOUNDARY;
static const char* _STREAM_BOUNDARY = "\\r\\n--" PART_BOUNDARY "\\r\\n";
static const char* _STREAM_PART = "Content-Type: image/jpeg\\r\\nContent-Length: %u\\r\\n\\r\\n";

httpd_handle_t stream_httpd = NULL;"""

new_ws_stuff = """// --- WEBSOCKET CLOUD RELAY ---
WebSocketsClient webSocket;
const char* WEBSOCKET_SERVER = "192.168.1.100"; // Default local testing, replace with cloud URL later
const uint16_t WEBSOCKET_PORT = 3000;
const char* WEBSOCKET_URL = "/";

bool cameraEnabled = true;
unsigned long lastFrameTime = 0;"""

content = content.replace(old_http_stuff, new_ws_stuff)

# 3. Replace stream_handler and startCameraServer
import re
content = re.sub(r'static esp_err_t stream_handler\(httpd_req_t \*req\) \{.*?\n\}\n\n', '', content, flags=re.DOTALL)
content = re.sub(r'void startCameraServer\(\) \{.*?\n\}\n\n', '', content, flags=re.DOTALL)

# 4. Wi-Fi Settings
content = content.replace('const char* WIFI_SSID = "Harshita_IRA";\nconst char* WIFI_PASSWORD = "Shivam21074";', 'const char* WIFI_SSID = "HGS_1_4G";\nconst char* WIFI_PASSWORD = "Shivam@5211";')

# 5. Remove WebServer and UDP declarations
content = re.sub(r'// WebServer & UDP Declarations\nWebServer server\(80\);\nWiFiUDP udp;\nconst unsigned int localUdpPort = 8888;\nchar incomingPacket\[255\];\n\n', '', content)

# 6. logToApp logic
old_log = """// Log Buffer for transmitting detailed logs to Cockpit App
String espLogs = "";
void logToApp(String msg) {
  Serial.println(msg);
  if (espLogs.length() > 3000) {
    espLogs = ""; // Clear to prevent buffer overflow
  }
  espLogs += "🤖 [ROBOT] " + msg + "\\n";
}"""

new_log = """// Log Buffer for transmitting detailed logs to Cockpit App
void logToApp(String msg) {
  Serial.println(msg);
  if (webSocket.isConnected()) {
    webSocket.sendTXT("🤖 [ROBOT] " + msg);
  }
}"""
content = content.replace(old_log, new_log)

# 7. Add webSocketEvent definition
ws_event_code = """
void webSocketEvent(WStype_t type, uint8_t * payload, size_t length) {
  if (type == WStype_CONNECTED) {
    logToApp("Connected to Cloud Relay!");
    webSocket.sendTXT("{\\"role\\":\\"robot\\"}");
  } else if (type == WStype_TEXT) {
    String text = (char*)payload;
    
    if (text == "camera_off") {
      cameraEnabled = false;
      logToApp("Camera turned OFF");
      return;
    } else if (text == "camera_on") {
      cameraEnabled = true;
      logToApp("Camera turned ON");
      return;
    } else if (text == "quality_vga") {
      sensor_t * s = esp_camera_sensor_get();
      s->set_framesize(s, FRAMESIZE_VGA);
      logToApp("Camera Quality -> VGA");
      return;
    } else if (text == "quality_uxga") {
      sensor_t * s = esp_camera_sensor_get();
      s->set_framesize(s, FRAMESIZE_UXGA);
      logToApp("Camera Quality -> UXGA");
      return;
    }

    if (text.startsWith("cmd:")) {
      String cmd = text.substring(4);
      if (cmd == "face_happy") { currentState = 1; stateTimer = 300; logToApp("Expression -> HAPPY"); }
      else if (cmd == "face_excited") { currentState = 4; stateTimer = 300; logToApp("Expression -> EXCITED (WINK)"); }
      else if (cmd == "face_shocked") { currentState = 2; stateTimer = 300; logToApp("Expression -> WONDER/SHOCKED"); }
      else if (cmd == "face_sad") { currentState = 3; stateTimer = 300; logToApp("Expression -> SLEEPY/SAD"); }
      else if (cmd == "horn") { logToApp("Chirping Horn!"); LED_RGB.setPixelColor(0, LED_RGB.Color(255, 255, 255)); LED_RGB.show(); delay(100); }
      else if (cmd == "action_wave") { currentState = 5; stateTimer = 150; logToApp("Action -> WAVE"); }
      else if (cmd == "action_rock") { currentState = 6; stateTimer = 150; logToApp("Action -> ROCK"); }
      else if (cmd == "action_paper") { currentState = 7; stateTimer = 150; logToApp("Action -> PAPER"); }
      else if (cmd == "action_scissors") { currentState = 8; stateTimer = 150; logToApp("Action -> SCISSORS"); }
      else if (cmd == "face_angry") { currentState = 9; stateTimer = 300; logToApp("Expression -> ANGRY"); }
      else if (cmd == "face_love") { currentState = 10; stateTimer = 300; logToApp("Expression -> LOVE"); }
      else if (cmd == "face_dizzy") { currentState = 11; stateTimer = 300; logToApp("Expression -> DIZZY"); }
      return;
    }

    int mIdx = text.indexOf("M:");
    int gIdx = text.indexOf(";G:");
    int hIdx = text.indexOf(";H:");
    int sIdx = text.indexOf(";S:");

    if (mIdx != -1) {
      int commaIdx = text.indexOf(",", mIdx);
      if (commaIdx != -1 && (gIdx == -1 || commaIdx < gIdx)) {
        String turnStr = text.substring(mIdx + 2, commaIdx);
        String speedStr = text.substring(commaIdx + 1, gIdx != -1 ? gIdx : text.length());
        float turn = turnStr.toFloat();
        float speed = speedStr.toFloat();
        driveMotors(speed, turn);
        
        static float lastSpeed = 0;
        static float lastTurn = 0;
        if (abs(speed - lastSpeed) > 0.15 || abs(turn - lastTurn) > 0.15) {
          char formattedDrive[80];
          snprintf(formattedDrive, sizeof(formattedDrive), "Steer Vector -> Speed: %.2f, Turn: %.2f", speed, turn);
          logToApp(formattedDrive);
          lastSpeed = speed;
          lastTurn = turn;
        }
      }
    }
    
    if (hIdx != -1) {
      int hVal = text.substring(hIdx + 3, hIdx + 4).toInt();
      static int lastHVal = -1;
      if (hVal != lastHVal) {
        logToApp(String("Headlights Command: ") + (hVal == 1 ? "ON" : "OFF"));
        lastHVal = hVal;
      }
      if (hVal == 1 && currentState == 0) {
        currentState = 4;
        stateTimer = 60;
      }
    }
    
    if (sIdx != -1) {
      int sVal = text.substring(sIdx + 3, sIdx + 4).toInt();
      static int lastSVal = -1;
      if (sVal != lastSVal) {
        logToApp(String("Siren Flashing Command: ") + (sVal == 1 ? "ON" : "OFF"));
        lastSVal = sVal;
      }
      if (sVal == 1 && currentState == 0) {
        currentState = 1;
        stateTimer = 90;
      }
    }
  }
}
"""
content = content.replace("void setup() {", ws_event_code + "\nvoid setup() {")

# 8. Setup function modifications
setup_old = """  // Prevent old Wi-Fi settings from being read/cached in NVS memory
  WiFi.persistent(false);
  WiFi.disconnect(true);      // Clear station cache
  WiFi.softAPdisconnect(true);  // Clear softAP NVS cache
  delay(100);

  // Configure a permanent static IP for the Access Point
  IPAddress local_IP(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  
  WiFi.mode(WIFI_AP); // Configure as a robust standalone Access Point
  WiFi.softAPConfig(local_IP, gateway, subnet);
  
  // Start the Access Point with SSID and password defined at top
  WiFi.softAP(WIFI_SSID, WIFI_PASSWORD);
  
  logToApp("Wi-Fi Access Point online.");
  logToApp("SSID: " + String(WIFI_SSID));
  logToApp("Static IP Address: " + WiFi.softAPIP().toString());"""

setup_new = """  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\\nConnected to Wi-Fi!");
  logToApp("Connected to Wi-Fi! IP: " + WiFi.localIP().toString());"""
content = content.replace(setup_old, setup_new)

# 9. Setup - Replace HTTP server and UDP with WebSocket begin
server_start_old = r'  // Set up HTTP Endpoints for App Cockpit\n.*?startCameraServer\(\);\n'
server_start_new = """  // Initialize WebSocket Client
  webSocket.begin(WEBSOCKET_SERVER, WEBSOCKET_PORT, WEBSOCKET_URL);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(5000);
  logToApp("WebSocket Client Started");
"""
content = re.sub(server_start_old, server_start_new, content, flags=re.DOTALL)

# 10. Loop - Remove HTTP handle and UDP, add WebSocket loop and camera streaming
loop_old = r'void loop\(\) \{\n.*?  // --- 1\. MOTION MATH \(Breathing & Gazing\) ---'
loop_new = """void loop() {
  webSocket.loop();

  if (cameraEnabled) {
    // Only capture and send frames at max ~15fps to conserve bandwidth and CPU
    if (millis() - lastFrameTime > 66) {
      camera_fb_t * fb = esp_camera_fb_get();
      if (fb) {
        webSocket.sendBIN(fb->buf, fb->len);
        esp_camera_fb_return(fb);
      }
      lastFrameTime = millis();
    }
  }

  // --- 1. MOTION MATH (Breathing & Gazing) ---"""
content = re.sub(loop_old, loop_new, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Patch applied successfully.")
