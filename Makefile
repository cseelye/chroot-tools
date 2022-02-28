SHELL = /bin/bash

.DEFAULT_GOAL := deb

container:
	docker image build -t deb-tools .

deb: container
	docker container run --rm -it -v $$(pwd):/work -w /work deb-tools ./make-deb

clean:
	$(RM) *.deb
