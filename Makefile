all: clean install

clean:
	-rm *.log
	-rm -r tmp/
	echo Clean done

install:
	sudo ./setup-nextcloud-hpb.sh