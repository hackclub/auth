module IdentityAware
  extend ActiveSupport::Concern

  private

  def backend_user
    case user
    when Backend::User then user
    when Identity then user.backend_user
    end
  end

  def identity
    case user
    when Identity then user
    when Backend::User then user.identity
    end
  end

  def owns?
    record.respond_to?(:identity) && record.identity == identity
  end

  def super_admin?
    backend_user&.super_admin?
  end

  def program_manager?
    backend_user&.program_manager?
  end
end
