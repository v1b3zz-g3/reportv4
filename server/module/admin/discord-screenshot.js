;(function() {
    const https = require('https');
    const url = require('url');

    /**
     * Sanitize username for safe filename usage
     */
    function sanitizeFilename(name) {
        if (!name || typeof name !== 'string') return 'unknown';
        
        return name
            .toLowerCase()
            .replace(/[^a-z0-9_-]/g, '_')
            .replace(/_+/g, '_')
            .replace(/^[_-]+/, '')
            .replace(/[_-]+$/, '')
            .substring(0, 32) || 'user';
    }

    function uploadScreenshotToDiscord(params, callback) {
        const { webhookUrl, threadId, base64Image, playerName, reportId, botName, botAvatar } = params;

        console.log('[sws-report:screenshot] Upload request:', {
            hasWebhook: !!webhookUrl,
            hasThread: !!threadId,
            hasImage: !!base64Image,
            reportId,
            playerName,
            imageLength: base64Image?.length
        });

        if (!webhookUrl || !base64Image) {
            console.error('[sws-report:screenshot] Missing webhook or image data');
            callback(false, null, 'Missing webhook URL or image data');
            return;
        }

        if (!threadId) {
            console.error('[sws-report:screenshot] Missing threadId for report #' + reportId);
            callback(false, null, 'Missing threadId - report thread must exist first');
            return;
        }

        let base64Data = base64Image;
        let contentType = 'image/png';
        let extension = 'png';

        if (base64Data.startsWith('data:')) {
            const matches = base64Data.match(/^data:(image\/\w+);base64,/);
            if (matches) {
                contentType = matches[1];
                extension = contentType.split('/')[1];
                base64Data = base64Data.replace(/^data:image\/\w+;base64,/, '');
            }
        }

        console.log('[sws-report:screenshot] Image format:', contentType, 'length:', base64Data.length);

        const imageBuffer = Buffer.from(base64Data, 'base64');
        const boundary = '----WebKitFormBoundary' + Math.random().toString().substring(2, 15);
        
        // CRITICAL FIX: Sanitize player name for filename
        const safeName = sanitizeFilename(playerName || 'unknown');
        const filename = `screenshot_r${reportId}_${safeName}_${Date.now()}.${extension}`;

        console.log('[sws-report:screenshot] Generated filename:', filename);

        const payload = {
            username: botName || 'Report System',
            avatar_url: botAvatar || '',
            embeds: [{
                title: '📸 Screenshot Captured',
                description: `Screenshot from player: **${playerName || 'Unknown'}**\nReport ID: #${reportId}`,
                color: 3447003,
                image: { url: `attachment://${filename}` },
                timestamp: new Date().toISOString()
            }]
        };

        const bodyStart = Buffer.from(
            `--${boundary}\r\n` +
            `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
            `Content-Type: ${contentType}\r\n\r\n`
        );

        const bodyEnd = Buffer.from(
            `\r\n--${boundary}\r\n` +
            'Content-Disposition: form-data; name="payload_json"\r\n' +
            'Content-Type: application/json\r\n\r\n' +
            JSON.stringify(payload) + '\r\n' +
            `--${boundary}--\r\n`
        );

        const fullBody = Buffer.concat([bodyStart, imageBuffer, bodyEnd]);

        const parsedUrl = url.parse(`${webhookUrl}?wait=true&thread_id=${threadId}`);

        console.log('[sws-report:screenshot] Uploading to thread:', threadId);

        const options = {
            hostname: parsedUrl.hostname,
            path: parsedUrl.path,
            method: 'POST',
            headers: {
                'Content-Type': `multipart/form-data; boundary=${boundary}`,
                'Content-Length': fullBody.length
            }
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                console.log('[sws-report:screenshot] Discord response status:', res.statusCode);

                if (res.statusCode === 200) {
                    try {
                        const response = JSON.parse(data);
                        const imageUrl = response.embeds?.[0]?.image?.url
                                      || response.attachments?.[0]?.url
                                      || null;
                        console.log('[sws-report:screenshot] Upload successful, URL:', imageUrl);
                        callback(true, imageUrl, null);
                    } catch (e) {
                        console.error('[sws-report:screenshot] Failed to parse response:', e.message);
                        callback(false, null, 'Failed to parse Discord response');
                    }
                } else {
                    console.error('[sws-report:screenshot] Upload failed, response:', data);
                    callback(false, null, `Discord returned status ${res.statusCode}`);
                }
            });
        });

        req.on('error', (e) => {
            console.error('[sws-report:screenshot] Request error:', e.message);
            callback(false, null, e.message);
        });
        
        req.write(fullBody);
        req.end();
    }

    exports('uploadScreenshotToDiscord', uploadScreenshotToDiscord);
})();