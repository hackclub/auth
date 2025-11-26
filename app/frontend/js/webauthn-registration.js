export function webauthnRegister() {
    return {
        nickname: '',
        loading: false,
        error: null,
        browserSupported: true,

        init() {
            // let's check browser support on initialization
            const hasJsonSupport = !!globalThis.PublicKeyCredential?.parseCreationOptionsFromJSON;
            this.browserSupported = hasJsonSupport;
        },

        async getRegistrationOptions() {
            const response = await fetch('/identity_webauthn_credentials/options', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                }
            });

            if (!response.ok) {
                throw new Error('Failed to get registration options from server');
            }

            return await response.json();
        },

        async register() {
            if (!this.nickname.trim()) {
                this.error = 'Please enter a nickname for your passkey';
                return;
            }

            this.loading = true;
            this.error = null;

            try {
                const options = await this.getRegistrationOptions();
                const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options);
                const credential = await navigator.credentials.create({ publicKey });

                if (!credential) {
                    throw new Error('Credential creation failed');
                }

                const credentialJSON = credential.toJSON();
                const response = await fetch('/identity_webauthn_credentials', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                    },
                    body: JSON.stringify({
                        nickname: this.nickname,
                        ...credentialJSON
                    })
                });

                const result = await response.json();

                if (!response.ok || !result.success) {
                    throw new Error(result.error || 'Failed to register passkey');
                }

                // Success! Redirect to the security page
                window.location.href = result.redirect_url || '/identity_webauthn_credentials';
            } catch (error) {
                console.error('Passkey registration error:', error);

                // Translate error codes to user-friendly messages
                if (error.name === 'NotAllowedError') {
                    this.error = 'Registration was cancelled or not allowed';
                } else if (error.name === 'InvalidStateError') {
                    this.error = 'This passkey is already registered';
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
