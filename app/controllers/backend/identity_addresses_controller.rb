module Backend
  class IdentityAddressesController < ApplicationController
    include IdentityAuthorizable

    before_action :set_identity
    before_action :set_address, only: [ :edit, :update, :destroy ]

    def new
      @address = @identity.addresses.build(
        first_name: @identity.first_name,
        last_name: @identity.last_name,
        country: @identity.country,
        phone_number: @identity.phone_number,
      )
      authorize @address

      add_breadcrumb "IDNT", backend_identities_path
      add_breadcrumb @identity.first_name, backend_identity_path(@identity)
      add_breadcrumb "new address"
    end

    def create
      @address = @identity.addresses.build(address_params)
      authorize @address

      if @address.save
        @identity.update!(primary_address: @address) if @identity.primary_address.nil?
        redirect_to backend_identity_path(@identity), notice: "Address created."
      else
        add_breadcrumb "IDNT", backend_identities_path
        add_breadcrumb @identity.first_name, backend_identity_path(@identity)
        add_breadcrumb "new address"
        render :new
      end
    end

    def edit
      authorize @address

      add_breadcrumb "IDNT", backend_identities_path
      add_breadcrumb @identity.first_name, backend_identity_path(@identity)
      add_breadcrumb "edit address"
    end

    def update
      authorize @address

      if @address.update(address_params)
        redirect_to backend_identity_path(@identity), notice: "Address updated."
      else
        add_breadcrumb "IDNT", backend_identities_path
        add_breadcrumb @identity.first_name, backend_identity_path(@identity)
        add_breadcrumb "edit address"
        render :edit
      end
    end

    def destroy
      authorize @address

      @identity.update!(primary_address: nil) if @identity.primary_address == @address
      @address.destroy!
      redirect_to backend_identity_path(@identity), notice: "Address deleted."
    end

    private

    def set_identity
      @identity = Identity.find_by_public_id!(params[:identity_id])
    end

    def set_address
      @address = @identity.addresses.find_by_public_id!(params[:id])
    end

    def address_params
      params.require(:address).permit(:first_name, :last_name, :line_1, :line_2, :city, :state, :postal_code, :country, :phone_number)
    end
  end
end
