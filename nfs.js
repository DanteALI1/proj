(() => {
  const docBody = document.getElementById("doc-body");
  const tocList = document.getElementById("toc-list");
  const toc = document.getElementById("toc");
  const tocToggle = document.getElementById("toc-toggle");
  const tocBackdrop = document.getElementById("toc-backdrop");
  const mdUrl = "docs/redos-8-nfs-setup.md";

  function setTocOpen(open) {
    toc.classList.toggle("open", open);
    tocToggle?.setAttribute("aria-expanded", String(open));
    document.body.classList.toggle("toc-open", open);
    if (tocBackdrop) {
      tocBackdrop.hidden = !open;
      tocBackdrop.classList.toggle("show", open);
    }
  }

  function scrollToHeading(id, { updateHash = true } = {}) {
    const target = document.getElementById(id);
    if (!target) return false;

    // На мобиле body.toc-open { overflow:hidden } блокирует scrollIntoView —
    // сначала закрываем оглавление, затем скроллим.
    setTocOpen(false);

    const go = () => {
      const top =
        target.getBoundingClientRect().top +
        window.pageYOffset -
        Math.max(12, parseInt(getComputedStyle(target).scrollMarginTop, 10) || 12);

      window.scrollTo({ top, behavior: "smooth" });

      if (updateHash) {
        const next = `#${id}`;
        if (location.hash !== next) {
          try {
            history.pushState(null, "", next);
          } catch {
            location.hash = id;
          }
        }
      }
    };

    // Два кадра: дождаться снятия overflow:hidden и пересчёта layout
    requestAnimationFrame(() => {
      requestAnimationFrame(go);
    });
    return true;
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

  function wrapTables(root) {
    root.querySelectorAll("table").forEach((table) => {
      if (!table.parentElement?.classList.contains("table-wrap")) {
        const wrap = document.createElement("div");
        wrap.className = "table-wrap";
        table.replaceWith(wrap);
        wrap.appendChild(table);
      }

      const headers = [...table.querySelectorAll("thead th")].map((th) =>
        th.textContent.trim()
      );
      if (!headers.length) return;

      table.querySelectorAll("tbody tr").forEach((tr) => {
        [...tr.children].forEach((cell, i) => {
          if (headers[i]) cell.setAttribute("data-label", headers[i]);
        });
      });
    });
  }

  function buildToc(root) {
    const headings = [...root.querySelectorAll("h2")];
    tocList.innerHTML = "";

    headings.forEach((h, index) => {
      const id = `section-${index + 1}`;
      h.id = id;

      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = `#${id}`;
      a.textContent = h.textContent.replace(/^\d+\.\s*/, "");
      a.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        scrollToHeading(id);
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
      { rootMargin: "-18% 0px -68% 0px", threshold: 0 }
    );
    headings.forEach((h) => observer.observe(h));
  }

  function jumpFromHash() {
    const raw = location.hash.replace(/^#/, "");
    if (!raw) return;
    const id = decodeURIComponent(raw);
    if (document.getElementById(id)) {
      scrollToHeading(id, { updateHash: false });
    }
  }

  function renderMarkdown(md) {
    if (typeof marked === "undefined") {
      docBody.innerHTML = `<pre>${md.replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]))}</pre>`;
      return;
    }

    marked.setOptions({
      gfm: true,
      breaks: false,
      headerIds: false,
      mangle: false,
    });

    docBody.innerHTML = marked.parse(md);
    enhanceCodeBlocks(docBody);
    wrapTables(docBody);
    buildToc(docBody);
    jumpFromHash();
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
    setTocOpen(!toc.classList.contains("open"));
  });

  tocBackdrop?.addEventListener("click", () => setTocOpen(false));

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") setTocOpen(false);
  });

  document.addEventListener("click", (e) => {
    if (!toc.classList.contains("open")) return;
    if (toc.contains(e.target) || tocToggle?.contains(e.target)) return;
    if (tocBackdrop?.contains(e.target)) return;
    setTocOpen(false);
  });

  window.addEventListener("hashchange", jumpFromHash);
  window.addEventListener("popstate", jumpFromHash);

  loadDoc();
})();
