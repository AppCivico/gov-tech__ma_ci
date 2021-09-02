APP = dispatcher-server
OUTPUT_DIR ?= bin

CMD = ./...

BIN ?= $(OUTPUT_DIR)/$(APP)

GO_FLAGS ?= -v -mod=vendor

ARGS ?=

.PHONY: $(BIN)
$(BIN):
	go build $(GO_FLAGS) -ldflags '-s -w' -o $(BIN) $(CMD)
	echo -n $(APP) > $(OUTPUT_DIR)/README.txt
	echo -n " was built for " >> $(OUTPUT_DIR)/README.txt
	dpkg --print-architecture >> $(OUTPUT_DIR)/README.txt

build: $(BIN)

clean:
	rm -rf "$(OUTPUT_DIR)" || true

