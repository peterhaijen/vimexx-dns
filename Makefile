# Detecteer of 'docker ps' werkt zonder sudo; anders gebruik 'sudo docker'
DOCKER := $(shell if docker ps > /dev/null 2>&1; then echo docker; else echo sudo docker; fi)

# Directory waar Dockerfiles staan
DOCKER_DIR := docker

# Vind alle Dockerfile.* bestanden
DOCKERFILES := $(wildcard $(DOCKER_DIR)/Dockerfile.[a-z]$)

# Haal de image-namen eruit (bijv. Dockerfile.app → app)
IMAGES := $(patsubst $(DOCKER_DIR)/Dockerfile.%,%, $(DOCKERFILES))

# Basisnaam van de image zonder tag
IMAGE_PREFIX := 2kman/vimexx-ddns-client

# Stabilizing 1.0         1.0~rc1, 1.0~beta2
# After 1.0 release       1.1~devYYYYMMDD
# Patching 1.0            1.0.1, 1.0.2
# Testing 1.1 pre-release 1.1~beta1, 1.1~rc1
# Final release           1.1, 1.2, etc.

# Versie
BASE_VERSION := 1.3.0

DATE_FILE := .stamp

# Uncomment for development builds
#DATE := $(shell [ -f $(DATE_FILE) ] && cat $(DATE_FILE) || date +%Y%m%d%H%M)

# Projectnaam en architectuur
PACKAGE := vimexx-dns
ARCH := all

ifndef DATE
DEB_VERSION := $(BASE_VERSION)
DOCKER_VERSION := $(BASE_VERSION)
else
DEB_VERSION := $(BASE_VERSION)~dev$(DATE)
DOCKER_VERSION := $(BASE_VERSION)-dev$(DATE)
endif

DEB=$(PACKAGE)_$(DEB_VERSION)_$(ARCH).deb
BUILD_DIR=$(PACKAGE)_$(DEB_VERSION)

# --- Default target ---
.PHONY: all
all: build

# --- Generate build timestamp file ---
.PHONY: versionstamp
versionstamp:
	@if [ -n "$(DATE)" ] && [ ! -f $(DATE_FILE) ]; then \
		echo "📦 Writing timestamp $(DATE) to $(DATE_FILE)"; \
		echo "$(DATE)" > $(DATE_FILE); \
	fi

# --- Generate script with embedded version ---
script: versionstamp vimexx-dns

vimexx-dns: vimexx-dns.in Makefile
	sed 's/@VERSION@/$(DEB_VERSION)/g' vimexx-dns.in > vimexx-dns
	chmod +x vimexx-dns

# --- Build alle images ---
.PHONY: build
build: script $(IMAGES:%=build-%)

build-%:
	$(DOCKER) build -f $(DOCKER_DIR)/Dockerfile.$* \
		-t $(IMAGE_PREFIX):$* \
		-t $(IMAGE_PREFIX):$*-$(DOCKER_VERSION) .

# --- Push alle images ---
.PHONY: push
push:
	@for image in $(IMAGES); do \
		echo "🚀 Pushing $(IMAGE_PREFIX):$$image"; \
		$(DOCKER) push $(IMAGE_PREFIX):$$image; \
		$(DOCKER) push $(IMAGE_PREFIX):$$image-$(DOCKER_VERSION); \
	done

# --- Clean images and generated files ---
.PHONY: clean
clean:
	@echo "🧹 Cleaning Docker images with prefix $(IMAGE_PREFIX)..."
	@$(DOCKER) images --format '{{.Repository}}:{{.Tag}}' | grep '^$(IMAGE_PREFIX):' | while read img; do \
		echo "🗑️ Removing image: $$img"; \
		$(DOCKER) rmi -f $$img; \
	done || true
	@rm -f vimexx-dns
	@rm -rf $(PACKAGE)_*
	@rm -f *.deb
	@rm -f $(DATE_FILE)

# --- Git Tag ---
.PHONY: tag
tag:
	@if git rev-parse "v$(DEB_VERSION)" >/dev/null 2>&1; then \
		echo "❌ Git tag v$(DEB_VERSION) already exists. Aborting."; \
		exit 1; \
	else \
		echo "🏷️ Creating Git tag v$(DEB_VERSION)..."; \
		git tag -a v$(DEB_VERSION) -m "Release version $(DEB_VERSION)"; \
		echo "✅ Git tag v$(DEB_VERSION) created."; \
	fi

# --- Push Git branch en tags ---
.PHONY: push-git
push-git:
	@current_branch=$$(git rev-parse --abbrev-ref HEAD); \
	echo "🌐 Pushing branch '$$current_branch' to origin..."; \
	git push origin $$current_branch; \
	echo "🏷️ Pushing tags to origin..."; \
	git push origin --tags; \
	echo "✅ Successfully pushed branch and tags."

# --- Container management (start en stop) ---
.PHONY: start-%
start-%:
	@if [ ! -f docker/env ]; then \
		echo "❌ Error: 'env' file not found. Cannot start container."; \
		exit 1; \
	fi
	@if [ ! -f conf ]; then \
		echo "❌ Error: 'conf' file not found. Cannot start container."; \
		exit 1; \
	fi
	$(DOCKER) run -dt --rm -v $(CURDIR)/conf:/etc/vimexx-dns.conf:ro --env-file docker/env --name $* $(IMAGE_PREFIX):$*-$(DOCKER_VERSION)

.PHONY: stop-%
stop-%:
	$(DOCKER) stop $* || true

.PHONY: start stop
start: $(IMAGES:%=start-%)
stop:  $(IMAGES:%=stop-%)

# --- Build DEB package ---
.PHONY: deb
deb: script
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/DEBIAN
	mkdir -p $(BUILD_DIR)/usr/local/bin
	mkdir -p $(BUILD_DIR)/etc

	cp vimexx-dns $(BUILD_DIR)/usr/local/bin/vimexx-dns
	cp conf.example $(BUILD_DIR)/etc/vimexx-ddns.conf

	echo "Package: $(PACKAGE)" > $(BUILD_DIR)/DEBIAN/control
	echo "Version: $(DEB_VERSION)" >> $(BUILD_DIR)/DEBIAN/control
	echo "Section: admin" >> $(BUILD_DIR)/DEBIAN/control
	echo "Priority: optional" >> $(BUILD_DIR)/DEBIAN/control
	echo "Architecture: $(ARCH)" >> $(BUILD_DIR)/DEBIAN/control
	echo "Maintainer: Peter Haijen <your@email.com>" >> $(BUILD_DIR)/DEBIAN/control
	echo "Depends: perl, libappconfig-std-perl, liblwp-protocol-https-perl, libjson-perl, libnet-dns-perl" >> $(BUILD_DIR)/DEBIAN/control
	echo "Description: Add/update Vimexx DNS entries" >> $(BUILD_DIR)/DEBIAN/control

	dpkg-deb --build $(BUILD_DIR) $(DEB)
