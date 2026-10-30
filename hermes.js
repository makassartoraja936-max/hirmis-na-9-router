#!/usr/bin/env node
/**
 * Hermes Autonomous Agent & 9Router Bridge
 * ========================================
 * Lightweight, robust Node.js agent for Linux/VM instances.
 * Monitors system health and provides an autonomous execution engine
 * connected to local 9Router (port 20128) and remote Fleet Hub Dashboard.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

// Optional require ws with graceful fallback
let WebSocket;
try {
  WebSocket = require('ws');
} catch (e) {
  // Will be installed on npm install
  WebSocket = null;
}

const WORKSPACE_DIR = process.env.WORKSPACE || path.join(os.homedir(), 'workspace');
const AUTH_KEY_FILE = path.join(WORKSPACE_DIR, '.auth_key');
const VPS_NAME_FILE = path.join(WORKSPACE_DIR, '.vps_name');
const WORKER_ID_FILE = path.join(WORKSPACE_DIR, '.worker_id');
const CONFIG_FILE = path.join(__dirname, 'config.json');

// Load default config
let config = {
  hub_url: 'wss://hub.databaru.my.id',
  router_port: 20128,
  heartbeat_interval_sec: 15,
  reconnect_delay_sec: 5
};

if (fs.existsSync(CONFIG_FILE)) {
  try {
    config = Object.assign(config, JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8')));
  } catch (err) {
    console.error('[CONFIG] Warning: could not parse config.json, using defaults.');
  }
}

/**
 * Reads or generates a secure 32-character authentication token
 */
function getAuthKey() {
  if (process.env.AGENT_AUTH_KEY && process.env.AGENT_AUTH_KEY.trim()) {
    return process.env.AGENT_AUTH_KEY.trim();
  }

  if (fs.existsSync(AUTH_KEY_FILE)) {
    try {
      const content = fs.readFileSync(AUTH_KEY_FILE, 'utf8').trim();
      if (content) return content;
    } catch (e) {}
  }

  try {
    if (!fs.existsSync(WORKSPACE_DIR)) {
      fs.mkdirSync(WORKSPACE_DIR, { recursive: true });
    }
    const token = crypto.randomBytes(16).toString('hex');
    fs.writeFileSync(AUTH_KEY_FILE, token, { mode: 0o600 });
    return token;
  } catch (e) {
    return crypto.randomBytes(16).toString('hex');
  }
}

/**
 * Gets display name of the node
 */
function getVpsName() {
  if (fs.existsSync(VPS_NAME_FILE)) {
    try {
      const name = fs.readFileSync(VPS_NAME_FILE, 'utf8').trim();
      if (name) return name;
    } catch (e) {}
  }
  const wid = getWorkerId();
  return wid.replace(/^worker-/, '').toUpperCase();
}

/**
 * Gets or creates persistent unique identifier for this instance
 */
function getWorkerId() {
  if (fs.existsSync(WORKER_ID_FILE)) {
    try {
      const wid = fs.readFileSync(WORKER_ID_FILE, 'utf8').trim();
      if (wid) return wid;
    } catch (e) {}
  }

  const hostname = os.hostname().toLowerCase().replace(/[^a-z0-9_-]/g, '-');
  const wid = `worker-${hostname}`;
  try {
    if (!fs.existsSync(WORKSPACE_DIR)) {
      fs.mkdirSync(WORKSPACE_DIR, { recursive: true });
    }
    fs.writeFileSync(WORKER_ID_FILE, wid);
  } catch (e) {}
  return wid;
}

let prevCpuTotal = 0;
let prevCpuIdle = 0;

/**
 * Collects safe hardware & OS metrics (CPU %, Free RAM MB, Uptime sec)
 */
function getSystemMetrics() {
  let memFreeMb = Math.round(os.freemem() / (1024 * 1024));
  let cpuPct = 0.0;
  let uptimeSec = Math.floor(os.uptime());

  // Linux precise metrics from /proc
  try {
    if (fs.existsSync('/proc/meminfo')) {
      const meminfo = fs.readFileSync('/proc/meminfo', 'utf8');
      const match = meminfo.match(/MemAvailable:\s+(\d+)\s+kB/i) || meminfo.match(/MemFree:\s+(\d+)\s+kB/i);
      if (match) {
        memFreeMb = Math.round(parseInt(match[1], 10) / 1024);
      }
    }

    if (fs.existsSync('/proc/stat')) {
      const statLine = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
      const parts = statLine.split(/\s+/).slice(1).map(Number);
      if (parts.length >= 4) {
        const idle = parts[3];
        const total = parts.reduce((a, b) => a + b, 0);
        if (prevCpuTotal > 0) {
          const diffTotal = total - prevCpuTotal;
          const diffIdle = idle - prevCpuIdle;
          if (diffTotal > 0) {
            cpuPct = Math.max(0.0, Math.min(100.0, parseFloat(((1.0 - (diffIdle / diffTotal)) * 100.0).toFixed(1))));
          }
        }
        prevCpuTotal = total;
        prevCpuIdle = idle;
      }
    } else {
      const loads = os.loadavg();
      cpuPct = parseFloat(((loads[0] / os.cpus().length) * 100).toFixed(1)) || 0.0;
    }
  } catch (e) {
    // Fallback safely to Node.js os module
  }

  return {
    cpu_pct: cpuPct,
    mem_free_mb: memFreeMb,
    uptime: uptimeSec,
    node_version: process.version,
    platform: process.platform
  };
}

