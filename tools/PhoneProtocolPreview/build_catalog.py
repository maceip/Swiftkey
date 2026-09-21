"""Build a local catalog from actual Swift RenderNodes and the web renderer.

No authority connection, secrets, service mutations, or synthetic success flow.
"""
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
output = root / "artifacts" / "phone-ui"
resources = root / "SwiftKeyServer/Sources/SwiftKeyServer/Resources"
surfaces = json.loads((output / "surfaces.json").read_text())
assert len(surfaces) >= 20
source = (resources / "app.js").read_text()
start = source.index("  function number(")
end = source.index("  function capturePresentation(")
renderer = source[start:end]
# Use the exact shipped primitive renderer, supplying a fixture-only event host.
prefix = r'''(() => {
"use strict";
const root = document.getElementById("swift-root");
let controls = [], bindings = new Map();
const session = {busy:false}, dirty = new Map(), disclosures = new Map();
let selected = null;
function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = String(text);
  return node;
}
function callback(id) { return String(id); }
function eventFor(id, kind, value) { return {id:String(id),kind,value}; }
function collect(id, kind, value) { dirty.set(String(id), {id,kind,value}); }
async function submit(action) {
  document.getElementById("event").textContent = "Fixture only · " +
    (action ? (selected.actions[action.id] || "Presentation control") : "Draft updated") +
    ". No request sent; no phone or account changed.";
}
'''
suffix = r'''
const picker = document.getElementById("surface");
function show(item) {
  selected = item; controls = []; bindings.clear(); dirty.clear(); disclosures.clear();
  root.replaceChildren(render(item.tree));
  document.getElementById("surface-title").textContent = item.title;
  document.getElementById("event").textContent = "Synthetic public records · no authority connection.";
  window.history.replaceState(null, "", "#" + item.id);
}
fetch("surfaces.json", {cache:"no-store"}).then(r => {
  if (!r.ok) throw new Error("Unable to load Swift surfaces"); return r.json();
}).then(items => {
  for (const item of items) {
    const option = element("option", "", item.title); option.value = item.id; picker.append(option);
  }
  const initial = items.find(x => x.id === location.hash.slice(1)) || items[0];
  picker.value = initial.id; show(initial);
  picker.addEventListener("change", () => show(items.find(x => x.id === picker.value)));
  document.getElementById("previous").addEventListener("click", () => {
    picker.selectedIndex = Math.max(0, picker.selectedIndex - 1); picker.dispatchEvent(new Event("change"));
  });
  document.getElementById("next").addEventListener("click", () => {
    picker.selectedIndex = Math.min(items.length - 1, picker.selectedIndex + 1); picker.dispatchEvent(new Event("change"));
  });
  document.getElementById("width").addEventListener("change", e => {
    document.getElementById("device").style.maxWidth = e.target.value + "px";
  });
  document.getElementById("large").addEventListener("change", e => {
    root.style.zoom = e.target.checked ? "1.4" : "1";
  });
}).catch(error => { document.getElementById("event").textContent = error.message; throw error; });
})();
'''
(output / "catalog.js").write_text(prefix + renderer + suffix)
shutil.copyfile(resources / "style.css", output / "style.css")
(output / "fonts").mkdir(exist_ok=True)
for name in ("host-grotesk.woff2", "jetbrains-mono.woff2", "space-grotesk.woff2", "ibm-plex-mono.woff2"):
    shutil.copyfile(resources / name, output / "fonts" / name)
(output / "index.html").write_text('''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>SwiftKey · Phone protocol surfaces</title>
<link rel="icon" href="data:,"><link rel="stylesheet" href="style.css"><script src="catalog.js" defer></script>
<style>
header{width:100%;min-width:0;max-width:1100px;margin:auto;padding:32px 24px 24px}h1{font-size:32px;font-weight:560;letter-spacing:-.3px;margin:8px 0}
header p{color:var(--muted);max-width:760px}.tools{display:flex;flex-wrap:wrap;gap:12px;align-items:end}
.tools label{min-width:0;display:flex;flex-direction:column;gap:6px;font-size:13px}.tools select{width:100%;padding:10px;max-width:100%;background:var(--surface);color:var(--ink);border-radius:8px;border:1px solid var(--line)}
.tools button{min-height:44px;padding:10px 16px;border:1px solid var(--line);background:var(--surface);color:var(--ink);border-radius:8px}
.tools .check{flex-direction:row;align-items:center;min-height:44px}.tools input{width:20px;height:20px}
.preview{border-top:1px solid var(--line);padding:28px 8px 64px;background:var(--subtle)}
#device{max-width:440px;margin:auto;background:var(--canvas);border:1px solid var(--line);border-radius:16px;overflow:hidden;box-shadow:var(--shadow)}
#surface-title{max-width:800px;margin:0 auto 20px;text-align:center;font:12px var(--mono);color:var(--muted)}
#event{max-width:800px;margin:20px auto 0;padding:16px;background:var(--canvas);font:12px/1.7 var(--mono);overflow-wrap:anywhere}
@media(max-width:480px){header{padding:24px 16px}h1{font-size:30px}.tools label:first-child{width:100%}}
</style></head><body><header><p class="eyebrow">SWIFTKEY / COMPONENT CATALOG</p>
<h1>One ceremony. Every state.</h1><p>Shared Swift phone surfaces, rendered through the existing browser adapter.
These are synthetic fixtures. Buttons expose typed callbacks; they do not sign, pair, or create accounts.</p>
<div class="tools"><label>Protocol surface<select id="surface"></select></label>
<button id="previous" type="button">Previous</button><button id="next" type="button">Next</button>
<label>Viewport width<select id="width"><option value="440">440 px</option><option value="360">360 px</option><option value="320">320 px</option><option value="800">800 px</option></select></label>
<label class="check"><input id="large" type="checkbox">140% text/layout scale</label></div></header>
<main class="preview"><h2 id="surface-title"></h2><div id="device"><div id="swift-root" class="swift-root"></div></div>
<p id="event" role="status" aria-live="polite">Loading Swift surfaces…</p></main></body></html>''')
print(f"Built {len(surfaces)} Swift component surfaces in {output}")
