# BeagleBone Black Boot Flow: ROM → SPL → U-Boot → Linux

## 1. Objective

Document the boot sequence of the BeagleBone Black (BBB), based on the TI AM335x SoC, from power-on reset through Linux userspace startup.

This document describes the responsibilities of each boot stage, the transfer of control between stages, the boot artifacts, and the project-specific boot configuration.

## 2. Platform and Software Configuration

 Component | Configuration 

| Board	BeagleBone Black
| SoC | 	Texas Instruments AM335x |
| CPU | ARM Cortex-A8, ARMv7-A |
| Boot media | microSD card |
| SPL image | `MLO` |
| U-Boot image | `u-boot.img` |
| U-Boot version | v2026.07 |
| Linux kernel image | `zImage` |
| Device Tree Blob | `am335x-boneblack.dtb` |
| Kernel version | 6.12.54 |
| Root filesystem | Existing filesystem on SD-card partition 2 |
| Console | Serial, 115200 baud |

## 3. High-Level Boot Architecture

The boot process consists of four main stages.

```text
          Power-on / Reset
                 |
                 v
      +-----------------------+
      | AM335x Boot ROM       |
      | First-stage selection |
      +-----------------------+
                 |
                 | Loads SPL from boot media
                 v
      +-----------------------+
      | SPL (MLO)             |
      | Early hardware setup  |
      | DDR initialization    |
      +-----------------------+
                 |
                 | Loads U-Boot proper
                 v
      +-----------------------+
      | U-Boot proper         |
      | v2026.07              |
      | Environment + commands|
      +-----------------------+
                 |
                 | Loads kernel and DTB
                 v
      +-----------------------+
      | Linux Kernel          |
      | Early initialization  |
      | Driver initialization |
      +-----------------------+
                 |
                 | Mounts root filesystem
                 v
      +-----------------------+
      | Linux Userspace       |
      | /sbin/init or equivalent
      +-----------------------+
```

## 4. Stage 1 — AM335x Boot ROM

### Purpose

The Boot ROM is immutable code inside the AM335x SoC. It executes automatically after reset and selects a boot source according to the boot configuration and supported boot sequence.

### Responsibilities

- Perform the initial processor-level setup required by the ROM.
- Determine the boot source based on the boot-mode configuration.
- Access the selected boot device.
- Locate and load the first-stage bootloader, SPL.
- Transfer execution to the loaded SPL.

### Project context

For this project, the boot source is the microSD card. The SPL image is named `MLO`.

The Boot ROM is not compiled as part of the project and is not a file that we replace during a normal U-Boot build.

**Key point:** The Boot ROM must load a sufficiently small first-stage program before the system can perform the full DDR and bootloader initialization needed for later stages.

## 5. Stage 2 — SPL / MLO

SPL stands for *Secondary Program Loader*. In this project, its generated boot image is `MLO`.

### Purpose

SPL prepares enough of the hardware to load and execute the full U-Boot image.

### Responsibilities

- Perform early SoC and board initialization.
- Initialize external DDR memory, which is required for larger software images.
- Initialize the storage interface needed to continue booting.
- Locate and load U-Boot proper from the boot media.
- Transfer execution to U-Boot proper.

The exact initialization sequence depends on the AM335x SPL implementation, its configuration, and the board-specific code.

### Project artifacts

| Artifact | Purpose |
|---|---|
| `MLO` | SPL boot image loaded by the Boot ROM |
| `u-boot.img` | Full U-Boot image loaded by SPL |

Both artifacts are built from the U-Boot source tree using the board configuration:

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- am335x_evm_defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j"$(nproc)"
```

### Important distinction

`MLO` is the first-stage bootloader image, whereas `u-boot.img` contains U-Boot proper. They are separate stages even though both originate from the U-Boot source tree.

## 6. Stage 3 — U-Boot Proper

### Purpose

U-Boot proper provides the bootloader command environment used to load the Linux kernel, prepare the device tree, configure kernel arguments, and transfer control to Linux.

The project uses U-Boot v2026.07.

### Responsibilities

- Initialize and expose the required bootloader facilities.
- Initialize the MMC interface and access the boot partition.
- Load and import environment settings.
- Select and execute the configured boot command.
- Load the kernel image and device tree.
- Set the Linux kernel command line.
- Invoke the appropriate kernel boot command.

### 6.1 Boot environment

The project's `uEnv.txt` contains the boot configuration. The relevant configuration is:

```bash
fdtfile=am335x-boneblack.dtb

loadkernel=load mmc 0:1 ${loadaddr} zImage
loadfdt=load mmc 0:1 ${fdtaddr} ${fdtfile}
setbootargs=setenv bootargs console=ttyS0,115200n8 root=/dev/mmcblk0p2 rw rootwait

uenvcmd=run loadkernel && run loadfdt && run setbootargs && bootz ${loadaddr} - ${fdtaddr}
```

The commands perform the following operations:

1. `loadkernel` loads `zImage` from MMC device 0, partition 1, into the address specified by `${loadaddr}`.
2. `loadfdt` loads `am335x-boneblack.dtb` into the address specified by `${fdtaddr}`.
3. `setbootargs` configures the kernel command line.
4. `bootz` starts the ARM Linux kernel using the loaded compressed kernel image and device tree. The `-` indicates that no separate initramfs image is being supplied.

**Address note:** `${loadaddr}` and `${fdtaddr}` are U-Boot environment variables. Their actual values should be verified on the target using `printenv loadaddr fdtaddr`.

### 6.2 Automated boot command

The persistent `bootcmd` is configured to:

```text
mmc dev 0;
if fatload mmc 0:1 ${loadaddr} uEnv.txt;
then
    if env import -t ${loadaddr} ${filesize};
    then run uenvcmd;
    fi;
