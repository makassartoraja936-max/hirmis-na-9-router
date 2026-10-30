const fs = require('fs');
const assert = require('assert');

const pkg = JSON.parse(fs.readFileSync(__dirname + '/package.json', 'utf8'));
assert.strictEqual(pkg.name, 'hermes-9router-agent');
assert.ok(pkg.dependencies.ws, 'ws dependency missing');
assert.ok(pkg.dependencies['9router'], '9router dependency missing');

const cfg = JSON.parse(fs.readFileSync(__dirname + '/config.json', 'utf8'));
assert.ok(cfg.hub_url, 'hub_url missing in config.json');
assert.strictEqual(cfg.router_port, 20128, 'router_port must be 20128');

console.log('✅ Task 1 Scaffolding test passed!');
