# == Schema Information
#
# Table name: addresses
#
#  id           :bigint           not null, primary key
#  city         :string
#  country      :integer
#  first_name   :string
#  last_name    :string
#  line_1       :string
#  line_2       :string
#  phone_number :string
#  postal_code  :string
#  state        :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  identity_id  :bigint           not null
#
# Indexes
#
#  index_addresses_on_identity_id  (identity_id)
#
# Foreign Keys
#
#  fk_rails_...  (identity_id => identities.id)
#
class Address < ApplicationRecord
  include PublicIdentifiable
  include PublicActivity::Model
  tracked owner: ->(controller, model) { controller&.user_for_public_activity }, only: [ :create, :update, :destroy ]

  has_paper_trail
  set_public_id_prefix "addr"

  belongs_to :identity

  include CountryEnumable
  has_country_enum

  GREMLINS = [
    "\u200E", # LEFT-TO-RIGHT MARK
    "\u200B" # ZERO WIDTH SPACE
  ].join

  def self.strip_gremlins(str) = str&.delete(GREMLINS)&.presence

  validates_presence_of :first_name, :line_1, :city, :state, :postal_code, :country, :phone_number

  before_validation :strip_gremlins_from_fields

  before_validation :normalize_phone_number

  def self.country_calling_code(country_alpha2)
    ISO3166::Country[country_alpha2]&.country_code
  end

  private def strip_gremlins_from_fields
    self.first_name = Address.strip_gremlins(first_name)
    self.last_name = Address.strip_gremlins(last_name)
    self.line_1 = Address.strip_gremlins(line_1)
    self.line_2 = Address.strip_gremlins(line_2)
    self.city = Address.strip_gremlins(city)
    self.state = Address.strip_gremlins(state)
    self.postal_code = Address.strip_gremlins(postal_code)
  end

  private def normalize_phone_number
    return if phone_number.blank?
    cleaned = phone_number.gsub(/[^\d+]/, "")
    calling_code = Address.country_calling_code(country)
    unless cleaned.start_with?("+")
      cleaned = "+#{calling_code}#{cleaned}"
    end
    self.phone_number = cleaned
  end
end
