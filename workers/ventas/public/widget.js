/**
 * Widget flotante del agente de ventas IA de SI SOL INMOBILIARIAS.
 *
 * Uso en cualquier página:
 *   <script src="https://sisol-agente-ventas.si-sol.workers.dev/widget.js" defer></script>
 *
 * - Globo flotante estilo WhatsApp (abajo a la derecha)
 * - Notificación de bienvenida al cargar la página
 * - Click en el globo -> abre/cierra la ventana del chat
 * - Abre la página del desarrollo cuando el agente detecta interés
 */
(function () {
  if (window.__sisolWidget) return; // evitar doble carga
  window.__sisolWidget = true;

  var ORIGIN;
  try {
    ORIGIN = new URL(document.currentScript.src).origin;
  } catch (e) {
    ORIGIN = "https://sisol-agente-ventas.si-sol.workers.dev";
  }

  var WHATSAPP_SVG =
    '<svg viewBox="0 0 32 32" width="34" height="34" fill="#fff" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M16.04 4C9.55 4 4.27 9.27 4.27 15.76c0 2.07.54 4.1 1.58 5.89L4.2 27.8l6.32-1.62c1.72.94 3.66 1.43 5.63 1.43h.01c6.48 0 11.76-5.27 11.76-11.76C27.91 9.27 22.53 4 16.04 4zm0 21.54h-.01c-1.76 0-3.48-.47-4.98-1.36l-.36-.21-3.75.96 1-3.65-.23-.37a9.7 9.7 0 0 1-1.49-5.15c0-5.38 4.38-9.76 9.77-9.76 2.61 0 5.06 1.02 6.9 2.86a9.71 9.71 0 0 1 2.86 6.91c0 5.39-4.38 9.77-9.71 9.77zm5.35-7.31c-.29-.15-1.73-.86-2-.96-.27-.1-.46-.15-.66.15-.19.29-.75.95-.92 1.15-.17.19-.34.22-.63.07-.29-.15-1.24-.45-2.35-1.45-.87-.78-1.46-1.74-1.63-2.03-.17-.29-.02-.45.13-.6.13-.13.29-.34.44-.51.15-.17.19-.29.29-.49.1-.19.05-.37-.02-.51-.07-.15-.66-1.58-.9-2.17-.24-.57-.48-.49-.66-.5h-.56c-.19 0-.51.07-.78.37-.27.29-1.02.99-1.02 2.43 0 1.43 1.05 2.82 1.19 3.01.15.19 2.06 3.14 4.98 4.41.7.3 1.24.48 1.66.61.7.22 1.33.19 1.84.12.56-.08 1.73-.71 1.97-1.39.24-.68.24-1.27.17-1.39-.07-.12-.27-.19-.56-.34z"/></svg>';

  var CLOSE_SVG =
    '<svg viewBox="0 0 24 24" width="26" height="26" fill="#fff" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>';

  // ---------- estilos ----------
  var css =
    "#sisol-burbuja{position:fixed;bottom:24px;right:24px;width:62px;height:62px;border-radius:50%;" +
    "background:#25D366;border:none;cursor:pointer;z-index:2147483000;display:flex;align-items:center;" +
    "justify-content:center;box-shadow:0 6px 24px rgba(0,0,0,.3);transition:transform .2s;}" +
    "#sisol-burbuja:hover{transform:scale(1.08);}" +
    "#sisol-burbuja .pulso{position:absolute;inset:0;border-radius:50%;background:#25D366;opacity:.5;" +
    "animation:sisol-pulso 2s ease-out infinite;z-index:-1;}" +
    "@keyframes sisol-pulso{0%{transform:scale(1);opacity:.5}100%{transform:scale(1.7);opacity:0}}" +
    "#sisol-notif{position:fixed;bottom:100px;right:24px;max-width:270px;background:#fff;color:#1a2659;" +
    "border-radius:14px;border-bottom-right-radius:4px;padding:13px 34px 13px 16px;font:14px/1.4 'Segoe UI',system-ui,sans-serif;" +
    "box-shadow:0 8px 28px rgba(0,0,0,.25);z-index:2147483000;cursor:pointer;opacity:0;transform:translateY(8px);" +
    "transition:opacity .35s,transform .35s;}" +
    "#sisol-notif.visible{opacity:1;transform:translateY(0);}" +
    "#sisol-notif b{color:#f28c1b;}" +
    "#sisol-notif .cerrar{position:absolute;top:6px;right:9px;color:#9aa0b5;font-size:16px;line-height:1;}" +
    "#sisol-panel{position:fixed;bottom:100px;right:24px;width:390px;height:min(620px,calc(100vh - 130px));" +
    "border:none;border-radius:18px;box-shadow:0 12px 40px rgba(0,0,0,.35);z-index:2147483000;background:#f5f6fa;" +
    "opacity:0;transform:translateY(12px) scale(.98);pointer-events:none;transition:opacity .25s,transform .25s;}" +
    "#sisol-panel.abierto{opacity:1;transform:translateY(0) scale(1);pointer-events:auto;}" +
    "@media (max-width:480px){#sisol-panel{right:0;bottom:0;width:100vw;height:100dvh;border-radius:0;}}";

  var style = document.createElement("style");
  style.textContent = css;
  document.head.appendChild(style);

  // ---------- globo ----------
  var burbuja = document.createElement("button");
  burbuja.id = "sisol-burbuja";
  burbuja.setAttribute("aria-label", "Chat de ventas SI SOL");
  burbuja.innerHTML = '<span class="pulso"></span>' + WHATSAPP_SVG;
  document.body.appendChild(burbuja);

  // ---------- panel (iframe perezoso) ----------
  var panel = null;
  var abierto = false;

  function asegurarPanel() {
    if (panel) return;
    panel = document.createElement("iframe");
    panel.id = "sisol-panel";
    panel.src = ORIGIN + "/";
    panel.allow = "clipboard-write";
    document.body.appendChild(panel);
  }

  // localStorage (no sessionStorage) para que el estado sobreviva a pestañas
  // nuevas, p. ej. al abrir la página de un desarrollo desde el chat.
  var ESTADO_MAX_MS = 12 * 60 * 60 * 1000; // 12 h

  function guardarEstado(clave, valor) {
    try {
      localStorage.setItem(clave, JSON.stringify({ t: Date.now(), v: valor }));
    } catch (e) {}
  }

  function leerEstado(clave) {
    try {
      var d = JSON.parse(localStorage.getItem(clave));
      if (!d || !d.t || Date.now() - d.t > ESTADO_MAX_MS) return null;
      return d.v;
    } catch (e) {
      return null;
    }
  }

  function alternar(forzar) {
    abierto = typeof forzar === "boolean" ? forzar : !abierto;
    guardarEstado("sisol-abierto", abierto ? "1" : "0");
    if (abierto) {
      asegurarPanel();
      setTimeout(function () {
        panel.classList.add("abierto");
      }, 30);
      burbuja.innerHTML = CLOSE_SVG;
      ocultarNotif();
    } else {
      if (panel) panel.classList.remove("abierto");
      burbuja.innerHTML = '<span class="pulso"></span>' + WHATSAPP_SVG;
    }
  }

  burbuja.addEventListener("click", function () {
    alternar();
  });

  // ---------- notificación de bienvenida ----------
  var notif = null;

  function ocultarNotif() {
    if (notif) {
      notif.classList.remove("visible");
      setTimeout(function () {
        if (notif) notif.remove();
        notif = null;
      }, 400);
    }
  }

  function mostrarNotif() {
    if (abierto) return;
    if (leerEstado("sisol-notif-vista")) return;
    guardarEstado("sisol-notif-vista", "1");
    notif = document.createElement("div");
    notif.id = "sisol-notif";
    notif.innerHTML =
      "¡Bienvenido! 👋 Soy tu <b>agente de IA</b> de SI SOL. ¿Te ayudo a encontrar tu propiedad ideal?" +
      '<span class="cerrar">✕</span>';
    document.body.appendChild(notif);
    setTimeout(function () {
      if (notif) notif.classList.add("visible");
    }, 30);
    notif.addEventListener("click", function (e) {
      if (e.target.className === "cerrar") {
        e.stopPropagation();
        ocultarNotif();
      } else {
        alternar(true);
      }
    });
    setTimeout(ocultarNotif, 15000); // se oculta sola a los 15 s
  }

  if (document.readyState === "complete") {
    setTimeout(mostrarNotif, 2000);
  } else {
    window.addEventListener("load", function () {
      setTimeout(mostrarNotif, 2000);
    });
  }

  // ---------- al cambiar de página o pestaña, reabre el chat si estaba en curso ----------
  if (leerEstado("sisol-abierto") === "1") {
    alternar(true);
  }
})();
