export function stepUpWebauthn() {
    return {
        loading: false,
        error: null,
        browserSupported: true,
        initialized: false,

        init() {
            if (this.initialized) return;
            this.initialized = true;

            this.browserSupported = !!(
                globalThis.PublicKeyCredential?.parseRequestOptionsFromJSON &&
                navigator.credentials?.get
            );

            if (this.browserSupported) {
                this.authenticate();
            }
        },

        async authenticate() {
            if (this.loading) return;
            this.loading = true;
            this.error = null;

            try {
                const response = await fetch('/step_up/webauthn/options', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
                    }
                });

                if (!response.ok) {
                    throw new Error('Failed to get authentication options from server');
                }

                const options = await response.json();
                const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(options);
                const credential = await navigator.credentials.get({ publicKey });

                if (!credential) {
                    throw new Error('Authentication failed - no credential returned');
                }

                const credResponse = credential.response;
                const toBase64Url = (buffer) => {
                    return btoa(String.fromCharCode(...new Uint8Array(buffer)))
                        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
                };

                const credentialJSON = {
                    id: credential.id,
                    rawId: toBase64Url(credential.rawId),
                    type: credential.type,
                    response: {
                        clientDataJSON: toBase64Url(credResponse.clientDataJSON),
                        authenticatorData: toBase64Url(credResponse.authenticatorData),
                        signature: toBase64Url(credResponse.signature),
                        userHandle: credResponse.userHandle ? toBase64Url(credResponse.userHandle) : null,
                    },
                    clientExtensionResults: credential.getClientExtensionResults(),
                };

                document.getElementById('step-up-credential-data').value = JSON.stringify(credentialJSON);
                document.getElementById('step-up-webauthn-form').submit();
            } catch (error) {
                console.error('Step-up passkey error:', error);

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