/**
 * Query local 9Router service (port 20128)
 */
async function queryRouter(prompt, baseUrl) {
  const endpoint = `${baseUrl || `http://127.0.0.1:${config.router_port}/v1`}/chat/completions`;
  const http = require(endpoint.startsWith('https') ? 'https' : 'http');
  const url = new URL(endpoint);

  const payload = JSON.stringify({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: prompt }]
  });

  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      },
      timeout: 30000
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          const reply = parsed.choices?.[0]?.message?.content || body;
          resolve(reply);
        } catch (e) {
          resolve(body);
        }
      });
    });

    req.on('error', err => reject(err));
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('9Router query timeout'));
    });

    req.write(payload);
    req.end();
  });
}

/**
 * Main WebSocket loop connecting to Central Fleet Hub
 */
async function connectHub() {
  if (!WebSocket) {
    console.error('[HERMES] WebSocket library not found. Run npm install.');
    return;
  }

  const hubUrl = config.hub_url;
  const workerId = getWorkerId();
  const vpsName = getVpsName();
  const authKey = getAuthKey();

  console.log(`[HERMES] Starting Hermes Agent: ${vpsName} [${workerId}]`);
  console.log(`[HERMES] Connecting to Hub Server: ${hubUrl}`);

  const ws = new WebSocket(hubUrl);
  let heartbeatTimer = null;

  ws.on('open', () => {
    console.log('[HERMES] Connected to Hub successfully!');

    // Send HELLO handshake
    const helloPayload = Object.assign({
      type: 'HELLO',
      agent_id: workerId,
      vps_name: vpsName,
      version: '1.0.0',
      auth_token: authKey,
      agent_type: 'hermes-9router'
    }, getSystemMetrics());

    ws.send(JSON.stringify(helloPayload));

    // Start periodic heartbeat
    heartbeatTimer = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        const hbPayload = Object.assign({
          type: 'HEARTBEAT',
          agent_id: workerId
        }, getSystemMetrics());
        ws.send(JSON.stringify(hbPayload));
      }
    }, config.heartbeat_interval_sec * 1000);
  });

  ws.on('message', async (data) => {
    try {
      const msg = JSON.parse(data.toString());
      const mtype = msg.type;

      if (mtype === 'PING') {
        ws.send(JSON.stringify({
          type: 'PONG',
          agent_id: workerId,
          sent_ts: msg.sent_ts || Date.now()
        }));
        return;
      }

      // Check authorization if token provided
      const reqAuth = msg.auth || msg.token || msg.key;
      if (reqAuth && reqAuth !== authKey) {
        console.warn(`[HERMES] Unauthorized instruction rejected: ${mtype}`);
        return;
      }

      if (mtype === 'RUN_PROMPT' || mtype === 'EXEC_TASK') {
        const prompt = msg.prompt || msg.task || msg.cmd || '';
        console.log(`[HERMES] Executing AI task via 9Router: ${prompt}`);
        try {
          const reply = await queryRouter(prompt);
          ws.send(JSON.stringify({
            type: 'TASK_DONE',
            agent_id: workerId,
            task: mtype,
            output: reply
          }));
        } catch (err) {
          ws.send(JSON.stringify({
            type: 'TASK_ERROR',
            agent_id: workerId,
            task: mtype,
            error: err.message
          }));
        }
      }
    } catch (err) {
      console.error('[HERMES] Error parsing incoming message:', err);
    }
  });

  ws.on('close', (code, reason) => {
    clearInterval(heartbeatTimer);
    console.warn(`[HERMES] Connection closed (${code}: ${reason}). Reconnecting in ${config.reconnect_delay_sec}s...`);
    setTimeout(connectHub, config.reconnect_delay_sec * 1000);
  });

  ws.on('error', (err) => {
    console.error(`[HERMES] WebSocket error: ${err.message}`);
  });
}

// Export for tests & modules
module.exports = {
  getSystemMetrics,
  getAuthKey,
  getVpsName,
  getWorkerId,
  queryRouter,
  connectHub
};

// Run directly if invoked as main script
if (require.main === module) {
  connectHub();
}
