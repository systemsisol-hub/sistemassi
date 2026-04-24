/* global React, Icon */
const { useState: useStateShell, useEffect: useEffectShell } = React;

// -------- Sidebar --------
const NAV = [
  {
    section: "Principal",
    items: [
      { id: "profile", label: "Mi Perfil", icon: "user" },
      { id: "social", label: "Social", icon: "users3" },
      { id: "signatures", label: "Firmas", icon: "pen" },
      { id: "calendar", label: "Calendario", icon: "calendar", badge: 3 },
    ],
  },
  {
    section: "Operación",
    items: [
      { id: "incidents", label: "Incidencias", icon: "file" },
      { id: "inventory", label: "Inventario", icon: "inventory" },
      { id: "attendance", label: "Asistencia", icon: "fingerprint" },
      { id: "contacts", label: "Contactos", icon: "phone" },
    ],
  },
  {
    section: "Administración",
    items: [
      { id: "users", label: "Usuarios", icon: "users" },
      { id: "employees", label: "Colaboradores", icon: "badge" },
      { id: "bi", label: "BI", icon: "chart" },
      { id: "logs", label: "Logs", icon: "logs" },
    ],
  },
];

function Sidebar({ active, setActive, expanded, setExpanded }) {
  const closeTimer = React.useRef(null);
  const onEnter = () => { clearTimeout(closeTimer.current); setExpanded(true); };
  const onLeave = () => { closeTimer.current = setTimeout(() => setExpanded(false), 120); };

  return (
    <aside className="rail" onMouseEnter={onEnter} onMouseLeave={onLeave}>
      <div className="brand-row">
        <div className="brand-mark">S</div>
        <div className="brand-name">
          <span className="t1">Sistemassi</span>
          <span className="t2">Sisol</span>
        </div>
      </div>

      <div className="nav">
        {NAV.map((sec) => (
          <div className="nav-section" key={sec.section}>
            <div className="nav-section-title">{sec.section}</div>
            {sec.items.map((it) => (
              <button
                key={it.id}
                className={"nav-item" + (active === it.id ? " active" : "")}
                onClick={() => setActive(it.id)}
                title={!expanded ? it.label : ""}
              >
                <span className="ico"><Icon name={it.icon} size={17}/></span>
                <span className="label">{it.label}</span>
                {it.badge && <span className="badge">{it.badge}</span>}
              </button>
            ))}
          </div>
        ))}
      </div>

      <div className="footer">
        <button className="user-chip">
          <span className="ava">AM</span>
          <span className="u-meta">
            <span className="n">Alejandra Martínez</span>
            <span className="r">Administrador</span>
          </span>
        </button>
      </div>
    </aside>
  );
}

// -------- Topbar --------
function Topbar({ title, crumbs }) {
  return (
    <header className="topbar">
      <div className="crumbs">
        {crumbs.map((c, i) => (
          <React.Fragment key={i}>
            <span className={"c" + (i === crumbs.length - 1 ? " current" : "")}>{c}</span>
            {i < crumbs.length - 1 && <span className="sep">/</span>}
          </React.Fragment>
        ))}
      </div>
      <div className="spacer"/>
      <div className="search">
        <Icon name="search" size={14}/>
        <span>Buscar colaborador, evento, activo…</span>
        <span className="kbd">⌘K</span>
      </div>
      <button className="top-ic" title="Ayuda"><Icon name="help" size={17}/></button>
      <button className="top-ic" title="Notificaciones">
        <Icon name="bell" size={17}/>
        <span className="dot-notif"/>
      </button>
    </header>
  );
}

window.Sidebar = Sidebar;
window.Topbar = Topbar;
