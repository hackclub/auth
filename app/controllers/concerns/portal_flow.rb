module PortalFlow
  extend ActiveSupport::Concern

  included do
    before_action :validate_portal_return_url, only: [ :start, :portal ]
    before_action :store_return_url, only: [ :start, :portal ]
  end

  private

  def portal_return_url
    session[:portal_return_to] || params[:return_to]
  end

  def store_return_url
    session[:portal_return_to] = validated_return_url if params[:return_to].present?
  end

  def validate_portal_return_url
    unless validated_return_url || session[:portal_return_to]
      flash[:error] = "Invalid or missing return URL"
      redirect_to root_path
    end
  end

  def validated_return_url
    return @validated_return_url if defined?(@validated_return_url)

    url = params[:return_to]
    return @validated_return_url = nil if url.blank?

    begin
      uri = URI.parse(url)
      host = uri.host
      return @validated_return_url = nil unless host

      allowed_hosts = Program.official.pluck(:redirect_uri).flat_map { |uris|
        uris.to_s.split("\n").filter_map { |u| URI.parse(u).host rescue nil }
      }.uniq
      allowed_hosts << "localhost" unless Rails.env.production?

      @validated_return_url = allowed_hosts.include?(host) ? url : nil
    rescue URI::InvalidURIError
      @validated_return_url = nil
    end
  end

  def redirect_to_portal_return(status: :success, notice: nil)
    return_url = portal_return_url
    session.delete(:portal_return_to)

    uri = URI.parse(return_url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["portal_status"] = status.to_s
    uri.query = URI.encode_www_form(params)

    redirect_to uri.to_s, notice: notice, allow_other_host: true
  end

  def cancel_portal_flow
    redirect_to_portal_return(status: :canceled)
  end

  def redirect_to_simple_return
    return_url = portal_return_url
    session.delete(:portal_return_to)
    redirect_to return_url, allow_other_host: true
  end
end
