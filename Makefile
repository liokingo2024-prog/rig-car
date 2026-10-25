FLUTTER ?= flutter

.PHONY: test analyze build-web run

test:
	$(FLUTTER) test

analyze:
	$(FLUTTER) analyze

build-web:
	$(FLUTTER) build web --release

run:
	$(FLUTTER) run -d chrome
