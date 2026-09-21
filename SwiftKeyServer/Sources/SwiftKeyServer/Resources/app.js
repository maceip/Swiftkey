(() => {
  "use strict";

  // Platform adapter only: Swift owns view composition, validation and actions.
  const $ = (id) => document.getElementById(id);
  const root = $("swift-root");
  const endpoint = "/v1/admin/ui/sessions";
  const session = { token: "", id: null, revision: null, generation: 0, busy: false, interrupted: false };
  const pending = new Set();
  const dirty = new Map();
  const disclosures = new Map();
  let controls = [];
  let bindings = new Map();

  function element(tag, className, text) {
    const result = document.createElement(tag);
    if (className) result.className = className;
    if (text !== undefined) result.textContent = String(text);
    return result;
  }
  function message(text, error = false) {
    $("notice").textContent = text;
    $("notice").className = `notice${error ? " error" : ""}`;
    $("notice").hidden = !text;
  }
  function shell() {
    const connected = Boolean(session.id);
    document.body.dataset.connection = session.interrupted ? "interrupted" : connected ? "connected" : "disconnected";
    $("connection-panel").hidden = connected;
    $("admin-token").disabled = session.busy;
    $("connect-button").disabled = session.busy;
    $("connect-button").textContent = session.busy ? "Connecting…" : "Connect";
    $("disconnect-button").hidden = !session.token;
    $("reconnect-button").hidden = !session.interrupted || !session.token;
    $("reconnect-button").disabled = session.busy;
    $("connection-status").textContent = session.interrupted ? "Connection interrupted" : session.busy ? "Updating…" : connected ? "Connected" : "Disconnected";
    root.setAttribute("aria-busy", String(session.busy));
    for (const item of controls) item.node.disabled = item.disabled || session.busy || session.interrupted;
  }
  class RequestError extends Error {
    constructor(text, status = 0, code = "") { super(text); this.status = status; this.code = code; }
  }
  async function request(path, method, body) {
    const generation = session.generation;
    const controller = new AbortController();
    pending.add(controller);
    try {
      const response = await fetch(path, {
        method, signal: controller.signal, cache: "no-store", credentials: "omit", redirect: "error",
        headers: { Authorization: `Bearer ${session.token}`, Accept: "application/json", ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      if (generation !== session.generation) throw new DOMException("Disconnected", "AbortError");
      if (response.status === 204) return null;
      let value;
      try { value = await response.json(); }
      catch { throw new RequestError(`The authority returned an invalid response (${response.status}).`, response.status); }
      if (generation !== session.generation) throw new DOMException("Disconnected", "AbortError");
      if (!response.ok) throw new RequestError(typeof value.error === "string" ? value.error : `Request failed (${response.status}).`, response.status, value.code);
      return value;
    } catch (error) {
      if (error.name === "AbortError" || error instanceof RequestError) throw error;
      throw new RequestError("The authority could not be reached. The last action was not confirmed. Reconnect to load its current state.");
    } finally { pending.delete(controller); }
  }
  function fail(error) {
    if (error.name === "AbortError") return;
    if (error.code === "unauthorized" || error.status === 401) {
      disconnect();
      message("Admin authorization was refused. Connect with this authority’s admin token.", true);
    } else {
      session.interrupted = true;
      message(error.message || "The view could not be loaded. Reconnect to reload it.", true);
      shell();
    }
  }
  function clearEffect() { $("effect-text").value = ""; $("effect-fallback").hidden = true; }
  function disconnect() {
    const previousID = session.id, previousToken = session.token;
    session.generation++;
    for (const controller of pending) controller.abort();
    pending.clear(); dirty.clear(); disclosures.clear(); bindings.clear(); controls = [];
    Object.assign(session, { token: "", id: null, revision: null, busy: false, interrupted: false });
    $("admin-token").value = "";
    root.replaceChildren(); clearEffect(); message(""); shell();
    if (previousID && previousToken) {
      // Best-effort session disposal; secrets never enter a URL or storage.
      void fetch(`${endpoint}/${encodeURIComponent(previousID)}`, {
        method: "DELETE", credentials: "omit", cache: "no-store", redirect: "error", keepalive: true,
        headers: { Authorization: `Bearer ${previousToken}` },
      }).catch(() => {});
    }
  }
  async function connect(token) {
    if (session.busy || !token) return;
    disconnect();
    session.token = token; session.busy = true; shell();
    const generation = session.generation;
    try {
      const response = await request(endpoint, "POST", {});
      if (generation !== session.generation) return;
      renderResponse(response);
      // A new session does not execute effects without a user's action.
    } catch (error) { if (generation === session.generation) fail(error); }
    finally { if (generation === session.generation) { session.busy = false; shell(); } }
  }
  function callback(id) {
    if (typeof id !== "string" || !/^\d{1,19}$/.test(id)) throw new Error("Invalid Swift callback identifier.");
    return id;
  }
  function eventFor(id, kind, value) {
    return { id: callback(id), kind, ...(kind === "void" ? {} : { value: String(value) }) };
  }
  function collect(id, kind, value) { dirty.set(callback(id), eventFor(id, kind, value)); }
  async function submit(action) {
    if (!session.id || session.busy || session.interrupted) return;
    const events = [...dirty.values()];
    if (action) {
      const index = events.findIndex((item) => item.id === action.id);
      if (index !== -1) events.splice(index, 1);
      events.push(action);
    }
    if (!events.length) return;
    const generation = session.generation;
    const presentation = capturePresentation();
    session.busy = true; clearEffect(); message(""); shell();
    try {
      const response = await request(`${endpoint}/${encodeURIComponent(session.id)}/events`, "POST", { revision: session.revision, events });
      if (generation !== session.generation) return;
      for (const item of events) dirty.delete(item.id);
      renderResponse(response, presentation);
      await runEffects(response.effects || [], generation);
    } catch (error) { if (generation === session.generation) fail(error); }
    finally { if (generation === session.generation) { session.busy = false; shell(); } }
  }
  function number(value, fallback = 0) {
    const result = typeof value === "number" ? value : typeof value === "string" && /^-?\d+(\.\d+)?$/.test(value) ? Number(value) : NaN;
    return Number.isFinite(result) ? result : fallback;
  }
  function color(value) {
    // Keep both variants in CSS: a theme change must not need another request
    // or replace the Swift tree (which could disturb focus and pending input).
    if (Array.isArray(value)) {
      if (value.length !== 2 || value.some(Array.isArray)) throw new Error("Invalid adaptive Swift color.");
      return `light-dark(${color(value[0])}, ${color(value[1])})`;
    }
    const argb = number(value, NaN);
    if (!Number.isInteger(argb) || argb < 0 || argb > 0xffffffff) throw new Error("Invalid Swift color.");
    return `rgba(${(argb >>> 16) & 255}, ${(argb >>> 8) & 255}, ${argb & 255}, ${((argb >>> 24) & 255) / 255})`;
  }
  function fontFamily(value) {
    if (value === "Host Grotesk" || value === "HostGrotesk") return "var(--sans)";
    if (value === "JetBrains Mono" || value === "JetBrainsMono") return "var(--mono)";
    return "system-ui, sans-serif";
  }
  function fontWeightValue(value) {
    const weight = number(value, NaN);
    if (!Number.isFinite(weight) || weight < 1 || weight > 1000) throw new Error("Invalid Swift font weight.");
    return String(weight);
  }
  function textMetric(value, positive) {
    const metric = number(value, NaN);
    if (!Number.isFinite(metric) || (positive && metric <= 0)) throw new Error("Invalid Swift text metric.");
    return `${metric}px`;
  }
  const align = (value) => ({ leading: "flex-start", trailing: "flex-end", top: "flex-start", bottom: "flex-end", center: "center" }[value] || "center");
  function textContent(tree) {
    if (tree.type === "Text") return String(tree.props?.text || "");
    return (tree.children || []).map(textContent).join(" ");
  }
  function addControl(node, disabled) { controls.push({ node, disabled }); node.disabled = disabled || session.busy; }
  function render(tree, inheritedDisabled = false, parentType = "") {
    if (!tree || typeof tree.type !== "string" || typeof tree.id !== "string" || !Array.isArray(tree.children) || !Array.isArray(tree.modifiers)) throw new Error("The authority returned an invalid Swift view tree.");
    const p = tree.props || {}, modifiers = tree.modifiers;
    const disabled = inheritedDisabled || modifiers.some((item) => item.kind === "disabled" && item.args?.value === true);
    let node;
    switch (tree.type) {
      case "Text": node = element("span", "swift-text", p.text ?? ""); break;
      case "VStack": case "HStack": case "ZStack": {
        node = element("div", `swift-stack swift-${tree.type.toLowerCase()}`);
        node.style.gap = `${Math.max(0, number(p.spacing, 8))}px`;
        if (tree.type === "ZStack") { node.style.justifyItems = align(p.horizontal); node.style.alignItems = align(p.vertical); }
        else node.style.alignItems = align(p.alignment);
        node.append(...tree.children.map((child) => render(child, disabled, tree.type)));
        break;
      }
      case "Group": case "TupleView": case "ForEach": {
        node = element("div", "swift-group");
        node.append(...tree.children.map((child) => render(child, disabled, parentType))); break;
      }
      case "ScrollView": {
        node = element("div", "swift-scroll"); node.dataset.axis = p.axis === "horizontal" ? "horizontal" : "vertical";
        node.append(...tree.children.map((child) => render(child, disabled, tree.type))); break;
      }
      case "Spacer": node = element("div", "swift-spacer"); node.setAttribute("aria-hidden", "true"); break;
      case "Divider": node = element("hr", "swift-divider"); break;
      case "EmptyView": node = element("div"); node.hidden = true; break;
      case "Shape": case "Rectangle": case "Color": {
        node = element("div", tree.type === "Color" ? "swift-color" : "swift-shape");
        node.style.backgroundColor = p.fill !== undefined || p.color !== undefined ? color(p.fill ?? p.color) : "currentColor";
        if (["circle", "capsule"].includes(p.shape)) node.style.borderRadius = "9999px";
        else if (p.cornerRadius !== undefined) node.style.borderRadius = `${Math.max(0, number(p.cornerRadius))}px`;
        node.setAttribute("aria-hidden", "true"); break;
      }
      case "Button": {
        node = element("button", "swift-button"); node.type = "button";
        node.append(...tree.children.map((child) => render(child, disabled, tree.type)));
        if ([...node.children].some((child) => child.style.width === "100%")) node.style.width = "100%";
        const action = eventFor(p.onTap, "void");
        node.addEventListener("click", () => void submit(action)); addControl(node, disabled); break;
      }
      case "TextField": {
        node = element("input", "swift-textfield"); node.type = p.secure ? "password" : "text";
        node.autocomplete = "off"; node.spellcheck = false; node.placeholder = String(p.placeholder || "");
        node.setAttribute("aria-label", String(p.placeholder || "Text"));
        const id = callback(p.onChange);
        // Secure contents stay local and are never restored from a server tree.
        node.value = dirty.get(id)?.value ?? (p.secure ? "" : String(p.text ?? ""));
        node.addEventListener("input", () => collect(id, "string", node.value));
        node.addEventListener("change", () => collect(id, "string", node.value));
        node.addEventListener("keydown", (event) => {
          if (event.key === "Enter" && !event.isComposing) { event.preventDefault(); void submit(); }
        });
        node.addEventListener("focusout", (event) => {
          // The next action flushes the bindings itself. Do not disable that
          // control with a separate blur request before its click/change fires.
          if (event.relatedTarget?.closest("button, select, summary")) return;
          queueMicrotask(() => { if (!session.busy) void submit(); });
        });
        bindings.set(id, node); addControl(node, disabled); break;
      }
      case "Picker": {
        node = element("select", "swift-picker"); node.setAttribute("aria-label", String(p.title || "Selection"));
        for (const child of tree.children) {
          const tag = child.modifiers?.find((item) => item.kind === "tag")?.args?.value;
          if (tag === undefined) throw new Error("A Swift picker option has no selection tag.");
          const option = element("option", "", textContent(child)); option.value = String(tag); node.append(option);
        }
        node.value = String(p.selection ?? "");
        const id = callback(p.onChange);
        node.addEventListener("change", () => void submit(eventFor(id, "string", node.value)));
        bindings.set(id, node); addControl(node, disabled); break;
      }
      case "DisclosureGroup": {
        node = element("details", "swift-disclosure");
        const summary = element("summary"), body = element("div", "swift-disclosure-content");
        const count = Math.max(0, number(p.labelCount, 1));
        summary.append(...tree.children.slice(0, count).map((child) => render(child, disabled, tree.type)));
        body.append(...tree.children.slice(count).map((child) => render(child, disabled, tree.type)));
        node.append(summary, body);
        const open = typeof p.isExpanded === "boolean" ? p.isExpanded : disclosures.get(tree.id) || false;
        node.open = open;
        if (p.onToggle !== undefined) {
          const id = callback(p.onToggle);
          summary.addEventListener("click", (event) => { event.preventDefault(); if (!disabled) void submit(eventFor(id, "bool", !node.open)); });
        } else {
          node.addEventListener("toggle", () => { if (node.isConnected) disclosures.set(tree.id, node.open); });
        }
        break;
      }
      default: throw new Error("This content is unavailable. Reconnect to reload the view.");
    }
    node.classList.add("swift-node");
    node.dataset.swiftId = tree.id; node.dataset.swiftType = tree.type;
    return applyModifiers(node, modifiers, tree.id);
  }
  function applyModifiers(content, modifiers, id) {
    let outer = content;
    // Core emits outermost-first; constructing nested DOM wrappers starts at
    // the content and therefore walks from the innermost modifier outward.
    for (const modifier of [...modifiers].reverse()) {
      const a = modifier.args || {};
      let wrap;
      switch (modifier.kind) {
        case "padding":
          wrap = element("div", "swift-modifier");
          wrap.style.padding = `${number(a.top, 16)}px ${number(a.trailing, 16)}px ${number(a.bottom, 16)}px ${number(a.leading, 16)}px`;
          break;
        case "frame":
          wrap = element("div", "swift-modifier");
          for (const key of ["width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight"]) if (a[key] !== undefined) wrap.style[key] = `${Math.max(0, number(a[key]))}px`;
          if (a.fillWidth || a.maxWidth !== undefined) wrap.style.width = "100%";
          else if (a.width === undefined && ["Shape", "Color", "Rectangle"].includes(content.dataset.swiftType)) wrap.style.width = "100%";
          if ((a.fillWidth || a.width !== undefined || a.maxWidth !== undefined) && !outer.style.width) outer.style.width = "100%";
          if (a.fillHeight) { wrap.style.height = "100%"; wrap.style.flexGrow = "1"; }
          wrap.style.alignItems = align(a.horizontal); wrap.style.justifyContent = align(a.vertical);
          break;
        case "background": wrap = element("div", "swift-modifier"); wrap.style.backgroundColor = color(a.color); break;
        case "border": wrap = element("div", "swift-modifier"); wrap.style.border = `${Math.max(0, number(a.width, 1))}px solid ${color(a.color)}`; break;
        case "cornerRadius": wrap = element("div", "swift-modifier"); wrap.style.borderRadius = `${Math.max(0, number(a.radius))}px`; wrap.style.overflow = "hidden"; break;
        case "foregroundColor": outer.style.color = color(a.color); break;
        case "font":
          if (a.size !== undefined) outer.style.fontSize = `${Math.max(1, number(a.size, 16))}px`;
          else if (a.style) outer.style.fontSize = `${({ largeTitle: 34, title: 28, title2: 22, title3: 20, headline: 17, body: 16, callout: 16, subheadline: 15, footnote: 13, caption: 12, caption2: 11 })[a.style] || 16}px`;
          if (a.weightValue !== undefined) outer.style.fontWeight = fontWeightValue(a.weightValue);
          else if (a.weight) outer.style.fontWeight = fontWeight(a.weight);
          if (a.family !== undefined) outer.style.fontFamily = fontFamily(a.family);
          else if (a.design !== undefined) outer.style.fontFamily = a.design === "monospaced" ? "var(--mono)" : "var(--sans)";
          break;
        case "fontWeight": outer.style.fontWeight = fontWeight(a.weight); break;
        case "tracking": outer.style.letterSpacing = textMetric(a.value, false); break;
        case "lineHeight": outer.style.lineHeight = textMetric(a.value, true); break;
        case "italic": outer.style.fontStyle = "italic"; break;
        case "multilineTextAlignment": outer.style.textAlign = ({ leading: "left", trailing: "right", center: "center" })[a.value] || "left"; break;
        case "opacity": outer.style.opacity = String(Math.max(0, Math.min(1, number(a.opacity, 1)))); break;
        case "disabled": if (a.value) outer.dataset.disabled = "true"; break;
        case "accessibilityLabel": content.setAttribute("aria-label", String(a.text || "")); break;
        case "accessibilityValue": content.setAttribute("aria-description", String(a.text || "")); break;
        case "accessibilityHidden": if (a.value) outer.setAttribute("aria-hidden", "true"); break;
        case "accessibilityIdentifier": content.dataset.accessibilityId = String(a.id || ""); break;
        case "accessibilityAddTraits":
          if (Array.isArray(a.traits)) {
            if (a.traits.includes("header")) { content.setAttribute("role", "heading"); content.setAttribute("aria-level", "2"); }
            if (a.traits.includes("selected")) content.setAttribute("aria-current", "true");
          }
          break;
        case "buttonStyle":
          for (const button of [content, ...content.querySelectorAll("button")]) {
            if (button.tagName === "BUTTON" && (button === content || button.dataset.style === undefined)) {
              button.dataset.style = String(a.style || "");
            }
          }
          break;
        case "tag": break;
        default: throw new Error("This content is unavailable. Reconnect to reload the view.");
      }
      if (wrap) {
        if (modifier.kind !== "frame") {
          // Transparent wrappers carry the child's size proposal. Padding adds
          // its insets to a finite frame instead of losing that frame's limit.
          const horizontal = modifier.kind === "padding" ? number(a.leading, 16) + number(a.trailing, 16) : 0;
          if (outer.style.width === "100%") wrap.style.width = "100%";
          else if (outer.style.width?.endsWith("px")) wrap.style.width = `${parseFloat(outer.style.width) + horizontal}px`;
          if (outer.style.maxWidth?.endsWith("px")) wrap.style.maxWidth = `${parseFloat(outer.style.maxWidth) + horizontal}px`;
        }
        wrap.append(outer); outer = wrap;
      }
    }
    outer.dataset.swiftRootId = id;
    return outer;
  }
  function fontWeight(value) { return String(({ ultraLight: 200, thin: 200, light: 300, regular: 400, medium: 500, semibold: 600, bold: 700, heavy: 800, black: 900 })[value] || 400); }
  function capturePresentation() {
    const active = document.activeElement;
    return {
      focus: active?.dataset.swiftId,
      selection: active instanceof HTMLInputElement && active.type === "text" ? [active.selectionStart, active.selectionEnd] : null,
      x: window.scrollX, y: window.scrollY,
      offsets: new Map([...root.querySelectorAll(".swift-scroll")].map((node) => [node.dataset.swiftId, [node.scrollLeft, node.scrollTop]])),
    };
  }
  function renderResponse(response, presentation = capturePresentation()) {
    const validRevision = Number.isSafeInteger(response?.revision) && response.revision >= 0 || typeof response?.revision === "string" && /^\d+$/.test(response.revision);
    if (!response || typeof response.sessionID !== "string" || !response.sessionID || !validRevision) throw new Error("The authority returned an invalid UI session.");
    if (session.id && session.id !== response.sessionID) throw new Error("The authority returned a different UI session.");
    const previousControls = controls, previousBindings = bindings;
    controls = []; bindings = new Map();
    let tree;
    try { tree = render(response.tree); }
    catch (error) { controls = previousControls; bindings = previousBindings; throw error; }
    session.id = response.sessionID; session.revision = response.revision; session.interrupted = false;
    root.replaceChildren(tree);
    for (const id of dirty.keys()) if (!bindings.has(id)) dirty.delete(id);
    for (const node of root.querySelectorAll(".swift-scroll")) {
      const offset = presentation.offsets.get(node.dataset.swiftId); if (offset) { node.scrollLeft = offset[0]; node.scrollTop = offset[1]; }
    }
    const generation = session.generation, revision = session.revision;
    window.requestAnimationFrame(() => {
      if (generation !== session.generation || revision !== session.revision || !$("effect-fallback").hidden) return;
      if (presentation.focus) {
        const replacement = [...root.querySelectorAll("[data-swift-id]")].find((node) => node.dataset.swiftId === presentation.focus);
        if (replacement && !replacement.disabled) {
          replacement.focus({ preventScroll: true });
          if (presentation.selection && replacement.setSelectionRange) replacement.setSelectionRange(...presentation.selection);
        }
      }
      window.scrollTo({ left: presentation.x, top: presentation.y, behavior: "instant" });
    });
  }
  async function runEffects(effects, generation) {
    if (!Array.isArray(effects)) throw new Error("Invalid UI effects.");
    for (const effect of effects) {
      if (generation !== session.generation) return;
      if (typeof effect.text !== "string") throw new Error("Invalid UI effect text.");
      if (effect.kind === "copy") {
        try { await navigator.clipboard.writeText(effect.text); if (generation === session.generation) message("Copied."); }
        catch {
          if (generation !== session.generation) return;
          $("effect-text").value = effect.text; $("effect-fallback").hidden = false;
          $("effect-text").focus({ preventScroll: true }); $("effect-text").select();
          $("effect-fallback").scrollIntoView({ block: "center", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
        }
      } else if (effect.kind === "download") {
        const filename = typeof effect.filename === "string" ? effect.filename.replace(/[\x00-\x1f\x7f/\\]/g, "_").slice(0, 200) : "download.txt";
        const mediaType = typeof effect.mediaType === "string" && /^[\w.+-]+\/[\w.+-]+(?:;\s*charset=utf-8)?$/i.test(effect.mediaType) ? effect.mediaType : "text/plain;charset=utf-8";
        const url = URL.createObjectURL(new Blob([effect.text], { type: mediaType }));
        const link = element("a"); link.href = url; link.download = filename || "download.txt";
        document.body.append(link); link.click(); link.remove();
        window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      } else throw new Error("This action is unavailable. Reconnect to reload the view.");
    }
  }

  $("server-origin").textContent = window.location.origin;
  $("connect-form").addEventListener("submit", (event) => { event.preventDefault(); void connect($("admin-token").value.trim()); });
  $("disconnect-button").addEventListener("click", disconnect);
  $("reconnect-button").addEventListener("click", () => void connect(session.token));
  $("dismiss-effect-button").addEventListener("click", clearEffect);
  window.addEventListener("pagehide", disconnect);
  shell();
})();
