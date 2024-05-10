# HX711 driver for Raspberry Pi

How to use IIO driver for HX711 on Raspberry PI (tested on RPI Zero).

## Device tree overlay

### Useful references

[Raspberry Pi Documentation - Device Tree overlays](https://www.raspberrypi.com/documentation/computers/configuration.html#device-tree-overlays)
[Overlays README](https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README)

[HX711 DT overlay (link 1)](https://gist.github.com/adrianlzt/6e927eb83b405f09d89624150e1d4d35)
[HX711 DT overlay (link 2)](https://raspberrypi.stackexchange.com/questions/103984/trouble-adding-a-gpio-device-to-the-device-tree/109715#109715)


### Build DT overlay

```bash
make install
```

May need to install `dtc` and/or other dt tools.
This should compile `hx711.dts` to `hx711.dtbo` without any errors or warnings
and then copy to `/boot/overlays/`

### Use hx711 overlay

Edit `/boot/config.txt`, add to the part where are other overlay examples new line (adjust `sckpin` and `doutpin` values to your HW setup):

```bash
dtoverlay=hx711,sckpin=23,doutpin=24
```

## HX711 IIO driver

Unfortunately raspbian does not supply all the IIO kenrel drivers so we need to compile them by ourselves.

Best is to crosscompile on another computer (e.g. Linux, WSL2, ...) 

Use the offcicial guide [Raspberry Pi Documentation - Cross-compiling the kernel](https://www.raspberrypi.com/documentation/computers/linux_kernel.html#cross-compiling-the-kernel) with following changes:

- determine your exact current kernel version
- find out the commit/tag
- checkout that version instead of the latest one
- after the `make .... *-defconfig` part do the same but with standard `make ... menuconfig` and enable required drivers as modules (M). Make sure at least following are enabled (under device drivers/industrial io/...). Do not disable any already enabled items.
  - `iio-trig-hrtimer`
  - `iio_trig_sysfs`
  - `hx711`
- build the modules using `make ... modules`
- copy the modules to raspberry pi to the corresponding dirs in `/lib/modules/...`

Add to `/etc/modules` these lines:
```bash
iio-trig-hrtimer
iio_trig_sysfs
```

Reboot raspberry pi.

## How to use

Note that the driver only provides HX711 ADC readings. Any calibration/conversion to actual weight is up to the user application.

### Direct read

Example:
```bash
cat /sys/bus/iio/devices/iio\:device0/in_voltage0_raw
8523636
```

### Periodic bufferred read

The goal is to have the system continously read in exact intervals the weigh an buffer the readings so that the application can be "flaky" about its timing.

Create timer triger for the sampling at 10Hz:
```bash
mkdir /sys/kernel/config/iio/triggers/hrtimer/hx_sample
echo 10.0 > /sys/bus/iio/devices/trigger0/sampling_frequency
```
This assumes there are no other triggers already created, otherwise find correspodning trigger index by checking its name (here `hx_sample`).

Set up hx711 to capture timestamp and first ADC, set buffer to 1k samples, watermark to 5 samples:
```bash
echo 1    > /sys/bus/iio/devices/iio:device0/buffer0/in_timestamp_en
echo 1    > /sys/bus/iio/devices/iio:device0/buffer0/in_voltage0_en
echo 1024 > /sys/bus/iio/devices/iio:device0/buffer0/length
echo 5    > /sys/bus/iio/devices/iio:device0/buffer0/watermark
```

Set our periodic trigger for the bufferred sampling and enable it.
```bash
echo hx_sample > /sys/bus/iio/devices/iio:device0/trigger/current_trigger
echo 1         > /sys/bus/iio/devices/iio:device0/buffer/enable
```

If all went well the system should now sample hx711 on its own. You can check it for example using (note that you may need to change acess rights or run as root, also see below):
```bash
cat /dev/iio\:device0 | hexdump
```

Now the application can read this file without worrying about timing.
Another advantage is that the timing is pretty accurate and with minimal system performance impact.
For details about the format see [Industrial IIO device buffers](https://dri.freedesktop.org/docs/drm/iio/iio_devbuf.html)

### Persist sysfs settings over boot

Unfortunately `sysfsutils` does not support dir create so will use [tmpfiles](https://manpages.ubuntu.com/manpages/bionic/man5/tmpfiles.d.5.html) instead.

Create file `/etc/tmpfiles.d/sysfs-hx711.conf` with following content:
```bash
#Type Path                                                     Mode UID  GID  Age Argument
d     /sys/kernel/config/iio/triggers/hrtimer/hx_sample        0755 root root
w     /sys/bus/iio/devices/trigger0/sampling_frequency         -    -    -    -   10.0
w     /sys/bus/iio/devices/iio:device0/buffer0/in_timestamp_en -    -    -    -   1
w     /sys/bus/iio/devices/iio:device0/buffer0/in_voltage0_en  -    -    -    -   1
w     /sys/bus/iio/devices/iio:device0/buffer0/length          -    -    -    -   1024
w     /sys/bus/iio/devices/iio:device0/buffer0/watermark       -    -    -    -   5
w     /sys/bus/iio/devices/iio:device0/trigger/current_trigger -    -    -    -   hx_sample
w     /sys/bus/iio/devices/iio:device0/buffer/enable           -    -    -    -   1
```

#### Device access rights

Create udev rule to add access rights to the bufferred device `/dev/iio:device0`.

Create for example `/etc/udev/rules.d/90-hx711.rules` with this rule:
```bash
KERNEL=="iio:device[0-9]*", SUBSYSTEM=="iio", GROUP="iio", MODE="0660"
```

Assuming you have group `iio` and required users are in it.

Reboot.

Now after system start there should be device `/dev/iio:device0` with continuously updated values accessible by ordinary user.
