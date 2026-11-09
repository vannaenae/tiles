// Shows the latest release in every [data-version] element. The text in the page is the fallback.
fetch("https://api.github.com/repos/vannaenae/tiles/releases/latest")
  .then(r => (r.ok ? r.json() : null))
  .then(r => { if (r && r.tag_name) document.querySelectorAll("[data-version]").forEach(el => { el.textContent = r.tag_name; }); })
  .catch(() => {});
