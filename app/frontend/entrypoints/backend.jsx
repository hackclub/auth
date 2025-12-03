import "../js/click-to-copy";
import { Kbar } from "../components/kbar.jsx";
import { SingleIdentityPicker, MultipleIdentityPicker } from "../components/identity_picker.jsx";

document.addEventListener("DOMContentLoaded", () => {
  const kbar = h(Kbar, null);
  document.body.appendChild(kbar);

  document.querySelectorAll("[data-identity-picker]").forEach((el) => {
    const dataEl = el.querySelector(".picker-initial-data");
    let initialData = {};
    if (dataEl) {
      try {
        initialData = JSON.parse(dataEl.textContent);
      } catch (e) {
        console.error("Failed to parse picker data:", e);
      }
    }
    const Component = initialData.multiple ? MultipleIdentityPicker : SingleIdentityPicker;
    const picker = h(Component, initialData);
    el.replaceWith(picker);
  });
});