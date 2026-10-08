PYTHON ?= python3

.PHONY: build build-legacy test verify project
build:
	$(PYTHON) scripts/build.py

test:
	$(PYTHON) -m unittest discover -s tests -v
	$(PYTHON) scripts/test_native.py
	$(PYTHON) scripts/test_command_safety.py

verify: build test
	$(PYTHON) scripts/verify_package.py

build-legacy:
	$(PYTHON) scripts/build_legacy.py

project:
	xcodegen generate
