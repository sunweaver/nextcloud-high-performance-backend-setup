all: check_root
	@echo "Execute 'sudo make install' to start the setup."

check_root:
	@if ! [ "$(shell id -u)" = 0 ]; then \
		echo "You are not root, run this target as root please"; \
		exit 1; \
	fi

clean: check_root
	-rm *.log
	-rm -r tmp/
	-rm -r nats-server-v*-linux-amd64/ *.patch coturn-master/ nextcloud-spreed-signaling-master/ *.tar.gz*
	@echo "Clean done"

install: check_root clean
	./setup-nextcloud-hpb.sh
