#include "esp_camera.h"
#include "Arduino.h"
#include <string>
#include <vector>
#include <cstdlib>
#include "discord_config.h"
#include "base64.h"
#include "img_converters.h"
#include "fb_gfx.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "esp_system.h"

// Pin definitions
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

#define TARGET_SIZE 51 //60 //70
//#define CHUNK_SIZE 250 //500 //1024

/*
Hello :)
Good luck reading my code.
============================================================
This script is a real-time image capture and compression 
system that converts camera feed into pixelated ASCII art 
for display on the TI Nspire CX
============================================================
What it does:
* Real time video stream with custom compression
* color quantization (36 colors) with weighting
* RGB565->RGB888 color space conversion
* color match + RLE encoding
* Huffman compression with few data loss
* Base64 encoding for transmission

Todo:
* Support for single picute + snap at end of stream
* Support for discord api with picture sending 
* Support for math/physics LLM api for question solving
============================================================
Tested on:
* ESP32-CAM module, Ai Thinker ESP32-CAM Board
* RHYX-M21-45 cam (or OV2640, will need adjustments)

Wires on the video/page:
[CP21 : cp2102 USB to UART adapter]
(computer) USB-A      ->  (esp)   5V, GND       (direct 5v, npire only goes to 3.3v)
(nspire)   USB-B      ->  (cp21)  [Usb-A port]  (Using usb-b to usb-a adapter)
(cp21)     Rx,Tx,GND  ->  (esp)   Tx,Rx,GND     
============================================================
Commands:
* STREAM  : Begin streaming service
* STOP    : Stop streaming service (may take a while if sent by nspire)
* PIC     : Capture single higher res picture
* FLASH   : Toggle flash
* fd+/fd- : (debug) adjust delay between frames
* cd+/cd- : (debug) adjust delay between chunks
* cz+/cz- : (debug) adjust chunk size
* NOTE: Mess around with the debug adjust features for better preformance
============================================================
Libs:
* ArduinoJson        | 7.4.1   | Benoit Blanchon
* EspSoftwareSerial  | 8.1.0   | Dirk Kaar
* JPEGENC            | 1.1.0   | Larry Bank


*/

struct RGB888 {
  uint8_t r, g, b;
};

struct Color {
  uint8_t r;
  uint8_t g;
  uint8_t b;
  char symbol;
};

typedef struct Node {
    char character;
    unsigned frequency;
    struct Node *left, *right;
} Node;

typedef struct MinHeap {
    unsigned size;
    unsigned capacity;
    Node** array;
} MinHeap;


static char* huffmanCodes[256] = {NULL};
static int huffCodeArr[100];
static char binaryString[TARGET_SIZE * TARGET_SIZE * 8]; // bad
static char serializedTree[TARGET_SIZE * TARGET_SIZE * 2]; // also bad

bool  rgb565_to_jpg(uint8_t* rgb_buffer, size_t rgb_len, uint8_t** jpg_buffer, size_t* jpg_len, int width, int height);
Node* buildHuffmanTree(const char* data, size_t size);
void  getCodes(Node* root, int arr[], int top);
char* binaryToBase64(const char* binary, size_t binaryLen, size_t* outputLen);
void  serializeHelper(Node* node, char* serialized, size_t* treeSize);
char* compressString(const char* input, size_t* outputSize);

inline RGB888 convertRGB565toRGB888(uint16_t pixel) {
  // invert
  pixel = ((pixel & 0xFF) << 8) | (pixel >> 8);
    
  uint16_t R = pixel & 0b1111100000000000;
  uint16_t G = pixel & 0b0000011111100000;
  uint16_t B = pixel & 0b0000000000011111;
    
  RGB888 rgb;
  // saturation boost
  rgb.r = (uint8_t)min(255, ((R >> 8) * 120) / 100);
  rgb.g = (uint8_t)min(255, ((G >> 3) * 110) / 100);
  rgb.b = (uint8_t)min(255, ((B << 3) * 120) / 100);
    
  return rgb;
}

