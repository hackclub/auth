// OTP/Code Input behavior with auto-formatting
// Usage: Add data-behavior="otp" to an input element

// Format the code as XXX-XXX
function formatCode(value) {
  const digits = value.replace(/\D/g, '');
  const limited = digits.slice(0, 6);
  if (limited.length > 3) {
    return limited.slice(0, 3) + '-' + limited.slice(3);
  }
  return limited;
}

const extractDigits = (value) => value.replace(/^h[-\s]*/i, '').replace(/\D/g, '');

function initOtpInputs() {
  const inputs = document.querySelectorAll('[data-behavior="otp"]');
  
  inputs.forEach(function(input) {
    // Skip if already initialized
    if (input.dataset.otpInitialized) return;
    input.dataset.otpInitialized = 'true';

    // Handle input event
    function handleInput(e) {
      if (input.dataset.otpFormatting === 'true') return;

      const cursorPos = input.selectionStart;
      const oldValue = input.value;
      const oldLength = oldValue.length;
      
      const formatted = formatCode(oldValue);
      
      if (formatted !== oldValue) {
        input.dataset.otpFormatting = 'true';
        input.value = formatted;
        
        let newCursorPos = cursorPos;
        
        if (formatted.length > oldLength && formatted[3] === '-' && cursorPos === 3) {
          newCursorPos = 4;
        } else if (formatted.length < oldLength) {
          newCursorPos = Math.min(cursorPos, formatted.length);
        } else {
          newCursorPos = cursorPos + (formatted.length - oldLength);
        }
        
        input.setSelectionRange(newCursorPos, newCursorPos);
        
        // Re-dispatch input so bindings (e.g., Alpine x-model) update
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dataset.otpFormatting = 'false';
      }
    }

    // Handle paste event
    function handlePaste(e) {
      e.preventDefault();
      
      const pastedText = (e.clipboardData || window.clipboardData).getData('text');
      const digits = extractDigits(pastedText);
      const formatted = formatCode(digits);
      
      input.value = formatted;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      
      input.setSelectionRange(formatted.length, formatted.length);
    }

    // Handle keydown for better UX
    function handleKeyDown(e) {
      const key = e.key;
      const cursorPos = input.selectionStart;
      const value = input.value;
      
      if (['Backspace', 'Delete', 'Tab', 'Escape', 'Enter', 'ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(key)) {
        if (key === 'Backspace' && cursorPos === 4 && value[3] === '-') {
          e.preventDefault();
          input.value = value.slice(0, 2) + value.slice(4);
          input.setSelectionRange(2, 2);
          input.dispatchEvent(new Event('input', { bubbles: true }));
        }
        return;
      }
      
      if (e.metaKey || e.ctrlKey) {
        return;
      }
      
      if (!/^\d$/.test(key)) {
        e.preventDefault();
      }
    }

    // Attach event listeners
    input.addEventListener('input', handleInput);
    input.addEventListener('paste', handlePaste);
    input.addEventListener('keydown', handleKeyDown);

    // Format on load if there's an existing value
    if (input.value) {
      input.value = formatCode(input.value);
    }
  });
}

// Global paste handler - capture paste anywhere on the page (initialized once)
let globalPasteHandlerAdded = false;

function addGlobalPasteHandler() {
  if (globalPasteHandlerAdded) return;
  globalPasteHandlerAdded = true;
  
  document.addEventListener('paste', function(e) {
    // Don't interfere with pasting into inputs/textareas
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    
    const pastedText = (e.clipboardData || window.clipboardData).getData('text');
    const digits = extractDigits(pastedText);
    
    if (digits.length > 0) {
      // Find the first OTP input on the page
      const otpInput = document.querySelector('[data-behavior="otp"]');
      if (!otpInput) return;
      
      e.preventDefault();
      
      const formatted = formatCode(digits);
      otpInput.value = formatted;
      otpInput.dispatchEvent(new Event('input', { bubbles: true }));
      
      otpInput.focus();
      otpInput.setSelectionRange(formatted.length, formatted.length);
    }
  });
}

// Initialize on page load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', function() {
    initOtpInputs();
    addGlobalPasteHandler();
  });
} else {
  // DOM is already ready
  initOtpInputs();
  addGlobalPasteHandler();
}

// Re-initialize after HTMX swaps (if HTMX is present)
if (window.htmx) {
  document.addEventListener('htmx:afterSwap', initOtpInputs);
}

// Re-initialize after Alpine is ready (if Alpine is present)
document.addEventListener('alpine:initialized', initOtpInputs);

