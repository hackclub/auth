# == Route Map
#
#                                   Prefix Verb   URI Pattern                                                                                       Controller#Action
#               native_oauth_authorization GET    /oauth/authorize/native(.:format)                                                                 doorkeeper/authorizations#show
#                      oauth_authorization GET    /oauth/authorize(.:format)                                                                        doorkeeper/authorizations#new
#                                          DELETE /oauth/authorize(.:format)                                                                        doorkeeper/authorizations#destroy
#                                          POST   /oauth/authorize(.:format)                                                                        doorkeeper/authorizations#create
#                              oauth_token POST   /oauth/token(.:format)                                                                            doorkeeper/tokens#create
#                             oauth_revoke POST   /oauth/revoke(.:format)                                                                           doorkeeper/tokens#revoke
#                         oauth_introspect POST   /oauth/introspect(.:format)                                                                       doorkeeper/tokens#introspect
#                       oauth_applications GET    /oauth/applications(.:format)                                                                     doorkeeper/applications#index
#                                          POST   /oauth/applications(.:format)                                                                     doorkeeper/applications#create
#                    new_oauth_application GET    /oauth/applications/new(.:format)                                                                 doorkeeper/applications#new
#                   edit_oauth_application GET    /oauth/applications/:id/edit(.:format)                                                            doorkeeper/applications#edit
#                        oauth_application GET    /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#show
#                                          PATCH  /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#update
#                                          PUT    /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#update
#                                          DELETE /oauth/applications/:id(.:format)                                                                 doorkeeper/applications#destroy
#            oauth_authorized_applications GET    /oauth/authorized_applications(.:format)                                                          doorkeeper/authorized_applications#index
#             oauth_authorized_application DELETE /oauth/authorized_applications/:id(.:format)                                                      doorkeeper/authorized_applications#destroy
#                         oauth_token_info GET    /oauth/token/info(.:format)                                                                       doorkeeper/token_info#show
#                        letter_opener_web        /letter_opener                                                                                    LetterOpenerWeb::Engine
#                active_storage_encryption        /encrypted_blobs                                                                                  ActiveStorageEncryption::Engine
#                       static_pages_index GET    /static_pages/index(.:format)                                                                     static_pages#index
#                credentials_enroll_window GET    /credentials/enroll_window(.:format)                                                              credentials#enroll_window
#                       credentials_enroll GET    /credentials/enroll(.:format)                                                                     credentials#enroll
#                 backend_identities_index GET    /backend/identities/index(.:format)                                                               backend/identities#index
#                  backend_identities_show GET    /backend/identities/show(.:format)                                                                backend/identities#show
#                         backend_good_job        /backend/good_job                                                                                 GoodJob::Engine
#                       backend_audit_logs GET    /backend/audit_logs(.:format)                                                                     backend/audit_logs#index
#                             backend_root GET    /backend(.:format)                                                                                backend/static_pages#index
#                            backend_login GET    /backend/login(.:format)                                                                          backend/static_pages#login
#                       backend_slack_auth GET    /backend/auth/slack(.:format)                                                                     backend/sessions#new
#              backend_auth_slack_callback GET    /backend/auth/slack/callback(.:format)                                                            backend/sessions#create
#      backend_fake_slack_callback_for_dev POST   /backend/auth/slack/fake(.:format)                                                                backend/sessions#fake_slack_callback_for_dev
#                  deactivate_backend_user POST   /backend/users/:id/deactivate(.:format)                                                           backend/users#deactivate
#                    activate_backend_user POST   /backend/users/:id/activate(.:format)                                                             backend/users#activate
#                            backend_users GET    /backend/users(.:format)                                                                          backend/users#index
#                                          POST   /backend/users(.:format)                                                                          backend/users#create
#                         new_backend_user GET    /backend/users/new(.:format)                                                                      backend/users#new
#                        edit_backend_user GET    /backend/users/:id/edit(.:format)                                                                 backend/users#edit
#                             backend_user GET    /backend/users/:id(.:format)                                                                      backend/users#show
#                                          PATCH  /backend/users/:id(.:format)                                                                      backend/users#update
#                                          PUT    /backend/users/:id(.:format)                                                                      backend/users#update
#                                          DELETE /backend/users/:id(.:format)                                                                      backend/users#destroy
#            pending_backend_verifications GET    /backend/verifications/pending(.:format)                                                          backend/verifications#pending
#             approve_backend_verification PATCH  /backend/verifications/:id/approve(.:format)                                                      backend/verifications#approve
#              reject_backend_verification PATCH  /backend/verifications/:id/reject(.:format)                                                       backend/verifications#reject
#                    backend_verifications GET    /backend/verifications(.:format)                                                                  backend/verifications#index
#                     backend_verification GET    /backend/verifications/:id(.:format)                                                              backend/verifications#show
#                       backend_identities GET    /backend/identities(.:format)                                                                     backend/identities#index
#                         backend_identity GET    /backend/identities/:id(.:format)                                                                 backend/identities#show
#                         backend_programs GET    /backend/programs(.:format)                                                                       backend/programs#index
#                                          POST   /backend/programs(.:format)                                                                       backend/programs#create
#                      new_backend_program GET    /backend/programs/new(.:format)                                                                   backend/programs#new
#                     edit_backend_program GET    /backend/programs/:id/edit(.:format)                                                              backend/programs#edit
#                          backend_program GET    /backend/programs/:id(.:format)                                                                   backend/programs#show
#                                          PATCH  /backend/programs/:id(.:format)                                                                   backend/programs#update
#                                          PUT    /backend/programs/:id(.:format)                                                                   backend/programs#update
#                                          DELETE /backend/programs/:id(.:format)                                                                   backend/programs#destroy
#                      backend_break_glass POST   /backend/break_glass(.:format)                                                                    backend/break_glass#create
#                                     root GET    /                                                                                                 static_pages#index
#                check_your_email_sessions GET    /sessions/check_your_email(.:format)                                                              sessions#check_your_email
#                          verify_sessions GET    /sessions/verify(.:format)                                                                        sessions#verify
#                         confirm_sessions POST   /sessions/confirm(.:format)                                                                       sessions#confirm
#                             new_sessions GET    /sessions/new(.:format)                                                                           sessions#new
#                                 sessions DELETE /sessions(.:format)                                                                               sessions#destroy
#                                          POST   /sessions(.:format)                                                                               sessions#create
#                       welcome_onboarding GET    /onboarding/welcome(.:format)                                                                     onboardings#welcome
#                        signin_onboarding GET    /onboarding/signin(.:format)                                                                      onboardings#signin
#                    basic_info_onboarding GET    /onboarding/basic_info(.:format)                                                                  onboardings#basic_info
#                                          POST   /onboarding/basic_info(.:format)                                                                  onboardings#create_basic_info
#                      document_onboarding GET    /onboarding/document(.:format)                                                                    onboardings#document
#                                          POST   /onboarding/document(.:format)                                                                    onboardings#create_document
#                     submitted_onboarding GET    /onboarding/submitted(.:format)                                                                   onboardings#submitted
#                      continue_onboarding GET    /onboarding/continue(.:format)                                                                    onboardings#continue
#                               onboarding GET    /onboarding(.:format)                                                                             onboardings#show
#                                addresses GET    /addresses(.:format)                                                                              addresses#index
#                                          POST   /addresses(.:format)                                                                              addresses#create
#                              new_address GET    /addresses/new(.:format)                                                                          addresses#new
#                             edit_address GET    /addresses/:id/edit(.:format)                                                                     addresses#edit
#                                  address GET    /addresses/:id(.:format)                                                                          addresses#show
#                                          PATCH  /addresses/:id(.:format)                                                                          addresses#update
#                                          PUT    /addresses/:id(.:format)                                                                          addresses#update
#                                          DELETE /addresses/:id(.:format)                                                                          addresses#destroy
#                        api_v1_identities GET    /api/v1/identities(.:format)                                                                      api/v1/identities#index
#                          api_v1_identity GET    /api/v1/identities/:id(.:format)                                                                  api/v1/identities#show
#                                api_v1_me GET    /api/v1/me(.:format)                                                                              api/v1/identities#me
#                               api_v1_hcb GET    /api/v1/hcb(.:format)                                                                             api/v1/hcb#show
#                       link_slack_account GET    /slack/link(.:format)                                                                             slack_accounts#new
#                   slack_account_callback GET    /slack/callback(.:format)                                                                         slack_accounts#create
#                       rails_health_check GET    /up(.:format)                                                                                     rails/health#show
#            rails_postmark_inbound_emails POST   /rails/action_mailbox/postmark/inbound_emails(.:format)                                           action_mailbox/ingresses/postmark/inbound_emails#create
#               rails_relay_inbound_emails POST   /rails/action_mailbox/relay/inbound_emails(.:format)                                              action_mailbox/ingresses/relay/inbound_emails#create
#            rails_sendgrid_inbound_emails POST   /rails/action_mailbox/sendgrid/inbound_emails(.:format)                                           action_mailbox/ingresses/sendgrid/inbound_emails#create
#      rails_mandrill_inbound_health_check GET    /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#health_check
#            rails_mandrill_inbound_emails POST   /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#create
#             rails_mailgun_inbound_emails POST   /rails/action_mailbox/mailgun/inbound_emails/mime(.:format)                                       action_mailbox/ingresses/mailgun/inbound_emails#create
#           rails_conductor_inbound_emails GET    /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#index
#                                          POST   /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#create
#        new_rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/new(.:format)                                      rails/conductor/action_mailbox/inbound_emails#new
#            rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/:id(.:format)                                      rails/conductor/action_mailbox/inbound_emails#show
# new_rails_conductor_inbound_email_source GET    /rails/conductor/action_mailbox/inbound_emails/sources/new(.:format)                              rails/conductor/action_mailbox/inbound_emails/sources#new
#    rails_conductor_inbound_email_sources POST   /rails/conductor/action_mailbox/inbound_emails/sources(.:format)                                  rails/conductor/action_mailbox/inbound_emails/sources#create
#    rails_conductor_inbound_email_reroute POST   /rails/conductor/action_mailbox/:inbound_email_id/reroute(.:format)                               rails/conductor/action_mailbox/reroutes#create
# rails_conductor_inbound_email_incinerate POST   /rails/conductor/action_mailbox/:inbound_email_id/incinerate(.:format)                            rails/conductor/action_mailbox/incinerates#create
#                       rails_service_blob GET    /rails/active_storage/blobs/redirect/:signed_id/*filename(.:format)                               active_storage/blobs/redirect#show
#                 rails_service_blob_proxy GET    /rails/active_storage/blobs/proxy/:signed_id/*filename(.:format)                                  active_storage/blobs/proxy#show
#                                          GET    /rails/active_storage/blobs/:signed_id/*filename(.:format)                                        active_storage/blobs/redirect#show
#                rails_blob_representation GET    /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename(.:format) active_storage/representations/redirect#show
#          rails_blob_representation_proxy GET    /rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename(.:format)    active_storage/representations/proxy#show
#                                          GET    /rails/active_storage/representations/:signed_blob_id/:variation_key/*filename(.:format)          active_storage/representations/redirect#show
#                       rails_disk_service GET    /rails/active_storage/disk/:encoded_key/*filename(.:format)                                       active_storage/disk#show
#                update_rails_disk_service PUT    /rails/active_storage/disk/:encoded_token(.:format)                                               active_storage/disk#update
#                     rails_direct_uploads POST   /rails/active_storage/direct_uploads(.:format)                                                    active_storage/direct_uploads#create
#
# Routes for LetterOpenerWeb::Engine:
#       letters GET  /                                letter_opener_web/letters#index
# clear_letters POST /clear(.:format)                 letter_opener_web/letters#clear
#        letter GET  /:id(/:style)(.:format)          letter_opener_web/letters#show
# delete_letter POST /:id/delete(.:format)            letter_opener_web/letters#destroy
#               GET  /:id/attachments/:file(.:format) letter_opener_web/letters#attachment {file: /[^\/]+/}
#
# Routes for ActiveStorageEncryption::Engine:
#                  encrypted_blob_put PUT  /blob/:token(.:format)           active_storage_encryption/encrypted_blobs#update
# create_encrypted_blob_direct_upload POST /blob/direct-uploads(.:format)   active_storage_encryption/encrypted_blobs#create_direct_upload
#        encrypted_blob_streaming_get GET  /blob/:token/*filename(.:format) active_storage_encryption/encrypted_blob_proxy#show
#
# Routes for GoodJob::Engine:
#                root GET    /                                         good_job/jobs#redirect_to_index
#    mass_update_jobs GET    /jobs/mass_update(.:format)               redirect(301, path: jobs)
#                     PUT    /jobs/mass_update(.:format)               good_job/jobs#mass_update
#         discard_job PUT    /jobs/:id/discard(.:format)               good_job/jobs#discard
#   force_discard_job PUT    /jobs/:id/force_discard(.:format)         good_job/jobs#force_discard
#      reschedule_job PUT    /jobs/:id/reschedule(.:format)            good_job/jobs#reschedule
#           retry_job PUT    /jobs/:id/retry(.:format)                 good_job/jobs#retry
#                jobs GET    /jobs(.:format)                           good_job/jobs#index
#                 job GET    /jobs/:id(.:format)                       good_job/jobs#show
#                     DELETE /jobs/:id(.:format)                       good_job/jobs#destroy
# metrics_primary_nav GET    /jobs/metrics/primary_nav(.:format)       good_job/metrics#primary_nav
#  metrics_job_status GET    /jobs/metrics/job_status(.:format)        good_job/metrics#job_status
#         retry_batch PUT    /batches/:id/retry(.:format)              good_job/batches#retry
#             batches GET    /batches(.:format)                        good_job/batches#index
#               batch GET    /batches/:id(.:format)                    good_job/batches#show
#  enqueue_cron_entry POST   /cron_entries/:cron_key/enqueue(.:format) good_job/cron_entries#enqueue
#   enable_cron_entry PUT    /cron_entries/:cron_key/enable(.:format)  good_job/cron_entries#enable
#  disable_cron_entry PUT    /cron_entries/:cron_key/disable(.:format) good_job/cron_entries#disable
#        cron_entries GET    /cron_entries(.:format)                   good_job/cron_entries#index
#          cron_entry GET    /cron_entries/:cron_key(.:format)         good_job/cron_entries#show
#           processes GET    /processes(.:format)                      good_job/processes#index
#   performance_index GET    /performance(.:format)                    good_job/performance#index
#         performance GET    /performance/:id(.:format)                good_job/performance#show
#              pauses POST   /pauses(.:format)                         good_job/pauses#create
#                     DELETE /pauses(.:format)                         good_job/pauses#destroy
#                     GET    /pauses(.:format)                         good_job/pauses#index
#       cleaner_index GET    /cleaner(.:format)                        good_job/cleaner#index
#     frontend_module GET    /frontend/modules/:version/:id(.:format)  good_job/frontends#module {version: "4-10-2", format: "js"}
#     frontend_static GET    /frontend/static/:version/:id(.:format)   good_job/frontends#static {version: "4-10-2"}