const PROGMEM Color palette[] = {
  { 255, 255, 255, 'A' },  { 0, 0, 0, 'B' },        { 255, 0, 0, 'C' },      { 0, 255, 0, 'D' },
  { 0, 0, 255, 'E' },      { 255, 255, 0, 'F' },    { 0, 255, 255, 'G' },    { 255, 0, 255, 'H' },
  { 255, 165, 0, 'I' },    { 255, 192, 203, 'J' },  { 128, 0, 128, 'a' },    { 165, 42, 42, 'b' },
  { 128, 128, 128, 'c' },  { 0, 255, 0, 'd' },      { 173, 216, 230, 'e' },  { 0, 128, 128, 'f' }, 
  { 0, 0, 128, 'g' },      { 128, 0, 0, 'h' },      { 128, 128, 0, 'i' },    { 255, 215, 0, 'j' }, 
  { 255, 127, 80, 'k' },   { 250, 128, 114, 'l' },  { 75, 0, 130, 'm' },     { 238, 130, 238, 'n' }, 
  { 64, 224, 208, 'o' },   { 220, 20, 60, 'p' },    { 255, 218, 185, 'q' },  { 230, 230, 250, 'r' }, 
  { 189, 252, 201, 's' },  { 245, 245, 220, 't' },  { 240, 230, 140, 'u' },  { 192, 192, 192, 'v' },
  { 210, 105, 30, 'w' },   { 0, 191, 255, 'x' },    { 34, 139, 34, 'y' },    { 64, 64, 64, 'z' }
};

const int PALETTE_SIZE = sizeof(palette) / sizeof(palette[0]);

bool streaming = false;
unsigned long frameDelay = 200;  // 270;  // 300
unsigned long chunkDelay = 50;  // 200;  // 280
bool camera_initialized = false;

unsigned long CHUNK_SIZE = 400;  //400;   // 250

// lookup tables 4 color matching
uint32_t colorDistanceLUT[256][256][256];
char closestColorLUT[16][16][16];
bool lutInitialized = false;

void initColorLUT() {
  if (lutInitialized) return;
  
  // coarser grid 16^3
  for (int r = 0; r < 16; r++) {
    for (int g = 0; g < 16; g++) {
      for (int b = 0; b < 16; b++) {
        uint8_t r_scaled = r * 17;
        uint8_t g_scaled = g * 17;
        uint8_t b_scaled = b * 17;
        
        uint32_t minDistance = 0xFFFFFFFF;
        char bestMatch = 'A';

        for (int i = 0; i < PALETTE_SIZE; i++) {
          Color color;
          memcpy_P(&color, &palette[i], sizeof(Color));
          
          // weight colors differently to prevent greys
          // adjust this depending on your camera!
          // tested on RHYX-M21-45 for esp32cam
          const uint32_t rw = 100;
          const uint32_t gw = 80;
          const uint32_t bw = 100;

          int32_t dr = ((int32_t)r_scaled - color.r);
          int32_t dg = ((int32_t)g_scaled - color.g);
          int32_t db = ((int32_t)b_scaled - color.b);

          uint32_t distance = (dr * dr * rw + dg * dg * gw + db * db * bw) / 100;
          
          if (distance < minDistance) {
            minDistance = distance;
            bestMatch = color.symbol;
          }
        }
        
        closestColorLUT[r][g][b] = bestMatch;
      }
    }
  }
  
  lutInitialized = true;
}

// LUT color
inline char findClosestColor(uint8_t r, uint8_t g, uint8_t b) {
  uint8_t r_idx = r >> 4;
  uint8_t g_idx = g >> 4;
  uint8_t b_idx = b >> 4;
  
  return closestColorLUT[r_idx][g_idx][b_idx];
}

