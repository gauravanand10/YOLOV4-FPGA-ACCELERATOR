# PetaLinux bring-up and webcam demo on the ZCU104

This guide takes you from `06_vivado/out/yolo_zcu104.xsa` to live webcam detections. Steps 1–4 run on
the Ubuntu PC, step 5 on the SD card, and steps 6–9 on the board and laptop.

**What you need:**
* ZCU104 with its 12 V supply
* micro-USB cable (JTAG/UART)
* Ethernet cable
* microSD card (≥ 8 GB)
* the Ubuntu machine with PetaLinux
* this `D:\MPSOC_YOLO` folder (copy `06_vivado/out`, `07_sw/board/deploy` and `07_sw/host` over)

---

## 0. Version check — do this first
The `.xsa` was built with **Vivado 2024.1**, and PetaLinux must be the **same release** as the Vivado
that produced the `.xsa`. A 2023.x PetaLinux will reject or mis-handle a 2024.1 `.xsa`.
```sh
petalinux-util --version        # or: echo $PETALINUX_VER
```
* **PetaLinux 2024.1** → continue.
* **PetaLinux 2023.x** (what the Ubuntu machine was set up with) → choose one:
  1. **Recommended:** install PetaLinux 2024.1 next to it, plus the ZCU104 2024.1 BSP. Check UG1144
     for the supported Ubuntu releases; 22.04 LTS is supported.
  2. Rebuild the hardware with the Ubuntu Vivado 2023.x, using the same scripts:
     ```sh
     cd MPSOC_YOLO/06_vivado
     vivado -mode batch -source build.tcl                 # stage 1: project + block design
     vivado -mode batch -source build.tcl -tclargs runs   # stage 2: synth, impl, bitstream, .xsa
     ```
     Then check `reports/timing_impl.rpt` again (WNS ≥ 0) before using that `.xsa`.

Source the tools in every new terminal:
```sh
source <petalinux-install>/settings.sh
```

## 1. Create the project
Starting from the ZCU104 BSP is best: the board's Ethernet PHY, SD and UART are preconfigured.
```sh
mkdir -p ~/zcu104 && cd ~/zcu104
cp /path/to/MPSOC_YOLO/06_vivado/out/yolo_zcu104.xsa .
petalinux-create -t project -s xilinx-zcu104-v2024.1-final.bsp -n yolo_plnx
#   (2024.1 also accepts the new syntax:  petalinux-create project -s <bsp> -n yolo_plnx)
cd yolo_plnx
petalinux-config --get-hw-description=../yolo_zcu104.xsa
```
**Without the BSP:** use `petalinux-create -t project --template zynqMP -n yolo_plnx` and, in the menu,
set **DTG Settings → MACHINE_NAME = `zcu104-revc`**.

In the `petalinux-config` menu:
* **Image Packaging Configuration → Root filesystem type:**
  * `INITRAMFS` (default) is simplest, but files copied to `/home/root` are lost on reboot. Keep the
    app on the SD card's FAT partition instead.
  * `EXT4 (SD/eMMC/...)` gives a persistent root filesystem on the SD card's second partition.
* Leave everything else at the defaults. Save and exit.

## 2. Reserve 256 MiB of DDR for the accelerator
The accelerator and `yolo_server` use physical `0x7000_0000 – 0x7FFF_FFFF`. Linux must never allocate it.
Edit `project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi`:
```dts
/include/ "system-conf.dtsi"
/ {
    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;
        yolo_reserved: yolo@70000000 {
            reg = <0x0 0x70000000 0x0 0x10000000>;   /* 256 MiB */
            no-map;
        };
    };
};
```
If the BSP's `system-user.dtsi` already has content, keep it and only add the `reserved-memory` node.

## 3. Kernel and root filesystem options
```sh
petalinux-config -c kernel
```
Under **Kernel hacking**, make sure **`CONFIG_STRICT_DEVMEM` is off**. If it must stay on, then at least
turn `CONFIG_IO_STRICT_DEVMEM` off. `yolo_server` maps the registers (0xA000_0000) and the reserved DDR
through `/dev/mem`.

```sh
petalinux-config -c rootfs
```
Enable:
* **Filesystem Packages → base → fpga-manager-script** (provides `fpgautil`, needed only for runtime bitstream loading)
* **Image Features → ssh-server-openssh** or dropbear (for `scp`); usually already on in the BSP
* optional: **Filesystem Packages → base → i2c-tools, ethtool**

## 4. Build and package
```sh
petalinux-build
petalinux-package --boot --fsbl images/linux/zynqmp_fsbl.elf --u-boot \
                  --pmufw images/linux/pmufw.elf --fpga images/linux/system.bit --force
```
`--fpga` puts the accelerator bitstream into `BOOT.BIN`, so the PL is configured and **pl_clk0 set to
187.5 MHz** by the FSBL at every boot. `system.bit` in `images/linux` comes from the `.xsa`; it is the
same file as `06_vivado/out/yolo_zcu104.bit`.

