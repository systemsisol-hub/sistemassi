/* global React, Icon */
const { useState: useStatePages } = React;

// ============ CALENDARIO ============
const EVENTS = [
  { day: 3, len: 1, title: "Junta de dirección", color: "brand", time: "09:00" },
  { day: 5, len: 2, title: "Revisión trimestral Q2", color: "brand", time: "11:00" },
  { day: 8, len: 1, title: "1:1 con Luis Cárdenas", color: "mute", time: "14:30" },
  { day: 11, len: 1, title: "Demo sistema asistencia", color: "success", time: "10:00" },
  { day: 14, len: 3, title: "Capacitación Bitrix24", color: "warn", time: "09:30" },
  { day: 18, len: 1, title: "Auditoría IT", color: "brand", time: "08:00" },
  { day: 22, len: 1, title: "Comida proveedor Dell", color: "mute", time: "13:00" },
  { day: 25, len: 2, title: "Cierre de periodo", color: "danger", time: "08:00" },
  { day: 28, len: 1, title: "Retro de equipo", color: "success", time: "16:00" },
];

function CalendarPage() {
  const [mode, setMode] = useStatePages("grupal");
  const [view, setView] = useStatePages("month");

  // build month grid (April 2026, starts Wednesday)
  const firstDay = 3; // Wed
  const days = 30;
  const weeks = 5;
  const cells = [];
  for (let i = 0; i < weeks * 7; i++) {
    const dn = i - firstDay + 1;
    cells.push(dn >= 1 && dn <= days ? dn : null);
  }

  const eventByDay = {};
  EVENTS.forEach(ev => { eventByDay[ev.day] = ev; });

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Calendario</h1>
          <div className="sub">Abril 2026 · Eventos de tu equipo y usuarios que sigues.</div>
        </div>
        <div className="actions">
          <div className="toggle-group">
            <button className={mode === "personal" ? "active" : ""} onClick={() => setMode("personal")}>Personal</button>
            <button className={mode === "grupal" ? "active" : ""} onClick={() => setMode("grupal")}>Grupal</button>
          </div>
          <button className="btn sm"><Icon name="search" size={14}/> Buscar</button>
          <button className="btn primary sm"><Icon name="plus" size={14}/> Nuevo evento</button>
        </div>
      </div>

      <div className="card">
        <div className="card-hd">
          <div style={{display:"flex", alignItems:"center", gap: 12}}>
            <button className="btn icon sm"><Icon name="chevron" size={14} style={{transform:"rotate(180deg)"}}/></button>
            <div style={{fontSize: 15, fontWeight: 600, letterSpacing: "-0.01em"}}>Abril 2026</div>
            <button className="btn icon sm"><Icon name="chevron" size={14}/></button>
            <button className="btn sm" style={{marginLeft: 8}}>Hoy</button>
          </div>
          <div className="toggle-group">
            <button className={view === "month" ? "active" : ""} onClick={() => setView("month")}>Mes</button>
            <button className={view === "week" ? "active" : ""} onClick={() => setView("week")}>Semana</button>
            <button className={view === "day" ? "active" : ""} onClick={() => setView("day")}>Día</button>
            <button className={view === "list" ? "active" : ""} onClick={() => setView("list")}>Lista</button>
          </div>
        </div>

        <div style={{display: "grid", gridTemplateColumns: "repeat(7, 1fr)", borderBottom: "1px solid var(--line)"}}>
          {["Lun","Mar","Mié","Jue","Vie","Sáb","Dom"].map(d => (
            <div key={d} style={{
              padding: "8px 12px", fontSize: 11, fontWeight: 500,
              textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--ink-3)",
              borderRight: "1px solid var(--line-2)",
            }}>{d}</div>
          ))}
        </div>
        <div style={{display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gridAutoRows: "minmax(110px, 1fr)"}}>
          {cells.map((d, i) => {
            const ev = d ? eventByDay[d] : null;
            const isToday = d === 14;
            return (
              <div key={i} style={{
                borderRight: "1px solid var(--line-2)",
                borderBottom: "1px solid var(--line-2)",
                padding: 8,
                background: d ? "var(--panel)" : "oklch(0.985 0.003 260)",
                position: "relative",
                minHeight: 110,
              }}>
                {d && (
                  <>
                    <div style={{
                      fontSize: 12,
                      fontFamily: "var(--f-mono)",
                      color: isToday ? "#fff" : "var(--ink-2)",
                      width: 22, height: 22,
                      borderRadius: "50%",
                      display: "inline-flex", alignItems: "center", justifyContent: "center",
                      background: isToday ? "var(--brand)" : "transparent",
                      fontWeight: isToday ? 600 : 500,
                      marginBottom: 4,
                    }}>{d}</div>
                    {ev && (
                      <div className={"ev-pill ev-" + ev.color} style={{
                        fontSize: 11.5,
                        padding: "3px 6px",
                        borderRadius: 4,
                        marginTop: 2,
                        background: ev.color === "brand" ? "var(--brand-tint)" :
                                    ev.color === "success" ? "var(--success-tint)" :
                                    ev.color === "warn" ? "var(--warn-tint)" :
                                    ev.color === "danger" ? "var(--danger-tint)" : "var(--hover)",
                        color: ev.color === "brand" ? "var(--brand)" :
                               ev.color === "success" ? "oklch(0.42 0.14 155)" :
                               ev.color === "warn" ? "oklch(0.45 0.15 75)" :
                               ev.color === "danger" ? "var(--danger)" : "var(--ink-2)",
                        borderLeft: "2px solid currentColor",
                        overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                        fontWeight: 500,
                      }}>
                        <span className="mono" style={{opacity: 0.7, marginRight: 6}}>{ev.time}</span>
                        {ev.title}
                      </div>
                    )}
                  </>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ============ INCIDENCIAS ============
const INCIDENCES = [
  { id: "INC-00812", user: "Carlos Ramírez", area: "Ventas CDMX", type: "VACACIONES", days: 5, from: "2026-05-04", status: "pendiente" },
  { id: "INC-00811", user: "Mariana Solís", area: "Marketing", type: "INCAPACIDAD", days: 2, from: "2026-04-22", status: "aprobada" },
  { id: "INC-00810", user: "Javier Ontiveros", area: "Sistemas", type: "PERMISO S/GOCE", days: 1, from: "2026-04-21", status: "pendiente" },
  { id: "INC-00809", user: "Paulina Vega", area: "Finanzas", type: "HOME OFFICE", days: 3, from: "2026-04-20", status: "aprobada" },
  { id: "INC-00808", user: "Fernando Gil", area: "Operaciones", type: "PERMISO C/GOCE", days: 1, from: "2026-04-19", status: "rechazada" },
  { id: "INC-00807", user: "Laura Espinosa", area: "RH", type: "VACACIONES", days: 7, from: "2026-04-15", status: "aprobada" },
];

function IncidenciasPage() {
  const [filter, setFilter] = useStatePages("all");
  const rows = filter === "all" ? INCIDENCES : INCIDENCES.filter(r => r.status === filter);
  const statusChip = (s) => {
    const map = { pendiente: "warn", aprobada: "success", rechazada: "danger" };
    return <span className={"chip " + map[s]}><span className="dot"/>{s.charAt(0).toUpperCase() + s.slice(1)}</span>;
  };

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Incidencias</h1>
          <div className="sub">Solicitudes de vacaciones, permisos e incapacidades del personal.</div>
        </div>
        <div className="actions">
          <button className="btn sm"><Icon name="file" size={14}/> Exportar PDF</button>
          <button className="btn primary sm"><Icon name="plus" size={14}/> Nueva incidencia</button>
        </div>
      </div>

      {/* Summary strip */}
      <div style={{display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 20}}>
        {[
          { l: "Total del mes", v: "32", d: "+4 vs mes ant." },
          { l: "Pendientes", v: "6", d: "requieren tu acción", accent: "warn" },
          { l: "Días acumulados", v: "47", d: "en todo el equipo" },
          { l: "Aprobación promedio", v: "3.2h", d: "SLA < 24h" },
        ].map((k, i) => (
          <div key={i} className="card" style={{padding: 14}}>
            <div style={{fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--ink-3)", fontWeight: 500}}>{k.l}</div>
            <div className="mono" style={{fontSize: 24, fontWeight: 600, marginTop: 4, letterSpacing: "-0.02em", color: k.accent === "warn" ? "oklch(0.45 0.15 75)" : "var(--ink)"}}>{k.v}</div>
            <div style={{fontSize: 11.5, color: "var(--ink-3)", marginTop: 2}}>{k.d}</div>
          </div>
        ))}
      </div>

      <div className="card">
        <div className="card-hd">
          <div className="title"><Icon name="file" size={15} style={{color: "var(--ink-3)"}}/> Solicitudes recientes</div>
          <div className="toggle-group">
            {["all","pendiente","aprobada","rechazada"].map(f => (
              <button key={f} className={filter === f ? "active" : ""} onClick={() => setFilter(f)}>
                {f === "all" ? "Todas" : f.charAt(0).toUpperCase() + f.slice(1) + "s"}
              </button>
            ))}
          </div>
        </div>
        <div style={{overflowX: "auto"}}>
          <table style={{width: "100%", borderCollapse: "collapse", fontSize: 13}}>
            <thead>
              <tr style={{borderBottom: "1px solid var(--line)", color: "var(--ink-3)", fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em"}}>
                <th style={{textAlign: "left", padding: "10px 18px", fontWeight: 500}}>Folio</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Colaborador</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Área</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Tipo</th>
                <th style={{textAlign: "right", padding: "10px 12px", fontWeight: 500}}>Días</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Inicio</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Estado</th>
                <th style={{padding: "10px 18px"}}></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i} style={{borderBottom: "1px solid var(--line-2)", transition: "background 120ms ease"}}
                  onMouseEnter={e => e.currentTarget.style.background = "var(--hover)"}
                  onMouseLeave={e => e.currentTarget.style.background = ""}>
                  <td className="mono" style={{padding: "11px 18px", fontSize: 12, color: "var(--ink-2)"}}>{r.id}</td>
                  <td style={{padding: "11px 12px", fontWeight: 500}}>{r.user}</td>
                  <td style={{padding: "11px 12px", color: "var(--ink-2)"}}>{r.area}</td>
                  <td style={{padding: "11px 12px"}}>
                    <span className="mono" style={{fontSize: 11, padding: "2px 7px", borderRadius: 4, background: "var(--active)", color: "var(--brand-ink)"}}>{r.type}</span>
                  </td>
                  <td className="mono" style={{textAlign: "right", padding: "11px 12px"}}>{r.days}</td>
                  <td className="mono" style={{padding: "11px 12px", fontSize: 12.5, color: "var(--ink-2)"}}>{r.from}</td>
                  <td style={{padding: "11px 12px"}}>{statusChip(r.status)}</td>
                  <td style={{padding: "11px 18px", textAlign: "right"}}>
                    <button className="btn sm" style={{height: 26}}>Ver</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ============ INVENTARIO ISSI ============
const INVENTORY = [
  { sku: "LAP-00482", tipo: "LAPTOP", marca: "LENOVO", modelo: "ThinkPad X1 Carbon G11", cond: "NUEVO", asignado: "A. Martínez" },
  { sku: "LAP-00481", tipo: "LAPTOP", marca: "DELL", modelo: "Latitude 5540", cond: "USADO", asignado: "R. Domínguez" },
  { sku: "MON-00129", tipo: "MONITOR", marca: "DELL", modelo: "U2723QE 27\"", cond: "NUEVO", asignado: "A. Martínez" },
  { sku: "CEL-00061", tipo: "CELULAR", marca: "APPLE", modelo: "iPhone 14 Pro 256GB", cond: "USADO", asignado: "A. Martínez" },
  { sku: "IMP-00022", tipo: "IMPRESORA", marca: "RICOH", modelo: "MP 5055", cond: "DAÑADO", asignado: "—" },
  { sku: "PC-00318",  tipo: "PC", marca: "HP", modelo: "EliteDesk 800 G9", cond: "NUEVO", asignado: "Recepción CDMX" },
  { sku: "DD-00091",  tipo: "DISCO DURO", marca: "KINGSTON", modelo: "NV2 1TB NVMe", cond: "NUEVO", asignado: "Almacén" },
  { sku: "TEL-00014", tipo: "TELEFONO", marca: "AASTRA", modelo: "6867i", cond: "SIN REPARACION", asignado: "—" },
];

function InventoryPage() {
  const [tipoF, setTipoF] = useStatePages("TODOS");
  const [query, setQuery] = useStatePages("");
  const tipos = ["TODOS","LAPTOP","PC","MONITOR","CELULAR","IMPRESORA","DISCO DURO","TELEFONO"];
  const rows = INVENTORY.filter(r =>
    (tipoF === "TODOS" || r.tipo === tipoF) &&
    (query === "" || (r.sku + r.modelo + r.marca + r.asignado).toLowerCase().includes(query.toLowerCase()))
  );

  const condChip = (c) => {
    const map = { NUEVO: "success", USADO: "", "DAÑADO": "danger", "SIN REPARACION": "warn" };
    return <span className={"chip " + map[c]}><span className="dot"/>{c}</span>;
  };

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Inventario ISSI</h1>
          <div className="sub">Control de equipo de cómputo, comunicación y activos asignados.</div>
        </div>
        <div className="actions">
          <button className="btn sm"><Icon name="file" size={14}/> Exportar</button>
          <button className="btn primary sm"><Icon name="plus" size={14}/> Registrar equipo</button>
        </div>
      </div>

      <div style={{display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 12, marginBottom: 20}}>
        {[
          { l: "Total activos", v: "482" },
          { l: "Asignados", v: "341" },
          { l: "En almacén", v: "118" },
          { l: "En reparación", v: "17" },
          { l: "Sin reparación", v: "6", accent: "danger" },
        ].map((k, i) => (
          <div key={i} className="card" style={{padding: 14}}>
            <div style={{fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--ink-3)", fontWeight: 500}}>{k.l}</div>
            <div className="mono" style={{fontSize: 22, fontWeight: 600, marginTop: 4, letterSpacing: "-0.02em", color: k.accent === "danger" ? "var(--danger)" : "var(--ink)"}}>{k.v}</div>
          </div>
        ))}
      </div>

      <div className="card">
        <div className="card-hd">
          <div style={{display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap"}}>
            <div className="input-wrap" style={{height: 30, minWidth: 220}}>
              <span className="adorn"><Icon name="search" size={14}/></span>
              <input placeholder="Buscar SKU, modelo, asignado…" value={query} onChange={e => setQuery(e.target.value)}/>
            </div>
            <div className="toggle-group" style={{marginLeft: 4}}>
              {tipos.slice(0, 5).map(t => (
                <button key={t} className={tipoF === t ? "active" : ""} onClick={() => setTipoF(t)}>{t}</button>
              ))}
            </div>
          </div>
          <span className="chip"><span className="dot"/> {rows.length} resultados</span>
        </div>
        <div style={{overflowX: "auto"}}>
          <table style={{width: "100%", borderCollapse: "collapse", fontSize: 13}}>
            <thead>
              <tr style={{borderBottom: "1px solid var(--line)", color: "var(--ink-3)", fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em"}}>
                <th style={{textAlign: "left", padding: "10px 18px", fontWeight: 500}}>SKU</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Tipo</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Marca</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Modelo</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Condición</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Asignado a</th>
                <th style={{padding: "10px 18px"}}></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i} style={{borderBottom: "1px solid var(--line-2)"}}
                  onMouseEnter={e => e.currentTarget.style.background = "var(--hover)"}
                  onMouseLeave={e => e.currentTarget.style.background = ""}>
                  <td className="mono" style={{padding: "11px 18px", fontSize: 12, color: "var(--brand)", fontWeight: 500}}>{r.sku}</td>
                  <td className="mono" style={{padding: "11px 12px", fontSize: 11, color: "var(--ink-2)"}}>{r.tipo}</td>
                  <td style={{padding: "11px 12px", color: "var(--ink-2)"}}>{r.marca}</td>
                  <td style={{padding: "11px 12px", fontWeight: 500}}>{r.modelo}</td>
                  <td style={{padding: "11px 12px"}}>{condChip(r.cond)}</td>
                  <td style={{padding: "11px 12px", color: r.asignado === "—" ? "var(--ink-4)" : "var(--ink)"}}>{r.asignado}</td>
                  <td style={{padding: "11px 18px", textAlign: "right"}}>
                    <button className="btn sm" style={{height: 26}}>Editar</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ============ ASISTENCIA ============
function AttendancePage() {
  const [mode, setMode] = useStatePages("checador");
  const [checked, setChecked] = useStatePages(false);
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Asistencia</h1>
          <div className="sub">Checador biométrico y reportes de entrada/salida.</div>
        </div>
        <div className="toggle-group">
          <button className={mode === "checador" ? "active" : ""} onClick={() => setMode("checador")}>Checador</button>
          <button className={mode === "admin" ? "active" : ""} onClick={() => setMode("admin")}>Configuración</button>
        </div>
      </div>

      <div style={{display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20}}>
        {/* Checador */}
        <div className="card" style={{padding: 28, display: "flex", flexDirection: "column", alignItems: "center", gap: 18}}>
          <div style={{textAlign: "center"}}>
            <div className="mono" style={{fontSize: 12, color: "var(--ink-3)", letterSpacing: "0.1em", textTransform: "uppercase"}}>
              {now.toLocaleDateString("es-MX", { weekday: "long", day: "numeric", month: "long", year: "numeric" })}
            </div>
            <div className="mono" style={{fontSize: 64, fontWeight: 600, letterSpacing: "-0.04em", marginTop: 6, color: "var(--ink)"}}>
              {hh}:{mm}
            </div>
          </div>

          <div style={{
            width: 160, height: 160, borderRadius: "50%",
            background: checked ? "var(--success-tint)" : "var(--brand-tint)",
            border: "2px solid " + (checked ? "var(--success)" : "var(--brand)"),
            display: "flex", alignItems: "center", justifyContent: "center",
            color: checked ? "oklch(0.42 0.14 155)" : "var(--brand)",
            transition: "all 240ms ease",
            cursor: "pointer",
            position: "relative",
          }} onClick={() => setChecked(!checked)}>
            {checked ? <Icon name="check" size={72}/> : <Icon name="fingerprint" size={72}/>}
            {!checked && (
              <div style={{
                position: "absolute", inset: -8, borderRadius: "50%",
                border: "2px solid var(--brand)",
                opacity: 0.3,
                animation: "ping 1.6s ease-out infinite",
              }}/>
            )}
          </div>

          <style>{`@keyframes ping { 0% { transform: scale(1); opacity: 0.4; } 100% { transform: scale(1.18); opacity: 0; } }`}</style>

          <button className="btn primary lg" onClick={() => setChecked(!checked)}>
            {checked ? "Registrar salida" : "Registrar entrada"}
          </button>

          <div style={{display: "flex", gap: 20, color: "var(--ink-3)", fontSize: 12.5}}>
            <div style={{display: "flex", alignItems: "center", gap: 6}}>
              <Icon name="pin" size={13}/> CDMX · Torre Corporativa
            </div>
            <div style={{display: "flex", alignItems: "center", gap: 6}}>
              <Icon name="camera" size={13}/> Foto activada
            </div>
          </div>
        </div>

        {/* Today log */}
        <div className="card">
          <div className="card-hd">
            <div className="title"><Icon name="logs" size={15} style={{color: "var(--ink-3)"}}/> Tu registro · Hoy</div>
            <span className="chip success"><span className="dot"/> Jornada activa</span>
          </div>
          <div className="card-bd" style={{padding: 18}}>
            {[
              { t: "08:47", e: "Entrada", loc: "CDMX · Torre Corp.", ok: true },
              { t: "13:12", e: "Salida a comida", loc: "CDMX · Torre Corp.", ok: true },
              { t: "14:03", e: "Regreso de comida", loc: "CDMX · Torre Corp.", ok: true },
              { t: "—", e: "Salida fin de jornada", loc: "Pendiente", ok: false },
            ].map((l, i) => (
              <div key={i} style={{
                display: "grid", gridTemplateColumns: "70px 1fr auto",
                gap: 14, padding: "10px 0",
                borderBottom: i < 3 ? "1px dashed var(--line-2)" : "none",
                alignItems: "center", opacity: l.ok ? 1 : 0.55,
              }}>
                <span className="mono" style={{fontSize: 14, fontWeight: 600, color: l.ok ? "var(--ink)" : "var(--ink-3)"}}>{l.t}</span>
                <div>
                  <div style={{fontSize: 13.5, fontWeight: 500}}>{l.e}</div>
                  <div style={{fontSize: 12, color: "var(--ink-3)"}}>{l.loc}</div>
                </div>
                {l.ok ? <Icon name="check" size={16} style={{color: "var(--success)"}}/> : <span style={{fontSize: 11, color: "var(--ink-4)", textTransform: "uppercase", letterSpacing: "0.08em"}}>pend.</span>}
              </div>
            ))}
            <hr className="h-divider" style={{margin: "12px 0"}}/>
            <div style={{display: "flex", justifyContent: "space-between", fontSize: 13}}>
              <span style={{color: "var(--ink-3)"}}>Tiempo trabajado</span>
              <span className="mono" style={{fontWeight: 600}}>7h 42m</span>
            </div>
            <div style={{display: "flex", justifyContent: "space-between", fontSize: 13, marginTop: 6}}>
              <span style={{color: "var(--ink-3)"}}>Días consecutivos</span>
              <span className="mono" style={{fontWeight: 600}}>23</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ============ USUARIOS ============
const USERS = [
  { n: "Alejandra Martínez Rivera", e: "a.martinez@sisol.com.mx", role: "admin", area: "TI", active: true },
  { n: "Luis Fernando Cárdenas", e: "l.cardenas@sisol.com.mx", role: "director", area: "Dirección", active: true },
  { n: "Mariana Solís", e: "m.solis@sisol.com.mx", role: "user", area: "Marketing", active: true },
  { n: "Javier Ontiveros", e: "j.ontiveros@sisol.com.mx", role: "user", area: "Sistemas", active: true },
  { n: "Paulina Vega", e: "p.vega@sisol.com.mx", role: "manager", area: "Finanzas", active: true },
  { n: "Fernando Gil", e: "f.gil@sisol.com.mx", role: "user", area: "Operaciones", active: false },
  { n: "Laura Espinosa", e: "l.espinosa@sisol.com.mx", role: "manager", area: "RH", active: true },
  { n: "Carlos Ramírez", e: "c.ramirez@sisol.com.mx", role: "user", area: "Ventas CDMX", active: true },
];

function UsersPage() {
  const [q, setQ] = useStatePages("");
  const rows = USERS.filter(u => (u.n + u.e + u.area).toLowerCase().includes(q.toLowerCase()));
  const initials = (n) => n.split(" ").slice(0,2).map(s => s[0]).join("");
  const roleChip = (r) => {
    const map = { admin: "brand", director: "warn", manager: "", user: "" };
    return <span className={"chip " + map[r]}><span className="dot"/>{r}</span>;
  };

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Usuarios</h1>
          <div className="sub">Gestión de cuentas, roles y permisos del sistema.</div>
        </div>
        <div className="actions">
          <button className="btn sm"><Icon name="file" size={14}/> Exportar CSV</button>
          <button className="btn primary sm"><Icon name="plus" size={14}/> Invitar usuario</button>
        </div>
      </div>

      <div className="card">
        <div className="card-hd">
          <div className="input-wrap" style={{height: 30, minWidth: 280}}>
            <span className="adorn"><Icon name="search" size={14}/></span>
            <input placeholder="Buscar por nombre, correo, área…" value={q} onChange={e => setQ(e.target.value)}/>
          </div>
          <span className="chip"><span className="dot"/> {rows.length} de {USERS.length}</span>
        </div>
        <div style={{overflowX: "auto"}}>
          <table style={{width: "100%", borderCollapse: "collapse", fontSize: 13}}>
            <thead>
              <tr style={{borderBottom: "1px solid var(--line)", color: "var(--ink-3)", fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em"}}>
                <th style={{textAlign: "left", padding: "10px 18px", fontWeight: 500}}>Usuario</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Área</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Rol</th>
                <th style={{textAlign: "left", padding: "10px 12px", fontWeight: 500}}>Estado</th>
                <th style={{padding: "10px 18px"}}></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((u, i) => (
                <tr key={i} style={{borderBottom: "1px solid var(--line-2)"}}
                  onMouseEnter={e => e.currentTarget.style.background = "var(--hover)"}
                  onMouseLeave={e => e.currentTarget.style.background = ""}>
                  <td style={{padding: "11px 18px"}}>
                    <div style={{display: "flex", alignItems: "center", gap: 10}}>
                      <div style={{
                        width: 32, height: 32, borderRadius: "50%",
                        background: "linear-gradient(135deg, oklch(0.92 0.04 265), oklch(0.76 0.08 265))",
                        color: "var(--brand-ink)",
                        display: "inline-flex", alignItems: "center", justifyContent: "center",
                        fontSize: 11, fontWeight: 600, letterSpacing: "-0.02em",
                        flexShrink: 0,
                      }}>{initials(u.n)}</div>
                      <div style={{minWidth: 0}}>
                        <div style={{fontWeight: 500, fontSize: 13.5}}>{u.n}</div>
                        <div className="mono" style={{fontSize: 11.5, color: "var(--ink-3)"}}>{u.e}</div>
                      </div>
                    </div>
                  </td>
                  <td style={{padding: "11px 12px", color: "var(--ink-2)"}}>{u.area}</td>
                  <td style={{padding: "11px 12px"}}>{roleChip(u.role)}</td>
                  <td style={{padding: "11px 12px"}}>
                    {u.active
                      ? <span className="chip success"><span className="dot"/> Activo</span>
                      : <span className="chip"><span className="dot"/> Inactivo</span>}
                  </td>
                  <td style={{padding: "11px 18px", textAlign: "right"}}>
                    <button className="btn sm" style={{height: 26}}>Editar</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ============ BI ============
function BiPage() {
  const metrics = [
    { l: "Ingresos abril", v: "$12.48M", d: "+8.2% vs marzo", up: true },
    { l: "Propiedades activas", v: "1,247", d: "+23 este mes", up: true },
    { l: "Operaciones cerradas", v: "84", d: "-4 vs marzo", up: false },
    { l: "Tiempo promedio cierre", v: "21d", d: "-3d vs marzo", up: true },
  ];

  const chartData = [62, 58, 71, 68, 82, 76, 89, 94, 88, 102, 98, 115, 108, 124, 118, 132, 126, 141, 138, 148, 155, 162];

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Business Intelligence</h1>
          <div className="sub">Indicadores clave del desempeño comercial y operativo.</div>
        </div>
        <div className="actions">
          <div className="toggle-group">
            <button>7d</button>
            <button className="active">30d</button>
            <button>90d</button>
            <button>YTD</button>
          </div>
          <button className="btn sm"><Icon name="file" size={14}/> Exportar</button>
        </div>
      </div>

      <div style={{display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16, marginBottom: 20}}>
        {metrics.map((m, i) => (
          <div key={i} className="card" style={{padding: 18}}>
            <div style={{fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--ink-3)", fontWeight: 500}}>{m.l}</div>
            <div className="mono" style={{fontSize: 26, fontWeight: 600, marginTop: 6, letterSpacing: "-0.025em"}}>{m.v}</div>
            <div style={{display: "flex", alignItems: "center", gap: 5, marginTop: 4, fontSize: 12}}>
              <span style={{color: m.up ? "var(--success)" : "var(--danger)", fontWeight: 500}}>
                {m.up ? "↗" : "↘"} {m.d}
              </span>
            </div>
          </div>
        ))}
      </div>

      <div style={{display: "grid", gridTemplateColumns: "2fr 1fr", gap: 20}}>
        <div className="card">
          <div className="card-hd">
            <div className="title"><Icon name="chart" size={15} style={{color: "var(--ink-3)"}}/> Ingresos mensuales · últimos 22 meses</div>
            <span className="chip brand"><span className="dot"/> En MXN millones</span>
          </div>
          <div style={{padding: "24px 18px 18px"}}>
            <svg viewBox="0 0 440 180" style={{width: "100%", height: 200}}>
              <defs>
                <linearGradient id="gArea" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--brand)" stopOpacity="0.25"/>
                  <stop offset="100%" stopColor="var(--brand)" stopOpacity="0"/>
                </linearGradient>
              </defs>
              {[0,1,2,3].map(i => (
                <line key={i} x1="0" y1={45*i + 10} x2="440" y2={45*i + 10} stroke="var(--line)" strokeDasharray="2,3"/>
              ))}
              {(() => {
                const max = Math.max(...chartData);
                const pts = chartData.map((v, i) => [i * (440/(chartData.length-1)), 170 - (v/max) * 150]);
                const path = pts.map((p, i) => (i === 0 ? "M" : "L") + p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ");
                const area = path + ` L 440 180 L 0 180 Z`;
                return (
                  <>
                    <path d={area} fill="url(#gArea)"/>
                    <path d={path} fill="none" stroke="var(--brand)" strokeWidth="1.8" strokeLinecap="round"/>
                    {pts.map((p, i) => (
                      <circle key={i} cx={p[0]} cy={p[1]} r="2.5" fill="var(--panel)" stroke="var(--brand)" strokeWidth="1.5"/>
                    ))}
                  </>
                );
              })()}
            </svg>
          </div>
        </div>

        <div className="card">
          <div className="card-hd">
            <div className="title"><Icon name="pin" size={15} style={{color: "var(--ink-3)"}}/> Por plaza</div>
          </div>
          <div className="card-bd" style={{padding: "10px 18px 16px"}}>
            {[
              { n: "CDMX", v: 42, p: 88 },
              { n: "Monterrey", v: 28, p: 62 },
              { n: "Guadalajara", v: 19, p: 42 },
              { n: "Querétaro", v: 11, p: 24 },
              { n: "Mérida", v: 7, p: 16 },
            ].map((p, i) => (
              <div key={i} style={{padding: "10px 0", borderBottom: i < 4 ? "1px dashed var(--line-2)" : "none"}}>
                <div style={{display: "flex", justifyContent: "space-between", fontSize: 13, marginBottom: 5}}>
                  <span style={{fontWeight: 500}}>{p.n}</span>
                  <span className="mono" style={{color: "var(--ink-2)"}}>{p.v}%</span>
                </div>
                <div style={{height: 4, background: "var(--hover)", borderRadius: 2, overflow: "hidden"}}>
                  <div style={{
                    width: p.p + "%", height: "100%",
                    background: "linear-gradient(90deg, var(--brand) 0%, color-mix(in oklch, var(--brand) 65%, #fff) 100%)",
                    borderRadius: 2,
                  }}/>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ============ SOCIAL ============
const POSTS = [
  { u: "Mariana Solís", a: "Marketing", t: "2h", body: "¡Felicidades al equipo de ventas Monterrey por cerrar el mes con +18% sobre la meta! 🎉 Gran trabajo.", likes: 24, comments: 6 },
  { u: "Luis F. Cárdenas", a: "Dirección", t: "5h", body: "Mañana a las 10:00 tendremos la junta trimestral en el auditorio. Preparen sus indicadores de área.", likes: 12, comments: 3, pinned: true },
  { u: "Javier Ontiveros", a: "Sistemas", t: "1d", body: "Recordatorio: mantenimiento del servidor DRP este sábado de 22:00 a 02:00. Puede haber intermitencia en el sistema de firmas.", likes: 8, comments: 2 },
  { u: "Laura Espinosa", a: "RH", t: "2d", body: "Les compartimos el nuevo catálogo de capacitaciones disponible desde hoy en el portal. Revísenlo con su líder.", likes: 31, comments: 9 },
];

function SocialPage() {
  const initials = (n) => n.split(" ").slice(0,2).map(s => s[0]).join("");
  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Social</h1>
          <div className="sub">Tablero interno de comunicados y actividad del equipo.</div>
        </div>
        <button className="btn primary sm"><Icon name="plus" size={14}/> Publicar</button>
      </div>

      <div style={{display: "grid", gridTemplateColumns: "1fr 280px", gap: 20, alignItems: "start"}}>
        <div style={{display: "flex", flexDirection: "column", gap: 14}}>
          <div className="card" style={{padding: 16, display: "flex", gap: 12, alignItems: "center"}}>
            <div style={{width: 36, height: 36, borderRadius: "50%", background: "linear-gradient(135deg, oklch(0.92 0.04 265), oklch(0.76 0.08 265))", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 12, fontWeight: 600, color: "var(--brand-ink)"}}>AM</div>
            <div style={{flex: 1, padding: "8px 12px", background: "var(--hover)", borderRadius: 8, color: "var(--ink-3)", fontSize: 13}}>¿Qué quieres compartir con el equipo?</div>
            <button className="btn sm">Publicar</button>
          </div>
          {POSTS.map((p, i) => (
            <div key={i} className="card" style={{padding: 18}}>
              <div style={{display: "flex", gap: 12, alignItems: "flex-start"}}>
                <div style={{width: 38, height: 38, borderRadius: "50%", background: "linear-gradient(135deg, oklch(0.92 0.04 265), oklch(0.76 0.08 265))", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 12, fontWeight: 600, color: "var(--brand-ink)", flexShrink: 0}}>{initials(p.u)}</div>
                <div style={{flex: 1, minWidth: 0}}>
                  <div style={{display: "flex", alignItems: "center", gap: 8, marginBottom: 2}}>
                    <span style={{fontWeight: 600, fontSize: 13.5}}>{p.u}</span>
                    <span style={{color: "var(--ink-4)"}}>·</span>
                    <span style={{color: "var(--ink-3)", fontSize: 12.5}}>{p.a}</span>
                    <span style={{color: "var(--ink-4)"}}>·</span>
                    <span className="mono" style={{color: "var(--ink-3)", fontSize: 12}}>{p.t}</span>
                    {p.pinned && <span className="chip brand" style={{marginLeft: "auto"}}><span className="dot"/> Fijado</span>}
                  </div>
                  <div style={{fontSize: 13.5, lineHeight: 1.55, color: "var(--ink)"}}>{p.body}</div>
                  <div style={{display: "flex", gap: 18, marginTop: 12, fontSize: 12.5, color: "var(--ink-3)"}}>
                    <button style={{display: "flex", alignItems: "center", gap: 5, color: "inherit"}}>♡ {p.likes}</button>
                    <button style={{display: "flex", alignItems: "center", gap: 5, color: "inherit"}}>💬 {p.comments}</button>
                    <button style={{display: "flex", alignItems: "center", gap: 5, color: "inherit", marginLeft: "auto"}}>Compartir</button>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>

        <aside className="card" style={{padding: 18, position: "sticky", top: 16}}>
          <div style={{fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em", color: "var(--ink-3)", fontWeight: 500, marginBottom: 12}}>A quién sigues</div>
          {["Luis F. Cárdenas","Mariana Solís","Javier Ontiveros","Laura Espinosa"].map((n, i) => (
            <div key={i} style={{display: "flex", alignItems: "center", gap: 10, padding: "8px 0", borderBottom: i < 3 ? "1px dashed var(--line-2)" : "none"}}>
              <div style={{width: 28, height: 28, borderRadius: "50%", background: "linear-gradient(135deg, oklch(0.92 0.04 265), oklch(0.76 0.08 265))", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 10.5, fontWeight: 600, color: "var(--brand-ink)"}}>{initials(n)}</div>
              <span style={{fontSize: 12.5, flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap"}}>{n}</span>
              <span className="chip success" style={{fontSize: 10.5}}><span className="dot"/> Sigue</span>
            </div>
          ))}
        </aside>
      </div>
    </div>
  );
}

// ============ FIRMAS ============
function SignaturesPage() {
  const [theme, setTheme] = useStatePages("default");
  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Generador de firmas</h1>
          <div className="sub">Crea tu firma de correo corporativa lista para copiar.</div>
        </div>
        <div className="actions">
          <button className="btn sm"><Icon name="copy" size={14}/> Copiar HTML</button>
          <button className="btn primary sm"><Icon name="mail" size={14}/> Enviarla por correo</button>
        </div>
      </div>

      <div style={{display: "grid", gridTemplateColumns: "340px 1fr", gap: 20}}>
        <div className="card">
          <div className="card-hd">
            <div className="title"><Icon name="pen" size={15} style={{color: "var(--ink-3)"}}/> Datos</div>
          </div>
          <div className="card-bd" style={{padding: "10px 18px 18px", display: "flex", flexDirection: "column", gap: 14}}>
            {[
              { l: "Nombre completo", v: "Alejandra Martínez Rivera" },
              { l: "Puesto", v: "Gerente de Sistemas" },
              { l: "Empresa", v: "Sisol Soluciones Inmobiliarias" },
              { l: "Correo", v: "a.martinez@sisol.com.mx" },
              { l: "Teléfono", v: "+52 55 4821 0032 ext. 118" },
              { l: "Celular", v: "+52 55 6213 8877" },
            ].map((f, i) => (
              <div key={i} className="field">
                <label>{f.l}</label>
                <div className="input-wrap"><input defaultValue={f.v}/></div>
              </div>
            ))}
            <div className="field">
              <label>Tema</label>
              <div className="toggle-group" style={{width: "100%"}}>
                <button className={theme === "default" ? "active" : ""} onClick={() => setTheme("default")} style={{flex: 1}}>Clásico</button>
                <button className={theme === "compact" ? "active" : ""} onClick={() => setTheme("compact")} style={{flex: 1}}>Compacto</button>
                <button className={theme === "dark" ? "active" : ""} onClick={() => setTheme("dark")} style={{flex: 1}}>Oscuro</button>
              </div>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-hd">
            <div className="title"><Icon name="mail" size={15} style={{color: "var(--ink-3)"}}/> Vista previa</div>
            <span className="chip"><span className="dot"/> 640px ancho</span>
          </div>
          <div style={{padding: 40, background: "oklch(0.985 0.003 260)", borderRadius: "0 0 14px 14px"}}>
            <div style={{
              background: theme === "dark" ? "#0f1640" : "#fff",
              color: theme === "dark" ? "#fff" : "#29261b",
              padding: theme === "compact" ? 16 : 24,
              borderRadius: 10, border: "1px solid " + (theme === "dark" ? "#1a2466" : "var(--line)"),
              display: "grid", gridTemplateColumns: "auto 1px 1fr", gap: 20,
            }}>
              <div style={{textAlign: "center"}}>
                <div style={{width: 72, height: 72, borderRadius: "50%", background: "linear-gradient(135deg, #344092, #1a2466)", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22, fontWeight: 600, margin: "0 auto"}}>AM</div>
                <div style={{marginTop: 10, fontFamily: "var(--f-mono)", fontSize: 10, letterSpacing: "0.1em", color: theme === "dark" ? "oklch(0.75 0.04 260)" : "var(--ink-3)"}}>SISOL</div>
              </div>
              <div style={{background: theme === "dark" ? "#1a2466" : "var(--line)"}}/>
              <div style={{fontFamily: "Arial, sans-serif", fontSize: 13, lineHeight: 1.55}}>
                <div style={{fontSize: 16, fontWeight: 700, color: theme === "dark" ? "#fff" : "#344092"}}>Alejandra Martínez Rivera</div>
                <div style={{fontSize: 12, color: theme === "dark" ? "oklch(0.82 0.03 260)" : "#555"}}>Gerente de Sistemas · Sisol Soluciones Inmobiliarias</div>
                <div style={{height: 8}}/>
                <div style={{fontSize: 12}}>📧 a.martinez@sisol.com.mx</div>
                <div style={{fontSize: 12}}>☎ +52 55 4821 0032 ext. 118 · 📱 +52 55 6213 8877</div>
                <div style={{fontSize: 12}}>🌐 sistemassi.com · CDMX, Torre Corporativa</div>
                <div style={{marginTop: 12, fontSize: 10, color: theme === "dark" ? "oklch(0.68 0.03 260)" : "#999", fontStyle: "italic"}}>Este mensaje es confidencial. Si lo recibió por error, por favor notifique al remitente.</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ============ CONTACTOS ============
const CONTACTS = [
  { n: "Roberto Mendieta", c: "Dell Technologies", tag: "Proveedor TI", tel: "+52 55 5261 0100", mail: "rmendieta@dell.com" },
  { n: "Sofía Paredes", c: "Ricoh México", tag: "Proveedor impresión", tel: "+52 55 8872 4411", mail: "s.paredes@ricoh.mx" },
  { n: "Emilio Castañeda", c: "Bufete Legal Castañeda", tag: "Legal", tel: "+52 55 3344 1020", mail: "emilio@bclegal.mx" },
  { n: "Daniela Ruiz", c: "Bitrix24 LATAM", tag: "Software", tel: "+52 55 1122 3344", mail: "d.ruiz@bitrix24.com" },
  { n: "Carlos Ibáñez", c: "Enkontrol", tag: "ERP", tel: "+52 81 4455 6677", mail: "cibanez@enkontrol.com" },
  { n: "Viviana Cortez", c: "Aastra Networks", tag: "Telefonía", tel: "+52 55 9988 0011", mail: "v.cortez@aastra.com" },
];

function ContactsPage() {
  const [q, setQ] = useStatePages("");
  const rows = CONTACTS.filter(c => (c.n + c.c + c.tag).toLowerCase().includes(q.toLowerCase()));
  const initials = (n) => n.split(" ").slice(0,2).map(s => s[0]).join("");
  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Contactos externos</h1>
          <div className="sub">Proveedores, legales y aliados estratégicos.</div>
        </div>
        <button className="btn primary sm"><Icon name="plus" size={14}/> Nuevo contacto</button>
      </div>

      <div className="card" style={{marginBottom: 0}}>
        <div className="card-hd">
          <div className="input-wrap" style={{height: 30, minWidth: 280}}>
            <span className="adorn"><Icon name="search" size={14}/></span>
            <input placeholder="Buscar contacto, empresa, categoría…" value={q} onChange={e => setQ(e.target.value)}/>
          </div>
          <span className="chip"><span className="dot"/> {rows.length} contactos</span>
        </div>
        <div style={{display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 1, background: "var(--line)"}}>
          {rows.map((c, i) => (
            <div key={i} style={{padding: 16, background: "var(--panel)"}}>
              <div style={{display: "flex", gap: 12, alignItems: "center", marginBottom: 10}}>
                <div style={{width: 38, height: 38, borderRadius: 10, background: "var(--brand-tint)", color: "var(--brand)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 12, fontWeight: 600}}>{initials(c.n)}</div>
                <div style={{minWidth: 0, flex: 1}}>
                  <div style={{fontWeight: 600, fontSize: 13.5}}>{c.n}</div>
                  <div style={{color: "var(--ink-3)", fontSize: 12}}>{c.c}</div>
                </div>
              </div>
              <div style={{display: "flex", flexDirection: "column", gap: 4, fontSize: 12.5}}>
                <div className="mono" style={{color: "var(--ink-2)", display: "flex", gap: 6, alignItems: "center"}}><Icon name="phone" size={12}/> {c.tel}</div>
                <div className="mono" style={{color: "var(--ink-2)", display: "flex", gap: 6, alignItems: "center", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap"}}><Icon name="mail" size={12}/> {c.mail}</div>
              </div>
              <div style={{marginTop: 10}}>
                <span className="chip"><span className="dot"/> {c.tag}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ============ COLABORADORES (CSSI) ============
const COLLABS = [
  { n: "Carlos Ramírez Torres", p: "Ejecutivo Comercial", area: "Ventas CDMX", ant: "3 años 2 meses", asist: 98 },
  { n: "Mariana Solís López", p: "Coordinador de Marketing", area: "Marketing", ant: "5 años 7 meses", asist: 96 },
  { n: "Javier Ontiveros Peña", p: "Analista de Sistemas", area: "TI", ant: "2 años 1 mes", asist: 100 },
  { n: "Paulina Vega Ruiz", p: "Gerente de Finanzas", area: "Finanzas", ant: "7 años 3 meses", asist: 94 },
  { n: "Fernando Gil Herrera", p: "Supervisor Operativo", area: "Operaciones", ant: "1 año 8 meses", asist: 88 },
  { n: "Laura Espinosa Mora", p: "Líder de RH", area: "RH", ant: "4 años 11 meses", asist: 97 },
];

function CollaboratorsPage() {
  const initials = (n) => n.split(" ").slice(0,2).map(s => s[0]).join("");
  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Colaboradores</h1>
          <div className="sub">Directorio de personal, puestos, antigüedad e indicadores.</div>
        </div>
        <div className="actions">
          <button className="btn sm"><Icon name="file" size={14}/> Exportar</button>
          <button className="btn primary sm"><Icon name="plus" size={14}/> Alta de colaborador</button>
        </div>
      </div>

      <div style={{display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14}}>
        {COLLABS.map((c, i) => (
          <div key={i} className="card" style={{padding: 18}}>
            <div style={{display: "flex", gap: 14, alignItems: "center"}}>
              <div style={{width: 52, height: 52, borderRadius: "50%", background: "linear-gradient(135deg, oklch(0.92 0.04 265), oklch(0.76 0.08 265))", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 16, fontWeight: 600, color: "var(--brand-ink)"}}>{initials(c.n)}</div>
              <div style={{minWidth: 0, flex: 1}}>
                <div style={{fontWeight: 600, fontSize: 14, letterSpacing: "-0.01em"}}>{c.n}</div>
                <div style={{fontSize: 12.5, color: "var(--ink-3)"}}>{c.p}</div>
              </div>
            </div>
            <hr className="h-divider" style={{margin: "14px 0"}}/>
            <div style={{display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, fontSize: 12.5}}>
              <div>
                <div style={{color: "var(--ink-3)", fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em"}}>Área</div>
                <div style={{fontWeight: 500, marginTop: 2}}>{c.area}</div>
              </div>
              <div>
                <div style={{color: "var(--ink-3)", fontSize: 11, textTransform: "uppercase", letterSpacing: "0.08em"}}>Antigüedad</div>
                <div className="mono" style={{fontWeight: 500, marginTop: 2}}>{c.ant}</div>
              </div>
              <div style={{gridColumn: "1 / -1"}}>
                <div style={{display: "flex", justifyContent: "space-between", fontSize: 11, color: "var(--ink-3)", textTransform: "uppercase", letterSpacing: "0.08em"}}>
                  <span>Asistencia</span>
                  <span className="mono" style={{color: c.asist >= 95 ? "var(--success)" : "var(--ink-2)"}}>{c.asist}%</span>
                </div>
                <div style={{height: 4, background: "var(--hover)", borderRadius: 2, marginTop: 5, overflow: "hidden"}}>
                  <div style={{width: c.asist + "%", height: "100%", background: c.asist >= 95 ? "var(--success)" : "var(--brand)", borderRadius: 2}}/>
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ============ LOGS ============
const LOGS = [
  { t: "2026-04-24 14:32:18", u: "a.martinez@sisol.com.mx", act: "INICIO DE SESIÓN", info: "IP 187.190.44.12 · CDMX", sev: "info" },
  { t: "2026-04-24 14:28:02", u: "j.ontiveros@sisol.com.mx", act: "ACTUALIZAR INVENTARIO", info: "SKU LAP-00481 · condición → USADO", sev: "info" },
  { t: "2026-04-24 13:55:47", u: "p.vega@sisol.com.mx", act: "APROBAR INCIDENCIA", info: "Folio INC-00809 · HOME OFFICE 3d", sev: "success" },
  { t: "2026-04-24 12:14:09", u: "a.martinez@sisol.com.mx", act: "CAMBIO DE CONTRASEÑA", info: "Usuario: c.ramirez@sisol.com.mx", sev: "warn" },
  { t: "2026-04-24 11:02:33", u: "—", act: "INTENTO DE ACCESO FALLIDO", info: "correo@desconocido.com · 3er intento", sev: "danger" },
  { t: "2026-04-24 09:48:51", u: "l.cardenas@sisol.com.mx", act: "EXPORTAR REPORTE BI", info: "Ingresos abril · PDF", sev: "info" },
  { t: "2026-04-24 08:47:02", u: "a.martinez@sisol.com.mx", act: "CHECADOR · ENTRADA", info: "CDMX · Torre Corporativa", sev: "success" },
  { t: "2026-04-23 18:22:15", u: "javier.sys@sisol.com.mx", act: "RESPALDO PROGRAMADO", info: "DB sistemassi_prod · 4.2 GB", sev: "info" },
];

function LogsPage() {
  const [sev, setSev] = useStatePages("all");
  const rows = sev === "all" ? LOGS : LOGS.filter(l => l.sev === sev);
  const sevDot = { info: "var(--ink-3)", success: "var(--success)", warn: "oklch(0.72 0.14 75)", danger: "var(--danger)" };

  return (
    <div className="fade-in">
      <div className="page-head">
        <div>
          <h1>Logs del sistema</h1>
          <div className="sub">Auditoría de eventos, cambios y accesos.</div>
        </div>
        <div className="actions">
          <div className="toggle-group">
            {["all","info","success","warn","danger"].map(s => (
              <button key={s} className={sev === s ? "active" : ""} onClick={() => setSev(s)}>
                {s === "all" ? "Todos" : s === "info" ? "Info" : s === "success" ? "OK" : s === "warn" ? "Aviso" : "Error"}
              </button>
            ))}
          </div>
          <button className="btn sm"><Icon name="file" size={14}/> Descargar</button>
        </div>
      </div>

      <div className="card" style={{fontFamily: "var(--f-mono)", fontSize: 12}}>
        <div style={{display: "grid", gridTemplateColumns: "8px 170px 220px 1fr 1fr", borderBottom: "1px solid var(--line)", padding: "10px 14px", color: "var(--ink-3)", fontSize: 10.5, textTransform: "uppercase", letterSpacing: "0.1em", fontWeight: 600, fontFamily: "var(--f-sans)"}}>
          <span/>
          <span>Timestamp</span>
          <span>Usuario</span>
          <span>Acción</span>
          <span>Detalle</span>
        </div>
        {rows.map((l, i) => (
          <div key={i} style={{
            display: "grid", gridTemplateColumns: "8px 170px 220px 1fr 1fr",
            padding: "9px 14px", borderBottom: i < rows.length - 1 ? "1px solid var(--line-2)" : "none",
            alignItems: "center", transition: "background 120ms ease",
          }}
          onMouseEnter={e => e.currentTarget.style.background = "var(--hover)"}
          onMouseLeave={e => e.currentTarget.style.background = ""}>
            <span style={{width: 6, height: 6, borderRadius: "50%", background: sevDot[l.sev]}}/>
            <span style={{color: "var(--ink-2)"}}>{l.t}</span>
            <span style={{color: l.u === "—" ? "var(--ink-4)" : "var(--ink)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap"}}>{l.u}</span>
            <span style={{color: "var(--brand-ink)", fontWeight: 600, fontSize: 11}}>{l.act}</span>
            <span style={{color: "var(--ink-3)"}}>{l.info}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// Expose
window.SocialPage = SocialPage;
window.SignaturesPage = SignaturesPage;
window.ContactsPage = ContactsPage;
window.CollaboratorsPage = CollaboratorsPage;
window.LogsPage = LogsPage;
window.CalendarPage = CalendarPage;
window.IncidenciasPage = IncidenciasPage;
window.InventoryPage = InventoryPage;
window.AttendancePage = AttendancePage;
window.UsersPage = UsersPage;
window.BiPage = BiPage;
