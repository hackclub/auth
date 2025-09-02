module PapersPleaseEngine
  def self.run(verification)
    tactics = case verification
    when Verification::DocumentVerification
        [] # maybe someday OCR documents & check for discrepancies?
    when Verification::AadhaarVerification
        [ AadhaarScrutinizer ]
    end

    issues = tactics.flat_map do |tactic|
      tactic.new(verification).run
    end

    if issues.any?
      verification.update(issues:)
    end
  end
end
