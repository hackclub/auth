# frozen_string_literal: true

require "rails_helper"

RSpec.describe SentryDirectoryTag do
  def event(transaction: nil)
    Sentry::ErrorEvent.new(configuration: Sentry::Configuration.new).tap { |e| e.transaction = transaction }
  end

  def raised(klass = RuntimeError, backtrace: [ "/app/app/models/identity.rb:1:in 'x'" ])
    klass.new("boom").tap { |e| e.set_backtrace(backtrace) }
  end

  it "tags directory controllers and jobs by transaction" do
    expect(described_class.apply(event(transaction: "Directory::CollectionsController#show"), {}).tags).to include(feature: "directory")
    expect(described_class.apply(event(transaction: "Directory::AfterChangeJob"), {}).tags).to include(feature: "directory")
  end

  it "tags Directory:: exceptions and errors raised from directory code" do
    expect(described_class.apply(event, { exception: raised(Directory::ValidateJob::DriftDetected) }).tags).to include(feature: "directory")
    from_directory = raised(backtrace: [ "/app/app/services/directory/rebuild.rb:12:in 'call'" ])
    expect(described_class.apply(event, { exception: from_directory }).tags).to include(feature: "directory")
  end

  it "leaves everything else alone" do
    tagged = described_class.apply(event(transaction: "LoginsController#create"), { exception: raised })
    expect(tagged.tags).not_to include(:feature)
  end
end
