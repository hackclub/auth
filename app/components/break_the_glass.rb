# frozen_string_literal: true

class Components::BreakTheGlass < Components::Base
  attr_reader :break_glassable, :auto_break_glass

  def initialize(break_glassable, auto_break_glass: nil)
    @break_glassable = break_glassable
    @auto_break_glass = auto_break_glass
  end

  def view_template
    if glass_broken?
      yield if block_given?
    else
      render_break_the_glass
    end
  end

  private

  def glass_broken?
    return false unless helpers.user_signed_in?

    # Check if a recent break glass record already exists
    existing_record = BreakGlassRecord.for_user_and_document(helpers.current_user, @break_glassable)
                                      .recent
                                      .exists?

    return true if existing_record

    # If auto_break_glass is enabled, automatically create a break glass record
    if @auto_break_glass
      BreakGlassRecord.create!(
        backend_user: helpers.current_user,
        break_glassable: @break_glassable,
        reason: @auto_break_glass,
        accessed_at: Time.current,
        automatic: true,
      )
      return true
    end

    false
  end

  def render_break_the_glass
    div do
      render Components::BreakTheGlassForm.new(@break_glassable)
    end
  end
end
