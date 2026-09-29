# 07_sw — software: board server (ZCU104) and laptop webcam client

```
 laptop (Windows/Linux)                                   ZCU104 (PetaLinux, ARM Cortex-A53)
 ┌─────────────────────────────┐   GbE / TCP 5000   ┌────────────────────────────────────────────┐
 │ host/yolo_client.py         │ ── 'YOLF' frame ──► │ board/yolo_server                          │
 │  webcam → resize 416 → RGB  │    416×416×3 RGB    │  rx thread: preprocess into free input slot │
 │  draw boxes, FPS, accel ms  │ ◄── 'YOLR' dets ─── │  main: run accel (slot A/B) → decode + NMS │
 └─────────────────────────────┘                     └───────────────┬────────────────────────────┘
                                                                     │ /dev/mem: regs 0xA000_0000
                                                                     │           DDR  0x7000_0000 (256 MiB)
                                                                     ▼
                                                             PL accelerator (06_vivado bitstream)
```

| Folder | Content | README |
|---|---|---|
| `board/` | C application and driver for the ZCU104 (aarch64 Linux) | [board/README.md](board/README.md) |
| `host/` | Python webcam client, plus a PC emulator of the board | [host/README.md](host/README.md) |

**Status:** the board app cross-compiles cleanly (`-Wall -Wextra`). Its C decode + NMS gives the same
detections as the Python golden decode (`test_dets.txt`). The client has been tested end to end
against `sim_server.py`. Nothing has run on the real board yet.
