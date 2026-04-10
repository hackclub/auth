import Persona from "persona";

document.addEventListener("DOMContentLoaded", () => {
  const el = document.querySelector("[data-persona-verify]");
  if (!el) return;

  const { inquiryId, sessionToken, statusUrl } = el.dataset;
  const button = el.querySelector("[data-persona-start]");
  const message = el.querySelector("[data-persona-message]");

  const client = new Persona.Client({
    inquiryId,
    sessionToken,
    onComplete: () => {
      if (message) message.textContent = "Verification complete — redirecting…";
      window.location.href = statusUrl;
    },
    onCancel: () => {
      if (message) message.textContent = "No worries — you can pick up where you left off anytime.";
    },
    onError: (error) => {
      console.error("[persona]", error);
      if (message) message.textContent = "Something went wrong. Try again, or use a different verification method.";
    },
  });

  if (button) {
    button.addEventListener("click", () => client.open());
  }
});
