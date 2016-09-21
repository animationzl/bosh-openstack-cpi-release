#!/usr/bin/env bash

set -e

source bosh-cpi-src-in/ci/tasks/utils.sh

ensure_not_replace_value bosh_admin_password
ensure_not_replace_value dns
ensure_not_replace_value v3_e2e_flavor
ensure_not_replace_value v3_e2e_connection_timeout
ensure_not_replace_value v3_e2e_read_timeout
ensure_not_replace_value v3_e2e_state_timeout
ensure_not_replace_value v3_e2e_write_timeout
ensure_not_replace_value v3_e2e_bosh_registry_port
ensure_not_replace_value v3_e2e_api_key
ensure_not_replace_value v3_e2e_auth_url
ensure_not_replace_value v3_e2e_default_key_name
ensure_not_replace_value v3_upgrade_director_floating_ip
ensure_not_replace_value v3_upgrade_director_manual_ip
ensure_not_replace_value v3_e2e_net_cidr
ensure_not_replace_value v3_e2e_net_gateway
ensure_not_replace_value v3_e2e_net_id
ensure_not_replace_value v3_e2e_security_group
ensure_not_replace_value v3_e2e_project
ensure_not_replace_value v3_e2e_domain
ensure_not_replace_value v3_e2e_username
ensure_not_replace_value v3_e2e_private_key_data
ensure_not_replace_value old_bosh_release_version
ensure_not_replace_value old_bosh_release_sha1
ensure_not_replace_value old_openstack_cpi_release_version
ensure_not_replace_value old_openstack_cpi_release_sha1
ensure_not_replace_value old_bosh_stemcell_name
ensure_not_replace_value old_bosh_stemcell_version
ensure_not_replace_value old_bosh_stemcell_sha1
ensure_not_replace_value time_server_1
ensure_not_replace_value time_server_2
optional_value bosh_openstack_ca_cert
optional_value distro

source /etc/profile.d/chruby-with-ruby-2.1.2.sh

export BOSH_INIT_LOG_LEVEL=DEBUG

deployment_dir="${PWD}/deployment"
manifest_filename="director-manifest.yml"
private_key=${deployment_dir}/bosh.pem
bosh_vcap_password_hash=$(ruby -e 'require "securerandom";puts ENV["bosh_admin_password"].crypt("$6$#{SecureRandom.base64(14)}")')

echo "setting up artifacts used in $manifest_filename"
mkdir -p ${deployment_dir}
prepare_bosh_release

echo "${v3_e2e_private_key_data}" > ${private_key}
chmod go-r ${private_key}
eval $(ssh-agent)
ssh-add ${private_key}

#create director manifest as heredoc
cat > "${deployment_dir}/${manifest_filename}"<<EOF
---
name: bosh

releases:
  - name: bosh
    url: file://bosh-release.tgz
  - name: bosh-openstack-cpi
    url: http://bosh.io/d/github.com/cloudfoundry-incubator/bosh-openstack-cpi-release?v=${old_openstack_cpi_release_version}
    sha1: ${old_openstack_cpi_release_sha1}

networks:
  - name: private
    type: manual
    subnets:
      - range:    ${v3_e2e_net_cidr}
        gateway:  ${v3_e2e_net_gateway}
        dns:     ${dns}
        static:  [${v3_upgrade_director_manual_ip}]
        cloud_properties:
          net_id: ${v3_e2e_net_id}
          security_groups: [${v3_e2e_security_group}]
  - name: public
    type: vip

resource_pools:
  - name: default
    network: private
    stemcell:
      url: https://bosh.io/d/stemcells/${old_bosh_stemcell_name}?v=${old_bosh_stemcell_version}
      sha1: ${old_bosh_stemcell_sha1}
    cloud_properties:
      instance_type: $v3_e2e_flavor
    env:
      bosh:
        password: ${bosh_vcap_password_hash}

disk_pools:
  - name: default
    disk_size: 25_000

