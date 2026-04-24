/* global React, Icon */
const { useState: useStateDash } = React;

const PROFILE = {
  name: "Alejandra Martínez Rivera",
  title: "Gerente de Sistemas · Administrador",
  employee: "EMP-00248",
  curp: "MARA890514MDFXXX02",
  empresa: "Sisol Soluciones Inmobiliarias",
  area: "Tecnología de la Información",
  ubicacion: "CDMX · Torre Corporativa",
  director: "Luis Fernando Cárdenas",
  gerente: "María Esther Villalobos",
  jefe: "Roberto Domínguez",
  lider: "Alejandra Martínez Rivera",
  telefono: "+52 55 4821 0032 ext. 118",
  celular: "+52 55 6213 8877",
  correo: "a.martinez@sisol.com.mx",
  initials: "AM",
};

const EQUIPMENT = [
  { type: "inventory", name: "Lenovo ThinkPad X1 Carbon", tag: "LAP-00482", meta: "Asignado · 2024-09-12" },
  { type: "inventory", name: "Dell UltraSharp U2723QE 27\"", tag: "MON-00129", meta: "Asignado · 2024-09-12" },
  { type: "phone",     name: "iPhone 14 Pro · 256 GB",     tag: "CEL-00061", meta: "Asignado · 2025-02-03" },
  { type: "badge",     name: "Gafete RFID nivel A",        tag: "GAF-00248", meta: "Activo" },
];

const CREDS = [
  { sys: "MAIL",   user: "a.martinez@sisol.com.mx",   pass: "••••••••••••" },
  { sys: "DRP",    user: "amartinez.drp",              pass: "••••••••••"   },
  { sys: "GP",     user: "amtz-gp",                    pass: "••••••••••••" },
  { sys: "BITRIX", user: "alejandra.martinez",         pass: "••••••••"     },
  { sys: "ENK",    user: "amartinez",                  pass: "•••••••••"    },
  { sys: "OTRO",   user: "—",                          pass: "—"            },
];

const ACTIVITY = [3, 5, 2, 6, 4, 8, 7, 9, 6, 10, 8, 11, 9, 12, 10, 13, 9, 11, 14, 10, 12, 15, 11, 9, 13, 12, 8, 10, 12, 14];

