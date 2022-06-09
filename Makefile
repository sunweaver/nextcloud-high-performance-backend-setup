all: check_root clean
	@echo "Execute 'sudo make install' to start the setup."

check_root:
	@if ! [ "$(shell id -u)" = 0 ]; then \
		echo "You are not root, run this target as root please"; \
		exit 1; \
	fi

clean: check_root
	-rm *.log
	-rm -r tmp/
	@echo "Clean done"

install: check_root clean
	sudo ./setup-nextcloud-hpb.sh
