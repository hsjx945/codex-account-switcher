const root = document.documentElement;
const themeButton = document.querySelector("[data-theme-toggle]");
const colorPreference = window.matchMedia("(prefers-color-scheme: dark)");
const requestedLanguage = new URLSearchParams(window.location.search).get("lang")?.toLowerCase();

function localizedPath(language) {
  const alternate = document.querySelector(`link[rel="alternate"][hreflang="${language}"]`);
  if (!alternate) return null;

  const alternatePath = new URL(alternate.href).pathname;
  const currentLanguage = root.lang.toLowerCase() === "zh-cn" ? "zh-CN" : "en";
  const currentAlternate = document.querySelector(
    `link[rel="alternate"][hreflang="${currentLanguage}"]`,
  );
  const canonicalCurrentPath = currentAlternate ? new URL(currentAlternate.href).pathname : "";
  const deploymentPrefix = canonicalCurrentPath.endsWith(window.location.pathname)
    ? canonicalCurrentPath.slice(0, -window.location.pathname.length)
    : "";
  return deploymentPrefix && alternatePath.startsWith(deploymentPrefix)
    ? alternatePath.slice(deploymentPrefix.length) || "/"
    : alternatePath;
}

if ((requestedLanguage === "zh" || requestedLanguage === "zh-cn") && root.lang === "en") {
  const target = new URL(window.location.href);
  target.pathname = localizedPath("zh-CN")
    ?? `/zh-CN${target.pathname.startsWith("/") ? target.pathname : `/${target.pathname}`}`;
  target.search = "";
  window.location.replace(target);
}

if (requestedLanguage === "en" && root.lang.toLowerCase() === "zh-cn") {
  const target = new URL(window.location.href);
  target.pathname = localizedPath("en")
    ?? (target.pathname.replace(/^\/zh-CN(?=\/|$)/, "") || "/");
  target.search = "";
  window.location.replace(target);
}

function currentTheme() {
  const savedTheme = root.dataset.theme;
  if (savedTheme === "light" || savedTheme === "dark") {
    return savedTheme;
  }
  return colorPreference.matches ? "dark" : "light";
}

function updateThemeLabel() {
  if (!themeButton) return;

  const nextTheme = currentTheme() === "dark" ? "light" : "dark";
  const isChinese = root.lang.toLowerCase() === "zh-cn";
  const labels = isChinese
    ? { light: "浅色", dark: "深色" }
    : { light: "Light", dark: "Dark" };

  const actionLabel = isChinese
    ? `切换到${labels[nextTheme]}模式`
    : `Switch to ${labels[nextTheme].toLowerCase()} mode`;
  themeButton.dataset.nextTheme = nextTheme;
  themeButton.setAttribute("aria-label", actionLabel);
  themeButton.setAttribute("title", actionLabel);
}

const savedTheme = localStorage.getItem("site-theme");
if (savedTheme === "light" || savedTheme === "dark") {
  root.dataset.theme = savedTheme;
}

themeButton?.addEventListener("click", () => {
  const nextTheme = currentTheme() === "dark" ? "light" : "dark";
  root.dataset.theme = nextTheme;
  localStorage.setItem("site-theme", nextTheme);
  updateThemeLabel();
});

colorPreference.addEventListener("change", updateThemeLabel);
updateThemeLabel();
