"""Laptop webcam client for the ZCU104 YOLOv4-tiny server.

usage: python yolo_client.py --host 192.168.1.10 [--port 5000] [--cam 0] [--video file.mp4] [--inflight 2]

Captures frames with OpenCV, resizes to 416x416 RGB (no letterbox, same as darknet), sends them,
receives detections and draws them on the original frame with end-to-end FPS and accelerator time.
Up to --inflight frames are kept in flight so network transfer overlaps board compute.
Protocol: see 07_sw/board/yolo_server.c.
"""
import argparse, socket, struct, threading, time, queue, collections
import numpy as np
import cv2

CLASSES = ['person', 'car', 'bicycle', 'bottle', 'chair', 'laptop', 'cup']
COLORS = [(0, 255, 0), (255, 128, 0), (0, 200, 255), (255, 0, 255), (0, 128, 255), (255, 255, 0), (128, 0, 255)]
MAGIC_F, MAGIC_R = 0x464C4F59, 0x524C4F59
DET = np.dtype([('x1', '<f4'), ('y1', '<f4'), ('x2', '<f4'), ('y2', '<f4'), ('score', '<f4'), ('cls', '<i4')])


def recv_all(s, n):
    b = bytearray()
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise ConnectionError('server closed connection')
        b += c
    return bytes(b)


def send_frame(s, fid, frame_bgr):
    rgb = cv2.cvtColor(cv2.resize(frame_bgr, (416, 416), interpolation=cv2.INTER_LINEAR), cv2.COLOR_BGR2RGB)
    s.sendall(struct.pack('<4I', MAGIC_F, fid, 416, 416) + rgb.tobytes())


def recv_result(s):
    magic, fid, n, acc_ms, srv_ms = struct.unpack('<3I2f', recv_all(s, 20))
    if magic != MAGIC_R:
        raise ValueError('bad reply magic')
    dets = np.frombuffer(recv_all(s, n * DET.itemsize), DET) if n else np.zeros(0, DET)
    return fid, dets, acc_ms, srv_ms


def draw(frame, dets):
    h, w = frame.shape[:2]
    for d in dets:
        c = int(d['cls'])
        x1, y1 = int(max(0, d['x1']) * w), int(max(0, d['y1']) * h)
        x2, y2 = int(min(1, d['x2']) * w), int(min(1, d['y2']) * h)
        col = COLORS[c % len(COLORS)]
        cv2.rectangle(frame, (x1, y1), (x2, y2), col, 2)
        lab = f'{CLASSES[c]} {d["score"]:.2f}'
        (tw, th), _ = cv2.getTextSize(lab, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(frame, (x1, max(0, y1 - th - 4)), (x1 + tw + 2, y1), col, -1)
        cv2.putText(frame, lab, (x1 + 1, y1 - 3), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='192.168.1.10')
    ap.add_argument('--port', type=int, default=5000)
    ap.add_argument('--cam', type=int, default=0)
    ap.add_argument('--video', default=None, help='video/image file instead of webcam')
    ap.add_argument('--inflight', type=int, default=2)
    ap.add_argument('--frames', type=int, default=0, help='stop after N frames (0 = run until q)')
    ap.add_argument('--no-display', action='store_true')
    a = ap.parse_args()

    still = cv2.imread(a.video) if a.video else None      # a still image is sent repeatedly
    cap = None if still is not None else cv2.VideoCapture(a.video if a.video else a.cam)
    if cap is not None and not cap.isOpened():
        raise SystemExit('cannot open video source')
    s = socket.create_connection((a.host, a.port))
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    pending = {}                      # fid -> original frame
    lock = threading.Lock()
    slots = threading.Semaphore(a.inflight)
    results = queue.Queue()
    stop = threading.Event()

    def rx():
        try:
            while True:
                r = recv_result(s)
                results.put(r)
                slots.release()
        except Exception as e:  # noqa: BLE001
            if not (stop.is_set() and not pending):   # ignore the error caused by our own close
                print('receiver:', e)
            results.put(None)

    threading.Thread(target=rx, daemon=True).start()
    fid, shown = 0, 0
    times = collections.deque(maxlen=30)
    t_start = time.time()
    acc_hist = collections.deque(maxlen=30)
    while True:
        # keep the pipeline full
        while not stop.is_set() and slots.acquire(blocking=False):
            if a.frames and fid >= a.frames:
                slots.release(); stop.set(); break
            if still is not None:
                ok, frame = True, still.copy()
            else:
                ok, frame = cap.read()
                if not ok and a.video:  # loop video files
                    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    ok, frame = cap.read()
            if not ok:
                slots.release(); stop.set(); break
            with lock:
                pending[fid] = frame
            send_frame(s, fid, frame)
            fid += 1
        with lock:
            if stop.is_set() and not pending:
                break
        r = results.get()
        if r is None:
            break
        rfid, dets, acc_ms, srv_ms = r
        with lock:
            frame = pending.pop(rfid)
        times.append(time.time()); acc_hist.append(acc_ms)
        fps = (len(times) - 1) / (times[-1] - times[0]) if len(times) > 1 else 0.0
        shown += 1
        draw(frame, dets)
        cv2.putText(frame, f'FPS {fps:5.1f}  accel {np.mean(acc_hist):5.1f} ms  dets {len(dets)}', (8, 22),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
        if not a.no_display:
            cv2.imshow('ZCU104 YOLOv4-tiny', frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break
        elif shown % 10 == 0:
            print(f'frame {rfid}: {len(dets)} dets, {fps:.1f} fps, accel {acc_ms:.2f} ms, server {srv_ms:.2f} ms')
        if a.frames and shown >= a.frames:
            break
    stop.set()
    print(f'{shown} frames in {time.time() - t_start:.1f}s ({shown / (time.time() - t_start):.1f} fps average)')
    s.close()
    if cap is not None:
        cap.release()
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
