const authenticateWebauthn = {
    checkBrowserSupport() {
        const hasJsonSupport = !!globalThis.PublicKeyCredential?.parseRequestOptionsFromJSON;

        if (!hasJsonSupport) {
            this.showBrowserWarning();
            return false;
        }

        return true;
    },

    showBrowserWarning() {
        const warning = document.getElementById('browser-support-warning');
        const authContainer = document.querySelector('.passkey-auth');

        if (warning) warning.style.display = 'block';
        if (authContainer) authContainer.style.display = 'none';
    },

    async getAuthenticationOptions() {
        // Fetch authentication options from the server
        // The server will generate a cryptographic challenge
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
        try {
            const options = await this.getAuthenticationOptions(); // fetch our options + challenge
            console.log('Authentication options:', options);

            const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(options);
            console.log('Parsed request options:', publicKey);

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

            console.log('Authentication successful');

            window.location.reload(); // TODO

            return {
                success: true
            };
        } catch (error) {
            console.error('Passkey authentication error:', error);

            let errorMessage = 'An unexpected error occurred';

            if (error.name === 'NotAllowedError') {
                errorMessage = 'Authentication was cancelled or not allowed';
            } else if (error.name === 'InvalidStateError') {
                errorMessage = 'No passkey found for this account';
            } else if (error.name === 'NotSupportedError') {
                errorMessage = 'Passkeys are not supported on this device';
            } else if (error.message) {
                errorMessage = error.message;
            }

            return {
                success: false,
                error: errorMessage
            };
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

    async handleAuthenticate() {
        const authBtn = document.getElementById('authenticate-btn');
        const btnText = authBtn?.querySelector('.btn-text');
        const btnSpinner = authBtn?.querySelector('.btn-spinner');
        const errorAlert = document.getElementById('webauthn-auth-error');
        const errorMessage = document.getElementById('error-message');

        if (authBtn) {
            authBtn.disabled = true;
            if (btnText) btnText.style.display = 'none';
            if (btnSpinner) btnSpinner.style.display = 'inline';
        }

        if (errorAlert) errorAlert.style.display = 'none';

        const result = await this.authenticate();

        if (authBtn) {
            authBtn.disabled = false;
            if (btnText) btnText.style.display = 'inline';
            if (btnSpinner) btnSpinner.style.display = 'none';
        }

        if (!result.success) {
            if (errorMessage) errorMessage.textContent = result.error;
            if (errorAlert) errorAlert.style.display = 'block';
        }
    },

    init() {
        if (!this.checkBrowserSupport()) {
            return;
        }

        const container = document.getElementById('passkey-auth-container');
        if (container && !container.dataset.webauthnInitialized) {
            this.handleAuthenticate();
            container.dataset.webauthnInitialized = 'true';
        }

        const authBtn = document.getElementById('authenticate-btn');
        if (authBtn && !authBtn.dataset.webauthnInitialized) {
            authBtn.addEventListener('click', () => this.handleAuthenticate());
            authBtn.dataset.webauthnInitialized = 'true';
        }
    }
};

export { authenticateWebauthn };