// RLE encoding
String encodeRLE(const String& input) {
    if (input.length() == 0) return "";
    
    String output;
    output.reserve(input.length());
    
    int count = 1;
    char current = input[0];
    
    for (size_t i = 1; i < input.length(); i++) {
        if (input[i] == current) {
            count++;
        } else {
            if (count > 4) {
                output += "%" + String(count) + current + "%";
            } else {
                // no encoding
                for (int j = 0; j < count; j++) {
                    output += current;
                }
            }
            current = input[i];
            count = 1;
        }
    }
    
    if (count > 4) {
        output += "%" + String(count) + current + "%";
    } else {
        for (int j = 0; j < count; j++) {
            output += current;
        }
    }
    
    return output;
}

// convert to JPEG
bool rgb565_to_jpg(uint8_t* rgb_buffer, size_t rgb_len, uint8_t** jpg_buffer, size_t* jpg_len, int width, int height) {
    return fmt2jpg(rgb_buffer, rgb_len, width, height, PIXFORMAT_RGB565, 80, jpg_buffer, jpg_len);
}

esp_err_t initialize_camera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.frame_size = FRAMESIZE_VGA;
  config.pixel_format = PIXFORMAT_RGB565;
  config.fb_count = 1;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    return err;
  }

  sensor_t* s = esp_camera_sensor_get();
  if (s) {
    s->set_brightness(s, 2);
    s->set_contrast(s, 1);
    s->set_saturation(s, 3);
    s->set_awb_gain(s, 1);
    s->set_exposure_ctrl(s, 1);
    s->set_aec2(s, 0);
    s->set_ae_level(s, 1);
    s->set_agc_gain(s, 1);
    s->set_bpc(s, 0);
    s->set_wpc(s, 0);
    s->set_raw_gma(s, 1);
    s->set_lenc(s, 1);
    s->set_dcw(s, 0);
  }

  Serial.println("Camera initialized!");
  return ESP_OK;
}

// Huffman stuff, dont really know whats goes on here tbh
Node* createNode(char character, unsigned frequency) {
    Node* temp = (Node*)malloc(sizeof(Node));
    temp->left = temp->right = NULL;
    temp->character = character;
    temp->frequency = frequency;
    return temp;
}

MinHeap* createMinHeap(unsigned capacity) {
    MinHeap* minHeap = (MinHeap*)malloc(sizeof(MinHeap));
    minHeap->size = 0;
    minHeap->capacity = capacity;
    minHeap->array = (Node**)malloc(minHeap->capacity * sizeof(Node*));
    return minHeap;
}

void swapNodes(Node** a, Node** b) {
    Node* t = *a;
    *a = *b;
    *b = t;
}

void minHeapify(MinHeap* minHeap, int idx) {
    int smallest = idx;
    int left = 2 * idx + 1;
    int right = 2 * idx + 2;

    if (left < minHeap->size && minHeap->array[left]->frequency < minHeap->array[smallest]->frequency)
        smallest = left;

    if (right < minHeap->size && minHeap->array[right]->frequency < minHeap->array[smallest]->frequency)
        smallest = right;

    if (smallest != idx) {
        swapNodes(&minHeap->array[smallest], &minHeap->array[idx]);
        minHeapify(minHeap, smallest);
    }
}

int isSizeOne(MinHeap* minHeap) {
    return (minHeap->size == 1);
}

Node* extractMin(MinHeap* minHeap) {
    Node* temp = minHeap->array[0];
    minHeap->array[0] = minHeap->array[minHeap->size - 1];
    --minHeap->size;
    minHeapify(minHeap, 0);
    return temp;
}

void insertMinHeap(MinHeap* minHeap, Node* minHeapNode) {
    ++minHeap->size;
    int i = minHeap->size - 1;
    while (i && minHeapNode->frequency < minHeap->array[(i - 1) / 2]->frequency) {
        minHeap->array[i] = minHeap->array[(i - 1) / 2];
        i = (i - 1) / 2;
    }
    minHeap->array[i] = minHeapNode;
}

