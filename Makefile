# make build     bundle src/ into dist/
# make check     fail if dist/ is out of date or the version doesn't match VERSION
# make test      run the tests in tests/
# make version   stamp a new CalVer (UTC+8), or make version V=2026.09.30.12.00
# make template  rebuild the ESOUI database template from your own database and 30-day history

.PHONY: build check test version template

build:
	@bash scripts/build.sh

check:
	@bash scripts/build.sh --check

test: build
	@bash tests/run.sh

version:
	@bash scripts/bump-version.sh $(V)
	@bash scripts/build.sh

template:
	@bash scripts/build-template.sh "$(or $(SRC),-)" "$(or $(OUT),-)" "$(V)"
