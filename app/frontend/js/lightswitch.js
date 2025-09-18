function getPreferred() {
    const savedTheme = localStorage.getItem("theme");
    if (savedTheme) {
        return savedTheme;
    }
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

// Get the current theme that was already set in the head
const savedTheme = getPreferred();

function updateIcon(theme) {
    const icon = document.querySelector(".lightswitch-icon");
    if (icon) {
        icon.textContent = theme === "dark" ? "💡" : "🌙";
    }
}

document.body.parentElement.dataset.theme = savedTheme;
updateIcon(savedTheme);
const lightswitchBtn = document.getElementById("lightswitch");
if (lightswitchBtn) {
    lightswitchBtn.classList.add("theme-loaded");
}

window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    if (!localStorage.getItem("theme")) {
        const theme = e.matches ? "dark" : "light";
        document.body.parentElement.dataset.theme = theme;
        updateIcon(theme);
    }
});

document.getElementById("lightswitch").addEventListener("click", () => {
    const theme = document.body.parentElement.dataset.theme === "dark" ? "light" : "dark";
    document.body.parentElement.dataset.theme = theme;
    localStorage.setItem("theme", theme);
    updateIcon(theme);
});