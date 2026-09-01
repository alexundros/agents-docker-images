# ============================================================
# Build/Publish images Makefile
# ============================================================

SHELL           := /usr/bin/bash
.SHELLFLAGS     := -c
FIND            ?= /usr/bin/find
DF_DIR          ?= dockerfiles
BUILD_CONTEXT   ?= .
DIST_DIR        ?= dist
IMAGE_PREFIX    ?=
OCI_SOURCE      ?=
OCI_REVISION    ?= local
REGISTRY        ?=
NAMESPACE       ?= $(notdir $(CURDIR))
PUSH_LATEST     ?= false
ALLOW_OVERWRITE ?= false

# Remote prefix "<registry>/<namespace>/"
ifeq ($(strip $(REGISTRY)),)
REMOTE_PREFIX := $(NAMESPACE)/
else ifeq ($(strip $(NAMESPACE)),)
REMOTE_PREFIX :=
else
REMOTE_PREFIX := $(REGISTRY)/$(NAMESPACE)/
endif

# Discovery (recursive; make 3.81-compatible via find)
# Absolute-ish paths of every versioned Dockerfile.
# -mindepth 3 guarantees at least <name>/<version>/Dockerfile under $(DF_DIR).
DF_PATHS := $(sort $(shell $(FIND) $(DF_DIR) -mindepth 3 -type f -name 'Dockerfile' 2>/dev/null))

# IDs = paths relative to $(DF_DIR), without the Dockerfile filename.
IDS := $(patsubst $(DF_DIR)/%/Dockerfile,%,$(DF_PATHS))

# Per-ID accessors (string ops only; safe at parse time)
# ID = <key>/<version>  (version is the last path component)
id_version = $(notdir $(1))
id_key     = $(patsubst %/,%,$(dir $(1)))
id_name    = $(notdir $(call id_key,$(1)))

dockerfile_path = $(DF_DIR)/$(1)/Dockerfile
meta_path       = $(DF_DIR)/$(1)/.meta

# Read scalar KEY from <ID>/.meta (stripped, first match, inline '#' removed).
meta_get = $(strip $(shell test -f '$(call meta_path,$(1))' && \
	sed -n 's/^[[:space:]]*$(2)[[:space:]]*=[[:space:]]*\(.*\)/\1/p' \
		'$(call meta_path,$(1))' 2>/dev/null \
	| sed -e 's/[[:space:]]*#.*$$//' -e 's/[[:space:]]*$$//' | head -n1))

# Image suffix: meta IMAGE, else NAME (basename).
img_suffix = $(strip $(or $(call meta_get,$(1),IMAGE),$(call id_name,$(1))))
img_name   = $(IMAGE_PREFIX)$(call img_suffix,$(1))

# Refs. Images are tagged with their final remote name during build;
# local_ref is only a fallback when REGISTRY/NAMESPACE are not set.
local_ref  = $(call img_name,$(1)):$(call id_version,$(1))
remote_ref = $(REMOTE_PREFIX)$(call img_name,$(1)):$(call id_version,$(1))
latest_ref = $(REMOTE_PREFIX)$(call img_name,$(1)):latest

# Tag used for the built image: remote when a registry is set, else local.
artifact_ref = $(if $(strip $(REMOTE_PREFIX)),$(call remote_ref,$(1)),$(call local_ref,$(1)))

# Parent base image: remote ref when a registry is set, else local.
parent_base = $(if $(strip $(REMOTE_PREFIX)),$(call remote_ref,$(1)),$(call local_ref,$(1)))

# Extra build args from ARG_* lines.
img_args = $(shell test -f '$(call meta_path,$(1))' && \
	sed -n 's/^[[:space:]]*ARG_\([A-Za-z0-9_]*\)[[:space:]]*=[[:space:]]*\(.*\)/--build-arg \1=\2/p' \
		'$(call meta_path,$(1))' 2>/dev/null | tr '\n' ' ')

# Parent ID (KEY/version) from meta PARENT.
parent_of = $(call meta_get,$(1),PARENT)

# Unique image keys (for aggregate targets like build-node-go).
KEYS := $(sort $(foreach id,$(IDS),$(call id_key,$(id))))

oci_labels = \
	--label "org.opencontainers.image.version=$(call id_version,$(1))" \
	--label "org.opencontainers.image.source=$(OCI_SOURCE)" \
	--label "org.opencontainers.image.revision=$(OCI_REVISION)"

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_./@-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'

