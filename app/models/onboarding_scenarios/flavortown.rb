module OnboardingScenarios
  class Flavortown < Base
    WRONG_ANSWERS = [
      [ "More butter", "flavortown_taste_wrong" ],
      [ "MSG", "flavortown_taste_wrong" ],
      [ "Salt", "flavortown_taste_wrong" ]
    ].freeze

    TERRIBLE_ANSWERS = [
      [ "Poison", "flavortown_taste_incredibly_wrong" ],
      [ "Bone hurting juice", "flavortown_taste_incredibly_wrong" ],
      [ "Bone apple tea", "flavortown_taste_incredibly_wrong" ],
      [ "Ómélêttè du fròmage", "flavortown_taste_incredibly_wrong" ],
      [ "Spite", "flavortown_taste_incredibly_wrong" ],
      [ "Raw chicken", "flavortown_taste_incredibly_wrong" ],
      [ "One day blinding stew", "flavortown_taste_incredibly_wrong" ]
    ].freeze

    DINO_NUGGETS = [ "Dino nuggets", "flavortown_dino_nuggets", style: "danger" ].freeze

    def self.slug = "flavortown"

    def title = "ready to enroll in cooking school?"

    def form_fields
      [ :first_name, :last_name, :primary_email, :birthday, :country ]
    end

    def slack_user_type = :multi_channel_guest

    def next_action = :home

    def slack_onboarding_flow = :internal_tutorial

    def slack_channels = chans(:flavortown_bulletin, :flavortown_esplanade, :flavortown_help, :identity_help)

    def promotion_channels = chans(:flavortown_construction, :library, :lounge, :welcome, :happenings, :community, :neighbourhood)

    def use_dm_channel? = false # slackbot is our friend!

    def bot_name = "Flavorpheus"
    def bot_icon_url = "https://hc-cdn.hel1.your-objectstorage.com/s/v3/3bc2db7b9c62b15230a4c1bcefca7131a6c491d2_icon_1.png"

    def first_step = :welcome

    def dialogue_flow
      {
        welcome: "flavortown/01_welcome",
        kitchen_code: "flavortown/02_kitchen_code",
        taste_test: "flavortown/03_taste_test",
        taste_retry: "flavortown/03b_taste_retry",
        taste_reveal: "flavortown/03c_taste_reveal",
        taste_terrible: "flavortown/03d_taste_terrible",
        dino_nuggets: "flavortown/03e_dino_nuggets",
        promoted: "flavortown/04_promoted"
      }
    end

    def handle_action(action_id)
      return { step: :promoted, promote: true } if identity_promoted?

      case action_id
      when "flavortown_continue" then :kitchen_code
      when "flavortown_agree" then :taste_test
      when "flavortown_taste_correct" then { step: :promoted, promote: true }
      when /\Aflavortown_retry_[wt]\d+\z/ then :taste_retry
      when "flavortown_try_again" then :taste_reveal
      when /\Aflavortown_final_[wt]\d+\z/ then :taste_reveal
      when /\Aflavortown_terrible_t\d+\z/ then :taste_terrible
      when "flavortown_dino_nuggets" then :dino_nuggets
      end
    end

    def logo_path = "images/flavortown/flavortown.png"
    def background_path = "images/flavortown/hero-bg.webp"
    def dark_mode_background_path = "images/flavortown/bg-dark.png"
  end
end
