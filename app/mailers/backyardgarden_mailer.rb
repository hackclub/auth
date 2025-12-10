class BackyardGarden_Mailer < ApplicationMailer
    def first_email(identity)
        @identity = identity
        @first_name = @identity.first_name
    
        mail(
          to: @identity.primary_email,
          subject: "Hack Club Onboarding"
        )
      end

    def ysws_email(identity)
        @identity = identity
        @first_name = @identity.first_name
    
        mail(
          to: @identity.primary_email,
          subject: "YSWS Onboarding"
        )
      end

    def community_events(identity)
        @identity = identity
        @first_name = @identity.first_name
    
        mail(
          to: @identity.primary_email,
          subject: "Community Events Onboarding"
        )
      end

      def clubs_email(identity)
        @identity = identity
        @first_name = @identity.first_name
    
        mail(
          to: @identity.primary_email,
          subject: "Putting the Club in Hack Club"
        )
      end

end