# ============================================================
# Validation
# ============================================================
.PHONY: validate
validate: ## Validate layout, duplicate image names and PARENT refs
	@err=0; \
	declare -A seen_name; \
	declare -A seen_id; \
	for id in $(IDS); do \
		case "$$id" in \
			*/*) ;; \
			*) echo "ERROR: invalid layout '$$id'"; err=1; continue;; \
		esac; \
		key="$${id%/*}"; \
		ver="$${id##*/}"; \
		if [ -z "$$ver" ] || [ "$$key" = "$$id" ]; then \
			echo "ERROR: missing version in '$$id'"; err=1; continue; \
		fi; \
		suffix="$$($(MAKE) -s _img-suffix ID=$$id)"; \
		if [ -n "$${seen_name[$$suffix]:-}" ] && [ "$${seen_name[$$suffix]}" != "$$key" ]; then \
			echo "ERROR: duplicate image name '$$suffix' from '$$id' and '$${seen_id[$$suffix]}'."; \
			echo "       Set a distinct IMAGE= in one of their .meta files."; err=1; \
		else \
			seen_name[$$suffix]="$$key"; \
			seen_id[$$suffix]="$$id"; \
		fi; \
	done; \
	for id in $(IDS); do \
		p="$$($(MAKE) -s _parent-of ID=$$id)"; \
		[ -z "$$p" ] && continue; \
		case "$$p" in */*) ;; *) \
			echo "ERROR: PARENT='$$p' in '$$id/.meta' must be '<key>/<version>'"; err=1; continue;; \
		esac; \
		if [ ! -f "$(DF_DIR)/$$p/Dockerfile" ]; then \
			echo "ERROR: PARENT '$$p' (from '$$id') has no $(DF_DIR)/$$p/Dockerfile"; err=1; \
		fi; \
	done; \
	if [ "$$err" = "0" ]; then echo "validate: OK ($(words $(IDS)) image(s))"; else exit 1; fi

.PHONY: _img-suffix _parent-of
_img-suffix:
	@printf '%s\n' "$(call img_suffix,$(ID))"
_parent-of:
	@printf '%s\n' "$(call parent_of,$(ID))"

.PHONY: images
images: ## List discovered images: <ID> -> <image>:<version> [parent]
	@for id in $(IDS); do $(MAKE) -s _describe ID=$$id; done

.PHONY: _describe
_describe:
	@p="$(call parent_of,$(ID))"; \
	if [ -n "$$p" ]; then dep=" (parent: $$p)"; else dep=""; fi; \
	printf '  %-36s -> %s%s\n' "$(ID)" "$(call artifact_ref,$(ID))" "$$dep"

# ============================================================
# Guards
# ============================================================
.PHONY: require-remote
require-remote:
	@if [ -z "$(REMOTE_PREFIX)" ]; then \
		echo "ERROR: set REGISTRY and NAMESPACE, e.g.: "; \
		echo "make $(MAKECMDGOALS) REGISTRY=ghcr.io NAMESPACE=acme"; \
		exit 1; \
	fi

# ============================================================
# Build (per-ID rules + per-KEY aggregates)
# ============================================================
.PHONY: all build
all: build ## Alias for build
build: validate $(addprefix build-,$(IDS)) ## Build all images

# Per-ID build rule (depends on parent ID when PARENT is set).
define BUILD_RULE
.PHONY: build-$(1)
build-$(1): $$(if $$(call parent_of,$(1)),build-$$(call parent_of,$(1))) ## Build $(1)
	docker build -f "$$(call dockerfile_path,$(1))" \
		$$(if $$(call parent_of,$(1)),--build-arg BASE_IMAGE="$$(call parent_base,$$(call parent_of,$(1)))") \
		$$(call img_args,$(1)) $$(call oci_labels,$(1)) -t "$$(call artifact_ref,$(1))" \
		$$(if $$(and $$(strip $(REMOTE_PREFIX)),$$(filter true,$$(PUSH_LATEST))),-t "$$(call latest_ref,$(1))") \
		"$$(BUILD_CONTEXT)"
endef
$(foreach id,$(IDS),$(eval $(call BUILD_RULE,$(id))))

