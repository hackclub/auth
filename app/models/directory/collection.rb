module Directory
  class Collection < ApplicationRecord
    self.table_name = "directory_collections"
    self.inheritance_column = "kind"

    has_paper_trail
    include PublicActivity::Model
    tracked owner: ->(controller, _model) { controller&.try(:user_for_public_activity) }

    belongs_to :created_by, class_name: "Identity", foreign_key: :created_by_identity_id, optional: true

    has_many :memberships, class_name: "Directory::Membership", foreign_key: :collection_id, dependent: :destroy
    has_many :member_people_memberships, -> { where.not(member_person_id: nil) },
             class_name: "Directory::Membership", foreign_key: :collection_id
    has_many :member_group_memberships, -> { where.not(member_group_id: nil) },
             class_name: "Directory::Membership", foreign_key: :collection_id
    has_many :direct_people, through: :member_people_memberships, source: :member_person
    has_many :direct_groups, through: :member_group_memberships, source: :member_group

    has_many :effective_memberships, class_name: "Directory::EffectiveMembership", dependent: :delete_all
    has_many :effective_people, through: :effective_memberships, source: :person

    has_many :grants_as_target, class_name: "Directory::Grant", foreign_key: :target_collection_id, dependent: :destroy
    has_many :grants_as_grantee, class_name: "Directory::Grant", foreign_key: :grantee_group_id, dependent: :destroy

    has_many :parent_memberships, -> { where.not(member_group_id: nil) },
             class_name: "Directory::Membership", foreign_key: :member_group_id
    has_many :parent_collections, through: :parent_memberships, source: :collection

    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
    validates :name, presence: true
    validates :kind, inclusion: { in: %w[group entitlement] }

    scope :groups, -> { where(kind: "group") }
    scope :entitlements, -> { where(kind: "entitlement") }

    def group? = kind == "group"
    def entitlement? = kind == "entitlement"

    def direct_member_count = memberships.count
    def effective_member_count = effective_memberships.count

    def self.find_sti_class(type_name)
      case type_name
      when "group" then Directory::Group
      when "entitlement" then Directory::Entitlement
      else super
      end
    end

    def self.sti_class_for(type_name)
      find_sti_class(type_name)
    end
  end
end
