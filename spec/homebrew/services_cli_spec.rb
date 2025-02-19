# frozen_string_literal: true

require "spec_helper"

describe Service::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#bin" do
    it "outputs command name" do
      expect(services_cli.bin).to eq("brew services")
    end
  end

  describe "#running" do
    it "macOS - returns the currently running services" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      allow(Utils).to receive(:popen_read).and_return <<~EOS
        77513   50  homebrew.mxcl.php
      EOS
      expect(services_cli.running).to eq(["homebrew.mxcl.php"])
    end

    it "systemD - returns the currently running services" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Utils).to receive(:popen_read).and_return <<~EOS
        homebrew.php.service     loaded active running Homebrew PHP service
        systemd-udevd.service    loaded active running Rule-based Manager for Device Events and Files
        udisks2.service          loaded active running Disk Manager
        user@1000.service        loaded active running User Manager for UID 1000
      EOS
      expect(services_cli.running).to eq(["homebrew.php.service"])
    end
  end

  describe "#check" do
    it "checks the input does not exist" do
      expect do
        services_cli.check([])
      end.to raise_error UsageError, "Formula(e) missing, please provide a formula name or use --all"
    end

    it "checks the input exists" do
      expect do
        services_cli.check("hello")
      end.not_to output("Formula(e) missing, please provide a formula name or use --all\n").to_stdout
    end
  end

  describe "#run" do
    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.run([])
    end
  end

  describe "#start" do
    it "checks missing file causes error" do
      expect(Service::System).not_to receive(:root?)
      expect do
        services_cli.start([], "/hfdkjshksdjhfkjsdhf/fdsjghsdkjhb")
      end.to raise_error UsageError, "Provided service file does not exist"
    end

    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.start([])
    end
  end

  describe "#stop" do
    it "checks empty targets cause no error" do
      expect(Service::System).not_to receive(:root?)
      services_cli.stop([])
    end
  end

  describe "#install_service_file" do
    it "checks service is installed" do
      expect do
        services_cli.install_service_file(OpenStruct.new(name: "name", installed?: false), nil)
      end.to raise_error TestExit, "Formula `name` is not installed"
    end

    it "checks service file exists" do
      service = OpenStruct.new(name: "name", installed?: true, service_file: OpenStruct.new(exist?: false))
      expect do
        services_cli.install_service_file(service, nil)
      end.to raise_error TestExit,
                         "Formula `name` has not implemented #plist, #service or installed a locatable service file"
    end
  end

  describe "#systemd_load" do
    it "checks non-enabling run" do
      expect(Service::System).to receive(:systemctl_scope).once.and_return("--user")
      expect(Service::System).to receive(:systemctl).once.and_return("/bin/launchctl")
      services_cli.systemd_load(OpenStruct.new(service_name: "name"), enable: false)
    end

    it "checks enabling run" do
      expect(Service::System).to receive(:systemctl_scope).exactly(2).and_return("--user")
      expect(Service::System).to receive(:systemctl).exactly(2).and_return("/bin/launchctl")
      services_cli.systemd_load(OpenStruct.new(service_name: "name"), enable: true)
    end
  end

  describe "#launchctl_load" do
    it "checks non-enabling run" do
      expect(Service::System).to receive(:domain_target).once.and_return("target")
      expect(Service::System).to receive(:launchctl).once.and_return("/bin/launchctl")
      services_cli.launchctl_load({}, file: "a", enable: false)
    end

    it "checks enabling run" do
      expect(Service::System).to receive(:domain_target).exactly(2).and_return("target")
      expect(Service::System).to receive(:launchctl).exactly(2).and_return("/bin/launchctl")
      services_cli.launchctl_load(OpenStruct.new(service_name: "name"), file: "a", enable: true)
    end
  end

  describe "#service_load" do
    it "checks non-root for login" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(false)
      expect(Service::System).to receive(:root?).once.and_return(true)
      out = "name must be run as non-root to start at user login!\nSuccessfully ran `name` (label: service.name)\n"
      expect do
        services_cli.service_load(
          OpenStruct.new(name: "name", service_name: "service.name", service_startup?: false), enable: false
        )
      end.to output(out).to_stdout
    end

    it "checks root for startup" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(false)
      expect(Service::System).to receive(:root?).exactly(2).and_return(false)
      out = "name must be run as root to start at system startup!\nSuccessfully ran `name` (label: service.name)\n"
      expect do
        services_cli.service_load(OpenStruct.new(name: "name", service_name: "service.name", service_startup?: true),
                                  enable: false)
      end.to output(out).to_stdout
    end

    it "triggers launchctl" do
      expect(Service::System).to receive(:domain_target).once.and_return("target")
      expect(Service::System).to receive(:launchctl?).once.and_return(true)
      expect(Service::System).to receive(:launchctl).once
      expect(Service::System).not_to receive(:systemctl?)
      expect(Service::System).to receive(:root?).exactly(2).and_return(false)
      expect do
        services_cli.service_load(
          OpenStruct.new(name: "name", service_name: "service.name", service_startup?: false), enable: false
        )
      end.to output("Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "triggers systemctl" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(true)
      expect(Service::System).to receive(:systemctl).once
      expect(Service::System).to receive(:systemctl_scope).once
      expect(Service::System).to receive(:root?).exactly(2).and_return(false)
      expect do
        services_cli.service_load(
          OpenStruct.new(name: "name", service_name: "service.name", service_startup?: false), enable: false
        )
      end.to output("Successfully ran `name` (label: service.name)\n").to_stdout
    end

    it "represents correct action" do
      expect(Service::System).to receive(:launchctl?).once.and_return(false)
      expect(Service::System).to receive(:systemctl?).once.and_return(true)
      expect(Service::System).to receive(:systemctl).exactly(2)
      expect(Service::System).to receive(:systemctl_scope).exactly(2)
      expect(Service::System).to receive(:root?).exactly(2).and_return(false)
      expect do
        services_cli.service_load(
          OpenStruct.new(name: "name", service_name: "service.name", service_startup?: false), enable: true
        )
      end.to output("Successfully started `name` (label: service.name)\n").to_stdout
    end
  end
end
