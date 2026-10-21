/*
 * web_page.h - built-in web interface for AcomControl
 *
 * Stored in flash (PROGMEM) and served with request->send_P(). v5.0 built a
 * ~9 KB String on every request to "/", which fragmented the heap.
 */

#ifndef ACOM_WEB_PAGE_H
#define ACOM_WEB_PAGE_H

#include <Arduino.h>

const char PAGE_INDEX[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AcomControl</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  :root{
    --bg:#0f1420;--panel:#182034;--panel2:#1f293f;--line:#2b3752;
    --text:#e8edf7;--dim:#8d9bb5;--accent:#4a9eff;--ok:#37d67a;
    --warn:#ffb020;--danger:#ff5c5c;--purple:#a97bff;
  }
  @media (prefers-color-scheme:light){
    :root{--bg:#f2f5fa;--panel:#fff;--panel2:#eef2f9;--line:#d8e0ee;
          --text:#131a26;--dim:#5d6b83}
  }
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
       background:var(--bg);color:var(--text);min-height:100vh;padding:16px;
       -webkit-font-smoothing:antialiased}
  .wrap{max-width:1040px;margin:0 auto}
  header{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:16px}
  h1{font-size:20px;font-weight:650;letter-spacing:-.01em}
  .sn{font-size:12px;color:var(--dim)}
  .spacer{flex:1}
  .pill{display:inline-flex;align-items:center;gap:7px;padding:6px 12px;
        border-radius:999px;font-size:12px;font-weight:600;background:var(--panel);
        border:1px solid var(--line)}
  .dot{width:9px;height:9px;border-radius:50%;background:var(--danger)}
  .pill.on .dot{background:var(--ok)}
  .pill.warn .dot{background:var(--warn)}

  /* TX banner: the single most important piece of state on the page */
  .txbar{display:flex;align-items:center;justify-content:center;gap:12px;
         padding:12px;border-radius:12px;font-size:16px;font-weight:750;
         letter-spacing:.16em;margin-bottom:16px;border:1px solid var(--line);
         background:var(--panel);color:var(--dim);transition:.15s}
  .txbar.tx{background:var(--danger);color:#fff;border-color:var(--danger);
            animation:pulse 1.1s ease-in-out infinite}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.72}}

  .grid{display:grid;gap:14px;margin-bottom:16px}
  .g3{grid-template-columns:repeat(3,1fr)}
  .g4{grid-template-columns:repeat(4,1fr)}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:16px}
  .card h2{font-size:12px;font-weight:600;color:var(--dim);text-transform:uppercase;
           letter-spacing:.06em;margin-bottom:12px}

  .gauge{text-align:center}
  .gauge svg{width:100%;max-width:190px;height:auto;display:block;margin:0 auto}
  .gv{font-size:30px;font-weight:750;font-variant-numeric:tabular-nums}
  .gu{font-size:12px;color:var(--dim)}
  .peak{font-size:11px;color:var(--dim);margin-top:2px;font-variant-numeric:tabular-nums}
  .spark{width:100%;height:34px;display:block;margin-top:8px}

  .tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
  .tile{background:var(--panel2);border-radius:9px;padding:10px}
  .tile .k{font-size:10px;color:var(--dim);text-transform:uppercase;letter-spacing:.04em}
  .tile .v{font-size:15px;font-weight:650;margin-top:3px;font-variant-numeric:tabular-nums}

  button{font:inherit;font-size:13px;font-weight:600;padding:10px 16px;border:1px solid var(--line);
         border-radius:9px;cursor:pointer;background:var(--panel2);color:var(--text);transition:.12s}
  button:hover:not(:disabled){border-color:var(--accent)}
  button:disabled{opacity:.4;cursor:not-allowed}
  button.on{background:var(--accent);border-color:var(--accent);color:#fff}
  button.danger{border-color:var(--danger);color:var(--danger)}
  button.danger:hover:not(:disabled){background:var(--danger);color:#fff}
  .row{display:flex;gap:9px;flex-wrap:wrap;align-items:center}
  .bands{display:grid;grid-template-columns:repeat(auto-fit,minmax(74px,1fr));gap:8px}
  .bands button.on{background:var(--purple);border-color:var(--purple);color:#fff}

  label{font-size:12px;color:var(--dim);display:block;margin-bottom:5px}
  input,select{font:inherit;font-size:13px;width:100%;padding:9px 11px;border-radius:8px;
               border:1px solid var(--line);background:var(--panel2);color:var(--text)}
  .field{margin-bottom:11px}
  .two{display:grid;grid-template-columns:1fr 1fr;gap:11px}

  .fault{display:flex;gap:10px;align-items:flex-start;padding:10px 12px;border-radius:9px;
         background:rgba(255,92,92,.12);border:1px solid rgba(255,92,92,.35);margin-bottom:8px}
  .fault .fc{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:700;color:var(--danger)}
  .fault .ft{font-size:12px;color:var(--dim)}
  .hidden{display:none !important}
  .note{font-size:11px;color:var(--dim);line-height:1.5;margin-top:8px}
  .toast{position:fixed;left:50%;bottom:22px;transform:translateX(-50%);padding:11px 20px;
         border-radius:9px;background:var(--panel);border:1px solid var(--line);
         font-size:13px;font-weight:600;opacity:0;pointer-events:none;transition:.2s;z-index:50}
  .toast.show{opacity:1}
  .toast.err{border-color:var(--danger);color:var(--danger)}
  @media (max-width:860px){.g3,.g4{grid-template-columns:repeat(2,1fr)}.tiles{grid-template-columns:repeat(2,1fr)}}
  @media (max-width:520px){.g3,.g4{grid-template-columns:1fr}.two{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="wrap">

  <header>
    <h1>AcomControl</h1>
    <span class="sn" id="sn"></span>
    <span class="spacer"></span>
    <span class="pill" id="ampPill"><span class="dot"></span><span id="ampTxt">No amplifier</span></span>
    <span class="pill" id="wsPill"><span class="dot"></span><span id="wsTxt">Offline</span></span>
  </header>

  <div class="txbar" id="txbar">RECEIVE</div>

  <div class="grid g3">
    <div class="card gauge">
      <h2>Forward Power</h2>
      <svg viewBox="0 0 200 118" role="img" aria-label="Forward power gauge">
        <path d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="var(--panel2)" stroke-width="15" stroke-linecap="round"/>
        <path id="fwdArc" d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="var(--accent)" stroke-width="15"
              stroke-linecap="round" stroke-dasharray="251.3" stroke-dashoffset="251.3"/>
        <line id="fwdPeak" x1="100" y1="20" x2="100" y2="34" stroke="var(--warn)" stroke-width="3"
              stroke-linecap="round" transform="rotate(-90 100 108)"/>
      </svg>
      <div><span class="gv" id="fwdV">0</span> <span class="gu">W</span></div>
      <div class="peak">peak <span id="fwdPk">0</span> W &middot; avg <span id="fwdAvg">0</span> W</div>
      <svg class="spark" id="fwdSpark" viewBox="0 0 200 34" preserveAspectRatio="none" aria-hidden="true"></svg>
    </div>

    <div class="card gauge">
      <h2>SWR</h2>
      <svg viewBox="0 0 200 118" role="img" aria-label="SWR gauge">
        <path d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="var(--panel2)" stroke-width="15" stroke-linecap="round"/>
        <path d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="rgba(255,92,92,.28)" stroke-width="15"
              stroke-dasharray="251.3" stroke-dashoffset="0" pathLength="251.3"
              style="stroke-dasharray:41.9 251.3;stroke-dashoffset:-209.4"/>
        <path id="swrArc" d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="var(--ok)" stroke-width="15"
              stroke-linecap="round" stroke-dasharray="251.3" stroke-dashoffset="251.3"/>
        <line id="swrPeak" x1="100" y1="20" x2="100" y2="34" stroke="var(--warn)" stroke-width="3"
              stroke-linecap="round" transform="rotate(-90 100 108)"/>
      </svg>
      <div><span class="gv" id="swrV">1.00</span> <span class="gu">:1</span></div>
      <div class="peak">peak <span id="swrPk">1.00</span>:1</div>
      <svg class="spark" id="swrSpark" viewBox="0 0 200 34" preserveAspectRatio="none" aria-hidden="true"></svg>
    </div>

    <div class="card gauge">
      <h2>PA Temperature</h2>
      <svg viewBox="0 0 200 118" role="img" aria-label="Temperature gauge">
        <path d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="var(--panel2)" stroke-width="15" stroke-linecap="round"/>
        <path id="tmpArc" d="M20 108 A80 80 0 0 1 180 108" fill="none" stroke="var(--accent)" stroke-width="15"
              stroke-linecap="round" stroke-dasharray="251.3" stroke-dashoffset="251.3"/>
        <line id="tmpPeak" x1="100" y1="20" x2="100" y2="34" stroke="var(--warn)" stroke-width="3"
              stroke-linecap="round" transform="rotate(-90 100 108)"/>
      </svg>
      <div><span class="gv" id="tmpV">0</span> <span class="gu">&deg;C</span></div>
      <div class="peak">peak <span id="tmpPk">0</span> &deg;C</div>
      <svg class="spark" id="tmpSpark" viewBox="0 0 200 34" preserveAspectRatio="none" aria-hidden="true"></svg>
    </div>
  </div>

  <div class="card" style="margin-bottom:16px">
    <h2>Telemetry
      <button id="btnResetPeaks" style="float:right;font-size:11px;padding:4px 10px;margin-top:-4px">
        Reset peaks</button>
    </h2>
    <div class="tiles">
      <div class="tile"><div class="k">Mode</div><div class="v" id="tMode">---</div></div>
      <div class="tile"><div class="k">Band</div><div class="v" id="tBand">---</div></div>
      <div class="tile"><div class="k">Frequency</div><div class="v" id="tFreq">---</div></div>
      <div class="tile"><div class="k">Antenna</div><div class="v" id="tAnt">---</div></div>
      <div class="tile"><div class="k">Reflected</div><div class="v" id="tRef">0 W</div></div>
      <div class="tile"><div class="k">Drive Power</div><div class="v" id="tIn">0.0 W</div></div>
      <div class="tile"><div class="k">Drain Current</div><div class="v" id="tCur">0.00 A</div></div>
      <div class="tile"><div class="k">HV Supply</div><div class="v" id="tHv">0.0 V</div></div>
      <div class="tile"><div class="k">Fan</div><div class="v" id="tFan">0%</div></div>
      <div class="tile"><div class="k">Dissipation</div><div class="v" id="tDis">0.0 W</div></div>
      <div class="tile"><div class="k">DC Input</div><div class="v" id="tPdc">0.0 W</div></div>
      <div class="tile"><div class="k">Messages</div><div class="v" id="tMsg">0</div></div>
    </div>
  </div>

  <div class="card hidden" id="faultCard" style="margin-bottom:16px">
    <h2>Active Faults</h2>
    <div id="faultList"></div>
    <div class="row"><button class="danger" id="btnClearErr">Clear Soft Faults</button></div>
    <p class="note">Fault names and severities come from section 3.4.1 of the ACOM RS-232
      specification, served by the controller at <code>/api/faults</code>. Only soft faults can
      be cleared from here; a hard fault has already shut the supply down.</p>
  </div>

  <div class="grid g4" style="grid-template-columns:1fr 1fr">
    <div class="card">
      <h2>Mode</h2>
      <div class="row">
        <button id="mStb" data-mode="5">Standby</button>
        <button id="mOpr" data-mode="6">Operate</button>
        <button class="danger" id="mOff">Power Off</button>
      </div>
      <p class="note">Standby and Operate always apply &mdash; dropping to standby mid-carrier is
        the fastest way to stop. Power Off asks for confirmation, and says so plainly if the
        amplifier is transmitting.</p>
    </div>

    <div class="card">
      <h2>Antenna</h2>
      <div class="row">
        <select id="antSel" aria-label="Antenna selection">
          <option value="1">Antenna 1</option><option value="2">Antenna 2</option>
          <option value="3">Antenna 3</option><option value="4">Antenna 4</option>
          <option value="5">Antenna 5</option><option value="6">Antenna 6</option>
          <option value="7">Antenna 7</option><option value="8">Antenna 8</option>
          <option value="9">Antenna 9</option><option value="10">Antenna 10</option>
        </select>
      </div>
      <p class="note">Band buttons keep the antenna shown here instead of forcing antenna 1.</p>
    </div>
  </div>

  <div class="card" style="margin:16px 0">
    <h2>Band</h2>
    <div class="bands" id="bandGrid"></div>
  </div>

  <div class="grid g4" style="grid-template-columns:1fr 1fr">
    <div class="card">
      <h2>Rig Integration</h2>
      <div class="row" style="margin-bottom:10px">
        <label style="margin:0;display:flex;align-items:center;gap:8px;cursor:pointer">
          <input type="checkbox" id="cfgFollow" style="width:auto">
          <span>Follow transceiver frequency (auto band change)</span>
        </label>
      </div>
      <div class="field">
        <label for="freqIn">Report frequency from rig control (kHz)</label>
        <div class="row">
          <input id="freqIn" type="number" min="1" max="65535" placeholder="14250" style="flex:1">
          <button id="btnFreq">Send</button>
        </div>
      </div>
      <p class="note">Band changes are never made while the amplifier is transmitting.</p>
    </div>

    <div class="card">
      <h2>Session Log</h2>
      <div class="row" style="margin-bottom:10px">
        <label style="margin:0;display:flex;align-items:center;gap:8px;cursor:pointer">
          <input type="checkbox" id="cfgLog" style="width:auto"><span>Log telemetry to flash</span>
        </label>
      </div>
      <div class="row">
        <button id="btnDownload">Download CSV</button>
        <button id="btnClearHist" class="danger">Clear History</button>
      </div>
      <p class="note" id="logNote"></p>
    </div>
  </div>

  <div class="grid g4" style="grid-template-columns:1fr 1fr;margin-top:16px">
    <div class="card">
      <h2>Network</h2>
      <div class="field"><label for="wSsid">WiFi SSID</label><input id="wSsid" placeholder="Network name"></div>
      <div class="field"><label for="wPass">WiFi password (blank for open network)</label>
        <input id="wPass" type="password" placeholder="Password"></div>
      <div class="field"><label for="hName">mDNS hostname</label><input id="hName" placeholder="acomcontrol"></div>
      <div class="row">
        <button id="btnWifi">Save WiFi &amp; Reboot</button>
        <button id="btnHost">Save Hostname</button>
      </div>
    </div>

    <div class="card">
      <h2>Access</h2>
      <div id="secWarn" class="hidden"></div>
      <div class="two">
        <div class="field"><label for="apiUser">API user</label>
          <input id="apiUser" placeholder="acom"></div>
        <div class="field"><label for="apiPass">API password (blank disables)</label>
          <input id="apiPass" type="password" placeholder="Password"></div>
      </div>
      <div class="field"><label for="apPass">Access point passphrase (8+ chars, blank reopens it)</label>
        <input id="apPass" placeholder="Passphrase"></div>
      <div class="row"><button id="btnAccess">Save Access &amp; Reboot</button></div>
      <p class="note">The passphrase shown is the one in use. Write it down before changing the
        network settings &mdash; it is how you reach the controller if it cannot join your WiFi.</p>
    </div>

    <div class="card">
      <h2>Firmware</h2>
      <div class="field"><label for="otaFile">Upload firmware.bin</label><input id="otaFile" type="file" accept=".bin"></div>
      <div class="row"><button id="btnOta">Flash Firmware</button></div>
      <p class="note" id="sysNote"></p>
    </div>
  </div>

  <p class="note" style="text-align:center;margin:22px 0 8px" id="footer"></p>
</div>

<div class="toast" id="toast"></div>

<script>
'use strict';
(function(){
  var ws=null, reconnectTimer=null, state={}, cfg={}, faultTable=null;
  var pollTimer=null, wsFailures=0;
  var MAX_FWD=600, MAX_SWR=3, MAX_TMP=90, ARC=251.3;
  // One band numbering, shared with the amplifier. 60m uses the 40m low-pass
  // filter, so band 3 covers both; v6.0 labelled band 2 "80/60m".
  var BANDS=[[1,'160m'],[2,'80m'],[3,'40/60m'],[4,'30m'],[5,'20m'],[6,'17m'],
             [7,'15m'],[8,'12m'],[9,'10m'],[10,'6m']];
  var hist={fwd:[],swr:[],tmp:[]}, HIST_MAX=120;
  var peak={fwd:0,swr:1,tmp:0}, fwdSum=0, fwdN=0;
  var antTouched=false;

  function $(id){return document.getElementById(id);}
  function toast(msg,isErr){
    var t=$('toast'); t.textContent=msg;
    t.className='toast show'+(isErr?' err':'');
    clearTimeout(t._h); t._h=setTimeout(function(){t.className='toast';},2600);
  }

  // ---- band buttons ----
  var grid=$('bandGrid');
  BANDS.forEach(function(b){
    var el=document.createElement('button');
    el.textContent=b[1]; el.dataset.band=b[0];
    el.setAttribute('aria-label','Select '+b[1]+' band');
    el.onclick=function(){
      // The controller refuses band changes while transmitting unless we say
      // we have asked. Switching the low-pass filter under RF is the
      // hot-switching case the amplifier's own protection watches for.
      var force=false;
      if(state.isTx){
        if(!confirm('The amplifier is transmitting. Switching the low-pass filter '+
                    'under RF risks hot-switching the antenna relays. Change band anyway?')) return;
        force=true;
      }
      send({cmd:'setBand',band:b[0],antenna:parseInt($('antSel').value,10)||1,force:force});
    };
    grid.appendChild(el);
  });

  // ---- transport ----
  // The WebSocket is the fast path, but a browser cannot set an Authorization
  // header on a WebSocket handshake: it can only reuse credentials it has
  // already cached for this origin, which is not something to rely on. So if
  // the socket will not come up, fall back to polling the REST API, which
  // carries cached Basic credentials reliably. Everything on the page works in
  // either mode.
  function applyState(d){
    if(d.success===false){ toast(d.error||'Command rejected',true); return; }
    state=d; render(d);
    if(!faultTable && (d.errorCode || (d.errors&&d.errors.length))) loadFaultTable();
  }

  function startPolling(){
    if(pollTimer) return;
    setPill('wsPill','wsTxt',true,'Polled');
    var tick=function(){
      fetch('/api/status').then(function(r){return r.json();}).then(function(j){
        if(j && j.success && j.data) applyState(j.data);
      }).catch(function(){ setPill('wsPill','wsTxt',false,'Offline'); });
    };
    tick();
    pollTimer=setInterval(tick,500);
  }
  function stopPolling(){
    if(pollTimer){ clearInterval(pollTimer); pollTimer=null; }
  }

  function connect(){
    try{ ws=new WebSocket('ws://'+location.host+'/ws'); }
    catch(e){ startPolling(); return; }

    ws.onopen=function(){
      wsFailures=0; stopPolling();
      setPill('wsPill','wsTxt',true,'Live');
      clearTimeout(reconnectTimer);
    };
    ws.onclose=function(){
      wsFailures++;
      if(wsFailures>=2){
        // Two failures in a row: assume the socket is not going to work here
        // and keep the page alive over REST instead.
        startPolling();
      } else {
        setPill('wsPill','wsTxt',false,'Offline');
      }
      clearTimeout(reconnectTimer);
      reconnectTimer=setTimeout(connect, wsFailures>=2?30000:2000);
    };
    ws.onerror=function(){};
    ws.onmessage=function(e){
      var d; try{ d=JSON.parse(e.data);}catch(err){ return; }
      applyState(d);
    };
  }

  function send(o){
    if(ws && ws.readyState===WebSocket.OPEN){ ws.send(JSON.stringify(o)); return true; }
    // Same command set, over REST.
    fetch('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},
                          body:JSON.stringify(o)})
      .then(function(r){return r.json();})
      .then(function(j){ if(!j.success) toast(j.error||'Command rejected',true); })
      .catch(function(){ toast('Not connected',true); });
    return true;
  }
  function setPill(pid,tid,on,txt){
    $(pid).className='pill'+(on?' on':''); $(tid).textContent=txt;
  }

  // ---- rendering ----
  function arc(id,frac,color){
    frac=Math.max(0,Math.min(1,frac));
    var el=$(id);
    el.style.strokeDashoffset=(ARC*(1-frac)).toFixed(1);
    if(color) el.style.stroke=color;
  }
  function needle(id,frac){
    frac=Math.max(0,Math.min(1,frac));
    $(id).setAttribute('transform','rotate('+(-90+frac*180).toFixed(1)+' 100 108)');
  }
  function push(arr,v){ arr.push(v); if(arr.length>HIST_MAX) arr.shift(); }
  function sparkline(id,arr,max,color){
    var el=$(id);
    if(arr.length<2){ el.innerHTML=''; return; }
    var step=200/(HIST_MAX-1), pts='';
    for(var i=0;i<arr.length;i++){
      var x=(i*step).toFixed(1);
      var y=(32-Math.max(0,Math.min(1,arr[i]/max))*30).toFixed(1);
      pts+=x+','+y+' ';
    }
    el.innerHTML='<polyline points="'+pts+'" fill="none" stroke="'+color+
                 '" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"/>';
  }
  function fmtFreq(k){
    if(!k) return '---';
    return (k/1000).toFixed(3)+' MHz';
  }

  function render(d){
    setPill('ampPill','ampTxt',!!d.connected,d.connected?'Amplifier online':'No amplifier');
    $('sn').textContent=(d.serialNumber && d.serialNumber!=='Unknown')?('S/N '+d.serialNumber):'';

    var bar=$('txbar');
    bar.className='txbar'+(d.isTx?' tx':'');
    bar.textContent=d.isTx?'TRANSMITTING':'RECEIVE';

    var fwd=d.forwardPower||0;
    var swr=(d.swr||100)/100;
    var tmp=(d.temperature||273)-273;

    if(d.isTx && fwd>0){ fwdSum+=fwd; fwdN++; }
    if(fwd>peak.fwd) peak.fwd=fwd;
    if(d.isTx && swr>peak.swr) peak.swr=swr;
    if(tmp>peak.tmp) peak.tmp=tmp;

    arc('fwdArc',fwd/MAX_FWD,'var(--accent)');
    needle('fwdPeak',peak.fwd/MAX_FWD);
    $('fwdV').textContent=Math.round(fwd);
    $('fwdPk').textContent=Math.round(peak.fwd);
    $('fwdAvg').textContent=fwdN?Math.round(fwdSum/fwdN):0;

    arc('swrArc',(swr-1)/(MAX_SWR-1),swr>2.5?'var(--danger)':(swr>2?'var(--warn)':'var(--ok)'));
    needle('swrPeak',(peak.swr-1)/(MAX_SWR-1));
    $('swrV').textContent=swr.toFixed(2);
    $('swrPk').textContent=peak.swr.toFixed(2);

    arc('tmpArc',tmp/MAX_TMP,tmp>70?'var(--danger)':(tmp>60?'var(--warn)':'var(--accent)'));
    needle('tmpPeak',peak.tmp/MAX_TMP);
    $('tmpV').textContent=Math.round(tmp);
    $('tmpPk').textContent=Math.round(peak.tmp);

    push(hist.fwd,fwd); push(hist.swr,Math.max(0,swr-1)); push(hist.tmp,tmp);
    sparkline('fwdSpark',hist.fwd,MAX_FWD,'var(--accent)');
    sparkline('swrSpark',hist.swr,MAX_SWR-1,'var(--ok)');
    sparkline('tmpSpark',hist.tmp,MAX_TMP,'var(--warn)');

    $('tMode').textContent=d.mode||'---';
    $('tBand').textContent=d.band||'---';
    $('tFreq').textContent=fmtFreq(d.frequency);
    $('tAnt').textContent=d.antenna?('Antenna '+d.antenna):'---';
    $('tRef').textContent=Math.round(d.reflectedPower||0)+' W';
    $('tIn').textContent=((d.inputPower||0)/10).toFixed(1)+' W';
    $('tCur').textContent=((d.current||0)/1000).toFixed(2)+' A';
    $('tHv').textContent=((d.hvVoltage||0)/10).toFixed(1)+' V';
    // The amplifier's fan level runs 0..4 (byte 69), not 0..15.
    $('tFan').textContent=(d.fanSpeed||0)+'% (lvl '+(d.fanLevel||0)+'/'+(d.fanLevelMax||4)+')';
    $('tDis').textContent=((d.disPower||0)/10).toFixed(1)+' W';
    $('tPdc').textContent=((d.pdcPower||0)/10).toFixed(1)+' W';
    $('tMsg').textContent=d.msgCount||0;

    if(!antTouched && d.antenna>=1 && d.antenna<=10) $('antSel').value=String(d.antenna);

    var live=!!d.connected;
    document.querySelectorAll('#bandGrid button').forEach(function(b){
      b.className=(parseInt(b.dataset.band,10)===d.bandCode)?'on':'';
      b.disabled=!live;
    });
    $('mStb').className=(d.modeCode&0xF0)===0x50?'on':'';
    $('mOpr').className=(d.modeCode&0xF0)===0x60||(d.modeCode&0xF0)===0x70?'on':'';
    $('mStb').disabled=$('mOpr').disabled=$('mOff').disabled=!live;

    renderFaults(d);
  }

  // Fault text comes from the controller, which holds the table out of section
  // 3.4.1 of the protocol document. v6.0 had no table and inferred a "likely
  // cause" from whichever telemetry threshold happened to be exceeded.
  function esc(s){
    return String(s).replace(/[&<>"]/g,function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];
    });
  }
  function hex2(c){ return '0x'+('0'+c.toString(16).toUpperCase()).slice(-2); }
  function faultInfo(code){
    return (faultTable && faultTable[String(code)]) || null;
  }
  function sevLabel(sev){
    if(sev==='hard') return 'Hard fault';
    if(sev==='soft') return 'Soft fault';
    return 'Warning';
  }
  function faultRow(code,info,severity,extra){
    var name=info?info.text:'Unnamed in the specification';
    var sev=severity||(info?info.severity:'warning');
    return '<div class="fault"><span class="fc">'+hex2(code)+'</span><div>'+
           '<div><strong>'+esc(name)+'</strong> &middot; '+sevLabel(sev)+'</div>'+
           '<div class="ft">'+esc(extra||'')+'</div></div></div>';
  }
  function renderFaults(d){
    var errs=Array.isArray(d.errors)?d.errors:[];
    var card=$('faultCard');
    if(!errs.length && !d.errorCode){ card.className='card hidden'; return; }
    card.className='card';

    var html='';
    if(d.errorCode){
      // The amplifier states the severity of the live code itself through
      // telemetry byte 70, so there is nothing to guess here.
      html+=faultRow(d.errorCode, faultInfo(d.errorCode), d.errorSeverity,
                     'Shown on the amplifier\'s screen'+
                     (d.errorParam?(' · parameter '+d.errorParam):''));
    }
    errs.forEach(function(c){
      if(c===d.errorCode) return;
      html+=faultRow(c, faultInfo(c), null, 'Active in the amplifier\'s fault log');
    });
    $('faultList').innerHTML=html;
  }

  // ---- controls ----
  // Standby and Operate are always allowed: dropping to standby mid-carrier is
  // the panic button, not a hazard.
  $('mStb').onclick=function(){ send({cmd:'setMode',mode:5}); };
  $('mOpr').onclick=function(){ send({cmd:'setMode',mode:6}); };
  $('mOff').onclick=function(){
    var msg=state.isTx
      ? 'The amplifier is TRANSMITTING. Cut its power supply anyway?'
      : 'Power off the amplifier? You cannot switch it back on from here.';
    if(confirm(msg)) send({cmd:'setMode',mode:10,force:!!state.isTx});
  };
  $('btnClearErr').onclick=function(){ send({cmd:'clearErrors'}); toast('Clear requested'); };
  $('antSel').onchange=function(){
    antTouched=true;
    if(!state.bandCode) return;
    var force=false;
    if(state.isTx){
      if(!confirm('The amplifier is transmitting. Switch the antenna relay anyway?')){
        if(state.antenna) this.value=String(state.antenna);
        return;
      }
      force=true;
    }
    send({cmd:'setAntenna',antenna:parseInt(this.value,10),band:state.bandCode,force:force});
  };
  $('btnFreq').onclick=function(){
    var f=parseInt($('freqIn').value,10);
    if(!f){ toast('Enter a frequency in kHz',true); return; }
    post('/api/frequency',{frequency:f},'Frequency reported');
  };

  // ---- config ----
  // The fault table never changes while the firmware is running, so fetch it
  // once and keep it.
  function loadFaultTable(){
    if(faultTable) return;
    fetch('/api/faults').then(function(r){return r.json();}).then(function(j){
      if(j.success && j.data && j.data.codes){
        faultTable=j.data.codes;
        if(state.connected) renderFaults(state);
      }
    }).catch(function(){});
  }

  function loadConfig(){
    fetch('/api/config').then(function(r){return r.json();}).then(function(j){
      if(!j.success) return;
      cfg=j.data;
      $('cfgFollow').checked=!!cfg.autoBandFollow;
      $('cfgLog').checked=!!cfg.logging;
      $('hName').value=cfg.hostname||'';
      // wifiSSID is the network the controller is CONFIGURED to join. v6.0
      // reported the access point's own name here in AP mode, so this field
      // offered to make the controller join itself.
      if(cfg.wifiSSID) $('wSsid').value=cfg.wifiSSID;
      renderSecurity(cfg);
    }).catch(function(){});

    fetch('/api/system').then(function(r){return r.json();}).then(function(j){
      if(!j.success) return;
      var s=j.data;
      $('sysNote').textContent='Firmware v'+s.firmwareVersion+' on '+s.chipModel+
        ' rev '+s.chipRevision+' · '+Math.round(s.freeHeap/1024)+' KB heap free';
      $('logNote').textContent=s.historyCount+' of '+s.historyCapacity+
        ' samples buffered · '+Math.round((s.logBytes||0)/1024)+' KB on flash';
      $('footer').textContent='AcomControl v'+s.firmwareVersion+' · '+s.wifiMode+
        ' · '+s.ipAddress+' · http://'+s.hostname+'.local'+
        (s.telemetryEnabled?' · telemetry streaming':' · telemetry polled');
    }).catch(function(){});
  }

  function renderSecurity(c){
    var warn=[];
    if(c.apOpen && c.apMode) warn.push('the access point has no passphrase');
    if(!c.authEnabled) warn.push('the API has no password');
    var el=$('secWarn');
    if(warn.length){
      el.className='fault';
      el.innerHTML='<span class="fc">!</span><div><div><strong>This controller is '+
        'unprotected</strong></div><div class="ft">Anyone who can reach it can change bands '+
        'or flash firmware, because '+esc(warn.join(' and '))+'.</div></div>';
    } else {
      el.className='hidden';
      el.innerHTML='';
    }
    if(c.apPassword) $('apPass').value=c.apPassword;
    $('apiUser').value=c.apiUser||'acom';
  }
  function post(url,body,okMsg){
    return fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},
                      body:JSON.stringify(body)})
      .then(function(r){return r.json();})
      .then(function(j){
        if(j.success) toast(okMsg); else toast(j.error||'Request failed',true);
        return j;
      })
      .catch(function(){ toast('Request failed',true); });
  }
  $('cfgFollow').onchange=function(){
    post('/api/config',{autoBandFollow:this.checked},
         this.checked?'Band follow enabled':'Band follow disabled');
  };
  $('cfgLog').onchange=function(){
    post('/api/config',{logging:this.checked},this.checked?'Logging enabled':'Logging disabled');
  };
  $('btnHost').onclick=function(){
    var h=$('hName').value.trim();
    if(!h){ toast('Enter a hostname',true); return; }
    post('/api/config',{hostname:h},'Hostname saved, rebooting');
  };
  $('btnAccess').onclick=function(){
    var ap=$('apPass').value, pw=$('apiPass').value, user=$('apiUser').value.trim();
    if(ap.length>0 && ap.length<8){ toast('A WPA2 passphrase needs 8+ characters',true); return; }
    if(ap.length===0 && !confirm('Leave the access point OPEN? Anyone in range will be able '+
                                 'to control the amplifier.')) return;
    var body={apPassword:ap,apiPassword:pw};
    if(user) body.apiUser=user;
    post('/api/config',body,'Access settings saved, rebooting');
  };
  // v6.0 accumulated peaks and the transmit average for the life of the page
  // with no way to clear them.
  $('btnResetPeaks').onclick=function(){
    peak={fwd:0,swr:1,tmp:0}; fwdSum=0; fwdN=0;
    hist={fwd:[],swr:[],tmp:[]};
    if(state.connected) render(state);
    toast('Peaks reset');
  };
  $('btnWifi').onclick=function(){
    var s=$('wSsid').value.trim();
    if(!s){ toast('Enter a WiFi SSID',true); return; }
    post('/api/wifi',{ssid:s,password:$('wPass').value},'WiFi saved, rebooting');
  };
  $('btnDownload').onclick=function(){ window.location='/api/history/download'; };
  $('btnClearHist').onclick=function(){
    if(confirm('Delete the stored session log and telemetry history?'))
      post('/api/history/clear',{},'History cleared').then(loadConfig);
  };
  $('btnOta').onclick=function(){
    var f=$('otaFile').files[0];
    if(!f){ toast('Choose a firmware .bin file',true); return; }
    if(!confirm('Flash '+f.name+' ('+Math.round(f.size/1024)+' KB)? The controller will reboot.')) return;
    var fd=new FormData(); fd.append('firmware',f,f.name);
    toast('Uploading firmware...');
    fetch('/api/ota',{method:'POST',body:fd})
      .then(function(r){return r.json();})
      .then(function(j){ toast(j.success?'Firmware flashed, rebooting':(j.error||'Update failed'),!j.success); })
      .catch(function(){ toast('Upload failed',true); });
  };

  // The REST API is reachable whether or not the WebSocket is. v6.0 only
  // called loadConfig() from ws.onopen, so a page whose socket could not
  // connect showed empty settings fields and a blank footer for ever.
  loadConfig();
  loadFaultTable();
  setInterval(loadConfig, 30000);
  connect();
})();
</script>
</body>
</html>
)rawliteral";

#endif  // ACOM_WEB_PAGE_H