fi
```

This is a logical representation of the command; the actual `bootcmd` is stored as a single U-Boot environment string.

Execution sequence:

1. Select MMC device 0.
2. Load `uEnv.txt` from the first partition.
3. Import the text file as environment variables.
4. Execute `uenvcmd` if the import succeeds.
5. Load the kernel and DTB, configure boot arguments, and invoke `bootz`.

The bootloader environment is persisted with:

```text
=> saveenv
```

The configured boot delay is verified using:

```text
=> printenv bootdelay
```

### 6.3 Kernel command line

The current configuration uses:

```text
console=ttyS0,115200n8 root=/dev/mmcblk0p2 rw rootwait
```

| Parameter | Meaning |
|---|---|
| `console=ttyS0,115200n8` | Send kernel console messages to the configured serial console at 115200 baud, 8 data bits, no parity |
| `root=/dev/mmcblk0p2` | Use the second partition of MMC device 0 as the root filesystem |
| `rw` | Mount the root filesystem read-write |
| `rootwait` | Wait for the root block device to become available |

These arguments are passed from U-Boot to Linux at boot time.

## 7. Stage 4 — Linux Kernel

### Purpose

The Linux kernel takes control from U-Boot and initializes the operating system environment.

### Responsibilities

- Enter the architecture-specific kernel startup code.
- Initialize memory management, interrupts, scheduling, and core kernel subsystems.
- Parse the kernel command line.
- Initialize built-in drivers and discover hardware described by the device tree.
- Initialize storage and filesystem support.
- Mount the root filesystem specified by `root=`.
- Start the first userspace process, typically `/sbin/init` or an equivalent init system.

### Kernel image and device tree

The project uses:

- `zImage` — compressed ARM Linux kernel image.
- `am335x-boneblack.dtb` — hardware description for the BeagleBone Black.

The device tree describes hardware resources such as memory regions, interrupt connections, buses, and peripherals. The kernel uses this description alongside its compiled-in and loadable drivers to initialize the board correctly.

### Root filesystem

The kernel mounts the existing root filesystem from:

```text
/dev/mmcblk0p2
```

Once the root filesystem is available and the initial userspace process starts successfully, boot progresses from kernel initialization to normal Linux operation.

## 8. How to Verify Each Stage

Connect to the BBB serial console and capture output from power-on through the Linux login prompt.

### U-Boot verification

At the U-Boot prompt:

```text
=> version
=> printenv bootcmd
=> printenv bootdelay
=> printenv loadaddr fdtaddr
=> mmc list
=> mmc dev 0
=> fatls mmc 0:1
```

Verify that the expected boot artifacts are present and that the configured boot environment matches the project configuration.

### Linux verification

After Linux boots:

```bash
uname -a
cat /proc/cmdline
findmnt /
ls -l /boot
```

Expected observations:

- The running kernel reports version `6.12.54`.
- `/proc/cmdline` contains the expected console and root filesystem arguments.
- The root filesystem is mounted from the expected storage device.

The `/boot` contents depend on how the root filesystem is organized; the kernel and DTB may instead reside only on the separate boot partition.

## 9. Failure Points and Debugging Strategy

| Stage | Typical failure | Initial investigation |
|---|---|---|
| Boot ROM | SPL is not found or loaded | Check boot-mode settings, SD-card layout, and `MLO` availability |
| SPL | DDR initialization or U-Boot loading fails | Capture early serial output and inspect the SPL build/configuration |
| U-Boot | Boot environment or file loading fails | Use `printenv`, `mmc list`, `fatls`, and `fatload` |
| Kernel entry | Kernel image or DTB is invalid | Verify the loaded files, load addresses, and `bootz` arguments |
| Root mount | Kernel cannot mount the root filesystem | Check `root=`, storage drivers, filesystem support, and `rootwait` |
| Userspace | Init cannot execute | Verify the root filesystem contents, init path, architecture, and executable dependencies |

For reliable recovery, keep a known-working SD-card boot configuration and retain access to the serial console while changing U-Boot.

## 10. Week 1 Outcome

The following milestones have been demonstrated on the target:

- U-Boot v2026.07 has been built from source for the AM335x board configuration.
- `MLO` and `u-boot.img` have been deployed to the SD-card boot partition.
- The custom U-Boot environment loads `uEnv.txt`.
- The kernel and device tree are loaded and passed to Linux.
- The Linux kernel boots and mounts the existing root filesystem.
- Automatic boot is working after configuration of the persistent boot command.

Remaining Week 1 evidence to capture:

- A complete serial boot log from power-on through userspace startup.
- The exact build commands, compiler version, U-Boot commit, and configuration used.
- A clean rebuild and boot verification.
- Git-tracked documentation and project configuration.

## 11. Conclusion

The demonstrated boot sequence is:

**AM335x Boot ROM → SPL (`MLO`) → U-Boot proper (`u-boot.img`) → Linux (`zImage` + DTB) → root filesystem → userspace init.**

Understanding this chain provides the foundation for subsequent work on boot failure handling, recovery boot paths, image validation, secure boot, and firmware update mechanisms.

