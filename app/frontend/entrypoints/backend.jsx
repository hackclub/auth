import "../js/click-to-copy";
import { Kbar } from "../components/kbar.jsx";
import { SingleIdentityPicker, MultipleIdentityPicker } from "../components/identity_picker.jsx";
import { NavigableList } from "../components/navigable_list.jsx";

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

  document.querySelectorAll("[data-navigable-list]").forEach((el) => {
    const wrapper = h(NavigableList, null);
    el.parentNode.insertBefore(wrapper, el);
    wrapper.appendChild(el);
  });

  document.addEventListener("keydown", (e) => {
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT") return
    if (e.metaKey || e.ctrlKey) return

    if (e.key === "/") {
      e.preventDefault()
      const searchInput = document.querySelector('input[type="search"]')
      if (searchInput) searchInput.focus()
    }
  })
});