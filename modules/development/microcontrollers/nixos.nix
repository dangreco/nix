# Grants the dialout group access to microcontroller programming hardware:
# debug probes, bootloaders, and USB-serial bridge chips. Stock udev rules
# already put ttyUSB*/ttyACM* in dialout; these additionally open the raw
# USB/hidraw/sg nodes that flashers (stlink, openocd, dfu-util, esptool) use,
# and keep ModemManager off programming ports.
#
# Adapted to GROUP="dialout" / MODE="0660" from:
# - OpenOCD contrib/60-openocd.rules
# - PlatformIO 99-platformio-udev.rules
# - stlink config/udev/rules.d/49-stlinkv*.rules
# - picotool udev/60-picotool.rules
{
  flake.modules.nixos.microcontrollers =
    { config, lib, ... }:
    {
      users.users = lib.genAttrs config.my.users (_: {
        extraGroups = [ "dialout" ];
      });

      services.udev.extraRules = ''
        # Only device-node subsystems flashers touch; never relax block/net
        # children (e.g. an RP2040 BOOTSEL mass-storage volume keeps default
        # permissions and stays behind udisks/polkit).
        ACTION!="add|change", GOTO="mcu_end"
        SUBSYSTEM!="usb|hidraw|tty|scsi_generic", GOTO="mcu_end"

        # ---- STMicroelectronics (VID-wide): ST-LINK V1 (3744), V2 (3748),
        # ---- V2-1 (374b), V3 (374d/374e/374f/3752/3753/3754/3755/3757),
        # ---- STM32 DFU bootloader (df11), STM32 virtual COM port (5740).
        # ---- V1 is SCSI-passthrough: its /dev/sgN node (scsi_generic) is
        # ---- matched by the same rule via ATTRS ancestor walk-up.
        ATTRS{idVendor}=="0483", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Espressif (VID-wide): ESP32-S2/S3 native USB CDC/JTAG (0002),
        # ---- ROM DFU mode (0009/0011), ESP-Prog JTAG (1001/1002), bridges (4001).
        ATTRS{idVendor}=="303a", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Arduino LLC (2341) + Arduino Srl (2a03), VID-wide:
        # ---- Uno/Mega/Leonardo/Nano/Zero/MKR/Portenta/Nicla + 16U2 DFU bootloaders.
        ATTRS{idVendor}=="2341", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="2a03", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Adafruit (239a) and Seeed (2886), VID-wide: Feather/Metro/ItsyBitsy,
        # ---- Wio, XIAO SAMD + their UF2 bootloaders.
        ATTRS{idVendor}=="239a", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="2886", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Microchip/Atmel (03eb), VID-wide: SAM-BA CDC (6124), 16U2/32U4 DFU
        # ---- bootloaders, AVR ISP mkII (2104), AVR Dragon (2107), Atmel-ICE,
        # ---- opendous/estick (204f).
        ATTRS{idVendor}=="03eb", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1", ENV{MTP_NO_PROBE}="1"

        # ---- Microchip PIC (04d8), VID-wide: PICkit 2/3/4/5, SNAP, MCP2221 USB-serial.
        ATTRS{idVendor}=="04d8", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- USB-serial bridge chips on dev boards: Silicon Labs CP210x (10c4),
        # ---- WCH CH340/CH343/CH9102 + WCH-Link probes + CH347 JTAG (1a86),
        # ---- Prolific PL2303.
        ATTRS{idVendor}=="10c4", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="1a86", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- FTDI UARTs + JTAG probes (enumerated; VID shared with OEM products):
        # ---- FT232/FT245, FT2232H, FT4232H, FT232H, FT231X, H-series, TUMPA,
        # ---- XDS100v2/v3, OOCDLink, KT-Link, Signalyzer, Stellaris ICDI,
        # ---- Turtelizer, ICEbear, JTAGlock-pick, JTAGkey, Presto.
        ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001|6010|6011|6014|6015|6040|6041|6042|6043|6044|6045|6048|8220|8a98|8a99|a6d0|a6d1|baf8|bbe2|bca0|bca1|bcd9|bcda|bdc8|c140|c141|cff8|f1a0", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Debug probes:
        # SEGGER J-Link (VID-wide, as in PlatformIO's rules)
        ATTRS{idVendor}=="1366", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # Olimex ARM-USB-OCD family (VID-wide)
        ATTRS{idVendor}=="15ba", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # HiTex probes (VID-wide)
        ATTRS{idVendor}=="0640", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # ARM mbed CMSIS-DAP reference
        ATTRS{idVendor}=="0d28", ATTRS{idProduct}=="0204", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # Any adapter identifying as CMSIS-DAP via product string (covers clones)
        ATTRS{product}=="*CMSIS-DAP*", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # Black Magic Probe
        ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="6018", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # Nuvoton NuLink
        ATTRS{idVendor}=="0416", ATTRS{idProduct}=="511b|511c|511d|5200|5201", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # Cypress KitProg (+ CMSIS-DAP mode) and SuperSpeed Explorer Kit
        ATTRS{idVendor}=="04b4", ATTRS{idProduct}=="0007|f138|f139", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        # Holtek e-Link32 Pro/Lite
        ATTRS{idVendor}=="04d9", ATTRS{idProduct}=="802f|8052", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Texas Instruments: XDS110/Luminary ICDI (1cbe VID-wide incl. DFU 00ff),
        # ---- ICDI (0451:c32a), XDS110 standalone (0451:bef3/bef4), MSP430 (f432).
        ATTRS{idVendor}=="1cbe", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="0451", ATTRS{idProduct}=="bef3|bef4|c32a|f432", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Raspberry Pi RP2040/RP2350 (VID-wide): BOOTSEL UF2 (0003),
        # ---- Picoprobe (0009), CDC (000a).
        ATTRS{idVendor}=="2e8a", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Open-source gadgets on the shared 16c0 VID: Teensy (04xx),
        # ---- USBasp (05dc), ixo-usb-jtag (06ad).
        ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04*|05dc|06ad", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        # ---- Misc programmers/bootloaders: USBtinyISP + USBprog, Maple DFU,
        # ---- GD32V DFU, Altera USB Blaster, NXP OSBDM, Keil ULink, Raisonance
        # ---- RLink, CK-Link, ANGIE, Qualcomm EUD, Infineon DAP miniWiggler,
        # ---- Neo1973, Sheevaplug, Amontec JTAGkey-HiSpeed, PLS SPC5,
        # ---- isodebug, Microchip RISC-V, Ambiq EVK.
        ATTRS{idVendor}=="1781", ATTRS{idProduct}=="0c63|0c9f", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="1eaf", ATTRS{idProduct}=="0003|0004", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="28e9", ATTRS{idProduct}=="0189", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="09fb", ATTRS{idProduct}=="6001|6010|6810", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="15a2", ATTRS{idProduct}=="0042|0058|005e", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="c251", ATTRS{idProduct}=="2710|2750", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="138e", ATTRS{idProduct}=="9000", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="32bf|42bf", ATTRS{idProduct}=="b210", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="584e", ATTRS{idProduct}=="414f|424e|4a55", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="05c6", ATTRS{idProduct}=="9501|9502|9503|9504|9505", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="058b", ATTRS{idProduct}=="0043", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="1457", ATTRS{idProduct}=="5118", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="9e88", ATTRS{idProduct}=="9e8f", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="0fbb", ATTRS{idProduct}=="1000", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="263d", ATTRS{idProduct}=="4001", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="22b7", ATTRS{idProduct}=="150d", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="1514", ATTRS{idProduct}=="2008|200a", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"
        ATTRS{idVendor}=="2aec", ATTRS{idProduct}=="1106|6010|6011", GROUP="dialout", MODE="0660", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{ID_MM_PORT_IGNORE}="1"

        LABEL="mcu_end"
      '';
    };
}
