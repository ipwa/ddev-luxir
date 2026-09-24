#!/usr/bin/env bats

# Run with: bats tests/test.bats   (needs DDEV and Docker; -tags '!release' for local iteration)

setup() {
  set -eu -o pipefail
  export GITHUB_REPO=ipwa/ddev-luxir
  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export TESTDIR=$(mktemp -d -t testluxir-XXXXXXXXXX)
  export PROJNAME="test-luxir-$$"
  export DDEV_NON_INTERACTIVE=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --project-type=php --docroot=web >/dev/null
  mkdir -p web && echo "ok" > web/index.php
}

teardown() {
  set -eu -o pipefail
  cd "${TESTDIR}" || true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
}

health_check() {
  run ddev exec curl -fsS http://luxir:9400/health
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
}

@test "install from directory" {
  set -eu -o pipefail
  cd "${TESTDIR}"
  ddev add-on get "${DIR}"
  ddev restart
  health_check

  ddev exec "curl -fsS -XPOST http://luxir:9400/collections/_create -d '{\"name\":\"demo\",\"schema\":{\"fields\":{\"title_t\":{\"type\":\"text\",\"analyzer\":{\"tokenizer\":\"unicode_word\",\"filters\":[\"nfkc_cf\"]}}}}}'"
  cp "${DIR}/tests/testdata/books.ndjson" "${TESTDIR}/books.ndjson"
  run ddev luxir POST /collections/demo/_update @books.ndjson
  [[ "$output" == *'"status": "ok"'* ]]
  run ddev luxir /collections/demo/_search '{"query":"title_t:dune","get_number":true}'
  [[ "$output" == *'"found": 2'* ]]

  # Data survives a restart.
  ddev restart
  health_check
  run ddev luxir /collections/demo/_search '{"query":"title_t:dune","get_number":true}'
  [[ "$output" == *'"found": 2'* ]]

  run ddev luxir-status
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo"* ]]
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  [ -n "${RELEASE_TEST:-}" ] || skip "no release yet; set RELEASE_TEST=1"
  cd "${TESTDIR}"
  ddev add-on get "${GITHUB_REPO}"
  ddev restart
  health_check
}

@test "version pin consistency" {
  set -eu -o pipefail
  dockerfile=$(sed -n 's/^ARG LUXIR_VERSION=//p' "${DIR}/luxir/Dockerfile")
  compose=$(sed -n 's/.*LUXIR_VERSION: \${LUXIR_VERSION:-\(.*\)}/\1/p' "${DIR}/docker-compose.luxir.yaml" | head -n1)
  [ -n "$dockerfile" ]
  [ "$dockerfile" = "$compose" ]
}
