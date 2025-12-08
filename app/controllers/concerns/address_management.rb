module AddressManagement
  extend ActiveSupport::Concern

  private

  def build_address
    @address = Address.new(
      identity: current_identity,
      country: current_identity.country,
      first_name: current_identity.first_name,
      last_name: current_identity.last_name
    )
  end
end
