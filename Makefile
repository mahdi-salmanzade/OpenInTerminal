PYTHON ?= python3

.PHONY: build test verify
build:
	$(PYTHON) scripts/build.py

test:
	$(PYTHON) -m unittest discover -s tests -v

verify: build test
	$(PYTHON) scripts/verify_package.py
