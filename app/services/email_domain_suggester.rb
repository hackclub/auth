class EmailDomainSuggester
  COMMON_DOMAINS = %w[
    gmail.com
    icloud.com
    outlook.com
    outlook.de
    outlook.fr
    proton.me
    hotmail.com
    yahoo.com
    duck.com
    protonmail.com
    qq.com
    gmx.de
    gmx.at
    web.de
    pm.me
    live.com
    mail.com
    mail.ru
    163.com
    tutamail.com
    mozmail.com
    seznam.cz
  ].freeze

  MAX_DISTANCE = 2

  def self.suggest(email)
    return nil if email.nil? || email.empty? || !email.include?("@")

    local, domain = email.split("@", 2)
    return nil if domain.nil? || domain.empty?

    domain = domain.downcase
    return nil if COMMON_DOMAINS.include?(domain)

    best_match = nil
    best_distance = MAX_DISTANCE + 1

    COMMON_DOMAINS.each do |known|
      distance = DamerauLevenshtein.distance(domain, known)
      if distance <= MAX_DISTANCE && distance < best_distance
        best_distance = distance
        best_match = known
      end
    end

    return nil unless best_match

    "#{local}@#{best_match}"
  end
end
