# Makefile — soc_full_test firmware for VeeR EL2 (RV32IMC)
XCHAIN  := /opt/riscv/bin/riscv64-unknown-elf
CC      := $(XCHAIN)-gcc
OBJCOPY := $(XCHAIN)-objcopy
OBJDUMP := $(XCHAIN)-objdump

CFLAGS  := -march=rv32imczicsr -mabi=ilp32 -O1 -g \
           -ffreestanding -nostdlib -nostartfiles \
           -Wall -Wextra

TARGET  := soc_full_test
LD      := soc_link.ld

all: $(TARGET).hex

$(TARGET).elf: crt0.s $(TARGET).c $(LD)
	$(CC) $(CFLAGS) -T $(LD) -o $@ crt0.s $(TARGET).c

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O verilog --verilog-data-width=1 $< $@

$(TARGET).dump: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases $< > $@

clean:
	rm -f $(TARGET).elf $(TARGET).hex $(TARGET).dump

.PHONY: all clean