function Dashboard() {
  const [reveal, setReveal] = useStateDash({});
  const toggle = (k) => setReveal((r) => ({ ...r, [k]: !r[k] }));

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Mi Perfil</h1>
          <div className="sub">Resumen de tu información, equipo asignado y accesos a sistemas.</div>
        </div>
        <div className="actions">
          <button className="btn sm"><Icon name="pen" size={14}/> Editar</button>
          <button className="btn sm"><Icon name="lock" size={14}/> Cambiar contraseña</button>
          <button className="btn sm danger-ghost"><Icon name="logout" size={14}/> Cerrar sesión</button>
        </div>
      </div>

      <div className="dash">
        {/* LEFT: profile card */}
        <section className="card profile-card">
          <div style={{display:"flex", alignItems:"center", gap: 16}}>
            <div className="avatar-wrap">
              <div className="avatar">{PROFILE.initials}</div>
              <button className="cam" title="Cambiar foto"><Icon name="camera" size={13}/></button>
            </div>
            <div style={{minWidth: 0}}>
              <div className="name">{PROFILE.name}</div>
              <div className="title">{PROFILE.title}</div>
              <div className="badges">
                <span className="chip brand"><span className="dot"/> Administrador</span>
                <span className="chip success"><span className="dot"/> Activo</span>
              </div>
            </div>
          </div>

          <div className="quick">
            <div className="quick-cell">
              <div className="n">4</div>
              <div className="l">Equipos</div>
            </div>
            <div className="quick-cell">
              <div className="n">6</div>
              <div className="l">Accesos</div>
            </div>
            <div className="quick-cell">
              <div className="n">98%</div>
              <div className="l">Asist.</div>
            </div>
          </div>

          <div>
            <div style={{display:"flex", justifyContent:"space-between", alignItems:"center"}}>
              <div style={{fontSize: 12, color: "var(--ink-3)", textTransform: "uppercase", letterSpacing: "0.08em", fontWeight: 500}}>
                Actividad · 30 días
              </div>
              <span className="mono" style={{fontSize: 11.5, color: "var(--ink-3)"}}>284 eventos</span>
            </div>
            <div className="activity">
              {ACTIVITY.map((v, i) => (
                <div key={i} className="bar" style={{height: `${v * 6}%`}}/>
              ))}
            </div>
          </div>

          <hr className="h-divider"/>

          <div style={{display: "flex", flexDirection: "column", gap: 6}}>
            <div className="row" style={{gridTemplateColumns: "1fr auto", padding: "6px 0", borderBottom: 0}}>
              <span className="k"><Icon name="mail" size={14} className="ico"/> Correo</span>
              <span className="v mono" style={{fontSize: 12.5}}>{PROFILE.correo}</span>
            </div>
            <div className="row" style={{gridTemplateColumns: "1fr auto", padding: "6px 0", borderBottom: 0}}>
              <span className="k"><Icon name="phone" size={14} className="ico"/> Celular</span>
              <span className="v mono" style={{fontSize: 12.5}}>{PROFILE.celular}</span>
            </div>
            <div className="row" style={{gridTemplateColumns: "1fr auto", padding: "6px 0", borderBottom: 0}}>
              <span className="k"><Icon name="pin" size={14} className="ico"/> Ubicación</span>
              <span className="v" style={{fontSize: 13}}>{PROFILE.ubicacion}</span>
            </div>
          </div>
        </section>

        {/* RIGHT: grid of cards */}
        <section className="dash-right">
          {/* Datos del colaborador */}
          <div className="card" style={{gridColumn: "1 / -1"}}>
            <div className="card-hd">
              <div className="title"><span className="ico"><Icon name="badge" size={16}/></span> Datos del colaborador</div>
              <div className="toggle-group">
                <button className="active">Resumen</button>
                <button>Completo</button>
              </div>
            </div>
            <div className="card-bd" style={{padding: "4px 18px 14px"}}>
              <div style={{display: "grid", gridTemplateColumns: "1fr 1fr", columnGap: 28}}>
                <Row icon="hash" k="N° empleado" v={PROFILE.employee} mono/>
                <Row icon="shield" k="CURP" v={PROFILE.curp} mono/>
                <Row icon="briefcase" k="Empresa" v={PROFILE.empresa}/>
                <Row icon="tree" k="Área" v={PROFILE.area}/>
                <Row icon="user" k="Director" v={PROFILE.director}/>
                <Row icon="user" k="Gerente regional" v={PROFILE.gerente}/>
                <Row icon="user" k="Jefe inmediato" v={PROFILE.jefe}/>
                <Row icon="users3" k="Líder" v={PROFILE.lider}/>
              </div>
            </div>
          </div>

          {/* Equipo asignado */}
          <div className="card">
            <div className="card-hd">
              <div className="title"><span className="ico"><Icon name="inventory" size={16}/></span> Equipo asignado</div>
              <span className="chip"><span className="dot"/> {EQUIPMENT.length} activos</span>
            </div>
            <div className="card-bd">
              {EQUIPMENT.map((e, i) => (
                <div className="eq-item" key={i}>
                  <div className="eq-ico"><Icon name={e.type} size={16}/></div>
                  <div>
                    <div className="eq-name">{e.name}</div>
                    <div className="eq-meta">{e.tag} · {e.meta}</div>
                  </div>
                  <button className="btn sm" style={{height: 26, padding: "0 8px", fontSize: 12}}>Ver</button>
                </div>
              ))}
            </div>
          </div>

          {/* Credenciales */}
          <div className="card">
            <div className="card-hd">
              <div className="title"><span className="ico"><Icon name="key" size={16}/></span> Credenciales de sistemas</div>
              <span className="chip brand"><span className="dot"/> Cifradas</span>
            </div>
            <div className="card-bd">
              {CREDS.map((c, i) => (
                <div className="cred-row" key={i}>
                  <span className="sys">{c.sys}</span>
                  <span className="user"><span className="u-label">user</span>{c.user}</span>
                  <div className="pass-wrap">
                    <span className={"pass" + (reveal[c.sys] ? " revealed" : "")}>
                      {reveal[c.sys] ? "Tr#8s-2026!" : c.pass}
                    </span>
                    <button className="eye" onClick={() => toggle(c.sys)} title="Mostrar/ocultar">
                      <Icon name={reveal[c.sys] ? "eyeOff" : "eye"} size={14}/>
                    </button>
                    <button className="eye" title="Copiar"><Icon name="copy" size={14}/></button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

function Row({ icon, k, v, mono }) {
  return (
    <div className="row" style={{gridTemplateColumns: "150px 1fr"}}>
      <span className="k"><Icon name={icon} size={13} className="ico"/> {k}</span>
      <span className={"v" + (mono ? " mono" : "")} style={{fontSize: mono ? 13 : 13.5}}>{v}</span>
    </div>
  );
}

// Placeholder for other nav items
function Placeholder({ title }) {
  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>{title}</h1>
          <div className="sub">Módulo disponible en la app principal · vista de rediseño pendiente.</div>
        </div>
      </div>
      <div className="card" style={{padding: 48, display: "flex", flexDirection: "column", alignItems: "center", gap: 12, textAlign: "center", color: "var(--ink-3)"}}>
        <Icon name="sparkle" size={28}/>
        <div style={{fontSize: 14, color: "var(--ink-2)", fontWeight: 500}}>Próximamente en este rediseño</div>
        <div style={{fontSize: 13, maxWidth: 440}}>
          El foco de esta iteración es el sistema visual: login y Mi Perfil. Los otros módulos heredarán los mismos tokens, tipografía y componentes.
        </div>
      </div>
    </div>
  );
}

window.Dashboard = Dashboard;
window.Placeholder = Placeholder;
