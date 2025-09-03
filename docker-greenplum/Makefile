GPDB_6_VERSIONS = 6.27.1
TAG_GPDB_6 ?= 6.27.1
GPDB_7_VERSIONS = 7.1.0
TAG_GPDB_7 ?= 7.1.0
UBUNTU_OS_VERSION = ubuntu22.04
OL_OS_VERSION = oraclelinux8
UID := $(shell id -u)
GID := $(shell id -g)

all: $(GPDB_6_VERSIONS) $(GPDB_7_VERSIONS)

.PHONY: $(GPDB_6_VERSIONS)
$(GPDB_6_VERSIONS):
	$(call build_image,6,$@,$(UBUNTU_OS_VERSION))

.PHONY: $(GPDB_7_VERSIONS)
$(GPDB_7_VERSIONS):
	$(call build_image,7,$@,$(UBUNTU_OS_VERSION))

.PHONY: build_gpdb_6_ubuntu
build_gpdb_6_ubuntu:
	$(call build_image_with_tag,6,$(TAG_GPDB_6),$(UBUNTU_OS_VERSION))

.PHONY: build_gpdb_7_ubuntu
build_gpdb_7_ubuntu:
	$(call build_image_with_tag,7,$(TAG_GPDB_7),$(UBUNTU_OS_VERSION))

.PHONY: build_gpdb_6_oraclelinux
build_gpdb_6_oraclelinux:
	$(call build_image_with_tag,6,$(TAG_GPDB_6),$(OL_OS_VERSION))
	
.PHONY: build_gpdb_7_oraclelinux
build_gpdb_7_oraclelinux:
	$(call build_image_with_tag,7,$(TAG_GPDB_7),$(OL_OS_VERSION))

.PHONY: test-e2e
test-e2e:
	$(MAKE) -C e2e-tests test-e2e

.PHONY: test-e2e-walg
test-e2e-walg:
	$(MAKE) -C e2e-tests test-e2e-walg


define build_image
	@echo "Build GPDB $(1):$(2) $(3) docker image"
	docker buildx build -f docker/$(3)/$(1)/Dockerfile --build-arg GPDB_VERSION=$(2) -t greenplum:$(2) .
endef

define build_image_with_tag
	@echo "Build GPDB $(1):$(2) $(3) docker image"
	docker buildx build -f docker/$(3)/$(1)/Dockerfile --build-arg GPDB_VERSION=$(2) -t greenplum:$(2)-$(3) .
endef

