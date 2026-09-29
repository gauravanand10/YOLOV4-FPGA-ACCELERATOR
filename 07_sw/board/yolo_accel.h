/* YOLOv4-tiny accelerator user-space driver (PetaLinux, /dev/mem). */
#ifndef YOLO_ACCEL_H
#define YOLO_ACCEL_H
#include <stdint.h>
#include <stddef.h>

#define ACCEL_REG_BASE   0xA0000000u   /* M_AXI_HPM0_FPD window assigned in the block design */
#define ACCEL_REG_SIZE   0x1000u
#define RESERVED_BYTES   0x10000000u   /* 256 MiB reserved-memory at DDR_BASE (see README) */

#define REG_CTRL      0x00
#define REG_STATUS    0x04
#define REG_DESC      0x08
#define REG_NLAYERS   0x0C
#define REG_CYCLES    0x10
#define REG_LAYER     0x14
#define REG_ID        0x18
#define REG_STALL_ROW 0x1C
#define REG_STALL_OUT 0x20
#define REG_WLOAD     0x24
#define ACCEL_ID      0x594F4C34u

#define NUM_SLOTS 2   /* double-buffered input images */

typedef struct {
    int fd;
    volatile uint32_t *regs;
    volatile uint8_t  *ddr;       /* mapping of DDR_BASE .. DDR_BASE+RESERVED_BYTES (non-cached) */
    uint32_t in_off[NUM_SLOTS];   /* input buffer offset per slot */
    uint32_t desc_off[NUM_SLOTS]; /* descriptor table per slot (layer 0 reads its own input) */
} accel_t;

typedef struct { uint32_t cycles, stall_row, stall_out, wload; } accel_stats_t;

int  accel_open(accel_t *a);
void accel_close(accel_t *a);
int  accel_load_model(accel_t *a, const char *desc_bin, const char *weights_bin);
/* write one 416x416 RGB (uint8, HWC) frame into input slot (pixel>>1, padded to 16 channels) */
void accel_write_input(accel_t *a, int slot, const uint8_t *rgb);
int  accel_run(accel_t *a, int slot, accel_stats_t *st, int timeout_ms);
/* copy both raw head buffers (13x13x64, 26x26x64 int8) out of DDR */
void accel_read_heads(accel_t *a, int8_t *out1, int8_t *out2);
/* 64-bit aligned copies to/from device memory (unaligned access to Device memory faults) */
void dev_write(volatile uint8_t *dst, const void *src, size_t n);
void dev_read(void *dst, const volatile uint8_t *src, size_t n);
#endif
