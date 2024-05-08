# HX711 driver for Raspberry Pi

How to use IIO driver for HX711 on Raspberry PI (tested on RPI Zero).

## Device tree overlay

### Useful references

https://forums.raspberrypi.com/viewtopic.php?t=252784
https://gist.github.com/adrianlzt/6e927eb83b405f09d89624150e1d4d35
https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README

### Build DT overlay

```bash
make install
```

May need to install `dtc` and/or other dt tools.
This should compile `hx711.dts` to `hx711.dtbo` without any errors or warnings
and then copy to `/boot/overlays/`

### Use hx711 overlay

Edit `/boot/config.txt`, add to the part where are other overlay examples new line:

```bash
dtoverlay=hx711
```

### TODO

Make GPIO pins confiurable (now hardcoded to 23 and 24).

## HX711 IIO driver

Unfortunately raspbian does not supply all the IIO kenrel drivers so we need to compile them by ourselves.

Best is to crosscompile on another computer (e.g. Linux, WSL2, ...) 

Use the offcicial guide https://www.raspberrypi.com/documentation/computers/linux_kernel.html#cross-compiling-the-kernel with following changes:

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

If all went well the system should now sample hx711 on its own. You can check it for example using:
```bash
cat /dev/iio\:device0 | hexdump
```

Now the application can read this file without worrying about timing.
Another advantage is that the timing is pretty accurate and with minimal system performance impact.
For details about the format see https://dri.freedesktop.org/docs/drm/iio/iio_devbuf.html
