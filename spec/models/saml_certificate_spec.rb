# frozen_string_literal: true

require "rails_helper"

RSpec.describe SAMLCertificate do
  include ActiveSupport::Testing::TimeHelpers

  let(:key_dir) { Dir.mktmpdir }

  before do
    stub_const("SAMLCertificate::KEY_DIR", key_dir)
    # 4096-bit keygen is slow and the size doesn't matter here
    allow(OpenSSL::PKey::RSA).to receive(:new).and_call_original
    allow(OpenSSL::PKey::RSA).to receive(:new).with(4096) { OpenSSL::PKey::RSA.generate(2048) }
    stub_const("ENV", ENV.to_h.except("SAML_IDP_CERT_PATH", "SAML_IDP_KEY_PATH"))
    SAMLService::Entities.reset!
  end

  after { FileUtils.remove_entry(key_dir) }

  def generate! = described_class.generate!

  describe ".generate!" do
    it "makes the first cert signing and the next one rollover" do
      first = generate!
      second = generate!

      expect(first).to be_signing
      expect(second).to be_rollover
    end

    it "writes the key 0600, named by fingerprint" do
      cert = generate!

      expect(File.stat(cert.key_path).mode & 0o777).to eq(0o600)
      expect(File.basename(cert.key_path)).to eq("saml-#{OpenSSL::Digest::SHA256.hexdigest(cert.x509.to_der).first(16)}.key")
    end

    it "uses the full subject" do
      expect(generate!.x509.subject.to_s).to eq("/C=US/ST=Vermont/L=Burlington/O=Hack Club/OU=Identity Services/CN=auth.hackclub.com")
    end

    it "refuses a second rollover without leaving a key behind" do
      generate!
      generate!

      expect { generate! }.to raise_error(RuntimeError, /rollover certificate already exists/)
      expect(Dir.children(key_dir).size).to eq(2)
    end

    it "rejects out-of-range validity" do
      expect { described_class.generate!(validity_years: 0) }.to raise_error(ArgumentError)
      expect { described_class.generate!(validity_years: nil) }.to raise_error(ArgumentError)
    end
  end

  describe ".import_from_env!" do
    it "copies the env key into KEY_DIR so swapping the env files can't split cert and key" do
      env_dir = Dir.mktmpdir
      key = OpenSSL::PKey::RSA.generate(2048)
      cert = OpenSSL::X509::Certificate.new.tap do |c|
        c.version = 2
        c.serial = 1
        c.subject = c.issuer = OpenSSL::X509::Name.parse("/CN=identity.hackclub.com")
        c.public_key = key.public_key
        c.not_before = Time.now
        c.not_after = 1.year.from_now
        c.sign(key, OpenSSL::Digest::SHA256.new)
      end
      File.write(File.join(env_dir, "cert.pem"), cert.to_pem)
      File.write(File.join(env_dir, "key.pem"), key.to_pem)
      ENV["SAML_IDP_CERT_PATH"] = File.join(env_dir, "cert.pem")
      ENV["SAML_IDP_KEY_PATH"] = File.join(env_dir, "key.pem")

      rollover = generate!
      imported = described_class.current_signing
      FileUtils.remove_entry(env_dir)

      expect(rollover).to be_rollover
      expect(imported.key_path).to start_with(key_dir)
      expect(imported.x509.check_private_key(imported.private_key)).to be true
    end
  end

  describe "#promote!" do
    it "demotes the old signing cert to rollover" do
      old = generate!
      new = generate!

      new.promote!

      expect(old.reload).to be_rollover
      expect(new.reload).to be_signing
      expect(described_class.signing.count).to eq(1)
      expect(old.versions.last.changeset["role"]).to eq(%w[signing rollover])
    end

    it "refuses a cert whose key isn't on this host, and keeps the old one signing" do
      old = generate!
      new = generate!
      File.delete(new.key_path)

      expect { new.promote! }.to raise_error(ActiveRecord::RecordInvalid, /not readable on this host/)
      expect(old.reload).to be_signing
      expect(new.reload).to be_rollover
    end

    it "refuses an expired cert" do
      generate!
      new = generate!

      travel_to 2.years.from_now do
        expect { new.promote! }.to raise_error(ActiveRecord::RecordInvalid, /in the past/)
      end
    end

    it "re-reads the row, so a stale page can't retire a cert someone just promoted" do
      generate!
      new = generate!
      stale = described_class.find(new.id)

      new.promote!

      expect { stale.retire! }.to raise_error(AASM::InvalidTransition)
      expect(new.reload).to be_signing
    end
  end

  describe ".current_signing" do
    it "only swallows the missing-table case" do
      allow(described_class).to receive(:signing).and_raise(ActiveRecord::QueryCanceled.new("canceled"))

      expect { described_class.current_signing }.to raise_error(ActiveRecord::QueryCanceled)
    end
  end

  describe "SAMLService::Entities" do
    it "publishes a new rollover without anyone calling reset!" do
      generate!
      SAMLService::Entities.metadata_xml
      rollover = generate!

      expect(SAMLService::Entities.keys.rollover_certificate).to eq(rollover.x509_certificate_base64)
      expect(SAMLService::Entities.metadata_xml).to include(rollover.x509_certificate_base64)
    end

    it "signs with the key that matches the published cert after a promote" do
      generate!
      SAMLService::Entities.keys
      new = generate!
      new.promote!

      keys = SAMLService::Entities.keys
      expect(keys.certificate).to eq(new.x509_certificate_base64)
      expect(new.x509.check_private_key(keys.private_key)).to be true
    end
  end
end