class SuperAdminConstraint
  def self.matches?(request)
    return false unless request.session[:user_id]

    user = Backend::User.find_by(id: request.session[:user_id])
    user&.super_admin?
  end
end

Rails.application.routes.draw do
  use_doorkeeper
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
  mount ActiveStorageEncryption::Engine, at: "/encrypted_blobs"

  # Image conversion routes

  get "static_pages/index"
  namespace :backend do
    get "identities/index"
    get "identities/show"
    constraints SuperAdminConstraint do
      mount GoodJob::Engine => "good_job"
      mount Audits1984::Engine => "/console_audit"
      mount Flipper::UI.app(Flipper) => "/flipper", as: :flipper
    end
    resources :audit_logs, only: [ :index ]
    get "dashboard", to: "dashboard#show", as: :dashboard
    root "static_pages#index", as: :root
    get "login", to: "static_pages#login", as: :login
    get "session_dump", to: "static_pages#session_dump", as: :session_dump unless Rails.env.production?

    get "/auth/slack", to: "sessions#new", as: :slack_auth
    get "/auth/slack/callback", to: "sessions#create"

    if Rails.env.development?
      post "/auth/slack/fake", to: "sessions#fake_slack_callback_for_dev", as: :fake_slack_callback_for_dev
    end

    resources :users do
      member do
        post :deactivate
        post :activate
      end
    end

    resources :verifications, only: [ :index, :show ] do
      collection do
        get :pending
      end
      member do
        patch :approve
        patch :reject
        patch :ignore
      end
    end

    resources :identities do
      member do
        post :clear_slack_id
        post :reprovision_slack
        get :new_vouch
        post :create_vouch
        post :promote_to_full_user
      end
    end

    resources :programs

    post "/break_glass", to: "break_glass#create"

    scope :json do
      defaults format: :json do
      end
    end
  end

  root "static_pages#home"

  get "/welcome", to: "static_pages#welcome", as: :welcome
  get "/oauth/welcome", to: "static_pages#oauth_welcome", as: :oauth_welcome
  get "/faq", to: "static_pages#faq", as: :faq
  get "/security", to: "static_pages#security", as: :security

  # Login system routes
  resource :sessions, only: [ :new, :create, :destroy ] do
    collection do
      get :check_your_email
      get :verify
      post :confirm
    end
  end

  resource :identity, only: [ :edit, :update ] do
    collection do
      post :toggle_2fa
    get :confirm_disable_2fa
    end
  end

  get "/signup", to: "identities#new", defaults: { route_context: "signup" }, as: :signup
  post "/signup", to: "identities#create", defaults: { route_context: "signup" }
  get "/migrate", to: "identities#new", defaults: { route_context: "migrate" }, as: :migrate
  post "/migrate", to: "identities#create", defaults: { route_context: "migrate" }
  get "/join/:slug", to: "identities#new", defaults: { route_context: "join" }, as: :join
  post "/join/:slug", to: "identities#create", defaults: { route_context: "join" }

  get "/login", to: "logins#new", as: :login
  post "/login", to: "logins#create"
  get "/login/:id", to: "logins#show", as: :login_attempt
  post "/login/:id/verify", to: "logins#verify", as: :verify_login_attempt
  post "/login/:id/resend", to: "logins#resend", as: :resend_login_attempt

  get "/login/:id/totp", to: "logins#totp", as: :totp_login_attempt
  post "/login/:id/totp", to: "logins#verify_totp", as: :verify_totp_login_attempt
  get "/login/:id/backup_code", to: "logins#backup_code", as: :backup_code_login_attempt
  post "/login/:id/backup_code", to: "logins#verify_backup_code", as: :verify_backup_code_login_attempt

  delete "/logout", to: "sessions#logout", as: :logout

  get "/verifications/new", to: "verifications#new", as: :new_verifications
  get "/verifications/status", to: "verifications#status", as: :verification_status
  get "/verifications/:id", to: "verifications#show", as: :verification_step
  put "/verifications/:id", to: "verifications#update", as: :update_verification_step

  resources :addresses do
    collection do
      get :program_create_address
    end
  end

  resources :identity_sessions, only: [ :index, :destroy ] do
    collection do
      delete :destroy_all
    end
  end

  resources :identity_totps, only: [ :index, :new, :destroy ] do
    member do
      post :verify
    end
  end

  # Step-up authentication flow
  get "/step_up", to: "step_up#new", as: :new_step_up
  post "/step_up/verify", to: "step_up#verify", as: :verify_step_up

  resources :identity_backup_codes, only: [ :index, :create ] do
    patch :confirm, on: :collection
  end

  resources :authorized_applications, only: [ :index, :destroy ]

  resources :developer_apps, path: "developer/apps"

  namespace :api do
    namespace :v1 do
      resources :identities, only: [ :show, :index ] do
        member do
          post :set_slack_id
        end
      end
      get "/me", to: "identities#me"
      get "/hcb", to: "hcb#show"
      get "/health_check", to: "health_check#show"
    end
    namespace :external do
      get "/check", to: "identities#check"
    end
  end

  get "/api/external", to: "static_pages#external_api_docs"

  get "/slack_staging", to: "static_pages#slack_staging" if Rails.env.staging?

  # Slack interactivity routes
  namespace :slack do
    post "/interactivity", to: "interactivity#create"
  end

  scope :saml do
    get "/metadata", to: "saml#metadata"
    get "/welcome", to: "saml#welcome", as: :saml_welcome
    post "/idp_initiated/:slug", to: "saml#idp_initiated", as: :idp_initiated_saml
    get "/auth", to: "saml#sp_initiated_get"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
