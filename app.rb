require 'rubygems'
require 'bundler'

# Setup load paths
Bundler.require
$: << File.expand_path('../', __FILE__)

# Require base
require 'sinatra/base'

require 'app/models'
require 'app/routes'
require 'app/utils'

module FleetAdapter
  VERSION = ENV["ADAPTER_VERSION"]

  class App < Sinatra::Application
    configure do
      disable :method_override
      disable :static
    end

    use FleetAdapter::Routes::Services
    use FleetAdapter::Routes::Metadata
  end
end

include FleetAdapter::Models
