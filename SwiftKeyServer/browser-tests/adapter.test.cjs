// Generic renderer regression tests; fake DOM and transport, no live authority calls.
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const assert = require('assert/strict');
class Node {
  constructor(tag) { this.tagName = tag.toUpperCase(); this.children = []; this.dataset = {}; this.style = {}; this.attributes = {}; this.listeners = {}; this.value = ''; this.hidden = false; this.disabled = false; this.className = ''; this.scrollLeft = 0; this.scrollTop = 0; this.classList = {add: value => { this.className += ' ' + value; }}; }
  set textContent(value) { this.text = String(value); this.children = []; }
  get textContent() { return (this.text || '') + this.children.map(x=>x.textContent).join(''); }
  append(...children) { for (const child of children) { child.parentElement = this; this.children.push(child); } }
  replaceChildren(...children) { for (const c of this.children) c.parentElement = null; this.children=[]; this.append(...children); }
  setAttribute(k,v) { this.attributes[k] = String(v); }
  getAttribute(k) { return this.attributes[k]; }
  addEventListener(k,v) { (this.listeners[k] ||= []).push(v); }
  dispatch(k,event={}) { for (const fn of this.listeners[k] || []) fn({preventDefault(){},...event}); }
  matches(s) { if(s.startsWith('.')) return this.className.split(' ').includes(s.slice(1)); if(s==='[data-swift-id]') return this.dataset.swiftId!==undefined; return this.tagName===s.toUpperCase(); }
  querySelectorAll(selector) { return this.children.flatMap(child => [...(child.matches(selector) ? [child] : []), ...child.querySelectorAll(selector)]); }
  closest(selectors) { return selectors.split(',').some(s=>this.matches(s.trim())) ? this : this.parentElement?.closest(selectors); }
  focus() { document.activeElement=this; }
  setSelectionRange(a,b) { this.selectionStart=a; this.selectionEnd=b; }
  select() { this.selectionStart=0; this.selectionEnd=this.value.length; }
  scrollIntoView() { this.scrolled=true; }
  get isConnected() { return this===document.body || Boolean(this.parentElement?.isConnected); }
  click() { this.dispatch('click'); }
  remove() { if(this.parentElement) this.parentElement.children=this.parentElement.children.filter(x=>x!==this); this.parentElement=null; }
}
class Input extends Node { constructor() { super('input'); } }
const document = {body:new Node('body'),activeElement:null,createElement:tag=>tag==='input'?new Input():new Node(tag)};
const ids = ['swift-root','notice','connection-panel','admin-token','connect-button','disconnect-button','reconnect-button','connection-status','effect-text','effect-fallback','server-origin','connect-form','dismiss-effect-button'];
const map = new Map(ids.map(id=>[id,id==='admin-token'?new Input():new Node('div')]));
document.getElementById=id=>map.get(id); for(const node of map.values()) document.body.append(node); document.activeElement=document.body;
let raf=[]; const window={location:{origin:'http://test.invalid'},scrollX:0,scrollY:42,requestAnimationFrame:fn=>raf.push(fn),scrollTo(){},matchMedia:()=>({matches:true}),setTimeout:fn=>fn(),addEventListener(){}};
const requests=[], responses=[], copies=[];
let clipboardFails=false;
const fetch=async (path, options)=>{requests.push({path,options}); if(options.method==='DELETE')return {status:204,ok:true}; const value=responses.shift(); if(!value)throw Error('Unexpected request'); return {status:value.status||200,ok:!value.status,json:async()=>value.data};};
const context={document,window,navigator:{clipboard:{writeText:async text=>{if(clipboardFails)throw Error('Denied');copies.push(text);}}},fetch,AbortController,DOMException,HTMLInputElement:Input,URL:{createObjectURL:()=> 'blob:test',revokeObjectURL(){}},Blob,queueMicrotask,console};
vm.createContext(context);
let source=fs.readFileSync(path.join(__dirname, '../Sources/SwiftKeyServer/Resources/app.js'),'utf8');
source=source.replace('  shell();\n})();','  shell();\n  globalThis.adapter={connect,collect,submit,disconnect,renderResponse,runEffects,session,render,color};\n})();');
vm.runInContext(source,context);
const api=context.adapter;
const change='9223372036854775806', tap='9223372036854775805';
const node=(type,id,props={},children=[],modifiers=[])=>({type,id,props,children,modifiers});
const tree=node('VStack','root',{alignment:'leading'},[
 node('Text','label',{text:'<img src=x onerror=alert(1)>'}),
 node('TextField','field',{text:'',placeholder:'Name',onChange:change}),
 node('Button','button',{onTap:tap},[node('Text','buttonlabel',{text:'Submit'})]),
 node('Shape','shape',{shape:'rectangle',fill:'4280297506'},[],[{kind:'frame',args:{width:32,height:4}}]),
 node('DisclosureGroup','details',{labelCount:'1'},[node('Text','summary',{text:'Details'}),node('Text','detail',{text:'Body'})]),
]);
const response=(revision=1)=>({sessionID:'test-session',revision,tree,effects:[]});
(async()=>{
 responses.push({data:{...response(),effects:[{kind:'copy',text:'should not copy on connect'}]}});
 await api.connect('never-print-this-test-secret');
 assert.equal(api.session.id,'test-session'); assert.equal(copies.length,0);
 assert.equal(map.get('swift-root').querySelectorAll('img').length,0);
 assert(map.get('swift-root').textContent.includes('<img src=x onerror=alert(1)>'));
 assert.equal(api.color('4280297506'),'rgba(32, 40, 34, 1)');
 const adaptive = [0xffa02ab8, 0xffd28fe2];
 const adaptiveCSS = 'light-dark(rgba(160, 42, 184, 1), rgba(210, 143, 226, 1))';
 assert.equal(api.color(adaptive), adaptiveCSS, 'retain both variants for CSS-driven OS theme changes');
 for (const invalid of [[], [0xffffffff], [0,0,0], [[0,0],0], [0,-1], [0,'invalid']]) {
   assert.throws(()=>api.color(invalid), /Invalid .*Swift color/);
 }
 const adaptiveText = api.render(node('Text','adaptiveText',{text:'Theme'},[],[{kind:'foregroundColor',args:{color:adaptive}}]));
 assert.equal(adaptiveText.style.color, adaptiveCSS);
 const adaptiveShape = api.render(node('Shape','adaptiveShape',{shape:'rectangle',fill:adaptive}));
 assert.equal(adaptiveShape.style.backgroundColor, adaptiveCSS);
 const adaptivePanel = api.render(node('Text','adaptivePanel',{text:'Panel'},[],[{kind:'border',args:{color:adaptive,width:1}},{kind:'background',args:{color:adaptive}}]));
 assert.equal(adaptivePanel.style.border, `1px solid ${adaptiveCSS}`);
 assert.equal(adaptivePanel.children[0].style.backgroundColor, adaptiveCSS);
 const heading = api.render(node('Text','heading',{text:'Shared typography'},[],[
   {kind:'font',args:{family:'Host Grotesk',size:32,weight:'semibold',weightValue:560}},
   {kind:'tracking',args:{value:-.5}}, {kind:'lineHeight',args:{value:48}},
 ]));
 assert.equal(heading.style.fontFamily,'var(--sans)');
 assert.equal(heading.style.fontWeight,'560', 'variable weight overrides named weight');
 assert.equal(heading.style.letterSpacing,'-0.5px');
 assert.equal(heading.style.lineHeight,'48px');
 const mono = api.render(node('Text','mono',{text:'Key'},[],[{kind:'font',args:{family:'JetBrains Mono',size:13}}]));
 assert.equal(mono.style.fontFamily,'var(--mono)');
 const standard = api.render(node('Text','standard',{text:'Default'},[],[{kind:'font',args:{design:'default'}}]));
 assert.equal(standard.style.fontFamily,'var(--sans)', 'explicit default must reset inherited monospaced font');
 const unknownFamily = api.render(node('Text','unknownFamily',{text:'Fallback'},[],[{kind:'font',args:{family:'Unbundled Typeface'}}]));
 assert.equal(unknownFamily.style.fontFamily,'system-ui, sans-serif');
 for (const weightValue of [0,1001,NaN,Infinity,'bold']) {
   assert.throws(()=>api.render(node('Text','invalidWeight',{},[],[{kind:'font',args:{weightValue}}])),/Invalid Swift font weight/);
 }
 for (const value of [0,-1,NaN,Infinity]) {
   assert.throws(()=>api.render(node('Text','invalidLeading',{},[],[{kind:'lineHeight',args:{value}}])),/Invalid Swift text metric/);
 }
 let input=map.get('swift-root').querySelectorAll('input')[0]; input.focus(); input.setSelectionRange(1,2);
 api.collect(change,'string','Hello'); responses.push({data:response(2)});
 await api.submit({id:tap,kind:'void'}); for(const fn of raf.splice(0))fn();
 const posted=JSON.parse(requests.at(-1).options.body);
 assert.deepEqual(posted,{revision:1,events:[{id:change,kind:'string',value:'Hello'},{id:tap,kind:'void'}]});
 assert(!requests.at(-1).options.body.includes('never-print'));
 assert.equal(document.activeElement.dataset.swiftId,'field');
 assert.equal(document.activeElement.selectionStart,1);
 const button=map.get('swift-root').querySelectorAll('button')[0];
 input=map.get('swift-root').querySelectorAll('input')[0]; input.value='Batch'; input.dispatch('input');
 const before=requests.length; input.dispatch('focusout',{relatedTarget:button}); await Promise.resolve();
 assert.equal(requests.length,before,'blur to an action must not race its click');
 responses.push({data:response(3)}); await api.submit({id:tap,kind:'void'});
 assert.equal(JSON.parse(requests.at(-1).options.body).events[0].value,'Batch');
 input=map.get('swift-root').querySelectorAll('input')[0]; input.value='Blur'; input.dispatch('input');
 responses.push({data:response(4)}); input.dispatch('focusout',{relatedTarget:document.body});
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(JSON.parse(requests.at(-1).options.body).events.length,1);
 const label=api.render(node('Text','styled',{text:'Refresh'},[],[{kind:'background',args:{color:'4279717174'}},{kind:'padding',args:{top:12,leading:12,bottom:12,trailing:12}},{kind:'font',args:{size:14}}]));
 assert(label.style.backgroundColor,'background must wrap the padded label');
 assert.equal(label.children[0].style.padding,'12px 12px 12px 12px');
 assert.equal(label.children[0].children[0].style.fontSize,'14px');
 const layout=api.render(node('VStack','layout',{alignment:'leading'},[],[{kind:'frame',args:{fillWidth:true}},{kind:'padding',args:{top:32,leading:24,bottom:48,trailing:24}},{kind:'frame',args:{maxWidth:960,horizontal:'leading'}}]));
 assert.equal(layout.style.width,'100%');
 assert.equal(layout.children[0].style.maxWidth,'1008px');
 assert.equal(layout.children[0].children[0].style.maxWidth,'960px');
 assert.equal(layout.children[0].children[0].children[0].style.width,'100%');
 const custom=api.render(node('Button','custom',{onTap:tap},[node('Text','customLabel',{text:'Go'},[],[{kind:'background',args:{color:'4279717174'}},{kind:'padding',args:{top:12,leading:12,bottom:12,trailing:12}}])]));
 assert.equal(custom.dataset.customLabel,undefined,'custom label shape must not remove requested button chrome');
 const customLabel = node('HStack','buttonStack',{},[node('Text','buttonTitle',{text:'Confirm'})]);
 const prominent = api.render(node('Button','prominent',{onTap:tap},[customLabel],[{kind:'buttonStyle',args:{style:'borderedProminent'}}]));
 assert.equal(prominent.dataset.style,'borderedProminent');
 assert.equal(prominent.dataset.customLabel,undefined);
 const plain = api.render(node('Button','plain',{onTap:tap},[customLabel],[{kind:'buttonStyle',args:{style:'plain'}}]));
 assert.equal(plain.dataset.style,'plain');
 const inheritedStyle = api.render(node('VStack','styledButtons',{},[node('Button','childButton',{onTap:tap},[customLabel])],[{kind:'buttonStyle',args:{style:'bordered'}}]));
 assert.equal(inheritedStyle.querySelectorAll('button')[0].dataset.style,'bordered');
 const explicitChildStyle = api.render(node('VStack','styleScope',{},[
   node('Button','plainChild',{onTap:tap},[customLabel],[{kind:'buttonStyle',args:{style:'plain'}}]),
 ],[{kind:'buttonStyle',args:{style:'borderedProminent'}}]));
 assert.equal(explicitChildStyle.querySelectorAll('button')[0].dataset.style,'plain','child explicit style overrides inherited chrome');
 const secure=api.render(node('TextField','secure',{text:'must-not-echo',secure:true,onChange:'11'})); assert.equal(secure.value,'');
 assert.throws(()=>api.render(node('Unimplemented','bad')),/Unsupported Swift view primitive/);
 clipboardFails=true; await api.runEffects([{kind:'copy',text:'full public output'}],api.session.generation);
 assert.equal(map.get('effect-text').value,'full public output'); assert.equal(map.get('effect-fallback').hidden,false);
 responses.push({status:409,data:{code:'staleRevision',error:'Stale revision'}}); await api.submit({id:tap,kind:'void'});
 const after=requests.length; await api.submit({id:tap,kind:'void'}); assert.equal(requests.length,after,'failed action must not be retried');
 assert.equal(api.session.interrupted,true);
 api.disconnect(); assert.equal(api.session.token,''); assert.equal(map.get('effect-text').value,''); assert.equal(map.get('swift-root').children.length,0);
 assert.equal(requests.at(-1).options.method,'DELETE');
 assert(requests.every(r=>!r.path.includes('never-print')));
 console.log('PASS: exact 63-bit callbacks, dirty-input batching, blur/action ordering, focus, escaping, static/adaptive colors, named/variable fonts, tracking/leading, secure fields, effect fallback, stale-response blocking and disconnect cleanup.');
})().catch(error=>{console.error(error);process.exitCode=1;});
