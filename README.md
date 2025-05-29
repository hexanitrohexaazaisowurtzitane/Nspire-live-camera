# Nspire-live-camera
A cool streaming camera for the ti nspire cx!

<img src="https://github.com/user-attachments/assets/0e3e0964-9cb6-434c-bd4e-dabce16ab631" width="400">
<img src="https://github.com/user-attachments/assets/8397de01-2330-407d-b3cc-b4d6e430bf36" width="400">


Demo video: https://www.youtube.com/watch?v=ovcZZQsaPfE


### What it does:
Esp32-cam (cam.ino):
- Captires real time images and converts them into a compressed feed of pixel art frames.
* Real time video stream with custom compression
* color quantization (36 colors) with weighting
* RGB565->RGB888 color space conversion
* color match + RLE encoding
* Huffman compression with few data loss
* Base64 encoding for transmission
* (read cam.ino header for more info)

NspireCx (readport3.0):
- Catches and renders the esp's feed into the display. Manages ui, controls and chats
* thats pretty much it

Todo:
* Real time interface with discord channel
* AI LLM photo + chat support
* faster camera controls for stopping stream and etc
* actually implement the available features into the esp lol

## Scheme
![qiuu](https://github.com/user-attachments/assets/1acd89ba-e1a6-4fd5-991b-56434bdedabf)
