
# Repo/Branch to clone from
# Defaults to the master branch of the base CoreDNS repo
GIT_REPO:=https://github.com/coredns/coredns
GIT_BRANCH:=master

# What linux architectures to build TARs and Docker Images for
# This is more or less bound to only linux getting a custom list due to CoreDNS native make files
#LINUX_ARCH:=amd64 arm arm64 mips64le ppc64le s390x mips riscv64
LINUX_ARCH:=amd64 arm arm64 riscv64

##
# If you are wishing to push the tarballs to a Github Repo's Releases you will need to populate the following values.
##

# Default version used for the releases will be that of the CoreDNS repo.
VERSION=$(shell grep 'CoreVersion' ./coredns/coremain/version.go | awk '{ print $$3 }' | tr -d '"')

# Access token for authentication to Github APIs
GITHUB_ACCESS_TOKEN?=
# Github ID aka Username/Company that owns the repo
GITHUB_OWNER?=
# Github Repo Name
GITHUB_REPO_NAME?=

##
# If you intend to do any docker image builds and push's.
# You will need to define the below variables
##

DOCKER_REPO?=
DOCKER_NAME?=coredns
DOCKER_IMAGE_NAME:=$(DOCKER_REPO)/$(DOCKER_NAME)


##
# Common Build Targets
##

.PHONY: setup
setup:
	rm -Rf ./coredns
	git clone -b $(GIT_BRANCH) $(GIT_REPO)

.PHONY: build-override
build-override: setup
	rm ./coredns/plugin.cfg
	cp plugin.cfg ./coredns/plugin.cfg
	env -C ./coredns make -f Makefile.release build LINUX_ARCH='$(LINUX_ARCH)'


.PHONY: build-append
build-append: setup
	cat plugin.cfg >> ./coredns/plugin.cfg
	env -C ./coredns make -f Makefile.release build LINUX_ARCH='$(LINUX_ARCH)'

##
# Tarball and Tarball Release Targets
##

.PHONY: tar
tar:
	env -C ./coredns make -f Makefile.release tar LINUX_ARCH='$(LINUX_ARCH)'

.PHONY: github-push
github-push:
	env -C ./coredns make -f Makefile.release github-push VERSION='$(VERSION)' GITHUB='$(GITHUB_OWNER)' NAME='$(GITHUB_REPO_NAME)' GITHUB_ACCESS_TOKEN='$(GITHUB_ACCESS_TOKEN)'

##
# Docker Build and Release Targets
##

.PHONY: setup-docker
setup-docker:
	for arch in $(LINUX_ARCH); do \
		mkdir -p ./coredns/build/docker/$${arch}; \
		cp ./coredns/build/linux/$${arch}/coredns ./coredns/build/docker/$${arch}/coredns; \
	done

.PHONY: docker-build
docker-build: setup-docker
ifeq ($(DOCKER_REPO),)
	$(error "Please specify Docker registry to use. Use DOCKER_REPO=coredns for releases")
else
	docker version
	for arch in $(LINUX_ARCH); do \
	    cp ./coredns/Dockerfile ./coredns/build/docker/$${arch} ; \
	    DOCKER_ARGS=""; \
	    if [ "$${arch}" = "riscv64" ]; then \
	        DOCKER_ARGS="--build-arg=DEBIAN_IMAGE=debian:unstable-slim --build-arg=BASE=ghcr.io/go-riscv/distroless/static-unstable:nonroot"; \
	    fi; \
	    DOCKER_BUILDKIT=1 docker build --provenance false --platform=linux/$${arch} -t $(DOCKER_IMAGE_NAME):$${arch}-$(VERSION) $${DOCKER_ARGS} ./coredns/build/docker/$${arch} ;\
	done
endif
# We don't call the in docker-build from CoreDNS since they don't define the OS.
# Which prevent the usage of any other OS from doing the docker builts. 
# E.G. If you attempt to build on MacOS it'll fail.
#	env -C ./coredns make -f Makefile.docker docker-build LINUX_ARCH='$(LINUX_ARCH)' VERSION='$(VERSION)' DOCKER='$(DOCKER_REPO)' NAME='$(DOCKER_NAME)'

.PHONY: docker-push
docker-push:
	env -C ./coredns make -f Makefile.docker docker-push LINUX_ARCH='$(LINUX_ARCH)' VERSION='$(VERSION)'  DOCKER='$(DOCKER_REPO)' NAME='$(DOCKER_NAME)'

.PHONY: clean
clean:
	rm -Rf ./coredns