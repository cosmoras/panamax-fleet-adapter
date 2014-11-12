require_relative '../spec_helper'
require_relative '../../app/utils'

describe FleetAdapter::Models::Service do
  using FleetAdapter::StringExtensions

  let(:attrs) do
    {
      name: 'foo',
      source: 'bar',
      command: '/bin/bash',
      ports: [{ hostPort: 3306, containerPort: 3306 }],
      expose: [3306],
      environment: [{ variable: 'DB_PASSWORD', value: 'password' }],
      volumes: [{ hostPath: '/foo/bar', containerPath: '/bar/baz' }],
      links: [{ name: 'db', alias: 'db_1' }],
      deployment: { count: 10 }
    }
  end

  let(:fake_fleet_client) do
    double(:fake_fleet_client,
           load: true,
           start: true,
           stop: true,
           destroy: true,
           status: {}
    )
  end

  subject { described_class.new(attrs, 1) }

  describe '.find' do
    before do
      allow(Fleet).to receive(:new) { fake_fleet_client }
    end

    it 'returns a new Service model with the id set' do
      expect(described_class.find('asdf').id).to eq 'asdf'
    end

    it 'refreshes the status of the Service model' do
      expect(described_class.find('asdf').status).to_not be_nil
    end
  end

  describe '#initialize' do

    context 'when no attrs are specified' do
      subject { described_class.new({}, 1) }

      its(:name) { is_expected.to be_empty }
      its(:source) { is_expected.to be_nil }
      its(:command) { is_expected.to be_nil }
      its(:expose) { is_expected.to eq [] }
      its(:ports) { is_expected.to eq [] }
      its(:environment) { is_expected.to eq [] }
      its(:volumes) { is_expected.to eq [] }
      its(:links) { is_expected.to eq [] }
      its(:deployment) { is_expected.to eq({}) }
    end

    context 'when attrs are specified' do
      its(:source) { is_expected.to eq attrs[:source] }
      its(:command) { is_expected.to eq attrs[:command] }
      its(:ports) { is_expected.to eq attrs[:ports] }
      its(:environment) { is_expected.to eq attrs[:environment] }
      its(:volumes) { is_expected.to eq attrs[:volumes] }
      its(:links) { is_expected.to eq attrs[:links] }
      its(:deployment) { is_expected.to eq attrs[:deployment] }
    end

    context 'when the name has a space' do
      subject { described_class.new({ name: 'foo bar', deployment: { count: 1 } }, 1) }
      it 'replaces spaces with underscores' do
        expect(subject.name).to eq('foo-bar')
      end
    end

    context 'when index is specified' do
      context 'when deployment count is more than 1' do
        it 'adds an @ to the name' do
          expect(subject.name).to eq('foo@1')
        end
      end

      context 'when deployment count is not more than 1' do
        subject { described_class.new({name: 'foo', deployment: { count: 1 } }, 1) }
        it 'name does not include @' do
          expect(subject.name).to eq('foo')
        end
      end

      context 'when there is no id' do
        it 'sets the id to name.service' do
          expect(subject.id).to eq("#{subject.name}.service")
        end
      end
    end
  end

  [:start, :stop, :destroy].each do |method|
    describe "##{method}" do

      before do
        allow(Fleet).to receive(:new) { fake_fleet_client }
      end

      it "sends a #{method} message to the fleet client" do
        expect(fake_fleet_client).to receive(method).with(subject.id)
        subject.send(method)
      end

      it 'returns the result of the fleet call' do
        expect(subject.send(method)).to eql true
      end
    end
  end
  describe '#load' do
    before do
      allow(Fleet).to receive(:new) { fake_fleet_client }
      allow(subject).to receive(:service_def).and_return({})
    end

    it 'sends the id and service_def to the fleet client' do
      expect(fake_fleet_client).to receive(:load).with(subject.id, {})
      subject.send(:load)
    end
  end


  describe '#refresh' do
    before do
      allow(Fleet).to receive(:new) { fake_fleet_client }
      allow(fake_fleet_client).to receive(:status).and_return(active_state: 'active',
                                                 load_state: 'loaded',
                                                 sub_state: 'running',
                                                 machine_state: 'wtf')
    end

    it 'gets the status of a unit' do
      subject.refresh
      expect(subject.status).to match /load_state: loaded/
      expect(subject.status).to match /active_state: active/
      expect(subject.status).to match /sub_state: running/
      expect(subject.status).not_to match /machine_state/
    end


  end

  describe '#docker_run_string' do
    before do
      subject.links = []
    end
    context 'when the service specifies exposed ports' do
      it 'generates a docker command with --expose' do
        expect(subject.send(:docker_run_string)).to include '--expose 3306'
      end
    end

    context 'when the service specifies port mappings' do
      before do
        subject.ports = [{
                           hostInterface: '0.0.0.0',
                           hostPort: '8000',
                           containerPort: '3000'
                       }]
      end

      it 'generates a docker command with -p' do
        expect(subject.send(:docker_run_string)).to include '-p 0.0.0.0:8000:3000'
      end

      context 'when the hostPort is empty' do

        before do
          subject.ports = [{
                           hostInterface: nil,
                           hostPort: '',
                           containerPort: '3000'
                         }]
        end

        it 'does not include the colon affixed to the host port info' do
          expect(subject.send(:docker_run_string)).to include '-p 3000'
        end
      end

      context 'when the UDP protocol is specified' do

        before do
          subject.ports = [{
                           containerPort: '3306',
                           protocol: 'udp'
                         }]
        end

        it 'generates a docker command with -p with the udp protocol' do
          expect(subject.send(:docker_run_string)).to include '-p 3306/udp'
        end
      end

      context 'when the TCP protocol is specified' do

        before do
          subject.ports = [{
                             containerPort: '3306',
                             protocol: 'tcp'
                         }]
        end

        it 'generates a docker command with -p with no protocol' do
          expect(subject.send(:docker_run_string)).to include '-p 3306'
        end
      end
    end


    context 'when the service specifies environment vars' do
      it 'generates a docker command with -e' do
        expect(subject.send(:docker_run_string)).to include "-e 'DB_PASSWORD=password'"
      end
    end

    context 'when the service specifies docker links' do
      it 'translates docker links to environment variables' do
        subject.links = [{ name: 'db', alias: 'db_1', exposed_ports: [{ protocol: 'tcp', containerPort: 3306, hostPort: 3306 }] }]
        expect(subject.send(:docker_run_string)).to include '-e DB_1_SERVICE_HOST=`/usr/bin/etcdctl get app/DB/DB_SERVICE_HOST`'
        expect(subject.send(:docker_run_string)).to include '-e DB_1_PORT=tcp://`/usr/bin/etcdctl get app/DB/DB_SERVICE_HOST`:3306'
        expect(subject.send(:docker_run_string)).to include '-e DB_1_PORT_3306_TCP_PROTO=tcp'
        expect(subject.send(:docker_run_string)).to include '-e DB_1_PORT_3306_TCP_ADDR=`/usr/bin/etcdctl get app/DB/DB_SERVICE_HOST`'
        expect(subject.send(:docker_run_string)).to include '-e DB_1_PORT_3306_TCP=tcp://`/usr/bin/etcdctl get app/DB/DB_SERVICE_HOST`:3306'
        expect(subject.send(:docker_run_string)).to include '-e DB_1_PORT_3306_TCP_PORT=3306'
      end

      it 'sanitizes the link names when creating the env vars' do
        subject.links = [{ name: 'db_@:.-', alias: 'db_1', exposed_ports: [{ protocol: 'tcp', containerPort: 3306, hostPort: 3306 }] }]
        expect(subject.send(:docker_run_string)).to include '-e DB_1_SERVICE_HOST=`/usr/bin/etcdctl get app/DB-----/DB-----_SERVICE_HOST`'
      end
    end

    context 'when the service specifies volumes' do
      it 'generates a docker command with -v' do
        expect(subject.send(:docker_run_string)).to include '-v /foo/bar:/bar/baz'
      end

      it 'excludes the : if only a container volume is specified' do
        subject.volumes.first[:hostPath] = ''
        expect(subject.send(:docker_run_string)).to include '-v /bar/baz'
      end
    end
  end

  describe '#service_def' do
    before do
      subject.links = [{ name: 'db', alias: 'db', exposed_ports: [{ hostPort: 1, containerPort: 2, protocol: 'tcp' }] }]
    end
    context 'when the service has links' do
      it 'assigns dependencies to the unit_block' do
        expect(subject.send(:service_def)['Unit']['After']).to eq('db.service')
        expect(subject.send(:service_def)['Unit']['Wants']).to eq('db.service')
      end
    end

    context 'when the service has no links' do
      before do
        subject.links = []
      end
      it 'does not assign dependencies to the unit_block' do
        expect(subject.send(:service_def)['Unit']['After']).to be_nil
        expect(subject.send(:service_def)['Unit']['Wants']).to be_nil
      end
    end

    it 'creates a docker rm string command with the service name only' do
      expect(subject.send(:service_def)['Service']['ExecStartPost']).to eq('-/usr/bin/docker rm foo')
      expect(subject.send(:service_def)['Service']['ExecStopPost']).to eq('-/usr/bin/docker rm foo')
    end

    it 'creates a docker kill string command with the service name only' do
      expect(subject.send(:service_def)['Service']['ExecStop']).to eq('-/bin/bash -c "/usr/bin/etcdctl rm app/FOO@1 --recursive && /usr/bin/docker kill foo"')
    end

    it 'adds an X-Fleet block to the unit file' do
      expect(subject.send(:service_def).keys).to include 'X-Fleet'
    end

    context 'when the service is scaled' do
      it 'adds a wildcard Conflicts rule to the X-Fleet block' do
        expect(subject.send(:service_def)['X-Fleet']['Conflicts']).to eq('foo@*.service')
      end
    end

    context 'when the service is not scaled' do
      before do
        subject.id = 'foo.service'
        subject.deployment[:count] = 1
      end

      it 'adds a non-wildcard Conflicts rule to the X-Fleet block' do
        expect(subject.send(:service_def)['X-Fleet']['Conflicts']).to eq('foo.service')
      end
    end
  end
end
