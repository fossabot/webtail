## webtail Makefile:
## Tail [log]files via web
#:

SHELL          = /bin/bash

# -----------------------------------------------------------------------------
# Build config

GO            ?= go
# not supported in BusyBox v1.26.2
SOURCES        = worker/*.go *.go

BUILD_DATE    ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF       ?= $(shell git rev-parse --short HEAD)
APP_VERSION   ?= $(shell git describe --tags --always)
GOLANG_VERSION = 1.15.5-alpine3.12

OS            ?= linux
ARCH          ?= amd64
ALLARCH       ?= "linux/amd64 linux/386 darwin/386"
DIRDIST       ?= dist

# -----------------------------------------------------------------------------
# Docker image config

# application name, docker-compose prefix
PRG           ?= $(shell basename $$PWD)

# Hardcoded in docker-compose.yml service name
DC_SERVICE    ?= app

# Generated docker image
DC_IMAGE      ?= webtail

# docker-compose image version
DC_VER        ?= latest

# docker app for change inside containers
DOCKER_BIN    ?= docker

# docker app log files directory
LOG_DIR       ?= /var/log

# -----------------------------------------------------------------------------
# App config

# Docker container port
SERVER_PORT   ?= 8080

# -----------------------------------------------------------------------------

.PHONY: all doc gen build-standalone coverage cov-html build test lint fmt vet vendor up down build-docker clean-docker

# default: show target list
all: help

# ------------------------------------------------------------------------------
## Compile operations
#:

## Generate embedded html/
gen:
	$(GO) generate ./cmd/webtail/...

## Run lint
lint:
	@golint ./...
	@golangci-lint run ./...

## Run vet
vet:
	$(GO) vet ./...

## Run tests
test: gen
	$(GO) test -coverprofile=coverage.out ./...

## Show package coverage in html (make cov-html PKG=counter)
cov-html:
	$(GO) tool cover -html=coverage.out

## Build app
build: gen $(PRG)

## Build webtail command
$(PRG): cmd/webtail/*.go $(SOURCES)
	GOOS=$(OS) GOARCH=$(ARCH) $(GO) build -v -o $@ -ldflags \
	  "-X main.built=$(BUILD_DATE) -X main.version=$(APP_VERSION)" ./cmd/$@

## Build like docker image from scratch
build-standalone: lint vet test
	GOOS=linux CGO_ENABLED=0 $(GO) build -a -v -o $(PRG) -ldflags \
	  "-X main.built=$(BUILD_DATE) -X main.version=$(APP_VERSION)" ./cmd/$(PRG)

## build and run in foreground
run: build
	./$(PRG) --log_level debug --root log/ --html html --trace

run-abs: build
	./$(PRG) --log_level debug --root $$PWD/log/ --html html --trace

doc:
	@echo "Open http://localhost:6060/pkg/LeKovr/webtail"
	@godoc -http=:6060

# ------------------------------------------------------------------------------
## Prepare distros
#:

## build app for all platforms
buildall: lint vet
	@echo "*** $@ ***" ; \
	  for a in "$(ALLARCH)" ; do \
	    echo "** $${a%/*} $${a#*/}" ; \
	    P=$(PRG)_$${a%/*}_$${a#*/} ; \
	    GOOS=$${a%/*} GOARCH=$${a#*/} $(GO) build -o $$P -ldflags \
	      "-X main.built=$(BUILD_DATE) -X main.version=$(APP_VERSION)" ./cmd/$(PRG) ; \
	  done

## create disro files
dist: clean buildall
	@echo "*** $@ ***"
	@[ -d $(DIRDIST) ] || mkdir $(DIRDIST)
	@sha256sum $(PRG)_* > $(DIRDIST)/SHA256SUMS ; \
	  for a in "$(ALLARCH)" ; do \
	    echo "** $${a%/*} $${a#*/}" ; \
	    P=$(PRG)_$${a%/*}_$${a#*/} ; \
	    zip "$(DIRDIST)/$$P.zip" "$$P" README.md ; \
	  done

## clean generated files
clean:
	@echo "*** $@ ***" ; \
	  for a in "$(ALLARCH)" ; do \
	    P=$(PRG)_$${a%/*}_$${a#*/} ; \
	    [ -f $$P ] && rm $$P || true ; \
	  done
	@[ -d $(DIRDIST) ] && rm -rf $(DIRDIST) || true
	@[ -f $(PRG) ] && rm -f $(PRG) || true

# ------------------------------------------------------------------------------
## Docker operations
#:

## Start service in container
up:
up: CMD="up -d $(DC_SERVICE)"
up: dc

## Stop service
down:
down: CMD="rm -f -s $(DC_SERVICE)"
down: dc

## Build docker image
build-docker: CMD="build --no-cache --force-rm $(DC_SERVICE)"
build-docker: dc

## Remove docker image & temp files
clean-docker:
	[[ "$$($(DOCKER_BIN) images -q $(DC_IMAGE) 2> /dev/null)" == "" ]] || $(DOCKER_BIN) rmi $(DC_IMAGE)

# ------------------------------------------------------------------------------

# $$PWD usage allows host directory mounts in child containers
# Thish works if path is the same for host, docker, docker-compose and child container
## run $(CMD) via docker-compose
dc: docker-compose.yml
	@$(DOCKER_BIN) run --rm  -i \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $$PWD:$$PWD -w $$PWD \
  --env=SERVER_PORT=$(SERVER_PORT) \
  --env=LOG_DIR=$(LOG_DIR) \
  --env=DC_IMAGE=$(DC_IMAGE) \
  --env=BUILD_DATE=$(BUILD_DATE) \
  --env=VCS_REF=$(VCS_REF) \
  --env=APP_VERSION=$(APP_VERSION) \
  --env=GOLANG_VERSION=$(GOLANG_VERSION) \
  docker/compose:$(DC_VER) \
  -p $(PRG) \
  "$(CMD)"

# ------------------------------------------------------------------------------
## Other
#:

# This code handles group header and target comment with one or two lines only
## list Makefile targets
## (this is default target)
help:
	@grep -A 1 -h "^## " $(MAKEFILE_LIST) \
  | sed -E 's/^--$$// ; /./{H;$$!d} ; x ; s/^\n## ([^\n]+)\n(## (.+)\n)*(.+):(.*)$$/"    " "\4" "\1" "\3"/' \
  | sed -E 's/^"    " "#" "(.+)" "(.*)"$$/"" "" "" ""\n"\1 \2" "" "" ""/' \
  | xargs printf "%s\033[36m%-15s\033[0m %s %s\n"
