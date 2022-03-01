SHELL = /bin/bash

.DEFAULT_GOAL := deb

INTERACTIVE:=$(shell [ -t 0 ] && echo 1)
ifeq ($(INTERACTIVE),1)
	TTY = --tty
else
	TTY =
endif

container:
	docker image build -t deb-tools .

deb: container
	docker container run \
        --rm \
        --interactive \
        $(TTY) \
        --init \
        --volume $$(pwd):/work \
        --work-dir /work \
        --name chroot-tools-build \
        deb-tools \
        ./make-deb

clean:
	$(RM) *.deb

