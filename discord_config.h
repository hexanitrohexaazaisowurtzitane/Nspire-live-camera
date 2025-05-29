#ifndef DISCORD_CONFIG_H
#define DISCORD_CONFIG_H

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
//#include <FS.h>

const char* WIFI_SSID = "SSID_NAME";
const char* WIFI_PASSWORD = "PASSWORD";

const char* DISCORD_TOKEN = "YOUR_TOKEN";
const char* CHANNEL_ID = "CHANNEL_ID";
const char* DISCORD_API = "https://discord.com/api/v9";


bool connectToWiFi(int maxAttempts = 20) {
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int attempts = 0;
    
    while (WiFi.status() != WL_CONNECTED && attempts < maxAttempts) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("\nWiFi connected!");
        Serial.println("IP address: ");
        Serial.println(WiFi.localIP());
        return true;
    } else {
        Serial.println("\nWiFi connection failed!");
        return false;
    }
}


// todo
void sendDiscordImage(const String& base64Image) {
    return true
}

void sendDiscordMessage(const char* message) {
    return true
}

#endif // DISCORD_CONFIG_H
