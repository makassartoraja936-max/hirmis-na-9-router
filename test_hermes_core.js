const assert = require('assert');
const { getSystemMetrics, getAuthKey } = require('./hermes');

const metrics = getSystemMetrics();
assert.ok(typeof metrics.cpu_pct === 'number', 'cpu_pct must be number');
assert.ok(typeof metrics.mem_free_mb === 'number', 'mem_free_mb must be number');
assert.ok(typeof metrics.uptime === 'number', 'uptime must be number');

const key = getAuthKey();
assert.ok(typeof key === 'string' && key.length >= 16, 'auth_key must be valid hex token');

console.log('✅ Task 2 Core Hermes test passed! Metrics:', metrics);
