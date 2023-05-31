const WORKER_SCRIPT = String.raw`
// synchronously, using the browser, import wasm_bindgen shim JS scripts
import init, { wasm_thread_entry_point } from "WASM_BINDGEN_SHIM_URL";

// Wait for the main thread to send us the shared module/memory and work context.
// Once we've got it, initialize it all with the "wasm_bindgen" global we imported via
// "importScripts".
self.onmessage = event => {
    let [module, memory, f, args, futex_ptr] = event.data;

    init(module, memory).catch(err => {
        console.log(err);

        // Propagate to main "onerror":
        setTimeout(() => {
            throw err;
        });
        
        // Rethrow to keep promise rejected and prevent execution of further commands:
        throw err;
    }).then(() => {
        // Enter rust code by calling entry point defined in "lib.rs".
        // This executes closure defined by work context.
        wasm_thread_entry_point(f, args, futex_ptr);

        // Once done, terminate web worker
        close();
    });
};
`;

/**
 * @typedef Globals
 * @type {Object}
 * @property {WebAssembly.Instance} instance
 * @property {WebAssembly.Module} module
 * @property {WebAssembly.Memory} memory
 * @property {(number | null)} next_idx
 * @property {Array.<(Worker | number | null)>} workers
 */

/**
 * @type {Globals}
 */
let global;

/**
 * 
 * @param {(BufferSource | Uint8Array |  Response | Promise<Response>)} source 
 * @param {(WebAssembly.ModuleImports | undefined)} exports
 * @returns {WebAssembly.WebAssemblyInstantiatedSource}
 */
export async function load(source, exports = undefined) {
    const env = { spawn_worker, release_worker, ...exports };
    
    var wasm;
    if (source instanceof ArrayBuffer || source instanceof Uint8Array) {
        wasm = await WebAssembly.instantiate(source, { env })
    } else {
        wasm = await WebAssembly.instantiateStreaming(source, { env });
    }

    global = {
        instance: wasm.instance,
        module: wasm.module,
        memory: wasm.instance.exports.memory,
        next_idx: null,
        workers: []
    }
    return wasm
}

/**
 * 
 * @param {number} name_ptr 
 * @param {number} name_len 
 * @param {number} f 
 * @param {number} args 
 * @param {number} futex_ptr
 * @returns {number}
 */
function spawn_worker(name_ptr, name_len, f, args, futex_ptr) {
    try {
        const script = worker_script();
    
        load_module_workers_polyfill();
        const options = {
            name: name_ptr === 0 ? undefined : import_zig_string(name_ptr, name_len),
            type: "module"
        };
    
        const worker = new Worker(script, options);
        worker.postMessage([global.module, global.memory, f, args, futex_ptr]);
        
        /**
         * @type {number}
         */
        let worker_idx;
        if (global.next_idx === null) {
            worker_idx = global.workers.push(worker) - 1;
        } else {
            const tmp = global.next_idx;
            global.next_idx = global.workers[tmp];
            global.workers[tmp] = worker;
            worker_idx = tmp;
        }
    
        return worker_idx
    } catch (e) {
        console.error(e);
        throw e;
    }
}

/**
 * @param {number} idx 
 */
function release_worker (idx) {
    const worker = global.workers[idx];
    worker = global.next_idx;
    global.next_idx = idx;
    // worker.terminate();
}

/**
 * 
 * @type {(string | null)}
*/
let script_url = null;

/**
 * Returns a url to the worker's script URL
 * @returns {string}
 */
function worker_script() {
    if (script_url === null) {
        const script = script_path();
        const template = WORKER_SCRIPT.replace("WASM_BINDGEN_SHIM_URL", script);
        const blob = new Blob([template]);
        script_url = URL.createObjectURL(blob.slice(undefined, undefined, "text/javascript"));
    }
    return script_url
}

