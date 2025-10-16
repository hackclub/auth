class AddressesController < ApplicationController
  include IsSneaky
  before_action :set_address, only: [ :show, :edit, :update, :destroy ]
  before_action :hide_some_data_away, only: %i[program_create_address]
  def index
    @addresses = current_identity.addresses
  end

  def show
  end

  def new
    build_address
  end

  def create
    @address = current_identity.addresses.new(address_params)
    if @address.save
      if current_identity.primary_address.nil?
        current_identity.update(primary_address: @address)
      end
      if params[:address][:from_program] == "true"
        redirect_to safe_redirect_url("address_return_to") || addresses_path, notice: "address created successfully!", allow_other_host: true
      else
        redirect_to addresses_path, notice: "address created successfully!"
      end
    else
      render params[:address][:from_program] == "true" ? :program_create_address : :new
    end
  end

  def program_create_address
    build_address
  end

  def edit
  end

  def update
    if params[:make_primary] == "true"
      current_identity.update(primary_address: @address)
      redirect_to addresses_path, notice: "Primary address updated!"
    elsif @address.update(address_params)
      redirect_to addresses_path, notice: "address updated successfully!"
    else
      render :edit
    end
  end

  def destroy
    if current_identity.primary_address == @address
      if Rails.env.development?
        current_identity.update(primary_address: nil)
      else
        flash[:alert] = "can't delete your primary address..."
        redirect_to addresses_path
        return
      end
    end
    @address.destroy
    redirect_to addresses_path, notice: "address deleted successfully!"
  end

  private

  def build_address
    @address = current_identity.addresses.build(
      country: current_identity.country,
      first_name: current_identity.first_name,
      last_name: current_identity.last_name,
    )
  end

  def set_address
    @address = current_identity.addresses.find(params[:id])
  end

  def address_params
    params.require(:address).permit(:first_name, :last_name, :line_1, :line_2, :city, :state, :postal_code, :country)
  end
end
