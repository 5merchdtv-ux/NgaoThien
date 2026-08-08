// HK Ngạo Thiên — trang tĩnh (GitHub Pages), điều hướng theo view, chỉ đọc JSON (không gọi VPS).
(function () {
  "use strict";

  var STATE_LABEL = { open: "Đang mở", maintenance: "Bảo trì", offline: "Tạm ngưng" };
  var store = { trangThai: null, noiDung: null, tinTuc: null, bxh: null, feed: null, suKien: null };

  function bust(u) { return u + (u.indexOf("?") === -1 ? "?" : "&") + "_=" + Date.now(); }
  function getJson(u) {
    return fetch(bust(u), { cache: "no-store" }).then(function (r) { if (!r.ok) throw 0; return r.json(); });
  }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function groupNum(s) { var str = String(s == null ? "" : s).replace(/[^0-9]/g, ""); return str ? str.replace(/\B(?=(\d{3})+(?!\d))/g, ".") : String(s); }
  function byId(id) { return document.getElementById(id); }

  /* ---------- ĐIỀU HƯỚNG ---------- */
  function switchView(view) {
    document.querySelectorAll(".nav-link").forEach(function (a) {
      a.classList.toggle("active", a.getAttribute("data-view") === view);
    });
    document.querySelectorAll(".view").forEach(function (p) {
      p.hidden = p.getAttribute("data-view-panel") !== view;
    });
    var hero = byId("hero"); if (hero) hero.style.display = (view === "home") ? "" : "none";
    document.body.classList.remove("nav-open");
    window.scrollTo(0, 0);
  }
  function initNav() {
    document.querySelectorAll("[data-view]").forEach(function (a) {
      a.addEventListener("click", function (e) { e.preventDefault(); switchView(a.getAttribute("data-view")); });
    });
    document.querySelectorAll("[data-goto]").forEach(function (b) {
      b.addEventListener("click", function () { switchView(b.getAttribute("data-goto")); });
    });
    var t = document.querySelector(".nav-toggle");
    if (t) t.addEventListener("click", function () { document.body.classList.toggle("nav-open"); });
  }

  /* ---------- TRẠNG THÁI ---------- */
  function renderChannels() {
    var d = store.trangThai, box = byId("channels"); box.innerHTML = "";
    var list = (d && d.kenh) || [];
    if (!list.length) { box.appendChild(el("div", "skeleton", "Chưa có dữ liệu.")); renderHero([]); return; }
    list.forEach(function (ch) {
      var st = STATE_LABEL[ch.trangThai] ? ch.trangThai : "offline";
      var row = el("div", "channel");
      row.appendChild(el("span", "dot " + st));
      row.appendChild(el("span", "name", ch.ten || "Kênh"));
      row.appendChild(el("span", "state " + st, STATE_LABEL[st]));
      box.appendChild(row);
    });
    renderHero(list);
  }
  function renderHero(list) {
    var h = byId("hero-status"); if (!h) return; h.innerHTML = "";
    list.forEach(function (ch, i) {
      var st = STATE_LABEL[ch.trangThai] ? ch.trangThai : "offline";
      if (i > 0) h.appendChild(el("span", "sep", "•"));
      h.appendChild(el("span", "hs-dot " + st));
      var t = el("span", null); t.appendChild(el("b", null, (ch.ten || "Kênh") + ": "));
      t.appendChild(document.createTextNode(STATE_LABEL[st])); h.appendChild(t);
    });
  }
  function renderUpdated() {
    var d = store.trangThai, o = byId("updated"); if (!o) return;
    if (!d || !d.capNhat) { o.textContent = ""; return; }
    var dt = new Date(d.capNhat); if (isNaN(dt.getTime())) { o.textContent = ""; return; }
    function p(n) { return String(n).padStart(2, "0"); }
    o.textContent = "Cập nhật " + p(dt.getHours()) + ":" + p(dt.getMinutes()) + " · kiểm tra mỗi 5 phút";
  }

  /* ---------- LINK TẢI ---------- */
  function renderLinks() {
    var url = store.noiDung && store.noiDung.linkGame;
    document.querySelectorAll(".js-game").forEach(function (a) {
      if (url) { a.href = url; a.classList.remove("disabled"); } else { a.href = "#"; a.classList.add("disabled"); }
    });
  }

  /* ---------- TIN TỨC ---------- */
  function buildCard(t) {
    var card = el("div", "news-card"); card.setAttribute("role", "button"); card.setAttribute("tabindex", "0");
    if (t.anh) { var img = el("img", "thumb"); img.src = t.anh; img.alt = t.tieuDe || ""; img.loading = "lazy"; img.onerror = function () { img.style.display = "none"; }; card.appendChild(img); }
    var cb = el("div", "card-body");
    var head = el("div", "card-head");
    if (t.badge) head.appendChild(el("span", "badge", t.badge));
    if (t.ngay) head.appendChild(el("span", "news-date", t.ngay));
    cb.appendChild(head);
    if (t.tieuDe) cb.appendChild(el("div", "card-title", t.tieuDe));
    if (t.noiDung) cb.appendChild(el("div", "card-excerpt", t.noiDung.replace(/\s+/g, " ").trim()));
    cb.appendChild(el("div", "card-more", "Xem chi tiết →"));
    card.appendChild(cb);
    card.onclick = function () { openModal(t); };
    card.onkeydown = function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openModal(t); } };
    return card;
  }
  function renderNewsInto(id, limit) {
    var box = byId(id); if (!box) return; box.innerHTML = "";
    var tin = (store.tinTuc && store.tinTuc.tinTuc) || [];
    if (!tin.length) { box.appendChild(el("div", "news-empty", "Chưa có tin tức.")); return; }
    (limit ? tin.slice(0, limit) : tin).forEach(function (t) { box.appendChild(buildCard(t)); });
  }
  function openModal(t) {
    var bd = byId("news-modal"), inner = bd.querySelector(".modal-inner"); inner.innerHTML = "";
    if (t.anh) { var im = el("img", "modal-img"); im.src = t.anh; im.alt = t.tieuDe || ""; im.onerror = function () { im.remove(); }; inner.appendChild(im); }
    var c = el("div", "modal-content");
    var head = el("div", "modal-head");
    if (t.badge) head.appendChild(el("span", "badge", t.badge));
    if (t.ngay) head.appendChild(el("span", "news-date", t.ngay));
    c.appendChild(head);
    if (t.tieuDe) c.appendChild(el("div", "modal-title", t.tieuDe));
    if (t.noiDung) { var b = el("div", "modal-body"); b.textContent = t.noiDung; c.appendChild(b); }
    if (t.tacGia) c.appendChild(el("div", "modal-author", "— " + t.tacGia));
    inner.appendChild(c);
    bd.querySelector(".modal").scrollTop = 0;
    bd.classList.add("open"); bd.setAttribute("aria-hidden", "false"); document.body.classList.add("modal-open");
  }
  function closeModal() { var bd = byId("news-modal"); bd.classList.remove("open"); bd.setAttribute("aria-hidden", "true"); document.body.classList.remove("modal-open"); }
  function initModal() {
    var bd = byId("news-modal"); if (!bd) return;
    bd.querySelector(".modal-close").onclick = closeModal;
    bd.addEventListener("click", function (e) { if (e.target === bd) closeModal(); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeModal(); });
  }

  /* ---------- BXH ---------- */
  var BXH_COL = {
    level: { key: "cap", label: "Cấp", fmt: function (v) { return v; } },
    wx: { key: "thanhTuu", label: "Võ huân", fmt: groupNum },
    pvp: { key: "thanhTuu", label: "Điểm PK", fmt: groupNum }
  };
  function factionTag(phai) { var cls = phai === "Chính" ? "chinh" : (phai === "Tà" ? "ta" : "tl"); return el("span", "tag-phai " + cls, phai || "—"); }
  function renderBxh(tab) {
    var body = byId("bxh-body"); if (!body) return;
    if (!store.bxh) { body.innerHTML = '<div class="skeleton">Đang tải…</div>'; return; }
    var rows = store.bxh[tab] || [], col = BXH_COL[tab] || BXH_COL.level;
    body.innerHTML = "";
    if (!rows.length) { body.appendChild(el("div", "news-empty", "Chưa có dữ liệu.")); return; }
    var table = el("table", "grid"), thead = el("thead"), htr = el("tr");
    ["#", "Nhân vật", "Nghề", "Phái", col.label].forEach(function (h, i) { htr.appendChild(el("th", (i === 0 ? "center" : (i === 4 ? "num" : "")), h)); });
    thead.appendChild(htr); table.appendChild(thead);
    var tb = el("tbody");
    rows.forEach(function (r) {
      var tr = el("tr");
      var c0 = el("td", "center"); c0.appendChild(el("span", "rankcell " + (r.rank <= 3 ? "top" + r.rank : "norm"), r.rank)); tr.appendChild(c0);
      var c1 = el("td"); var nm = el("span", "chname", r.ten || ""); if (r.online) nm.appendChild(el("span", "on")); c1.appendChild(nm); tr.appendChild(c1);
      tr.appendChild(el("td", null, r.nghe || ""));
      var c3 = el("td"); c3.appendChild(factionTag(r.phai)); tr.appendChild(c3);
      tr.appendChild(el("td", "num", col.fmt(r[col.key])));
      tb.appendChild(tr);
    });
    table.appendChild(tb); body.appendChild(table);
  }
  function renderLvMax() {
    var o = byId("lvmax"); if (!o) return;
    var lv = store.bxh && store.bxh.level && store.bxh.level[0] && store.bxh.level[0].cap;
    o.textContent = lv ? lv : "—";
  }
  function renderTopCaoThu() {
    var box = byId("top-cao-thu"); if (!box) return;
    if (!store.bxh) return;
    var rows = (store.bxh.level || []).slice(0, 3); box.innerHTML = "";
    if (!rows.length) { box.appendChild(el("div", "news-empty", "—")); return; }
    var medal = ["🥇", "🥈", "🥉"];
    rows.forEach(function (r, i) {
      var it = el("div", "top-item");
      it.appendChild(el("span", "top-medal", medal[i] || ""));
      var info = el("div", "top-info");
      info.appendChild(el("div", "top-name", r.ten || ""));
      info.appendChild(el("div", "top-sub", (r.nghe || "") + " · LV " + (r.cap || "")));
      it.appendChild(info);
      box.appendChild(it);
    });
  }

  /* ---------- CƯỜNG HÓA (feed) ---------- */
  function hashHue(s) { var h = 0, i; s = s || ""; for (i = 0; i < s.length; i++) { h = (h * 31 + s.charCodeAt(i)) >>> 0; } return h % 360; }
  function nameColor(s) { return "hsl(" + hashHue(s) + ", 72%, 72%)"; }
  function buildFeedTable(rows) {
    var table = el("table", "grid ch-feed"), thead = el("thead"), htr = el("tr");
    var heads = ["Thời gian", "Kênh", "Nhân vật", "Thao tác", "Trang bị", "Cấp", "Ngọc / Bùa", "Thay đổi", "Kết quả"];
    var centers = { 1: 1, 5: 1, 8: 1 };
    heads.forEach(function (h, i) { htr.appendChild(el("th", (centers[i] ? "center" : ""), h)); });
    thead.appendChild(htr); table.appendChild(thead);
    var tb = el("tbody");
    rows.forEach(function (r) {
      var tr = el("tr");
      var col = nameColor(r.nhanVat);
      var c0 = el("td", null, r.thoiGian || ""); c0.style.boxShadow = "inset 3px 0 0 " + col; tr.appendChild(c0);
      tr.appendChild(el("td", "center", "K" + r.kenh));
      var c2 = el("td"); var nm = el("span", "chname", r.nhanVat || ""); nm.style.color = col; c2.appendChild(nm); tr.appendChild(c2);
      tr.appendChild(el("td", "op " + (r.loai === "hop-thanh" ? "op-ht" : "op-ch"), r.loai === "hop-thanh" ? "◆ Hợp thành" : "✦ Cường hóa"));
      tr.appendChild(el("td", null, r.trangBi || ""));
      tr.appendChild(el("td", "center", r.capDo || "—"));
      tr.appendChild(el("td", null, r.nguyenLieu || "—"));
      tr.appendChild(el("td", null, r.thayDoi || ""));
      tr.appendChild(el("td", "center " + (r.thanhCong ? "kq-ok" : "kq-fail"), r.thanhCong ? "THÀNH CÔNG" : "THẤT BẠI"));
      tb.appendChild(tr);
    });
    table.appendChild(tb); return table;
  }
  function renderDapDo(filter) {
    var body = byId("ch-body"); if (!body) return;
    if (!store.feed) { body.innerHTML = '<div class="skeleton">Đang tải…</div>'; return; }
    var list = (store.feed.danhSach) || [];
    var rows = list.filter(function (r) {
      if (filter === "cuong-hoa") return r.loai === "cuong-hoa";
      if (filter === "hop-thanh") return r.loai === "hop-thanh";
      if (filter === "thanh-cong") return r.thanhCong;
      if (filter === "that-bai") return !r.thanhCong;
      return true;
    });
    body.innerHTML = "";
    if (!rows.length) { body.appendChild(el("div", "news-empty", "Chưa có hoạt động.")); }
    else body.appendChild(buildFeedTable(rows));
    var n = byId("ch-note"); if (n) n.textContent = "Hoạt động cường hóa & hợp thành mới nhất của người chơi — tự động cập nhật.";
  }
  function renderHomeFeed() {
    var body = byId("home-feed"); if (!body) return;
    if (!store.feed) return;
    var rows = (store.feed.danhSach || []).slice(0, 8); body.innerHTML = "";
    if (!rows.length) { body.appendChild(el("div", "news-empty", "Chưa có hoạt động.")); return; }
    body.appendChild(buildFeedTable(rows));
  }

  /* ---------- SỰ KIỆN ---------- */
  function renderSuKien() {
    var box = byId("su-kien"); if (!box) return;
    var list = (store.suKien && store.suKien.danhSach) || []; box.innerHTML = "";
    if (!list.length) { box.appendChild(el("div", "news-empty", "Chưa có sự kiện.")); return; }
    list.forEach(function (s) {
      var it = el("div", "event-item");
      if (s.tieuDe) it.appendChild(el("div", "event-title", s.tieuDe));
      if (s.thoiGian) { var tg = el("div", "event-time"); tg.appendChild(el("span", "ev-ico", "⏰")); tg.appendChild(document.createTextNode(" " + s.thoiGian)); it.appendChild(tg); }
      if (s.moc && s.moc.length) { var ul = el("ul", "event-moc"); s.moc.forEach(function (m) { ul.appendChild(el("li", null, m)); }); it.appendChild(ul); }
      box.appendChild(it);
    });
  }

  /* ---------- TABS ---------- */
  function initTabs() {
    document.querySelectorAll(".tabs").forEach(function (group) {
      group.addEventListener("click", function (e) {
        var btn = e.target.closest(".tab"); if (!btn) return;
        group.querySelectorAll(".tab").forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        var tab = btn.getAttribute("data-tab"), which = group.getAttribute("data-tabs");
        if (which === "bxh") renderBxh(tab); else if (which === "dd") renderDapDo(tab);
      });
    });
  }

  /* ---------- BOOT ---------- */
  function boot() {
    getJson("data/trang-thai.json").then(function (d) { store.trangThai = d; renderChannels(); renderUpdated(); })
      .catch(function () { byId("channels").innerHTML = '<div class="skeleton">Không tải được.</div>'; });
    getJson("data/noi-dung.json").then(function (d) { store.noiDung = d; renderLinks(); }).catch(function () {});
    getJson("data/tin-tuc.json").then(function (d) { store.tinTuc = d; renderNewsInto("news"); renderNewsInto("home-news", 3); })
      .catch(function () { byId("news").innerHTML = '<div class="news-empty">Không tải được tin tức.</div>'; });
    getJson("data/bxh.json").then(function (d) { store.bxh = d; renderBxh("level"); renderLvMax(); renderTopCaoThu(); })
      .catch(function () { byId("bxh-body").innerHTML = '<div class="news-empty">Không tải được xếp hạng.</div>'; });
    getJson("data/cuong-hoa.json").then(function (d) { store.feed = d; renderDapDo("all"); renderHomeFeed(); })
      .catch(function () { byId("ch-body").innerHTML = '<div class="news-empty">Không tải được.</div>'; });
    getJson("data/su-kien.json").then(function (d) { store.suKien = d; renderSuKien(); }).catch(function () {});
  }

  initNav(); initTabs(); initModal();
  switchView("home");
  boot();
  setInterval(boot, 5 * 60 * 1000);
})();