/// Extracts current script file path from artificially generated stack trace
function script_path() {
    try {
        throw new Error();
    } catch (e) {
        let parts = e.stack.match(/(?:\(|@)(\S+):\d+:\d+/);
        return parts[1];
    }
}

const TEXT_DECODER = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/**
 * 
 * @param {number} ptr Pointer to WASM memory
 * @param {number} len Length of the string (in bytes)
 * @returns {string}
 */
function import_zig_string(ptr, len) {
    const buf = new Uint8Array(global.memory.buffer).subarray(ptr, ptr + len);
    return TEXT_DECODER.decode(buf)
}

function load_module_workers_polyfill() {
    if (Worker._$P !== true) {
        let polyfill = "!function(e){if(!e||!0!==e._$P){if(e){var n,r=Object.defineProperty({},\"type\",{get:function(){n=!0}});try{var t=URL.createObjectURL(new Blob([\"\"],{type:\"text/javascript\"}));new e(t,r).terminate(),URL.revokeObjectURL(t)}catch(e){}if(!n)try{new e(\"data:text/javascript,\",r).terminate()}catch(e){}if(n)return;(self.Worker=function(n,r){return r&&\"module\"==r.type&&(r={name:n+\"\\n\"+(r.name||\"\")},n=\"undefined\"==typeof document?location.href:document.currentScript&&document.currentScript.src||(new Error).stack.match(/[(@]((file|https?):\\/\\/[^)]+?):\\d+(:\\d+)?(?:\\)|$)/m)[1]),new e(n,r)})._$P=!0}\"undefined\"==typeof document&&function(){var e={},n={};function r(e,n){for(n=n.replace(/^(\\.\\.\\/|\\.\\/)/,e.replace(/[^/]+$/g,\"\")+\"$1\");n!==(n=n.replace(/[^/]+\\/\\.\\.\\//g,\"\")););return n.replace(/\\.\\//g,\"\")}var t=[],s=t.push.bind(t);addEventListener(\"message\",s);var a=self.name.match(/^[^\\n]+/)[0];self.name=self.name.replace(/^[^\\n]*\\n/g,\"\"),function t(s,a){var u,o=s;return a&&(s=r(a,s)),e[s]||(e[s]=fetch(s).then((function(a){if((o=a.url)!==s){if(null!=e[o])return e[o];e[o]=e[s]}return a.text().then((function(e){if(!a.ok)throw e;var c={exports:{}};u=n[o]||(n[o]=c.exports);var i=function(e){return t(e,o)},f=[];return e=function(e,n){n=n||[];var r,t=[],a=0;function u(e,n){for(var s,a=/(?:^|,)\\s*([\\w$]+)(?:\\s+as\\s+([\\w$]+))?\\s*/g,u=[];s=a.exec(e);)n?t.push((s[2]||s[1])+\":\"+s[1]):u.push((s[2]||s[1])+\"=\"+r+\".\"+s[1]);return u}return(e=e.replace(/(^\\s*|[;}\\s\\n]\\s*)import\\s*(?:(?:([\\w$]+)(?:\\s*\\,\\s*\\{([^}]+)\\})?|(?:\\*\\s*as\\s+([\\w$]+))|\\{([^}]*)\\})\\s*from)?\\s*(['\"])(.+?)\\6/g,(function(e,t,s,o,c,i,f,p){return n.push(p),t+=\"var \"+(r=\"$im$\"+ ++a)+\"=$require(\"+f+p+f+\")\",s&&(t+=\";var \"+s+\" = 'default' in \"+r+\" ? \"+r+\".default : \"+r),c&&(t+=\";var \"+c+\" = \"+r),(o=o||i)&&(t+=\";var \"+u(o,!1)),t})).replace(/((?:^|[;}\\s\\n])\\s*)export\\s*(?:\\s+(default)\\s+|((?:async\\s+)?function\\s*\\*?|class|const\\s|let\\s|var\\s)\\s*([a-zA-Z0-9$_{[]+))/g,(function(e,n,r,s,u){if(r){var o=\"$im$\"+ ++a;return t.push(\"default:\"+o),n+\"var \"+o+\"=\"}return t.push(u+\":\"+u),n+s+\" \"+u})).replace(/((?:^|[;}\\s\\n])\\s*)export\\s*\\{([^}]+)\\}\\s*;?/g,(function(e,n,r){return u(r,!0),n})).replace(/((?:^|[^a-zA-Z0-9$_@`'\".])\\s*)(import\\s*\\([\\s\\S]+?\\))/g,\"$1$$$2\")).replace(/((?:^|[^a-zA-Z0-9$_@`'\".])\\s*)import\\.meta\\.url/g,\"$1\"+JSON.stringify(s))+\"\\n$module.exports={\"+t.join(\",\")+\"}\"}(e,f),Promise.all(f.map((function(e){var s=r(o,e);return s in n?n[s]:t(s)}))).then((function(n){e+=\"\\n//# sourceURL=\"+s;try{var r=new Function(\"$import\",\"$require\",\"$module\",\"$exports\",e)}catch(n){var t=n.line-1,a=n.column,o=e.split(\"\\n\"),p=(o[t-2]||\"\")+\"\\n\"+o[t-1]+\"\\n\"+(null==a?\"\":new Array(a).join(\"-\")+\"^\\n\")+(o[t]||\"\"),l=new Error(n.message+\"\\n\\n\"+p,s,t);throw l.sourceURL=l.fileName=s,l.line=t,l.column=a,l}var m=r(i,(function(e){return n[f.indexOf(e)]}),c,c.exports);return null!=m&&(c.exports=m),Object.assign(u,c.exports),c.exports}))}))})))}(a).then((function(){removeEventListener(\"message\",s),t.map(dispatchEvent)})).catch((function(e){setTimeout((function(){throw e}))}))}()}}(self.Worker);";
        let blob = new Blob([polyfill], { type: 'text/javascript' });
        let blobUrl = URL.createObjectURL(blob);
        !function (e) { if (!e || !0 !== e._$P) { if (e) { var n, r = Object.defineProperty({}, "type", { get: function () { n = !0 } }); try { var t = URL.createObjectURL(new Blob([""], { type: "text/javascript" })); new e(t, r).terminate(), URL.revokeObjectURL(t) } catch (e) { } if (!n) try { new e("data:text/javascript,", r).terminate() } catch (e) { } if (n) return; (self.Worker = function (n, r) { return r && "module" == r.type && (r = { name: n + "\n" + (r.name || "") }, n = blobUrl), new e(n, r) })._$P = !0 } "undefined" == typeof document && function () { var e = {}, n = {}; function r(e, n) { for (n = n.replace(/^(\.\.\/|\.\/)/, e.replace(/[^/]+$/g, "") + "$1"); n !== (n = n.replace(/[^/]+\/\.\.\//g, ""));); return n.replace(/\.\//g, "") } var t = [], s = t.push.bind(t); addEventListener("message", s); var a = self.name.match(/^[^\n]+/)[0]; self.name = self.name.replace(/^[^\n]*\n/g, ""), function t(s, a) { var u, o = s; return a && (s = r(a, s)), e[s] || (e[s] = fetch(s).then((function (a) { if ((o = a.url) !== s) { if (null != e[o]) return e[o]; e[o] = e[s] } return a.text().then((function (e) { if (!a.ok) throw e; var c = { exports: {} }; u = n[o] || (n[o] = c.exports); var i = function (e) { return t(e, o) }, f = []; return e = function (e, n) { n = n || []; var r, t = [], a = 0; function u(e, n) { for (var s, a = /(?:^|,)\s*([\w$]+)(?:\s+as\s+([\w$]+))?\s*/g, u = []; s = a.exec(e);)n ? t.push((s[2] || s[1]) + ":" + s[1]) : u.push((s[2] || s[1]) + "=" + r + "." + s[1]); return u } return (e = e.replace(/(^\s*|[;}\s\n]\s*)import\s*(?:(?:([\w$]+)(?:\s*\,\s*\{([^}]+)\})?|(?:\*\s*as\s+([\w$]+))|\{([^}]*)\})\s*from)?\s*(['"])(.+?)\6/g, (function (e, t, s, o, c, i, f, p) { return n.push(p), t += "var " + (r = "$im$" + ++a) + "=$require(" + f + p + f + ")", s && (t += ";var " + s + " = 'default' in " + r + " ? " + r + ".default : " + r), c && (t += ";var " + c + " = " + r), (o = o || i) && (t += ";var " + u(o, !1)), t })).replace(/((?:^|[;}\s\n])\s*)export\s*(?:\s+(default)\s+|((?:async\s+)?function\s*\*?|class|const\s|let\s|var\s)\s*([a-zA-Z0-9$_{[]+))/g, (function (e, n, r, s, u) { if (r) { var o = "$im$" + ++a; return t.push("default:" + o), n + "var " + o + "=" } return t.push(u + ":" + u), n + s + " " + u })).replace(/((?:^|[;}\s\n])\s*)export\s*\{([^}]+)\}\s*;?/g, (function (e, n, r) { return u(r, !0), n })).replace(/((?:^|[^a-zA-Z0-9$_@`'".])\s*)(import\s*\([\s\S]+?\))/g, "$1$$$2")).replace(/((?:^|[^a-zA-Z0-9$_@`'".])\s*)import\.meta\.url/g, "$1" + JSON.stringify(s)) + "\n$module.exports={" + t.join(",") + "}" }(e, f), Promise.all(f.map((function (e) { var s = r(o, e); return s in n ? n[s] : t(s) }))).then((function (n) { e += "\n//# sourceURL=" + s; try { var r = new Function("$import", "$require", "$module", "$exports", e) } catch (n) { var t = n.line - 1, a = n.column, o = e.split("\n"), p = (o[t - 2] || "") + "\n" + o[t - 1] + "\n" + (null == a ? "" : new Array(a).join("-") + "^\n") + (o[t] || ""), l = new Error(n.message + "\n\n" + p, s, t); throw l.sourceURL = l.fileName = s, l.line = t, l.column = a, l } var m = r(i, (function (e) { return n[f.indexOf(e)] }), c, c.exports); return null != m && (c.exports = m), Object.assign(u, c.exports), c.exports })) })) }))) }(a).then((function () { removeEventListener("message", s), t.map(dispatchEvent) })).catch((function (e) { setTimeout((function () { throw e })) })) }() } }(self.Worker);
    }
}
