(() => {
  const docBody = document.getElementById("doc-body");
  const tocList = document.getElementById("toc-list");
  const toc = document.getElementById("toc");
  const tocToggle = document.getElementById("toc-toggle");
  const mdUrl = "docs/redos-8-nfs-setup.md";

  function slugify(text) {
    return text
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s-]/gu, "")
      .trim()
      .replace(/\s+/g, "-")
      .slice(0, 80);
  }

  function enhanceCodeBlocks(root) {
    root.querySelectorAll("pre > code").forEach((code) => {
      const pre = code.parentElement;
      const wrap = document.createElement("div");
      wrap.className = "pre-wrap";
      pre.replaceWith(wrap);
      wrap.appendChild(pre);

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "copy-btn";
      btn.textContent = "Копировать";
      btn.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(code.textContent);
          btn.textContent = "Скопировано";
          btn.classList.add("copied");
          setTimeout(() => {
            btn.textContent = "Копировать";
            btn.classList.remove("copied");
          }, 1600);
        } catch {
          btn.textContent = "Ошибка";
        }
      });
      wrap.appendChild(btn);
    });
  }

  function buildToc(root) {
    const headings = [...root.querySelectorAll("h2")];
    tocList.innerHTML = "";
    const used = new Set();

    headings.forEach((h) => {
      let id = h.id || slugify(h.textContent);
      let n = 1;
      while (used.has(id)) {
        id = `${slugify(h.textContent)}-${n++}`;
      }
      used.add(id);
      h.id = id;

      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = `#${id}`;
      a.textContent = h.textContent.replace(/^\d+\.\s*/, "");
      a.addEventListener("click", () => {
        toc.classList.remove("open");
        tocToggle?.setAttribute("aria-expanded", "false");
      });
      li.appendChild(a);
      tocList.appendChild(li);
    });

    const links = [...tocList.querySelectorAll("a")];
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const id = entry.target.id;
          links.forEach((link) => {
            link.classList.toggle("active", link.getAttribute("href") === `#${id}`);
          });
        });
      },
      { rootMargin: "-20% 0px -65% 0px", threshold: 0 }
    );
    headings.forEach((h) => observer.observe(h));
  }

  function renderMarkdown(md) {
    if (typeof marked === "undefined") {
      docBody.innerHTML = `<pre>${md.replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]))}</pre>`;
      return;
    }

    marked.setOptions({
      gfm: true,
      breaks: false,
      headerIds: true,
      mangle: false,
    });

    docBody.innerHTML = marked.parse(md);
    enhanceCodeBlocks(docBody);
    buildToc(docBody);
  }

  async function loadDoc() {
    const embedded = document.getElementById("doc-source");
    if (embedded?.textContent?.trim()) {
      renderMarkdown(embedded.textContent);
      return;
    }

    try {
      const res = await fetch(mdUrl, { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      renderMarkdown(await res.text());
    } catch (err) {
      docBody.innerHTML = `
        <blockquote>
          <p>Не удалось загрузить инструкцию (${String(err.message || err)}).</p>
          <p>Откройте <a href="${mdUrl}">docs/redos-8-nfs-setup.md</a>.</p>
        </blockquote>
      `;
    }
  }

  tocToggle?.addEventListener("click", () => {
    const open = toc.classList.toggle("open");
    tocToggle.setAttribute("aria-expanded", String(open));
  });

  document.addEventListener("click", (e) => {
    if (!toc.classList.contains("open")) return;
    if (toc.contains(e.target) || tocToggle.contains(e.target)) return;
    toc.classList.remove("open");
    tocToggle.setAttribute("aria-expanded", "false");
  });

  loadDoc();
})();
