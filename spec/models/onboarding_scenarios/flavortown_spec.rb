require "rails_helper"

RSpec.describe OnboardingScenarios::Flavortown do
  let(:identity) { create(:identity) }
  let(:scenario) { described_class.new(identity) }

  describe ".slug" do
    it "returns 'flavortown'" do
      expect(described_class.slug).to eq("flavortown")
    end
  end

  describe "#dialogue_flow" do
    it "defines all expected steps" do
      expect(scenario.dialogue_flow.keys).to contain_exactly(
        :welcome,
        :kitchen_code,
        :taste_test,
        :taste_retry,
        :taste_reveal,
        :taste_terrible,
        :dino_nuggets,
        :promoted
      )
    end

    it "maps steps to correct templates" do
      expect(scenario.dialogue_flow[:welcome]).to eq("flavortown/01_welcome")
      expect(scenario.dialogue_flow[:kitchen_code]).to eq("flavortown/02_kitchen_code")
      expect(scenario.dialogue_flow[:taste_test]).to eq("flavortown/03_taste_test")
      expect(scenario.dialogue_flow[:taste_retry]).to eq("flavortown/03b_taste_retry")
      expect(scenario.dialogue_flow[:taste_reveal]).to eq("flavortown/03c_taste_reveal")
      expect(scenario.dialogue_flow[:taste_terrible]).to eq("flavortown/03d_taste_terrible")
      expect(scenario.dialogue_flow[:dino_nuggets]).to eq("flavortown/03e_dino_nuggets")
      expect(scenario.dialogue_flow[:promoted]).to eq("flavortown/04_promoted")
    end
  end

  describe "#first_step" do
    it "starts at :welcome" do
      expect(scenario.first_step).to eq(:welcome)
    end
  end

  describe "#handle_action" do
    context "happy path" do
      it "advances from welcome to kitchen_code" do
        expect(scenario.handle_action("flavortown_continue")).to eq(:kitchen_code)
      end

      it "advances from kitchen_code to taste_test" do
        expect(scenario.handle_action("flavortown_agree")).to eq(:taste_test)
      end

      it "promotes on correct answer" do
        result = scenario.handle_action("flavortown_taste_correct")
        expect(result).to eq({ step: :promoted, promote: true })
      end
    end

    context "wrong answers" do
       it "goes to taste_retry on first wrong answer" do
         expect(scenario.handle_action("flavortown_retry_w0")).to eq(:taste_retry)
       end

       it "reveals answer from scolding screens" do
         expect(scenario.handle_action("flavortown_try_again")).to eq(:taste_reveal)
       end

       it "reveals answer after second wrong answer" do
         expect(scenario.handle_action("flavortown_final_w0")).to eq(:taste_reveal)
       end
     end

    context "terrible answers" do
      it "goes to taste_terrible on incredibly wrong answer" do
        expect(scenario.handle_action("flavortown_terrible_t0")).to eq(:taste_terrible)
      end

      it "goes to dino_nuggets on dino nuggets answer" do
        expect(scenario.handle_action("flavortown_dino_nuggets")).to eq(:dino_nuggets)
      end
    end

    context "unknown action" do
      it "returns nil for unknown actions" do
        expect(scenario.handle_action("unknown_action")).to be_nil
      end
    end
  end

  describe "bot persona" do
    it "has custom bot name" do
      expect(scenario.bot_name).to eq("Flavorpheus")
    end

    it "has custom bot icon" do
      expect(scenario.bot_icon_url).to be_present
    end
  end

  describe "slack configuration" do
    it "uses multi-channel guest type" do
      expect(scenario.slack_user_type).to eq(:multi_channel_guest)
    end

    it "does not use DM channel" do
       expect(scenario.use_dm_channel?).to be false
     end

    it "has initial slack channels" do
      expect(scenario.slack_channels).to be_an(Array)
      expect(scenario.slack_channels).not_to be_empty
    end

    it "has promotion channels" do
      expect(scenario.promotion_channels).to be_an(Array)
      expect(scenario.promotion_channels).not_to be_empty
    end
  end

  describe "flow integration" do
    it "can complete the happy path: welcome -> kitchen_code -> taste_test -> promoted" do
      step = scenario.first_step
      expect(step).to eq(:welcome)

      step = scenario.handle_action("flavortown_continue")
      expect(step).to eq(:kitchen_code)

      step = scenario.handle_action("flavortown_agree")
      expect(step).to eq(:taste_test)

      result = scenario.handle_action("flavortown_taste_correct")
      expect(result).to eq({ step: :promoted, promote: true })
    end

    it "can complete the wrong-then-correct path" do
      step = scenario.first_step
      step = scenario.handle_action("flavortown_continue")
      step = scenario.handle_action("flavortown_agree")
      expect(step).to eq(:taste_test)

      step = scenario.handle_action("flavortown_retry_w0")
      expect(step).to eq(:taste_retry)

      result = scenario.handle_action("flavortown_taste_correct")
      expect(result).to eq({ step: :promoted, promote: true })
    end

    it "can complete the reveal path (wrong twice)" do
      scenario.handle_action("flavortown_continue")
      scenario.handle_action("flavortown_agree")

      step = scenario.handle_action("flavortown_retry_w0")
      expect(step).to eq(:taste_retry)

      step = scenario.handle_action("flavortown_final_w0")
      expect(step).to eq(:taste_reveal)
    end

    it "can complete the dino nuggets path" do
       scenario.handle_action("flavortown_continue")
       scenario.handle_action("flavortown_agree")

       step = scenario.handle_action("flavortown_dino_nuggets")
       expect(step).to eq(:dino_nuggets)

       step = scenario.handle_action("flavortown_try_again")
       expect(step).to eq(:taste_reveal)
     end

    it "can complete the terrible answer path" do
       scenario.handle_action("flavortown_continue")
       scenario.handle_action("flavortown_agree")

       step = scenario.handle_action("flavortown_terrible_t0")
       expect(step).to eq(:taste_terrible)

       step = scenario.handle_action("flavortown_try_again")
       expect(step).to eq(:taste_reveal)
     end
  end
end
