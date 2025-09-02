module IsSneaky
  extend ActiveSupport::Concern

  def hide_some_data_away
    if params[:stash_data]
      stash = begin
                b64ed = Base64.urlsafe_decode64(params[:stash_data]).force_encoding("UTF-8")
                unlzed = LZString::UTF16.decompress(b64ed)
                JSON.parse(unlzed)
              rescue StandardError
                {}
              end
      request.reset_session if stash["invalidate_session"]
      session[:stashed_data] = stash
    end
  end

  def safe_redirect_url(key)
    return unless session[:stashed_data]&.[](key)
    redirect_url = session[:stashed_data][key]
    redirect_domain = URI.parse(redirect_url).host rescue nil
    return unless redirect_domain
    allowed_domains = Program.pluck(:redirect_uri).flat_map { |uri|
      uri.split("\n").map { |u| URI.parse(u).host rescue nil }
    }.compact.uniq
    allowed_domains << "localhost" unless Rails.env.production?

    if allowed_domains.include?(redirect_domain)
      redirect_url
    else
      nil
    end
  end
end
