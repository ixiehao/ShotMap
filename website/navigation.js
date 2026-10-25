// Language links work without JavaScript. Keep the URL authoritative: visiting
// the English root must not silently replace it with a previously chosen locale.
const picker = document.querySelector(".language-picker");
const languageLinks = [...document.querySelectorAll("a[data-lang]")];
const requested = new URLSearchParams(window.location.search).get("lang");
const requestedLink = languageLinks.find(link => link.dataset.lang === requested);
if (requestedLink && requested !== document.documentElement.dataset.defaultLanguage) {
  window.location.replace(requestedLink.href + window.location.hash);
}

document.addEventListener("click", event => {
  if (picker && !picker.contains(event.target)) picker.open = false;
});
document.addEventListener("keydown", event => {
  if (event.key === "Escape" && picker?.open) {
    picker.open = false;
    picker.querySelector("summary").focus();
  }
});
