$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'tmpdir'
require 'zlib'
require 'archive/tar/minitar'
require 'webmock'
include Archive::Tar

require 'cloud/openstack'

def mock_cloud_options(api_version=2)
  if api_version == 2
    {
      'plugin' => 'openstack',
      'properties' => {
        'openstack' => {
          'auth_url' => 'http://127.0.0.1:5000/v2.0',
          'username' => 'admin',
          'api_key' => 'nova',
          'tenant' => 'admin',
          'region' => 'RegionOne',
          'state_timeout' => 1,
          'wait_resource_poll_interval' => 3
        },
        'registry' => {
          'endpoint' => 'localhost:42288',
          'user' => 'admin',
          'password' => 'admin'
        },
        'agent' => {
          'foo' => 'bar',
          'baz' => 'zaz'
        }
      }
    }
  elsif api_version == 3
    {
      'plugin' => 'openstack',
      'properties' => {
        'openstack' => {
          'auth_url' => 'http://127.0.0.1:5000/v3',
          'username' => 'admin',
          'api_key' => 'nova',
          'project' => 'admin',
          'domain' => 'some_domain',
          'region' => 'RegionOne',
          'state_timeout' => 1,
          'wait_resource_poll_interval' => 3
        },
        'registry' => {
          'endpoint' => 'localhost:42288',
          'user' => 'admin',
          'password' => 'admin'
        },
        'agent' => {
          'foo' => 'bar',
          'baz' => 'zaz'
        }
      }
    }
  end
end

def make_cloud(options = nil)
  Bosh::OpenStackCloud::Cloud.new(options || mock_cloud_options['properties'])
end

def mock_registry(endpoint = 'http://registry:3333')
  registry = double('registry', :endpoint => endpoint)
  allow(Bosh::Cpi::RegistryClient).to receive(:new).and_return(registry)
  registry
end

def mock_cloud(options = nil)
  servers = double('servers')
  images = double('images')
  flavors = double('flavors')
  volumes = double('volumes')
  addresses = double('addresses')
  snapshots = double('snapshots')
  key_pairs = double('key_pairs')
  security_groups = [double('default_sec_group', id: 'default_sec_group_id', name: 'default')]

  glance = double(Fog::Image::OpenStack::V2)
  allow(Fog::Image::OpenStack::V2).to receive(:new).and_return(glance)

  volume = double(Fog::Volume::OpenStack::V2)
  allow(volume).to receive(:volumes).and_return(volumes)
  allow(Fog::Volume::OpenStack::V2).to receive(:new).and_return(volume)

  openstack = double(Fog::Compute)

  allow(openstack).to receive(:servers).and_return(servers)
  allow(openstack).to receive(:images).and_return(images)
  allow(openstack).to receive(:flavors).and_return(flavors)
  allow(openstack).to receive(:volumes).and_return(volumes)
  allow(openstack).to receive(:addresses).and_return(addresses)
  allow(openstack).to receive(:snapshots).and_return(snapshots)
  allow(openstack).to receive(:key_pairs).and_return(key_pairs)
  allow(openstack).to receive(:security_groups).and_return(security_groups)

  allow(Fog::Compute).to receive(:new).and_return(openstack)

  yield openstack if block_given?

  Bosh::OpenStackCloud::Cloud.new(options || mock_cloud_options['properties'])
end

def mock_glance_v1(options = nil)
  cloud = mock_cloud(options)

  glance = double(Fog::Image::OpenStack::V1, images: double('images'))
  allow(cloud.instance_variable_get('@openstack')).to receive(:image).and_return(glance)
  allow(glance).to receive(:class).and_return(Fog::Image::OpenStack::V1::Mock)

  yield glance if block_given?

  cloud
end

def mock_glance_v2(options = nil)
  cloud = mock_cloud(options)

  glance = double(Fog::Image::OpenStack::V2, images: double('images'))
  allow(cloud.instance_variable_get('@openstack')).to receive(:image).and_return(glance)
  allow(glance).to receive(:class).and_return(Fog::Image::OpenStack::V2::Mock)

  yield glance if block_given?

  cloud
end

