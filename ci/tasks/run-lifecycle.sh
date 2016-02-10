#!/usr/bin/env bash

set -e
set -o pipefail

source bosh-cpi-release/ci/tasks/utils.sh

ensure_not_replace_value BOSH_OPENSTACK_DOMAIN
ensure_not_replace_value BOSH_OPENSTACK_AUTH_URL_V2
ensure_not_replace_value BOSH_OPENSTACK_AUTH_URL_V3
ensure_not_replace_value BOSH_OPENSTACK_USERNAME
ensure_not_replace_value BOSH_OPENSTACK_API_KEY
ensure_not_replace_value BOSH_OPENSTACK_USERNAME_V3
ensure_not_replace_value BOSH_OPENSTACK_API_KEY_V3
ensure_not_replace_value BOSH_OPENSTACK_TENANT
ensure_not_replace_value BOSH_OPENSTACK_PROJECT
ensure_not_replace_value BOSH_OPENSTACK_MANUAL_IP
ensure_not_replace_value BOSH_OPENSTACK_NET_ID
ensure_not_replace_value BOSH_OPENSTACK_DEFAULT_KEY_NAME
ensure_not_replace_value BOSH_CLI_SILENCE_SLOW_LOAD_WARNING
ensure_not_replace_value BOSH_OPENSTACK_VOLUME_TYPE
ensure_not_replace_value BOSH_OPENSTACK_CONNECT_TIMEOUT
ensure_not_replace_value BOSH_OPENSTACK_READ_TIMEOUT
ensure_not_replace_value BOSH_OPENSTACK_WRITE_TIMEOUT
optional_value BOSH_OPENSTACK_CA_CERT

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

mkdir "$PWD/openstack-lifecycle-stemcell/stemcell"
tar -C "$PWD/openstack-lifecycle-stemcell/stemcell" -xzf "$PWD/openstack-lifecycle-stemcell/stemcell.tgz"
export BOSH_OPENSTACK_STEMCELL_PATH="$PWD/openstack-lifecycle-stemcell/stemcell"

cd bosh-cpi-release/src/bosh_openstack_cpi

bundle install
bundle exec rspec spec/integration 2>&1 | tee ../../../output/lifecycle.log