void buildMinHeap(MinHeap* minHeap) {
    int n = minHeap->size - 1;
    for (int i = (n - 1) / 2; i >= 0; --i)
        minHeapify(minHeap, i);
}

MinHeap* createAndBuildMinHeap(const char* data, size_t size) {
    unsigned frequency[256] = {0};
    
    // count char frequencies
    for (size_t i = 0; i < size; ++i)
        ++frequency[(unsigned char)data[i]];

    // count distinct chars
    int uniqueChars = 0;
    for (int i = 0; i < 256; ++i)
        if (frequency[i] > 0)
            ++uniqueChars;

    MinHeap* minHeap = createMinHeap(uniqueChars);

    for (int i = 0; i < 256; ++i) {
        if (frequency[i] > 0) {
            minHeap->array[minHeap->size] = createNode(i, frequency[i]);
            ++minHeap->size;
        }
    }

    buildMinHeap(minHeap);
    return minHeap;
}

Node* buildHuffmanTree(const char* data, size_t size) {
    Node *left, *right, *top;
    MinHeap* minHeap = createAndBuildMinHeap(data, size);

    while (!isSizeOne(minHeap)) {
        left = extractMin(minHeap);
        right = extractMin(minHeap);

        top = createNode('$', left->frequency + right->frequency);
        top->left = left;
        top->right = right;
        insertMinHeap(minHeap, top);
    }

    return extractMin(minHeap);
}

void getCodes(Node* root, int arr[], int top) {
    if (root->left) {
        arr[top] = 0;
        getCodes(root->left, arr, top + 1);
    }

    if (root->right) {
        arr[top] = 1;
        getCodes(root->right, arr, top + 1);
    }

    if (!root->left && !root->right) {
        char* code = (char*)malloc(top + 1);
        for (int i = 0; i < top; ++i)
            code[i] = arr[i] + '0';
        code[top] = '\0';
        huffmanCodes[(unsigned char)root->character] = code;
    }
}

void generateHuffmanCodes(Node* root) {
    for (int i = 0; i < 256; ++i) {
        if (huffmanCodes[i]) {
            free(huffmanCodes[i]);
            huffmanCodes[i] = NULL;
        }
    }
    
    int top = 0;
    getCodes(root, huffCodeArr, top);
}

void countNodesHelper(Node* node, int& count) {
    if (node) {
        count++;
        countNodesHelper(node->left, count);
        countNodesHelper(node->right, count);
    }
}

void serializeHelper(Node* node, char* serialized, size_t* treeSize) {
    if (node) {
        if (!node->left && !node->right) {
            serialized[(*treeSize)++] = 'L';
            serialized[(*treeSize)++] = node->character;
        } else {
            serialized[(*treeSize)++] = 'I';
            serializeHelper(node->left, serialized, treeSize);
            serializeHelper(node->right, serialized, treeSize);
        }
    }
}

char* binaryToBase64(const char* binary, size_t binaryLen, size_t* outputLen) {
    const char* base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t outputSize = (binaryLen + 5) / 6; // 6 bits -> 1 base64 char, very nice
    char* output = (char*)malloc(outputSize + 1);
    *outputLen = outputSize;
    
    for (size_t i = 0, j = 0; i < binaryLen; i += 6, j++) {
        int value = 0;
        int bits = 0;
        for (int k = 0; k < 6 && i + k < binaryLen; k++) {
            value = (value << 1) | (binary[i + k] - '0');
            bits++;
        }
        // shift left for missing bits
        value <<= (6 - bits);
        output[j] = base64Chars[value];
    }
    output[*outputLen] = '\0';
    return output;
}

