RSpec.shared_examples "a verification type" do
  describe "polymorphic interface" do
    it { is_expected.to respond_to(:review_info_partial) }
    it { is_expected.to respond_to(:review_full_partial) }
    it { is_expected.to respond_to(:relevant_record) }
    it { is_expected.to respond_to(:document_type_label) }
    it { is_expected.to respond_to(:rejection_reason_options) }
    it { is_expected.to respond_to(:rejection_reason_name) }
    it { is_expected.to respond_to(:needs_break_glass?) }

    describe "#review_info_partial" do
      it "returns a partial path string" do
        expect(subject.review_info_partial).to be_a(String)
        expect(subject.review_info_partial).to include("/")
      end
    end

    describe "#review_full_partial" do
      it "returns a partial path string" do
        expect(subject.review_full_partial).to be_a(String)
        expect(subject.review_full_partial).to include("/")
      end
    end

    describe "#document_type_label" do
      it "returns a human-readable string" do
        expect(subject.document_type_label).to be_a(String)
        expect(subject.document_type_label).not_to be_empty
      end
    end

    describe "#rejection_reason_options" do
      it "returns retryable and fatal groups" do
        options = subject.rejection_reason_options
        expect(options).to have_key(:retryable)
        expect(options).to have_key(:fatal)
        expect(options[:retryable]).to be_an(Array)
        expect(options[:fatal]).to be_an(Array)
      end

      it "returns [label, value] pairs in each group" do
        options = subject.rejection_reason_options
        (options[:retryable] + options[:fatal]).each do |pair|
          expect(pair).to be_an(Array)
          expect(pair.length).to eq(2)
        end
      end
    end
  end
end
