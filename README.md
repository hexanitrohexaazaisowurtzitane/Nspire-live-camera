# Nspire-live-camera
A cool streaming camera for the ti nspire cx!

<img src="https://github.com/user-attachments/assets/fab9612a-ea3d-4c8d-8b29-f3bd2f5bee28" width="400">
<img src="https://github.com/user-attachments/assets/d19f8476-37e2-4f46-a45f-02e3f6d9f9e6" width="400">




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
* ✓ Real time interface with discord channel
* ✗ improve on transmission preformance
* ✗ AI LLM photo + chat support
* ✗ faster camera controls for stopping stream and etc
* ✗ actually implement the available features into the esp lol
* ✗ Make use of dock connector (+bypass read write) and hide the electronics

## Scheme
![qiuu](https://github.com/user-attachments/assets/a2b94dbc-631a-4b90-a59e-4046df9790aa)

