import "../js/click-to-copy";
import "dreamland";
import { Kbar } from "../components/kbar.jsx";

document.addEventListener("DOMContentLoaded", () => {
  const kbar = h(Kbar, null);
  document.body.appendChild(kbar);
});