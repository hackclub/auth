RSpec.shared_examples "a rejectable verification" do
  describe "Verification::Rejectable" do
    describe "class-level DSL" do
      it "defines REJECTION_REASONS constant" do
        expect(described_class::REJECTION_REASONS).to be_a(Hash)
        expect(described_class::REJECTION_REASONS).to be_frozen
      end

      it "defines RETRYABLE_REJECTION_REASONS" do
        expect(described_class::RETRYABLE_REJECTION_REASONS).to be_an(Array)
        expect(described_class::RETRYABLE_REJECTION_REASONS).to be_frozen
      end

      it "defines FATAL_REJECTION_REASONS" do
        expect(described_class::FATAL_REJECTION_REASONS).to be_an(Array)
        expect(described_class::FATAL_REJECTION_REASONS).to be_frozen
      end

      it "defines REJECTION_REASON_NAMES" do
        expect(described_class::REJECTION_REASON_NAMES).to be_a(Hash)
        described_class::REJECTION_REASON_NAMES.each do |key, name|
          expect(key).to be_a(String)
          expect(name).to be_a(String)
          expect(name).not_to be_empty
        end
      end

      it "partitions reasons into retryable and fatal exhaustively" do
        all_reasons = described_class::REJECTION_REASONS.keys.map(&:to_s)
        partitioned = described_class::RETRYABLE_REJECTION_REASONS + described_class::FATAL_REJECTION_REASONS
        expect(partitioned.sort).to eq(all_reasons.sort)
      end

      it "sets up the rejection_reason enum" do
        expect(subject).to respond_to(:rejection_reason)
        described_class::REJECTION_REASONS.each_key do |reason|
          expect(subject).to respond_to(:"#{reason}?")
        end
      end
    end

    describe "#rejection_reason_name" do
      it "returns the human-readable name for a known reason" do
        reason = described_class::REJECTION_REASONS.keys.first.to_s
        subject.rejection_reason = reason
        expect(subject.rejection_reason_name).to eq(described_class::REJECTION_REASON_NAMES[reason])
      end

      it "falls back to raw reason when name is missing" do
        allow(subject).to receive(:rejection_reason).and_return("unknown_thing")
        expect(subject.rejection_reason_name).to eq("unknown_thing")
      end
    end

    describe "#rejection_reason_options" do
      it "returns a hash with :retryable and :fatal keys" do
        options = subject.rejection_reason_options
        expect(options).to have_key(:retryable)
        expect(options).to have_key(:fatal)
      end

      it "returns [label, value] pairs" do
        options = subject.rejection_reason_options
        (options[:retryable] + options[:fatal]).each do |pair|
          expect(pair).to be_an(Array)
          expect(pair.length).to eq(2)
          expect(pair[0]).to be_a(String) # label
          expect(pair[1]).to be_a(String) # value
        end
      end

      it "includes all defined reasons" do
        options = subject.rejection_reason_options
        all_values = (options[:retryable] + options[:fatal]).map(&:last)
        described_class::REJECTION_REASONS.each_key do |reason|
          expect(all_values).to include(reason.to_s)
        end
      end
    end

    describe "validations" do
      it "requires rejection_reason when rejected" do
        subject.status = "rejected"
        subject.rejection_reason = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:rejection_reason]).to be_present
      end

      it "requires rejection_reason_details when reason is other" do
        subject.status = "rejected"
        subject.rejection_reason = "other"
        subject.rejection_reason_details = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:rejection_reason_details]).to be_present
      end

      it "accepts rejection_reason_details for reason other" do
        subject.status = "rejected"
        subject.rejection_reason = "other"
        subject.rejection_reason_details = "specific explanation"
        subject.valid?
        expect(subject.errors[:rejection_reason_details]).to be_empty
      end
    end
  end
end
