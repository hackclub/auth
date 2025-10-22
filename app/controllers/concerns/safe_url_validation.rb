module SafeUrlValidation
  extend ActiveSupport::Concern

  private

  def url_from(param)
    return nil if param.blank?

    s = param.to_s

    return nil if s.match?(/[\x00-\x1F]/) || s.include?("\\")

    uri = URI.parse(s)

    return s if uri.relative? && s.start_with?("/") && !s.start_with?("//")

    nil
  rescue URI::InvalidURIError
    nil
  end
end
