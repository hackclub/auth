# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, "https://cdn.jsdelivr.net"
    policy.img_src     :self, :data, :blob, "https://cdn.hackclub.com", "https://hc-cdn.hel1.your-objectstorage.com", "https://user-cdn.hackclub-assets.com"
    policy.object_src  :none
    policy.script_src  :self, "https://maps.googleapis.com"
    policy.style_src   :self
    policy.frame_src   :self, "https://are-we-there-yet.hackclub.com", "https://*.withpersona.com"
    policy.connect_src :self, "https://maps.googleapis.com", "https://*.withpersona.com"

    if Rails.env.development?
      policy.script_src *policy.script_src, "http://#{ViteRuby.config.host_with_port}"
      policy.style_src  *policy.style_src, :unsafe_inline
      policy.connect_src *policy.connect_src, "ws://#{ViteRuby.config.host_with_port}"
    end

    if Rails.env.test?
      policy.script_src *policy.script_src, :blob
    end
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
