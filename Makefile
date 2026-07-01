CC ?= gcc
PKG_CONFIG ?= pkg-config
SRC_DIR := src/basic-tutorial
BIN_DIR := bin

GST_PKGS := gstreamer-1.0
GTK_PKGS := gtk+-3.0 gstreamer-1.0
GST_AUDIO_PKGS := gstreamer-1.0 gstreamer-audio-1.0
GST_PBUTILS_PKGS := gstreamer-1.0 gstreamer-pbutils-1.0

CFLAGS ?= -Wall -Wextra -g
CPPFLAGS :=
LDLIBS :=

TUTORIALS := \
	basic-tutorial-1 \
	basic-tutorial-2 \
	basic-tutorial-3 \
	basic-tutorial-4 \
	basic-tutorial-5 \
	basic-tutorial-6 \
	basic-tutorial-7 \
	basic-tutorial-8 \
	basic-tutorial-9 \
	basic-tutorial-12 \
	basic-tutorial-13

TARGETS := $(addprefix $(BIN_DIR)/,$(TUTORIALS))

.PHONY: all clean $(TUTORIALS)

all: $(TARGETS)

$(TUTORIALS): %: $(BIN_DIR)/%

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

define build_with_pkgs
@$(PKG_CONFIG) --exists $(1) || { \
	echo "Missing pkg-config package(s): $(1)"; \
	echo "Install the corresponding GStreamer/GTK development packages and retry."; \
	exit 1; \
}
$(CC) $(CFLAGS) $$($(PKG_CONFIG) --cflags $(1)) $< -o $@ $$($(PKG_CONFIG) --libs $(1))
endef

$(BIN_DIR)/basic-tutorial-1: $(SRC_DIR)/basic-tutorial-1.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-2: $(SRC_DIR)/basic-tutorial-2.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-3: $(SRC_DIR)/basic-tutorial-3.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-4: $(SRC_DIR)/basic-tutorial-4.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-5: $(SRC_DIR)/basic-tutorial-5.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GTK_PKGS))

$(BIN_DIR)/basic-tutorial-6: $(SRC_DIR)/basic-tutorial-6.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-7: $(SRC_DIR)/basic-tutorial-7.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-8: $(SRC_DIR)/basic-tutorial-8.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_AUDIO_PKGS))

$(BIN_DIR)/basic-tutorial-9: $(SRC_DIR)/basic-tutorial-9.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PBUTILS_PKGS))

$(BIN_DIR)/basic-tutorial-12: $(SRC_DIR)/basic-tutorial-12.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

$(BIN_DIR)/basic-tutorial-13: $(SRC_DIR)/basic-tutorial-13.c | $(BIN_DIR)
	$(call build_with_pkgs,$(GST_PKGS))

clean:
	rm -f $(TARGETS)
