# frozen_string_literal: true

module RuboCop
  module Cop
    module Custom
      class FlipperFlagDated < Base
        MSG = "Flipper flag `:%<flag>s` must end with a date suffix (`_YYYY_MM_DD`)."
        DATE_SUFFIX = /_\d{4}_\d{2}_\d{2}\z/

        # Flipper.enabled?(:flag, ...) / Flipper.enable(:flag) / etc.
        # @!method flipper_flag_symbol(node)
        def_node_matcher :flipper_call, <<~PATTERN
          (send (const nil? :Flipper) {:enabled? :enable :disable :enable_actor :disable_actor} $(sym _) ...)
        PATTERN

        def on_send(node)
          flipper_call(node) do |flag_node|
            flag = flag_node.value.to_s
            return if flag.match?(DATE_SUFFIX)

            add_offense(flag_node, message: format(MSG, flag: flag))
          end
        end
      end
    end
  end
end
