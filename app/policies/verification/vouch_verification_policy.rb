class Verification::VouchVerificationPolicy < VerificationPolicy
  def create? = user.super_admin?
end