char* compressString(const char* input, size_t* outputSize) {
    size_t inputLength = strlen(input);
    
    // built tree nd nodes
    Node* root = buildHuffmanTree(input, inputLength);
    generateHuffmanCodes(root);
    
    size_t binarySize = 0;
    for (size_t i = 0; i < inputLength; i++) {
        unsigned char ch = input[i];
        if (huffmanCodes[ch]) {
            size_t codeLen = strlen(huffmanCodes[ch]);
            memcpy(binaryString + binarySize, huffmanCodes[ch], codeLen);
            binarySize += codeLen;
        }
    }
    binaryString[binarySize] = '\0';
    
    size_t treeSize = 0;
    serializeHelper(root, serializedTree, &treeSize);
    serializedTree[treeSize] = '\0';
    
    // binary -> Base64 encode
    size_t encodedSize;
    char* encoded = binaryToBase64(binaryString, binarySize, &encodedSize);
    
    // [Original Length][Tree Size][Serialized Tree][Encoded Data]
    char lengthStr[20], treeSizeStr[20];
    sprintf(lengthStr, "%zu", inputLength);
    sprintf(treeSizeStr, "%zu", treeSize);
    
    size_t headerSize = strlen(lengthStr) + 1 + strlen(treeSizeStr) + 1;
    *outputSize = headerSize + treeSize + encodedSize;
    
    char* output = (char*)malloc(*outputSize + 1);
    sprintf(output, "%s,%s,", lengthStr, treeSizeStr);
    memcpy(output + headerSize, serializedTree, treeSize);
    memcpy(output + headerSize + treeSize, encoded, encodedSize);
    output[*outputSize] = '\0';
    
    free(encoded);
    
    return output;
}

void stop_camera() {
  if (camera_initialized) {
    esp_camera_deinit();
    camera_initialized = false;
    Serial.println("Camera stopped");
  }
}

void captureAndSendPicture(int size, bool sendJpeg) {
  if (!camera_initialized) {
    esp_err_t err = initialize_camera();
    if (err != ESP_OK) {
      Serial.println("Failed to initialize camera for picture");
      return;
    }
    camera_initialized = true;
  }

  if (!lutInitialized) {
    initColorLUT();
  }

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Camera capture failed");
    return;
  }
  // does not work yet! disabled for now
  /*
  if (sendJpeg) {
    uint8_t* jpg_buf = NULL;
    size_t jpg_len = 0;
    
    // does not work yet! disabled for now
    if (rgb565_to_jpg(fb->buf, fb->len, &jpg_buf, &jpg_len, fb->width, fb->height)) {
      String base64Image = base64::encode(jpg_buf, jpg_len);
      free(jpg_buf);
      sendDiscordImage(base64Image);
    } else {
      String base64Image = base64::encode(fb->buf, fb->len);
      sendDiscordImage(base64Image);
    }
  }
  */

  // pixel art thingy
  uint16_t* buffer = (uint16_t*)fb->buf;
  int src_width = fb->width;
  int src_height = fb->height;

  int crop_size = min(src_width, src_height);
  int crop_x = (src_width - crop_size) / 2;
  int crop_y = (src_height - crop_size) / 2;

  int block_w = crop_size / size;
  int block_h = crop_size / size;

  String result;
  result.reserve(size * size);

  for (int y = 0; y < size; y++) {
    int src_y_base = crop_y + (y * block_h);
    
    for (int x = 0; x < size; x++) {
      int src_x_base = crop_x + (x * block_w);
      
      // average pixels
      uint32_t r_sum = 0, g_sum = 0, b_sum = 0;
      int valid_pixels = 0;
      
      // sparser grid (every 2nd pixel)
      for (int by = 0; by < block_h; by += 2) {
        int src_y = src_y_base + by;
        if (src_y >= src_height) continue;
        
        int row_offset = src_y * src_width;
        
        for (int bx = 0; bx < block_w; bx += 2) {
          int src_x = src_x_base + bx;
          if (src_x >= src_width) continue;
          
          int pos = row_offset + src_x;
          uint16_t pixel = buffer[pos];
          
          RGB888 rgb = convertRGB565toRGB888(pixel);
          r_sum += rgb.r;
          g_sum += rgb.g;
          b_sum += rgb.b;
          valid_pixels++;
        }
      }
      
      if (valid_pixels > 0) {
        uint8_t r = r_sum / valid_pixels;
        uint8_t g = g_sum / valid_pixels;
        uint8_t b = b_sum / valid_pixels;
        
        result += findClosestColor(r, g, b);
      } else {
        result += 'A';
      }
    }
  }

  //Serial.print("Raw Pixel Data:");
  //Serial.println(result);

  size_t compressedSize;
  char* compressed = compressString(result.c_str(), &compressedSize);
  String compressedString = String(compressed);
  //Serial.print("rAW Compressed String:");
  //Serial.println(compressedString);
  compressedString = encodeRLE(compressedString);

  //Serial.print("Compressed String:");
  //Serial.println(compressedString);

  
  Serial.println("\nSTART_IMAGE\n");
  for(unsigned int i = 0; i < compressedString.length(); i += CHUNK_SIZE) {
    Serial.println(compressedString.substring(i, i + CHUNK_SIZE));
    delay(chunkDelay);
  }
  Serial.println("\nEND_IMAGE\n");

  esp_camera_fb_return(fb);
  free(compressed);
}

