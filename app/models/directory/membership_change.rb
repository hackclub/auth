module Directory
  class MembershipChange < ApplicationRecord
    self.table_name = "directory_membership_changes"

    belongs_to :collection, class_name: "Directory::Collection", optional: true
    belongs_to :person, class_name: "Directory::Person", optional: true

    scope :added, -> { where(op: "added") }
    scope :removed, -> { where(op: "removed") }
  end
end
