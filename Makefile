
hx711.dtbo: hx711.dts
	dtc -@ -I dts -O dtb -o hx711.dtbo hx711.dts

install: hx711.dtbo
	sudo cp -f hx711.dtbo /boot/overlays/

clean:
	rm -f hx711.dtbo

.PHONY: clean install
