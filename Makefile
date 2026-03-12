
# Repo/Branch to clone from
# Defaults to the master branch of the base CoreDNS repo
COREDNS_GIT_REPO:=https://github.com/coredns/coredns
COREDNS_GIT_BRANCH:=master

# What linux architectures to build TARs and Docker Images for
# This is more or less bound to only linux getting a custom list due to CoreDNS native make files
#LINUX_ARCH:=amd64 arm arm64 mips64le ppc64le s390x mips riscv64
LINUX_ARCH:=amd64 arm arm64 riscv64

##
# If you are wishing to push the tarballs to a Github Repo's Releases you will need to populate the following values.
##

# Default version used for the releases will be that of the CoreDNS repo.
COREDNS_VERSION=$(shell grep 'CoreVersion' ./coredns/coremain/version.go | awk '{ print $$3 }' | tr -d '"')
CUSTOMIZED_VERSION?=
VERSION=$(CUSTOMIZED_VERSION)-$(COREDNS_VERSION)

# Github Repo
# Examples: username/repo or github.com/username/repo
GITHUB_REPO=$(shell gh repo view --json url -t '{{.url}}')

##
# If you intend to do any docker image builds and push's.
# You will need to define the below variables
##

DOCKER_REPO?=
DOCKER_NAME?=coredns
DOCKER_IMAGE_NAME:=$(DOCKER_REPO)/$(DOCKER_NAME)

##
# Packaging Variables
##

MAINTAINER_NAME=$(shell git config user.name)
MAINTAINER_EMAIL=$(shell git config user.email)

##
# Common Build Targets
##

.PHONY: clean
clean:
	rm -Rf ./coredns

.PHONY: setup
setup: clean
	git clone -b $(COREDNS_GIT_BRANCH) $(COREDNS_GIT_REPO)

.PHONY: build-override
build-override: setup
	rm ./coredns/plugin.cfg
	cp plugin.cfg ./coredns/plugin.cfg
	while read line; do \
		env -C ./coredns go get $${line##*:}; \
	done < plugin.cfg
	env -C ./coredns go generate
	env -C ./coredns make -f Makefile.release build LINUX_ARCH='$(LINUX_ARCH)'

.PHONY: build-append
build-append: setup
	cat plugin.cfg >> ./coredns/plugin.cfg
	while read -r line; do \
		echo "Package - $${line##*:}"; \
		env -C ./coredns go get $${line##*:}; \
	done < plugin.cfg
	env -C ./coredns go generate
	env -C ./coredns make -f Makefile.release build LINUX_ARCH='$(LINUX_ARCH)'

##
# Tarball and Tarball Release Targets
#
# Create Tarballs & SHA256 Checksums
##

.PHONY: tar
tar:
	env -C ./coredns make -f Makefile.release tar LINUX_ARCH='$(LINUX_ARCH)'
	for asset in `ls -A ./coredns/release/*tgz`; do \
		sha256sum $${asset} > $${asset}.sha256;\
	done

##
# Github Targets
#
# Create Releases, Upload the Tarballs and Checksums, and Publish the Release
##
.PHONY: github-create-release
github-create-release:
	gh release create $(VERSION) --generate-notes --draft --repo $(GITHUB_REPO)
	

.PHONY: github-upload
github-upload:
	gh release upload $(VERSION) ./coredns/release/* --repo $(GITHUB_REPO)

.PHONY: github-publish-release
github-publish-release:
	gh release edit  $(VERSION) --draft=false  --repo $(GITHUB_REPO)

##
# Docker Build and Release Targets
##

# Create Build Dirs for each Architecture
.PHONY: setup-docker
setup-docker:
	for arch in $(LINUX_ARCH); do \
		mkdir -p ./coredns/build/docker/$${arch}; \
		cp ./coredns/build/linux/$${arch}/coredns ./coredns/build/docker/$${arch}/coredns; \
		cp ./coredns/Dockerfile ./coredns/build/docker/$${arch} ; \
	done

.PHONY: docker-build
docker-build: setup-docker
ifeq ($(DOCKER_REPO),)
	$(error "Please specify Docker registry to use. Use `DOCKER_REPO=coredns` for releases")
else
	docker version
	for arch in $(LINUX_ARCH); do \
	    DOCKER_ARGS=""; \
	    if [ "$${arch}" = "riscv64" ]; then \
	        DOCKER_ARGS="--build-arg=DEBIAN_IMAGE=debian:unstable-slim --build-arg=BASE=ghcr.io/go-riscv/distroless/static-unstable:nonroot"; \
	    fi; \
	    DOCKER_BUILDKIT=1 docker build --provenance false --platform=linux/$${arch} -t $(DOCKER_IMAGE_NAME):$${arch}-$(VERSION) $${DOCKER_ARGS} ./coredns/build/docker/$${arch} ;\
	done
endif
# We don't call the in docker-build from CoreDNS directly since they don't define the OS, `--provenance false`.
# Which prevent the usage of any other OS from doing the docker builts. 
# E.G. If you attempt to build on MacOS it'll fail.
#	env -C ./coredns make -f Makefile.docker docker-build LINUX_ARCH='$(LINUX_ARCH)' VERSION='$(VERSION)' DOCKER='$(DOCKER_REPO)' NAME='$(DOCKER_NAME)'

.PHONY: docker-push
docker-push:
	env -C ./coredns make -f Makefile.docker docker-push LINUX_ARCH='$(LINUX_ARCH)' VERSION='$(VERSION)'  DOCKER='$(DOCKER_REPO)' NAME='$(DOCKER_NAME)'

##
# Debian Packaging Targets
#
# NOTE: Debian Packaging is in development/early-release
##

.PHONY: package-deb
package-deb:
	rm -Rf ./coredns/package/deb
	for arch in $(LINUX_ARCH); do \
		mkdir -p ./coredns/package/deb/coredns_$${arch}/usr/local/coredns/bin ;\
		mkdir -p ./coredns/package/deb/coredns_$${arch}/usr/local/coredns/etc ;\
		mkdir -p ./coredns/package/deb/coredns_$${arch}/etc/coredns ;\
		mkdir -p ./coredns/package/deb/coredns_$${arch}/etc/systemd/system/ ;\
		mkdir -p ./coredns/package/deb/coredns_$${arch}/DEBIAN ;\
		cp packaging/Corefile ./coredns/package/deb/coredns_$${arch}/usr/local/coredns/etc/Corefile ;\
		cp packaging/coredns.service ./coredns/package/deb/coredns_$${arch}/etc/systemd/system/coredns.service ;\
		cp ./coredns/build/linux/$${arch}/coredns ./coredns/package/deb/coredns_$${arch}/usr/local/coredns/bin/coredns ;\
		cat packaging/control.j2 | sed -e "s/{{VERSION}}/$(VERSION)/" | sed -e "s/{{ARCHITECTURE}}/$${arch}/" | sed -e "s/{{MAINTAINER_NAME}}/$(MAINTAINER_NAME)/" | sed -e "s/{{MAINTAINER_EMAIL}}/$(MAINTAINER_EMAIL)/" > ./coredns/package/deb/coredns_$${arch}/DEBIAN/control ;\
		dpkg-deb -b --root-owner-group ./coredns/package/deb/coredns_$${arch} ./coredns/release/coredns_$(VERSION)_$${arch}.deb ;\
		sha256sum ./coredns/release/coredns_$(VERSION)_$${arch}.deb > ./coredns/release/coredns_$(VERSION)_$${arch}.deb.sha256 ;\
	done
