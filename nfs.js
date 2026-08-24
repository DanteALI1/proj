(() => {
  const docBody = document.getElementById("doc-body");
  const tocList = document.getElementById("toc-list");
  const toc = document.getElementById("toc");
  const tocToggle = document.getElementById("toc-toggle");
  const tocBackdrop = document.getElementById("toc-backdrop");
  const mdUrl =
    document.body?.dataset?.mdUrl || "docs/redos-8-nfs-setup.md";
  let scrollLockY = 0;

  function setTocOpen(open) {
    if (open) {
      scrollLockY = window.scrollY || window.pageYOffset || 0;
      toc.classList.add("open");
      document.body.classList.add("toc-open");
      document.body.style.top = `-${scrollLockY}px`;
      tocToggle?.setAttribute("aria-expanded", "true");
      if (tocBackdrop) {
        tocBackdrop.hidden = false;
        tocBackdrop.classList.add("show");
      }
      return;
    }

    toc.classList.remove("open");
    document.body.classList.remove("toc-open");
    document.body.style.top = "";
    tocToggle?.setAttribute("aria-expanded", "false");
    if (tocBackdrop) {
      tocBackdrop.classList.remove("show");
      tocBackdrop.hidden = true;
    }
    window.scrollTo(0, scrollLockY);
  }

  function scrollToHeading(id, { updateHash = true } = {}) {
    const target = document.getElementById(id);
    if (!target) return false;

    const wasOpen = toc.classList.contains("open");
    if (wasOpen) {
      toc.classList.remove("open");
      document.body.classList.remove("toc-open");
      document.body.style.top = "";
      tocToggle?.setAttribute("aria-expanded", "false");
      if (tocBackdrop) {
        tocBackdrop.classList.remove("show");
        tocBackdrop.hidden = true;
      }
      window.scrollTo(0, scrollLockY);
    }

    const navigate = () => {
      const prefersReduced =
        window.matchMedia &&
        window.matchMedia("(prefers-reduced-motion: reduce)").matches;

      const offset = 12;
      const top =
        target.getBoundingClientRect().top + window.pageYOffset - offset;
      window.scrollTo({
        top: Math.max(0, top),
        behavior: prefersReduced ? "auto" : "smooth",
      });

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

      tocList.querySelectorAll(".toc-link").forEach((el) => {
        el.classList.toggle("active", el.dataset.target === id);
      });
    };

    window.setTimeout(navigate, wasOpen ? 100 : 0);
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
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "toc-link";
      btn.dataset.target = id;
      btn.textContent = h.textContent.replace(/^\d+\.\s*/, "");

      // Прямой обработчик на каждой кнопке — без closest() по Text-node
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        scrollToHeading(id);
      });

      li.appendChild(btn);
      tocList.appendChild(li);
    });

    const links = [...tocList.querySelectorAll(".toc-link")];
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          const id = entry.target.id;
          links.forEach((link) => {
            link.classList.toggle("active", link.dataset.target === id);
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

  tocToggle?.addEventListener("click", (e) => {
    e.stopPropagation();
    setTocOpen(!toc.classList.contains("open"));
  });

  tocBackdrop?.addEventListener("click", () => setTocOpen(false));

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") setTocOpen(false);
  });

  document.addEventListener("click", (e) => {
    if (!toc.classList.contains("open")) return;
    const node = e.target instanceof Element ? e.target : e.target?.parentElement;
    if (node && (toc.contains(node) || tocToggle?.contains(node))) return;
    if (tocBackdrop?.contains(node)) return;
    setTocOpen(false);
  });

  window.addEventListener("hashchange", jumpFromHash);
  window.addEventListener("popstate", jumpFromHash);

  loadDoc();
})();