# Per-KEY aggregate: build all versions of a key (e.g. make build-node-go).
define KEY_RULE
.PHONY: build-$(1)
build-$(1): $$(addprefix build-,$$(filter $(1)/%,$$(IDS))) ## Build all versions of $(1)
endef
# Only emit aggregate if the KEY differs from any single ID (avoid target clash).
$(foreach key,$(filter-out $(IDS),$(KEYS)),$(eval $(call KEY_RULE,$(key))))

# ============================================================
# Registry check (overwrite protection)
# ============================================================
.PHONY: check-remote
check-remote: require-remote ## Check :VERSION tags (ALLOW_OVERWRITE=true disables guard)
	@export DOCKER_CLI_EXPERIMENTAL=enabled; \
	exists=0; \
	for id in $(IDS); do \
		ref="$$($(MAKE) -s _remote-ref ID=$$id)"; \
		if docker manifest inspect "$$ref" >/dev/null 2>&1; then \
			echo "FOUND: $$ref already exists"; exists=1; \
		else \
			echo "OK:    $$ref is free"; \
		fi; \
	done; \
	if [ "$$exists" = "1" ]; then \
		if [ "$(ALLOW_OVERWRITE)" = "true" ]; then \
			echo "WARNING: ALLOW_OVERWRITE=true - existing tags will be overwritten"; \
		else \
			echo "ERROR: some versions are already published. \
				Bump versions or pass ALLOW_OVERWRITE=true."; \
			exit 1; \
		fi; \
	fi

.PHONY: _remote-ref
_remote-ref:
	@printf '%s\n' "$(call remote_ref,$(ID))"

# ============================================================
# Publishing
# ============================================================
.PHONY: login
login: ## Log in to the registry (REGISTRY, REGISTRY_USER, REGISTRY_TOKEN)
	@if [ -z "$(REGISTRY)" ]; then echo "ERROR: set REGISTRY"; exit 1; fi; \
	echo "$(REGISTRY_TOKEN)" | docker login "$(REGISTRY)" -u "$(REGISTRY_USER)" \
	--password-stdin

.PHONY: push
push: require-remote check-remote ## Push images (PUSH_LATEST, ALLOW_OVERWRITE)
	@for id in $(IDS); do $(MAKE) -s _push-one ID=$$id; done

.PHONY: _push-one
_push-one:
	@docker push "$(call remote_ref,$(ID))"; \
	if [ "$(PUSH_LATEST)" = "true" ]; then \
		docker push "$(call latest_ref,$(ID))"; \
	fi

.PHONY: release
release: build push ## Full cycle: build + push

# ============================================================
# Save / load
# ============================================================
.PHONY: save
save: ## Save images to $(DIST_DIR)/<image>-<version>.tar.gz
	@mkdir -p "$(DIST_DIR)"; \
	for id in $(IDS); do $(MAKE) -s _save-one ID=$$id; done

.PHONY: _save-one
_save-one:
	@ref="$(call artifact_ref,$(ID))"; \
	out="$(DIST_DIR)/$(call img_name,$(ID))-$(call id_version,$(ID)).tar.gz"; \
	echo "Saving $$ref -> $$out"; docker save "$$ref" | gzip > "$$out"

.PHONY: load
load: ## Load images from $(DIST_DIR)/*.tar.gz
	@shopt -s nullglob; \
	files=("$(DIST_DIR)"/*.tar.gz); \
	if [ $${#files[@]} -eq 0 ]; then echo "No files in $(DIST_DIR)/*.tar.gz"; exit 0; fi; \
	for f in "$${files[@]}"; do echo "Loading $$f"; gunzip -c "$$f" | docker load; done

# ============================================================
# Cleanup
# ============================================================
.PHONY: clean
clean: ## Remove built images
	@for id in $(IDS); do $(MAKE) -s _clean-one ID=$$id; done

.PHONY: _clean-one
_clean-one:
	@refs="$(call artifact_ref,$(ID))"; \
	if [ -n "$(REMOTE_PREFIX)" ]; then \
		refs="$$refs $(call latest_ref,$(ID))"; \
	fi; \
	for ref in $$refs; do docker rmi -f "$$ref" 2>/dev/null || true; done

.PHONY: clean-dist
clean-dist: ## Clean the $(DIST_DIR) directory
	@rm -rf "$(DIST_DIR)"