void setup() {
  Serial.begin(115200);
  
  // must disable brownout detector
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  pinMode(4, OUTPUT);
  
  while (!connectToWiFi()) {
    Serial.print(".");
    delay(1000);
  }
  
  initColorLUT();
  
  Serial.println("Setup complete - ready for commands");
}

void loop() {
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    if (command) {
      Serial.print("Recieved: ");
      Serial.print(command);
    }
    if (command == "STREAM") {
      Serial.println("Attempting to begin stream...");
      if (!camera_initialized) {
        esp_err_t err = initialize_camera();
        if (err == ESP_OK) {
          camera_initialized = true;
          streaming = true;
          Serial.println("Streaming started");
        } else {
          Serial.println("Failed to start streaming - camera initialization error");
        }
      } else {
        streaming = true;
        Serial.println("Streaming started");
      }
    } else if (command == "STOP") {
      streaming = false;
      stop_camera();
    } else if (command == "FLASH") {
      static bool flashOn = false;
      flashOn = !flashOn;
      digitalWrite(4, flashOn ? HIGH : LOW);
      Serial.print("Flash turned ");
      Serial.println(flashOn ? "on" : "off");
    } else if (command == "PIC") {
      streaming = false;
      Serial.println("\nTaking picture");
      captureAndSendPicture(TARGET_SIZE*2, true);
      stop_camera();
    } else if (command == "cd+") {
      chunkDelay += 10;
      Serial.println("Set Delay /p Chunk to:");
      Serial.print(chunkDelay);
    } else if (command == "cd-") {
      chunkDelay = max(10UL, chunkDelay - 10);
      Serial.println("Set Delay /p Chunk to:");
      Serial.print(chunkDelay);
    } else if (command == "fd+") {
      frameDelay += 10;
      Serial.println("Set Delay /p Frame to:");
      Serial.print(frameDelay);
    } else if (command == "fd-") {
      frameDelay = max(10UL, frameDelay - 10);
      Serial.println("Set Delay /p Frame to:");
      Serial.print(frameDelay);
    } else if (command == "cz-") {
      CHUNK_SIZE = max(10UL, CHUNK_SIZE - 10);
      Serial.println("Set Chunk Size to:");
      Serial.print(CHUNK_SIZE);
    } else if (command == "cz+") {
      CHUNK_SIZE += 10;
      Serial.println("Set Chunk Size to:");
      Serial.print(CHUNK_SIZE);
    }
  }

  if (!streaming) {
    Serial.println(".");
    delay(1000);
    return;
  }

  if (!camera_initialized) {
    Serial.println("Camera not initialized!");
    streaming = false;
    return;
  }

  if (streaming) {
    captureAndSendPicture(TARGET_SIZE, false);
    delay(frameDelay);
  }
}