jobs:
  - name: bosh
    templates:
      - {name: nats, release: bosh}
      - {name: redis, release: bosh}
      - {name: postgres, release: bosh}
      - {name: blobstore, release: bosh}
      - {name: director, release: bosh}
      - {name: health_monitor, release: bosh}
      - {name: registry, release: bosh}
      - {name: powerdns, release: bosh}
      - {name: openstack_cpi, release: bosh-openstack-cpi}

    instances: 1
    resource_pool: default
    persistent_disk_pool: default

    networks:
      - name: private
        static_ips: [${v3_upgrade_director_manual_ip}]
        default: [dns, gateway]
      - name: public
        static_ips: [${v3_upgrade_director_floating_ip}]

    properties:
      nats:
        address: 127.0.0.1
        user: nats
        password: ${bosh_admin_password}

      redis:
        listen_addresss: 127.0.0.1
        address: 127.0.0.1
        password: ${bosh_admin_password}

      postgres: &db
        host: 127.0.0.1
        user: postgres
        password: ${bosh_admin_password}
        database: bosh
        adapter: postgres

      # Tells the Director/agents how to contact registry
      registry:
        address: ${v3_upgrade_director_manual_ip}
        host: ${v3_upgrade_director_manual_ip}
        db: *db
        http: {user: admin, password: ${bosh_admin_password}, port: ${v3_e2e_bosh_registry_port}}
        username: admin
        password: ${bosh_admin_password}
        port: ${v3_e2e_bosh_registry_port}
        endpoint: http://admin:${bosh_admin_password}@${v3_upgrade_director_manual_ip}:${v3_e2e_bosh_registry_port}

      # Tells the Director/agents how to contact blobstore
      blobstore:
        address: ${v3_upgrade_director_manual_ip}
        port: 25250
        provider: dav
        director: {user: director, password: ${bosh_admin_password}}
        agent: {user: agent, password: ${bosh_admin_password}}

      director:
        address: 127.0.0.1
        name: micro
        db: *db
        cpi_job: openstack_cpi
        user_management:
          provider: local
          local:
            users:
              - {name: admin, password: ${bosh_admin_password}}

      hm:
        http: {user: hm, password: ${bosh_admin_password}}
        director_account: {user: admin, password: ${bosh_admin_password}}

      dns:
        address: 127.0.0.1
        db: *db

      openstack: &openstack
        auth_url: ${v3_e2e_auth_url}
        username: ${v3_e2e_username}
        api_key: ${v3_e2e_api_key}
        project: ${v3_e2e_project}
        domain:  ${v3_e2e_domain}
        region: #leave this blank
        endpoint_type: publicURL
        default_key_name: ${v3_e2e_default_key_name}
        default_security_groups:
          - ${v3_e2e_security_group}
        state_timeout: ${v3_e2e_state_timeout}
        wait_resource_poll_interval: 5
        human_readable_vm_names: true
        connection_options:
          # old bosh openstack cpi does not know ca_cert feature, give it ssl_verify_peer:false instead
          ssl_verify_peer: $(if [ -z "$bosh_openstack_ca_cert" ]; then echo "true"; else echo "false"; fi)
          connect_timeout: ${v3_e2e_connection_timeout}
          read_timeout: ${v3_e2e_read_timeout}
          write_timeout: ${v3_e2e_write_timeout}

      # Tells agents how to contact nats
      agent: {mbus: "nats://nats:${bosh_admin_password}@${v3_upgrade_director_manual_ip}:4222"}

      ntp: &ntp
        - ${time_server_1}
        - ${time_server_2}

cloud_provider:
  template: {name: openstack_cpi, release: bosh-openstack-cpi}

  # Tells bosh-micro how to SSH into deployed VM
  ssh_tunnel:
    host: ${v3_upgrade_director_floating_ip}
    port: 22
    user: vcap
    private_key: ${private_key}

  # Tells bosh-micro how to contact remote agent
  mbus: https://mbus-user:${bosh_admin_password}@${v3_upgrade_director_floating_ip}:6868

  properties:
    openstack: *openstack

    # Tells CPI how agent should listen for requests
    agent: {mbus: "https://mbus-user:${bosh_admin_password}@0.0.0.0:6868"}

    blobstore:
      provider: local
      path: /var/vcap/micro_bosh/data/cache

    ntp: *ntp
EOF

initver=$(cat old-bosh-init/version)
bosh_init="${PWD}/old-bosh-init/bosh-init-${initver}-linux-amd64"
chmod +x $bosh_init

echo "deploying BOSH..."
$bosh_init deploy ${deployment_dir}/${manifest_filename}
