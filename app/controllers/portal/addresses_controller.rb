class Portal::AddressesController < Portal::BaseController
  include AddressManagement

  def portal
    @addresses = current_identity.addresses
    build_address
    render @addresses.any? ? :manage : :portal
  end

  def create
    @address = current_identity.addresses.new(address_params)

    if @address.save
      set_primary_if_needed
      redirect_to_simple_return
    else
      render :portal
    end
  end

  def done
    redirect_to_simple_return
  end

  private

  def address_params
    params.require(:address).permit(:first_name, :last_name, :line_1, :line_2, :city, :state, :postal_code, :country, :phone_number)
  end

  def set_primary_if_needed
    if current_identity.primary_address.nil? || current_identity.addresses.count == 1
      current_identity.update(primary_address: @address)
    end
  end
end
