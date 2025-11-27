export function webauthnAuth() {
    return {
        loading: false,
        error: null,
        browserSupported: true,

        init() {
            this.browserSupported = !!(
                globalThis.PublicKeyCredential?.parseRequestOptionsFromJSON &&
                navigator.credentials?.get
            );

            if (this.browserSupported) {
                this.authenticate();
            }
        },

        getLoginAttemptId() {
            const pathParts = window.location.pathname.split('/');
            const loginIndex = pathParts.indexOf('login');
            if (loginIndex >= 0 && pathParts.length > loginIndex + 1) {
                return pathParts[loginIndex + 1];
            }
            throw new Error('Could not determine login attempt ID');
        },

        async getAuthenticationOptions() {
            const loginAttemptId = this.getLoginAttemptId();
            const response = await fetch(`/login/${loginAttemptId}/webauthn/options`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                }
            });

            if (!response.ok) {
                throw new Error('Failed to get authentication options from server');
            }

            return await response.json();
        },

        async authenticate() {
            this.loading = true;
            this.error = null;

            try {
                const options = await this.getAuthenticationOptions();
                const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(options);
                const credential = await navigator.credentials.get({ publicKey });

                if (!credential) {
                    throw new Error('Authentication failed - no credential returned');
                }

                const credentialJSON = credential.toJSON();

                const credentialDataField = document.getElementById('credential-data');
                const form = document.getElementById('webauthn-form');

                if (!credentialDataField || !form) {
                    throw new Error('Form elements not found');
                }

                credentialDataField.value = JSON.stringify(credentialJSON);
                form.submit();
            } catch (error) {
                console.error('Passkey authentication error:', error);

                if (error.name === 'NotAllowedError') {
                    this.error = 'Authentication was cancelled or not allowed';
                } else if (error.name === 'InvalidStateError') {
                    this.error = 'No passkey found for this account';
                } else if (error.name === 'NotSupportedError') {
                    this.error = 'Passkeys are not supported on this device';
                } else {
                    this.error = error.message || 'An unexpected error occurred';
                }

                this.loading = false;
            }
        }
    };
}
