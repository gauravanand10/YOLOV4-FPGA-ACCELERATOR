# 07_sw/host — laptop side

## yolo_client.py — webcam demo
Captures the laptop webcam with OpenCV and resizes each frame to 416×416 RGB (plain resize, the same
as darknet). It sends the frames to the board and draws the returned boxes on the original frame,
with end-to-end FPS, accelerator ms and the detection count. Up to `--inflight` frames are in flight at
once, so network transfer overlaps board compute. Press `q` to quit.

```bat
pip install opencv-python numpy
python yolo_client.py --host 192.168.1.10 --port 5000 --cam 0
```
| Option | Default | Meaning |
|---|---|---|
| `--host` | 192.168.1.10 | board IP |
| `--port` | 5000 | server port |
| `--cam` | 0 | webcam index |
| `--video <file>` | — | use a video or image file instead of the webcam |
| `--inflight` | 2 | frames in flight (2 matches the board's two input slots) |
| `--frames N` | 0 | stop after N frames (0 = until `q`) |
| `--no-display` | off | headless (prints statistics only) |

**Network:** connect the ZCU104 Ethernet port directly to the laptop. Give the board a static
192.168.1.10 and the laptop 192.168.1.1/24. One 416×416×3 frame is 519 KB, about 4.5 ms on gigabit.

## sim_server.py — the board, emulated on the PC
Speaks exactly the same protocol, but computes with the bit-exact INT8 golden model
(`02_golden_model/quant.py`) on the PC CPU/GPU. It returns the same detections the hardware will
produce, at about 0.2 s per frame. Use it to test the client and the protocol without a board:

```bat
python sim_server.py --port 5000
python yolo_client.py --host 127.0.0.1 --port 5000
```
The golden conv now uses float32/int32 instead of float64 and matches the old version bit for bit on
all 21 layers. This fixed the earlier out-of-memory crash.