Optional one-file SD image:
```sh
petalinux-package --wic --bootfiles "BOOT.BIN boot.scr image.ub"
#  -> images/linux/petalinux-sdimage.wic   (write with balenaEtcher or dd)
```

Optional SDK to build `yolo_server` on Linux. The Windows `build_board.bat` binary also works.
```sh
petalinux-build --sdk && petalinux-package --sysroot
```

## 5. Prepare the SD card and boot
* **With the .wic:** write it to the card (balenaEtcher, or `sudo dd if=petalinux-sdimage.wic of=/dev/sdX bs=4M status=progress`).
* **By hand:** make a FAT32 first partition and copy `images/linux/BOOT.BIN`, `boot.scr` and `image.ub` to it.
  For an EXT4 root filesystem, also extract `rootfs.tar.gz` onto a second ext4 partition.

Copy the application onto the FAT partition as well, so it survives reboots with INITRAMFS:
`07_sw/board/deploy/*` and `06_vivado/out/yolo_zcu104.bit.bin` go into a folder `yolo/`.

On the board:
1. Set **SW6 to SD boot** (ON-OFF-OFF-OFF for positions 1–4; confirm with UG1267 or the board silkscreen).
2. Connect the micro-USB UART and open the console at **115200 8N1**. The ZCU104 shows 4 COM ports;
   the Linux console is usually the first one.
3. Power on and log in: user `petalinux`, set a password at first login (2024.1), then `sudo -i`.
   Older releases use `root` / `root`.

## 6. Check the hardware
```sh
cat /proc/iomem | grep -i 7000      # the reserved region must NOT appear as "System RAM"
devmem 0xA0000018                   # must print 0x594F4C34  ("YOL4" = accelerator is alive)
```
If the ID read hangs or returns garbage, the PL is not configured. Load it at runtime:
```sh
fpgautil -b /run/media/mmcblk0p1/yolo/yolo_zcu104.bit.bin
devmem 0xA0000018
```

## 7. Network (direct cable to the laptop)
```sh
ifconfig eth0 192.168.1.10 netmask 255.255.255.0 up
```
Laptop: set its Ethernet adapter to 192.168.1.1 / 255.255.255.0, then `ping 192.168.1.10`.
To copy the files over the network instead of via the SD card:
`scp -r 07_sw/board/deploy petalinux@192.168.1.10:~/yolo` (2024.1 disables root login over ssh by default; run the app with `sudo`).

## 8. Self-test on the board (the first real hardware measurement)
```sh
cd /run/media/mmcblk0p1/yolo        # or ~/yolo if copied with scp (run as root: sudo -i)
chmod +x yolo_server
./yolo_server --selftest .
```
Expected:
* `slot 0 … PASS` and `slot 1 … PASS`: the INT8 heads are **bit-identical** to the golden model;
* accelerator ≈ 7.5 M cycles ≈ **40 ms ≈ 25 fps** (at 187.5 MHz);
* a throughput line over 50 back-to-back runs.

Record these numbers in `08_docs/README.md` as the first on-board results.

## 9. Live webcam demo
Board:
```sh
./yolo_server -p 5000 -m . -t 0.25
```
Laptop (Windows):
```bat
pip install opencv-python numpy
python D:\MPSOC_YOLO\07_sw\host\yolo_client.py --host 192.168.1.10 --port 5000 --cam 0
```
The window shows boxes, end-to-end FPS and accelerator ms. Press `q` to quit.
The expected end-to-end rate is about 20–25 fps, set by the accelerator; each frame takes about 4.5 ms
on gigabit and is overlapped with compute. It will be lower if the webcam itself delivers fewer fps,
since many laptop cameras are capped at 30 fps or drop to 15 fps in low light.

## Troubleshooting

| Symptom | Likely cause → fix |
|---|---|
| `petalinux-config --get-hw-description` errors or warns about the version | PetaLinux ≠ 2024.1 → see §0 |
| `open /dev/mem: Operation not permitted` or `mmap: Invalid argument` | `CONFIG_STRICT_DEVMEM` still on → §3; or not running as root |
| `accelerator ID mismatch` / `devmem 0xA0000018` hangs | PL not programmed → `fpgautil -b …bit.bin`, or package with `--fpga` |
| Self-test times out (done never set) | Reserved region missing, so Linux may have used 0x7000_0000 → check §2 and `/proc/iomem` |
| Self-test `FAIL` (mismatching bytes) | Stale model files: re-copy `deploy/`, which must come from the same `03_quant_export` run |
| Bus error while copying into DDR | Unaligned access to device memory; always use the provided `dev_write`/`dev_read` |
| Client connects but fps is very low | Laptop Wi-Fi in use, or the link is not 1 Gb/s; check `ethtool eth0` on the board |
| Boxes shifted or stretched | The client must resize to 416×416 without letterbox (it does); don't change `yolo_client.py` preprocessing |
