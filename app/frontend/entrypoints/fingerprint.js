import FingerprintJS from '@fingerprintjs/fingerprintjs';

document.addEventListener('DOMContentLoaded', async () => {
  console.log('[Fingerprint] Script running');
  const fingerprintInput = document.querySelector('#fingerprint');
  const timezoneInput = document.querySelector('#timezone');
  
  console.log('[Fingerprint] Found inputs:', { fingerprintInput, timezoneInput });
  
  if (!fingerprintInput) {
    console.log('[Fingerprint] No fingerprint input found, exiting');
    return;
  }
  
  // Set timezone immediately
  if (timezoneInput) {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    timezoneInput.value = tz;
    console.log('[Fingerprint] Set timezone:', tz);
  }
  
  // Load fingerprint
  try {
    console.log('[Fingerprint] Loading FingerprintJS...');
    const fp = await FingerprintJS.load();
    const result = await fp.get();
    fingerprintInput.value = result.visitorId;
    console.log('[Fingerprint] Set fingerprint:', result.visitorId);
  } catch (error) {
    console.error('Fingerprint collection failed:', error);
  }
});
