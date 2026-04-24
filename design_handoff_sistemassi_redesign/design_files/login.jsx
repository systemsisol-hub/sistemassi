/* global React, Icon */
const { useState: useStateLogin } = React;

function LoginScreen({ onLogin }) {
  const [email, setEmail] = useStateLogin("a.martinez@sisol.com.mx");
  const [pw, setPw] = useStateLogin("••••••••••");
  const [show, setShow] = useStateLogin(false);
  const [loading, setLoading] = useStateLogin(false);

  const submit = (e) => {
    e.preventDefault();
    setLoading(true);
    setTimeout(() => { setLoading(false); onLogin(); }, 900);
  };

  return (
    <div className="login-root fade-in">
      <div className="login-form-pane">
        <form className="login-form" onSubmit={submit}>
          <div className="logo">
            <div className="mark">S</div>
            <div>
              <div style={{fontSize: 14, fontWeight: 600, letterSpacing: "-0.01em"}}>Sistemassi</div>
              <div style={{fontSize: 11, color: "var(--ink-3)", textTransform: "uppercase", letterSpacing: "0.1em"}}>Sisol · Intranet</div>
            </div>
          </div>

          <div>
            <h1>Bienvenido de vuelta</h1>
            <p className="sub">Accede a la plataforma operativa de Sisol Soluciones Inmobiliarias.</p>
          </div>

          <div className="field">
            <label>Correo corporativo</label>
            <div className="input-wrap">
              <span className="adorn"><Icon name="mail" size={16}/></span>
              <input type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="nombre@sisol.com.mx"/>
            </div>
          </div>

          <div className="field">
            <div style={{display:"flex", justifyContent:"space-between", alignItems:"center"}}>
              <label>Contraseña</label>
              <a className="forgot" href="#">¿Olvidaste tu contraseña?</a>
            </div>
            <div className="input-wrap">
              <span className="adorn"><Icon name="key" size={16}/></span>
              <input type={show ? "text" : "password"} value={pw} onChange={e => setPw(e.target.value)}/>
              <button type="button" className="adorn adorn-r" onClick={() => setShow(!show)} style={{cursor:"pointer"}}>
                <Icon name={show ? "eyeOff" : "eye"} size={16}/>
              </button>
            </div>
          </div>

          <button type="submit" className="btn primary lg" disabled={loading} style={{width:"100%", marginTop: 6}}>
            {loading ? <><span className="spinner"/> Verificando…</> : <>Iniciar sesión <Icon name="arrow" size={15}/></>}
          </button>

          <div className="meta">
            <span>Acceso restringido a personal autorizado.</span>
            <span className="mono">v2.4.0</span>
          </div>
        </form>
      </div>

      <aside className="login-art">
        <div>
          <div className="tag">Sistema interno · Release 2026.Q2</div>
          <h2>Opera tu día desde un solo lugar <em>ordenado</em>.</h2>
        </div>

        <div style={{display:"flex", flexDirection:"column", gap: 20}}>
          <div className="modules">
            {["MI PERFIL","CALENDARIO","INCIDENCIAS","INVENTARIO","ASISTENCIA","FIRMAS","BI","USUARIOS","LOGS","CONTACTOS"].map(m => (
              <span className="mod-chip" key={m}>{m}</span>
            ))}
          </div>

          <div className="statgrid">
            <div className="cell">
              <div className="n">248</div>
              <div className="l">Colaboradores activos</div>
            </div>
            <div className="cell">
              <div className="n">12.4k</div>
              <div className="l">Eventos registrados</div>
            </div>
            <div className="cell">
              <div className="n">99.98%</div>
              <div className="l">Uptime 30 días</div>
            </div>
          </div>
        </div>
      </aside>
    </div>
  );
}

window.LoginScreen = LoginScreen;
