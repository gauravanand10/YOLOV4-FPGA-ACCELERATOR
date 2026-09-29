# Cross-compile for the ZCU104 (aarch64 Linux / PetaLinux).
#   make                      (CROSS=aarch64-linux-gnu-  e.g. from PetaLinux SDK or Vitis gnu/aarch64/.../aarch64-linux)
#   make host                 (host build of the decode path only: ./yolo_decode_host --decode heads.bin)
CROSS  ?= aarch64-linux-gnu-
CC      = $(CROSS)gcc
CFLAGS ?= -O3 -Wall -Wextra -mcpu=cortex-a53
MODEL   = ../../03_quant_export/out

all: yolo_server

model_params.h: $(MODEL)/model_params.h
	cp $< $@

yolo_server: yolo_server.c yolo_accel.c yolo_post.c yolo_accel.h yolo_post.h model_params.h
	$(CC) $(CFLAGS) -o $@ yolo_server.c yolo_accel.c yolo_post.c -lpthread -lm

host: yolo_server.c yolo_post.c model_params.h
	gcc -O2 -Wall -DHOST_ONLY -o yolo_decode_host yolo_server.c yolo_post.c -lm

# files to copy to the board (e.g. scp -r deploy root@zcu104:/home/root/yolo)
deploy: yolo_server
	mkdir -p deploy
	cp yolo_server $(MODEL)/yolo_desc.bin $(MODEL)/yolo_weights.bin $(MODEL)/test_input_rgb.bin $(MODEL)/test_heads.bin deploy/

clean:
	rm -rf yolo_server yolo_decode_host deploy
