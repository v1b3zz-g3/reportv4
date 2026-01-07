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

        console.log('[screenshot] Upload request received:', {
            hasWebhook: !!webhookUrl,
            hasThread: !!threadId,
            hasImage: !!base64Image,
            reportId,
            playerName,
            imageLength: base64Image?.length || 0
        });

        // Validate inputs
        if (!webhookUrl) {
            console.error('[screenshot] ERROR: Missing webhook URL');
            if (callback) callback(false, null, 'Missing webhook URL');
            return;
        }

        if (!base64Image) {
            console.error('[screenshot] ERROR: Missing image data');
            if (callback) callback(false, null, 'Missing image data');
            return;
        }

        if (!threadId) {
            console.error('[screenshot] ERROR: Missing threadId for report #' + reportId);
            console.error('[screenshot] Report thread must exist before uploading');
            if (callback) callback(false, null, 'Missing threadId - report thread must exist first');
            return;
        }

        try {
            // Parse image data
            let base64Data = base64Image;
            let contentType = 'image/png';
            let extension = 'png';

            // Handle data URI format
            if (base64Data.startsWith('data:')) {
                const matches = base64Data.match(/^data:(image\/\w+);base64,/);
                if (matches) {
                    contentType = matches[1];
                    extension = contentType.split('/')[1];
                    base64Data = base64Data.replace(/^data:image\/\w+;base64,/, '');
                }
            }

            console.log('[screenshot] Processing image:', {
                contentType,
                extension,
                dataLength: base64Data.length
            });

            // Convert base64 to buffer
            const imageBuffer = Buffer.from(base64Data, 'base64');
            
            if (imageBuffer.length === 0) {
                console.error('[screenshot] ERROR: Image buffer is empty after decoding');
                if (callback) callback(false, null, 'Invalid base64 data');
                return;
            }

            console.log('[screenshot] Buffer created:', imageBuffer.length, 'bytes');

            // Create multipart form data
            const boundary = '----WebKitFormBoundary' + Math.random().toString(36).substring(2);
            const safeName = sanitizeFilename(playerName || 'unknown');
            const filename = `screenshot_r${reportId}_${safeName}_${Date.now()}.${extension}`;

            console.log('[screenshot] Generated filename:', filename);

            // Build the payload
            const payload = {
                username: botName || 'Report System',
                embeds: [{
                    title: '📸 Screenshot Captured',
                    description: `Screenshot from player: **${playerName || 'Unknown'}**\nReport ID: #${reportId}`,
                    color: 3447003,
                    image: { url: `attachment://${filename}` },
                    timestamp: new Date().toISOString()
                }]
            };

            if (botAvatar) {
                payload.avatar_url = botAvatar;
            }

            // Construct multipart body
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

            console.log('[screenshot] Body created:', fullBody.length, 'bytes');

            // Parse webhook URL and add thread_id parameter
            const parsedUrl = new URL(webhookUrl);
            parsedUrl.searchParams.set('wait', 'true');
            parsedUrl.searchParams.set('thread_id', threadId);

            console.log('[screenshot] Uploading to:', parsedUrl.pathname);
            console.log('[screenshot] Thread ID:', threadId);

            const options = {
                hostname: parsedUrl.hostname,
                path: parsedUrl.pathname + parsedUrl.search,
                method: 'POST',
                headers: {
                    'Content-Type': `multipart/form-data; boundary=${boundary}`,
                    'Content-Length': fullBody.length
                },
                timeout: 30000 // 30 second timeout
            };

            const req = https.request(options, (res) => {
                let data = '';
                
                res.on('data', chunk => {
                    data += chunk;
                });

                res.on('end', () => {
                    console.log('[screenshot] Discord response status:', res.statusCode);

                    if (res.statusCode === 200 || res.statusCode === 204) {
                        try {
                            const response = JSON.parse(data);
                            const imageUrl = response.embeds?.[0]?.image?.url || 
                                           response.attachments?.[0]?.url || 
                                           null;
                            
                            if (imageUrl) {
                                console.log('[screenshot] Upload SUCCESS. URL:', imageUrl);
                                if (callback) callback(true, imageUrl, null);
                            } else {
                                console.error('[screenshot] Upload completed but no URL in response');
                                console.error('[screenshot] Response:', data.substring(0, 500));
                                if (callback) callback(false, null, 'No image URL in Discord response');
                            }
                        } catch (e) {
                            console.error('[screenshot] Failed to parse Discord response:', e.message);
                            console.error('[screenshot] Response data:', data.substring(0, 500));
                            if (callback) callback(false, null, 'Failed to parse Discord response');
                        }
                    } else {
                        console.error('[screenshot] Upload FAILED. Status:', res.statusCode);
                        console.error('[screenshot] Response:', data.substring(0, 1000));
                        
                        let errorMsg = `Discord returned status ${res.statusCode}`;
                        try {
                            const errorData = JSON.parse(data);
                            errorMsg = errorData.message || errorData.error || errorMsg;
                        } catch (e) {
                            // Use raw data if not JSON
                            if (data) errorMsg = data.substring(0, 200);
                        }
                        
                        if (callback) callback(false, null, errorMsg);
                    }
                });
            });

            req.on('error', (e) => {
                console.error('[screenshot] Request ERROR:', e.message);
                if (callback) callback(false, null, e.message);
            });

            req.on('timeout', () => {
                console.error('[screenshot] Request TIMEOUT after 30 seconds');
                req.destroy();
                if (callback) callback(false, null, 'Request timeout');
            });

            // Write the body
            req.write(fullBody);
            req.end();

            console.log('[screenshot] Request sent, waiting for response...');

        } catch (e) {
            console.error('[screenshot] Exception in uploadScreenshotToDiscord:', e.message);
            console.error('[screenshot] Stack:', e.stack);
            if (callback) callback(false, null, e.message);
        }
    }

    exports('uploadScreenshotToDiscord', uploadScreenshotToDiscord);
    
    console.log('[screenshot] Module loaded successfully');
})();