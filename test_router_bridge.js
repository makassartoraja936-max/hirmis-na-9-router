const http = require('http');
const assert = require('assert');
const { queryRouter } = require('./hermes');

// Jalankan mock server 9router di port 20129
const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ choices: [{ message: { content: 'Hermes Task Completed' } }] }));
    });
});

server.listen(20129, async () => {
    try {
        const result = await queryRouter('Hello Hermes', 'http://127.0.0.1:20129/v1');
        assert.strictEqual(result, 'Hermes Task Completed');
        console.log('✅ Task 3 9Router Bridge test passed!');
    } catch (err) {
        console.error('❌ Task 3 Test failed:', err);
        process.exit(1);
    } finally {
        server.close();
    }
});