def dynamic_network_spec
  {
    'type' => 'dynamic',
    'cloud_properties' => {
      'security_groups' => %w[default]
    },
    'use_dhcp' => true
  }
end

def manual_network_spec(net_id: 'net', ip: '0.0.0.0')
  {
    'type' => 'manual',
    'ip' => ip,
    'cloud_properties' => {
      'security_groups' => %w[default],
      'net_id' => net_id
    },
    'use_dhcp' => true
  }
end

def manual_network_without_netid_spec
  {
    'type' => 'manual',
    'cloud_properties' => {
      'security_groups' => %w[default],
    }
  }
end

def dynamic_network_with_netid_spec
  {
    'type' => 'dynamic',
    'cloud_properties' => {
      'security_groups' => %w[default],
      'net_id' => 'net'
    }
  }
end

def vip_network_spec
  {
    'type' => 'vip',
    'ip' => '10.0.0.1',
    'use_dhcp' => true
  }
end

def combined_network_spec
  {
    'network_a' => dynamic_network_spec,
    'network_b' => vip_network_spec
  }
end

def resource_pool_spec
  {
    'key_name' => 'test_key',
    'availability_zone' => 'foobar-1a',
    'instance_type' => 'm1.tiny'
  }
end

def resource_pool_spec_with_root_disk
  {
    'key_name' => 'test_key',
    'availability_zone' => 'foobar-1a',
    'instance_type' => 'm1.tiny',
    'root_disk' => { 'size' => 10240 }
  }
end

def resource_pool_spec_with_0_root_disk
  {
    'key_name' => 'test_key',
    'availability_zone' => 'foobar-1a',
    'instance_type' => 'm1.tiny',
    'root_disk' => { 'size' => 0 }
  }
end

RSpec.configure do |config|
  config.before(:each) { allow(Bosh::Clouds::Config).to receive(:logger).and_return(double.as_null_object)  }
end

class LifecycleHelper
  extend WebMock::API

  def self.get_config(key, default=:none)
    env_file = ENV['LIFECYCLE_ENV_FILE']
    env_name = ENV['LIFECYCLE_ENV_NAME']
    env_key = "BOSH_OPENSTACK_#{key.to_s.upcase}"

    if env_file
      config = load_config_from_file(env_file, env_name)

      value = config[key.to_s]
      present = config.has_key?(key.to_s)
    else
      value = ENV[env_key]
      present = ENV.has_key?(env_key)
    end

    if !present && default == :none
      raise("Missing #{key}/#{env_key}; use LIFECYCLE_ENV_FILE=file.yml and LIFECYCLE_ENV_NAME=xxx or set in ENV")
    end
    present ? value : default
  end

  def self.load_config_from_file(env_file, env_name)
    @configs ||= YAML.load_file(env_file)
    config =
        if env_name
          unless @configs[env_name]
            raise "no such env #{env_name} in #{env_file} (available: #{@configs.keys.sort.join(", ")})"
          end
          @configs[env_name]
        else
          @configs
        end
    config
  end

end

def write_ssl_ca_file(ca_cert, logger)
  Dir::Tmpname.create('cacert.pem') do |path|
    logger.info("cacert.pem file: #{path}")
    File.write(path, ca_cert)
  end
end

def connection_options(additional_options = {})
  options = {
      'connect_timeout' => LifecycleHelper.get_config(:connect_timeout, '120').to_i,
      'read_timeout' => LifecycleHelper.get_config(:read_timeout, '120').to_i,
      'write_timeout' => LifecycleHelper.get_config(:write_timeout, '120').to_i
  }
  additional_options.each { |key, value|
    options[key] = value
  }
  options
end

def additional_connection_options(logger)
  additional_connection_options = {}
  ca_cert = LifecycleHelper.get_config(:ca_cert, nil)
  if ca_cert && !ca_cert.empty?
    additional_connection_options['ssl_ca_file'] = write_ssl_ca_file(ca_cert, logger)
  elsif LifecycleHelper.get_config(:insecure, false)
    additional_connection_options['ssl_verify_peer'] = false
  end
  additional_connection_options
end

def str_to_bool(string)
  if string == 'true'
    true
  else
    false
  end
end
