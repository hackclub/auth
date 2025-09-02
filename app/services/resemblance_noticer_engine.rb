module ResemblanceNoticerEngine
  TACTICS = [ NameSimilarity, DuplicateDocuments, EmailSubaddressing ]

  def self.run(identity)
    results = TACTICS.flat_map do |tactic|
      tactic.new(identity).run
    end

    results.each &:save!
  end
end
