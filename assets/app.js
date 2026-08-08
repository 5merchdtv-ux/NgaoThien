// HK Ngạo Thiên — trang tĩnh, chỉ đọc JSON trên GitHub Pages (không gọi VPS).
//   data/trang-thai.json  — trạng thái kênh (VPS đẩy)
//   data/noi-dung.json    — link tải game
//   data/tin-tuc.json     — tin tức lấy từ nguồn Launcher (VPS đẩy)
//   data/bxh.json         — bảng xếp hạng (VPS đẩy)
//   data/cuong-hoa.json   — bảng tỉ lệ cường hóa (tĩnh)
(function () {
  "use strict";

  var STATE_LABEL = { open: "Đang mở", maintenance: "Bảo trì", offline: "Tạm ngưng" };

  function bust(u) { return u + (u.indexOf("?") === -1 ? "?" : "&") + "_=" + Date.now(); }
  function getJson(u) {
    return fetch(bust(u), { cache: "no-store" }).then(function (r) {
      if (!r.ok) throw new Error(u + " -> " + r.status); return r.json();
    });
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function groupNum(s) {
    if (s == null) return "";
    var str = String(s).replace(/[^0-9]/g, "");
    if (!str) return String(s);
    return str.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  }

  /* ---------- TRẠNG THÁI ---------- */
  function renderChannels(d) {
    var box = document.getElementById("channels"); box.innerHTML = "";
    var list = (d && d.kenh) || [];
    if (!list.length) { box.appendChild(el("div", "skeleton", "Chưa có dữ liệu.")); renderHero([]); return; }
    list.forEach(function (ch) {
      var st = STATE_LABEL[ch.trangThai] ? ch.trangThai : "offline";
      var row = el("div", "channel");
      row.appendChild(el("span", "dot " + st));
      row.appendChild(el("span", "name", ch.ten || "Kênh"));
      if (ch.ghiChu) row.appendChild(el("span", "note", ch.ghiChu));
      row.appendChild(el("span", "state " + st, STATE_LABEL[st]));
      box.appendChild(row);
    });
    renderHero(list);
  }
  function renderHero(list) {
    var h = document.getElementById("hero-status"); if (!h) return; h.innerHTML = "";
    list.forEach(function (ch, i) {
      var st = STATE_LABEL[ch.trangThai] ? ch.trangThai : "offline";
      if (i > 0) h.appendChild(el("span", "sep", "•"));
      h.appendChild(el("span", "hs-dot " + st));
      var t = el("span", null);
      t.appendChild(el("b", null, (ch.ten || "Kênh") + ": "));
      t.appendChild(document.createTextNode(STATE_LABEL[st]));
      h.appendChild(t);
    });
  }
  function renderUpdated(d) {
    var o = document.getElementById("updated");
    if (!d || !d.capNhat) { o.textContent = ""; return; }
    var dt = new Date(d.capNhat);
    if (isNaN(dt.getTime())) { o.textContent = ""; return; }
    function p(n) { return String(n).padStart(2, "0"); }
    o.textContent = "Cập nhật lúc " + p(dt.getHours()) + ":" + p(dt.getMinutes()) +
      " ngày " + p(dt.getDate()) + "/" + p(dt.getMonth() + 1) + " · tự động kiểm tra mỗi 5 phút";
  }

  /* ---------- LINK TẢI ---------- */
  function renderLink(noiDung) {
    var a = document.getElementById("btn-game");
    var url = noiDung && noiDung.linkGame;
    if (url) { a.href = url; a.classList.remove("disabled"); }
    else { a.href = "#"; a.classList.add("disabled"); }
  }

  /* ---------- TIN TỨC ---------- */
  function renderNews(d) {
    var box = document.getElementById("news"); box.innerHTML = "";
    var tin = (d && d.tinTuc) || [];
    if (!tin.length) { box.appendChild(el("div", "news-empty", "Chưa có tin tức.")); return; }
    tin.forEach(function (t) {
      var item = el("div", "news-item");
      var head = el("div", "news-head");
      if (t.badge) head.appendChild(el("span", "badge", t.badge));
      if (t.ngay) head.appendChild(el("span", "news-date", t.ngay));
      item.appendChild(head);
      if (t.tieuDe) item.appendChild(el("div", "news-title", t.tieuDe));
      if (t.anh) {
        var img = el("img", "news-img"); img.src = t.anh; img.alt = t.tieuDe || "";
        img.loading = "lazy"; img.onerror = function () { img.remove(); };
        item.appendChild(img);
      }
      if (t.noiDung) {
        var body = el("div", "news-body");
        body.textContent = t.noiDung;
        var long = t.noiDung.length > 360;
        if (long) body.classList.add("clamped");
        item.appendChild(body);
        if (long) {
          var btn = el("button", "news-more", "Xem thêm ▾");
          btn.onclick = function () {
            var open = body.classList.toggle("clamped") === false;
            btn.textContent = open ? "Thu gọn ▴" : "Xem thêm ▾";
          };
          item.appendChild(btn);
        }
      }
      if (t.tacGia) item.appendChild(el("div", "news-author", "— " + t.tacGia));
      box.appendChild(item);
    });
  }

  /* ---------- BẢNG XẾP HẠNG ---------- */
  var bxhData = null;
  var BXH_COL = {
    level: { key: "cap", label: "Cấp", fmt: function (v) { return v; } },
    wx: { key: "thanhTuu", label: "Võ huân", fmt: groupNum },
    pvp: { key: "thanhTuu", label: "Điểm PK", fmt: groupNum }
  };
  function factionTag(phai) {
    var cls = phai === "Chính" ? "chinh" : (phai === "Tà" ? "ta" : "tl");
    var s = el("span", "tag-phai " + cls, phai || "—"); return s;
  }
  function renderBxh(tab) {
    var body = document.getElementById("bxh-body");
    if (!bxhData) { body.innerHTML = '<div class="skeleton">Đang tải…</div>'; return; }
    var rows = bxhData[tab] || [];
    body.innerHTML = "";
    if (!rows.length) { body.appendChild(el("div", "news-empty", "Chưa có dữ liệu xếp hạng.")); return; }
    var col = BXH_COL[tab] || BXH_COL.level;
    var table = el("table", "grid");
    var thead = el("thead"), htr = el("tr");
    ["#", "Nhân vật", "Nghề", "Phái", col.label, "Bang hội"].forEach(function (h, i) {
      var th = el("th", (i === 0 ? "center" : (i === 4 ? "num" : "")), h); htr.appendChild(th);
    });
    thead.appendChild(htr); table.appendChild(thead);
    var tb = el("tbody");
    rows.forEach(function (r) {
      var tr = el("tr");
      var c0 = el("td", "center");
      var badge = el("span", "rankcell " + (r.rank <= 3 ? "top" + r.rank : "norm"), r.rank);
      c0.appendChild(badge); tr.appendChild(c0);
      var c1 = el("td");
      var nm = el("span", "chname", r.ten || "");
      if (r.online) nm.appendChild(el("span", "on"));
      c1.appendChild(nm); tr.appendChild(c1);
      tr.appendChild(el("td", null, r.nghe || ""));
      var c3 = el("td"); c3.appendChild(factionTag(r.phai)); tr.appendChild(c3);
      tr.appendChild(el("td", "num", col.fmt(r[col.key])));
      tr.appendChild(el("td", null, r.bang || "—"));
      tb.appendChild(tr);
    });
    table.appendChild(tb);
    body.appendChild(table);
  }

  /* ---------- CƯỜNG HÓA ---------- */
  var chData = null;
  var CH_TITLE = { vuKhi: "Vũ khí", trangSuc: "Trang sức", aoChoang: "Áo choàng" };
  function renderCh(tab) {
    var body = document.getElementById("ch-body");
    if (!chData) { body.innerHTML = '<div class="skeleton">Đang tải…</div>'; return; }
    var rows = chData[tab] || [];
    body.innerHTML = "";
    var table = el("table", "grid");
    var thead = el("thead"), htr = el("tr");
    ["Cấp", "Tỉ lệ cơ bản", "Tối đa (đủ hỗ trợ)"].forEach(function (h, i) {
      htr.appendChild(el("th", (i === 0 ? "center" : "num"), h));
    });
    thead.appendChild(htr); table.appendChild(thead);
    var tb = el("tbody");
    rows.forEach(function (r) {
      var tr = el("tr");
      tr.appendChild(el("td", "center", "+" + r.cap));
      tr.appendChild(el("td", "num", r.coBan + "%"));
      tr.appendChild(el("td", "num", r.toiDa + "%"));
      tb.appendChild(tr);
    });
    table.appendChild(tb); body.appendChild(table);
    var note = document.getElementById("ch-note");
    if (note) note.textContent = chData.ghiChu || "";
  }

  /* ---------- TABS ---------- */
  function initTabs() {
    document.querySelectorAll(".tabs").forEach(function (group) {
      group.addEventListener("click", function (e) {
        var btn = e.target.closest(".tab"); if (!btn) return;
        group.querySelectorAll(".tab").forEach(function (b) { b.classList.remove("active"); });
        btn.classList.add("active");
        var tab = btn.getAttribute("data-tab");
        if (group.getAttribute("data-tabs") === "bxh") renderBxh(tab);
        else renderCh(tab);
      });
    });
  }

  /* ---------- BOOT ---------- */
  function boot() {
    getJson("data/trang-thai.json").then(function (d) { renderChannels(d); renderUpdated(d); })
      .catch(function () { document.getElementById("channels").innerHTML = '<div class="skeleton">Không tải được trạng thái.</div>'; });
    getJson("data/noi-dung.json").then(renderLink).catch(function () {});
    getJson("data/tin-tuc.json").then(renderNews)
      .catch(function () { document.getElementById("news").innerHTML = '<div class="news-empty">Không tải được tin tức.</div>'; });
    getJson("data/bxh.json").then(function (d) { bxhData = d; renderBxh("level"); })
      .catch(function () { document.getElementById("bxh-body").innerHTML = '<div class="news-empty">Không tải được xếp hạng.</div>'; });
    getJson("data/cuong-hoa.json").then(function (d) { chData = d; renderCh("vuKhi"); })
      .catch(function () { document.getElementById("ch-body").innerHTML = '<div class="news-empty">Không tải được bảng cường hóa.</div>'; });
  }

  initTabs();
  boot();
  setInterval(boot, 5 * 60 * 1000);
})();
