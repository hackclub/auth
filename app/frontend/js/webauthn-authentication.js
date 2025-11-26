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
                const loginAttemptId = this.getLoginAttemptId();
                const response = await fetch(`/login/${loginAttemptId}/webauthn/verify`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                    },
                    body: JSON.stringify(credentialJSON)
                });

                if (!response.ok) {
                    const result = await response.json();
                    throw new Error(result.error || 'Authentication failed');
                }

                // Success! Redirect to the next page (server will handle this via htmx or full page load)
                window.location.reload();
            } catch (error) {
                console.error('Passkey authentication error:', error);

                // Translate error codes to user-friendly messages
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
