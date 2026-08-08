// HK Ngạo Thiên — trang trạng thái (tĩnh, chỉ đọc dữ liệu, không gọi VPS).
// Đọc 2 tệp cùng origin (GitHub Pages):
//   data/trang-thai.json  — script trên VPS đẩy lên định kỳ (trạng thái kênh + thời điểm)
//   data/noi-dung.json    — admin sửa tay (link tải + tin tức)
(function () {
  "use strict";

  var STATE_LABEL = {
    open: "Đang mở",
    maintenance: "Bảo trì",
    offline: "Tạm ngưng"
  };

  function bust(url) {
    return url + (url.indexOf("?") === -1 ? "?" : "&") + "_=" + Date.now();
  }

  function getJson(url) {
    return fetch(bust(url), { cache: "no-store" }).then(function (r) {
      if (!r.ok) throw new Error(url + " -> " + r.status);
      return r.json();
    });
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function renderChannels(trangThai) {
    var box = document.getElementById("channels");
    box.innerHTML = "";
    var list = (trangThai && trangThai.kenh) || [];
    if (!list.length) {
      box.appendChild(el("div", "skeleton", "Chưa có dữ liệu trạng thái."));
      return;
    }
    list.forEach(function (ch) {
      var state = STATE_LABEL[ch.trangThai] ? ch.trangThai : "offline";
      var row = el("div", "channel");
      row.appendChild(el("span", "dot " + state));
      row.appendChild(el("span", "name", ch.ten || "Kênh"));
      if (ch.ghiChu) row.appendChild(el("span", "note", ch.ghiChu));
      row.appendChild(el("span", "state " + state, STATE_LABEL[state]));
      box.appendChild(row);
    });
  }

  function renderUpdated(trangThai) {
    var out = document.getElementById("updated");
    if (!trangThai || !trangThai.capNhat) { out.textContent = ""; return; }
    var d = new Date(trangThai.capNhat);
    if (isNaN(d.getTime())) { out.textContent = ""; return; }
    var hh = String(d.getHours()).padStart(2, "0");
    var mm = String(d.getMinutes()).padStart(2, "0");
    var dd = String(d.getDate()).padStart(2, "0");
    var mo = String(d.getMonth() + 1).padStart(2, "0");
    out.textContent = "Cập nhật lúc " + hh + ":" + mm + " ngày " + dd + "/" + mo;
  }

  function setLink(id, url, disabledText) {
    var a = document.getElementById(id);
    if (url) {
      a.href = url;
      a.classList.remove("disabled");
    } else {
      a.href = "#";
      a.classList.add("disabled");
      if (disabledText) {
        var em = a.querySelector("em");
        if (em) em.textContent = disabledText;
      }
    }
  }

  function renderNoiDung(noiDung) {
    noiDung = noiDung || {};
    setLink("btn-launcher", noiDung.linkLauncher, "chưa có link");
    setLink("btn-game", noiDung.linkGame, "chưa có link");

    var ver = document.getElementById("launcher-ver");
    if (noiDung.phienBanLauncher) ver.textContent = "phiên bản " + noiDung.phienBanLauncher;

    var box = document.getElementById("news");
    box.innerHTML = "";
    var tin = noiDung.tinTuc || [];
    if (!tin.length) {
      box.appendChild(el("div", "news-empty", "Chưa có tin tức."));
      return;
    }
    tin.forEach(function (t) {
      var item = el("div", "news-item");
      if (t.ngay) item.appendChild(el("div", "news-date", t.ngay));
      item.appendChild(el("div", "news-title", t.tieuDe || ""));
      if (t.noiDung) item.appendChild(el("div", "news-body", t.noiDung));
      box.appendChild(item);
    });
  }

  function boot() {
    getJson("data/trang-thai.json")
      .then(function (d) { renderChannels(d); renderUpdated(d); })
      .catch(function () {
        document.getElementById("channels").innerHTML =
          '<div class="skeleton">Không tải được trạng thái. Thử lại sau.</div>';
      });

    getJson("data/noi-dung.json")
      .then(renderNoiDung)
      .catch(function () {
        document.getElementById("news").innerHTML =
          '<div class="news-empty">Không tải được tin tức.</div>';
      });
  }

  // Tự làm mới nhẹ mỗi 5 phút để bắt kịp nhịp đẩy của server.
  boot();
  setInterval(boot, 5 * 60 * 1000);
})();
